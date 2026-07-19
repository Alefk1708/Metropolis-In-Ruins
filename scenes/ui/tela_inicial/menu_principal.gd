extends Control

# Distância horizontal de onde os botões começam a animação.
@export_range(80.0, 600.0, 10.0) var distancia_entrada: float = 300.0
# Tempo de entrada de cada botão.
@export_range(0.2, 1.5, 0.05) var duracao_entrada: float = 0.95
# Intervalo entre a entrada de um botão e o próximo.
@export_range(0.05, 0.5, 0.01) var intervalo_entre_botoes: float = 0.24

# Apresentação geral da tela antes da entrada dos elementos interativos.
@export_range(0.35, 1.8, 0.05) var duracao_fade_tela: float = 0.90
@export_range(1.0, 1.08, 0.005) var zoom_inicial_fundo: float = 1.035
@export_range(0.0, 0.6, 0.05) var intervalo_apos_fade: float = 0.15

# Tempo que o jogador consegue ver cada animação antes da ação do botão.
@export_range(0.2, 1.5, 0.05) var tempo_antes_partida_local: float = 0.42
@export_range(0.2, 1.5, 0.05) var tempo_antes_partida_online: float = 0.42
@export_range(0.2, 1.2, 0.05) var tempo_antes_sair: float = 0.38

# Cena aberta pelo novo botão de tutorial e duração do fechamento cinematográfico.
@export_file("*.tscn") var cena_tutorial: String = "res://scenes/ui/tutorial/tutorial.tscn"
@export_range(0.25, 1.2, 0.05) var duracao_transicao_tela: float = 0.50

# Mantém as cores originais quando os botões estão temporariamente bloqueados.
# Somente o alfa é reduzido; nenhum estado visual "disabled" cinza é usado.
const OPACIDADE_BOTOES_BLOQUEADOS: float = 0.90
const META_ENTRADA_DETALHADA_POS_CINEMATICA: String = "entrada_detalhada_menu_pos_cinematica"

const FONTE_PERFIL: Font = preload("res://assets/fonts/m5x7.ttf")

# Áreas dos dois "S" na textura original LogoMetropolis.png (1394 x 563).
# O S superior, em METROPOLIS, ativa a neve. O S inferior, em RUINS, ativa as rosas.
const RETANGULO_S_METROPOLIS_LOGO: Rect2 = Rect2(1218.0, 16.0, 168.0, 244.0)
const RETANGULO_S_RUINS_LOGO: Rect2 = Rect2(1038.0, 300.0, 184.0, 246.0)
const CLIQUES_EASTER_EGG: int = 7
const DURACAO_NEVE_EASTER_EGG: float = 6.0
const INTERVALO_GERACAO_NEVE: float = 0.085
const JANELA_ANTI_DUPLICACAO_CLIQUE_MS: int = 140

const FLOCO_NEVE_1: Texture2D = preload("res://assets/textures/easter_egg/floco_neve_1.png")
const FLOCO_NEVE_2: Texture2D = preload("res://assets/textures/easter_egg/floco_neve_2.png")
const FLOCO_NEVE_3: Texture2D = preload("res://assets/textures/easter_egg/floco_neve_3.png")

@onready var btn_local: Button = $ContainerBotoes/VBoxBotoes/BtnLocal
@onready var btn_online: Button = $ContainerBotoes/VBoxBotoes/BtnOnline
@onready var btn_opcoes: Button = $ContainerBotoes/VBoxBotoes/BtnOpcoes
@onready var btn_sair: Button = $ContainerBotoes/VBoxBotoes/BtnSair
@onready var btn_tutorial: Button = $TutorialContainer/BtnTutorial
@onready var fundo_cidade: TextureRect = $FundoCidade
@onready var logo_metropolis: TextureRect = $LogoMetropolis
@onready var container_botoes: PanelContainer = $ContainerBotoes
@onready var tutorial_container: PanelContainer = $TutorialContainer

var _tween_fade_tela: Tween
var _tween_painel_menu: Tween
var _camada_fade_entrada: ColorRect
var _tween_entrada: Tween
var _tween_entrada_tutorial: Tween
var _tween_transicao_tela: Tween
var _camada_transicao_tela: ColorRect
var _acao_em_andamento: bool = false
var _apresentacao_inicial_ativa: bool = true

@onready var _painel_resumo_perfil: PanelContainer = %ResumoPerfilProgressao
@onready var _label_nome_resumo: Label = %LabelNomeResumo
@onready var _label_nivel_resumo: Label = %LabelNivelResumo
@onready var _label_xp_resumo: Label = %LabelXpResumo
@onready var _btn_perfil: Button = %BtnAbrirPerfil

@onready var _modal_perfil: Control = %ModalPerfilProgressao
@onready var _painel_modal_perfil: PanelContainer = %PainelPerfilCompleto
@onready var _input_nome_perfil: LineEdit = %InputNomePerfil
@onready var _label_dados_perfil: Label = %LabelDadosPerfil
@onready var _barra_xp_perfil: ProgressBar = %BarraXpPerfil
@onready var _label_barra_xp_perfil: Label = %LabelBarraXpPerfil


@onready var _easter_egg_overlay: Control = %EasterEggOverlay
@onready var _ceu_easter_egg: TextureRect = %CeuEstrelado
@onready var _lua_easter_egg: TextureRect = %Lua
@onready var _rosas_layer: Control = %RosasLayer
@onready var _rosa_template: Control = $EasterEggOverlay/RosasLayer/RosaTemplate

var _tween_resumo_perfil: Tween
var _tween_modal_perfil: Tween

var _modal_opcoes: Control
var _painel_opcoes: PanelContainer
var _slider_volume: HSlider
var _check_tela_cheia: CheckButton
var _label_volume: Label
var _tween_opcoes: Tween


var _contador_cliques_s_metropolis: int = 0
var _contador_cliques_s_ruins: int = 0
var _easter_egg_ativo: bool = false
var _rosas_easter_egg: Array[Control] = []
var _floquinhos_easter_egg: Array[TextureRect] = []
var _rng_easter_egg: RandomNumberGenerator = RandomNumberGenerator.new()
var _tempo_restante_neve: float = 0.0
var _acumulador_spawn_neve: float = 0.0
var _ultimo_clique_easter_ms: int = -1000
var _ultima_posicao_clique_easter: Vector2 = Vector2(-9999.0, -9999.0)


func _ready() -> void:
	var entrada_pos_cinematica := _consumir_marcador_entrada_pos_cinematica()
	if entrada_pos_cinematica:
		_preparar_apresentacao_inicial()
	else:
		_preparar_apresentacao_retorno()
	_rng_easter_egg.randomize()
	_criar_modal_opcoes()
	_preparar_overlay_easter_egg()
	if not Progressao.perfil_atualizado.is_connected(_atualizar_interface_perfil):
		Progressao.perfil_atualizado.connect(_atualizar_interface_perfil)
	_atualizar_interface_perfil(Progressao.obter_perfil())
	# Aguarda os containers calcularem suas posições e tamanhos definitivos.
	await get_tree().process_frame
	await get_tree().process_frame
	if entrada_pos_cinematica:
		await _reproduzir_apresentacao_pos_cinematica()
	else:
		_reproduzir_apresentacao_retorno()


func _unhandled_input(event: InputEvent) -> void:
	if _easter_egg_ativo:
		return

	if not event.is_action_pressed("ui_cancel"):
		return

	if _modal_opcoes != null and is_instance_valid(_modal_opcoes) and _modal_opcoes.visible:
		_fechar_opcoes()
		get_viewport().set_input_as_handled()
		return

	if _modal_perfil != null and is_instance_valid(_modal_perfil) and _modal_perfil.visible:
		_fechar_perfil()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _tempo_restante_neve <= 0.0 and _floquinhos_easter_egg.is_empty():
		return
	_atualizar_easter_egg_neve(delta)


func _consumir_marcador_entrada_pos_cinematica() -> bool:
	var arvore := get_tree()
	var entrada_pos_cinematica := bool(
		arvore.get_meta(META_ENTRADA_DETALHADA_POS_CINEMATICA, false)
	)
	if arvore.has_meta(META_ENTRADA_DETALHADA_POS_CINEMATICA):
		arvore.remove_meta(META_ENTRADA_DETALHADA_POS_CINEMATICA)
	return entrada_pos_cinematica


func _reproduzir_apresentacao_pos_cinematica() -> void:
	await _animar_entrada_tela()
	if intervalo_apos_fade > 0.0:
		await get_tree().create_timer(intervalo_apos_fade).timeout
	_animar_apresentacao_logo()
	_animar_entrada_painel_menu()
	# O pequeno intervalo deixa o painel ser percebido antes de seus botões.
	await get_tree().create_timer(0.22).timeout
	animar_entrada_botoes()
	_animar_entrada_tutorial(0.08)
	_animar_entrada_resumo_perfil()


func _reproduzir_apresentacao_retorno() -> void:
	# Ao voltar do jogo, lobby ou outras telas, mantém somente a apresentação
	# rápida que já existia: logo e botões.
	_animar_apresentacao_logo()
	animar_entrada_botoes()
	_animar_entrada_tutorial(0.06)


func _preparar_apresentacao_inicial() -> void:
	# Tudo é preparado antes do primeiro frame para não existir um clarão dos
	# elementos em suas posições finais.
	_apresentacao_inicial_ativa = true
	modulate.a = 1.0
	_criar_camada_fade_entrada()
	logo_metropolis.modulate.a = 0.0
	logo_metropolis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container_botoes.modulate.a = 0.0
	tutorial_container.modulate.a = 0.0

	for botao: Button in _todos_botoes_menu():
		botao.modulate.a = 0.0
		botao.mouse_filter = Control.MOUSE_FILTER_IGNORE
		botao.focus_mode = Control.FOCUS_NONE

	if _painel_resumo_perfil != null and is_instance_valid(_painel_resumo_perfil):
		_painel_resumo_perfil.modulate.a = 0.0
	if _btn_perfil != null and is_instance_valid(_btn_perfil):
		_btn_perfil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_btn_perfil.focus_mode = Control.FOCUS_NONE


func _preparar_apresentacao_retorno() -> void:
	# Não esconde nem move o cenário, o painel principal ou o resumo do perfil.
	# Somente logo e botões são preparados para a animação curta.
	_apresentacao_inicial_ativa = true
	modulate.a = 1.0
	fundo_cidade.scale = Vector2.ONE
	container_botoes.modulate.a = 1.0
	container_botoes.scale = Vector2.ONE
	tutorial_container.modulate.a = 0.0
	logo_metropolis.modulate.a = 0.0
	logo_metropolis.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for botao: Button in _todos_botoes_menu():
		botao.modulate.a = 0.0
		botao.mouse_filter = Control.MOUSE_FILTER_IGNORE
		botao.focus_mode = Control.FOCUS_NONE

	if _painel_resumo_perfil != null and is_instance_valid(_painel_resumo_perfil):
		_painel_resumo_perfil.modulate.a = 1.0
		_painel_resumo_perfil.scale = Vector2.ONE
	if _btn_perfil != null and is_instance_valid(_btn_perfil):
		_btn_perfil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_btn_perfil.focus_mode = Control.FOCUS_NONE


func _criar_camada_fade_entrada() -> void:
	_camada_fade_entrada = ColorRect.new()
	_camada_fade_entrada.name = "FadeEntrada"
	add_child(_camada_fade_entrada)
	_camada_fade_entrada.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_camada_fade_entrada.color = Color(0.004, 0.005, 0.019, 1.0)
	_camada_fade_entrada.mouse_filter = Control.MOUSE_FILTER_STOP
	_camada_fade_entrada.z_index = 4000


func _animar_entrada_tela() -> void:
	if _tween_fade_tela != null and _tween_fade_tela.is_valid():
		_tween_fade_tela.kill()

	fundo_cidade.pivot_offset = fundo_cidade.size * 0.5
	fundo_cidade.scale = Vector2.ONE * zoom_inicial_fundo

	_tween_fade_tela = create_tween().set_parallel(true)
	(
		_tween_fade_tela
		. tween_property(_camada_fade_entrada, "modulate:a", 0.0, duracao_fade_tela)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_tween_fade_tela
		. tween_property(fundo_cidade, "scale", Vector2.ONE, duracao_fade_tela + 0.24)
		. set_trans(Tween.TRANS_QUINT)
		. set_ease(Tween.EASE_OUT)
	)

	await _tween_fade_tela.finished
	fundo_cidade.scale = Vector2.ONE
	if _camada_fade_entrada != null and is_instance_valid(_camada_fade_entrada):
		_camada_fade_entrada.queue_free()
	_camada_fade_entrada = null


func _animar_entrada_painel_menu() -> void:
	if _tween_painel_menu != null and _tween_painel_menu.is_valid():
		_tween_painel_menu.kill()

	var posicao_final := container_botoes.position
	container_botoes.pivot_offset = container_botoes.size * 0.5
	container_botoes.position = posicao_final + Vector2(0.0, 24.0)
	container_botoes.scale = Vector2(0.975, 0.975)
	container_botoes.modulate.a = 0.0

	_tween_painel_menu = create_tween().set_parallel(true)
	(
		_tween_painel_menu
		. tween_property(container_botoes, "position", posicao_final, 0.58)
		. set_trans(Tween.TRANS_QUINT)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_tween_painel_menu
		. tween_property(container_botoes, "scale", Vector2.ONE, 0.62)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_tween_painel_menu
		. tween_property(container_botoes, "modulate:a", 1.0, 0.36)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)


func _animar_apresentacao_logo() -> void:
	if logo_metropolis == null or not is_instance_valid(logo_metropolis):
		return

	var posicao_final := logo_metropolis.position
	logo_metropolis.position = posicao_final + Vector2(0.0, -28.0)
	logo_metropolis.modulate.a = 0.0
	logo_metropolis.scale = Vector2(0.97, 0.97)
	logo_metropolis.pivot_offset = logo_metropolis.size * 0.5

	var tween := create_tween().set_parallel(true)
	(
		tween
		. tween_property(logo_metropolis, "position", posicao_final, 0.72)
		. set_trans(Tween.TRANS_QUINT)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tween
		. tween_property(logo_metropolis, "modulate:a", 1.0, 0.48)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tween
		. tween_property(logo_metropolis, "scale", Vector2.ONE, 0.78)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)


func _botoes_principais_menu() -> Array[Button]:
	return [btn_local, btn_online, btn_opcoes, btn_sair]


func _todos_botoes_menu() -> Array[Button]:
	return [btn_local, btn_online, btn_opcoes, btn_sair, btn_tutorial]


func _animar_entrada_tutorial(atraso: float) -> void:
	if tutorial_container == null or not is_instance_valid(tutorial_container):
		return
	if btn_tutorial == null or not is_instance_valid(btn_tutorial):
		return
	if _tween_entrada_tutorial != null and _tween_entrada_tutorial.is_valid():
		_tween_entrada_tutorial.kill()

	var posicao_final: Vector2 = tutorial_container.position
	var atraso_seguro: float = maxf(atraso, 0.0)
	tutorial_container.pivot_offset = tutorial_container.size * 0.5
	tutorial_container.position = posicao_final + Vector2(-58.0, -18.0)
	tutorial_container.scale = Vector2(0.86, 0.86)
	tutorial_container.rotation = deg_to_rad(-2.5)
	tutorial_container.modulate.a = 0.0
	btn_tutorial.modulate.a = 0.0
	btn_tutorial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn_tutorial.focus_mode = Control.FOCUS_NONE

	_tween_entrada_tutorial = create_tween().set_parallel(true)
	(
		_tween_entrada_tutorial
		. tween_property(tutorial_container, "position", posicao_final, 0.66)
		. set_delay(atraso_seguro)
		. set_trans(Tween.TRANS_QUINT)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_tween_entrada_tutorial
		. tween_property(tutorial_container, "scale", Vector2.ONE, 0.72)
		. set_delay(atraso_seguro)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_tween_entrada_tutorial
		. tween_property(tutorial_container, "rotation", 0.0, 0.62)
		. set_delay(atraso_seguro)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_tween_entrada_tutorial
		. tween_property(tutorial_container, "modulate:a", 1.0, 0.34)
		. set_delay(atraso_seguro)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_tween_entrada_tutorial
		. tween_property(btn_tutorial, "modulate:a", 1.0, 0.42)
		. set_delay(atraso_seguro + 0.08)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)


func _animar_botao_acionado(botao: Button, cor_luz: Color) -> void:
	if botao == null or not is_instance_valid(botao):
		return
	botao.pivot_offset = botao.size * 0.5
	var cor_original := botao.modulate
	var tween := create_tween()
	(
		tween
		. tween_property(botao, "scale", Vector2(0.965, 0.965), 0.08)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	tween.parallel().tween_property(botao, "modulate", cor_luz, 0.08)
	(
		tween
		. tween_property(botao, "scale", Vector2(1.025, 1.025), 0.12)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	tween.parallel().tween_property(botao, "modulate", cor_original, 0.16)
	(
		tween
		. tween_property(botao, "scale", Vector2.ONE, 0.16)
		. set_trans(Tween.TRANS_ELASTIC)
		. set_ease(Tween.EASE_OUT)
	)


func _criar_modal_opcoes() -> void:
	if _modal_opcoes != null and is_instance_valid(_modal_opcoes):
		return

	_modal_opcoes = Control.new()
	_modal_opcoes.name = "ModalOpcoes"
	_modal_opcoes.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_opcoes.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_opcoes.z_index = 1800
	_modal_opcoes.visible = false
	add_child(_modal_opcoes)

	var fundo := ColorRect.new()
	fundo.name = "FundoEscurecidoOpcoes"
	fundo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fundo.color = Color(0.01, 0.008, 0.018, 0.88)
	fundo.mouse_filter = Control.MOUSE_FILTER_STOP
	fundo.gui_input.connect(_ao_clicar_fundo_opcoes)
	_modal_opcoes.add_child(fundo)

	var centro := CenterContainer.new()
	centro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_opcoes.add_child(centro)

	_painel_opcoes = PanelContainer.new()
	_painel_opcoes.name = "PainelOpcoes"
	_painel_opcoes.custom_minimum_size = Vector2(720.0, 500.0)
	_painel_opcoes.mouse_filter = Control.MOUSE_FILTER_STOP
	_painel_opcoes.add_theme_stylebox_override(
		"panel",
		_estilo_perfil(Color(0.07, 0.06, 0.10, 0.99), Color(0.58, 0.55, 0.65, 1.0), 5)
	)
	centro.add_child(_painel_opcoes)

	var margem := MarginContainer.new()
	margem.add_theme_constant_override("margin_left", 46)
	margem.add_theme_constant_override("margin_right", 46)
	margem.add_theme_constant_override("margin_top", 38)
	margem.add_theme_constant_override("margin_bottom", 38)
	_painel_opcoes.add_child(margem)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	margem.add_child(vbox)

	var titulo := Label.new()
	titulo.text = "OPÇÕES"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_color_override("font_color", Color(1.0, 0.78, 0.78))
	_aplicar_fonte_perfil(titulo, 48, 5)
	vbox.add_child(titulo)

	var linha := ColorRect.new()
	linha.custom_minimum_size = Vector2(0.0, 4.0)
	linha.color = Color(0.55, 0.51, 0.61, 1.0)
	linha.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(linha)

	var rotulo_volume := Label.new()
	rotulo_volume.text = "VOLUME GERAL"
	rotulo_volume.add_theme_color_override("font_color", Color.WHITE)
	_aplicar_fonte_perfil(rotulo_volume, 29, 3)
	vbox.add_child(rotulo_volume)

	var linha_volume := HBoxContainer.new()
	linha_volume.add_theme_constant_override("separation", 18)
	vbox.add_child(linha_volume)

	_slider_volume = HSlider.new()
	_slider_volume.min_value = 0.0
	_slider_volume.max_value = 100.0
	_slider_volume.step = 1.0
	_slider_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider_volume.custom_minimum_size = Vector2(0.0, 54.0)
	var volume_linear := db_to_linear(AudioServer.get_bus_volume_db(0))
	_slider_volume.value = clampf(volume_linear * 100.0, 0.0, 100.0)
	_slider_volume.value_changed.connect(_alterar_volume)
	linha_volume.add_child(_slider_volume)

	_label_volume = Label.new()
	_label_volume.custom_minimum_size = Vector2(105.0, 54.0)
	_label_volume.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label_volume.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label_volume.add_theme_color_override("font_color", Color(0.65, 0.88, 1.0))
	_aplicar_fonte_perfil(_label_volume, 28, 3)
	linha_volume.add_child(_label_volume)
	_atualizar_texto_volume(_slider_volume.value)

	_check_tela_cheia = CheckButton.new()
	_check_tela_cheia.text = "TELA CHEIA"
	_check_tela_cheia.button_pressed = (
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	)
	_check_tela_cheia.add_theme_color_override("font_color", Color.WHITE)
	_check_tela_cheia.add_theme_color_override("font_hover_color", Color(1.0, 0.78, 0.78))
	_aplicar_fonte_perfil(_check_tela_cheia, 30, 3)
	_check_tela_cheia.toggled.connect(_alternar_tela_cheia)
	_check_tela_cheia.visible = not OS.has_feature("mobile")
	vbox.add_child(_check_tela_cheia)

	var espacador := Control.new()
	espacador.custom_minimum_size = Vector2(0.0, 12.0)
	vbox.add_child(espacador)

	var btn_voltar := Button.new()
	btn_voltar.text = "VOLTAR"
	btn_voltar.custom_minimum_size = Vector2(0.0, 76.0)
	btn_voltar.add_theme_stylebox_override(
		"normal",
		_estilo_perfil(Color(0.20, 0.18, 0.27, 1.0), Color(0.42, 0.40, 0.50, 1.0), 4)
	)
	btn_voltar.add_theme_stylebox_override(
		"hover",
		_estilo_perfil(Color(0.52, 0.38, 0.46, 1.0), Color(1.0, 0.78, 0.76, 1.0), 4)
	)
	btn_voltar.add_theme_stylebox_override(
		"pressed",
		_estilo_perfil(Color(0.30, 0.19, 0.25, 1.0), Color(1.0, 0.67, 0.70, 1.0), 4)
	)
	btn_voltar.add_theme_color_override("font_color", Color.WHITE)
	btn_voltar.add_theme_color_override("font_hover_color", Color.WHITE)
	btn_voltar.add_theme_color_override("font_pressed_color", Color(1.0, 0.86, 0.86))
	_aplicar_fonte_perfil(btn_voltar, 35, 4)
	btn_voltar.pressed.connect(_fechar_opcoes)
	vbox.add_child(btn_voltar)


func _abrir_opcoes() -> void:
	if _modal_opcoes == null or not is_instance_valid(_modal_opcoes):
		return
	if _tween_opcoes != null and _tween_opcoes.is_valid():
		_tween_opcoes.kill()

	_modal_opcoes.visible = true
	_modal_opcoes.modulate.a = 0.0
	_painel_opcoes.pivot_offset = _painel_opcoes.size * 0.5
	_painel_opcoes.scale = Vector2(0.94, 0.94)
	get_viewport().gui_release_focus()

	_tween_opcoes = create_tween().set_parallel(true)
	(
		_tween_opcoes
		. tween_property(_modal_opcoes, "modulate:a", 1.0, 0.18)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_tween_opcoes
		. tween_property(_painel_opcoes, "scale", Vector2.ONE, 0.28)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	if _slider_volume != null:
		_slider_volume.grab_focus()


func _fechar_opcoes() -> void:
	if _modal_opcoes == null or not is_instance_valid(_modal_opcoes) or not _modal_opcoes.visible:
		return
	if _tween_opcoes != null and _tween_opcoes.is_valid():
		_tween_opcoes.kill()

	_tween_opcoes = create_tween().set_parallel(true)
	(
		_tween_opcoes
		. tween_property(_modal_opcoes, "modulate:a", 0.0, 0.14)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
	(
		_tween_opcoes
		. tween_property(_painel_opcoes, "scale", Vector2(0.97, 0.97), 0.14)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
	_tween_opcoes.chain().tween_callback(_concluir_fechamento_opcoes)


func _concluir_fechamento_opcoes() -> void:
	_modal_opcoes.visible = false
	_modal_opcoes.modulate.a = 1.0
	_painel_opcoes.scale = Vector2.ONE
	btn_opcoes.grab_focus()


func _ao_clicar_fundo_opcoes(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var clique := event as InputEventMouseButton
		if clique.pressed and clique.button_index == MOUSE_BUTTON_LEFT:
			_fechar_opcoes()
	elif event is InputEventScreenTouch:
		var toque := event as InputEventScreenTouch
		if toque.pressed:
			_fechar_opcoes()


func _alterar_volume(valor: float) -> void:
	var volume_linear := maxf(valor / 100.0, 0.0001)
	AudioServer.set_bus_volume_db(0, linear_to_db(volume_linear))
	AudioServer.set_bus_mute(0, valor <= 0.0)
	_atualizar_texto_volume(valor)


func _atualizar_texto_volume(valor: float) -> void:
	if _label_volume != null and is_instance_valid(_label_volume):
		_label_volume.text = "%d%%" % int(round(valor))


func _alternar_tela_cheia(ativado: bool) -> void:
	if OS.has_feature("mobile"):
		return
	if ativado:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)


func _estilo_perfil(cor_fundo: Color, cor_borda: Color, largura_borda: int = 3) -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = cor_fundo
	estilo.border_color = cor_borda
	estilo.set_border_width_all(largura_borda)
	estilo.corner_radius_top_left = 8
	estilo.corner_radius_top_right = 8
	estilo.corner_radius_bottom_left = 8
	estilo.corner_radius_bottom_right = 8
	estilo.content_margin_left = 18.0
	estilo.content_margin_right = 18.0
	estilo.content_margin_top = 12.0
	estilo.content_margin_bottom = 12.0
	return estilo


func _aplicar_fonte_perfil(controle: Control, tamanho: int, contorno: int = 3) -> void:
	controle.add_theme_font_override("font", FONTE_PERFIL)
	controle.add_theme_font_size_override("font_size", tamanho)
	controle.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	controle.add_theme_constant_override("outline_size", contorno)


func _animar_entrada_resumo_perfil() -> void:
	if _painel_resumo_perfil == null or not is_instance_valid(_painel_resumo_perfil):
		return
	if _tween_resumo_perfil != null and _tween_resumo_perfil.is_valid():
		_tween_resumo_perfil.kill()

	_painel_resumo_perfil.pivot_offset = _painel_resumo_perfil.size
	_painel_resumo_perfil.modulate.a = 0.0
	_painel_resumo_perfil.scale = Vector2(0.93, 0.93)
	_btn_perfil.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_tween_resumo_perfil = create_tween()
	_tween_resumo_perfil.tween_interval(0.50)
	(
		_tween_resumo_perfil
		. tween_property(_painel_resumo_perfil, "modulate:a", 1.0, 0.45)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_tween_resumo_perfil
		. parallel()
		. tween_property(_painel_resumo_perfil, "scale", Vector2.ONE, 0.55)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	_tween_resumo_perfil.chain().tween_callback(_liberar_interacao_resumo_perfil)


func _liberar_interacao_resumo_perfil() -> void:
	if _apresentacao_inicial_ativa:
		return
	if _btn_perfil == null or not is_instance_valid(_btn_perfil):
		return
	_btn_perfil.mouse_filter = Control.MOUSE_FILTER_STOP
	_btn_perfil.focus_mode = Control.FOCUS_ALL


func _atualizar_interface_perfil(perfil_recebido: Dictionary = {}) -> void:
	var perfil := perfil_recebido if not perfil_recebido.is_empty() else Progressao.obter_perfil()
	var xp_total := int(perfil.get("xp_total", 0))
	var nivel := int(perfil.get("nivel", Progressao.calcular_nivel(xp_total)))
	var xp_nivel := Progressao.xp_no_nivel_atual(xp_total)
	var xp_proximo := Progressao.xp_necessario_para_proximo_nivel(nivel)
	var nome := str(perfil.get("nome", "JOGADOR"))

	if _label_nome_resumo != null and is_instance_valid(_label_nome_resumo):
		_label_nome_resumo.text = nome.to_upper()
	if _label_nivel_resumo != null and is_instance_valid(_label_nivel_resumo):
		_label_nivel_resumo.text = "NÍVEL %d" % nivel
	if _label_xp_resumo != null and is_instance_valid(_label_xp_resumo):
		_label_xp_resumo.text = "%d / %d XP" % [xp_nivel, xp_proximo]
	if _input_nome_perfil != null and is_instance_valid(_input_nome_perfil) and not _input_nome_perfil.has_focus():
		_input_nome_perfil.text = nome
	if _barra_xp_perfil != null and is_instance_valid(_barra_xp_perfil):
		_barra_xp_perfil.max_value = max(1, xp_proximo)
		_barra_xp_perfil.value = xp_nivel
	if _label_barra_xp_perfil != null and is_instance_valid(_label_barra_xp_perfil):
		_label_barra_xp_perfil.text = "NÍVEL %d  •  %d/%d XP" % [nivel, xp_nivel, xp_proximo]
	if _label_dados_perfil != null and is_instance_valid(_label_dados_perfil):
		_label_dados_perfil.text = (
			"XP TOTAL: %d\n\n"
			+ "PARTIDAS: %d     •     VITÓRIAS: %d     •     2º LUGAR: %d     •     3º LUGAR: %d\n\n"
			+ "ELIMINAÇÕES: %d     •     MONOPÓLIOS COMPLETADOS: %d\n\n"
			+ "HABILIDADES USADAS: %d     •     ACORDOS DE 5 TURNOS: %d\n\n"
			+ "BÔNUS DE 3 EVENTOS SEGUROS: %d\n\n"
			+ "MELHOR XP EM UMA PARTIDA: %d     •     ÚLTIMA PARTIDA: +%d XP"
		) % [
			xp_total,
			int(perfil.get("partidas", 0)), int(perfil.get("vitorias", 0)),
			int(perfil.get("segundos_lugares", 0)), int(perfil.get("terceiros_lugares", 0)),
			int(perfil.get("eliminacoes", 0)), int(perfil.get("monopolios_completados", 0)),
			int(perfil.get("habilidades_usadas", 0)), int(perfil.get("acordos_cumpridos", 0)),
			int(perfil.get("bonus_eventos_seguros", 0)), int(perfil.get("melhor_xp_partida", 0)),
			int(perfil.get("ultima_partida_xp", 0)),
		]


func _abrir_perfil() -> void:
	if _modal_perfil == null or not is_instance_valid(_modal_perfil):
		return
	_atualizar_interface_perfil(Progressao.obter_perfil())
	if _tween_modal_perfil != null and _tween_modal_perfil.is_valid():
		_tween_modal_perfil.kill()

	_modal_perfil.visible = true
	_modal_perfil.modulate.a = 0.0
	_painel_modal_perfil.pivot_offset = _painel_modal_perfil.size * 0.5
	_painel_modal_perfil.scale = Vector2(0.95, 0.95)
	get_viewport().gui_release_focus()

	_tween_modal_perfil = create_tween().set_parallel(true)
	(
		_tween_modal_perfil
		. tween_property(_modal_perfil, "modulate:a", 1.0, 0.20)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_tween_modal_perfil
		. tween_property(_painel_modal_perfil, "scale", Vector2.ONE, 0.28)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)


func _fechar_perfil() -> void:
	if _modal_perfil == null or not is_instance_valid(_modal_perfil) or not _modal_perfil.visible:
		return
	if _tween_modal_perfil != null and _tween_modal_perfil.is_valid():
		_tween_modal_perfil.kill()

	_tween_modal_perfil = create_tween().set_parallel(true)
	(
		_tween_modal_perfil
		. tween_property(_modal_perfil, "modulate:a", 0.0, 0.16)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
	(
		_tween_modal_perfil
		. tween_property(_painel_modal_perfil, "scale", Vector2(0.97, 0.97), 0.16)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
	_tween_modal_perfil.chain().tween_callback(_concluir_fechamento_perfil)


func _concluir_fechamento_perfil() -> void:
	_modal_perfil.visible = false
	_modal_perfil.modulate.a = 1.0
	_painel_modal_perfil.scale = Vector2.ONE
	if _btn_perfil != null and is_instance_valid(_btn_perfil):
		_btn_perfil.grab_focus()


func _ao_clicar_fundo_perfil(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var clique := event as InputEventMouseButton
		if clique.pressed and clique.button_index == MOUSE_BUTTON_LEFT:
			_fechar_perfil()
	elif event is InputEventScreenTouch:
		var toque := event as InputEventScreenTouch
		if toque.pressed:
			_fechar_perfil()


func _ao_submeter_nome_perfil(_texto: String) -> void:
	_salvar_nome_perfil()


func _salvar_nome_perfil() -> void:
	if _input_nome_perfil == null or not is_instance_valid(_input_nome_perfil):
		return
	if not Progressao.definir_nome(_input_nome_perfil.text):
		_input_nome_perfil.placeholder_text = "O nome não pode ficar vazio"
		_input_nome_perfil.grab_focus()
		return
	_atualizar_interface_perfil(Progressao.obter_perfil())


func animar_entrada_botoes() -> void:
	if _tween_entrada and _tween_entrada.is_valid():
		_tween_entrada.kill()

	var botoes: Array[Button] = _botoes_principais_menu()
	var posicoes_finais: Array[Vector2] = []

	# Prepara todos os botões antes de iniciar a sequência.
	for botao in botoes:
		posicoes_finais.append(botao.position)
		botao.pivot_offset = botao.size * 0.5
		botao.position -= Vector2(distancia_entrada, 0.0)
		botao.modulate.a = 0.0
		botao.scale = Vector2(0.96, 0.96)
		botao.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Todas as propriedades são animadas em paralelo, mas cada botão recebe
	# um atraso progressivo para entrar de cima para baixo.
	_tween_entrada = create_tween().set_parallel(true)

	for indice in botoes.size():
		var botao := botoes[indice]
		var atraso := float(indice) * intervalo_entre_botoes

		(
			_tween_entrada
			. tween_property(botao, "position", posicoes_finais[indice], duracao_entrada)
			. set_delay(atraso)
			. set_trans(Tween.TRANS_QUINT)
			. set_ease(Tween.EASE_OUT)
		)

		(
			_tween_entrada
			. tween_property(botao, "modulate:a", 1.0, duracao_entrada * 0.72)
			. set_delay(atraso)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)

		(
			_tween_entrada
			. tween_property(botao, "scale", Vector2.ONE, duracao_entrada)
			. set_delay(atraso)
			. set_trans(Tween.TRANS_BACK)
			. set_ease(Tween.EASE_OUT)
		)

	await _tween_entrada.finished

	# Garante valores exatos ao terminar e libera a interação.
	for indice in botoes.size():
		var botao := botoes[indice]
		botao.position = posicoes_finais[indice]
		botao.modulate.a = 1.0
		botao.scale = Vector2.ONE
		botao.mouse_filter = Control.MOUSE_FILTER_STOP
		botao.focus_mode = Control.FOCUS_ALL

	_concluir_apresentacao_inicial()
	btn_local.grab_focus()


func _concluir_apresentacao_inicial() -> void:
	_apresentacao_inicial_ativa = false
	logo_metropolis.mouse_filter = Control.MOUSE_FILTER_STOP
	if btn_tutorial != null and is_instance_valid(btn_tutorial):
		btn_tutorial.modulate = Color.WHITE
		btn_tutorial.scale = Vector2.ONE
		btn_tutorial.mouse_filter = Control.MOUSE_FILTER_STOP
		btn_tutorial.focus_mode = Control.FOCUS_ALL
	if _btn_perfil != null and is_instance_valid(_btn_perfil):
		_btn_perfil.mouse_filter = Control.MOUSE_FILTER_STOP
		_btn_perfil.focus_mode = Control.FOCUS_ALL


func _definir_interacao_menu_bloqueada(bloqueada: bool) -> void:
	for botao: Button in _todos_botoes_menu():
		botao.disabled = false
		botao.mouse_filter = Control.MOUSE_FILTER_IGNORE if bloqueada else Control.MOUSE_FILTER_STOP
		botao.focus_mode = Control.FOCUS_NONE if bloqueada else Control.FOCUS_ALL
		botao.modulate = (
			Color(1.0, 1.0, 1.0, OPACIDADE_BOTOES_BLOQUEADOS)
			if bloqueada
			else Color.WHITE
		)

	if _btn_perfil != null and is_instance_valid(_btn_perfil):
		_btn_perfil.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE if bloqueada else Control.MOUSE_FILTER_STOP
		)
		_btn_perfil.focus_mode = Control.FOCUS_NONE if bloqueada else Control.FOCUS_ALL
	if _painel_resumo_perfil != null and is_instance_valid(_painel_resumo_perfil):
		_painel_resumo_perfil.modulate.a = OPACIDADE_BOTOES_BLOQUEADOS if bloqueada else 1.0


func _iniciar_acao() -> bool:
	if _acao_em_andamento or _easter_egg_ativo or _apresentacao_inicial_ativa:
		return false

	_acao_em_andamento = true
	get_viewport().gui_release_focus()
	_definir_interacao_menu_bloqueada(true)
	return true


func _finalizar_acao(botao_foco: Button) -> void:
	_acao_em_andamento = false
	_definir_interacao_menu_bloqueada(false)

	if botao_foco != null and is_instance_valid(botao_foco):
		botao_foco.grab_focus()


func _preparar_overlay_easter_egg() -> void:
	if _easter_egg_overlay == null or not is_instance_valid(_easter_egg_overlay):
		return
	_easter_egg_overlay.visible = false
	_easter_egg_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_easter_egg_overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)
	if _ceu_easter_egg != null and is_instance_valid(_ceu_easter_egg):
		_ceu_easter_egg.visible = true
		_ceu_easter_egg.modulate = Color(1.0, 1.0, 1.0, 0.0)
	if _lua_easter_egg != null and is_instance_valid(_lua_easter_egg):
		_lua_easter_egg.visible = true
		_lua_easter_egg.modulate = Color(1.0, 1.0, 1.0, 0.0)
		_lua_easter_egg.scale = Vector2(0.72, 0.72)
	if _rosa_template != null and is_instance_valid(_rosa_template):
		_rosa_template.visible = false
	_liberar_rosas_easter_egg()
	_liberar_floquinhos_easter_egg()


func _on_logo_metropolis_gui_input(event: InputEvent) -> void:
	if _easter_egg_ativo or _acao_em_andamento or _apresentacao_inicial_ativa:
		return
	if _modal_perfil != null and is_instance_valid(_modal_perfil) and _modal_perfil.visible:
		return
	if _modal_opcoes != null and is_instance_valid(_modal_opcoes) and _modal_opcoes.visible:
		return

	var posicao_clique := Vector2.ZERO
	if event is InputEventMouseButton:
		var clique_mouse := event as InputEventMouseButton
		if clique_mouse.button_index != MOUSE_BUTTON_LEFT or not clique_mouse.pressed:
			return
		posicao_clique = clique_mouse.position
	elif event is InputEventScreenTouch:
		var toque := event as InputEventScreenTouch
		if not toque.pressed:
			return
		posicao_clique = toque.position
	else:
		return

	# Em alguns celulares, um toque pode gerar também um clique de mouse emulado.
	# Esta janela impede que o mesmo toque físico seja contado duas vezes.
	var agora_ms: int = Time.get_ticks_msec()
	if (
		agora_ms - _ultimo_clique_easter_ms <= JANELA_ANTI_DUPLICACAO_CLIQUE_MS
		and posicao_clique.distance_to(_ultima_posicao_clique_easter) <= 12.0
	):
		return
	_ultimo_clique_easter_ms = agora_ms
	_ultima_posicao_clique_easter = posicao_clique

	var posicao_textura: Vector2 = _converter_posicao_logo_para_textura(posicao_clique)
	if posicao_textura.x < 0.0:
		_resetar_contadores_easter_egg()
		return

	if RETANGULO_S_METROPOLIS_LOGO.has_point(posicao_textura):
		_contador_cliques_s_metropolis += 1
		_contador_cliques_s_ruins = 0
		if _contador_cliques_s_metropolis >= CLIQUES_EASTER_EGG:
			_resetar_contadores_easter_egg()
			_executar_easter_egg_neve()
	elif RETANGULO_S_RUINS_LOGO.has_point(posicao_textura):
		_contador_cliques_s_ruins += 1
		_contador_cliques_s_metropolis = 0
		if _contador_cliques_s_ruins >= CLIQUES_EASTER_EGG:
			_resetar_contadores_easter_egg()
			_executar_easter_egg_rosas()
	else:
		_resetar_contadores_easter_egg()


func _converter_posicao_logo_para_textura(posicao_local_logo: Vector2) -> Vector2:
	if logo_metropolis == null or logo_metropolis.texture == null:
		return Vector2(-1.0, -1.0)

	var tamanho_controle: Vector2 = logo_metropolis.size
	var tamanho_textura: Vector2 = logo_metropolis.texture.get_size()
	if tamanho_controle.x <= 0.0 or tamanho_controle.y <= 0.0:
		return Vector2(-1.0, -1.0)
	if tamanho_textura.x <= 0.0 or tamanho_textura.y <= 0.0:
		return Vector2(-1.0, -1.0)

	var escala: float = minf(
		tamanho_controle.x / tamanho_textura.x,
		tamanho_controle.y / tamanho_textura.y
	)
	var tamanho_desenhado: Vector2 = tamanho_textura * escala
	var origem_textura: Vector2 = (tamanho_controle - tamanho_desenhado) * 0.5
	var retangulo_desenhado := Rect2(origem_textura, tamanho_desenhado)
	if not retangulo_desenhado.has_point(posicao_local_logo):
		return Vector2(-1.0, -1.0)

	var uv: Vector2 = (posicao_local_logo - origem_textura) / tamanho_desenhado
	return Vector2(uv.x * tamanho_textura.x, uv.y * tamanho_textura.y)


func _resetar_contadores_easter_egg() -> void:
	_contador_cliques_s_metropolis = 0
	_contador_cliques_s_ruins = 0


func _executar_easter_egg_rosas() -> void:
	if _easter_egg_ativo:
		return
	call_deferred("_rodar_easter_egg_rosas")


func _rodar_easter_egg_rosas() -> void:
	if _easter_egg_ativo:
		return
	_easter_egg_ativo = true
	_definir_interacao_menu_bloqueada(true)
	get_viewport().gui_release_focus()
	_preparar_overlay_easter_egg()
	_easter_egg_overlay.visible = true

	var tween_intro := create_tween().set_parallel(true)
	(
		tween_intro
		. tween_property(_easter_egg_overlay, "modulate:a", 1.0, 0.42)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	if _ceu_easter_egg != null and is_instance_valid(_ceu_easter_egg):
		(
			tween_intro
			. parallel()
			. tween_property(_ceu_easter_egg, "modulate:a", 1.0, 0.54)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_OUT)
		)
	if _lua_easter_egg != null and is_instance_valid(_lua_easter_egg):
		(
			tween_intro
			. parallel()
			. tween_property(_lua_easter_egg, "modulate:a", 1.0, 0.65)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_OUT)
		)
		(
			tween_intro
			. parallel()
			. tween_property(_lua_easter_egg, "scale", Vector2.ONE, 0.90)
			. set_trans(Tween.TRANS_BACK)
			. set_ease(Tween.EASE_OUT)
		)
	await tween_intro.finished

	var respiracao_lua: Tween
	if _lua_easter_egg != null and is_instance_valid(_lua_easter_egg):
		respiracao_lua = create_tween().set_loops()
		(
			respiracao_lua
			. tween_property(_lua_easter_egg, "scale", Vector2(1.018, 1.018), 1.80)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)
		(
			respiracao_lua
			. tween_property(_lua_easter_egg, "scale", Vector2.ONE, 1.80)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)

	await _animar_rosas_easter_egg()
	if respiracao_lua != null and respiracao_lua.is_valid():
		respiracao_lua.kill()
	if _lua_easter_egg != null and is_instance_valid(_lua_easter_egg):
		_lua_easter_egg.scale = Vector2.ONE
	await get_tree().create_timer(0.35).timeout

	var tween_outro := create_tween().set_parallel(true)
	(
		tween_outro
		. tween_property(_easter_egg_overlay, "modulate:a", 0.0, 0.65)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	if _lua_easter_egg != null and is_instance_valid(_lua_easter_egg):
		(
			tween_outro
			. parallel()
			. tween_property(_lua_easter_egg, "scale", Vector2(1.08, 1.08), 0.65)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)
	await tween_outro.finished

	_liberar_rosas_easter_egg()
	_easter_egg_overlay.visible = false
	_definir_interacao_menu_bloqueada(false)
	_easter_egg_ativo = false
	_resetar_contadores_easter_egg()
	if btn_local != null and is_instance_valid(btn_local):
		btn_local.grab_focus()


func _animar_rosas_easter_egg() -> Signal:
	_liberar_rosas_easter_egg()
	var viewport_tamanho := get_viewport_rect().size
	var disposicao := [
		{"x": 0.06, "escala": 0.82, "delay": 0.00, "base_y": 1.03},
		{"x": 0.16, "escala": 0.94, "delay": 0.14, "base_y": 1.02},
		{"x": 0.27, "escala": 0.76, "delay": 0.28, "base_y": 1.04},
		{"x": 0.39, "escala": 0.98, "delay": 0.42, "base_y": 1.02},
		{"x": 0.50, "escala": 1.08, "delay": 0.56, "base_y": 1.03},
		{"x": 0.61, "escala": 0.96, "delay": 0.70, "base_y": 1.02},
		{"x": 0.73, "escala": 0.78, "delay": 0.84, "base_y": 1.04},
		{"x": 0.84, "escala": 0.92, "delay": 0.98, "base_y": 1.02},
		{"x": 0.94, "escala": 0.84, "delay": 1.12, "base_y": 1.03}
	]

	var atraso_maximo: float = 0.0
	for indice in disposicao.size():
		var dados: Dictionary = disposicao[indice]
		var atraso: float = float(dados["delay"])
		atraso_maximo = maxf(atraso_maximo, atraso)

		var rosa := _rosa_template.duplicate() as Control
		rosa.name = "RosaEasterEgg%02d" % indice
		rosa.visible = true
		rosa.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rosa.pivot_offset = Vector2(64.0, 320.0)
		rosa.scale = Vector2.ONE * float(dados["escala"])
		var rotacao_base := deg_to_rad(_rng_easter_egg.randf_range(-1.2, 1.2))
		rosa.rotation = rotacao_base
		rosa.position = Vector2(
			viewport_tamanho.x * float(dados["x"]) - 64.0,
			viewport_tamanho.y * float(dados["base_y"]) - 320.0
		)
		_rosas_layer.add_child(rosa)
		_rosas_easter_egg.append(rosa)

		var caule := rosa.get_node("Caule") as TextureRect
		var botao := rosa.get_node("Botao") as TextureRect
		var meia_aberta := rosa.get_node("FlorMeiaAberta") as TextureRect
		var aberta := rosa.get_node("FlorAberta") as TextureRect

		caule.visible = true
		caule.modulate = Color(1.0, 1.0, 1.0, 0.0)
		caule.scale = Vector2(0.88, 0.015)
		botao.visible = true
		botao.modulate = Color(1.0, 1.0, 1.0, 0.0)
		botao.scale = Vector2(0.48, 0.34)
		meia_aberta.visible = true
		meia_aberta.modulate = Color(1.0, 1.0, 1.0, 0.0)
		meia_aberta.scale = Vector2(0.60, 0.52)
		aberta.visible = true
		aberta.modulate = Color(1.0, 1.0, 1.0, 0.0)
		aberta.scale = Vector2(0.64, 0.56)

		var florescer := create_tween()
		florescer.tween_interval(atraso)
		(
			florescer
			. tween_property(caule, "modulate:a", 1.0, 0.28)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_OUT)
		)
		(
			florescer
			. parallel()
			. tween_property(caule, "scale", Vector2.ONE, 1.40)
			. set_trans(Tween.TRANS_QUINT)
			. set_ease(Tween.EASE_OUT)
		)
		(
			florescer
			. tween_property(botao, "modulate:a", 1.0, 0.55)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_OUT)
		)
		(
			florescer
			. parallel()
			. tween_property(botao, "scale", Vector2.ONE, 0.65)
			. set_trans(Tween.TRANS_QUINT)
			. set_ease(Tween.EASE_OUT)
		)
		florescer.tween_interval(0.20)
		(
			florescer
			. tween_property(meia_aberta, "modulate:a", 1.0, 0.72)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)
		(
			florescer
			. parallel()
			. tween_property(meia_aberta, "scale", Vector2.ONE, 0.72)
			. set_trans(Tween.TRANS_QUINT)
			. set_ease(Tween.EASE_OUT)
		)
		(
			florescer
			. parallel()
			. tween_property(botao, "modulate:a", 0.0, 0.72)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)
		(
			florescer
			. parallel()
			. tween_property(botao, "scale", Vector2(1.07, 1.04), 0.72)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_OUT)
		)
		(
			florescer
			. tween_property(aberta, "modulate:a", 1.0, 0.95)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)
		(
			florescer
			. parallel()
			. tween_property(aberta, "scale", Vector2.ONE, 0.95)
			. set_trans(Tween.TRANS_QUINT)
			. set_ease(Tween.EASE_OUT)
		)
		(
			florescer
			. parallel()
			. tween_property(meia_aberta, "modulate:a", 0.0, 0.95)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)
		(
			florescer
			. parallel()
			. tween_property(meia_aberta, "scale", Vector2(1.08, 1.06), 0.95)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_OUT)
		)
		(
			florescer
			. tween_property(aberta, "scale", Vector2(1.035, 1.035), 0.58)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)
		(
			florescer
			. tween_property(aberta, "scale", Vector2.ONE, 0.82)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)

		var balanco := create_tween()
		balanco.tween_interval(atraso + 5.05)
		(
			balanco
			. tween_property(rosa, "rotation", rotacao_base - deg_to_rad(1.15), 0.65)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)
		(
			balanco
			. tween_property(rosa, "rotation", rotacao_base + deg_to_rad(1.15), 1.15)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)
		(
			balanco
			. tween_property(rosa, "rotation", rotacao_base, 0.65)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)

	# Espera a última rosa terminar de abrir e mantém o jardim por alguns instantes.
	await get_tree().create_timer(atraso_maximo + 7.65).timeout

	for indice in _rosas_easter_egg.size():
		var rosa := _rosas_easter_egg[indice]
		if not is_instance_valid(rosa):
			continue
		var escala_atual := rosa.scale
		var saida := create_tween()
		saida.tween_interval(float(indice) * 0.055)
		(
			saida
			. tween_property(rosa, "position", rosa.position + Vector2(0.0, 390.0), 1.65)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)
		(
			saida
			. parallel()
			. tween_property(rosa, "modulate:a", 0.0, 1.48)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_IN)
		)
		(
			saida
			. parallel()
			. tween_property(rosa, "scale", escala_atual * 0.96, 1.65)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)
		(
			saida
			. parallel()
			. tween_property(
				rosa,
				"rotation",
				rosa.rotation + deg_to_rad(_rng_easter_egg.randf_range(-2.0, 2.0)),
				1.65
			)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)

	return get_tree().create_timer(2.20).timeout


func _liberar_rosas_easter_egg() -> void:
	for rosa in _rosas_easter_egg:
		if rosa != null and is_instance_valid(rosa):
			rosa.queue_free()
	_rosas_easter_egg.clear()


func _executar_easter_egg_neve() -> void:
	if _easter_egg_ativo:
		return
	call_deferred("_rodar_easter_egg_neve")


func _rodar_easter_egg_neve() -> void:
	if _easter_egg_ativo:
		return
	_easter_egg_ativo = true
	_resetar_contadores_easter_egg()
	_definir_interacao_menu_bloqueada(true)
	get_viewport().gui_release_focus()

	# A neve usa somente a camada transparente. O céu e a lua permanecem
	# exclusivos do easter egg das rosas.
	_preparar_overlay_easter_egg()
	if _ceu_easter_egg != null and is_instance_valid(_ceu_easter_egg):
		_ceu_easter_egg.visible = false
	if _lua_easter_egg != null and is_instance_valid(_lua_easter_egg):
		_lua_easter_egg.visible = false
	if _easter_egg_overlay != null and is_instance_valid(_easter_egg_overlay):
		_easter_egg_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_easter_egg_overlay.modulate = Color.WHITE
		_easter_egg_overlay.visible = true

	_tempo_restante_neve = DURACAO_NEVE_EASTER_EGG
	_acumulador_spawn_neve = INTERVALO_GERACAO_NEVE
	await get_tree().create_timer(DURACAO_NEVE_EASTER_EGG).timeout

	if not is_inside_tree():
		return
	_tempo_restante_neve = 0.0

	# Os últimos flocos continuam descendo enquanto desaparecem lentamente.
	if _easter_egg_overlay != null and is_instance_valid(_easter_egg_overlay):
		var desaparecimento := create_tween()
		(
			desaparecimento
			. tween_property(_easter_egg_overlay, "modulate:a", 0.0, 1.45)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)
		await desaparecimento.finished

	_finalizar_easter_egg_neve()


func _atualizar_easter_egg_neve(delta: float) -> void:
	if _tempo_restante_neve > 0.0:
		_tempo_restante_neve = maxf(0.0, _tempo_restante_neve - delta)
		_acumulador_spawn_neve += delta
		while _acumulador_spawn_neve >= INTERVALO_GERACAO_NEVE:
			_acumulador_spawn_neve -= INTERVALO_GERACAO_NEVE
			_gerar_onda_floquinhos()

	var viewport_tamanho: Vector2 = get_viewport_rect().size
	for indice in range(_floquinhos_easter_egg.size() - 1, -1, -1):
		var floco := _floquinhos_easter_egg[indice]
		if floco == null or not is_instance_valid(floco):
			_floquinhos_easter_egg.remove_at(indice)
			continue

		var fase: float = float(floco.get_meta("fase"))
		fase += float(floco.get_meta("frequencia_balanco")) * delta
		floco.set_meta("fase", fase)
		floco.position.x += (
			float(floco.get_meta("velocidade_x"))
			+ sin(fase) * float(floco.get_meta("amplitude_balanco"))
		) * delta
		floco.position.y += float(floco.get_meta("velocidade_y")) * delta
		floco.rotation += float(floco.get_meta("velocidade_rotacao")) * delta

		var alfa_base: float = float(floco.get_meta("alfa_base"))
		if floco.position.y < 52.0:
			floco.modulate.a = clampf(floco.position.y / 52.0, 0.0, 1.0) * alfa_base
		else:
			floco.modulate.a = alfa_base

		if floco.position.y > viewport_tamanho.y + 48.0:
			floco.queue_free()
			_floquinhos_easter_egg.remove_at(indice)


func _gerar_onda_floquinhos() -> void:
	if _rosas_layer == null or not is_instance_valid(_rosas_layer):
		return
	var viewport_tamanho: Vector2 = get_viewport_rect().size
	var quantidade: int = _rng_easter_egg.randi_range(2, 4)
	for _indice in range(quantidade):
		var floco := TextureRect.new()
		floco.mouse_filter = Control.MOUSE_FILTER_IGNORE
		floco.texture = _textura_floquinho_aleatoria()
		floco.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		floco.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var tamanho_lado: float = _rng_easter_egg.randf_range(17.0, 34.0)
		floco.size = Vector2.ONE * tamanho_lado
		floco.pivot_offset = floco.size * 0.5
		floco.position = Vector2(
			_rng_easter_egg.randf_range(-28.0, viewport_tamanho.x + 28.0),
			_rng_easter_egg.randf_range(-90.0, -12.0)
		)
		var alfa_base: float = _rng_easter_egg.randf_range(0.58, 0.96)
		floco.modulate = Color(1.0, 1.0, 1.0, 0.0)
		_rosas_layer.add_child(floco)
		_floquinhos_easter_egg.append(floco)
		floco.set_meta("velocidade_y", _rng_easter_egg.randf_range(76.0, 142.0))
		floco.set_meta("velocidade_x", _rng_easter_egg.randf_range(-5.0, 5.0))
		floco.set_meta("amplitude_balanco", _rng_easter_egg.randf_range(7.0, 23.0))
		floco.set_meta("frequencia_balanco", _rng_easter_egg.randf_range(1.1, 2.4))
		floco.set_meta(
			"velocidade_rotacao",
			deg_to_rad(_rng_easter_egg.randf_range(-8.0, 8.0))
		)
		floco.set_meta("fase", _rng_easter_egg.randf_range(0.0, TAU))
		floco.set_meta("alfa_base", alfa_base)


func _textura_floquinho_aleatoria() -> Texture2D:
	match _rng_easter_egg.randi_range(0, 2):
		0:
			return FLOCO_NEVE_1
		1:
			return FLOCO_NEVE_2
		_:
			return FLOCO_NEVE_3


func _finalizar_easter_egg_neve() -> void:
	_tempo_restante_neve = 0.0
	_acumulador_spawn_neve = 0.0
	_liberar_floquinhos_easter_egg()
	if _easter_egg_overlay != null and is_instance_valid(_easter_egg_overlay):
		_easter_egg_overlay.visible = false
		_easter_egg_overlay.modulate = Color.WHITE
	_easter_egg_ativo = false
	_definir_interacao_menu_bloqueada(false)
	_resetar_contadores_easter_egg()
	if btn_local != null and is_instance_valid(btn_local):
		btn_local.grab_focus()


func _liberar_floquinhos_easter_egg() -> void:
	for floco in _floquinhos_easter_egg:
		if floco != null and is_instance_valid(floco):
			floco.queue_free()
	_floquinhos_easter_egg.clear()


func _criar_camada_transicao_tela(cor_luz: Color) -> void:
	if _camada_transicao_tela != null and is_instance_valid(_camada_transicao_tela):
		_camada_transicao_tela.queue_free()

	_camada_transicao_tela = ColorRect.new()
	_camada_transicao_tela.name = "TransicaoEntreTelas"
	add_child(_camada_transicao_tela)
	_camada_transicao_tela.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_camada_transicao_tela.color = Color(
		clampf(cor_luz.r * 0.10, 0.0, 1.0),
		clampf(cor_luz.g * 0.10, 0.0, 1.0),
		clampf(cor_luz.b * 0.10, 0.0, 1.0),
		0.0
	)
	_camada_transicao_tela.mouse_filter = Control.MOUSE_FILTER_STOP
	_camada_transicao_tela.z_index = 4500


func _animar_transicao_tela(cor_luz: Color) -> void:
	if _tween_transicao_tela != null and _tween_transicao_tela.is_valid():
		_tween_transicao_tela.kill()
	_criar_camada_transicao_tela(cor_luz)

	var cor_final: Color = Color(
		lerpf(0.004, cor_luz.r, 0.035),
		lerpf(0.005, cor_luz.g, 0.035),
		lerpf(0.019, cor_luz.b, 0.035),
		1.0
	)
	var duracao_elementos: float = duracao_transicao_tela * 0.76
	fundo_cidade.pivot_offset = fundo_cidade.size * 0.5

	_tween_transicao_tela = create_tween().set_parallel(true)
	(
		_tween_transicao_tela
		. tween_property(
			_camada_transicao_tela,
			"color",
			cor_final,
			duracao_transicao_tela
		)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN_OUT)
	)
	(
		_tween_transicao_tela
		. tween_property(fundo_cidade, "scale", Vector2.ONE * 1.025, duracao_transicao_tela)
		. set_trans(Tween.TRANS_QUINT)
		. set_ease(Tween.EASE_IN)
	)
	(
		_tween_transicao_tela
		. tween_property(logo_metropolis, "modulate:a", 0.0, duracao_elementos)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
	(
		_tween_transicao_tela
		. tween_property(container_botoes, "modulate:a", 0.0, duracao_elementos)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
	(
		_tween_transicao_tela
		. tween_property(tutorial_container, "modulate:a", 0.0, duracao_elementos)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
	if _painel_resumo_perfil != null and is_instance_valid(_painel_resumo_perfil):
		(
			_tween_transicao_tela
			. tween_property(
				_painel_resumo_perfil,
				"modulate:a",
				0.0,
				duracao_elementos
			)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_IN)
		)

	await _tween_transicao_tela.finished


func _restaurar_apos_falha_transicao() -> void:
	if _tween_transicao_tela != null and _tween_transicao_tela.is_valid():
		_tween_transicao_tela.kill()

	_tween_transicao_tela = create_tween().set_parallel(true)
	if _camada_transicao_tela != null and is_instance_valid(_camada_transicao_tela):
		(
			_tween_transicao_tela
			. tween_property(_camada_transicao_tela, "modulate:a", 0.0, 0.24)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
	_tween_transicao_tela.tween_property(fundo_cidade, "scale", Vector2.ONE, 0.28)
	_tween_transicao_tela.tween_property(logo_metropolis, "modulate:a", 1.0, 0.22)
	_tween_transicao_tela.tween_property(container_botoes, "modulate:a", 1.0, 0.22)
	_tween_transicao_tela.tween_property(tutorial_container, "modulate:a", 1.0, 0.22)
	if _painel_resumo_perfil != null and is_instance_valid(_painel_resumo_perfil):
		_tween_transicao_tela.tween_property(
			_painel_resumo_perfil,
			"modulate:a",
			1.0,
			0.22
		)

	await _tween_transicao_tela.finished
	fundo_cidade.scale = Vector2.ONE
	if _camada_transicao_tela != null and is_instance_valid(_camada_transicao_tela):
		_camada_transicao_tela.queue_free()
	_camada_transicao_tela = null


func _trocar_para_cena(
	caminho: String,
	descricao: String,
	botao_foco: Button,
	cor_luz: Color
) -> void:
	var caminho_limpo: String = caminho.strip_edges()
	if caminho_limpo.is_empty() or not ResourceLoader.exists(caminho_limpo):
		push_error(
			"Não foi possível abrir %s. Cena não encontrada: %s"
			% [descricao, caminho_limpo]
		)
		_finalizar_acao(botao_foco)
		return

	await _animar_transicao_tela(cor_luz)
	var erro: Error = get_tree().change_scene_to_file(caminho_limpo)
	if erro != OK:
		push_error("Não foi possível abrir %s. Código: %s" % [descricao, erro])
		await _restaurar_apos_falha_transicao()
		_finalizar_acao(botao_foco)


# Abre o lobby local após um pulso rápido no botão.
func _on_btn_local_pressed() -> void:
	if not _iniciar_acao():
		return

	_animar_botao_acionado(btn_local, Color(1.0, 0.82, 0.84, 1.0))
	await get_tree().create_timer(tempo_antes_partida_local).timeout
	await _trocar_para_cena(
		"res://scenes/ui/lobby/lobby.tscn",
		"o lobby local",
		btn_local,
		Color(1.0, 0.82, 0.84, 1.0)
	)


# Abre o menu online.
func _on_btn_online_pressed() -> void:
	if not _iniciar_acao():
		return

	_animar_botao_acionado(btn_online, Color(0.72, 0.91, 1.0, 1.0))
	await get_tree().create_timer(tempo_antes_partida_online).timeout
	await _trocar_para_cena(
		"res://scenes/ui/online/online_menu.tscn",
		"o modo online",
		btn_online,
		Color(0.72, 0.91, 1.0, 1.0)
	)


# Abre o tutorial com o mesmo fechamento usado nas demais trocas de tela.
func _on_btn_tutorial_pressed() -> void:
	if not _iniciar_acao():
		return

	var cor_tutorial: Color = Color(1.0, 0.86, 0.52, 1.0)
	_animar_botao_acionado(btn_tutorial, cor_tutorial)
	await get_tree().create_timer(0.38).timeout
	await _trocar_para_cena(
		cena_tutorial,
		"o tutorial",
		btn_tutorial,
		cor_tutorial
	)


func _on_btn_opcoes_pressed() -> void:
	_animar_botao_acionado(btn_opcoes, Color(1.0, 0.82, 0.84, 1.0))
	_abrir_opcoes()


# Encerra o jogo.
func _on_btn_sair_pressed() -> void:
	if not _iniciar_acao():
		return

	_animar_botao_acionado(btn_sair, Color(1.0, 0.62, 0.65, 1.0))
	await get_tree().create_timer(tempo_antes_sair).timeout
	get_tree().quit()
