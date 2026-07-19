extends CanvasLayer

# ============================================================================
# METROPOLIS IN RUINS — PAINEL DE NEGOCIAÇÃO (Fase 1 + 2)
# ============================================================================
# Controlador da cena independente painel_negociacao.tscn.
# Toda a estrutura visual fixa (painel, campos, contadores de visitas/passes,
# listas e botões) é declarada na cena. Este script mantém somente o estado,
# preenche os dados e cria dinamicamente apenas os itens de propriedades.
#
# Dois modos:
#   - MODO_PROPOSTA : o proponente monta a proposta e clica ENVIAR.
#   - MODO_RESPOSTA : o receptor vê a proposta (read-only) e clica ACEITAR/RECUSAR.
# ============================================================================

signal proposta_enviada(proposta: Dictionary)
signal proposta_respondida(id_proposta: String, aceita: bool, aceitador: String)
signal cancelado()
# --- NOVO (Fase 3 — Alianças): signal emitido quando o jogador propõe aliança ---
signal alianca_proposta(proposta: Dictionary)

const MODO_PROPOSTA: int = 0
const MODO_RESPOSTA: int = 1

# ============================================================================
# ⚙️ CONFIGURAÇÃO VISUAL — ajuste livremente para corrigir erros visuais
# ============================================================================

const FONT_LABEL_PROPS := 16
const FONT_LEGENDA_AJUDA := 12
const FONT_CONTADOR := 19
const ALT_ITEM_PROPS := 62
const ALT_ITEM_PROPS_RESPOSTA := 82

const COR_TITULO := Color(0.95, 0.85, 0.15, 1)
const COR_TEXTO := Color(1.0, 1.0, 1.0, 1)
const COR_TEXTO_SECUNDARIO := Color(0.7, 0.7, 0.7, 1)
const COR_OFERECE := Color(0.3, 0.9, 0.5, 1)
const COR_PEDE := Color(0.95, 0.6, 0.2, 1)
const COR_ERRO := Color(0.95, 0.3, 0.3, 1)
const COR_OK := Color(0.4, 0.95, 0.4, 1)
const COR_DESTAQUE_PROP_OFERECE := Color(0.15, 0.35, 0.20, 0.95)
const COR_DESTAQUE_PROP_PEDE := Color(0.35, 0.20, 0.10, 0.95)

const FONTE_PIXEL := preload("res://assets/fonts/PressStart2P.ttf")

# Animação modal: leve aproximação e fade, sem quique excessivo.
const ESCALA_ABERTURA := Vector2(0.955, 0.955)
const ESCALA_FECHAMENTO := Vector2(0.975, 0.975)
const DURACAO_ABERTURA := 0.26
const DURACAO_FECHAMENTO := 0.17

# ============================================================================
# FIM DA CONFIGURAÇÃO VISUAL
# ============================================================================

# --- Estado interno ---
var modo: int = MODO_PROPOSTA
var id_proposta_recebida: String = ""
var proposta_recebida: Dictionary = {}

var meu_id: String = ""
var dados_jogadores: Dictionary = {}
var tabuleiro_data: Dictionary = {}
var registro_props: Dictionary = {}
var lista_turnos_ativos: Array = []

var alvo_id: String = ""
var props_oferecidas_selecionadas: Array[int] = []
var props_pedidas_selecionadas: Array[int] = []

# --- Referências aos nós do .tscn (caminhos relativos ao CanvasLayer PainelNegociacao) ---
# Estes nós JÁ EXISTEM no hud_partida.tscn — não precisam ser criados.
@onready var fundo = $Fundo
@onready var painel_principal = $Centro/PainelPrincipal
@onready var titulo_label = $Centro/PainelPrincipal/VBoxRaiz/HBoxHeader/Titulo
@onready var botao_fechar = $Centro/PainelPrincipal/VBoxRaiz/HBoxHeader/BtnFechar

# Coluna OFERECE
@onready var sub_oferece = $Centro/PainelPrincipal/VBoxRaiz/HBoxColunas/ColunaOferece/VBoxOferece/SubOferece
@onready var input_dinheiro_oferece = $Centro/PainelPrincipal/VBoxRaiz/HBoxColunas/ColunaOferece/VBoxOferece/HBoxDinheiroOferece/InputDinheiroOferece
@onready var input_imunidade_oferece = $Centro/PainelPrincipal/VBoxRaiz/HBoxColunas/ColunaOferece/VBoxOferece/HBoxImunidadeOferece/SpinImunidadeOferece
@onready var linha_passe_oferece: HBoxContainer = $Centro/PainelPrincipal/VBoxRaiz/HBoxColunas/ColunaOferece/VBoxOferece/HBoxPassesOferece
@onready var input_passe_oferece: SpinBox = $Centro/PainelPrincipal/VBoxRaiz/HBoxColunas/ColunaOferece/VBoxOferece/HBoxPassesOferece/SpinPassesOferece
@onready var lista_props_oferece = $Centro/PainelPrincipal/VBoxRaiz/HBoxColunas/ColunaOferece/VBoxOferece/ScrollOferece/ListaPropsOferece

# Coluna PEDE
@onready var lbl_info_alvo = $Centro/PainelPrincipal/VBoxRaiz/HBoxColunas/ColunaPede/VBoxPede/LblInfoAlvo
@onready var dropdown_alvo = $Centro/PainelPrincipal/VBoxRaiz/HBoxColunas/ColunaPede/VBoxPede/DropdownAlvo
@onready var input_dinheiro_pede = $Centro/PainelPrincipal/VBoxRaiz/HBoxColunas/ColunaPede/VBoxPede/HBoxDinheiroPede/InputDinheiroPede
@onready var input_imunidade_pede = $Centro/PainelPrincipal/VBoxRaiz/HBoxColunas/ColunaPede/VBoxPede/HBoxImunidadePede/SpinImunidadePede
@onready var linha_passe_pede: HBoxContainer = $Centro/PainelPrincipal/VBoxRaiz/HBoxColunas/ColunaPede/VBoxPede/HBoxPassesPede
@onready var input_passe_pede: SpinBox = $Centro/PainelPrincipal/VBoxRaiz/HBoxColunas/ColunaPede/VBoxPede/HBoxPassesPede/SpinPassesPede
@onready var lista_props_pede = $Centro/PainelPrincipal/VBoxRaiz/HBoxColunas/ColunaPede/VBoxPede/ScrollPede/ListaPropsPede

# Footer
@onready var label_resumo = $Centro/PainelPrincipal/VBoxRaiz/LabelResumo
@onready var botao_cancelar = $Centro/PainelPrincipal/VBoxRaiz/HBoxBotoes/BtnCancelar
@onready var botao_acao_principal = $Centro/PainelPrincipal/VBoxRaiz/HBoxBotoes/BtnAcao
# --- NOVO (Fase 3 — Alianças): botão para propor aliança ---
@onready var botao_alianca = $Centro/PainelPrincipal/VBoxRaiz/HBoxBotoes/BtnAlianca

# Cache de checkboxes
var _checkboxes_oferece: Dictionary = {}
var _checkboxes_pede: Dictionary = {}

# StyleBoxes para checkbox e cards (criados em _ready pois não vão no .tscn)
var _sb_checkbox_unchecked: StyleBoxFlat = null
var _sb_checkbox_checked: StyleBoxFlat = null
var _sb_card_resposta_oferece: StyleBoxFlat = null
var _sb_card_resposta_pede: StyleBoxFlat = null

var _bloqueado: bool = false
# Guarda se já configuramos este painel para um modo específico.
# Evita reconfigurar quando exibir() é chamado múltiplas vezes.
var _modo_configurado: bool = false

var _tween_exibicao: Tween = null
var _id_animacao_exibicao: int = 0
var _alpha_fundo_alvo: float = 0.82

# ============================================================================
# INICIALIZAÇÃO
# ============================================================================
func _ready() -> void:
		layer = 100
		_alpha_fundo_alvo = fundo.color.a
		painel_principal.pivot_offset = Vector2.ZERO
		painel_principal.pivot_offset_ratio = Vector2(0.5, 0.5)
		_criar_styleboxes()
		_aplicar_fonte_pixel_nos_contadores()
		_conectar_sinais_ui()

# Conecta os sinais dos botões e inputs que vêm do .tscn.
# IMPORTANTE: estes nós já existem — só precisamos conectar seus sinais.
func _conectar_sinais_ui():
		if botao_fechar:
				botao_fechar.pressed.connect(_on_fechar)
		if botao_cancelar:
				botao_cancelar.pressed.connect(_on_fechar)
		if botao_acao_principal:
				botao_acao_principal.pressed.connect(_on_acao_principal)
		# --- NOVO (Fase 3 — Alianças): botão de propor aliança ---
		if botao_alianca:
				botao_alianca.pressed.connect(_propor_alianca)
		if dropdown_alvo:
				dropdown_alvo.item_selected.connect(_on_alvo_selecionado)
		if input_dinheiro_oferece:
				input_dinheiro_oferece.text_changed.connect(_on_dinheiro_alterado.bind(true))
		if input_dinheiro_pede:
				input_dinheiro_pede.text_changed.connect(_on_dinheiro_alterado.bind(false))
		if input_imunidade_oferece:
				input_imunidade_oferece.value_changed.connect(_on_imunidade_alterada.bind(true))
		if input_imunidade_pede:
				input_imunidade_pede.value_changed.connect(_on_imunidade_alterada.bind(false))
		if input_passe_oferece:
				input_passe_oferece.value_changed.connect(_on_passe_alterado.bind(true))
		if input_passe_pede:
				input_passe_pede.value_changed.connect(_on_passe_alterado.bind(false))

func _aplicar_fonte_pixel_nos_contadores() -> void:
		# O número exibido pelo SpinBox pertence a um LineEdit interno. O Theme
		# da cena já usa a fonte pixel art; estes overrides garantem o resultado
		# também em versões/plataformas que não propagam o tema ao LineEdit.
		for spin: SpinBox in [input_imunidade_oferece, input_passe_oferece, input_imunidade_pede, input_passe_pede]:
				if spin == null:
						continue
				spin.add_theme_font_override("font", FONTE_PIXEL)
				spin.add_theme_font_size_override("font_size", FONT_CONTADOR)
				var editor: LineEdit = spin.get_line_edit()
				if editor:
						editor.add_theme_font_override("font", FONTE_PIXEL)
						editor.add_theme_font_size_override("font_size", FONT_CONTADOR)
						editor.alignment = HORIZONTAL_ALIGNMENT_CENTER

func _qtd_linhas_metro(id_jogador: String) -> int:
	var total = 0
	for casa_id in registro_props.keys():
		if registro_props[casa_id] == id_jogador and tabuleiro_data.get(casa_id, {}).get("grupo", "") == "Transporte":
			total += 1
	return total

func _atualizar_disponibilidade_passes() -> void:
	if not input_passe_oferece or not input_passe_pede:
		return
	var pode_oferecer = _qtd_linhas_metro(meu_id) >= 2
	var pode_pedir = alvo_id != "" and _qtd_linhas_metro(alvo_id) >= 2
	input_passe_oferece.editable = pode_oferecer and modo == MODO_PROPOSTA
	input_passe_pede.editable = pode_pedir and modo == MODO_PROPOSTA
	if not pode_oferecer and modo == MODO_PROPOSTA:
		input_passe_oferece.value = 0
	if not pode_pedir and modo == MODO_PROPOSTA:
		input_passe_pede.value = 0

# Cria os StyleBoxes usados pelas checkboxes customizadas e pelos cards
# de propriedade no MODO_RESPOSTA. (CheckBox não suporta stylebox para os
# estados checked/unchecked via .tscn, então criamos em código.)
func _criar_styleboxes():
		_sb_checkbox_unchecked = StyleBoxFlat.new()
		_sb_checkbox_unchecked.bg_color = Color(0.12, 0.12, 0.14, 0.95)
		_sb_checkbox_unchecked.border_width_left = 3
		_sb_checkbox_unchecked.border_width_top = 3
		_sb_checkbox_unchecked.border_width_right = 3
		_sb_checkbox_unchecked.border_width_bottom = 3
		_sb_checkbox_unchecked.border_color = Color(0.7, 0.85, 1.0, 0.9)
		_sb_checkbox_unchecked.corner_radius_top_left = 4
		_sb_checkbox_unchecked.corner_radius_top_right = 4
		_sb_checkbox_unchecked.corner_radius_bottom_right = 4
		_sb_checkbox_unchecked.corner_radius_bottom_left = 4

		_sb_checkbox_checked = StyleBoxFlat.new()
		_sb_checkbox_checked.bg_color = Color(0.4, 0.9, 0.5, 0.95)
		_sb_checkbox_checked.border_width_left = 3
		_sb_checkbox_checked.border_width_top = 3
		_sb_checkbox_checked.border_width_right = 3
		_sb_checkbox_checked.border_width_bottom = 3
		_sb_checkbox_checked.border_color = Color(1.0, 1.0, 1.0, 1.0)
		_sb_checkbox_checked.corner_radius_top_left = 4
		_sb_checkbox_checked.corner_radius_top_right = 4
		_sb_checkbox_checked.corner_radius_bottom_right = 4
		_sb_checkbox_checked.corner_radius_bottom_left = 4

		_sb_card_resposta_oferece = StyleBoxFlat.new()
		_sb_card_resposta_oferece.bg_color = COR_DESTAQUE_PROP_OFERECE
		_sb_card_resposta_oferece.border_width_left = 4
		_sb_card_resposta_oferece.border_width_top = 4
		_sb_card_resposta_oferece.border_width_right = 4
		_sb_card_resposta_oferece.border_width_bottom = 4
		_sb_card_resposta_oferece.border_color = Color(1, 1, 1, 0.5)
		_sb_card_resposta_oferece.corner_radius_top_left = 6
		_sb_card_resposta_oferece.corner_radius_top_right = 6
		_sb_card_resposta_oferece.corner_radius_bottom_right = 6
		_sb_card_resposta_oferece.corner_radius_bottom_left = 6
		_sb_card_resposta_oferece.content_margin_left = 14
		_sb_card_resposta_oferece.content_margin_right = 14
		_sb_card_resposta_oferece.content_margin_top = 12
		_sb_card_resposta_oferece.content_margin_bottom = 12

		_sb_card_resposta_pede = StyleBoxFlat.new()
		_sb_card_resposta_pede.bg_color = COR_DESTAQUE_PROP_PEDE
		_sb_card_resposta_pede.border_width_left = 4
		_sb_card_resposta_pede.border_width_top = 4
		_sb_card_resposta_pede.border_width_right = 4
		_sb_card_resposta_pede.border_width_bottom = 4
		_sb_card_resposta_pede.border_color = Color(1, 1, 1, 0.5)
		_sb_card_resposta_pede.corner_radius_top_left = 6
		_sb_card_resposta_pede.corner_radius_top_right = 6
		_sb_card_resposta_pede.corner_radius_bottom_right = 6
		_sb_card_resposta_pede.corner_radius_bottom_left = 6
		_sb_card_resposta_pede.content_margin_left = 14
		_sb_card_resposta_pede.content_margin_right = 14
		_sb_card_resposta_pede.content_margin_top = 12
		_sb_card_resposta_pede.content_margin_bottom = 12

# ============================================================================
# ANIMAÇÃO DE ABERTURA E FECHAMENTO
# ============================================================================

func _cancelar_tween_exibicao() -> void:
	if _tween_exibicao != null and _tween_exibicao.is_valid():
		_tween_exibicao.kill()
	_tween_exibicao = null

func _proximo_id_animacao() -> int:
	_id_animacao_exibicao += 1
	return _id_animacao_exibicao

# ============================================================================
# CONFIGURAÇÃO PÚBLICA (chamado pela HUD antes de exibir())
# ============================================================================

func configurar_como_proposta(meu_id_p: String, dados_jogadores_p: Dictionary, tabuleiro_p: Dictionary, registro_p: Dictionary, lista_turnos_p: Array) -> void:
		modo = MODO_PROPOSTA
		meu_id = meu_id_p
		dados_jogadores = dados_jogadores_p
		tabuleiro_data = tabuleiro_p
		registro_props = registro_p
		lista_turnos_ativos = lista_turnos_p
		_modo_configurado = false  # força reconfigurar na próxima exibição

func configurar_como_resposta(proposta: Dictionary, meu_id_p: String, dados_jogadores_p: Dictionary, tabuleiro_p: Dictionary, registro_p: Dictionary) -> void:
		modo = MODO_RESPOSTA
		proposta_recebida = proposta
		id_proposta_recebida = proposta.get("id_proposta", "")
		meu_id = meu_id_p
		dados_jogadores = dados_jogadores_p
		tabuleiro_data = tabuleiro_p
		registro_props = registro_p
		_modo_configurado = false


# Monta a proposta-modelo da aula depois que o painel já foi exibido. O aluno
# ainda revisa as duas colunas e é quem efetivamente toca em ENVIAR PROPOSTA.
func preparar_proposta_tutorial(
	alvo_desejado: String,
	dinheiro_oferecido: int,
	propriedades_pedidas: Array
) -> bool:
	if (
		not Global.modo_tutorial
		or modo != MODO_PROPOSTA
		or not visible
		or _bloqueado
	):
		return false

	var indice_alvo: int = -1
	for indice: int in range(dropdown_alvo.item_count):
		if str(dropdown_alvo.get_item_metadata(indice)) == alvo_desejado:
			indice_alvo = indice
			break
	if indice_alvo < 0:
		return false

	dropdown_alvo.select(indice_alvo)
	alvo_id = alvo_desejado
	props_oferecidas_selecionadas.clear()
	props_pedidas_selecionadas.clear()
	_reconstruir_lista_props_checkboxes(
		lista_props_oferece,
		_checkboxes_oferece,
		true,
		_props_do_jogador(meu_id)
	)
	_reconstruir_lista_props_checkboxes(
		lista_props_pede,
		_checkboxes_pede,
		false,
		_props_do_jogador(alvo_id)
	)

	input_dinheiro_oferece.text = str(maxi(0, dinheiro_oferecido))
	input_dinheiro_pede.text = "0"
	input_imunidade_oferece.value = 0
	input_imunidade_pede.value = 0
	input_passe_oferece.value = 0
	input_passe_pede.value = 0

	var todas_encontradas: bool = true
	for casa_variant: Variant in propriedades_pedidas:
		var casa_id: int = int(casa_variant)
		if not _checkboxes_pede.has(casa_id):
			todas_encontradas = false
			continue
		var check: CheckBox = _checkboxes_pede.get(casa_id) as CheckBox
		if check == null:
			todas_encontradas = false
			continue
		check.set_pressed_no_signal(true)
		props_pedidas_selecionadas.append(casa_id)
	_atualizar_disponibilidade_passes()
	_atualizar_resumo()
	return todas_encontradas

# Chamado pela HUD para exibir o painel (após configurar_*).
# Torna o CanvasLayer visível e preenche a UI conforme o modo.
func exibir() -> void:
		var animacao_id := _proximo_id_animacao()
		_cancelar_tween_exibicao()
		visible = true

		# Desbloqueia o painel (caso tenha sido bloqueado em uso anterior).
		_bloqueado = false
		if botao_acao_principal:
				botao_acao_principal.disabled = false
		if botao_cancelar:
				botao_cancelar.disabled = false
		if botao_fechar:
				botao_fechar.disabled = false

		# Preenche a UI antes do frame de layout, para o painel calcular seu
		# tamanho final já com o conteúdo correto.
		if modo == MODO_PROPOSTA:
				_atualizar_modo_proposta()
		else:
				_atualizar_modo_resposta()
		_modo_configurado = true

		fundo.color.a = 0.0
		painel_principal.modulate.a = 0.0
		painel_principal.scale = ESCALA_ABERTURA

		# O painel está dentro de um CenterContainer. Esperar o layout evita que
		# a escala seja recalculada antes de o pivô central estar correto.
		await get_tree().process_frame
		if not is_instance_valid(self) or animacao_id != _id_animacao_exibicao or not visible:
				return

		painel_principal.pivot_offset = Vector2.ZERO
		painel_principal.pivot_offset_ratio = Vector2(0.5, 0.5)
		painel_principal.scale = ESCALA_ABERTURA

		_tween_exibicao = create_tween()
		_tween_exibicao.tween_property(fundo, "color:a", _alpha_fundo_alvo, DURACAO_ABERTURA * 0.72).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween_exibicao.parallel().tween_property(painel_principal, "modulate:a", 1.0, DURACAO_ABERTURA * 0.68).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween_exibicao.parallel().tween_property(painel_principal, "scale", Vector2.ONE, DURACAO_ABERTURA).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween_exibicao.tween_callback(func() -> void:
				if animacao_id != _id_animacao_exibicao:
						return
				painel_principal.modulate.a = 1.0
				painel_principal.scale = Vector2.ONE
				fundo.color.a = _alpha_fundo_alvo
				_tween_exibicao = null
		)

# ============================================================================
# ATUALIZAÇÃO DA UI POR MODO
# ============================================================================

func _atualizar_modo_proposta() -> void:
		titulo_label.text = "🤝 NOVA NEGOCIAÇÃO"
		botao_acao_principal.text = "ENVIAR PROPOSTA"
		botao_acao_principal.modulate = Color(1, 1, 1)
		botao_cancelar.text = "CANCELAR"
		botao_cancelar.modulate = Color(1, 1, 1)
		# --- NOVO (Fase 3): botão de aliança só aparece no MODO_PROPOSTA ---
		if botao_alianca:
				botao_alianca.visible = true

		# Mostra dropdown e label do alvo
		dropdown_alvo.visible = true
		lbl_info_alvo.visible = true
		sub_oferece.visible = true

		# Inputs habilitados
		input_dinheiro_oferece.editable = true
		input_dinheiro_pede.editable = true
		input_imunidade_oferece.editable = true
		input_imunidade_pede.editable = true
		if linha_passe_oferece: linha_passe_oferece.visible = true
		if linha_passe_pede: linha_passe_pede.visible = true

		# Reseta valores
		input_dinheiro_oferece.text = "0"
		input_dinheiro_pede.text = "0"
		input_imunidade_oferece.value = 0
		input_imunidade_pede.value = 0
		input_passe_oferece.value = 0
		input_passe_pede.value = 0
		props_oferecidas_selecionadas.clear()
		props_pedidas_selecionadas.clear()

		# Preenche dropdown de alvos: SÓ jogadores na partida atual, exceto eu e falidos
		dropdown_alvo.clear()
		var primeiro_alvo := ""
		for id in lista_turnos_ativos:
				if id == meu_id:
						continue
				if not dados_jogadores.has(id):
						continue
				if dados_jogadores[id].get("falido", false):
						continue
				var nome = dados_jogadores[id].get("nome", id)
				var reputacao = int(dados_jogadores[id].get("reputacao", 50))
				dropdown_alvo.add_item(nome.to_upper() + "  [REP " + str(reputacao) + "]", dropdown_alvo.item_count)
				dropdown_alvo.set_item_metadata(dropdown_alvo.item_count - 1, id)
				if primeiro_alvo == "":
						primeiro_alvo = id

		if primeiro_alvo == "":
				botao_acao_principal.disabled = true
				botao_acao_principal.text = "SEM JOGADORES"
				label_resumo.text = "Nenhum jogador disponível para negociar."
				_reconstruir_lista_props_checkboxes(lista_props_oferece, _checkboxes_oferece, true, [])
				_reconstruir_lista_props_checkboxes(lista_props_pede, _checkboxes_pede, false, [])
				return

		alvo_id = primeiro_alvo
		dropdown_alvo.select(0)
		_reconstruir_lista_props_checkboxes(lista_props_oferece, _checkboxes_oferece, true, _props_do_jogador(meu_id))
		_reconstruir_lista_props_checkboxes(lista_props_pede, _checkboxes_pede, false, _props_do_jogador(alvo_id))
		_atualizar_disponibilidade_passes()
		_atualizar_resumo()

func _atualizar_modo_resposta() -> void:
		# --- NOVO (Fase 3): Se a proposta for do tipo "alianca", mostra um
		#     resumo específico de aliança em vez de troca normal. ---
		var tipo_proposta = proposta_recebida.get("tipo", "troca")
		var de_id = proposta_recebida.get("de", "")
		var de_nome = dados_jogadores.get(de_id, {}).get("nome", de_id)
		var de_reputacao = int(dados_jogadores.get(de_id, {}).get("reputacao", 50))

		if tipo_proposta == "alianca":
				titulo_label.text = "🤝 PROPOSTA DE ALIANÇA"
				botao_acao_principal.text = "ACEITAR ALIANÇA"
				botao_acao_principal.modulate = Color(0.95, 0.85, 0.15)
				botao_cancelar.text = "RECUSAR"
				botao_cancelar.modulate = Color(1.0, 0.6, 0.4)
				if botao_alianca:
						botao_alianca.visible = false
				# Esconde todos os campos de troca (dinheiro, props, imunidade)
				dropdown_alvo.visible = false
				lbl_info_alvo.visible = false
				sub_oferece.visible = false
				input_dinheiro_oferece.editable = false
				input_dinheiro_pede.editable = false
				input_imunidade_oferece.editable = false
				input_imunidade_pede.editable = false
				if linha_passe_oferece: linha_passe_oferece.visible = false
				if linha_passe_pede: linha_passe_pede.visible = false
				# Zera valores (não há troca em aliança)
				input_dinheiro_oferece.text = "0"
				input_dinheiro_pede.text = "0"
				input_imunidade_oferece.value = 0
				input_imunidade_pede.value = 0
				# Limpa listas de props
				_renderizar_props_modo_resposta([], [])
				# Mostra resumo da aliança
				var duracao = proposta_recebida.get("duracao_turnos", 5)
				label_resumo.text = "%s propõe ALIANÇA por %d turnos. Reputação: %d/100.\nAliados pagam +10%% aluguel um ao outro.\nNegociações com terceiros têm -10%% de taxa." % [de_nome.to_upper(), duracao, de_reputacao]
				label_resumo.add_theme_color_override("font_color", COR_TITULO)
				return

		titulo_label.text = "📨 PROPOSTA RECEBIDA"
		botao_acao_principal.text = "ACEITAR"
		botao_acao_principal.modulate = Color(0.4, 1.0, 0.4)
		botao_cancelar.text = "RECUSAR"
		botao_cancelar.modulate = Color(1.0, 0.6, 0.4)
		# --- NOVO (Fase 3): esconde botão de aliança no MODO_RESPOSTA ---
		if botao_alianca:
				botao_alianca.visible = false

		# Esconde dropdown e sub-texto (não aplicáveis em resposta)
		dropdown_alvo.visible = false
		lbl_info_alvo.visible = false
		sub_oferece.visible = false

		# Inputs read-only
		input_dinheiro_oferece.editable = false
		input_dinheiro_pede.editable = false
		input_imunidade_oferece.editable = false
		input_imunidade_pede.editable = false
		if linha_passe_oferece: linha_passe_oferece.visible = true
		if linha_passe_pede: linha_passe_pede.visible = true
		input_passe_oferece.editable = false
		input_passe_pede.editable = false

		# Preenche valores da proposta recebida
		var oferece = proposta_recebida.get("oferece", {})
		var pede = proposta_recebida.get("pede", {})

		input_dinheiro_oferece.text = str(int(oferece.get("dinheiro", 0)))
		input_dinheiro_pede.text = str(int(pede.get("dinheiro", 0)))
		input_imunidade_oferece.value = int(oferece.get("imunidade_visitas", 0))
		input_imunidade_pede.value = int(pede.get("imunidade_visitas", 0))
		input_passe_oferece.value = int(oferece.get("passes_transporte", 0))
		input_passe_pede.value = int(pede.get("passes_transporte", 0))

		# Renderiza APENAS as propriedades da proposta, como cards destacados
		_renderizar_props_modo_resposta(oferece.get("propriedades", []), pede.get("propriedades", []))

		var resumo_passes = ""
		if int(oferece.get("passes_transporte", 0)) > 0 or int(pede.get("passes_transporte", 0)) > 0:
			resumo_passes = "\nInclui passes de transporte: oferece %d / pede %d." % [int(oferece.get("passes_transporte", 0)), int(pede.get("passes_transporte", 0))]
		label_resumo.text = "%s está te propondo uma troca. Analise com cuidado!%s" % [de_nome.to_upper(), resumo_passes]
		label_resumo.add_theme_color_override("font_color", COR_TITULO)

# ============================================================================
# RECONSTRUÇÃO DAS LISTAS DE PROPRIEDADES (MODO_PROPOSTA — checkboxes)
# ============================================================================

func _props_do_jogador(id_jogador: String) -> Array:
		var resultado: Array = []
		for casa_id in registro_props.keys():
				if registro_props[casa_id] == id_jogador:
						resultado.append(casa_id)
		return resultado

func _reconstruir_lista_props_checkboxes(container: VBoxContainer, cache: Dictionary, eh_oferece: bool, props_ids: Array):
		cache.clear()
		for child in container.get_children():
				child.queue_free()
		if props_ids.is_empty():
				var lbl = Label.new()
				lbl.text = "(sem propriedades)"
				lbl.add_theme_font_override("font", FONTE_PIXEL)
				lbl.add_theme_font_size_override("font_size", FONT_LABEL_PROPS)
				lbl.add_theme_color_override("font_color", COR_TEXTO_SECUNDARIO)
				lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				container.add_child(lbl)
				return
		for casa_id in props_ids:
				var check = _criar_checkbox_prop(casa_id, eh_oferece)
				container.add_child(check)
				cache[casa_id] = check

# Cria uma CheckBox estilizada para uma propriedade (MODO_PROPOSTA).
# Usa StyleBoxes criados em _ready para os estados checked/unchecked.
func _criar_checkbox_prop(casa_id: int, eh_oferece: bool) -> CheckBox:
		var check = CheckBox.new()
		check.add_theme_font_override("font", FONTE_PIXEL)
		check.add_theme_font_size_override("font_size", FONT_LABEL_PROPS)
		check.custom_minimum_size = Vector2(0, ALT_ITEM_PROPS)
		check.text = _formatar_nome_prop(casa_id)
		if _sb_checkbox_unchecked and _sb_checkbox_checked:
				check.add_theme_stylebox_override("normal", _sb_checkbox_unchecked)
				check.add_theme_stylebox_override("hover", _sb_checkbox_unchecked)
				check.add_theme_stylebox_override("pressed", _sb_checkbox_checked)
				check.add_theme_stylebox_override("checked", _sb_checkbox_checked)
				check.add_theme_stylebox_override("checked_hover", _sb_checkbox_checked)
				check.add_theme_stylebox_override("checked_pressed", _sb_checkbox_checked)
		check.add_theme_constant_override("check_v_offset", 2)
		check.add_theme_constant_override("h_separation", 12)
		check.toggled.connect(_on_prop_toggled.bind(casa_id, eh_oferece))
		return check

func _formatar_nome_prop(casa_id: int) -> String:
		if not tabuleiro_data.has(casa_id):
				return "Casa " + str(casa_id)
		var dados = tabuleiro_data[casa_id]
		var nome = dados.get("nome", "Casa " + str(casa_id)).replace("\n", " ")
		var nivel = dados.get("nivel", 0)
		var hipotecada = dados.get("hipotecada", false)
		var grupo = dados.get("grupo", "")
		var sufixo = ""
		if nivel == 5:
				sufixo = " [HOTEL]"
		elif nivel > 0:
				sufixo = " [N" + str(nivel) + "]"
		if hipotecada:
				sufixo += " [HIPOT.]"
		if grupo != "":
				sufixo += " (" + grupo + ")"
		return nome.to_upper() + sufixo

# ============================================================================
# RENDERIZAÇÃO MODO_RESPOSTA — cards destacados
# ============================================================================

func _renderizar_props_modo_resposta(props_oferece: Array, props_pede: Array):
		_checkboxes_oferece.clear()
		for child in lista_props_oferece.get_children():
				child.queue_free()
		if props_oferece.is_empty():
				var lbl = Label.new()
				lbl.text = "(nenhuma propriedade oferecida)"
				lbl.add_theme_font_override("font", FONTE_PIXEL)
				lbl.add_theme_font_size_override("font_size", FONT_LABEL_PROPS)
				lbl.add_theme_color_override("font_color", COR_TEXTO_SECUNDARIO)
				lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				lista_props_oferece.add_child(lbl)
		else:
				for casa_id in props_oferece:
						var card = _criar_card_prop_resposta(casa_id, _sb_card_resposta_oferece, "OFERECE")
						lista_props_oferece.add_child(card)

		_checkboxes_pede.clear()
		for child in lista_props_pede.get_children():
				child.queue_free()
		if props_pede.is_empty():
				var lbl = Label.new()
				lbl.text = "(nenhuma propriedade pedida)"
				lbl.add_theme_font_override("font", FONTE_PIXEL)
				lbl.add_theme_font_size_override("font_size", FONT_LABEL_PROPS)
				lbl.add_theme_color_override("font_color", COR_TEXTO_SECUNDARIO)
				lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				lista_props_pede.add_child(lbl)
		else:
				for casa_id in props_pede:
						var card = _criar_card_prop_resposta(casa_id, _sb_card_resposta_pede, "PEDE")
						lista_props_pede.add_child(card)

func _criar_card_prop_resposta(casa_id: int, sb: StyleBoxFlat, etiqueta: String) -> PanelContainer:
		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(0, ALT_ITEM_PROPS_RESPOSTA)
		if sb:
				card.add_theme_stylebox_override("panel", sb)

		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		card.add_child(vbox)

		var lbl_etiqueta = Label.new()
		lbl_etiqueta.text = "▸ " + etiqueta
		lbl_etiqueta.add_theme_font_override("font", FONTE_PIXEL)
		lbl_etiqueta.add_theme_font_size_override("font_size", FONT_LEGENDA_AJUDA)
		lbl_etiqueta.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
		vbox.add_child(lbl_etiqueta)

		var lbl_nome = Label.new()
		lbl_nome.text = _formatar_nome_prop(casa_id)
		lbl_nome.add_theme_font_override("font", FONTE_PIXEL)
		lbl_nome.add_theme_font_size_override("font_size", FONT_LABEL_PROPS)
		lbl_nome.add_theme_color_override("font_color", COR_TEXTO)
		lbl_nome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(lbl_nome)

		return card

# ============================================================================
# HANDLERS DE EVENTOS
# ============================================================================

func _on_alvo_selecionado(idx: int) -> void:
		if _bloqueado:
				return
		var id = dropdown_alvo.get_item_metadata(idx)
		if id == null or id == "":
				return
		if id == alvo_id:
				return
		alvo_id = id
		props_pedidas_selecionadas.clear()
		_reconstruir_lista_props_checkboxes(lista_props_pede, _checkboxes_pede, false, _props_do_jogador(alvo_id))
		_atualizar_disponibilidade_passes()
		_atualizar_resumo()

func _on_dinheiro_alterado(_novo_texto: String, eh_oferece: bool) -> void:
		if _bloqueado:
				return
		if eh_oferece:
				input_dinheiro_oferece.text = _sanitizar_inteiro(input_dinheiro_oferece.text)
				input_dinheiro_oferece.caret_column = input_dinheiro_oferece.text.length()
		else:
				input_dinheiro_pede.text = _sanitizar_inteiro(input_dinheiro_pede.text)
				input_dinheiro_pede.caret_column = input_dinheiro_pede.text.length()
		_atualizar_resumo()

func _sanitizar_inteiro(texto: String) -> String:
		var resultado := ""
		for ch in texto:
				if ch >= "0" and ch <= "9":
						resultado += ch
		if resultado == "":
				return "0"
		var i = 0
		while i < resultado.length() - 1 and resultado[i] == "0":
				i += 1
		resultado = resultado.substr(i)
		# --- BUG FIX (HIGH #9): Limita a 9 dígitos (máximo $999.999.999).
		#     Antes, jogador podia digitar "999999999999" — int() podia
		#     estourar ou dar número negativo. Agora trunca para 9 dígitos. ---
		if resultado.length() > 9:
			resultado = resultado.substr(0, 9)
		return resultado

func _on_imunidade_alterada(_novo_valor: float, _eh_oferece: bool) -> void:
		if _bloqueado:
				return
		_atualizar_resumo()

func _on_passe_alterado(_novo_valor: float, _eh_oferece: bool) -> void:
	if _bloqueado:
		return
	_atualizar_resumo()

func _on_prop_toggled(pressionado: bool, casa_id: int, eh_oferece: bool) -> void:
		if _bloqueado:
				return
		if eh_oferece:
				var idx = props_oferecidas_selecionadas.find(casa_id)
				if pressionado and idx == -1:
						props_oferecidas_selecionadas.append(casa_id)
				elif not pressionado and idx != -1:
						props_oferecidas_selecionadas.remove_at(idx)
		else:
				var idx = props_pedidas_selecionadas.find(casa_id)
				if pressionado and idx == -1:
						props_pedidas_selecionadas.append(casa_id)
				elif not pressionado and idx != -1:
						props_pedidas_selecionadas.remove_at(idx)
		_atualizar_resumo()

func _on_fechar() -> void:
		if _bloqueado:
				return
		if modo == MODO_RESPOSTA:
				_responder_proposta(false)
				return
		cancelado.emit()
		_esconder()

func _on_acao_principal() -> void:
		if _bloqueado:
				return
		if modo == MODO_PROPOSTA:
				_enviar_proposta()
		else:
				_responder_proposta(true)

# ============================================================================
# NOVO (Fase 3 — Alianças): PROPOR ALIANÇA
# ============================================================================
# Chamado quando o jogador clica em "🤝 Propor Aliança" (botão extra no painel).
# Cria uma proposta do tipo "alianca" e emite o signal alianca_proposta.
# O fluxo é o mesmo da negociação: A propõe → B aceita → aliança formada.
# Mas a proposta de aliança é mais simples: só precisa do alvo_id e da duração
# (fixa em 5 turnos, conforme GDD). Não há troca de dinheiro ou propriedades.
func _propor_alianca():
		if _bloqueado:
				return
		if modo != MODO_PROPOSTA:
				return
		if alvo_id == "":
				label_resumo.text = "❌ Selecione um jogador alvo para propor aliança."
				label_resumo.add_theme_color_override("font_color", COR_ERRO)
				return
		if alvo_id == meu_id:
				label_resumo.text = "❌ Não pode formar aliança consigo mesmo."
				label_resumo.add_theme_color_override("font_color", COR_ERRO)
				return
		if dados_jogadores.get(alvo_id, {}).get("falido", false):
				label_resumo.text = "❌ Alvo está falido."
				label_resumo.add_theme_color_override("font_color", COR_ERRO)
				return
		# Verifica se já são aliados
		if _ja_sao_aliados(meu_id, alvo_id):
				label_resumo.text = "❌ Vocês já são aliados."
				label_resumo.add_theme_color_override("font_color", COR_ERRO)
				return
		# Cria proposta de aliança
		var id_unico = "alianca_%d_%d_%d" % [OnlineTransport.local_player_id(), Time.get_ticks_msec(), randi() % 100000]  # BUG FIX (MED #24): adiciona peer_id para evitar colisão entre peers
		var proposta_alianca := {
				"id_proposta": id_unico,
				"tipo": "alianca",
				"de": meu_id,
				"para": alvo_id,
				"duracao_turnos": 5,  # 5 turnos de aliança (conforme GDD)
		}
		_bloquear_painel("Aguardando resposta da aliança...")
		alianca_proposta.emit(proposta_alianca)

# Verifica se dois jogadores já são aliados (para evitar propostas duplicadas)
func _ja_sao_aliados(id_a: String, id_b: String) -> bool:
		if not dados_jogadores.has(id_a) or not dados_jogadores.has(id_b):
				return false
		for alianca in dados_jogadores[id_a].get("aliancas", []):
				if alianca.get("com", "") == id_b and alianca.get("turnos_restantes", 0) > 0:
						return true
		return false

# ============================================================================
# LÓGICA DE PROPOSTA (MODO_PROPOSTA)
# ============================================================================

func _enviar_proposta() -> void:
		var erros := _validar_proposta()
		if not erros.is_empty():
				label_resumo.text = "❌ " + erros[0]
				label_resumo.add_theme_color_override("font_color", COR_ERRO)
				return
		var proposta := _montar_dicionario_proposta()
		_bloquear_painel("Aguardando resposta...")
		proposta_enviada.emit(proposta)

func _validar_proposta() -> Array:
		var erros: Array = []
		if alvo_id == "":
				erros.append("Selecione um jogador alvo.")
				return erros
		if alvo_id == meu_id:
				erros.append("Não pode negociar consigo mesmo.")
				return erros
		if dados_jogadores.get(alvo_id, {}).get("falido", false):
				erros.append("Alvo está falido.")
				return erros
		if dados_jogadores.get(meu_id, {}).get("falido", false):
				erros.append("Você está falido.")
				return erros

		var dinheiro_oferece = int(input_dinheiro_oferece.text)
		var dinheiro_pede = int(input_dinheiro_pede.text)
		var meu_saldo = dados_jogadores[meu_id].get("dinheiro", 0)
		var saldo_alvo = dados_jogadores[alvo_id].get("dinheiro", 0)

		if dinheiro_oferece < 0:
				erros.append("Dinheiro oferecido não pode ser negativo.")
		if dinheiro_pede < 0:
				erros.append("Dinheiro pedido não pode ser negativo.")
		if dinheiro_oferece > meu_saldo:
				erros.append("Você não tem $" + str(dinheiro_oferece) + " em caixa (tem $" + str(meu_saldo) + ").")
		if dinheiro_pede > saldo_alvo:
				erros.append("O alvo não tem $" + str(dinheiro_pede) + " em caixa (tem $" + str(saldo_alvo) + ").")

		for casa_id in props_oferecidas_selecionadas:
				if not registro_props.has(casa_id) or registro_props[casa_id] != meu_id:
						erros.append("Propriedade '" + _formatar_nome_prop(casa_id) + "' não é sua.")
						break
		for casa_id in props_pedidas_selecionadas:
				if not registro_props.has(casa_id) or registro_props[casa_id] != alvo_id:
						erros.append("Propriedade '" + _formatar_nome_prop(casa_id) + "' não é do alvo.")
						break

		var visitas_oferece = int(input_imunidade_oferece.value)
		var visitas_pede = int(input_imunidade_pede.value)
		var passes_oferece = int(input_passe_oferece.value)
		var passes_pede = int(input_passe_pede.value)
		if passes_oferece > 0 and _qtd_linhas_metro(meu_id) < 2:
			erros.append("Você precisa possuir ao menos 2 Linhas de Metrô para oferecer passes.")
		if passes_pede > 0 and _qtd_linhas_metro(alvo_id) < 2:
			erros.append("O alvo precisa possuir ao menos 2 Linhas de Metrô para conceder passes.")
		if dinheiro_oferece == 0 and props_oferecidas_selecionadas.is_empty() and visitas_oferece == 0 and passes_oferece == 0:
				erros.append("Você precisa oferecer algo.")
		if dinheiro_pede == 0 and props_pedidas_selecionadas.is_empty() and visitas_pede == 0 and passes_pede == 0:
				erros.append("Você precisa pedir algo em troca.")
		return erros

func _montar_dicionario_proposta() -> Dictionary:
		var id_unico = "prop_%d_%d_%d" % [OnlineTransport.local_player_id(), Time.get_ticks_msec(), randi() % 100000]  # BUG FIX (MED #25): adiciona peer_id
		var props_oferece_untyped: Array = []
		for c in props_oferecidas_selecionadas:
				props_oferece_untyped.append(int(c))
		var props_pede_untyped: Array = []
		for c in props_pedidas_selecionadas:
				props_pede_untyped.append(int(c))
		var visitas_oferece = int(input_imunidade_oferece.value)
		var visitas_pede = int(input_imunidade_pede.value)
		var passes_oferece = int(input_passe_oferece.value)
		var passes_pede = int(input_passe_pede.value)
		return {
				"id_proposta": id_unico,
				"de": meu_id,
				"para": alvo_id,
				"oferece": {
						"dinheiro": int(input_dinheiro_oferece.text),
						"propriedades": props_oferece_untyped,
						"imunidade_visitas": visitas_oferece,
						"passes_transporte": passes_oferece,
				},
				"pede": {
						"dinheiro": int(input_dinheiro_pede.text),
						"propriedades": props_pede_untyped,
						"imunidade_visitas": visitas_pede,
						"passes_transporte": passes_pede,
				},
		}

# ============================================================================
# LÓGICA DE RESPOSTA (MODO_RESPOSTA)
# ============================================================================

func _responder_proposta(aceita: bool) -> void:
		if aceita:
				_bloquear_painel("✓ Aceito! Processando...")
		else:
				_bloquear_painel("Recusando...")
		# --- NOVO (Fase 3): Se for proposta de aliança, emite signal específico ---
		var tipo_proposta = proposta_recebida.get("tipo", "troca")
		if tipo_proposta == "alianca":
				# Usa o signal proposta_respondida mesmo para aliança — o tabuleiro
				# diferencia pelo tipo na proposta. Mas como a proposta_respondida
				# só leva (id, aceita, aceitador), precisamos garantir que o
				# tabuleiro saiba que é aliança. Vamos emitir proposta_respondida
				# normalmente; o tabuleiro vai procurar a proposta em _propostas_pendentes
				# e ver o tipo. Isso já funciona com a arquitetura existente.
				proposta_respondida.emit(id_proposta_recebida, aceita, meu_id)
		else:
				proposta_respondida.emit(id_proposta_recebida, aceita, meu_id)

# ============================================================================
# ESTADO PÚBLICO (chamado pela HUD / tabuleiro)
# ============================================================================

func mostrar_status(texto: String, cor: Color = COR_TEXTO_SECUNDARIO) -> void:
		label_resumo.text = texto
		label_resumo.add_theme_color_override("font_color", cor)

func _bloquear_painel(mensagem: String) -> void:
		_bloqueado = true
		if botao_acao_principal:
				botao_acao_principal.disabled = true
		if botao_cancelar:
				botao_cancelar.disabled = true
		if botao_fechar:
				botao_fechar.disabled = true
		mostrar_status(mensagem, COR_TITULO)

func desbloquear_painel() -> void:
		_bloqueado = false
		if botao_acao_principal:
				botao_acao_principal.disabled = false
		if botao_cancelar:
				botao_cancelar.disabled = false
		if botao_fechar:
				botao_fechar.disabled = false

func esconder_animado() -> void:
		_esconder()

func _esconder() -> void:
		if not visible:
				return
		var animacao_id := _proximo_id_animacao()
		_cancelar_tween_exibicao()
		_bloqueado = true
		if botao_acao_principal:
				botao_acao_principal.disabled = true
		if botao_cancelar:
				botao_cancelar.disabled = true
		if botao_fechar:
				botao_fechar.disabled = true

		painel_principal.pivot_offset = Vector2.ZERO
		painel_principal.pivot_offset_ratio = Vector2(0.5, 0.5)
		_tween_exibicao = create_tween()
		_tween_exibicao.tween_property(painel_principal, "modulate:a", 0.0, DURACAO_FECHAMENTO).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_tween_exibicao.parallel().tween_property(painel_principal, "scale", ESCALA_FECHAMENTO, DURACAO_FECHAMENTO).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_tween_exibicao.parallel().tween_property(fundo, "color:a", 0.0, DURACAO_FECHAMENTO).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_tween_exibicao.tween_callback(func() -> void:
				if animacao_id != _id_animacao_exibicao:
						return
				visible = false
				painel_principal.modulate.a = 1.0
				painel_principal.scale = Vector2.ONE
				fundo.color.a = _alpha_fundo_alvo
				_tween_exibicao = null
		)

# ============================================================================
# ATUALIZAÇÃO DO RESUMO
# ============================================================================

func _atualizar_resumo() -> void:
		if modo == MODO_RESPOSTA:
				return
		if alvo_id == "":
				label_resumo.text = "Selecione com quem deseja negociar."
				label_resumo.add_theme_color_override("font_color", COR_TEXTO_SECUNDARIO)
				return
		var nome_alvo = dados_jogadores.get(alvo_id, {}).get("nome", alvo_id).to_upper()
		var d_of = int(input_dinheiro_oferece.text)
		var d_pe = int(input_dinheiro_pede.text)
		var n_of = props_oferecidas_selecionadas.size()
		var n_pe = props_pedidas_selecionadas.size()
		var v_of = int(input_imunidade_oferece.value)
		var v_pe = int(input_imunidade_pede.value)
		var p_of = int(input_passe_oferece.value)
		var p_pe = int(input_passe_pede.value)
		var txt_of = "$%d + %d prop(s)" % [d_of, n_of]
		if v_of > 0:
				txt_of += " + %d visita(s) imune" % v_of
		if p_of > 0:
				txt_of += " + %d passe(s) de metrô" % p_of
		var txt_pe = "$%d + %d prop(s)" % [d_pe, n_pe]
		if v_pe > 0:
				txt_pe += " + %d visita(s) imune" % v_pe
		if p_pe > 0:
				txt_pe += " + %d passe(s) de metrô" % p_pe
		label_resumo.text = "Você oferece %s  →  pede %s de %s" % [txt_of, txt_pe, nome_alvo]
		label_resumo.add_theme_color_override("font_color", COR_TEXTO_SECUNDARIO)
