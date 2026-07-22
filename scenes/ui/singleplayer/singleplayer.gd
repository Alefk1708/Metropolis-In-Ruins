extends Control

const CENA_MENU_PRINCIPAL: String = (
	"res://scenes/ui/tela_inicial/menu_principal.tscn"
)
const CENA_TABULEIRO: String = (
	"res://scenes/gameplay/tabuleiro/tabuleiro.tscn"
)
const CAMINHO_FONTE: String = (
	"res://assets/fonts/m5x7.ttf"
)

const COR_TEXTO: Color = Color(0.98, 0.97, 0.98, 1.0)
const COR_DESTAQUE: Color = Color(1.0, 0.76, 0.78, 1.0)
const COR_AZUL: Color = Color(0.66, 0.88, 1.0, 1.0)

const PERSONAGENS := {
	"yasmin": {
		"nome": "YASMIN KHALIL",
		"alcunha": "A CORRETORA",
		"lore": "O mercado não tem moral. Mas eu tenho agenda.",
		"passiva": "Leilão Preferencial e Relatório de Mercado.",
		"ativa": "Oferta Irrecusável.",
		"imagem": "res://assets/textures/retrato_yasmin.jpg",
	},
	"breno": {
		"nome": "BRENO VASQUEZ",
		"alcunha": "O LOBISTA",
		"lore": "Não é corrupção. É facilitação.",
		"passiva": "Imunidade Política e Rede de Contatos.",
		"ativa": "Decreto Emergencial.",
		"imagem": "res://assets/textures/retrato_breno.jpg",
	},
	"mira": {
		"nome": "MIRA SANTOS",
		"alcunha": "A ARQUITETA SOCIAL",
		"lore": "Cada tijolo muda o destino de alguém.",
		"passiva": "Construção Acelerada e Resistência Estrutural.",
		"ativa": "Retrofit Urbano.",
		"imagem": "res://assets/textures/retrato_mira.jpg",
	},
	"igor": {
		"nome": "IGOR VOLKOV",
		"alcunha": "O ESPECULADOR",
		"lore": "Não compro imóveis. Compro o futuro deles.",
		"passiva": "Abutre do Mercado e Hedge Fund.",
		"ativa": "Especulação Imobiliária.",
		"imagem": "res://assets/textures/retrato_igor.jpg",
	},
	"diana": {
		"nome": "DIANA FERRO",
		"alcunha": "A INFILTRADA",
		"lore": "Informação é o único ativo que não deprecia.",
		"passiva": "Dossiê e Fonte Anônima.",
		"ativa": "Vazamento Seletivo.",
		"imagem": "res://assets/textures/retrato_diana.jpg",
	},
	"kofi": {
		"nome": "KOFI MENSAH",
		"alcunha": "O CONSTRUTOR DE COMUNIDADE",
		"lore": "Você compra o terreno, não o que foi construído nele.",
		"passiva": "Raízes e Solidariedade.",
		"ativa": "Mutirão.",
		"imagem": "res://assets/textures/retrato_kofi.jpg",
	},
}

var _fonte: Font = null
var _personagem_selecionado: String = "yasmin"
var _quantidade_bots: int = 3
var _botoes_personagens: Dictionary = {}
var _iniciando_partida: bool = false

var _conteudo_principal: Control = null
var _retrato_grande: TextureRect = null
var _label_nome: Label = null
var _label_alcunha: Label = null
var _label_lore: Label = null
var _label_habilidades: Label = null
var _label_resumo_partida: Label = null
var _seletor_bots: OptionButton = null
var _btn_iniciar: Button = null
var _btn_voltar: Button = null

@onready var _raiz_interface: MarginContainer = $RaizInterface
@onready var _fade_transicao: ColorRect = $FadeTransicao


func _enter_tree() -> void:
	Global.preparar_modo_singleplayer(3)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists(CAMINHO_FONTE):
		_fonte = load(CAMINHO_FONTE) as Font

	_criar_interface()
	_selecionar_personagem(_personagem_selecionado)
	call_deferred("_animar_entrada")


func _notification(what: int) -> void:
	if (
		what == NOTIFICATION_WM_GO_BACK_REQUEST
		and not _iniciando_partida
	):
		_voltar_ao_menu()


func _unhandled_input(evento: InputEvent) -> void:
	if _iniciando_partida:
		return
	if evento.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_voltar_ao_menu()


func _criar_interface() -> void:
	var coluna := VBoxContainer.new()
	coluna.name = "ConteudoSingleplayer"
	coluna.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coluna.size_flags_vertical = Control.SIZE_EXPAND_FILL
	coluna.add_theme_constant_override("separation", 14)
	_raiz_interface.add_child(coluna)
	_conteudo_principal = coluna

	var titulo := Label.new()
	titulo.text = "MODO SINGLEPLAYER"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_color_override("font_color", COR_DESTAQUE)
	_aplicar_fonte(titulo, 45, 5)
	coluna.add_child(titulo)

	var subtitulo := Label.new()
	subtitulo.text = (
		"ESCOLHA SEU PERSONAGEM E QUANTOS ADVERSÁRIOS A IA CONTROLARÁ"
	)
	subtitulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitulo.add_theme_color_override("font_color", COR_TEXTO)
	_aplicar_fonte(subtitulo, 24, 3)
	coluna.add_child(subtitulo)

	var corpo := HBoxContainer.new()
	corpo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	corpo.add_theme_constant_override("separation", 24)
	coluna.add_child(corpo)

	var painel_personagens := PanelContainer.new()
	painel_personagens.custom_minimum_size = Vector2(760.0, 0.0)
	painel_personagens.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	painel_personagens.add_theme_stylebox_override(
		"panel",
		_estilo_painel(
			Color(0.07, 0.065, 0.10, 0.98),
			Color(0.43, 0.42, 0.50, 1.0),
			5
		)
	)
	corpo.add_child(painel_personagens)

	var margem_personagens := MarginContainer.new()
	_configurar_margens(margem_personagens, 22)
	painel_personagens.add_child(margem_personagens)

	var coluna_personagens := VBoxContainer.new()
	coluna_personagens.add_theme_constant_override("separation", 14)
	margem_personagens.add_child(coluna_personagens)

	var titulo_personagens := Label.new()
	titulo_personagens.text = "PERSONAGENS"
	titulo_personagens.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo_personagens.add_theme_color_override(
		"font_color",
		COR_TEXTO
	)
	_aplicar_fonte(titulo_personagens, 34, 4)
	coluna_personagens.add_child(titulo_personagens)

	var grade := GridContainer.new()
	grade.columns = 2
	grade.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grade.add_theme_constant_override("h_separation", 14)
	grade.add_theme_constant_override("v_separation", 14)
	coluna_personagens.add_child(grade)

	for personagem_variant: Variant in PERSONAGENS.keys():
		var personagem_id: String = str(personagem_variant)
		var botao: Button = _criar_botao_personagem(
			personagem_id,
			PERSONAGENS[personagem_id]
		)
		grade.add_child(botao)
		_botoes_personagens[personagem_id] = botao

	var painel_detalhes := PanelContainer.new()
	painel_detalhes.custom_minimum_size = Vector2(610.0, 0.0)
	painel_detalhes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	painel_detalhes.add_theme_stylebox_override(
		"panel",
		_estilo_painel(
			Color(0.045, 0.055, 0.085, 0.99),
			Color(0.45, 0.66, 0.82, 1.0),
			5
		)
	)
	corpo.add_child(painel_detalhes)

	var margem_detalhes := MarginContainer.new()
	_configurar_margens(margem_detalhes, 24)
	painel_detalhes.add_child(margem_detalhes)

	var coluna_detalhes := VBoxContainer.new()
	coluna_detalhes.add_theme_constant_override("separation", 12)
	margem_detalhes.add_child(coluna_detalhes)

	var cabecalho := HBoxContainer.new()
	cabecalho.add_theme_constant_override("separation", 18)
	coluna_detalhes.add_child(cabecalho)

	_retrato_grande = TextureRect.new()
	_retrato_grande.custom_minimum_size = Vector2(210.0, 210.0)
	_retrato_grande.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_retrato_grande.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)
	cabecalho.add_child(_retrato_grande)

	var titulos := VBoxContainer.new()
	titulos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titulos.alignment = BoxContainer.ALIGNMENT_CENTER
	cabecalho.add_child(titulos)

	_label_nome = Label.new()
	_label_nome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label_nome.add_theme_color_override(
		"font_color",
		COR_DESTAQUE
	)
	_aplicar_fonte(_label_nome, 35, 4)
	titulos.add_child(_label_nome)

	_label_alcunha = Label.new()
	_label_alcunha.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label_alcunha.add_theme_color_override(
		"font_color",
		COR_AZUL
	)
	_aplicar_fonte(_label_alcunha, 27, 3)
	titulos.add_child(_label_alcunha)

	_label_lore = Label.new()
	_label_lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label_lore.add_theme_color_override(
		"font_color",
		Color(0.86, 0.86, 0.91, 1.0)
	)
	_aplicar_fonte(_label_lore, 25, 3)
	coluna_detalhes.add_child(_label_lore)

	var divisor := HSeparator.new()
	coluna_detalhes.add_child(divisor)

	_label_habilidades = Label.new()
	_label_habilidades.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)
	_label_habilidades.size_flags_vertical = (
		Control.SIZE_EXPAND_FILL
	)
	_label_habilidades.add_theme_color_override(
		"font_color",
		COR_TEXTO
	)
	_aplicar_fonte(_label_habilidades, 26, 3)
	coluna_detalhes.add_child(_label_habilidades)

	var linha_bots := HBoxContainer.new()
	linha_bots.add_theme_constant_override("separation", 16)
	coluna_detalhes.add_child(linha_bots)

	var rotulo_bots := Label.new()
	rotulo_bots.text = "ADVERSÁRIOS IA"
	rotulo_bots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rotulo_bots.add_theme_color_override(
		"font_color",
		COR_TEXTO
	)
	_aplicar_fonte(rotulo_bots, 28, 3)
	linha_bots.add_child(rotulo_bots)

	_seletor_bots = OptionButton.new()
	_seletor_bots.custom_minimum_size = Vector2(210.0, 58.0)
	for quantidade: int in range(1, 6):
		var texto: String = (
			"%d BOT" % quantidade
			if quantidade == 1
			else "%d BOTS" % quantidade
		)
		_seletor_bots.add_item(texto, quantidade)

	_seletor_bots.select(2)
	_seletor_bots.item_selected.connect(
		_ao_quantidade_bots_alterada
	)
	_aplicar_fonte(_seletor_bots, 26, 3)
	linha_bots.add_child(_seletor_bots)

	_label_resumo_partida = Label.new()
	_label_resumo_partida.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)
	_label_resumo_partida.add_theme_color_override(
		"font_color",
		Color(0.72, 0.87, 1.0, 1.0)
	)
	_aplicar_fonte(_label_resumo_partida, 23, 2)
	coluna_detalhes.add_child(_label_resumo_partida)

	var linha_botoes := HBoxContainer.new()
	linha_botoes.add_theme_constant_override("separation", 16)
	coluna_detalhes.add_child(linha_botoes)

	_btn_voltar = Button.new()
	_btn_voltar.text = "VOLTAR"
	_btn_voltar.custom_minimum_size = Vector2(190.0, 70.0)
	_btn_voltar.add_theme_stylebox_override(
		"normal",
		_estilo_botao(Color(0.28, 0.15, 0.19, 1.0))
	)
	_btn_voltar.add_theme_stylebox_override(
		"hover",
		_estilo_botao(Color(0.50, 0.27, 0.33, 1.0))
	)
	_aplicar_fonte(_btn_voltar, 31, 4)
	_btn_voltar.pressed.connect(_voltar_ao_menu)
	linha_botoes.add_child(_btn_voltar)

	_btn_iniciar = Button.new()
	_btn_iniciar.text = "INICIAR PARTIDA"
	_btn_iniciar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_iniciar.custom_minimum_size = Vector2(0.0, 70.0)
	_btn_iniciar.add_theme_stylebox_override(
		"normal",
		_estilo_botao(Color(0.18, 0.34, 0.52, 1.0))
	)
	_btn_iniciar.add_theme_stylebox_override(
		"hover",
		_estilo_botao(Color(0.28, 0.56, 0.76, 1.0))
	)
	_aplicar_fonte(_btn_iniciar, 32, 4)
	_btn_iniciar.pressed.connect(_iniciar_partida)
	linha_botoes.add_child(_btn_iniciar)

	_btn_voltar.focus_neighbor_right = (
		_btn_voltar.get_path_to(_btn_iniciar)
	)
	_btn_iniciar.focus_neighbor_left = (
		_btn_iniciar.get_path_to(_btn_voltar)
	)


func _criar_botao_personagem(
	personagem_id: String,
	dados: Dictionary
) -> Button:
	var botao := Button.new()
	botao.name = "Btn" + personagem_id.capitalize()
	botao.custom_minimum_size = Vector2(330.0, 145.0)
	botao.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	botao.toggle_mode = true
	botao.text = str(dados.get("nome", personagem_id)).to_upper()
	botao.tooltip_text = (
		"Selecionar " + str(dados.get("nome", personagem_id))
	)
	botao.add_theme_stylebox_override(
		"normal",
		_estilo_botao(Color(0.17, 0.16, 0.23, 1.0))
	)
	botao.add_theme_stylebox_override(
		"hover",
		_estilo_botao(Color(0.45, 0.33, 0.42, 1.0))
	)
	botao.add_theme_stylebox_override(
		"pressed",
		_estilo_botao(Color(0.57, 0.39, 0.48, 1.0))
	)
	botao.add_theme_color_override("font_color", COR_TEXTO)
	botao.add_theme_color_override(
		"font_pressed_color",
		Color.WHITE
	)
	botao.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	botao.expand_icon = true

	var caminho_imagem: String = str(dados.get("imagem", ""))
	if ResourceLoader.exists(caminho_imagem):
		botao.icon = load(caminho_imagem) as Texture2D

	_aplicar_fonte(botao, 25, 3)
	botao.pressed.connect(
		_selecionar_personagem.bind(personagem_id)
	)
	return botao


func _selecionar_personagem(personagem_id: String) -> void:
	if not PERSONAGENS.has(personagem_id):
		return

	_personagem_selecionado = personagem_id

	for id_variant: Variant in _botoes_personagens.keys():
		var id_botao: String = str(id_variant)
		var botao: Button = (
			_botoes_personagens[id_botao] as Button
		)
		if botao != null:
			botao.set_pressed_no_signal(
				id_botao == personagem_id
			)

	var dados: Dictionary = PERSONAGENS[personagem_id]
	_label_nome.text = str(dados.get("nome", "")).to_upper()
	_label_alcunha.text = str(
		dados.get("alcunha", "")
	).to_upper()
	_label_lore.text = "\"%s\"" % str(dados.get("lore", ""))
	_label_habilidades.text = (
		"PASSIVAS\n%s\n\nHABILIDADE ATIVA\n%s"
		% [
			str(dados.get("passiva", "")),
			str(dados.get("ativa", "")),
		]
	)

	var caminho_imagem: String = str(dados.get("imagem", ""))
	if ResourceLoader.exists(caminho_imagem):
		_retrato_grande.texture = load(
			caminho_imagem
		) as Texture2D
	else:
		_retrato_grande.texture = null

	_atualizar_resumo_partida()


func _ao_quantidade_bots_alterada(indice: int) -> void:
	if _seletor_bots == null:
		return
	_quantidade_bots = _seletor_bots.get_item_id(indice)
	_quantidade_bots = clampi(_quantidade_bots, 1, 5)
	_atualizar_resumo_partida()


func _atualizar_resumo_partida() -> void:
	if _label_resumo_partida == null:
		return

	var total_jogadores: int = _quantidade_bots + 1
	_label_resumo_partida.text = (
		"PARTIDA COM %d JOGADORES • %d HUMANO • %d IA\n"
		+ "Os adversários e a ordem dos turnos serão sorteados."
	) % [
		total_jogadores,
		1,
		_quantidade_bots,
	]


func _iniciar_partida() -> void:
	if _iniciando_partida:
		return

	if not Global.configurar_partida_singleplayer(
		_personagem_selecionado,
		_quantidade_bots
	):
		push_error(
			"Não foi possível configurar a partida singleplayer."
		)
		return

	_iniciando_partida = true
	_btn_iniciar.disabled = true
	_btn_voltar.disabled = true
	_btn_iniciar.text = "PREPARANDO..."

	await _executar_transicao(
		Color(0.05, 0.10, 0.18, 1.0)
	)

	if not ResourceLoader.exists(CENA_TABULEIRO):
		push_error(
			"Cena do tabuleiro não encontrada: " + CENA_TABULEIRO
		)
		Global.preparar_modo_singleplayer(_quantidade_bots)
		_restaurar_apos_falha()
		return

	var erro: Error = get_tree().change_scene_to_file(
		CENA_TABULEIRO
	)
	if erro != OK:
		push_error(
			"Falha ao abrir a partida singleplayer. Código: %s"
			% erro
		)
		Global.preparar_modo_singleplayer(_quantidade_bots)
		_restaurar_apos_falha()


func _voltar_ao_menu() -> void:
	if _iniciando_partida:
		return

	_iniciando_partida = true
	Global.limpar_partida_singleplayer()
	if _btn_iniciar != null:
		_btn_iniciar.disabled = true
	if _btn_voltar != null:
		_btn_voltar.disabled = true

	await _executar_transicao(
		Color(0.035, 0.02, 0.045, 1.0)
	)

	var erro: Error = get_tree().change_scene_to_file(
		CENA_MENU_PRINCIPAL
	)
	if erro != OK:
		push_error(
			"Falha ao voltar ao menu. Código: %s" % erro
		)
		_restaurar_apos_falha()


func _executar_transicao(cor_final: Color) -> void:
	_fade_transicao.visible = true
	_fade_transicao.color = Color(
		cor_final.r,
		cor_final.g,
		cor_final.b,
		0.0
	)

	var tween := create_tween().set_parallel(true)
	(
		tween
		. tween_property(
			_fade_transicao,
			"color",
			cor_final,
			0.48
		)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN_OUT)
	)
	if _conteudo_principal != null:
		(
			tween
			. tween_property(
				_conteudo_principal,
				"modulate:a",
				0.0,
				0.34
			)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_IN)
		)

	await tween.finished


func _restaurar_apos_falha() -> void:
	_iniciando_partida = false
	_btn_iniciar.disabled = false
	_btn_voltar.disabled = false
	_btn_iniciar.text = "INICIAR PARTIDA"

	var tween := create_tween().set_parallel(true)
	(
		tween
		. tween_property(
			_fade_transicao,
			"modulate:a",
			0.0,
			0.24
		)
	)
	if _conteudo_principal != null:
		tween.tween_property(
			_conteudo_principal,
			"modulate:a",
			1.0,
			0.24
		)
	await tween.finished
	_fade_transicao.visible = false
	_fade_transicao.modulate.a = 1.0


func _animar_entrada() -> void:
	if _conteudo_principal == null:
		return

	_conteudo_principal.modulate.a = 0.0
	_conteudo_principal.scale = Vector2(0.975, 0.975)
	_conteudo_principal.pivot_offset = (
		_conteudo_principal.size * 0.5
	)

	var tween := create_tween().set_parallel(true)
	(
		tween
		. tween_property(
			_conteudo_principal,
			"modulate:a",
			1.0,
			0.38
		)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tween
		. tween_property(
			_conteudo_principal,
			"scale",
			Vector2.ONE,
			0.52
		)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)

	await tween.finished

	if _botoes_personagens.has(_personagem_selecionado):
		var botao: Button = (
			_botoes_personagens[_personagem_selecionado]
			as Button
		)
		if botao != null:
			botao.grab_focus()


func _configurar_margens(
	margem: MarginContainer,
	valor: int
) -> void:
	margem.add_theme_constant_override("margin_left", valor)
	margem.add_theme_constant_override("margin_top", valor)
	margem.add_theme_constant_override("margin_right", valor)
	margem.add_theme_constant_override("margin_bottom", valor)


func _aplicar_fonte(
	controle: Control,
	tamanho: int,
	contorno: int = 3
) -> void:
	if _fonte != null:
		controle.add_theme_font_override("font", _fonte)
	controle.add_theme_font_size_override("font_size", tamanho)
	controle.add_theme_color_override(
		"font_outline_color",
		Color(0.0, 0.0, 0.0, 0.96)
	)
	controle.add_theme_constant_override(
		"outline_size",
		contorno
	)


func _estilo_painel(
	cor_fundo: Color,
	cor_borda: Color,
	largura: int
) -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = cor_fundo
	estilo.border_color = cor_borda
	estilo.set_border_width_all(largura)
	estilo.corner_radius_top_left = 8
	estilo.corner_radius_top_right = 8
	estilo.corner_radius_bottom_left = 8
	estilo.corner_radius_bottom_right = 8
	estilo.shadow_color = Color(0.0, 0.0, 0.0, 0.72)
	estilo.shadow_size = 8
	estilo.shadow_offset = Vector2(0.0, 5.0)
	return estilo


func _estilo_botao(cor_fundo: Color) -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = cor_fundo
	estilo.border_color = Color(0.025, 0.022, 0.035, 1.0)
	estilo.set_border_width_all(4)
	estilo.corner_radius_top_left = 6
	estilo.corner_radius_top_right = 6
	estilo.corner_radius_bottom_left = 6
	estilo.corner_radius_bottom_right = 6
	estilo.content_margin_left = 16.0
	estilo.content_margin_right = 16.0
	estilo.content_margin_top = 10.0
	estilo.content_margin_bottom = 10.0
	estilo.shadow_color = Color(0.0, 0.0, 0.0, 0.72)
	estilo.shadow_size = 5
	estilo.shadow_offset = Vector2(0.0, 4.0)
	return estilo
