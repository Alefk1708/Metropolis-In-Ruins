extends CanvasLayer

signal solicitar_pausa
signal solicitar_retomada
signal solicitar_desistencia
signal solicitar_salvamento
signal solicitar_salvar_e_sair
signal visibilidade_alterada(aberto: bool)

@onready var raiz: Control = %PauseRoot
@onready var fundo: ColorRect = %FundoPause
@onready var painel_principal: PanelContainer = %PainelPause
@onready var painel_opcoes: Control = %TelaOpcoesPause
@onready var painel_confirmacao: Control = %TelaConfirmarDesistencia
@onready var pausa_remota: Control = %PausaRemota
@onready var painel_pausa_remota: PanelContainer = %PainelPausaRemota
@onready var label_pausado_por: Label = %LabelPausadoPor
@onready var aviso: PanelContainer = %AvisoPause
@onready var label_aviso: Label = %LabelAvisoPause
@onready var slider_volume: HSlider = %SliderVolumePause
@onready var label_volume: Label = %LabelVolumePause
@onready var check_tela_cheia: CheckButton = %CheckTelaCheiaPause
@onready var btn_confirmar_desistencia: Button = %BtnConfirmarDesistencia
@onready var btn_salvar: Button = %BtnSalvar
@onready var btn_sair: Button = %BtnSair
@onready var label_confirmacao_titulo: Label = $PauseRoot/TelaConfirmarDesistencia/Centro/PainelConfirmarDesistencia/Margem/Conteudo/Titulo
@onready var label_confirmacao_mensagem: Label = $PauseRoot/TelaConfirmarDesistencia/Centro/PainelConfirmarDesistencia/Margem/Conteudo/Mensagem

var _aberto: bool = false
var _pausa_global_ativa: bool = false
var _sou_iniciador_pausa: bool = false
var _tween_interface: Tween
var _tween_aviso: Tween
var _ultimo_evento_voltar_ms: int = -1000
var _modo_confirmacao: String = "desistencia"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Reforço em runtime; o project.godot também mantém esta opção desativada
	# para que o botão Voltar do Android não encerre o aplicativo.
	ProjectSettings.set_setting("application/config/quit_on_go_back", false)
	raiz.visible = false
	painel_principal.visible = true
	painel_opcoes.visible = false
	painel_confirmacao.visible = false
	pausa_remota.visible = false
	aviso.visible = false
	_configurar_opcoes_atuais()


func esta_aberto() -> bool:
	return _pausa_global_ativa


func sou_iniciador_da_pausa() -> bool:
	return _pausa_global_ativa and _sou_iniciador_pausa


# Mantido para compatibilidade com chamadas antigas. A abertura real só ocorre
# quando o host confirma e sincroniza a pausa com todos os participantes.
func abrir() -> void:
	if not _pausa_global_ativa:
		solicitar_pausa.emit()


# Mantido para compatibilidade. Apenas quem iniciou a pausa pode retomá-la.
func fechar() -> void:
	if not _pausa_global_ativa or not _sou_iniciador_pausa:
		return
	if painel_confirmacao.visible:
		_fechar_confirmacao()
		return
	if painel_opcoes.visible:
		_fechar_opcoes()
		return
	solicitar_retomada.emit()


func aplicar_estado_sincronizado(
	ativo: bool,
	sou_iniciador: bool,
	nome_iniciador: String
) -> void:
	if ativo:
		_aplicar_abertura_sincronizada(sou_iniciador, nome_iniciador)
	else:
		_aplicar_fechamento_sincronizado()


func _aplicar_abertura_sincronizada(
	sou_iniciador: bool,
	nome_iniciador: String
) -> void:
	_pausa_global_ativa = true
	_sou_iniciador_pausa = sou_iniciador
	_aberto = true
	raiz.visible = true
	painel_opcoes.visible = false
	painel_confirmacao.visible = false
	aviso.visible = false
	btn_confirmar_desistencia.disabled = false
	btn_confirmar_desistencia.text = "SIM, DESISTIR"
	btn_salvar.disabled = false
	btn_salvar.text = "SALVAR AGORA"
	btn_sair.disabled = false
	btn_sair.text = "SALVAR E SAIR"

	painel_principal.visible = sou_iniciador
	pausa_remota.visible = not sou_iniciador
	var nome_exibicao := nome_iniciador.strip_edges()
	if nome_exibicao.is_empty():
		nome_exibicao = "OUTRO JOGADOR"
	label_pausado_por.text = "PAUSA SOLICITADA POR\n%s" % nome_exibicao.to_upper()

	fundo.modulate.a = 0.0
	var painel_animado: Control = painel_principal if sou_iniciador else painel_pausa_remota
	painel_animado.modulate.a = 0.0
	painel_animado.scale = Vector2(0.95, 0.95)
	painel_animado.pivot_offset = painel_animado.size * 0.5

	_matar_tween_interface()
	_tween_interface = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	(
		_tween_interface
		. tween_property(fundo, "modulate:a", 1.0, 0.24)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_tween_interface
		. tween_property(painel_animado, "modulate:a", 1.0, 0.28)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_tween_interface
		. tween_property(painel_animado, "scale", Vector2.ONE, 0.38)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)

	# A política de pausa é aplicada pelo Tabuleiro. Em rede ela é uma pausa
	# lógica (sem congelar o SceneTree/Photon); em partida local pode ser dura.
	visibilidade_alterada.emit(true)
	if sou_iniciador:
		call_deferred("_focar_continuar")


func _aplicar_fechamento_sincronizado() -> void:
	if not _pausa_global_ativa and not raiz.visible:
		return

	_pausa_global_ativa = false
	_sou_iniciador_pausa = false
	_aberto = false
	visibilidade_alterada.emit(false)

	_matar_tween_interface()
	var painel_animado: Control = painel_principal if painel_principal.visible else painel_pausa_remota
	_tween_interface = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	(
		_tween_interface
		. tween_property(fundo, "modulate:a", 0.0, 0.18)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN)
	)
	(
		_tween_interface
		. tween_property(painel_animado, "modulate:a", 0.0, 0.16)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
	(
		_tween_interface
		. tween_property(painel_animado, "scale", Vector2(0.97, 0.97), 0.18)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
	await _tween_interface.finished
	if _pausa_global_ativa:
		return
	raiz.visible = false
	painel_principal.visible = true
	painel_opcoes.visible = false
	painel_confirmacao.visible = false
	pausa_remota.visible = false
	aviso.visible = false


func fechar_imediatamente() -> void:
	_matar_tween_interface()
	_aberto = false
	_pausa_global_ativa = false
	_sou_iniciador_pausa = false
	raiz.visible = false
	painel_principal.visible = true
	painel_opcoes.visible = false
	painel_confirmacao.visible = false
	pausa_remota.visible = false
	aviso.visible = false
	visibilidade_alterada.emit(false)


func _unhandled_input(event: InputEvent) -> void:
	if Global.modo_tutorial:
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	_tratar_botao_voltar()
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if Global.modo_tutorial:
			return
		# Com application/config/quit_on_go_back=false, este evento deixa de
		# encerrar o APK e passa a ser usado exclusivamente pelo menu de pausa.
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
		call_deferred("_tratar_botao_voltar")


func _tratar_botao_voltar() -> void:
	var agora := Time.get_ticks_msec()
	if agora - _ultimo_evento_voltar_ms < 500:
		return
	_ultimo_evento_voltar_ms = agora

	if not _pausa_global_ativa:
		solicitar_pausa.emit()
		return
	if not _sou_iniciador_pausa:
		return
	if painel_confirmacao.visible:
		_fechar_confirmacao()
	elif painel_opcoes.visible:
		_fechar_opcoes()
	else:
		solicitar_retomada.emit()


func _focar_continuar() -> void:
	var botao := get_node_or_null(
		"PauseRoot/CentroPause/PainelPause/MargemPause/ConteudoPause/BtnContinuar"
	) as Button
	if botao != null and botao.is_visible_in_tree():
		botao.grab_focus()


func _on_btn_continuar_pressed() -> void:
	if _sou_iniciador_pausa:
		solicitar_retomada.emit()


func _on_btn_opcoes_pressed() -> void:
	if not _sou_iniciador_pausa:
		return
	painel_principal.visible = false
	painel_opcoes.visible = true
	_configurar_opcoes_atuais()
	var painel := %PainelOpcoesPause as Control
	painel.modulate.a = 0.0
	painel.scale = Vector2(0.96, 0.96)
	painel.pivot_offset = painel.size * 0.5
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	tween.tween_property(painel, "modulate:a", 1.0, 0.18)
	(
		tween
		. tween_property(painel, "scale", Vector2.ONE, 0.25)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	call_deferred("_focar_voltar_opcoes")


func _fechar_opcoes() -> void:
	painel_opcoes.visible = false
	painel_principal.visible = true
	call_deferred("_focar_continuar")


func _focar_voltar_opcoes() -> void:
	var botao := %BtnVoltarOpcoesPause as Button
	if botao != null:
		botao.grab_focus()


func _on_btn_desistir_pressed() -> void:
	if not _sou_iniciador_pausa:
		return
	_abrir_confirmacao("desistencia")


func _abrir_confirmacao(modo: String) -> void:
	_modo_confirmacao = modo
	if modo == "salvar_sair":
		label_confirmacao_titulo.text = "SALVAR E SAIR?"
		label_confirmacao_titulo.add_theme_color_override(
			"font_color", Color(1.0, 0.76, 0.32, 1.0)
		)
		label_confirmacao_mensagem.text = (
			"O ESTADO ATUAL SERÁ SALVO E TODOS\nVOLTARÃO AO MENU ONLINE. O HOST PODERÁ\nCRIAR UMA SALA E RECONVIDAR O GRUPO."
		)
		btn_confirmar_desistencia.text = "SIM, SALVAR E SAIR"
	else:
		label_confirmacao_titulo.text = "DESISTIR DA PARTIDA?"
		label_confirmacao_titulo.add_theme_color_override(
			"font_color", Color(1.0, 0.48, 0.48, 1.0)
		)
		label_confirmacao_mensagem.text = (
			"VOCÊ SERÁ ELIMINADO E O ADVERSÁRIO\nRECEBERÁ A VITÓRIA. ESTA AÇÃO NÃO\nPODE SER DESFEITA."
		)
		btn_confirmar_desistencia.text = "SIM, DESISTIR"
	btn_confirmar_desistencia.disabled = false
	painel_confirmacao.visible = true
	var painel := %PainelConfirmarDesistencia as Control
	painel.modulate.a = 0.0
	painel.scale = Vector2(0.94, 0.94)
	painel.pivot_offset = painel.size * 0.5
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	tween.tween_property(painel, "modulate:a", 1.0, 0.18)
	(
		tween
		. tween_property(painel, "scale", Vector2.ONE, 0.28)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	call_deferred("_focar_cancelar_desistencia")


func _fechar_confirmacao() -> void:
	painel_confirmacao.visible = false
	btn_confirmar_desistencia.disabled = false
	btn_confirmar_desistencia.text = "SIM, DESISTIR"
	_modo_confirmacao = "desistencia"
	call_deferred("_focar_continuar")


func _focar_cancelar_desistencia() -> void:
	var botao := %BtnCancelarDesistencia as Button
	if botao != null:
		botao.grab_focus()


func _on_btn_confirmar_desistencia_pressed() -> void:
	if not _sou_iniciador_pausa:
		return
	btn_confirmar_desistencia.disabled = true
	if _modo_confirmacao == "salvar_sair":
		btn_confirmar_desistencia.text = "SALVANDO..."
		solicitar_salvar_e_sair.emit()
	else:
		btn_confirmar_desistencia.text = "ENCERRANDO..."
		# O host retirará a pausa lógica de todos antes de resolver a desistência.
		solicitar_desistencia.emit()


func restaurar_apos_falha_desistencia(mensagem: String) -> void:
	btn_confirmar_desistencia.disabled = false
	btn_confirmar_desistencia.text = "SIM, DESISTIR"
	_mostrar_aviso(mensagem)


func _on_btn_salvar_pressed() -> void:
	if not _sou_iniciador_pausa or btn_salvar.disabled:
		return
	btn_salvar.disabled = true
	btn_salvar.text = "SALVANDO..."
	solicitar_salvamento.emit()


func _on_btn_sair_pressed() -> void:
	if not _sou_iniciador_pausa:
		return
	_abrir_confirmacao("salvar_sair")


func notificar_resultado_salvamento(
	sucesso: bool,
	mensagem: String,
	encerrando: bool = false
) -> void:
	btn_salvar.disabled = false
	btn_salvar.text = "SALVAR AGORA"
	btn_sair.disabled = false
	btn_sair.text = "SALVAR E SAIR"
	if encerrando and sucesso:
		btn_confirmar_desistencia.disabled = true
		btn_confirmar_desistencia.text = "SAINDO..."
		_mostrar_aviso("PARTIDA SALVA\nVOLTANDO AO MENU ONLINE")
		return
	if painel_confirmacao.visible and _modo_confirmacao == "salvar_sair":
		btn_confirmar_desistencia.disabled = false
		btn_confirmar_desistencia.text = "SIM, SALVAR E SAIR"
	_mostrar_aviso(mensagem if not mensagem.is_empty() else (
		"PARTIDA SALVA" if sucesso else "FALHA AO SALVAR A PARTIDA"
	))


func _mostrar_aviso(texto: String) -> void:
	label_aviso.text = texto
	aviso.visible = true
	aviso.modulate.a = 0.0
	aviso.position.y = 16.0
	if _tween_aviso != null and _tween_aviso.is_valid():
		_tween_aviso.kill()
	_tween_aviso = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween_aviso.tween_property(aviso, "modulate:a", 1.0, 0.18)
	(
		_tween_aviso
		. parallel()
		. tween_property(aviso, "position:y", 0.0, 0.22)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	_tween_aviso.tween_interval(1.85)
	_tween_aviso.tween_property(aviso, "modulate:a", 0.0, 0.25)
	_tween_aviso.tween_callback(func() -> void:
		if aviso != null and is_instance_valid(aviso):
			aviso.visible = false
	)


func _configurar_opcoes_atuais() -> void:
	var indice_master := AudioServer.get_bus_index("Master")
	if indice_master >= 0:
		var volume_linear := db_to_linear(AudioServer.get_bus_volume_db(indice_master))
		slider_volume.set_value_no_signal(clampf(volume_linear * 100.0, 0.0, 100.0))
	_atualizar_label_volume(slider_volume.value)
	var modo := DisplayServer.window_get_mode()
	check_tela_cheia.set_pressed_no_signal(
		modo == DisplayServer.WINDOW_MODE_FULLSCREEN
		or modo == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	)


func _on_slider_volume_value_changed(valor: float) -> void:
	var indice_master := AudioServer.get_bus_index("Master")
	if indice_master >= 0:
		AudioServer.set_bus_volume_db(
			indice_master,
			linear_to_db(maxf(valor / 100.0, 0.0001))
		)
	_atualizar_label_volume(valor)


func _atualizar_label_volume(valor: float) -> void:
	label_volume.text = "%d%%" % int(round(valor))


func _on_check_tela_cheia_toggled(ativado: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if ativado else DisplayServer.WINDOW_MODE_WINDOWED
	)


func _matar_tween_interface() -> void:
	if _tween_interface != null and _tween_interface.is_valid():
		_tween_interface.kill()
