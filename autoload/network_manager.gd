extends Node

## Gerenciador persistente da rede local (LAN).
##
## A criação do ENet client só inicia uma tentativa; a conexão real é confirmada
## pelos sinais connected_to_server / connection_failed do MultiplayerAPI.

signal estado_rede_alterado(estado: int, mensagem: String)
signal servidor_criado(ip_principal: String, ips_disponiveis: PackedStringArray, porta: int)
signal conexao_iniciada(ip: String, porta: int)
signal conectado_ao_servidor()
signal falha_conexao(mensagem: String)
signal servidor_desconectado(mensagem: String)
signal jogador_conectado(id: int)
signal jogador_desconectado(id: int)

enum EstadoRede {
	OFFLINE,
	HOSPEDANDO,
	CONECTANDO,
	CONECTADO,
	ERRO,
}

const PORT: int = 8910
const MAX_JOGADORES: int = 6
const TIMEOUT_CONEXAO_SEGUNDOS: float = 10.0
const CENA_LOBBY: String = "res://scenes/ui/lobby/lobby.tscn"

var peer: ENetMultiplayerPeer
var estado_rede: int = EstadoRede.OFFLINE
var ip_alvo_atual: String = ""
var ip_host_principal: String = ""
var ips_host_disponiveis: PackedStringArray = PackedStringArray()
var ultima_mensagem_rede: String = ""
var mensagem_pendente_lobby: String = ""
var sala_aceitando_jogadores: bool = false

var _tentativa_conexao_id: int = 0
var _desconexao_intencional: bool = false
var _sinais_conectados: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_garantir_sinais_conectados()
	# Mantém a árvore em um estado multiplayer válido mesmo antes de criar sala.
	if multiplayer.multiplayer_peer == null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _garantir_sinais_conectados() -> void:
	if _sinais_conectados:
		return

	if not multiplayer.connected_to_server.is_connected(_ao_conectar_no_servidor):
		multiplayer.connected_to_server.connect(_ao_conectar_no_servidor)
	if not multiplayer.connection_failed.is_connected(_ao_falhar_conexao):
		multiplayer.connection_failed.connect(_ao_falhar_conexao)
	if not multiplayer.server_disconnected.is_connected(_ao_servidor_desconectar):
		multiplayer.server_disconnected.connect(_ao_servidor_desconectar)
	if not multiplayer.peer_connected.is_connected(_ao_jogador_conectar):
		multiplayer.peer_connected.connect(_ao_jogador_conectar)
	if not multiplayer.peer_disconnected.is_connected(_ao_jogador_desconectar):
		multiplayer.peer_disconnected.connect(_ao_jogador_desconectar)

	_sinais_conectados = true


func _definir_estado(novo_estado: int, mensagem: String) -> void:
	estado_rede = novo_estado
	ultima_mensagem_rede = mensagem
	estado_rede_alterado.emit(estado_rede, mensagem)
	print("[REDE] " + mensagem)


func _fechar_peer_atual() -> void:
	_tentativa_conexao_id += 1
	_desconexao_intencional = true

	if peer != null:
		peer.close()
	peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

	# Os sinais gerados pelo fechamento costumam ser síncronos. O deferred evita
	# que uma queda intencional seja tratada como perda inesperada do servidor.
	call_deferred("_liberar_flag_desconexao_intencional")


func _liberar_flag_desconexao_intencional() -> void:
	_desconexao_intencional = false


## Cria uma sala que escuta em todas as interfaces de rede do aparelho.
## MAX_JOGADORES inclui o host, portanto o ENet aceita no máximo 5 clientes.
func criar_servidor() -> int:
	_garantir_sinais_conectados()
	_fechar_peer_atual()

	peer = ENetMultiplayerPeer.new()
	peer.set_bind_ip("*")
	var erro: int = peer.create_server(PORT, MAX_JOGADORES - 1)
	if erro != OK:
		peer = null
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		var mensagem := _mensagem_erro_criacao_servidor(erro)
		_definir_estado(EstadoRede.ERRO, mensagem)
		return erro

	multiplayer.multiplayer_peer = peer
	mensagem_pendente_lobby = ""
	sala_aceitando_jogadores = true
	peer.refuse_new_connections = false
	ips_host_disponiveis = obter_ips_lan()
	ip_host_principal = ips_host_disponiveis[0] if not ips_host_disponiveis.is_empty() else ""
	ip_alvo_atual = ""
	_definir_estado(EstadoRede.HOSPEDANDO, "Sala LAN criada na porta UDP %d." % PORT)
	servidor_criado.emit(ip_host_principal, ips_host_disponiveis, PORT)
	return OK


## Inicia a tentativa de conexão. O retorno OK significa somente que o cliente
## ENet foi criado; o sucesso real chega pelo sinal conectado_ao_servidor.
func entrar_servidor(ip_servidor: String) -> int:
	_garantir_sinais_conectados()
	var endereco := ip_servidor.strip_edges()
	if not endereco_ipv4_valido(endereco):
		var mensagem := "IP inválido. Use um IPv4 como 192.168.1.25."
		_definir_estado(EstadoRede.ERRO, mensagem)
		return ERR_INVALID_PARAMETER
	if endereco_loopback(endereco):
		var mensagem := (
			"127.0.0.1 aponta para este próprio aparelho. Digite o IP LAN exibido pelo host."
		)
		_definir_estado(EstadoRede.ERRO, mensagem)
		return ERR_INVALID_PARAMETER
	if _endereco_ipv4_descartavel(endereco):
		var mensagem := "Esse endereço não pode ser usado como destino de uma sala LAN."
		_definir_estado(EstadoRede.ERRO, mensagem)
		return ERR_INVALID_PARAMETER

	_fechar_peer_atual()
	sala_aceitando_jogadores = false
	mensagem_pendente_lobby = ""
	peer = ENetMultiplayerPeer.new()
	var erro: int = peer.create_client(endereco, PORT)
	if erro != OK:
		peer = null
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		var mensagem := _mensagem_erro_cliente(erro, endereco)
		_definir_estado(EstadoRede.ERRO, mensagem)
		return erro

	multiplayer.multiplayer_peer = peer
	ip_alvo_atual = endereco
	_tentativa_conexao_id += 1
	var id_tentativa := _tentativa_conexao_id
	_definir_estado(EstadoRede.CONECTANDO, "Conectando a %s:%d..." % [endereco, PORT])
	conexao_iniciada.emit(endereco, PORT)
	_iniciar_timeout_conexao(id_tentativa, endereco)
	return OK


func _iniciar_timeout_conexao(id_tentativa: int, endereco: String) -> void:
	await get_tree().create_timer(TIMEOUT_CONEXAO_SEGUNDOS).timeout
	if id_tentativa != _tentativa_conexao_id:
		return
	if estado_rede != EstadoRede.CONECTANDO:
		return

	var mensagem := (
		"Tempo esgotado ao conectar em %s:%d. Verifique o IP, o mesmo Wi-Fi e o Firewall do host."
		% [endereco, PORT]
	)
	_fechar_peer_atual()
	sala_aceitando_jogadores = false
	_definir_estado(EstadoRede.ERRO, mensagem)
	falha_conexao.emit(mensagem)


func desconectar(motivo: String = "Conexão encerrada.") -> void:
	_fechar_peer_atual()
	ip_alvo_atual = ""
	ip_host_principal = ""
	ips_host_disponiveis = PackedStringArray()
	sala_aceitando_jogadores = false
	_definir_estado(EstadoRede.OFFLINE, motivo)


func _ao_conectar_no_servidor() -> void:
	if _desconexao_intencional:
		return
	if estado_rede != EstadoRede.CONECTANDO:
		return
	_tentativa_conexao_id += 1
	sala_aceitando_jogadores = false
	_definir_estado(EstadoRede.CONECTADO, "Conectado à sala %s:%d." % [ip_alvo_atual, PORT])
	conectado_ao_servidor.emit()


func _ao_falhar_conexao() -> void:
	if _desconexao_intencional:
		return
	if estado_rede != EstadoRede.CONECTANDO:
		return
	var endereco := ip_alvo_atual
	var mensagem := (
		"Não foi possível conectar em %s:%d. Confirme o IP, a rede Wi-Fi e a porta UDP."
		% [endereco, PORT]
	)
	_fechar_peer_atual()
	sala_aceitando_jogadores = false
	_definir_estado(EstadoRede.ERRO, mensagem)
	falha_conexao.emit(mensagem)


func _ao_servidor_desconectar() -> void:
	if _desconexao_intencional:
		return
	if estado_rede not in [EstadoRede.CONECTANDO, EstadoRede.CONECTADO]:
		return

	var mensagem := "A conexão com o host foi perdida. A sala foi encerrada."
	_fechar_peer_atual()
	_definir_estado(EstadoRede.ERRO, mensagem)
	servidor_desconectado.emit(mensagem)

	# Se a queda acontecer durante seleção ou partida, todos os clientes voltam
	# ao lobby em vez de permanecerem numa cena sem autoridade de rede.
	var cena_atual := get_tree().current_scene
	if cena_atual != null and cena_atual.scene_file_path != CENA_LOBBY:
		mensagem_pendente_lobby = mensagem
		get_tree().call_deferred("change_scene_to_file", CENA_LOBBY)
	else:
		mensagem_pendente_lobby = ""


func _ao_jogador_conectar(id: int) -> void:
	print("[REDE] Peer %d entrou na sala." % id)
	jogador_conectado.emit(id)


func _ao_jogador_desconectar(id: int) -> void:
	print("[REDE] Peer %d saiu da sala." % id)
	jogador_desconectado.emit(id)


func esta_hospedando() -> bool:
	return estado_rede == EstadoRede.HOSPEDANDO and multiplayer.is_server()


func esta_conectado_como_cliente() -> bool:
	return estado_rede == EstadoRede.CONECTADO and not multiplayer.is_server()


func esta_conectando() -> bool:
	return estado_rede == EstadoRede.CONECTANDO


func esta_em_sala() -> bool:
	return esta_hospedando() or esta_conectado_como_cliente()


func trancar_sala() -> void:
	if not esta_hospedando() or peer == null:
		return
	sala_aceitando_jogadores = false
	peer.refuse_new_connections = true
	print("[REDE] Sala trancada para novos jogadores.")


func abrir_sala() -> void:
	if not esta_hospedando() or peer == null:
		return
	sala_aceitando_jogadores = true
	peer.refuse_new_connections = false
	print("[REDE] Sala aberta para novos jogadores.")


func total_jogadores_na_sala() -> int:
	if not esta_em_sala():
		return 0
	return mini(MAX_JOGADORES, multiplayer.get_peers().size() + 1)


func consumir_mensagem_pendente_lobby() -> String:
	var mensagem := mensagem_pendente_lobby
	mensagem_pendente_lobby = ""
	return mensagem


func atualizar_ips_host() -> PackedStringArray:
	ips_host_disponiveis = obter_ips_lan()
	ip_host_principal = ips_host_disponiveis[0] if not ips_host_disponiveis.is_empty() else ""
	return ips_host_disponiveis


## Retorna IPv4s úteis da LAN, priorizando Wi-Fi, depois Ethernet e outras
## interfaces privadas. Loopback, APIPA e broadcast são descartados.
func obter_ips_lan() -> PackedStringArray:
	var wifi_privados: Array = []
	var ethernet_privados: Array = []
	var outros_privados: Array = []
	var outros_ipv4: Array = []

	for interface_data in IP.get_local_interfaces():
		var descricao := (
			str(interface_data.get("name", "")) + " " + str(interface_data.get("friendly", ""))
		).to_lower()
		var eh_wifi := (
			descricao.contains("wi-fi")
			or descricao.contains("wifi")
			or descricao.contains("wireless")
			or descricao.contains("wlan")
		)
		var eh_ethernet := (
			descricao.contains("ethernet")
			or descricao.begins_with("eth")
			or descricao.contains(" lan")
		)

		for endereco_variant in interface_data.get("addresses", []):
			var endereco := str(endereco_variant).strip_edges()
			if not endereco_ipv4_valido(endereco):
				continue
			if _endereco_ipv4_descartavel(endereco):
				continue

			if _endereco_ipv4_privado(endereco):
				if eh_wifi:
					_adicionar_unico(wifi_privados, endereco)
				elif eh_ethernet:
					_adicionar_unico(ethernet_privados, endereco)
				else:
					_adicionar_unico(outros_privados, endereco)
			else:
				_adicionar_unico(outros_ipv4, endereco)

	var resultado: Array = []
	for grupo in [wifi_privados, ethernet_privados, outros_privados, outros_ipv4]:
		for endereco in grupo:
			_adicionar_unico(resultado, endereco)

	# Fallback para plataformas que não retornam interfaces detalhadas.
	if resultado.is_empty():
		for endereco_variant in IP.get_local_addresses():
			var endereco := str(endereco_variant).strip_edges()
			if endereco_ipv4_valido(endereco) and not _endereco_ipv4_descartavel(endereco):
				_adicionar_unico(resultado, endereco)

	return PackedStringArray(resultado)


func endereco_ipv4_valido(endereco: String) -> bool:
	var partes := endereco.strip_edges().split(".")
	if partes.size() != 4:
		return false
	for parte in partes:
		var trecho := str(parte)
		if trecho.is_empty() or not trecho.is_valid_int():
			return false
		var numero := int(trecho)
		if numero < 0 or numero > 255:
			return false
	return true


func endereco_loopback(endereco: String) -> bool:
	return endereco.begins_with("127.")


func _endereco_ipv4_privado(endereco: String) -> bool:
	var partes := endereco.split(".")
	var primeiro := int(partes[0])
	var segundo := int(partes[1])
	return (
		primeiro == 10
		or (primeiro == 172 and segundo >= 16 and segundo <= 31)
		or (primeiro == 192 and segundo == 168)
	)


func _endereco_ipv4_descartavel(endereco: String) -> bool:
	return (
		endereco == "0.0.0.0"
		or endereco == "255.255.255.255"
		or endereco.begins_with("127.")
		or endereco.begins_with("169.254.")
	)


func _adicionar_unico(lista: Array, valor: String) -> void:
	if not lista.has(valor):
		lista.append(valor)


func _mensagem_erro_criacao_servidor(erro: int) -> String:
	match erro:
		ERR_ALREADY_IN_USE:
			return "A porta UDP %d já está em uso. Feche outra instância do jogo." % PORT
		ERR_CANT_CREATE:
			return "Não foi possível abrir a porta UDP %d. Verifique o Firewall e a rede." % PORT
		_:
			return "Erro ao criar a sala LAN (código %d)." % erro


func _mensagem_erro_cliente(erro: int, endereco: String) -> String:
	match erro:
		ERR_ALREADY_IN_USE:
			return "Já existe uma conexão de rede ativa neste aparelho."
		ERR_CANT_CREATE:
			return "Não foi possível iniciar a conexão com %s:%d." % [endereco, PORT]
		ERR_INVALID_PARAMETER:
			return "O endereço informado é inválido."
		_:
			return "Erro ao iniciar conexão com %s:%d (código %d)." % [endereco, PORT, erro]


# ==========================================
# FUNÇÕES DE SINCRONIZAÇÃO (RPC)
# ==========================================

@rpc("authority", "call_local", "reliable")
func iniciar_selecao_personagens() -> void:
	trancar_sala()
	print("Sincronizando transição para a Seleção de Personagens...")
	Global.escolhas_da_mesa.clear()
	Global.user_ids_da_mesa.clear()
	Global.escolhas_por_user_id.clear()
	Global.modo_online = false
	Global.meu_peer_id = multiplayer.get_unique_id()
	get_tree().change_scene_to_file("res://scenes/ui/selecao_personagem/selecao_personagem.tscn")


@rpc("authority", "call_local", "reliable")
func _voltar_lobby_rede() -> void:
	abrir_sala()
	print("Voltando ao lobby para nova partida...")
	Global.escolhas_da_mesa.clear()
	Global.user_ids_da_mesa.clear()
	Global.escolhas_por_user_id.clear()
	Global.modo_online = false
	get_tree().change_scene_to_file(CENA_LOBBY)
