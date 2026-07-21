extends Control

## Tela intermediária usada antes de abrir cenas pesadas.
##
## A cena de destino é carregada em outra thread e depois instanciada atrás
## desta interface. A sobreposição só é removida após o _ready() da nova cena
## terminar e o Godot processar um quadro, evitando que o fundo cinza apareça.

@export_file("*.tscn") var cena_destino: String = ""
@export var mensagem: String = "PREPARANDO A PARTIDA"
@export_range(0.15, 3.0, 0.05) var tempo_minimo_exibicao: float = 0.70
@export_range(0.0, 1.0, 0.05) var duracao_saida: float = 0.20

const LOGO: Texture2D = preload("res://assets/textures/LogoMetropolis.png")
const FONTE_PIXEL: Font = preload("res://assets/fonts/m5x7.ttf")
const CAMADA_INTERFACE: int = 1000

var _label_status: Label
var _spinner: Control
var _camada_carregamento: CanvasLayer
var _interface_carregamento: Control
var _instancia_destino: Node

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
			var posicao: Vector2 = (
				centro
				+ Vector2(cos(angulo), sin(angulo)) * raio
			)
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
		_instanciar_cena_carregada()
		return

	if _trocando_cena or cena_destino.is_empty():
		return

	var status: ResourceLoader.ThreadLoadStatus = (
		ResourceLoader.load_threaded_get_status(
			cena_destino,
			_progresso
		)
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
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# O CanvasLayer garante que o carregamento permaneça acima do tabuleiro,
	# mesmo depois que a cena pesada for adicionada à árvore.
	_camada_carregamento = CanvasLayer.new()
	_camada_carregamento.name = "CamadaCarregamento"
	_camada_carregamento.layer = CAMADA_INTERFACE
	_camada_carregamento.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_camada_carregamento)

	_interface_carregamento = Control.new()
	_interface_carregamento.name = "InterfaceCarregamento"
	_interface_carregamento.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	_interface_carregamento.mouse_filter = Control.MOUSE_FILTER_STOP
	_camada_carregamento.add_child(_interface_carregamento)

	var fundo := ColorRect.new()
	fundo.name = "FundoCarregamento"
	fundo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fundo.color = Color(0.004, 0.005, 0.019, 1.0)
	fundo.mouse_filter = Control.MOUSE_FILTER_STOP
	_interface_carregamento.add_child(fundo)

	var brilho := ColorRect.new()
	brilho.name = "BrilhoCentral"
	brilho.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	brilho.color = Color(0.07, 0.035, 0.075, 0.28)
	brilho.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interface_carregamento.add_child(brilho)

	var centro := CenterContainer.new()
	centro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interface_carregamento.add_child(centro)

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
	if not is_instance_valid(logo):
		return

	logo.pivot_offset = logo.size * 0.5
	logo.scale = Vector2(0.965, 0.965)

	var tween := create_tween().set_parallel(true)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	(
		tween
		.tween_property(logo, "modulate:a", 1.0, 0.34)
		.set_trans(Tween.TRANS_QUAD)
		.set_ease(Tween.EASE_OUT)
	)
	(
		tween
		.tween_property(logo, "scale", Vector2.ONE, 0.52)
		.set_trans(Tween.TRANS_BACK)
		.set_ease(Tween.EASE_OUT)
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

	var quantidade_pontos: int = int(
		floor(_pontos_animacao / 0.35)
	) % 4
	var sufixo := ""
	for _indice in range(quantidade_pontos):
		sufixo += "."
	_label_status.text = mensagem + sufixo


func _instanciar_cena_carregada() -> void:
	if _trocando_cena or _falhou:
		return

	_trocando_cena = true
	_carregamento_finalizado = false

	var recurso: Resource = ResourceLoader.load_threaded_get(cena_destino)
	if not recurso is PackedScene:
		_trocando_cena = false
		_exibir_erro("A CENA CARREGADA É INVÁLIDA")
		return

	if _label_status != null and is_instance_valid(_label_status):
		_label_status.text = "MONTANDO O TABULEIRO"

	_instancia_destino = (recurso as PackedScene).instantiate()
	if _instancia_destino == null:
		_trocando_cena = false
		_exibir_erro("NÃO FOI POSSÍVEL CRIAR A PARTIDA")
		return

	# Não usa change_scene_to_packed(). A nova cena é adicionada como irmã da
	# tela de carregamento. Dessa forma, esta interface continua renderizada
	# durante toda a execução síncrona dos métodos _ready() do tabuleiro e HUD.
	var raiz_arvore: Window = get_tree().root
	raiz_arvore.add_child(_instancia_destino)

	# add_child() só retorna depois dos _ready() síncronos da cena e dos filhos.
	# Um frame adicional permite que câmera, TileMap e texturas sejam enviados
	# ao RenderingServer enquanto o CanvasLayer continua cobrindo tudo.
	await get_tree().process_frame

	if (
		not is_instance_valid(_instancia_destino)
		or not _instancia_destino.is_inside_tree()
	):
		_trocando_cena = false
		_exibir_erro("A PARTIDA FOI ENCERRADA DURANTE O CARREGAMENTO")
		return

	get_tree().current_scene = _instancia_destino

	if _label_status != null and is_instance_valid(_label_status):
		_label_status.text = "PARTIDA PRONTA"

	# A cinemática do tabuleiro possui uma espera inicial. A saída curta ocorre
	# antes do movimento da câmera, portanto a animação continua começando do
	# início, já com o tabuleiro completamente montado atrás da interface.
	if (
		duracao_saida > 0.0
		and _interface_carregamento != null
		and is_instance_valid(_interface_carregamento)
	):
		var tween_saida := create_tween()
		tween_saida.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween_saida.set_trans(Tween.TRANS_QUAD)
		tween_saida.set_ease(Tween.EASE_OUT)
		tween_saida.tween_property(
			_interface_carregamento,
			"modulate:a",
			0.0,
			duracao_saida
		)
		await tween_saida.finished

	queue_free()


func _exibir_erro(texto: String) -> void:
	_falhou = true
	_carregamento_finalizado = false
	_trocando_cena = false

	if (
		_instancia_destino != null
		and is_instance_valid(_instancia_destino)
		and _instancia_destino != get_tree().current_scene
	):
		_instancia_destino.queue_free()

	if _spinner != null and is_instance_valid(_spinner):
		_spinner.set_process(false)

	if _label_status != null and is_instance_valid(_label_status):
		_label_status.text = texto
		_label_status.add_theme_color_override(
			"font_color",
			Color(1.0, 0.38, 0.38, 1.0)
		)

	push_error("[CARREGAMENTO] %s: %s" % [texto, cena_destino])
