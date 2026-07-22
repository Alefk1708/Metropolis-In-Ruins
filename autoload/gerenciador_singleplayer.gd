extends Node

const CENA_MENU_PRINCIPAL: String = (
	"res://scenes/ui/tela_inicial/menu_principal.tscn"
)
const CENA_SINGLEPLAYER: String = (
	"res://scenes/ui/singleplayer/singleplayer.tscn"
)

var _ultima_cena: Node = null
var _integracao_em_andamento: bool = false
var _transicao_em_andamento: bool = false
var _cena_menu: Node = null
var _container_singleplayer: PanelContainer = null
var _botao_singleplayer: Button = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_verificar_cena_atual")


func _process(_delta: float) -> void:
	var cena: Node = get_tree().current_scene
	if cena == _ultima_cena:
		return

	_ultima_cena = cena
	_cena_menu = null
	_container_singleplayer = null
	_botao_singleplayer = null
	_transicao_em_andamento = false
	call_deferred("_integrar_cena_atual")


func _verificar_cena_atual() -> void:
	_ultima_cena = get_tree().current_scene
	await _integrar_cena_atual()


func _integrar_cena_atual() -> void:
	if _integracao_em_andamento:
		return

	var cena: Node = get_tree().current_scene
	if not _eh_menu_principal(cena):
		return

	_integracao_em_andamento = true
	if Global.modo_singleplayer:
		Global.limpar_partida_singleplayer()

	# O botão já existe no menu_principal.tscn. Esta espera serve somente para
	# o layout calcular tamanhos e para o script do menu iniciar sua apresentação.
	for _tentativa in range(8):
		if not _eh_menu_principal(cena):
			_integracao_em_andamento = false
			return
		await get_tree().process_frame

	var container: PanelContainer = cena.get_node_or_null(
		"SingleplayerContainer"
	) as PanelContainer
	var botao: Button = cena.get_node_or_null(
		"SingleplayerContainer/BtnSingleplayer"
	) as Button
	var botao_tutorial: Button = cena.get_node_or_null(
		"TutorialContainer/BtnTutorial"
	) as Button

	if container == null or botao == null:
		push_error(
			"SingleplayerContainer/BtnSingleplayer não foi encontrado em "
			+ CENA_MENU_PRINCIPAL
		)
		_integracao_em_andamento = false
		return

	_cena_menu = cena
	_container_singleplayer = container
	_botao_singleplayer = botao

	container.process_mode = Node.PROCESS_MODE_ALWAYS
	container.pivot_offset = container.size * 0.5
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.modulate.a = 0.0
	botao.process_mode = Node.PROCESS_MODE_ALWAYS
	botao.mouse_filter = Control.MOUSE_FILTER_IGNORE
	botao.focus_mode = Control.FOCUS_NONE
	botao.disabled = true
	botao.modulate.a = 0.0

	var callback_singleplayer := Callable(
		self,
		"_ao_btn_singleplayer_pressed"
	)
	if not botao.pressed.is_connected(callback_singleplayer):
		botao.pressed.connect(callback_singleplayer)

	if botao_tutorial != null:
		botao_tutorial.focus_neighbor_bottom = (
			botao_tutorial.get_path_to(botao)
		)
		botao.focus_neighbor_top = botao.get_path_to(botao_tutorial)

	_conectar_limpeza_outros_modos(cena)
	_integracao_em_andamento = false
	await _animar_entrada_singleplayer(cena, container, botao)


func _eh_menu_principal(cena: Node) -> bool:
	return (
		cena != null
		and is_instance_valid(cena)
		and cena.scene_file_path == CENA_MENU_PRINCIPAL
	)


func _conectar_limpeza_outros_modos(cena: Node) -> void:
	var caminhos_botoes: Array[String] = [
		"ContainerBotoes/VBoxBotoes/BtnLocal",
		"ContainerBotoes/VBoxBotoes/BtnOnline",
		"TutorialContainer/BtnTutorial",
		"ContainerBotoes/VBoxBotoes/BtnSair",
	]

	for caminho: String in caminhos_botoes:
		var botao: Button = cena.get_node_or_null(caminho) as Button
		if botao == null:
			continue
		var callback := Callable(self, "_ao_abrir_outro_modo")
		if not botao.pressed.is_connected(callback):
			botao.pressed.connect(callback)


func _ao_abrir_outro_modo() -> void:
	if Global.modo_singleplayer:
		Global.limpar_partida_singleplayer()

	if (
		_container_singleplayer == null
		or not is_instance_valid(_container_singleplayer)
	):
		return

	var tween: Tween = create_tween()
	(
		tween
		. tween_property(
			_container_singleplayer,
			"modulate:a",
			0.0,
			0.18
		)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)


func _animar_entrada_singleplayer(
	cena: Node,
	container: PanelContainer,
	botao: Button
) -> void:
	# O botão permanente permanece invisível até a apresentação original terminar.
	for _tentativa in range(180):
		if not _eh_menu_principal(cena):
			return
		if not bool(cena.get("_apresentacao_inicial_ativa")):
			break
		await get_tree().process_frame

	if (
		container == null
		or botao == null
		or not is_instance_valid(container)
		or not is_instance_valid(botao)
	):
		return

	var posicao_final: Vector2 = container.position
	container.pivot_offset = container.size * 0.5
	container.position = posicao_final + Vector2(-58.0, -18.0)
	container.scale = Vector2(0.86, 0.86)
	container.rotation = deg_to_rad(-2.5)
	container.modulate.a = 0.0
	botao.modulate.a = 0.0

	var tween: Tween = create_tween().set_parallel(true)
	(
		tween
		. tween_property(container, "position", posicao_final, 0.66)
		. set_trans(Tween.TRANS_QUINT)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tween
		. tween_property(container, "scale", Vector2.ONE, 0.72)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tween
		. tween_property(container, "rotation", 0.0, 0.62)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tween
		. tween_property(container, "modulate:a", 1.0, 0.34)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tween
		. tween_property(botao, "modulate:a", 1.0, 0.42)
		. set_delay(0.08)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)

	await tween.finished
	if not _eh_menu_principal(cena):
		return
	if not is_instance_valid(container) or not is_instance_valid(botao):
		return

	container.mouse_filter = Control.MOUSE_FILTER_PASS
	botao.mouse_filter = Control.MOUSE_FILTER_STOP
	botao.focus_mode = Control.FOCUS_ALL
	botao.disabled = false


func _ao_btn_singleplayer_pressed() -> void:
	var cena: Node = get_tree().current_scene
	if _transicao_em_andamento:
		return
	if not _eh_menu_principal(cena):
		return
	if bool(cena.get("_acao_em_andamento")):
		return
	if (
		_container_singleplayer == null
		or _botao_singleplayer == null
		or not is_instance_valid(_container_singleplayer)
		or not is_instance_valid(_botao_singleplayer)
	):
		return

	_transicao_em_andamento = true
	_botao_singleplayer.disabled = true
	get_viewport().gui_release_focus()

	if NetworkManager.esta_em_sala():
		NetworkManager.desconectar("Modo singleplayer iniciado.")

	Global.preparar_modo_singleplayer(3)

	_botao_singleplayer.pivot_offset = (
		_botao_singleplayer.size * 0.5
	)
	var pulso: Tween = create_tween()
	pulso.tween_property(
		_botao_singleplayer,
		"scale",
		Vector2(0.96, 0.96),
		0.08
	)
	pulso.tween_property(
		_botao_singleplayer,
		"scale",
		Vector2(1.03, 1.03),
		0.12
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pulso.tween_property(
		_botao_singleplayer,
		"scale",
		Vector2.ONE,
		0.14
	)

	var camada := ColorRect.new()
	camada.name = "TransicaoSingleplayer"
	camada.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	camada.color = Color(0.004, 0.005, 0.019, 0.0)
	camada.mouse_filter = Control.MOUSE_FILTER_STOP
	camada.z_index = 4096
	cena.add_child(camada)

	var tween: Tween = create_tween().set_parallel(true)
	(
		tween
		. tween_property(
			camada,
			"color",
			Color(0.004, 0.005, 0.019, 1.0),
			0.46
		)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN_OUT)
	)
	(
		tween
		. tween_property(
			_container_singleplayer,
			"modulate:a",
			0.0,
			0.32
		)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)

	await tween.finished

	if not ResourceLoader.exists(CENA_SINGLEPLAYER):
		push_error(
			"Cena singleplayer não encontrada: "
			+ CENA_SINGLEPLAYER
		)
		_restaurar_menu_apos_falha(camada)
		return

	var erro: Error = get_tree().change_scene_to_file(CENA_SINGLEPLAYER)
	if erro != OK:
		push_error(
			"Não foi possível abrir o modo singleplayer. Código: %s"
			% erro
		)
		_restaurar_menu_apos_falha(camada)


func _restaurar_menu_apos_falha(camada: ColorRect) -> void:
	Global.limpar_partida_singleplayer()
	_transicao_em_andamento = false

	if (
		_botao_singleplayer != null
		and is_instance_valid(_botao_singleplayer)
	):
		_botao_singleplayer.disabled = false
	if (
		_container_singleplayer != null
		and is_instance_valid(_container_singleplayer)
	):
		_container_singleplayer.modulate.a = 1.0
	if camada != null and is_instance_valid(camada):
		camada.queue_free()
