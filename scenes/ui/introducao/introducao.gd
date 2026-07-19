extends Control

## Pequena abertura cinematografica exibida antes do menu principal.
## A cena e independente do restante do jogo para nao interferir nas partidas.

const CENA_MENU_PRINCIPAL: String = "res://scenes/ui/tela_inicial/menu_principal.tscn"
const META_ENTRADA_DETALHADA_POS_CINEMATICA: String = "entrada_detalhada_menu_pos_cinematica"
const CORES_PARTICULAS: Array[Color] = [
	Color("ff9a72"),
	Color("e97978"),
	Color("9b7bd8"),
	Color("6978bd"),
]

@onready var arte_logo: TextureRect = %ArteLogo
@onready var linha_luz: ColorRect = %LinhaLuz
@onready var label_apresenta: Label = %LabelApresenta
@onready var dica_pular: Label = %DicaPular
@onready var fade_preto: ColorRect = %FadePreto
@onready var camada_particulas: Control = %Particulas

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _tween_apresentacao: Tween
var _finalizando: bool = false
var _pode_pular: bool = false


func _ready() -> void:
	# Garante que a abertura continue mesmo se alguma configuracao anterior tiver
	# alterado a pausa global antes de voltar ao menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 0x534B504958454C53

	await get_tree().process_frame
	await get_tree().process_frame

	_preparar_estado_inicial()
	_criar_particulas_ambiente()
	_reproduzir_apresentacao()


func _preparar_estado_inicial() -> void:
	arte_logo.pivot_offset = arte_logo.size * 0.5
	arte_logo.scale = Vector2(0.935, 0.935)
	arte_logo.modulate = Color(0.58, 0.54, 0.72, 0.0)

	linha_luz.pivot_offset = linha_luz.size * 0.5
	linha_luz.scale = Vector2(0.0, 1.0)
	linha_luz.modulate.a = 0.0

	label_apresenta.modulate.a = 0.0
	dica_pular.modulate.a = 0.0
	fade_preto.modulate.a = 1.0


func _reproduzir_apresentacao() -> void:
	_tween_apresentacao = create_tween()
	_tween_apresentacao.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

	_tween_apresentacao.tween_interval(0.16)
	(
		_tween_apresentacao
		. tween_property(fade_preto, "modulate:a", 0.0, 0.62)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_tween_apresentacao
		. parallel()
		. tween_property(arte_logo, "modulate", Color.WHITE, 0.86)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_tween_apresentacao
		. parallel()
		. tween_property(arte_logo, "scale", Vector2.ONE, 1.08)
		. set_trans(Tween.TRANS_QUINT)
		. set_ease(Tween.EASE_OUT)
	)

	_tween_apresentacao.tween_interval(0.08)
	(
		_tween_apresentacao
		. tween_property(linha_luz, "scale", Vector2.ONE, 0.38)
		. set_trans(Tween.TRANS_QUINT)
		. set_ease(Tween.EASE_OUT)
	)
	_tween_apresentacao.parallel().tween_property(linha_luz, "modulate:a", 0.82, 0.16)
	_tween_apresentacao.tween_property(linha_luz, "modulate:a", 0.0, 0.46)
	(
		_tween_apresentacao
		. parallel()
		. tween_property(label_apresenta, "modulate:a", 0.86, 0.42)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)

	_tween_apresentacao.tween_callback(_liberar_pulo)
	_tween_apresentacao.tween_property(dica_pular, "modulate:a", 0.48, 0.30)
	_tween_apresentacao.tween_interval(1.52)
	_tween_apresentacao.tween_callback(_iniciar_saida)


func _liberar_pulo() -> void:
	_pode_pular = true


func _unhandled_input(event: InputEvent) -> void:
	if not _pode_pular or _finalizando:
		return

	var solicitou_pulo: bool = false
	if event is InputEventScreenTouch:
		solicitou_pulo = event.pressed
	elif event is InputEventMouseButton:
		solicitou_pulo = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventKey:
		solicitou_pulo = event.pressed and not event.echo
	elif event is InputEventJoypadButton:
		solicitou_pulo = event.pressed

	if not solicitou_pulo:
		return

	get_viewport().set_input_as_handled()
	_iniciar_saida()


func _notification(what: int) -> void:
	# No Android, o botao Voltar tambem funciona como pulo da abertura.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _pode_pular and not _finalizando:
		_iniciar_saida()


func _iniciar_saida() -> void:
	if _finalizando:
		return

	_finalizando = true
	_pode_pular = false
	if _tween_apresentacao != null and _tween_apresentacao.is_valid():
		_tween_apresentacao.kill()

	var tween_saida := create_tween()
	tween_saida.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	(
		tween_saida
		. tween_property(fade_preto, "modulate:a", 1.0, 0.54)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN_OUT)
	)
	(
		tween_saida
		. parallel()
		. tween_property(arte_logo, "scale", Vector2(1.028, 1.028), 0.54)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
	tween_saida.parallel().tween_property(arte_logo, "modulate:a", 0.0, 0.46)
	tween_saida.parallel().tween_property(label_apresenta, "modulate:a", 0.0, 0.22)
	tween_saida.parallel().tween_property(dica_pular, "modulate:a", 0.0, 0.14)

	await tween_saida.finished
	var arvore := get_tree()
	arvore.set_meta(META_ENTRADA_DETALHADA_POS_CINEMATICA, true)
	var erro := arvore.change_scene_to_file(CENA_MENU_PRINCIPAL)
	if erro != OK:
		arvore.remove_meta(META_ENTRADA_DETALHADA_POS_CINEMATICA)
		push_error("Nao foi possivel abrir o menu principal. Codigo: %s" % erro)
		_finalizando = false


func _criar_particulas_ambiente() -> void:
	var tamanho_tela := get_viewport_rect().size
	for indice in range(22):
		var particula := ColorRect.new()
		var lado := float(_rng.randi_range(2, 5))
		particula.size = Vector2(lado, lado)
		particula.color = CORES_PARTICULAS[indice % CORES_PARTICULAS.size()]
		particula.mouse_filter = Control.MOUSE_FILTER_IGNORE
		particula.modulate.a = 0.0
		camada_particulas.add_child(particula)

		var inicio := Vector2(
			_rng.randf_range(0.04, 0.96) * tamanho_tela.x,
			_rng.randf_range(0.30, 0.98) * tamanho_tela.y
		)
		var destino := inicio + Vector2(
			_rng.randf_range(-34.0, 34.0),
			-_rng.randf_range(75.0, 190.0)
		)
		var atraso := _rng.randf_range(0.25, 2.15)
		var duracao := _rng.randf_range(1.30, 2.25)
		var opacidade := _rng.randf_range(0.16, 0.42)
		particula.position = inicio

		var tween_particula := create_tween()
		tween_particula.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween_particula.tween_interval(atraso)
		tween_particula.tween_property(particula, "modulate:a", opacidade, 0.28)
		(
			tween_particula
			. parallel()
			. tween_property(particula, "position", destino, duracao)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_OUT)
		)
		tween_particula.tween_property(particula, "modulate:a", 0.0, 0.42)
