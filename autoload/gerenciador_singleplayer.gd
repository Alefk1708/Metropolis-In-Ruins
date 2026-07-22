extends Node

const CENA_MENU_PRINCIPAL: String = (
	"res://scenes/ui/tela_inicial/menu_principal.tscn"
)
const CENA_SINGLEPLAYER: String = (
	"res://scenes/ui/singleplayer/singleplayer.tscn"
)
const ICONE_SINGLEPLAYER: String = (
	"res://assets/textures/PlayIcon.png"
)

var _ultima_cena: Node = null
var _integracao_em_andamento: bool = false
var _transicao_em_andamento: bool = false
var _container_singleplayer: PanelContainer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_verificar_cena_atual")


func _process(_delta: float) -> void:
	var cena: Node = get_tree().current_scene
	if cena == _ultima_cena:
		return

	_ultima_cena = cena
	_container_singleplayer = null
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

	if Global.modo_singleplayer:
		Global.limpar_partida_singleplayer()

	_integracao_em_andamento = true

	# Aguarda a cena calcular a posição do botão Tutorial.
	for _tentativa: int in range(8):
		if cena == null or not is_instance_valid(cena):
			_integracao_em_andamento = false
			return
		await get_tree().process_frame

	var tutorial_container: PanelContainer = cena.get_node_or_null(
		"TutorialContainer"
	) as PanelContainer
	if tutorial_container == null:
		_integracao_em_andamento = false
		return

	var existente: PanelContainer = cena.get_node_or_null(
		"SingleplayerContainer"
	) as PanelContainer
	if existente != null:
		_container_singleplayer = existente
		_integracao_em_andamento = false
		return

	_criar_botao_singleplayer(cena, tutorial_container)
	_integracao_em_andamento = false


func _eh_menu_principal(cena: Node) -> bool:
	return (
		cena != null
		and is_instance_valid(cena)
		and cena.scene_file_path == CENA_MENU_PRINCIPAL
	)


func _criar_botao_singleplayer(
	cena: Node,
	tutorial_container: PanelContainer
) -> void:
	# Duplica a estrutura visual completa do Tutorial. O sinal original
	# não é copiado, evitando que JOGAR SOLO também abra o tutorial.
	var novo_container: PanelContainer = (
		tutorial_container.duplicate(0) as PanelContainer
	)
	if novo_container == null:
		return

	novo_container.name = "SingleplayerContainer"
	novo_container.modulate.a = 0.0
	novo_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cena.add_child(novo_container)

	var posicao_final: Vector2 = (
		tutorial_container.position
		+ Vector2(0.0, tutorial_container.size.y + 16.0)
	)
	novo_container.position = posicao_final
	novo_container.size = tutorial_container.size
	novo_container.pivot_offset = novo_container.size * 0.5
	novo_container.process_mode = Node.PROCESS_MODE_ALWAYS

	var botao: Button = novo_container.get_node_or_null(
		"BtnTutorial"
	) as Button
	if botao == null:
		novo_container.queue_free()
		return

	botao.name = "BtnSingleplayer"
	botao.mouse_filter = Control.MOUSE_FILTER_IGNORE
	botao.focus_mode = Control.FOCUS_NONE
	botao.tooltip_text = (
		"Jogue sozinho contra adversários controlados pela IA."
	)
	botao.process_mode = Node.PROCESS_MODE_ALWAYS

	var label: Label = botao.get_node_or_null("Label") as Label
	if label != null:
		# Mantém exatamente a mesma fonte e tamanho usados pelo Tutorial.
		label.text = "     JOGAR SOLO"

	var icone: TextureRect = botao.get_node_or_null(
		"TextureRect"
	) as TextureRect
	if (
		icone != null
		and ResourceLoader.exists(ICONE_SINGLEPLAYER)
	):
		# Troca apenas a textura. Dimensões e posição continuam idênticas
		# às do ícone existente no botão Tutorial.
		icone.texture = load(ICONE_SINGLEPLAYER) as Texture2D

	var botao_tutorial: Button = tutorial_container.get_node_or_null(
		"BtnTutorial"
	) as Button
	if botao_tutorial != null:
		botao_tutorial.focus_neighbor_bottom = (
			botao_tutorial.get_path_to(botao)
		)
		botao.focus_neighbor_top = botao.get_path_to(botao_tutorial)

	botao.pressed.connect(
		_ao_btn_singleplayer_pressed.bind(
			cena,
			novo_container,
			botao
		)
	)

	_conectar_limpeza_outros_modos(cena, novo_container)

	_container_singleplayer = novo_container
	_animar_entrada_singleplayer(
		cena,
		novo_container,
		posicao_final
	)


func _conectar_limpeza_outros_modos(
	cena: Node,
	container: PanelContainer
) -> void:
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

		var callback := Callable(
			self,
			"_ao_abrir_outro_modo"
		).bind(container)

		if not botao.pressed.is_connected(callback):
			botao.pressed.connect(callback)


func _ao_abrir_outro_modo(
	container: PanelContainer
) -> void:
	if Global.modo_singleplayer:
		Global.limpar_partida_singleplayer()

	if container == null or not is_instance_valid(container):
		return

	var tween: Tween = create_tween()
	(
		tween
		. tween_property(container, "modulate:a", 0.0, 0.18)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)


func _animar_entrada_singleplayer(
	cena: Node,
	container: PanelContainer,
	posicao_final: Vector2
) -> void:
	if container == null or not is_instance_valid(container):
		return

	# Mantém a sequência visual do menu. O botão aparece depois que os
	# elementos originais já terminaram a apresentação.
	for _tentativa: int in range(180):
		if cena == null or not is_instance_valid(cena):
			return
		if not bool(cena.get("_apresentacao_inicial_ativa")):
			break
		await get_tree().process_frame

	if container == null or not is_instance_valid(container):
		return

	container.position = posicao_final + Vector2(-58.0, -18.0)
	container.scale = Vector2(0.86, 0.86)
	container.rotation = deg_to_rad(-2.5)
	container.modulate.a = 0.0

	var botao_animado: Button = container.get_node_or_null(
		"BtnSingleplayer"
	) as Button
	if botao_animado != null:
		botao_animado.modulate.a = 0.0

	# Mesmos valores usados pela animação original do botão Tutorial.
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
	if botao_animado != null:
		(
			tween
			. tween_property(botao_animado, "modulate:a", 1.0, 0.42)
			. set_delay(0.08)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)

	await tween.finished
	if container == null or not is_instance_valid(container):
		return

	container.mouse_filter = Control.MOUSE_FILTER_PASS
	var botao: Button = container.get_node_or_null(
		"BtnSingleplayer"
	) as Button
	if botao != null:
		botao.mouse_filter = Control.MOUSE_FILTER_STOP
		botao.focus_mode = Control.FOCUS_ALL


func _ao_btn_singleplayer_pressed(
	cena: Node,
	container: PanelContainer,
	botao: Button
) -> void:
	if _transicao_em_andamento:
		return
	if not _eh_menu_principal(cena):
		return
	if bool(cena.get("_acao_em_andamento")):
		return

	_transicao_em_andamento = true
	botao.disabled = true
	get_viewport().gui_release_focus()

	if NetworkManager.esta_em_sala():
		NetworkManager.desconectar(
			"Modo singleplayer iniciado."
		)

	Global.preparar_modo_singleplayer(3)

	botao.pivot_offset = botao.size * 0.5
	var pulso: Tween = create_tween()
	pulso.tween_property(
		botao,
		"scale",
		Vector2(0.96, 0.96),
		0.08
	)
	pulso.tween_property(
		botao,
		"scale",
		Vector2(1.03, 1.03),
		0.12
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pulso.tween_property(
		botao,
		"scale",
		Vector2.ONE,
		0.14
	)

	var camada := ColorRect.new()
	camada.name = "TransicaoSingleplayer"
	camada.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
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
			container,
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
		_restaurar_menu_apos_falha(
			container,
			botao,
			camada
		)
		return

	var erro: Error = get_tree().change_scene_to_file(
		CENA_SINGLEPLAYER
	)
	if erro != OK:
		push_error(
			"Não foi possível abrir o modo singleplayer. Código: %s"
			% erro
		)
		_restaurar_menu_apos_falha(
			container,
			botao,
			camada
		)


func _restaurar_menu_apos_falha(
	container: PanelContainer,
	botao: Button,
	camada: ColorRect
) -> void:
	Global.limpar_partida_singleplayer()
	_transicao_em_andamento = false

	if botao != null and is_instance_valid(botao):
		botao.disabled = false
	if container != null and is_instance_valid(container):
		container.modulate.a = 1.0
	if camada != null and is_instance_valid(camada):
		camada.queue_free()
