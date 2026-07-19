extends Node

signal perfil_atualizado(perfil: Dictionary)

const CAMINHO_PERFIL := "user://perfil_progressao.json"
const VERSAO_PERFIL := 1
const XP_BASE_PROXIMO_NIVEL := 500
const XP_CRESCIMENTO_POR_NIVEL := 250

var _perfil: Dictionary = {}


func _ready() -> void:
	carregar_perfil()


func _perfil_padrao() -> Dictionary:
	return {
		"versao": VERSAO_PERFIL,
		"nome": "JOGADOR",
		"xp_total": 0,
		"nivel": 1,
		"partidas": 0,
		"vitorias": 0,
		"segundos_lugares": 0,
		"terceiros_lugares": 0,
		"eliminacoes": 0,
		"monopolios_completados": 0,
		"habilidades_usadas": 0,
		"acordos_cumpridos": 0,
		"bonus_eventos_seguros": 0,
		"melhor_xp_partida": 0,
		"ultima_partida_xp": 0,
		"ultima_colocacao": 0,
	}


func carregar_perfil() -> Dictionary:
	_perfil = _perfil_padrao()
	if not FileAccess.file_exists(CAMINHO_PERFIL):
		salvar_perfil()
		return obter_perfil()

	var arquivo := FileAccess.open(CAMINHO_PERFIL, FileAccess.READ)
	if arquivo == null:
		push_warning("Não foi possível abrir o perfil de progressão. Um perfil novo será usado.")
		return obter_perfil()

	var conteudo := arquivo.get_as_text()
	var carregado = JSON.parse_string(conteudo)
	if carregado is Dictionary:
		for chave in carregado.keys():
			_perfil[chave] = carregado[chave]
	else:
		push_warning("O arquivo de perfil estava inválido. Um perfil novo será usado.")

	_normalizar_perfil()
	return obter_perfil()


func salvar_perfil() -> bool:
	_normalizar_perfil()
	var arquivo := FileAccess.open(CAMINHO_PERFIL, FileAccess.WRITE)
	if arquivo == null:
		push_error("Não foi possível salvar o perfil de progressão em " + CAMINHO_PERFIL)
		return false
	arquivo.store_string(JSON.stringify(_perfil, "\t"))
	return true


func obter_perfil() -> Dictionary:
	_normalizar_perfil()
	return _perfil.duplicate(true)


func definir_nome(novo_nome: String) -> bool:
	var nome_limpo := novo_nome.strip_edges().substr(0, 18)
	if nome_limpo == "":
		return false
	_perfil["nome"] = nome_limpo
	var salvo := salvar_perfil()
	perfil_atualizado.emit(obter_perfil())
	return salvo


func aplicar_resultado_partida(resumo: Dictionary) -> Dictionary:
	_normalizar_perfil()
	var xp_ganho := maxi(0, int(resumo.get("xp_ganho", 0)))
	var colocacao := maxi(0, int(resumo.get("colocacao", 0)))
	var nivel_anterior := int(_perfil.get("nivel", 1))
	var xp_anterior := int(_perfil.get("xp_total", 0))

	_perfil["xp_total"] = xp_anterior + xp_ganho
	_perfil["nivel"] = calcular_nivel(int(_perfil["xp_total"]))
	_perfil["partidas"] = int(_perfil.get("partidas", 0)) + 1
	_perfil["ultima_partida_xp"] = xp_ganho
	_perfil["ultima_colocacao"] = colocacao
	_perfil["melhor_xp_partida"] = maxi(int(_perfil.get("melhor_xp_partida", 0)), xp_ganho)

	if colocacao == 1:
		_perfil["vitorias"] = int(_perfil.get("vitorias", 0)) + 1
	elif colocacao == 2:
		_perfil["segundos_lugares"] = int(_perfil.get("segundos_lugares", 0)) + 1
	elif colocacao == 3:
		_perfil["terceiros_lugares"] = int(_perfil.get("terceiros_lugares", 0)) + 1

	_perfil["eliminacoes"] = int(_perfil.get("eliminacoes", 0)) + maxi(0, int(resumo.get("eliminacoes", 0)))
	_perfil["monopolios_completados"] = int(_perfil.get("monopolios_completados", 0)) + maxi(0, int(resumo.get("monopolios", 0)))
	_perfil["habilidades_usadas"] = int(_perfil.get("habilidades_usadas", 0)) + maxi(0, int(resumo.get("habilidades_usadas", 0)))
	_perfil["acordos_cumpridos"] = int(_perfil.get("acordos_cumpridos", 0)) + maxi(0, int(resumo.get("acordos_cumpridos", 0)))
	_perfil["bonus_eventos_seguros"] = int(_perfil.get("bonus_eventos_seguros", 0)) + maxi(0, int(resumo.get("bonus_eventos_seguros", 0)))

	var salvo := salvar_perfil()
	var resultado := {
		"salvo": salvo,
		"xp_ganho": xp_ganho,
		"xp_anterior": xp_anterior,
		"xp_total": int(_perfil["xp_total"]),
		"nivel_anterior": nivel_anterior,
		"nivel_atual": int(_perfil["nivel"]),
		"subiu_nivel": int(_perfil["nivel"]) > nivel_anterior,
		"colocacao": colocacao,
		"perfil": obter_perfil(),
	}
	perfil_atualizado.emit(obter_perfil())
	return resultado


func calcular_nivel(xp_total: int) -> int:
	var restante := maxi(0, xp_total)
	var nivel := 1
	while restante >= xp_necessario_para_proximo_nivel(nivel):
		restante -= xp_necessario_para_proximo_nivel(nivel)
		nivel += 1
	return nivel


func xp_necessario_para_proximo_nivel(nivel: int) -> int:
	return XP_BASE_PROXIMO_NIVEL + maxi(0, nivel - 1) * XP_CRESCIMENTO_POR_NIVEL


func xp_no_nivel_atual(xp_total: int) -> int:
	var restante := maxi(0, xp_total)
	var nivel := 1
	while restante >= xp_necessario_para_proximo_nivel(nivel):
		restante -= xp_necessario_para_proximo_nivel(nivel)
		nivel += 1
	return restante


func progresso_nivel(xp_total: int) -> float:
	var nivel := calcular_nivel(xp_total)
	var necessario := xp_necessario_para_proximo_nivel(nivel)
	if necessario <= 0:
		return 0.0
	return clampf(float(xp_no_nivel_atual(xp_total)) / float(necessario), 0.0, 1.0)


func _normalizar_perfil() -> void:
	if _perfil.is_empty():
		_perfil = _perfil_padrao()
	var padrao := _perfil_padrao()
	for chave in padrao.keys():
		if not _perfil.has(chave):
			_perfil[chave] = padrao[chave]
	_perfil["versao"] = VERSAO_PERFIL
	_perfil["nome"] = str(_perfil.get("nome", "JOGADOR")).strip_edges().substr(0, 18)
	if str(_perfil["nome"]) == "":
		_perfil["nome"] = "JOGADOR"
	_perfil["xp_total"] = maxi(0, int(_perfil.get("xp_total", 0)))
	_perfil["nivel"] = calcular_nivel(int(_perfil["xp_total"]))
	for chave in [
		"partidas", "vitorias", "segundos_lugares", "terceiros_lugares",
		"eliminacoes", "monopolios_completados", "habilidades_usadas",
		"acordos_cumpridos", "bonus_eventos_seguros", "melhor_xp_partida",
		"ultima_partida_xp", "ultima_colocacao"
	]:
		_perfil[chave] = maxi(0, int(_perfil.get(chave, 0)))
