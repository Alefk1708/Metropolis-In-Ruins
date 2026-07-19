extends Node

## Salvamento persistente da partida online.
##
## Somente o host grava o snapshot autoritativo. O arquivo usa escrita atômica,
## checksum e uma cópia de segurança para que uma interrupção durante a gravação
## não destrua o último salvamento válido.

signal salvamento_concluido(sucesso: bool, mensagem: String)

const VERSAO_FORMATO: int = 1
const ASSINATURA_ARQUIVO: String = "METROPOLIS_IN_RUINS_SAVE"
const CAMINHO_SALVAMENTO: String = "user://partida_online_salva.mirsave"
const CAMINHO_TEMPORARIO: String = "user://partida_online_salva.tmp"
const CAMINHO_BACKUP: String = "user://partida_online_salva.bak"
const TAMANHO_MAXIMO_ARQUIVO: int = 16 * 1024 * 1024
const INTERVALO_AUTOSSALVAMENTO_MS: int = 15000
const ATRASO_ESTADO_ALTERADO_MS: int = 1200
const ATRASO_PRIMEIRO_AUTOSSALVAMENTO_MS: int = 3500

var _tabuleiro_registrado: Node = null
var _registro_cache: Dictionary = {}
var _sessao_atual_id: String = ""
var _estado_sujo: bool = false
var _salvando: bool = false
var _ultimo_salvamento_ms: int = 0
var _proximo_salvamento_ms: int = 0

var _retomada_preparada: bool = false
var _codigo_sala_retomada: String = ""
var _snapshot_retomada_pendente: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_registro_cache = _carregar_melhor_registro()


func _process(_delta: float) -> void:
	if _salvando or not _tabuleiro_valido():
		return
	if not OnlineTransport.usando_photon() or not OnlineTransport.is_host():
		return

	var agora_ms: int = Time.get_ticks_msec()
	var intervalo_expirou: bool = (
		_ultimo_salvamento_ms <= 0
		or agora_ms - _ultimo_salvamento_ms >= INTERVALO_AUTOSSALVAMENTO_MS
	)
	if agora_ms < _proximo_salvamento_ms:
		return
	if not _estado_sujo and not intervalo_expirou:
		return

	var resultado: Dictionary = salvar_partida(_tabuleiro_registrado, "automatico")
	if not bool(resultado.get("sucesso", false)):
		# Estados transitórios (movimento, leilão ou decisão aberta) apenas
		# adiam o autosave. Evita tentar gravar novamente a cada frame.
		_proximo_salvamento_ms = agora_ms + 2500


func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_PAUSED and what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	if not _tabuleiro_valido() or _salvando:
		return
	if OnlineTransport.usando_photon() and OnlineTransport.is_host():
		salvar_partida(_tabuleiro_registrado, "suspensao")


func registrar_tabuleiro(tabuleiro: Node) -> void:
	if tabuleiro == null:
		return
	_tabuleiro_registrado = tabuleiro
	if not _snapshot_retomada_pendente.is_empty():
		_sessao_atual_id = str(_registro_cache.get("sessao_id", ""))
	else:
		_sessao_atual_id = _gerar_id_sessao()
	_estado_sujo = true
	_ultimo_salvamento_ms = 0
	_proximo_salvamento_ms = (
		Time.get_ticks_msec() + ATRASO_PRIMEIRO_AUTOSSALVAMENTO_MS
	)


func desregistrar_tabuleiro(tabuleiro: Node) -> void:
	if _tabuleiro_registrado != tabuleiro:
		return
	_tabuleiro_registrado = null
	_estado_sujo = false
	_proximo_salvamento_ms = 0


func marcar_estado_alterado(tabuleiro: Node) -> void:
	if tabuleiro == null or tabuleiro != _tabuleiro_registrado:
		return
	if not OnlineTransport.usando_photon() or not OnlineTransport.is_host():
		return
	_estado_sujo = true
	var novo_prazo: int = Time.get_ticks_msec() + ATRASO_ESTADO_ALTERADO_MS
	if _proximo_salvamento_ms <= 0:
		_proximo_salvamento_ms = novo_prazo
	else:
		_proximo_salvamento_ms = mini(_proximo_salvamento_ms, novo_prazo)


func salvar_partida(tabuleiro: Node, motivo: String = "manual") -> Dictionary:
	if _salvando:
		return _resultado(false, "UM SALVAMENTO JÁ ESTÁ EM ANDAMENTO")
	if tabuleiro == null or not is_instance_valid(tabuleiro):
		return _resultado(false, "O TABULEIRO NÃO ESTÁ DISPONÍVEL")
	if not OnlineTransport.usando_photon():
		return _resultado(false, "O SALVAMENTO RETOMÁVEL EXIGE UMA SALA ONLINE")
	if not OnlineTransport.is_host():
		return _resultado(false, "SOMENTE O HOST PODE GRAVAR O ESTADO DA PARTIDA")
	if not tabuleiro.has_method(&"criar_snapshot_online"):
		return _resultado(false, "O TABULEIRO NÃO FORNECE UM SNAPSHOT VÁLIDO")

	if tabuleiro.has_method(&"validar_salvamento_partida"):
		var bloqueio_variant: Variant = tabuleiro.call(&"validar_salvamento_partida")
		var bloqueio: String = str(bloqueio_variant).strip_edges()
		if not bloqueio.is_empty():
			return _resultado(false, bloqueio)

	_salvando = true
	var snapshot_variant: Variant = tabuleiro.call(&"criar_snapshot_online")
	if not snapshot_variant is Dictionary:
		_salvando = false
		return _resultado(false, "NÃO FOI POSSÍVEL GERAR O SNAPSHOT DA PARTIDA")

	var snapshot: Dictionary = _normalizar_snapshot_para_salvamento(snapshot_variant)
	var participantes: Array = _coletar_participantes(snapshot)
	var escolhas_por_usuario: Dictionary = Dictionary(
		snapshot.get("escolhas_por_user_id", {})
	)
	if (
		participantes.size() < 2
		or participantes.size() > 6
		or participantes.size() != escolhas_por_usuario.size()
	):
		_salvando = false
		return _resultado(false, "NÃO FOI POSSÍVEL IDENTIFICAR TODOS OS PARTICIPANTES")

	var host_user_id: String = PhotonManager.obter_user_id_local()
	if host_user_id.is_empty():
		_salvando = false
		return _resultado(false, "A IDENTIDADE PERSISTENTE DO HOST NÃO ESTÁ DISPONÍVEL")

	if _sessao_atual_id.is_empty():
		_sessao_atual_id = _gerar_id_sessao()

	var estado: Dictionary = Dictionary(snapshot.get("estado", {}))
	var agora_unix: int = int(Time.get_unix_time_from_system())
	var registro: Dictionary = {
		"versao": VERSAO_FORMATO,
		"sessao_id": _sessao_atual_id,
		"salvo_em_unix": agora_unix,
		"motivo": motivo,
		"codigo_sala_anterior": PhotonManager.codigo_sala_atual,
		"host_user_id": host_user_id,
		"host_nome": PhotonManager.obter_nome_jogador(PhotonManager.jogador_local_id),
		"rodada": int(estado.get("rodada_atual", 1)),
		"jogador_atual_id": str(estado.get("jogador_atual_id", "")),
		"participantes": participantes,
		"snapshot": snapshot,
	}
	var erro_registro: String = _validar_registro(registro)
	if not erro_registro.is_empty():
		_salvando = false
		return _resultado(false, erro_registro)

	var gravado: bool = _escrever_registro_atomico(registro)
	_salvando = false
	if not gravado:
		var falha: Dictionary = _resultado(false, "NÃO FOI POSSÍVEL GRAVAR A PARTIDA")
		salvamento_concluido.emit(false, str(falha.get("mensagem", "")))
		return falha

	_registro_cache = registro.duplicate(true)
	_estado_sujo = false
	_ultimo_salvamento_ms = Time.get_ticks_msec()
	_proximo_salvamento_ms = _ultimo_salvamento_ms + INTERVALO_AUTOSSALVAMENTO_MS
	var mensagem: String = "PARTIDA SALVA COM SEGURANÇA"
	var sucesso: Dictionary = _resultado(true, mensagem)
	sucesso["resumo"] = obter_resumo_partida_salva()
	salvamento_concluido.emit(true, mensagem)
	return sucesso


func tem_partida_salva() -> bool:
	return not _registro_cache.is_empty()


func pode_retomar_nesta_instalacao() -> bool:
	if _registro_cache.is_empty():
		return false
	var dono_salvamento: String = str(_registro_cache.get("host_user_id", ""))
	return not dono_salvamento.is_empty() and dono_salvamento == PhotonManager.obter_user_id_local()


func obter_resumo_partida_salva() -> Dictionary:
	if _registro_cache.is_empty():
		return {}
	var participantes: Array = Array(_registro_cache.get("participantes", [])).duplicate(true)
	var salvo_em: int = int(_registro_cache.get("salvo_em_unix", 0))
	return {
		"sessao_id": str(_registro_cache.get("sessao_id", "")),
		"salvo_em_unix": salvo_em,
		"salvo_em_texto": _formatar_data_hora(salvo_em),
		"rodada": int(_registro_cache.get("rodada", 1)),
		"jogador_atual_id": str(_registro_cache.get("jogador_atual_id", "")),
		"quantidade_participantes": participantes.size(),
		"participantes": participantes,
		"pode_retomar": pode_retomar_nesta_instalacao(),
	}


func preparar_sala_retomada(codigo_sala: String) -> Dictionary:
	if not tem_partida_salva():
		return _resultado(false, "NENHUMA PARTIDA SALVA FOI ENCONTRADA")
	if not pode_retomar_nesta_instalacao():
		return _resultado(false, "ESTE SALVAMENTO PERTENCE AO HOST ORIGINAL")

	var codigo: String = PhotonManager.normalizar_codigo_sala(codigo_sala)
	if codigo.length() < PhotonManager.TAMANHO_MINIMO_CODIGO_SALA:
		return _resultado(false, "NÃO FOI POSSÍVEL GERAR A SALA DE RETOMADA")

	_retomada_preparada = true
	_codigo_sala_retomada = codigo
	_snapshot_retomada_pendente.clear()
	var resultado: Dictionary = _resultado(true, "SALA DE RETOMADA PREPARADA")
	resultado["codigo_sala"] = codigo
	resultado["contexto"] = obter_contexto_publico_retomada()
	return resultado


func cancelar_preparacao_retomada() -> void:
	_retomada_preparada = false
	_codigo_sala_retomada = ""
	_snapshot_retomada_pendente.clear()


func retomada_em_preparacao() -> bool:
	return _retomada_preparada and not _registro_cache.is_empty()


func obter_contexto_publico_retomada() -> Dictionary:
	if not retomada_em_preparacao():
		return {}
	var resumo: Dictionary = obter_resumo_partida_salva()
	return {
		"sessao_id": str(resumo.get("sessao_id", "")),
		"codigo_sala": _codigo_sala_retomada,
		"salvo_em_unix": int(resumo.get("salvo_em_unix", 0)),
		"salvo_em_texto": str(resumo.get("salvo_em_texto", "")),
		"rodada": int(resumo.get("rodada", 1)),
		"jogador_atual_id": str(resumo.get("jogador_atual_id", "")),
		"participantes": Array(resumo.get("participantes", [])).duplicate(true),
	}


func preparar_snapshot_retomada(jogadores_sala: Array) -> Dictionary:
	if not retomada_em_preparacao() or _registro_cache.is_empty():
		return _resultado(false, "A RETOMADA NÃO ESTÁ PREPARADA")
	if not OnlineTransport.usando_photon() or not OnlineTransport.is_host():
		return _resultado(false, "SOMENTE O HOST PODE RETOMAR A PARTIDA")

	var peer_por_user_id: Dictionary = {}
	for jogador_variant in jogadores_sala:
		if not jogador_variant is Dictionary:
			continue
		var jogador: Dictionary = jogador_variant
		if bool(jogador.get("inativo", false)):
			continue
		var user_id: String = str(jogador.get("user_id", ""))
		var peer_id: int = int(jogador.get("id", 0))
		if user_id.is_empty() or peer_id <= 0:
			continue
		if peer_por_user_id.has(user_id):
			return _resultado(false, "UM PARTICIPANTE ENTROU DUAS VEZES NA SALA")
		peer_por_user_id[user_id] = peer_id

	var participantes: Array = Array(_registro_cache.get("participantes", []))
	var ids_esperados: Array[String] = []
	var escolhas: Dictionary = {}
	var usuarios: Dictionary = {}
	var escolhas_por_usuario: Dictionary = {}
	for participante_variant in participantes:
		if not participante_variant is Dictionary:
			continue
		var participante: Dictionary = participante_variant
		var user_id: String = str(participante.get("user_id", ""))
		var personagem: String = str(participante.get("personagem", ""))
		if user_id.is_empty() or personagem.is_empty():
			return _resultado(false, "O SALVAMENTO POSSUI UM PARTICIPANTE INVÁLIDO")
		ids_esperados.append(user_id)
		if not peer_por_user_id.has(user_id):
			return _resultado(false, "AINDA FALTAM PARTICIPANTES DA PARTIDA SALVA")
		var peer_id: int = int(peer_por_user_id[user_id])
		escolhas[peer_id] = personagem
		usuarios[peer_id] = user_id
		escolhas_por_usuario[user_id] = personagem

	for user_id_variant in peer_por_user_id.keys():
		var user_id: String = str(user_id_variant)
		if not ids_esperados.has(user_id):
			return _resultado(false, "HÁ UM JOGADOR QUE NÃO PARTICIPAVA DA PARTIDA SALVA")

	var snapshot_variant: Variant = _registro_cache.get("snapshot", {})
	if not snapshot_variant is Dictionary:
		return _resultado(false, "O SNAPSHOT SALVO É INVÁLIDO")
	var snapshot: Dictionary = snapshot_variant.duplicate(true)
	snapshot["criado_em_ms"] = Time.get_ticks_msec()
	snapshot["escolhas_da_mesa"] = escolhas.duplicate(true)
	snapshot["user_ids_da_mesa"] = usuarios.duplicate(true)
	snapshot["escolhas_por_user_id"] = escolhas_por_usuario.duplicate(true)
	_snapshot_retomada_pendente = snapshot
	_sessao_atual_id = str(_registro_cache.get("sessao_id", ""))

	var resultado: Dictionary = _resultado(true, "TODOS OS PARTICIPANTES FORAM CONFIRMADOS")
	resultado["escolhas_da_mesa"] = escolhas
	resultado["user_ids_da_mesa"] = usuarios
	resultado["escolhas_por_user_id"] = escolhas_por_usuario
	return resultado


func consumir_snapshot_retomada() -> Dictionary:
	if _snapshot_retomada_pendente.is_empty():
		return {}
	var snapshot: Dictionary = _snapshot_retomada_pendente.duplicate(true)
	_snapshot_retomada_pendente.clear()
	return snapshot


func confirmar_retomada_carregada() -> void:
	_retomada_preparada = false
	_codigo_sala_retomada = ""
	_estado_sujo = true
	_proximo_salvamento_ms = Time.get_ticks_msec() + ATRASO_ESTADO_ALTERADO_MS


func marcar_partida_finalizada() -> void:
	if not OnlineTransport.usando_photon() or not OnlineTransport.is_host():
		return
	if _registro_cache.is_empty():
		return
	# Ao concluir qualquer partida hospedada nesta instalação, um salvamento
	# anterior não pode continuar aparecendo como se ainda fosse retomável.
	remover_partida_salva()


func remover_partida_salva() -> bool:
	var exclusao_concluida: bool = true
	var caminhos_persistentes: Array[String] = [
		CAMINHO_SALVAMENTO,
		CAMINHO_BACKUP,
	]
	for caminho in caminhos_persistentes:
		if not FileAccess.file_exists(caminho):
			continue
		var erro_remocao: Error = DirAccess.remove_absolute(
			ProjectSettings.globalize_path(caminho)
		)
		if erro_remocao != OK and FileAccess.file_exists(caminho):
			exclusao_concluida = false

	# O temporário nunca é usado para retomada. Sua remoção é apenas uma limpeza
	# adicional e não invalida a exclusão dos salvamentos principal e reserva.
	if FileAccess.file_exists(CAMINHO_TEMPORARIO):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CAMINHO_TEMPORARIO))

	if not exclusao_concluida:
		_registro_cache = _carregar_melhor_registro()
		return false

	_registro_cache.clear()
	_snapshot_retomada_pendente.clear()
	_retomada_preparada = false
	_codigo_sala_retomada = ""
	_sessao_atual_id = ""
	_estado_sujo = false
	return true


func _tabuleiro_valido() -> bool:
	return _tabuleiro_registrado != null and is_instance_valid(_tabuleiro_registrado)


func _resultado(sucesso: bool, mensagem: String) -> Dictionary:
	return {"sucesso": sucesso, "mensagem": mensagem}


func _gerar_id_sessao() -> String:
	var origem: String = "%d|%d|%d|%s" % [
		int(Time.get_unix_time_from_system()),
		Time.get_ticks_msec(),
		randi(),
		PhotonManager.obter_user_id_local(),
	]
	return origem.sha256_text().left(24)


func _normalizar_snapshot_para_salvamento(snapshot_original: Dictionary) -> Dictionary:
	var snapshot: Dictionary = snapshot_original.duplicate(true)
	var estado: Dictionary = Dictionary(snapshot.get("estado", {})).duplicate(true)
	# O menu de pausa está necessariamente aberto no salvamento manual. A partida
	# deve voltar em um turno jogável, nunca presa ao peer numérico da sala antiga.
	estado["_pausa_global_ativa"] = false
	estado["_peer_iniciador_pausa"] = 0
	estado["_personagem_iniciador_pausa"] = ""
	estado["_nome_iniciador_pausa"] = ""
	estado["_partida_encerrada"] = false
	snapshot["estado"] = estado
	snapshot["criado_em_ms"] = 0
	return snapshot


func _coletar_participantes(snapshot: Dictionary) -> Array:
	var participantes: Array = []
	var escolhas_usuario: Dictionary = Dictionary(
		snapshot.get("escolhas_por_user_id", {})
	)
	var nomes_por_usuario: Dictionary = {}
	for jogador_variant in PhotonManager.obter_jogadores_sala():
		if not jogador_variant is Dictionary:
			continue
		var jogador: Dictionary = jogador_variant
		var user_id: String = str(jogador.get("user_id", ""))
		if not user_id.is_empty():
			nomes_por_usuario[user_id] = str(jogador.get("nome", "JOGADOR"))

	var estado: Dictionary = Dictionary(snapshot.get("estado", {}))
	var ordem_personagens: Array = Array(estado.get("ordem_original_partida", []))
	var usuarios_adicionados: Array[String] = []
	for personagem_variant in ordem_personagens:
		var personagem: String = str(personagem_variant)
		var user_id_encontrado: String = ""
		for user_id_variant in escolhas_usuario.keys():
			var user_id: String = str(user_id_variant)
			if str(escolhas_usuario[user_id_variant]) == personagem:
				user_id_encontrado = user_id
				break
		if user_id_encontrado.is_empty():
			continue
		usuarios_adicionados.append(user_id_encontrado)
		participantes.append({
			"user_id": user_id_encontrado,
			"nome": str(nomes_por_usuario.get(user_id_encontrado, personagem.capitalize())),
			"personagem": personagem,
		})

	for user_id_variant in escolhas_usuario.keys():
		var user_id: String = str(user_id_variant)
		if user_id.is_empty() or usuarios_adicionados.has(user_id):
			continue
		var personagem: String = str(escolhas_usuario[user_id_variant])
		participantes.append({
			"user_id": user_id,
			"nome": str(nomes_por_usuario.get(user_id, personagem.capitalize())),
			"personagem": personagem,
		})
	return participantes


func _escrever_registro_atomico(registro: Dictionary) -> bool:
	var payload: PackedByteArray = var_to_bytes(registro)
	if payload.is_empty():
		return false
	var hash_payload: String = _calcular_hash(payload)
	if hash_payload.is_empty():
		return false
	var envelope: Dictionary = {
		"assinatura": ASSINATURA_ARQUIVO,
		"versao": VERSAO_FORMATO,
		"hash": hash_payload,
		"payload": payload,
	}
	var bytes_envelope: PackedByteArray = var_to_bytes(envelope)
	if bytes_envelope.is_empty() or bytes_envelope.size() > TAMANHO_MAXIMO_ARQUIVO:
		return false

	var arquivo: FileAccess = FileAccess.open(CAMINHO_TEMPORARIO, FileAccess.WRITE)
	if arquivo == null:
		return false
	arquivo.store_buffer(bytes_envelope)
	arquivo.flush()
	arquivo.close()

	var verificacao: Dictionary = _ler_registro_caminho(CAMINHO_TEMPORARIO)
	if verificacao.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CAMINHO_TEMPORARIO))
		return false

	var caminho_final: String = ProjectSettings.globalize_path(CAMINHO_SALVAMENTO)
	var caminho_temp: String = ProjectSettings.globalize_path(CAMINHO_TEMPORARIO)
	var caminho_backup: String = ProjectSettings.globalize_path(CAMINHO_BACKUP)
	var havia_salvamento: bool = FileAccess.file_exists(CAMINHO_SALVAMENTO)
	var final_valido: bool = (
		havia_salvamento
		and not _ler_registro_caminho(CAMINHO_SALVAMENTO).is_empty()
	)
	var final_movido_para_backup: bool = false
	if havia_salvamento:
		if final_valido:
			if FileAccess.file_exists(CAMINHO_BACKUP):
				var erro_remocao_backup: Error = DirAccess.remove_absolute(caminho_backup)
				if erro_remocao_backup != OK:
					DirAccess.remove_absolute(caminho_temp)
					return false
			var erro_backup: Error = DirAccess.rename_absolute(
				caminho_final,
				caminho_backup
			)
			if erro_backup != OK:
				DirAccess.remove_absolute(caminho_temp)
				return false
			final_movido_para_backup = true
		else:
			# Nunca substitui um backup válido por um arquivo principal corrompido.
			var erro_remocao_final: Error = DirAccess.remove_absolute(caminho_final)
			if erro_remocao_final != OK:
				DirAccess.remove_absolute(caminho_temp)
				return false

	var erro_publicacao: Error = DirAccess.rename_absolute(caminho_temp, caminho_final)
	if erro_publicacao != OK:
		if final_movido_para_backup and FileAccess.file_exists(CAMINHO_BACKUP):
			var erro_restauracao: Error = DirAccess.rename_absolute(
				caminho_backup,
				caminho_final
			)
			if erro_restauracao != OK:
				push_error("Não foi possível restaurar o salvamento anterior.")
		if FileAccess.file_exists(CAMINHO_TEMPORARIO):
			DirAccess.remove_absolute(caminho_temp)
		return false
	return true


func _carregar_melhor_registro() -> Dictionary:
	var principal: Dictionary = _ler_registro_caminho(CAMINHO_SALVAMENTO)
	if not principal.is_empty():
		return principal
	return _ler_registro_caminho(CAMINHO_BACKUP)


func _ler_registro_caminho(caminho: String) -> Dictionary:
	if not FileAccess.file_exists(caminho):
		return {}
	var arquivo: FileAccess = FileAccess.open(caminho, FileAccess.READ)
	if arquivo == null:
		return {}
	var tamanho: int = int(arquivo.get_length())
	if tamanho <= 0 or tamanho > TAMANHO_MAXIMO_ARQUIVO:
		arquivo.close()
		return {}
	var bytes_envelope: PackedByteArray = arquivo.get_buffer(tamanho)
	arquivo.close()
	var envelope_variant: Variant = bytes_to_var(bytes_envelope)
	if not envelope_variant is Dictionary:
		return {}
	var envelope: Dictionary = envelope_variant
	if str(envelope.get("assinatura", "")) != ASSINATURA_ARQUIVO:
		return {}
	if int(envelope.get("versao", 0)) != VERSAO_FORMATO:
		return {}
	var payload_variant: Variant = envelope.get("payload", PackedByteArray())
	if not payload_variant is PackedByteArray:
		return {}
	var payload: PackedByteArray = payload_variant
	var hash_esperado: String = str(envelope.get("hash", ""))
	if hash_esperado.is_empty() or _calcular_hash(payload) != hash_esperado:
		return {}
	var registro_variant: Variant = bytes_to_var(payload)
	if not registro_variant is Dictionary:
		return {}
	var registro: Dictionary = registro_variant
	if not _validar_registro(registro).is_empty():
		return {}
	return registro


func _validar_registro(registro: Dictionary) -> String:
	if int(registro.get("versao", 0)) != VERSAO_FORMATO:
		return "O FORMATO DO SALVAMENTO NÃO É COMPATÍVEL"
	if str(registro.get("sessao_id", "")).is_empty():
		return "O SALVAMENTO NÃO POSSUI UMA SESSÃO VÁLIDA"
	var host_user_id: String = str(registro.get("host_user_id", ""))
	if host_user_id.is_empty():
		return "O SALVAMENTO NÃO IDENTIFICA O HOST ORIGINAL"

	var participantes_variant: Variant = registro.get("participantes", [])
	if not participantes_variant is Array:
		return "A LISTA DE PARTICIPANTES DO SALVAMENTO É INVÁLIDA"
	var participantes: Array = participantes_variant
	if participantes.size() < 2 or participantes.size() > 6:
		return "A QUANTIDADE DE PARTICIPANTES DO SALVAMENTO É INVÁLIDA"

	var ids: Array[String] = []
	var personagens: Array[String] = []
	for participante_variant in participantes:
		if not participante_variant is Dictionary:
			return "O SALVAMENTO POSSUI UM PARTICIPANTE INVÁLIDO"
		var participante: Dictionary = participante_variant
		var user_id: String = str(participante.get("user_id", ""))
		var personagem: String = str(participante.get("personagem", ""))
		if user_id.is_empty() or personagem.is_empty():
			return "O SALVAMENTO POSSUI UM PARTICIPANTE INCOMPLETO"
		if ids.has(user_id) or personagens.has(personagem):
			return "O SALVAMENTO POSSUI PARTICIPANTES DUPLICADOS"
		ids.append(user_id)
		personagens.append(personagem)
	if not ids.has(host_user_id):
		return "O HOST ORIGINAL NÃO CONSTA ENTRE OS PARTICIPANTES"

	var snapshot_variant: Variant = registro.get("snapshot", {})
	if not snapshot_variant is Dictionary:
		return "O SNAPSHOT SALVO É INVÁLIDO"
	var snapshot: Dictionary = snapshot_variant
	if int(snapshot.get("versao", 0)) != 1:
		return "A VERSÃO DO SNAPSHOT SALVO NÃO É COMPATÍVEL"
	var estado_variant: Variant = snapshot.get("estado", {})
	if not estado_variant is Dictionary:
		return "O ESTADO PRINCIPAL DO SNAPSHOT É INVÁLIDO"
	var estado: Dictionary = estado_variant
	var economia_variant: Variant = estado.get("dados_economia_jogadores", {})
	if not economia_variant is Dictionary:
		return "A ECONOMIA SALVA É INVÁLIDA"
	var economia: Dictionary = economia_variant
	var turnos_variant: Variant = estado.get("lista_turnos", [])
	if not turnos_variant is Array:
		return "A ORDEM DE TURNOS SALVA É INVÁLIDA"
	var turnos: Array = turnos_variant
	var jogador_atual: String = str(estado.get("jogador_atual_id", ""))
	if (
		jogador_atual.is_empty()
		or not economia.has(jogador_atual)
		or not turnos.has(jogador_atual)
	):
		return "O TURNO ATUAL DO SALVAMENTO É INVÁLIDO"
	var pinos_variant: Variant = snapshot.get("pinos", {})
	if not pinos_variant is Dictionary:
		return "AS POSIÇÕES SALVAS SÃO INVÁLIDAS"
	var pinos: Dictionary = pinos_variant
	if pinos.is_empty() or not pinos.has(jogador_atual):
		return "AS POSIÇÕES SALVAS SÃO INVÁLIDAS"
	var tabuleiro_variant: Variant = snapshot.get("tabuleiro_mutavel", {})
	if not tabuleiro_variant is Dictionary:
		return "O ESTADO DO TABULEIRO SALVO É INVÁLIDO"
	var tabuleiro_salvo: Dictionary = tabuleiro_variant
	if tabuleiro_salvo.is_empty():
		return "O ESTADO DO TABULEIRO SALVO É INVÁLIDO"
	var escolhas_variant: Variant = snapshot.get("escolhas_por_user_id", {})
	if not escolhas_variant is Dictionary:
		return "AS IDENTIDADES DO SNAPSHOT SÃO INVÁLIDAS"
	var escolhas: Dictionary = escolhas_variant
	if escolhas.size() != participantes.size():
		return "O SNAPSHOT NÃO CONTÉM TODOS OS PARTICIPANTES"
	for indice in range(ids.size()):
		var user_id: String = ids[indice]
		if not escolhas.has(user_id) or str(escolhas[user_id]) != personagens[indice]:
			return "A ASSOCIAÇÃO ENTRE JOGADOR E PERSONAGEM É INVÁLIDA"
	return ""


func _calcular_hash(dados: PackedByteArray) -> String:
	var contexto: HashingContext = HashingContext.new()
	var erro_inicio: Error = contexto.start(HashingContext.HASH_SHA256)
	if erro_inicio != OK:
		return ""
	var erro_dados: Error = contexto.update(dados)
	if erro_dados != OK:
		return ""
	return contexto.finish().hex_encode()


func _formatar_data_hora(unix_time: int) -> String:
	if unix_time <= 0:
		return "DATA DESCONHECIDA"
	var fuso_horario: Dictionary = Time.get_time_zone_from_system()
	var ajuste_segundos: int = int(fuso_horario.get("bias", 0)) * 60
	var data: Dictionary = Time.get_datetime_dict_from_unix_time(
		unix_time + ajuste_segundos
	)
	return "%02d/%02d/%04d %02d:%02d" % [
		int(data.get("day", 1)),
		int(data.get("month", 1)),
		int(data.get("year", 2000)),
		int(data.get("hour", 0)),
		int(data.get("minute", 0)),
	]
