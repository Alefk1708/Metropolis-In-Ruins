extends Node

## Camada única de transporte para LAN (ENet) e Online (Photon Fusion).
##
## O jogo antigo usa o MultiplayerAPI do Godot. No modo Photon não existe um
## MultiplayerPeer compatível com esses RPCs, então esta camada encapsula as
## chamadas e as entrega por um único broadcast receiver persistente.

signal jogador_desconectado(jogador_id: int, inativo: bool)
signal jogador_reconectado(id_antigo: int, id_novo: int, user_id: String)
signal host_alterado(eh_host: bool)
signal sessao_sincronizada(fase: String)
signal snapshot_aplicado()
signal erro_transporte(mensagem: String)
signal solicitacao_pausa_partida_recebida(peer_id: int, deseja_pausar: bool)
signal solicitacao_desistencia_partida_recebida(peer_id: int)
signal estado_pausa_partida_recebido(
	ativo: bool,
	peer_iniciador: int,
	personagem_iniciador: String,
	nome_iniciador: String
)
signal resultado_desistencia_partida_recebido(
	token: String,
	jogador_desistente: String,
	vencedor: String
)
signal confirmacao_vitoria_desistencia_recebida(
	token: String,
	peer_confirmando: int,
	vencedor: String
)

const CENA_ONLINE := "res://scenes/ui/online/online_menu.tscn"
const CENA_SELECAO := "res://scenes/ui/selecao_personagem/selecao_personagem.tscn"
const CENA_TABULEIRO := "res://scenes/gameplay/tabuleiro/tabuleiro.tscn"
const TEMPO_FILA_RPC_MS := 8000
const LIMITE_PACOTES_VISTOS := 1024
const TAMANHO_PARTE_SNAPSHOT := 7000
const TEMPO_TRANSFERENCIA_SNAPSHOT_MS := 20000
const MAX_PARTES_SNAPSHOT := 256
const REENVIOS_ESTADO_PAUSA_PHOTON := 3
const TEMPO_MAXIMO_ACK_PAUSA_MS := 1200
const INTERVALO_REENVIO_PAUSA := 0.20

var _fusion: Object = null
var _registrado_no_fusion: bool = false
var _sequencia_local: int = 0
var _remetente_rpc_atual: int = 0
var _pacotes_vistos: Dictionary = {}
var _ordem_pacotes_vistos: Array[String] = []
var _fila_rpc: Array[Dictionary] = []
var _snapshot_pendente: Dictionary = {}
var _transferencias_snapshot: Dictionary = {}
var _sequencia_snapshot: int = 0
var _sincronizando_cena: bool = false
var _revisao_estado_pausa_partida: int = 0
var _estado_pausa_partida: Dictionary = {
	"ativo": false,
	"peer_iniciador": 0,
	"personagem_iniciador": "",
	"nome_iniciador": "",
}
var _acks_estado_pausa: Dictionary = {}
var _destinos_estado_pausa: Array[int] = []
var _token_resultado_desistencia_atual: String = ""
var _sequencia_resultado_desistencia: int = 0
var _resultado_desistencia_pendente: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_conectar_sinais()
	_obter_fusion()
	_registrar_receiver()


func _process(_delta: float) -> void:
	_processar_fila_rpc()
	_tentar_aplicar_snapshot_pendente()
	_limpar_transferencias_snapshot_expiradas()


func _conectar_sinais() -> void:
	if not PhotonManager.sala_entrada.is_connected(_ao_entrar_sala_photon):
		PhotonManager.sala_entrada.connect(_ao_entrar_sala_photon)
	if not PhotonManager.jogador_saiu.is_connected(_ao_jogador_sair_photon):
		PhotonManager.jogador_saiu.connect(_ao_jogador_sair_photon)
	if not PhotonManager.host_alterado.is_connected(_ao_host_alterado_photon):
		PhotonManager.host_alterado.connect(_ao_host_alterado_photon)
	if PhotonManager.has_signal("jogador_descoberto"):
		var cb := Callable(self, "_ao_jogador_descoberto")
		if not PhotonManager.is_connected("jogador_descoberto", cb):
			PhotonManager.connect("jogador_descoberto", cb)
	if PhotonManager.has_signal("jogador_reconectado"):
		var cb_reconexao := Callable(self, "_ao_jogador_reconectado")
		if not PhotonManager.is_connected("jogador_reconectado", cb_reconexao):
			PhotonManager.connect("jogador_reconectado", cb_reconexao)
	if not NetworkManager.jogador_desconectado.is_connected(_ao_jogador_sair_lan):
		NetworkManager.jogador_desconectado.connect(_ao_jogador_sair_lan)


func _obter_fusion() -> void:
	if Engine.has_singleton("Fusion"):
		_fusion = Engine.get_singleton("Fusion")
	else:
		_fusion = get_node_or_null("/root/Fusion")
	if _fusion is Node:
		(_fusion as Node).process_mode = Node.PROCESS_MODE_ALWAYS


func _registrar_receiver() -> void:
	_obter_fusion()
	if _fusion == null or _registrado_no_fusion:
		return
	if not _fusion.has_method(&"register_broadcast_receiver"):
		return
	_fusion.call(&"register_broadcast_receiver", self)
	_registrado_no_fusion = true


func usando_photon() -> bool:
	return PhotonManager.esta_em_sala()


func usando_lan() -> bool:
	return NetworkManager.esta_em_sala()


func esta_em_sala() -> bool:
	return usando_photon() or usando_lan()


func is_host() -> bool:
	if usando_photon():
		return PhotonManager.eh_host
	if usando_lan():
		return multiplayer.is_server()
	return true


func local_player_id() -> int:
	if usando_photon():
		return PhotonManager.jogador_local_id
	if usando_lan():
		return multiplayer.get_unique_id()
	return 1


func get_peer_ids(incluir_inativos: bool = false) -> Array[int]:
	var resultado: Array[int] = []
	if usando_photon():
		for dados_variant in PhotonManager.obter_jogadores_sala():
			var dados: Dictionary = dados_variant
			var id := int(dados.get("id", 0))
			if id <= 0 or id == local_player_id():
				continue
			if not incluir_inativos and bool(dados.get("inativo", false)):
				continue
			resultado.append(id)
		return resultado
	if usando_lan():
		for id_variant in multiplayer.get_peers():
			resultado.append(int(id_variant))
	return resultado


func _obter_destinos_estado_pausa_photon() -> Array[int]:
	var destinos: Array[int] = []
	var id_local: int = local_player_id()

	# Fonte principal: jogadores conhecidos pelo transporte atual.
	for id_variant in get_peer_ids(true):
		var peer_sala: int = int(id_variant)
		if peer_sala > 0 and peer_sala != id_local and not destinos.has(peer_sala):
			destinos.append(peer_sala)

	# Fallback: jogadores que já escolheram personagem/entraram na mesa.
	# Isso cobre alguns frames em que a lista do Photon ainda não foi atualizada.
	for chave_variant in Global.escolhas_da_mesa.keys():
		var peer_escolha: int = int(chave_variant)
		if (
			peer_escolha > 0
			and peer_escolha != id_local
			and not destinos.has(peer_escolha)
		):
			destinos.append(peer_escolha)

	# Segundo fallback: lista bruta informada pelo PhotonManager.
	for dados_variant in PhotonManager.obter_jogadores_sala():
		if not dados_variant is Dictionary:
			continue
		var dados_jogador: Dictionary = dados_variant
		var peer_lista: int = int(dados_jogador.get("id", 0))
		if peer_lista > 0 and peer_lista != id_local and not destinos.has(peer_lista):
			destinos.append(peer_lista)

	return destinos


func total_jogadores() -> int:
	if usando_photon():
		var total := 0
		for dados_variant in PhotonManager.obter_jogadores_sala():
			var dados: Dictionary = dados_variant
			if not bool(dados.get("inativo", false)):
				total += 1
		return total
	if usando_lan():
		return multiplayer.get_peers().size() + 1
	return 1


func get_remote_sender_id() -> int:
	if usando_photon():
		return _remetente_rpc_atual
	return multiplayer.get_remote_sender_id()


func host_player_id() -> int:
	if usando_photon():
		for dados_variant in PhotonManager.obter_jogadores_sala():
			var dados: Dictionary = dados_variant
			if bool(dados.get("host", false)):
				return int(dados.get("id", 0))
		if PhotonManager.eh_host:
			return PhotonManager.jogador_local_id
		return 0
	return 1


## Envia para todos. `exigir_host` protege notificações que só podem ser
## originadas pelo coordenador da sala. `executar_local` preserva call_local.
func send_all(
	alvo: Object,
	metodo: StringName,
	argumentos: Array = [],
	exigir_host: bool = false,
	executar_local: bool = true
) -> bool:
	if alvo == null:
		return false
	if usando_photon():
		return _enviar_photon("all", 0, alvo, metodo, argumentos, exigir_host, executar_local)
	if usando_lan() and alvo is Node:
		var chamada: Array = [metodo]
		chamada.append_array(argumentos)
		alvo.callv(&"rpc", chamada)
		return true
	if executar_local and alvo.has_method(metodo):
		alvo.callv(metodo, argumentos)
		return true
	return false


## Envia uma solicitação ao host/Master Client.
func send_host(
	alvo: Object,
	metodo: StringName,
	argumentos: Array = [],
	executar_local_se_host: bool = false
) -> bool:
	if alvo == null:
		return false
	if usando_photon():
		var destino := host_player_id()
		if destino <= 0:
			_emitir_erro("Não foi possível identificar o host da sala Photon.")
			return false
		return _enviar_photon(
			"player", destino, alvo, metodo, argumentos, false, executar_local_se_host
		)
	if usando_lan() and alvo is Node:
		if multiplayer.is_server() and executar_local_se_host:
			alvo.callv(metodo, argumentos)
			return true
		var chamada: Array = [1, metodo]
		chamada.append_array(argumentos)
		alvo.callv(&"rpc_id", chamada)
		return true
	if executar_local_se_host and alvo.has_method(metodo):
		alvo.callv(metodo, argumentos)
		return true
	return false


func send_player(
	jogador_id: int,
	alvo: Object,
	metodo: StringName,
	argumentos: Array = [],
	executar_local_se_destino: bool = false,
	exigir_host: bool = false
) -> bool:
	if jogador_id <= 0 or alvo == null:
		return false
	if usando_photon():
		return _enviar_photon(
			"player",
			jogador_id,
			alvo,
			metodo,
			argumentos,
			exigir_host,
			executar_local_se_destino
		)
	if usando_lan() and alvo is Node:
		if jogador_id == multiplayer.get_unique_id() and executar_local_se_destino:
			alvo.callv(metodo, argumentos)
			return true
		var chamada: Array = [jogador_id, metodo]
		chamada.append_array(argumentos)
		alvo.callv(&"rpc_id", chamada)
		return true
	if jogador_id == local_player_id() and executar_local_se_destino and alvo.has_method(metodo):
		alvo.callv(metodo, argumentos)
		return true
	return false


func solicitar_estado_pausa_partida_ao_host(deseja_pausar: bool) -> bool:
	if not usando_photon():
		return false
	if is_host():
		solicitacao_pausa_partida_recebida.emit(local_player_id(), deseja_pausar)
		return true
	return send_host(
		self,
		&"_receber_solicitacao_estado_pausa_partida",
		[local_player_id(), deseja_pausar],
		false
	)


func publicar_estado_pausa_partida(
	ativo: bool,
	peer_iniciador: int,
	personagem_iniciador: String,
	nome_iniciador: String
) -> bool:
	if not usando_photon() or not is_host():
		return false

	_revisao_estado_pausa_partida += 1
	var revisao: int = _revisao_estado_pausa_partida
	var argumentos: Array = [
		revisao,
		ativo,
		peer_iniciador,
		personagem_iniciador,
		nome_iniciador,
	]
	print(
		"[PAUSA PHOTON] Broadcast revisão %d ativo=%s iniciador=%d"
		% [revisao, ativo, peer_iniciador]
	)

	# Não aguardamos ACK antes de aplicar a pausa. A pausa de rede é lógica e
	# nunca congela o SceneTree, então o Fusion continua recebendo heartbeats.
	# Broadcast evita depender de IDs de rpc_to_player que podem mudar na sala.
	var enviado := send_all(
		self,
		&"_receber_estado_pausa_partida",
		argumentos,
		true,
		false
	)
	_receber_estado_pausa_partida(
		revisao,
		ativo,
		peer_iniciador,
		personagem_iniciador,
		nome_iniciador,
		true
	)
	call_deferred(
		"_reenviar_estado_pausa_broadcast",
		revisao,
		argumentos.duplicate(true)
	)
	return enviado


func _reenviar_estado_pausa_broadcast(revisao: int, argumentos: Array) -> void:
	for tentativa in range(2):
		await get_tree().create_timer(0.22 + float(tentativa) * 0.24).timeout
		if revisao != _revisao_estado_pausa_partida:
			return
		if not usando_photon() or not is_host():
			return
		send_all(
			self,
			&"_receber_estado_pausa_partida",
			argumentos,
			true,
			false
		)


func obter_estado_pausa_partida() -> Dictionary:
	return _estado_pausa_partida.duplicate(true)


func _receber_solicitacao_estado_pausa_partida(
	peer_declarado: int,
	deseja_pausar: bool
) -> void:
	if not usando_photon() or not is_host():
		return
	var peer_remetente: int = get_remote_sender_id()
	if peer_remetente <= 0:
		peer_remetente = peer_declarado
	if peer_remetente <= 0:
		return
	solicitacao_pausa_partida_recebida.emit(peer_remetente, deseja_pausar)


func solicitar_desistencia_partida_ao_host() -> bool:
	if not usando_photon():
		return false
	if is_host():
		solicitacao_desistencia_partida_recebida.emit(local_player_id())
		return true
	return send_host(
		self,
		&"_receber_solicitacao_desistencia_partida",
		[local_player_id()],
		false
	)


func _receber_solicitacao_desistencia_partida(peer_declarado: int) -> void:
	if not usando_photon() or not is_host():
		return
	var peer_remetente: int = get_remote_sender_id()
	if peer_remetente <= 0:
		peer_remetente = peer_declarado
	if peer_remetente <= 0:
		return
	solicitacao_desistencia_partida_recebida.emit(peer_remetente)


func _receber_estado_pausa_partida(
	revisao: int,
	ativo: bool,
	peer_iniciador: int,
	personagem_iniciador: String,
	nome_iniciador: String,
	aplicacao_local_host: bool = false
) -> void:
	var remetente: int = get_remote_sender_id()
	var host_conhecido: int = host_player_id()
	if (
		not aplicacao_local_host
		and remetente > 0
		and host_conhecido > 0
		and remetente != host_conhecido
	):
		return
	if revisao < _revisao_estado_pausa_partida:
		return
	if revisao == _revisao_estado_pausa_partida:
		var ativo_atual := bool(_estado_pausa_partida.get("ativo", false))
		var peer_atual := int(_estado_pausa_partida.get("peer_iniciador", 0))
		if ativo_atual == ativo and (not ativo or peer_atual == peer_iniciador):
			return
	_revisao_estado_pausa_partida = revisao
	print(
		"[PAUSA PHOTON] Recebida revisão %d ativo=%s host_local=%s remetente=%d"
		% [revisao, ativo, aplicacao_local_host, remetente]
	)
	_estado_pausa_partida = {
		"ativo": ativo,
		"peer_iniciador": peer_iniciador if ativo else 0,
		"personagem_iniciador": personagem_iniciador if ativo else "",
		"nome_iniciador": nome_iniciador if ativo else "",
	}
	estado_pausa_partida_recebido.emit(
		ativo,
		peer_iniciador,
		personagem_iniciador,
		nome_iniciador
	)


func publicar_resultado_desistencia_partida(
	jogador_desistente: String,
	vencedor: String
) -> String:
	if not usando_photon() or not is_host():
		return ""
	_sequencia_resultado_desistencia += 1
	var token := "%d:%d:%d" % [
		local_player_id(),
		Time.get_ticks_msec(),
		_sequencia_resultado_desistencia,
	]
	_token_resultado_desistencia_atual = token
	var argumentos: Array = [token, jogador_desistente, vencedor]
	print(
		"[DESISTÊNCIA PHOTON] Broadcast token=%s desistente=%s vencedor=%s"
		% [token, jogador_desistente, vencedor]
	)

	# Resultado terminal vai por broadcast e também por reenvios. Isso evita a
	# dependência exclusiva de rpc_to_player e continua válido após migração.
	send_all(
		self,
		&"_receber_resultado_desistencia_partida",
		argumentos,
		true,
		false
	)
	_receber_resultado_desistencia_partida(
		token,
		jogador_desistente,
		vencedor,
		true
	)
	call_deferred(
		"_reenviar_resultado_desistencia_partida",
		token,
		argumentos.duplicate(true)
	)
	return token


func _reenviar_resultado_desistencia_partida(token: String, argumentos: Array) -> void:
	for tentativa in range(4):
		await get_tree().create_timer(0.25 + float(tentativa) * 0.30).timeout
		if token != _token_resultado_desistencia_atual:
			return
		if not usando_photon() or not is_host():
			return
		send_all(
			self,
			&"_receber_resultado_desistencia_partida",
			argumentos,
			true,
			false
		)
		for peer_id in _obter_destinos_estado_pausa_photon():
			send_player(
				peer_id,
				self,
				&"_receber_resultado_desistencia_partida",
				argumentos,
				false,
				true
			)


func _receber_resultado_desistencia_partida(
	token: String,
	jogador_desistente: String,
	vencedor: String,
	aplicacao_local_host: bool = false
) -> void:
	if token.is_empty():
		return
	var remetente: int = get_remote_sender_id()
	var host_conhecido: int = host_player_id()
	var host_origem_token: int = int(token.get_slice(":", 0))
	if (
		not aplicacao_local_host
		and remetente > 0
		and host_conhecido > 0
		and remetente != host_conhecido
		and remetente != host_origem_token
	):
		return
	_resultado_desistencia_pendente = {
		"token": token,
		"jogador_desistente": jogador_desistente,
		"vencedor": vencedor,
	}
	print(
		"[DESISTÊNCIA PHOTON] Resultado recebido token=%s desistente=%s vencedor=%s"
		% [token, jogador_desistente, vencedor]
	)
	resultado_desistencia_partida_recebido.emit(
		token,
		jogador_desistente,
		vencedor
	)


func obter_resultado_desistencia_pendente() -> Dictionary:
	return _resultado_desistencia_pendente.duplicate(true)


func limpar_resultado_desistencia_pendente(token: String) -> void:
	if token.is_empty():
		return
	if str(_resultado_desistencia_pendente.get("token", "")) == token:
		_resultado_desistencia_pendente.clear()


func confirmar_vitoria_desistencia_ao_host(
	token: String,
	vencedor: String
) -> bool:
	if not usando_photon() or token.is_empty():
		return false
	if is_host():
		confirmacao_vitoria_desistencia_recebida.emit(
			token,
			local_player_id(),
			vencedor
		)
		return true
	return send_host(
		self,
		&"_receber_confirmacao_vitoria_desistencia",
		[token, local_player_id(), vencedor],
		false
	)


func _receber_confirmacao_vitoria_desistencia(
	token: String,
	peer_declarado: int,
	vencedor: String
) -> void:
	if not usando_photon() or not is_host():
		return
	var peer_remetente: int = get_remote_sender_id()
	if peer_remetente <= 0:
		peer_remetente = peer_declarado
	confirmacao_vitoria_desistencia_recebida.emit(
		token,
		peer_remetente,
		vencedor
	)


func _enviar_photon(
	tipo_destino: String,
	jogador_destino: int,
	alvo: Object,
	metodo: StringName,
	argumentos: Array,
	exigir_host: bool,
	executar_local: bool
) -> bool:
	_registrar_receiver()
	if _fusion == null or not PhotonManager.esta_em_sala():
		_emitir_erro("Photon não está pronto para enviar RPC.")
		return false
	if not alvo is Node:
		_emitir_erro("O alvo do RPC online precisa ser um Node da árvore.")
		return false

	_sequencia_local += 1
	var remetente := local_player_id()
	var caminho := str((alvo as Node).get_path())
	var pacote_id := "%d:%d" % [remetente, _sequencia_local]
	var payload: Array = [
		caminho,
		str(metodo),
		argumentos.duplicate(true),
		remetente,
		jogador_destino,
		exigir_host,
		executar_local,
		pacote_id,
	]

	if tipo_destino == "all":
		if not _fusion.has_method(&"rpc"):
			_emitir_erro("A versão do Fusion instalada não possui rpc().")
			return false
		var chamada_all: Array = [Callable(self, "_rpc_dispatch")]
		chamada_all.append_array(payload)
		_fusion.callv(&"rpc", chamada_all)
		return true

	if jogador_destino == remetente:
		Callable(self, "_rpc_dispatch").callv(payload)
		return true
	if not _fusion.has_method(&"rpc_to_player"):
		_emitir_erro("A versão do Fusion instalada não possui rpc_to_player().")
		return false
	var chamada_player: Array = [jogador_destino, Callable(self, "_rpc_dispatch")]
	chamada_player.append_array(payload)
	_fusion.callv(&"rpc_to_player", chamada_player)
	return true


@rpc("any_peer", "call_local")
func _rpc_dispatch(
	caminho_alvo: String,
	metodo: String,
	argumentos: Array,
	remetente: int,
	jogador_destino: int,
	exigir_host: bool,
	executar_local: bool,
	pacote_id: String
) -> void:
	if not usando_photon():
		return
	if _pacote_ja_processado(pacote_id):
		return
	_marcar_pacote_processado(pacote_id)

	var id_local := local_player_id()
	if jogador_destino > 0 and jogador_destino != id_local:
		return
	if not executar_local and remetente == id_local:
		return
	if exigir_host and remetente != host_player_id():
		push_warning("RPC Photon ignorado: %s não veio do host." % metodo)
		return

	var pacote := {
		"caminho": caminho_alvo,
		"metodo": metodo,
		"argumentos": argumentos.duplicate(true),
		"remetente": remetente,
		"expira": Time.get_ticks_msec() + TEMPO_FILA_RPC_MS,
	}
	if not _invocar_pacote(pacote):
		_fila_rpc.append(pacote)


func _invocar_pacote(pacote: Dictionary) -> bool:
	var caminho := str(pacote.get("caminho", ""))
	var metodo := StringName(str(pacote.get("metodo", "")))
	var alvo := get_node_or_null(NodePath(caminho))
	if alvo == null or not alvo.has_method(metodo):
		return false
	var remetente_anterior := _remetente_rpc_atual
	_remetente_rpc_atual = int(pacote.get("remetente", 0))
	alvo.callv(metodo, Array(pacote.get("argumentos", [])))
	_remetente_rpc_atual = remetente_anterior
	return true


func _processar_fila_rpc() -> void:
	if _fila_rpc.is_empty():
		return
	var agora := Time.get_ticks_msec()
	var restantes: Array[Dictionary] = []
	for pacote in _fila_rpc:
		if int(pacote.get("expira", 0)) < agora:
			push_warning(
				"RPC Photon expirou aguardando o nó %s.%s"
				% [pacote.get("caminho", ""), pacote.get("metodo", "")]
			)
			continue
		if not _invocar_pacote(pacote):
			restantes.append(pacote)
	_fila_rpc = restantes


func _pacote_ja_processado(pacote_id: String) -> bool:
	return _pacotes_vistos.has(pacote_id)


func _marcar_pacote_processado(pacote_id: String) -> void:
	_pacotes_vistos[pacote_id] = true
	_ordem_pacotes_vistos.append(pacote_id)
	while _ordem_pacotes_vistos.size() > LIMITE_PACOTES_VISTOS:
		var antigo: String = _ordem_pacotes_vistos[0]
		_ordem_pacotes_vistos.remove_at(0)
		_pacotes_vistos.erase(antigo)


func mudar_cena_para_todos(caminho: String, limpar_escolhas: bool = false) -> bool:
	if not is_host():
		return false
	return send_all(
		self,
		&"_aplicar_mudanca_cena_online",
		[caminho, limpar_escolhas],
		true,
		true
	)


func iniciar_tabuleiro_retomado(
	escolhas: Dictionary,
	usuarios: Dictionary,
	escolhas_usuario: Dictionary
) -> bool:
	if not usando_photon() or not is_host():
		return false
	if escolhas.is_empty() or usuarios.is_empty() or escolhas_usuario.is_empty():
		return false
	return send_all(
		self,
		&"_aplicar_inicio_tabuleiro_retomado",
		[
			escolhas.duplicate(true),
			usuarios.duplicate(true),
			escolhas_usuario.duplicate(true),
		],
		true,
		true
	)


@rpc("authority", "call_local", "reliable")
func _aplicar_inicio_tabuleiro_retomado(
	escolhas: Dictionary,
	usuarios: Dictionary,
	escolhas_usuario: Dictionary
) -> void:
	if _sincronizando_cena:
		return
	var id_local: int = local_player_id()
	if id_local <= 0 or not escolhas.has(id_local) or not usuarios.has(id_local):
		_emitir_erro("Este usuário não pertence à partida salva.")
		return
	var user_id_local: String = PhotonManager.obter_user_id_local()
	var personagem_local: String = str(escolhas[id_local])
	if (
		user_id_local.is_empty()
		or str(usuarios[id_local]) != user_id_local
		or str(escolhas_usuario.get(user_id_local, "")) != personagem_local
	):
		_emitir_erro("A identidade deste participante não corresponde ao salvamento.")
		return

	_sincronizando_cena = true
	Global.escolhas_da_mesa = escolhas.duplicate(true)
	Global.user_ids_da_mesa = usuarios.duplicate(true)
	Global.escolhas_por_user_id = escolhas_usuario.duplicate(true)
	Global.modo_online = true
	Global.meu_peer_id = id_local
	Global.fase_online = "tabuleiro"
	Global.cena_online_atual = CENA_TABULEIRO
	get_tree().call_deferred("change_scene_to_file", CENA_TABULEIRO)
	await get_tree().process_frame
	_sincronizando_cena = false


@rpc("authority", "call_local", "reliable")
func _aplicar_mudanca_cena_online(caminho: String, limpar_escolhas: bool) -> void:
	if _sincronizando_cena:
		return
	_sincronizando_cena = true
	if limpar_escolhas:
		Global.escolhas_da_mesa.clear()
		Global.user_ids_da_mesa.clear()
		Global.escolhas_por_user_id.clear()
	Global.modo_online = usando_photon()
	Global.meu_peer_id = local_player_id()
	Global.fase_online = _fase_por_cena(caminho)
	Global.cena_online_atual = caminho
	get_tree().call_deferred("change_scene_to_file", caminho)
	await get_tree().process_frame
	_sincronizando_cena = false


func voltar_para_lobby_online() -> void:
	if is_host():
		mudar_cena_para_todos(CENA_ONLINE, true)
	else:
		PhotonManager.sair_sala()
		Global.modo_online = false
		get_tree().change_scene_to_file(CENA_ONLINE)


func definir_fase_online(fase: String, cena: String = "") -> void:
	Global.fase_online = fase
	if not cena.is_empty():
		Global.cena_online_atual = cena


func solicitar_snapshot_tabuleiro() -> void:
	if not usando_photon() or is_host():
		return
	send_host(self, &"_receber_pedido_snapshot", [local_player_id()], false)


func publicar_snapshot_tabuleiro() -> void:
	if not usando_photon() or not is_host():
		return
	_enviar_snapshot_tabuleiro(0, true)


func _receber_pedido_snapshot(jogador_solicitante: int) -> void:
	if not is_host() or jogador_solicitante <= 0:
		return
	_enviar_snapshot_tabuleiro(jogador_solicitante, false)


func _enviar_snapshot_tabuleiro(jogador_destino: int, para_todos: bool) -> void:
	var tabuleiro_node: Node = get_tree().get_first_node_in_group("tabuleiro_principal")
	if tabuleiro_node == null or not tabuleiro_node.has_method(&"criar_snapshot_online"):
		return
	var snapshot_variant: Variant = tabuleiro_node.call(&"criar_snapshot_online")
	if not snapshot_variant is Dictionary:
		return

	# O snapshot é serializado e dividido em partes pequenas. Enviar o dicionário
	# inteiro em um único RPC fazia a transferência falhar silenciosamente em
	# algumas versões preview do Fusion e podia bloquear a fila UDP.
	var dados_serializados: PackedByteArray = var_to_bytes(snapshot_variant)
	if dados_serializados.is_empty():
		_emitir_erro("Não foi possível serializar o snapshot da partida.")
		return

	var total_partes: int = ceili(
		float(dados_serializados.size()) / float(TAMANHO_PARTE_SNAPSHOT)
	)
	if total_partes <= 0 or total_partes > MAX_PARTES_SNAPSHOT:
		_emitir_erro(
			"Snapshot inválido ou grande demais: %d bytes em %d partes."
			% [dados_serializados.size(), total_partes]
		)
		return

	_sequencia_snapshot += 1
	var transferencia_id: String = "%d:%d:%d" % [
		local_player_id(),
		Time.get_ticks_msec(),
		_sequencia_snapshot,
	]
	print(
		"[PHOTON] Enviando snapshot %s: %d bytes em %d partes."
		% [transferencia_id, dados_serializados.size(), total_partes]
	)

	for indice in range(total_partes):
		var inicio: int = indice * TAMANHO_PARTE_SNAPSHOT
		var fim: int = mini(inicio + TAMANHO_PARTE_SNAPSHOT, dados_serializados.size())
		var parte: PackedByteArray = dados_serializados.slice(inicio, fim)
		var argumentos: Array = [
			transferencia_id,
			indice,
			total_partes,
			dados_serializados.size(),
			parte,
		]
		if para_todos:
			send_all(
				self,
				&"_receber_parte_snapshot",
				argumentos,
				true,
				false
			)
		else:
			send_player(
				jogador_destino,
				self,
				&"_receber_parte_snapshot",
				argumentos,
				false,
				true
			)


func _receber_parte_snapshot(
	transferencia_id: String,
	indice: int,
	total_partes: int,
	tamanho_total: int,
	parte: PackedByteArray
) -> void:
	if transferencia_id.is_empty():
		return
	if total_partes <= 0 or total_partes > MAX_PARTES_SNAPSHOT:
		return
	if indice < 0 or indice >= total_partes:
		return
	if tamanho_total <= 0 or parte.is_empty():
		return

	var transferencia: Dictionary = Dictionary(
		_transferencias_snapshot.get(transferencia_id, {})
	)
	if transferencia.is_empty():
		transferencia = {
			"total": total_partes,
			"tamanho": tamanho_total,
			"partes": {},
			"expira": Time.get_ticks_msec() + TEMPO_TRANSFERENCIA_SNAPSHOT_MS,
		}
	elif int(transferencia.get("total", 0)) != total_partes:
		_transferencias_snapshot.erase(transferencia_id)
		return

	var partes: Dictionary = Dictionary(transferencia.get("partes", {}))
	if not partes.has(indice):
		partes[indice] = parte.duplicate()
	transferencia["partes"] = partes
	transferencia["expira"] = Time.get_ticks_msec() + TEMPO_TRANSFERENCIA_SNAPSHOT_MS
	_transferencias_snapshot[transferencia_id] = transferencia

	if partes.size() < total_partes:
		return

	var dados_serializados: PackedByteArray = PackedByteArray()
	for parte_indice in range(total_partes):
		if not partes.has(parte_indice):
			return
		var parte_variant: Variant = partes[parte_indice]
		if not parte_variant is PackedByteArray:
			_transferencias_snapshot.erase(transferencia_id)
			return
		dados_serializados.append_array(parte_variant)

	_transferencias_snapshot.erase(transferencia_id)
	if dados_serializados.size() != tamanho_total:
		push_warning(
			"[PHOTON] Snapshot %s chegou incompleto: %d de %d bytes."
			% [transferencia_id, dados_serializados.size(), tamanho_total]
		)
		return

	var snapshot_variant: Variant = bytes_to_var(dados_serializados)
	if not snapshot_variant is Dictionary:
		push_warning("[PHOTON] Snapshot recebido não pôde ser decodificado.")
		return
	print(
		"[PHOTON] Snapshot %s recebido por completo: %d bytes."
		% [transferencia_id, tamanho_total]
	)
	_receber_snapshot_tabuleiro(snapshot_variant)


func _receber_snapshot_tabuleiro(snapshot: Dictionary) -> void:
	_snapshot_pendente = snapshot.duplicate(true)
	_tentar_aplicar_snapshot_pendente()


func _tentar_aplicar_snapshot_pendente() -> void:
	if _snapshot_pendente.is_empty():
		return
	var tabuleiro_node: Node = get_tree().get_first_node_in_group("tabuleiro_principal")
	if tabuleiro_node == null or not tabuleiro_node.has_method(&"aplicar_snapshot_online"):
		return
	var snapshot: Dictionary = _snapshot_pendente.duplicate(true)
	_snapshot_pendente.clear()
	tabuleiro_node.call(&"aplicar_snapshot_online", snapshot)
	snapshot_aplicado.emit()


func _limpar_transferencias_snapshot_expiradas() -> void:
	if _transferencias_snapshot.is_empty():
		return
	var agora: int = Time.get_ticks_msec()
	for id_variant in _transferencias_snapshot.keys().duplicate():
		var transferencia_id: String = str(id_variant)
		var transferencia_variant: Variant = _transferencias_snapshot.get(
			transferencia_id, {}
		)
		if not transferencia_variant is Dictionary:
			_transferencias_snapshot.erase(transferencia_id)
			continue
		var transferencia: Dictionary = transferencia_variant
		if int(transferencia.get("expira", 0)) < agora:
			push_warning(
				"[PHOTON] Transferência de snapshot %s expirou." % transferencia_id
			)
			_transferencias_snapshot.erase(transferencia_id)


func _ao_entrar_sala_photon(_codigo: String, _id: int, _host: bool) -> void:
	_registrar_receiver()
	_revisao_estado_pausa_partida = 0
	_acks_estado_pausa.clear()
	_destinos_estado_pausa.clear()
	_token_resultado_desistencia_atual = ""
	_resultado_desistencia_pendente.clear()
	_estado_pausa_partida = {
		"ativo": false,
		"peer_iniciador": 0,
		"personagem_iniciador": "",
		"nome_iniciador": "",
	}
	Global.modo_online = true
	Global.meu_peer_id = local_player_id()


func _ao_jogador_sair_photon(jogador_id: int, inativo: bool) -> void:
	jogador_desconectado.emit(jogador_id, inativo)


func _ao_jogador_sair_lan(jogador_id: int) -> void:
	jogador_desconectado.emit(jogador_id, false)


func _ao_host_alterado_photon(valor: bool) -> void:
	host_alterado.emit(valor)


func _ao_jogador_reconectado(id_antigo: int, id_novo: int, user_id: String) -> void:
	jogador_reconectado.emit(id_antigo, id_novo, user_id)


func _ao_jogador_descoberto(dados: Dictionary) -> void:
	if not usando_photon() or not is_host():
		return
	var novo_id := int(dados.get("id", 0))
	if novo_id <= 0 or novo_id == local_player_id():
		return
	var user_id := str(dados.get("user_id", ""))
	var fase := str(Global.fase_online)
	if fase == "online_lobby" or fase.is_empty():
		return

	# Durante uma partida, somente um usuário que já possuía personagem pode
	# retornar. Novos participantes não entram no meio da economia.
	if fase == "tabuleiro" and not Global.escolhas_por_user_id.has(user_id):
		send_player(
			novo_id,
			self,
			&"_rejeitar_entrada_em_partida",
			["A partida já começou e esta vaga não pertence a este usuário."],
			false,
			true
		)
		return

	var peer_antigo := _encontrar_peer_por_user_id(user_id, novo_id)
	var personagem_reconectado := str(Global.escolhas_por_user_id.get(user_id, ""))
	if not personagem_reconectado.is_empty():
		send_all(
			self,
			&"_aplicar_remapeamento_peer",
			[peer_antigo, novo_id, user_id, personagem_reconectado],
			true,
			true
		)
	send_player(
		novo_id,
		self,
		&"_sincronizar_sessao_online",
		[
			fase,
			str(Global.cena_online_atual),
			Global.escolhas_da_mesa.duplicate(true),
			Global.user_ids_da_mesa.duplicate(true),
			Global.escolhas_por_user_id.duplicate(true),
		],
		false,
		true
	)


func _encontrar_peer_por_user_id(user_id: String, ignorar_id: int = 0) -> int:
	if user_id.is_empty():
		return 0
	for peer_variant in Global.user_ids_da_mesa.keys():
		var peer_id := int(peer_variant)
		if peer_id != ignorar_id and str(Global.user_ids_da_mesa[peer_variant]) == user_id:
			return peer_id
	return 0


func _aplicar_remapeamento_peer(
	peer_antigo: int,
	peer_novo: int,
	user_id: String,
	personagem: String
) -> void:
	if peer_antigo > 0 and peer_antigo != peer_novo:
		Global.user_ids_da_mesa.erase(peer_antigo)
		Global.escolhas_da_mesa.erase(peer_antigo)
	if peer_novo > 0 and not personagem.is_empty():
		Global.user_ids_da_mesa[peer_novo] = user_id
		Global.escolhas_da_mesa[peer_novo] = personagem
	if not user_id.is_empty() and not personagem.is_empty():
		Global.escolhas_por_user_id[user_id] = personagem


func _sincronizar_sessao_online(
	fase: String,
	cena: String,
	escolhas: Dictionary,
	usuarios: Dictionary,
	escolhas_usuario: Dictionary
) -> void:
	Global.modo_online = true
	Global.meu_peer_id = local_player_id()
	Global.fase_online = fase
	Global.cena_online_atual = cena
	Global.escolhas_da_mesa = escolhas.duplicate(true)
	Global.user_ids_da_mesa = usuarios.duplicate(true)
	Global.escolhas_por_user_id = escolhas_usuario.duplicate(true)
	if not cena.is_empty() and get_tree().current_scene != null:
		if get_tree().current_scene.scene_file_path != cena:
			get_tree().change_scene_to_file(cena)
			await get_tree().process_frame
	if fase == "tabuleiro":
		call_deferred("solicitar_snapshot_tabuleiro")
	sessao_sincronizada.emit(fase)


func _rejeitar_entrada_em_partida(mensagem: String) -> void:
	_emitir_erro(mensagem)
	PhotonManager.sair_sala()
	Global.modo_online = false
	Global.fase_online = "online_lobby"
	Global.cena_online_atual = CENA_ONLINE
	get_tree().change_scene_to_file(CENA_ONLINE)


func _fase_por_cena(caminho: String) -> String:
	match caminho:
		CENA_SELECAO:
			return "selecao"
		CENA_TABULEIRO:
			return "tabuleiro"
		_:
			return "online_lobby"


func _emitir_erro(mensagem: String) -> void:
	push_error("[TRANSPORTE ONLINE] " + mensagem)
	erro_transporte.emit(mensagem)
