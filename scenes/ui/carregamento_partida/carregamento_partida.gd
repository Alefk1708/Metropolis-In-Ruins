extends Control

## Tela intermediária usada antes de abrir cenas pesadas.
## Mantém a interface visível enquanto o Godot carrega a cena em outra thread,
## evitando o quadro cinza entre a seleção e o tabuleiro.

@export_file("*.tscn") var cena_destino: String = ""
@export var mensagem: String = "PREPARANDO A PARTIDA"
@export_range(0.15, 3.0, 0.05) var tempo_minimo_exibicao: float = 0.70

const LOGO: Texture2D = preload("res://assets/textures/LogoMetropolis.png")
const FONTE_PIXEL: Font = preload("res://assets/fonts/m5x7.ttf")

var _label_status: Label
var _spinner: Control
var _tempo_exibido: float = 0.0
var _pontos_animacao: float = 0.0
var _carregamento_finalizado: bool = false
var _trocando_cena: bool = false
var _falhou: bool = false
var _progresso: Array = []


class SpinnerPartida extends Control:
	var velocidade: float = 4.6

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		custom_minimum_size = Vector2(74.0, 74.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func _process(delta: float) -> void:
		pivot_offset = size * 0.5
		rotation += velocidade * delta

	func _draw() -> void:
		var centro: Vector2 = size * 0.5
		var raio: float = 25.0
		var quantidade: int = 10
		for indice in range(quantidade):
			var angulo: float = TAU * float(indice) / float(quantidade)
			var intensidade: float = float(indice + 2) / float(quantidade + 1)
			var posicao: Vector2 = centro + Vector2(cos(angulo), sin(angulo)) * raio
			draw_circle(
				posicao,
				4.2,
				Color(1.0, 0.82, 0.84, intensidade)
			)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_criar_interface()
	call_deferred("_iniciar_carregamento")


func _process(delta: float) -> void:
	if _falhou:
		return

	_tempo_exibido += delta
	_pontos_animacao += delta
	_atualizar_texto_status()

	if _carregamento_finalizado and _tempo_exibido >= tempo_minimo_exibicao:
		_finalizar_troca()
		return

	if _trocando_cena or cena_destino.is_empty():
		return

	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(
		cena_destino,
		_progresso
	)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			pass
		ResourceLoader.THREAD_LOAD_LOADED:
			_carregamento_finalizado = true
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_exibir_erro("NÃO FOI POSSÍVEL CARREGAR A PARTIDA")


func _criar_interface() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var fundo := ColorRect.new()
	fundo.name = "FundoCarregamento"
	fundo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fundo.color = Color(0.004, 0.005, 0.019, 1.0)
	fundo.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(fundo)

	var brilho := ColorRect.new()
	brilho.name = "BrilhoCentral"
	brilho.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	brilho.color = Color(0.07, 0.035, 0.075, 0.28)
	brilho.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(brilho)

	var centro := CenterContainer.new()
	centro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centro)

	var coluna := VBoxContainer.new()
	coluna.custom_minimum_size = Vector2(620.0, 0.0)
	coluna.alignment = BoxContainer.ALIGNMENT_CENTER
	coluna.add_theme_constant_override("separation", 20)
	centro.add_child(coluna)

	var logo := TextureRect.new()
	logo.name = "LogoMetropolis"
	logo.texture = LOGO
	logo.custom_minimum_size = Vector2(620.0, 250.0)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.modulate.a = 0.0
	coluna.add_child(logo)

	_spinner = SpinnerPartida.new()
	_spinner.name = "IndicadorGiratorio"
	coluna.add_child(_spinner)

	_label_status = Label.new()
	_label_status.name = "StatusCarregamento"
	_label_status.text = mensagem
	_label_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_status.add_theme_font_override("font", FONTE_PIXEL)
	_label_status.add_theme_font_size_override("font_size", 34)
	_label_status.add_theme_color_override(
		"font_color",
		Color(1.0, 0.88, 0.88, 1.0)
	)
	_label_status.add_theme_color_override(
		"font_outline_color",
		Color(0.0, 0.0, 0.0, 0.95)
	)
	_label_status.add_theme_constant_override("outline_size", 4)
	coluna.add_child(_label_status)

	var dica := Label.new()
	dica.text = "A CIDADE ESTÁ SENDO PREPARADA"
	dica.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dica.add_theme_font_override("font", FONTE_PIXEL)
	dica.add_theme_font_size_override("font_size", 22)
	dica.add_theme_color_override(
		"font_color",
		Color(0.70, 0.70, 0.78, 0.88)
	)
	coluna.add_child(dica)

	await get_tree().process_frame
	logo.pivot_offset = logo.size * 0.5
	logo.scale = Vector2(0.965, 0.965)

	var tween := create_tween().set_parallel(true)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	(
		tween
		. tween_property(logo, "modulate:a", 1.0, 0.34)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tween
		. tween_property(logo, "scale", Vector2.ONE, 0.52)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)


func _iniciar_carregamento() -> void:
	var caminho := cena_destino.strip_edges()
	cena_destino = caminho
	if caminho.is_empty() or not ResourceLoader.exists(caminho):
		_exibir_erro("CENA DA PARTIDA NÃO ENCONTRADA")
		return

	var erro: Error = ResourceLoader.load_threaded_request(
		caminho,
		"PackedScene",
		true
	)
	if erro != OK:
		_exibir_erro("NÃO FOI POSSÍVEL INICIAR O CARREGAMENTO")


func _atualizar_texto_status() -> void:
	if (
		_label_status == null
		or not is_instance_valid(_label_status)
		or _trocando_cena
		or _falhou
	):
		return

	var quantidade_pontos: int = int(floor(_pontos_animacao / 0.35)) % 4
	var sufixo := ""
	for _indice in range(quantidade_pontos):
		sufixo += "."
	_label_status.text = mensagem + sufixo


func _finalizar_troca() -> void:
	if _trocando_cena or _falhou:
		return
	_trocando_cena = true

	var recurso: Resource = ResourceLoader.load_threaded_get(cena_destino)
	if not recurso is PackedScene:
		_trocando_cena = false
		_exibir_erro("A CENA CARREGADA É INVÁLIDA")
		return

	_label_status.text = "ENTRANDO NA PARTIDA"
	await get_tree().create_timer(0.12, true, false, true).timeout

	# A cena antiga permanece desenhada até este momento. Como o PackedScene já
	# foi carregado em outra thread, a troca é curta e não revela o fundo cinza.
	var erro: Error = get_tree().change_scene_to_packed(recurso as PackedScene)
	if erro != OK:
		_trocando_cena = false
		_exibir_erro("ERRO AO ABRIR A PARTIDA")


func _exibir_erro(texto: String) -> void:
	_falhou = true
	_carregamento_finalizado = false
	_trocando_cena = false
	if _spinner != null and is_instance_valid(_spinner):
		_spinner.set_process(false)
	if _label_status != null and is_instance_valid(_label_status):
		_label_status.text = texto
		_label_status.add_theme_color_override(
			"font_color",
			Color(1.0, 0.38, 0.38, 1.0)
		)
	push_error("[CARREGAMENTO] %s: %s" % [texto, cena_destino])
