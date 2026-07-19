extends Node

## Integração central com Photon Fusion Godot.
##
## A API é acessada dinamicamente para que o projeto continue abrindo antes da
## instalação do addon nativo. Quando a pasta addons/fusion/ estiver presente,
## o singleton global `Fusion` é detectado e os sinais são conectados.

signal estado_alterado(resumo: Dictionary)
signal conectado_ao_photon()
signal sala_entrada(codigo: String, jogador_local_id: int, eh_host: bool)
signal sala_saida()
signal jogador_saiu(jogador_id: int, inativo: bool)
signal jogador_descoberto(dados: Dictionary)
signal jogador_reconectado(id_antigo: int, id_novo: int, user_id: String)
signal jogadores_sala_alterados(jogadores: Array)
signal pronto_local_alterado(pronto: bool)
signal host_alterado(eh_host: bool)
signal erro_photon(mensagem: String)

enum Estado {
	PLUGIN_AUSENTE,
	CONFIGURACAO_INCOMPLETA,
	PRONTO,
	CONECTANDO,
	CONECTADO,
	ENTRANDO_SALA,
	EM_SALA,
	ERRO,
}

const CAMINHO_CONFIG_PROJETO := "res://photon/photon_config.cfg"
const CAMINHO_CONFIG_USUARIO := "user://photon_config.cfg"
const CAMINHO_ID_USUARIO := "user://photon_user_id.txt"
const PREFIXO_ARGUMENTO_USER_ID := "--photon-user-id="
const PREFIXO_ARGUMENTO_TESTE := "--photon-test-slot="
const TAMANHO_MINIMO_CODIGO_SALA := 3
const TAMANHO_MAXIMO_CODIGO_SALA := 20
const CARACTERES_CODIGO := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

var estado: Estado = Estado.PLUGIN_AUSENTE
var plugin_disponivel: bool = false
var configuracao_valida: bool = false
var conectado: bool = false
var em_sala: bool = false
var entrando_sala: bool = false
var app_id_mascarado: String = ""
var modo_autoridade_configurado: bool = false
var codigo_sala_atual: String = ""
var jogador_local_id: int = 0
var eh_host: bool = false
var ultima_mensagem: String = ""
var ultimo_erro: String = ""
var config: Dictionary = {}

# Estado do lobby online. Cada entrada usa o player_id numérico do Fusion.
# { id: { "id", "user_id", "nome", "pronto", "host", "inativo" } }
var jogadores_sala: Dictionary = {}
var nome_jogador_local: String = "JOGADOR"
var pronto_local: bool = false

var _fusion: Object = null
var _sinais_conectados: bool = false
var _desconexao_intencional: bool = false
var _acao_pendente: Dictionary = {}
var _user_id_conexao: String = ""
var _broadcast_registrado: bool = false
var _sequencia_anuncio: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	nome_jogador_local = _obter_nome_perfil()
	recarregar_configuracao()


func recarregar_configuracao() -> Dictionary:
	plugin_disponivel = _detectar_plugin()
	config = _carregar_configuracao()
	configuracao_valida = _validar_configuracao(config)
	app_id_mascarado = _mascarar_app_id(str(config.get("app_id", "")))
	ultimo_erro = ""

	if plugin_disponivel:
		_obter_singleton_fusion()
		_conectar_sinais()
		_aplicar_configuracao_ao_project_settings()
		_atualizar_flags_da_api()

	if not plugin_disponivel:
		_definir_estado(
			Estado.PLUGIN_AUSENTE,
			"Instale o Photon Fusion Godot copiando a pasta fusion para addons/fusion/."
		)
	elif not configuracao_valida:
		_definir_estado(
			Estado.CONFIGURACAO_INCOMPLETA,
			"Configure o Fusion 3 App ID em Project Settings > Fusion > Connection > App ID."
		)
	elif em_sala:
		_definir_estado(Estado.EM_SALA, "Conectado à sala Photon %s." % codigo_sala_atual)
	elif conectado:
		_definir_estado(Estado.CONECTADO, "Conectado ao Photon Cloud.")
	else:
		_definir_estado(Estado.PRONTO, "Photon configurado. Pronto para conectar.")

	return obter_resumo()


func conectar_nuvem() -> bool:
	_acao_pendente.clear()
	return _iniciar_conexao()


func entrar_ou_criar_sala(codigo: String, max_jogadores: int = 6) -> bool:
	var codigo_limpo := normalizar_codigo_sala(codigo)
	if codigo_limpo.length() < TAMANHO_MINIMO_CODIGO_SALA:
		_falhar("O código da sala precisa ter pelo menos %d caracteres." % TAMANHO_MINIMO_CODIGO_SALA)
		return false

	_atualizar_flags_da_api()
	if entrando_sala:
		_definir_estado(Estado.ENTRANDO_SALA, "A entrada em uma sala já está em andamento.")
		return false

	_acao_pendente = {
		"tipo": "entrar_ou_criar",
		"codigo": codigo_limpo,
		"max_jogadores": clampi(max_jogadores, 2, 6),
	}

	if em_sala:
		if codigo_sala_atual == codigo_limpo:
			_definir_estado(Estado.EM_SALA, "Você já está na sala %s." % codigo_limpo)
			return true
		_falhar("Saia da sala atual antes de entrar em outra.")
		return false

	if conectado:
		_executar_acao_pendente()
		return true
	return _iniciar_conexao()


func entrar_partida_rapida(max_jogadores: int = 6) -> bool:
	_atualizar_flags_da_api()
	if entrando_sala:
		_definir_estado(Estado.ENTRANDO_SALA, "A busca por uma partida já está em andamento.")
		return false
	if em_sala:
		_falhar("Saia da sala atual antes de procurar outra partida.")
		return false

	_acao_pendente = {
		"tipo": "partida_rapida",
		"codigo": "PARTIDA-RAPIDA",
		"max_jogadores": clampi(max_jogadores, 2, 6),
	}
	if conectado:
		_executar_acao_pendente()
		return true
	return _iniciar_conexao()


func desconectar() -> void:
	_acao_pendente.clear()
	_desconexao_intencional = true
	if _fusion != null and _fusion.has_method(&"disconnect_from_photon"):
		_fusion.call(&"disconnect_from_photon")
	conectado = false
	em_sala = false
	entrando_sala = false
	codigo_sala_atual = ""
	jogador_local_id = 0
	eh_host = false
	_limpar_lobby_online()
	var estado_final := (
		Estado.PRONTO if configuracao_valida else Estado.CONFIGURACAO_INCOMPLETA
	)
	_definir_estado(estado_final, "Conexão Photon encerrada.")
	call_deferred("_liberar_desconexao_intencional")


func gerar_codigo_sala(tamanho: int = 6) -> String:
	var resultado := ""
	var quantidade := clampi(tamanho, TAMANHO_MINIMO_CODIGO_SALA, 10)
	for _i in range(quantidade):
		resultado += CARACTERES_CODIGO[randi_range(0, CARACTERES_CODIGO.length() - 1)]
	return resultado


func normalizar_codigo_sala(codigo: String) -> String:
	var resultado := ""
	var permitido := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
	for caractere in codigo.strip_edges().to_upper():
		var texto := str(caractere)
		if permitido.contains(texto):
			resultado += texto
		if resultado.length() >= TAMANHO_MAXIMO_CODIGO_SALA:
			break
	return resultado


func esta_conectado() -> bool:
	return conectado


func esta_em_sala() -> bool:
	return em_sala


func sair_sala() -> void:
	_acao_pendente.clear()
	if _fusion != null and em_sala and _fusion.has_method(&"leave_room"):
		_fusion.call(&"leave_room")
		return
	_ao_sair_sala()


func definir_nome_local(novo_nome: String) -> void:
	var nome_limpo := _normalizar_nome_jogador(novo_nome)
	if nome_limpo.is_empty():
		nome_limpo = "JOGADOR"
	nome_jogador_local = nome_limpo
	if em_sala:
		_anunciar_estado_local()


func definir_pronto_local(valor: bool) -> void:
	if not em_sala or jogador_local_id <= 0:
		return
	pronto_local = valor
	_anunciar_estado_local()
	pronto_local_alterado.emit(pronto_local)


func alternar_pronto_local() -> void:
	definir_pronto_local(not pronto_local)


func obter_user_id_jogador(id_jogador: int) -> String:
	if jogadores_sala.has(id_jogador):
		return str(jogadores_sala[id_jogador].get("user_id", ""))
	if id_jogador == jogador_local_id:
		return _user_id_conexao
	return ""


func obter_user_id_local() -> String:
	# O mesmo identificador precisa sobreviver ao fechamento do jogo para que um
	# participante seja associado ao personagem correto ao retomar uma partida.
	if _user_id_conexao.is_empty():
		_user_id_conexao = _obter_ou_criar_user_id()
	return _user_id_conexao


func obter_nome_jogador(id_jogador: int) -> String:
	if jogadores_sala.has(id_jogador):
		return str(jogadores_sala[id_jogador].get("nome", "JOGADOR"))
	if id_jogador == jogador_local_id:
		return nome_jogador_local
	return "JOGADOR %d" % id_jogador


func obter_jogadores_sala() -> Array:
	var lista: Array = []
	for chave in jogadores_sala.keys():
		var dados: Dictionary = jogadores_sala[chave].duplicate(true)
		lista.append(dados)
	lista.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.get("host", false)) != bool(b.get("host", false)):
			return bool(a.get("host", false))
		return int(a.get("id", 0)) < int(b.get("id", 0))
	)
	return lista


func total_jogadores_sala() -> int:
	return jogadores_sala.size()


func todos_jogadores_prontos() -> bool:
	if jogadores_sala.size() < 2:
		return false
	for dados_variant in jogadores_sala.values():
		var dados: Dictionary = dados_variant
		if bool(dados.get("inativo", false)) or not bool(dados.get("pronto", false)):
			return false
	return true


func obter_resumo() -> Dictionary:
	return {
		"estado": int(estado),
		"estado_nome": _nome_estado(estado),
		"plugin_disponivel": plugin_disponivel,
		"configuracao_valida": configuracao_valida,
		"conectado": conectado,
		"em_sala": em_sala,
		"entrando_sala": entrando_sala,
		"app_id_mascarado": app_id_mascarado,
		"app_version": str(config.get("app_version", "")),
		"modo_autoridade": modo_autoridade_configurado,
		"default_region": str(config.get("default_region", "")),
		"codigo_sala": codigo_sala_atual,
		"jogador_local_id": jogador_local_id,
		"user_id_conexao": _user_id_conexao,
		"eh_host": eh_host,
		"nome_jogador_local": nome_jogador_local,
		"pronto_local": pronto_local,
		"total_jogadores": jogadores_sala.size(),
		"todos_prontos": todos_jogadores_prontos(),
		"jogadores": obter_jogadores_sala(),
		"mensagem": ultima_mensagem,
		"erro": ultimo_erro,
		"config_path": str(config.get("source_path", "Project Settings > Fusion > Connection")),
	}


func _iniciar_conexao() -> bool:
	recarregar_configuracao()
	var resultado := false

	if not plugin_disponivel:
		_falhar("O addon Photon Fusion Godot ainda não está instalado.")
	elif not configuracao_valida:
		_falhar(
			"App ID Photon ausente ou inválido em Project Settings > Fusion > Connection > App ID."
		)
	elif _fusion == null:
		_falhar("O addon foi detectado, mas o singleton Fusion não pôde ser obtido.")
	else:
		_atualizar_flags_da_api()
		if em_sala:
			_definir_estado(Estado.EM_SALA, "Você já está em uma sala Photon.")
			resultado = true
		elif conectado:
			_definir_estado(Estado.CONECTADO, "Já conectado ao Photon Cloud.")
			_executar_acao_pendente()
			resultado = true
		elif not _fusion.has_method(&"connect_to_photon"):
			_falhar("A versão instalada do addon não possui connect_to_photon().")
		else:
			_user_id_conexao = _obter_ou_criar_user_id()
			_definir_estado(
				Estado.CONECTANDO,
				"Conectando ao Photon Cloud com uma identidade exclusiva..."
			)
			_fusion.call(&"connect_to_photon", _user_id_conexao)
			resultado = true

	return resultado


func _executar_acao_pendente() -> void:
	if _acao_pendente.is_empty() or _fusion == null:
		return

	_atualizar_flags_da_api()
	if em_sala:
		_acao_pendente.clear()
		_definir_estado(Estado.EM_SALA, "Você já está conectado a uma sala Photon.")
		return
	if entrando_sala:
		return
	if not conectado:
		return

	var tipo := str(_acao_pendente.get("tipo", ""))
	if tipo != "entrar_ou_criar" and tipo != "partida_rapida":
		_acao_pendente.clear()
		return
	if not _fusion.has_method(&"join_or_create_room"):
		_falhar("A versão instalada do addon não possui join_or_create_room().")
		_acao_pendente.clear()
		return

	var codigo := str(_acao_pendente.get("codigo", ""))
	var max_jogadores := int(_acao_pendente.get("max_jogadores", 6))
	# Nome vazio solicita matchmaking aleatório no Fusion. Se não houver uma
	# sala compatível, join_or_create_room cria uma sessão nova.
	var nome_interno := "" if tipo == "partida_rapida" else _nome_interno_sala(codigo)
	var opcoes := {
		"max_players": max_jogadores,
		"is_visible": true,
		"is_open": true,
		"player_ttl_ms": 120000,
		"empty_room_ttl_ms": 30000,
		"game": "metropolis_in_ruins",
		"version": str(config.get("app_version", "0.34.0")),
		"lobby_properties": ["game", "version"],
	}

	codigo_sala_atual = codigo
	entrando_sala = true
	_definir_estado(
		Estado.ENTRANDO_SALA,
		"Procurando partida rápida..."
		if tipo == "partida_rapida"
		else "Entrando ou criando a sala %s..." % codigo
	)
	_fusion.call(&"join_or_create_room", nome_interno, opcoes)
	_acao_pendente.clear()


func _detectar_plugin() -> bool:
	return Engine.has_singleton("Fusion") or get_node_or_null("/root/Fusion") != null


func _obter_singleton_fusion() -> void:
	if Engine.has_singleton("Fusion"):
		_fusion = Engine.get_singleton("Fusion")
	else:
		_fusion = get_node_or_null("/root/Fusion")
	if _fusion == null:
		_sinais_conectados = false
	elif _fusion is Node:
		(_fusion as Node).process_mode = Node.PROCESS_MODE_ALWAYS


func _conectar_sinais() -> void:
	if _fusion == null or _sinais_conectados:
		return
	_conectar_sinal(&"connected_to_photon", Callable(self, "_ao_conectado_photon"))
	_conectar_sinal(&"connection_failed", Callable(self, "_ao_falha_conexao"))
	_conectar_sinal(&"connection_status_changed", Callable(self, "_ao_status_conexao_mudou"))
	_conectar_sinal(&"room_joined", Callable(self, "_ao_entrar_sala"))
	_conectar_sinal(&"room_left", Callable(self, "_ao_sair_sala"))
	_conectar_sinal(&"player_left", Callable(self, "_ao_jogador_sair"))
	_registrar_broadcast_receiver()
	_sinais_conectados = true


func _conectar_sinal(nome: StringName, callback: Callable) -> void:
	if _fusion == null or not _fusion.has_signal(nome):
		return
	if not _fusion.is_connected(nome, callback):
		_fusion.connect(nome, callback)


func _ao_conectado_photon() -> void:
	conectado = true
	_definir_estado(Estado.CONECTADO, "Conectado ao Photon Cloud.")
	conectado_ao_photon.emit()
	_executar_acao_pendente()


func _ao_falha_conexao(erro: String) -> void:
	_atualizar_flags_da_api()
	entrando_sala = false

	var erro_normalizado := erro.to_lower()
	if erro_normalizado.contains("already joined") or erro_normalizado.contains("active joiner"):
		if em_sala:
			_ao_entrar_sala()
			return
		_falhar(
			"Esta identidade Photon já está ativa nessa sala. Feche a outra instância "
			+ "do jogo ou aguarde a vaga antiga expirar. Em builds de depuração, "
			+ "a V36 passa a gerar uma identidade diferente para cada processo."
		)
		return

	conectado = _chamar_bool(&"is_connected_to_photon", false)
	em_sala = false
	codigo_sala_atual = ""
	_falhar("Falha na conexão Photon: %s" % erro)


func _ao_status_conexao_mudou(status: int) -> void:
	# Estados oficiais do SDK: 0 desconectado, 1 conectando, 2 conectado,
	# 3 entrando na sala, 4 em sala e 5 erro.
	match status:
		0:
			conectado = false
			em_sala = false
			entrando_sala = false
			if not _desconexao_intencional:
				_definir_estado(Estado.PRONTO, "Desconectado do Photon Cloud.")
		1:
			_definir_estado(Estado.CONECTANDO, "Conectando ao Photon Cloud...")
		2:
			conectado = true
			_definir_estado(Estado.CONECTADO, "Conectado ao Photon Cloud.")
		3:
			entrando_sala = true
			_definir_estado(Estado.ENTRANDO_SALA, "Entrando na sala Photon...")
		4:
			conectado = true
			em_sala = true
			entrando_sala = false
		5:
			_falhar("Photon informou um erro de conexão.")


func _ao_entrar_sala() -> void:
	conectado = true
	em_sala = true
	entrando_sala = false
	jogador_local_id = _chamar_int(&"get_local_player_id", 0)
	var host_anterior := eh_host
	eh_host = _chamar_bool(&"is_master_client", false)
	nome_jogador_local = _obter_nome_perfil()
	pronto_local = false
	_limpar_lobby_online()
	_registrar_broadcast_receiver()
	_definir_estado(
		Estado.EM_SALA,
		"Sala %s conectada. Você é %s." % [
			codigo_sala_atual,
			"o host" if eh_host else "cliente",
		]
	)
	if host_anterior != eh_host:
		host_alterado.emit(eh_host)
	sala_entrada.emit(codigo_sala_atual, jogador_local_id, eh_host)
	call_deferred("_iniciar_handshake_lobby")


func _ao_sair_sala() -> void:
	em_sala = false
	entrando_sala = false
	codigo_sala_atual = ""
	jogador_local_id = 0
	var era_host := eh_host
	eh_host = false
	_limpar_lobby_online()
	if era_host:
		host_alterado.emit(false)
	_atualizar_flags_da_api()
	_definir_estado(
		Estado.CONECTADO if conectado else Estado.PRONTO,
		"Você saiu da sala Photon."
	)
	sala_saida.emit()


func _ao_jogador_sair(id_jogador: int, inativo: bool) -> void:
	if jogadores_sala.has(id_jogador):
		if inativo:
			var dados: Dictionary = jogadores_sala[id_jogador]
			dados["inativo"] = true
			dados["pronto"] = false
			jogadores_sala[id_jogador] = dados
		else:
			jogadores_sala.erase(id_jogador)
		_emitir_lista_jogadores()
	jogador_saiu.emit(id_jogador, inativo)
	call_deferred("_reavaliar_master_client")


func _atualizar_flags_da_api() -> void:
	if _fusion == null:
		conectado = false
		em_sala = false
		return
	conectado = _chamar_bool(&"is_connected_to_photon", conectado)
	em_sala = _chamar_bool(&"is_in_room", em_sala)
	if em_sala:
		jogador_local_id = _chamar_int(&"get_local_player_id", jogador_local_id)
		var host_anterior := eh_host
		eh_host = _chamar_bool(&"is_master_client", eh_host)
		if host_anterior != eh_host:
			host_alterado.emit(eh_host)
			_anunciar_estado_local()


func _chamar_bool(metodo: StringName, padrao: bool) -> bool:
	if _fusion == null or not _fusion.has_method(metodo):
		return padrao
	return bool(_fusion.call(metodo))


func _chamar_int(metodo: StringName, padrao: int) -> int:
	if _fusion == null or not _fusion.has_method(metodo):
		return padrao
	return int(_fusion.call(metodo))


func _registrar_broadcast_receiver() -> void:
	if _fusion == null or _broadcast_registrado:
		return
	if not _fusion.has_method(&"register_broadcast_receiver"):
		return
	_fusion.call(&"register_broadcast_receiver", self)
	_broadcast_registrado = true


func _iniciar_handshake_lobby() -> void:
	if not em_sala or jogador_local_id <= 0:
		return
	_anunciar_estado_local()
	# A versão preview ainda não expõe player_joined. Repetir o anúncio em
	# pequenos intervalos torna o handshake confiável mesmo quando dois clientes
	# concluem a entrada quase ao mesmo tempo.
	_sequencia_anuncio += 1
	var sequencia := _sequencia_anuncio
	for atraso in [0.20, 0.70, 1.50]:
		await get_tree().create_timer(float(atraso)).timeout
		if sequencia != _sequencia_anuncio or not em_sala:
			return
		_anunciar_estado_local()


func _anunciar_estado_local() -> void:
	if not em_sala or jogador_local_id <= 0 or _fusion == null:
		return
	if not _fusion.has_method(&"rpc"):
		return
	_fusion.call(
		&"rpc",
		Callable(self, "_rpc_lobby_anunciar_jogador"),
		jogador_local_id,
		_user_id_conexao,
		nome_jogador_local,
		pronto_local,
		eh_host
	)


func _responder_estado_para(jogador_destino: int) -> void:
	if not em_sala or jogador_destino <= 0 or _fusion == null:
		return
	if not _fusion.has_method(&"rpc_to_player"):
		return
	_fusion.call(
		&"rpc_to_player",
		jogador_destino,
		Callable(self, "_rpc_lobby_anunciar_jogador"),
		jogador_local_id,
		_user_id_conexao,
		nome_jogador_local,
		pronto_local,
		eh_host
	)


@rpc("any_peer", "call_local")
func _rpc_lobby_anunciar_jogador(
	id_jogador: int,
	user_id: String,
	nome: String,
	pronto: bool,
	host: bool
) -> void:
	if not em_sala or id_jogador <= 0:
		return
	var era_novo := not jogadores_sala.has(id_jogador)
	var id_antigo_mesmo_usuario := 0
	if not user_id.is_empty():
		for chave_existente in jogadores_sala.keys():
			var existente: Dictionary = jogadores_sala[chave_existente]
			if int(chave_existente) == id_jogador:
				continue
			if str(existente.get("user_id", "")) == user_id:
				id_antigo_mesmo_usuario = int(chave_existente)
				jogadores_sala.erase(chave_existente)
				break
	var nome_limpo := _normalizar_nome_jogador(nome)
	if nome_limpo.is_empty():
		nome_limpo = "JOGADOR %d" % id_jogador
	jogadores_sala[id_jogador] = {
		"id": id_jogador,
		"user_id": user_id.left(48),
		"nome": nome_limpo,
		"pronto": pronto,
		"host": host,
		"inativo": false,
	}
	if id_jogador == jogador_local_id:
		pronto_local = pronto
		nome_jogador_local = nome_limpo
	_emitir_lista_jogadores()
	if id_antigo_mesmo_usuario > 0:
		jogador_reconectado.emit(id_antigo_mesmo_usuario, id_jogador, user_id)
	if era_novo:
		jogador_descoberto.emit(jogadores_sala[id_jogador].duplicate(true))

	# Como o preview não tem player_joined, cada peer já presente responde ao
	# recém-chegado diretamente. Assim ele monta a lista completa sem polling.
	if era_novo and id_jogador != jogador_local_id:
		call_deferred("_responder_estado_para", id_jogador)


func _emitir_lista_jogadores() -> void:
	jogadores_sala_alterados.emit(obter_jogadores_sala())
	estado_alterado.emit(obter_resumo())


func _limpar_lobby_online() -> void:
	_sequencia_anuncio += 1
	jogadores_sala.clear()
	pronto_local = false
	jogadores_sala_alterados.emit([])
	pronto_local_alterado.emit(false)


func _reavaliar_master_client() -> void:
	if not em_sala:
		return
	await get_tree().process_frame
	var host_anterior := eh_host
	eh_host = _chamar_bool(&"is_master_client", eh_host)
	if host_anterior != eh_host:
		host_alterado.emit(eh_host)
	_anunciar_estado_local()


func _obter_nome_perfil() -> String:
	var nome := "JOGADOR"
	var progressao := get_node_or_null("/root/Progressao")
	if progressao != null and progressao.has_method(&"obter_perfil"):
		var perfil_variant = progressao.call(&"obter_perfil")
		if perfil_variant is Dictionary:
			nome = str(perfil_variant.get("nome", nome))
	return _normalizar_nome_jogador(nome)


func _normalizar_nome_jogador(valor: String) -> String:
	var limpo := valor.strip_edges()
	limpo = limpo.replace("\n", " ").replace("\r", " ").replace("\t", " ")
	while limpo.contains("  "):
		limpo = limpo.replace("  ", " ")
	return limpo.left(18)


func _carregar_configuracao() -> Dictionary:
	# O Fusion Godot 3 atual lê as credenciais diretamente das configurações
	# do projeto. Essa é a fonte principal e evita exigir o App ID duas vezes.
	var dados_project_settings := {
		"app_id": str(
			ProjectSettings.get_setting("fusion/connection/app_id", "")
		).strip_edges(),
		"app_version": str(
			ProjectSettings.get_setting("fusion/connection/app_version", "0.34.0")
		).strip_edges(),
		"default_region": str(
			ProjectSettings.get_setting("fusion/connection/default_region", "")
		).strip_edges(),
		"source_path": "Project Settings > Fusion > Connection",
	}

	if _validar_configuracao(dados_project_settings):
		return dados_project_settings

	# Compatibilidade com a configuração antiga da V34. O arquivo em user://
	# só é consultado quando o App ID não está configurado no Project Settings.
	var caminho := CAMINHO_CONFIG_PROJETO
	if FileAccess.file_exists(CAMINHO_CONFIG_USUARIO):
		caminho = CAMINHO_CONFIG_USUARIO

	var arquivo := ConfigFile.new()
	if arquivo.load(caminho) != OK:
		return dados_project_settings

	return {
		"app_id": str(arquivo.get_value("PHOTON", "app_id", "")).strip_edges(),
		"app_version": str(arquivo.get_value("PHOTON", "app_version", "0.34.0")).strip_edges(),
		"default_region": str(arquivo.get_value("PHOTON", "default_region", "")).strip_edges(),
		"source_path": caminho,
	}


func _validar_configuracao(dados: Dictionary) -> bool:
	var app_id := str(dados.get("app_id", "")).strip_edges()
	if app_id.is_empty() or app_id.begins_with("COLE_"):
		return false
	# App IDs do Photon são UUIDs; aceitamos também valores sem hífen para não
	# bloquear formatos futuros do painel.
	return app_id.length() >= 20


func _aplicar_configuracao_ao_project_settings() -> void:
	if not configuracao_valida:
		return

	# O SDK atual se inicializa automaticamente a partir do Project Settings.
	# set_app_id() é usado somente como compatibilidade quando a configuração
	# veio do arquivo legado da V34 ou de user://.
	var origem := str(config.get("source_path", ""))
	if origem != "Project Settings > Fusion > Connection":
		ProjectSettings.set_setting("fusion/connection/app_id", str(config.get("app_id", "")))
		ProjectSettings.set_setting(
			"fusion/connection/app_version", str(config.get("app_version", "0.34.0"))
		)
		ProjectSettings.set_setting(
			"fusion/connection/default_region", str(config.get("default_region", ""))
		)
		if _fusion != null and _fusion.has_method(&"set_app_id"):
			_fusion.call(&"set_app_id", str(config.get("app_id", "")))

	modo_autoridade_configurado = _configurar_modo_autoridade()


func _configurar_modo_autoridade() -> bool:
	const CAMINHO_MODO := "fusion/simulation/mode"
	if not ProjectSettings.has_setting(CAMINHO_MODO):
		return false

	for propriedade in ProjectSettings.get_property_list():
		if str(propriedade.get("name", "")) != CAMINHO_MODO:
			continue
		var opcoes := str(propriedade.get("hint_string", "")).split(",")
		for indice in range(opcoes.size()):
			var nome_opcao := str(opcoes[indice]).split(":")[0].strip_edges()
			if nome_opcao.to_lower() == "authority":
				ProjectSettings.set_setting(CAMINHO_MODO, indice)
				return true
	return false


func _obter_ou_criar_user_id() -> String:
	var id_base := _obter_ou_criar_user_id_persistente()

	# Permite testes determinísticos usando, por exemplo:
	# --photon-test-slot=cliente2
	for argumento in OS.get_cmdline_user_args():
		if argumento.begins_with(PREFIXO_ARGUMENTO_USER_ID):
			var valor := argumento.trim_prefix(PREFIXO_ARGUMENTO_USER_ID)
			var id_manual := _normalizar_fragmento_user_id(valor)
			if not id_manual.is_empty():
				return "metro_%s" % id_manual
		if argumento.begins_with(PREFIXO_ARGUMENTO_TESTE):
			var slot := argumento.trim_prefix(PREFIXO_ARGUMENTO_TESTE)
			var slot_limpo := _normalizar_fragmento_user_id(slot)
			if not slot_limpo.is_empty():
				return ("%s_%s" % [id_base, slot_limpo]).left(48)

	# Em testes com várias janelas, use --photon-test-slot=host/cliente2. Um
	# sufixo baseado no processo tornava o ID diferente a cada reinício e impedia
	# reconhecer os jogadores de uma partida salva.
	return id_base


func _obter_ou_criar_user_id_persistente() -> String:
	if FileAccess.file_exists(CAMINHO_ID_USUARIO):
		var leitura := FileAccess.open(CAMINHO_ID_USUARIO, FileAccess.READ)
		if leitura != null:
			var existente := leitura.get_as_text().strip_edges()
			if not existente.is_empty():
				return existente

	var origem := "%s|%s|%s|%d|%d" % [
		OS.get_name(),
		OS.get_model_name(),
		OS.get_locale(),
		int(Time.get_unix_time_from_system()),
		randi(),
	]
	var novo_id := "metro_%s" % origem.sha256_text().substr(0, 24)
	var escrita := FileAccess.open(CAMINHO_ID_USUARIO, FileAccess.WRITE)
	if escrita != null:
		escrita.store_string(novo_id)
	return novo_id


func _normalizar_fragmento_user_id(valor: String) -> String:
	var resultado := ""
	for caractere in valor.strip_edges().to_lower():
		var texto := str(caractere)
		if "abcdefghijklmnopqrstuvwxyz0123456789_-".contains(texto):
			resultado += texto
		if resultado.length() >= 32:
			break
	return resultado


func _nome_interno_sala(codigo: String) -> String:
	var versao := str(config.get("app_version", "0.34.0")).replace(".", "_")
	return "metro_%s_%s" % [versao, codigo.to_lower()]


func _mascarar_app_id(app_id: String) -> String:
	var valor := app_id.strip_edges()
	if valor.is_empty() or valor.begins_with("COLE_"):
		return "—"
	if valor.length() <= 12:
		return valor
	return "%s...%s" % [valor.left(8), valor.right(4)]


func _liberar_desconexao_intencional() -> void:
	_desconexao_intencional = false


func _definir_estado(novo_estado: Estado, mensagem: String) -> void:
	estado = novo_estado
	ultima_mensagem = mensagem
	if novo_estado != Estado.ERRO:
		ultimo_erro = ""
	estado_alterado.emit(obter_resumo())
	print("[PHOTON] " + mensagem)


func _falhar(mensagem: String) -> void:
	estado = Estado.ERRO
	ultima_mensagem = mensagem
	ultimo_erro = mensagem
	push_error("[PHOTON] " + mensagem)
	erro_photon.emit(mensagem)
	estado_alterado.emit(obter_resumo())


func _nome_estado(valor: Estado) -> String:
	var nomes := {
		Estado.PLUGIN_AUSENTE: "PLUGIN AUSENTE",
		Estado.CONFIGURACAO_INCOMPLETA: "CONFIGURAÇÃO INCOMPLETA",
		Estado.PRONTO: "PRONTO",
		Estado.CONECTANDO: "CONECTANDO",
		Estado.CONECTADO: "CONECTADO",
		Estado.ENTRANDO_SALA: "ENTRANDO NA SALA",
		Estado.EM_SALA: "EM SALA",
		Estado.ERRO: "ERRO",
	}
	return str(nomes.get(valor, "DESCONHECIDO"))
