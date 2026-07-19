extends Control

signal seguimento_solicitado(jogador_id: String, automatico: bool)

const COR_CIANO := Color(0.26, 0.84, 1.0)
const COR_AMARELO := Color(1.0, 0.78, 0.20)
const COR_VERDE := Color(0.42, 0.95, 0.54)
const COR_VERMELHO := Color(0.96, 0.34, 0.32)
const COR_ROXO := Color(0.82, 0.54, 1.0)
const COR_TEXTO := Color(0.89, 0.92, 0.96)
const COR_TEXTO_FRACO := Color(0.61, 0.68, 0.76)

var _dados: Dictionary = {}
var _alvo_id: String = ""
var _reconstruindo_opcoes := false
var _detalhes_abertos := false
var _estado_inicializado := false

@onready var _painel_logs: PanelContainer = %PainelLogs
@onready var _lista_logs: VBoxContainer = %ListaLogs
@onready var _painel_ranking: PanelContainer = %PainelRanking
@onready var _lista_ranking: VBoxContainer = %ListaRanking
@onready var _painel_efeitos: PanelContainer = %PainelEfeitos
@onready var _lista_efeitos: VBoxContainer = %ListaEfeitos
@onready var _painel_resumo: PanelContainer = %PainelResumoAlvo
@onready var _resumo_nome: Label = %ResumoNome
@onready var _resumo_status: Label = %ResumoStatus
@onready var _resumo_propriedades: Label = %ResumoPropriedades
@onready var _btn_detalhes: Button = %BtnDetalhes
@onready var _painel_detalhes: PanelContainer = %GavetaDetalhes
@onready var _detalhes_titulo: Label = %DetalhesTitulo
@onready var _detalhes_conteudo: VBoxContainer = %DetalhesConteudo
@onready var _dock_camera: PanelContainer = %DockCamera
@onready var _auto_seguir: CheckButton = %AutoSeguir
@onready var _dropdown_jogadores: OptionButton = %DropdownJogadores
@onready var _btn_focar: Button = %BtnFocar
@onready var _status_camera: Label = %StatusCamera
@onready var _status_partida: Label = %StatusPartida

@onready var _template_ranking_neutro: Button = %TemplateRankingNeutro
@onready var _template_ranking_ciano: Button = %TemplateRankingCiano
@onready var _template_ranking_amarelo: Button = %TemplateRankingAmarelo
@onready var _template_ranking_vermelho: Button = %TemplateRankingVermelho
@onready var _template_linha_12: Label = %TemplateLinha12
@onready var _template_linha_13: Label = %TemplateLinha13
@onready var _template_subtitulo: Label = %TemplateSubtitulo
@onready var _template_separador: ColorRect = %TemplateSeparador

func mostrar() -> void:
	visible = true
	_animar_entrada()

func ocultar() -> void:
	visible = false

func atualizar_dados(dados: Dictionary) -> void:
	_dados = dados.duplicate(true)
	_atualizar_alvo_com_estado()
	_reconstruir_opcoes_jogadores()
	_reconstruir_logs()
	_reconstruir_ranking()
	_reconstruir_efeitos()
	_reconstruir_resumo()
	if _detalhes_abertos:
		_reconstruir_detalhes()
	_atualizar_status_camera()

func _animar_entrada() -> void:
	var entradas: Array[Control] = [_painel_logs, _painel_ranking, _painel_efeitos, _painel_resumo, _dock_camera]
	for i in range(entradas.size()):
		var item := entradas[i]
		item.modulate.a = 0.0
		item.scale = Vector2(0.98, 0.98)
		item.pivot_offset = item.size / 2.0
		var tween := item.create_tween()
		tween.tween_interval(float(i) * 0.055)
		tween.tween_property(item, "modulate:a", 1.0, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(item, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _atualizar_alvo_com_estado() -> void:
	if not _estado_inicializado:
		var auto_inicial := bool(_dados.get("auto_seguir", true))
		_auto_seguir.set_pressed_no_signal(auto_inicial)
		_alvo_id = str(_dados.get("jogador_atual_id", "")) if auto_inicial else str(_dados.get("alvo_seguido", _dados.get("jogador_atual_id", "")))
		_estado_inicializado = true
	elif _auto_seguir.button_pressed:
		_alvo_id = str(_dados.get("jogador_atual_id", _alvo_id))
	if not _jogador_existe(_alvo_id):
		_alvo_id = _primeiro_jogador_ativo()

func _primeiro_jogador_ativo() -> String:
	for jogador in _dados.get("jogadores", []):
		if not bool(jogador.get("falido", false)):
			return str(jogador.get("id", ""))
	return ""

func _jogador_existe(jogador_id: String) -> bool:
	for jogador in _dados.get("jogadores", []):
		if str(jogador.get("id", "")) == jogador_id:
			return true
	return false

func _jogador_ativo(jogador_id: String) -> bool:
	for jogador in _dados.get("jogadores", []):
		if str(jogador.get("id", "")) == jogador_id:
			return not bool(jogador.get("falido", false))
	return false

func _jogador_por_id(jogador_id: String) -> Dictionary:
	for jogador in _dados.get("jogadores", []):
		if str(jogador.get("id", "")) == jogador_id:
			return jogador
	return {}

func _nome_jogador(jogador_id: String) -> String:
	var jogador := _jogador_por_id(jogador_id)
	return str(jogador.get("nome", jogador_id))

func _limpar(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _reconstruir_opcoes_jogadores() -> void:
	_reconstruindo_opcoes = true
	_dropdown_jogadores.clear()
	var indice_selecionado := 0
	for jogador in _dados.get("jogadores", []):
		var indice := _dropdown_jogadores.item_count
		var falido := bool(jogador.get("falido", false))
		var sufixo := " [FALIDO]" if falido else ""
		_dropdown_jogadores.add_item(str(jogador.get("nome", jogador.get("id", ""))).to_upper() + sufixo)
		_dropdown_jogadores.set_item_metadata(indice, str(jogador.get("id", "")))
		if str(jogador.get("id", "")) == _alvo_id:
			indice_selecionado = indice
	if _dropdown_jogadores.item_count > 0:
		_dropdown_jogadores.select(clampi(indice_selecionado, 0, _dropdown_jogadores.item_count - 1))
	_dropdown_jogadores.disabled = _auto_seguir.button_pressed
	_btn_focar.disabled = _auto_seguir.button_pressed or not _jogador_ativo(_alvo_id)
	_reconstruindo_opcoes = false

func _cor_tipo_log(tipo: String) -> Color:
	match tipo:
		"compra", "construcao", "vitoria":
			return COR_VERDE
		"falencia", "prisao", "dano":
			return COR_VERMELHO
		"evento", "reputacao":
			return COR_AMARELO
		"negociacao", "promessa":
			return COR_ROXO
		_:
			return Color(0.72, 0.80, 0.90)

func _reconstruir_logs() -> void:
	_limpar(_lista_logs)
	var rodada := int(_dados.get("rodada", 1))
	var turno := int(_dados.get("turno_global", 0))
	var atual := _nome_jogador(str(_dados.get("jogador_atual_id", ""))).to_upper()
	_status_partida.text = "RODADA %d  //  TURNO %d  //  VEZ DE %s" % [rodada, turno, atual]
	var historico: Array = _dados.get("historico", [])
	if historico.is_empty():
		_adicionar_linha(_lista_logs, "A cidade aguarda a primeira movimentação...", COR_TEXTO_FRACO, 7)
		return
	var inicio := maxi(0, historico.size() - 6)
	for i in range(historico.size() - 1, inicio - 1, -1):
		var acao: Dictionary = historico[i]
		var prefixo := "[%02d]" % int(acao.get("turno", 0))
		_adicionar_linha(_lista_logs, prefixo + " " + str(acao.get("texto", "")), _cor_tipo_log(str(acao.get("tipo", ""))), 7)

func _reconstruir_ranking() -> void:
	_limpar(_lista_ranking)
	var posicao := 1
	for jogador in _dados.get("jogadores", []):
		var id := str(jogador.get("id", ""))
		var falido := bool(jogador.get("falido", false))
		var em_turno := bool(jogador.get("em_turno", false))
		var selecionado := id == _alvo_id
		var template := _template_ranking_neutro
		if falido:
			template = _template_ranking_vermelho
		elif em_turno:
			template = _template_ranking_amarelo
		elif selecionado:
			template = _template_ranking_ciano
		var botao := template.duplicate() as Button
		botao.visible = true
		var estado := "FALIDO" if falido else ("EM TURNO" if em_turno else "ATIVO")
		botao.text = "%d. %s\n$%d  |  %.1f%%  |  %s" % [posicao, str(jogador.get("nome", id)).to_upper(), int(jogador.get("patrimonio", 0)), float(jogador.get("previsao_vitoria", 0.0)), estado]
		botao.pressed.connect(_selecionar_jogador_ranking.bind(id))
		_lista_ranking.add_child(botao)
		posicao += 1

func _reconstruir_efeitos() -> void:
	_limpar(_lista_efeitos)
	var eventos: Array = _dados.get("eventos_ativos", [])
	if eventos.is_empty():
		_adicionar_linha(_lista_efeitos, "• Mercado estável; nenhum efeito temporário.", COR_VERDE, 7)
	else:
		var limite := mini(eventos.size(), 4)
		for i in range(limite):
			var evento: Dictionary = eventos[i]
			var turnos := int(evento.get("turnos", -1))
			var duracao := "ATUAL" if turnos < 0 else str(turnos) + "T"
			_adicionar_linha(_lista_efeitos, "• %s  [%s]" % [str(evento.get("nome", "EFEITO")), duracao], COR_AMARELO, 7)
		if eventos.size() > limite:
			_adicionar_linha(_lista_efeitos, "+ %d efeito(s) na gaveta de detalhes" % (eventos.size() - limite), COR_TEXTO_FRACO, 6)
	var ativas := 0
	var primeira := ""
	for promessa in _dados.get("promessas", []):
		if str(promessa.get("status", "ativa")) == "ativa":
			ativas += 1
			if primeira == "":
				primeira = str(promessa.get("texto", ""))
	_adicionar_linha(_lista_efeitos, "ACORDOS PÚBLICOS ATIVOS: %d" % ativas, COR_ROXO, 7)
	if primeira != "":
		_adicionar_linha(_lista_efeitos, "“%s”" % primeira, Color(0.76, 0.70, 0.85), 6)

func _reconstruir_resumo() -> void:
	var jogador := _jogador_por_id(_alvo_id)
	if jogador.is_empty():
		_resumo_nome.text = "SEM ALVO"
		_resumo_status.text = "Nenhum jogador disponível."
		_resumo_propriedades.text = ""
		_btn_detalhes.disabled = true
		return
	_btn_detalhes.disabled = false
	_resumo_nome.text = str(jogador.get("nome", _alvo_id)).to_upper()
	var estado := "FALIDO" if jogador.get("falido", false) else ("EM TURNO" if jogador.get("em_turno", false) else "ATIVO")
	_resumo_status.text = "%s  //  CAIXA $%d\nPATRIMÔNIO $%d  //  VITÓRIA %.1f%%\nPROPS %d  //  HIPOTECAS %d  //  REP %d/100  //  XP %d" % [
		estado,
		int(jogador.get("dinheiro", 0)), int(jogador.get("patrimonio", 0)), float(jogador.get("previsao_vitoria", 0.0)),
		int(jogador.get("quantidade_propriedades", 0)), int(jogador.get("hipotecas", 0)), int(jogador.get("reputacao", 50)), int(jogador.get("xp_partida", 0))]
	var nomes: Array[String] = []
	for prop in jogador.get("propriedades", []):
		if nomes.size() >= 3:
			break
		var marca := " [H]" if prop.get("hipotecada", false) else ""
		nomes.append(str(prop.get("nome", "")) + marca)
	var lista_nomes := ", ".join(PackedStringArray(nomes)) if not nomes.is_empty() else "nenhum"
	_resumo_propriedades.text = "IMÓVEIS: " + lista_nomes
	if int(jogador.get("quantidade_propriedades", 0)) > nomes.size():
		_resumo_propriedades.text += "  +%d" % (int(jogador.get("quantidade_propriedades", 0)) - nomes.size())

func _reconstruir_detalhes() -> void:
	_limpar(_detalhes_conteudo)
	var jogador := _jogador_por_id(_alvo_id)
	_detalhes_titulo.text = "DOSSIÊ // " + str(jogador.get("nome", _alvo_id)).to_upper()
	if jogador.is_empty():
		_adicionar_linha(_detalhes_conteudo, "Nenhum dado disponível.", COR_TEXTO_FRACO, 7)
		return
	_adicionar_subtitulo_detalhes("PATRIMÔNIO", COR_AMARELO)
	_adicionar_linha(_detalhes_conteudo, "Caixa $%d | Total $%d | Chance %.1f%%" % [int(jogador.get("dinheiro", 0)), int(jogador.get("patrimonio", 0)), float(jogador.get("previsao_vitoria", 0.0))], COR_TEXTO, 7)
	_adicionar_linha(_detalhes_conteudo, "Monopólios %d | Hipotecas %d | Reputação %d/100 | XP %d" % [int(jogador.get("monopolios", 0)), int(jogador.get("hipotecas", 0)), int(jogador.get("reputacao", 50)), int(jogador.get("xp_partida", 0))], COR_TEXTO_FRACO, 6)
	_adicionar_subtitulo_detalhes("PROPRIEDADES", COR_CIANO)
	var propriedades: Array = jogador.get("propriedades", [])
	if propriedades.is_empty():
		_adicionar_linha(_detalhes_conteudo, "Nenhuma propriedade registrada.", COR_TEXTO_FRACO, 7)
	else:
		for prop in propriedades:
			var estado := "HIPOTECADA" if prop.get("hipotecada", false) else "ATIVA"
			var nivel := int(prop.get("nivel", 0))
			var nivel_texto := "HOTEL" if nivel == 5 else (str(nivel) + " CASA(S)")
			_adicionar_linha(_detalhes_conteudo, "• %s [%s]\n  %s | %s | aluguel $%d" % [str(prop.get("nome", "")), str(prop.get("grupo", "")), estado, nivel_texto, int(prop.get("aluguel_estimado", 0))], COR_TEXTO, 7)
	_adicionar_subtitulo_detalhes("EFEITOS ATIVOS", COR_ROXO)
	var eventos: Array = _dados.get("eventos_ativos", [])
	if eventos.is_empty():
		_adicionar_linha(_detalhes_conteudo, "Nenhum efeito temporário ativo.", COR_VERDE, 7)
	else:
		for evento in eventos:
			var turnos := int(evento.get("turnos", -1))
			var duracao := "atual/permanente" if turnos < 0 else str(turnos) + " turno(s)"
			_adicionar_linha(_detalhes_conteudo, "• %s — %s" % [str(evento.get("nome", "Efeito")), duracao], COR_AMARELO, 7)
	_adicionar_subtitulo_detalhes("ACORDOS PÚBLICOS", COR_ROXO)
	var exibiu := false
	for promessa in _dados.get("promessas", []):
		if str(promessa.get("status", "ativa")) != "ativa":
			continue
		exibiu = true
		var autor := _nome_jogador(str(promessa.get("autor_id", ""))).to_upper()
		_adicionar_linha(_detalhes_conteudo, "• %s: “%s”\n  %d turno(s) restante(s)" % [autor, str(promessa.get("texto", "")), int(promessa.get("turnos_restantes", 0))], Color(0.82, 0.75, 0.92), 7)
	if not exibiu:
		_adicionar_linha(_detalhes_conteudo, "Nenhum acordo público ativo.", COR_TEXTO_FRACO, 7)

func _adicionar_subtitulo_detalhes(texto: String, cor: Color) -> void:
	var titulo := _template_subtitulo.duplicate() as Label
	titulo.visible = true
	titulo.text = texto
	titulo.add_theme_color_override("font_color", cor)
	_detalhes_conteudo.add_child(titulo)
	var linha := _template_separador.duplicate() as ColorRect
	linha.visible = true
	linha.color = Color(cor.r, cor.g, cor.b, 0.25)
	_detalhes_conteudo.add_child(linha)

func _adicionar_linha(container: VBoxContainer, texto: String, cor: Color, tamanho: int) -> Label:
	var template := _template_linha_12 if tamanho <= 6 else _template_linha_13
	var label := template.duplicate() as Label
	label.visible = true
	label.text = texto
	label.add_theme_color_override("font_color", cor)
	container.add_child(label)
	return label

func _atualizar_status_camera() -> void:
	var nome := _nome_jogador(_alvo_id).to_upper()
	if not _jogador_ativo(_alvo_id):
		_status_camera.text = "INSPEÇÃO\n" + nome
	elif _auto_seguir.button_pressed:
		_status_camera.text = "CÂMERA\nTURNO: " + nome
	else:
		_status_camera.text = "CÂMERA\nFIXA: " + nome

func _on_auto_toggled(ativo: bool) -> void:
	if _reconstruindo_opcoes:
		return
	if ativo:
		_alvo_id = str(_dados.get("jogador_atual_id", _alvo_id))
	_dropdown_jogadores.disabled = ativo
	_btn_focar.disabled = ativo or not _jogador_ativo(_alvo_id)
	_reconstruir_opcoes_jogadores()
	_reconstruir_ranking()
	_reconstruir_resumo()
	if _detalhes_abertos:
		_reconstruir_detalhes()
	_atualizar_status_camera()
	emit_signal("seguimento_solicitado", _alvo_id, ativo)

func _on_alvo_selecionado(indice: int) -> void:
	if _reconstruindo_opcoes or indice < 0:
		return
	_alvo_id = str(_dropdown_jogadores.get_item_metadata(indice))
	_btn_focar.disabled = not _jogador_ativo(_alvo_id)
	_reconstruir_ranking()
	_reconstruir_resumo()
	if _detalhes_abertos:
		_reconstruir_detalhes()
	_atualizar_status_camera()

func _on_focar_pressed() -> void:
	if not _jogador_ativo(_alvo_id):
		return
	_auto_seguir.set_pressed_no_signal(false)
	_dropdown_jogadores.disabled = false
	_btn_focar.disabled = false
	_atualizar_status_camera()
	emit_signal("seguimento_solicitado", _alvo_id, false)

func _selecionar_jogador_ranking(jogador_id: String) -> void:
	_alvo_id = jogador_id
	for i in range(_dropdown_jogadores.item_count):
		if str(_dropdown_jogadores.get_item_metadata(i)) == jogador_id:
			_dropdown_jogadores.select(i)
			break
	if _jogador_ativo(jogador_id):
		_auto_seguir.set_pressed_no_signal(false)
		_dropdown_jogadores.disabled = false
		_btn_focar.disabled = false
		emit_signal("seguimento_solicitado", _alvo_id, false)
	else:
		_auto_seguir.set_pressed_no_signal(false)
		_dropdown_jogadores.disabled = false
		_btn_focar.disabled = true
	_reconstruir_ranking()
	_reconstruir_resumo()
	if _detalhes_abertos:
		_reconstruir_detalhes()
	_atualizar_status_camera()

func _alternar_detalhes() -> void:
	_detalhes_abertos = not _detalhes_abertos
	_painel_detalhes.visible = _detalhes_abertos
	_btn_detalhes.text = "FECHAR DETALHES" if _detalhes_abertos else "ABRIR DETALHES"
	if _detalhes_abertos:
		_reconstruir_detalhes()
		_painel_detalhes.modulate.a = 0.0
		_painel_detalhes.position.x += 24.0
		var tween := _painel_detalhes.create_tween().set_parallel(true)
		tween.tween_property(_painel_detalhes, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(_painel_detalhes, "position:x", _painel_detalhes.position.x - 24.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
