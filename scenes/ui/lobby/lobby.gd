extends Control

# Mesma referência de ritmo usada no menu_principal.gd.
@export_range(80.0, 600.0, 10.0) var distancia_entrada_voltar: float = 300.0
@export_range(80.0, 600.0, 10.0) var distancia_entrada_vertical: float = 220.0
@export_range(0.2, 1.5, 0.05) var duracao_entrada: float = 0.95
@export_range(0.05, 0.5, 0.01) var intervalo_entre_controles: float = 0.24

var _tween_entrada: Tween
var _ip_copiado_atual: String = ""

@onready var btn_voltar: Button = $BtnVoltar
@onready var btn_criar: Button = $VBoxContainer/BtnCriar
@onready var input_ip: LineEdit = $VBoxContainer/InputIP
@onready var btn_entrar: Button = $VBoxContainer/BtnEntrar
@onready var painel_info_rede: PanelContainer = $VBoxContainer/PainelInfoRede
@onready var label_status_rede: Label = $VBoxContainer/PainelInfoRede/MargemInfo/VBoxInfo/LabelStatusRede
@onready var label_titulo_ip: Label = $VBoxContainer/PainelInfoRede/MargemInfo/VBoxInfo/LabelTituloIP
@onready var seletor_ip_host: OptionButton = $VBoxContainer/PainelInfoRede/MargemInfo/VBoxInfo/SeletorIPHost
@onready var botoes_ip: HBoxContainer = $VBoxContainer/PainelInfoRede/MargemInfo/VBoxInfo/BotoesIP
@onready var btn_copiar_ip: Button = $VBoxContainer/PainelInfoRede/MargemInfo/VBoxInfo/BotoesIP/BtnCopiarIP
@onready var btn_atualizar_ip: Button = $VBoxContainer/PainelInfoRede/MargemInfo/VBoxInfo/BotoesIP/BtnAtualizarIP
@onready var label_dica_rede: Label = $VBoxContainer/PainelInfoRede/MargemInfo/VBoxInfo/LabelDicaRede
@onready var btn_cancelar_conexao: Button = $VBoxContainer/BtnCancelarConexao
@onready var btn_comecar: Button = $VBoxContainer/BtnComecar
@onready var texto_jogadores: Label = $TextoJogadores


func _ready() -> void:
	_conectar_sinais_rede()
	_configurar_estado_visual_inicial()

	# Esconde os controles antes do primeiro frame renderizado. Sem isso, eles
	# aparecem por alguns frames enquanto o VBoxContainer calcula o layout,
	# somem quando o tween começa e só então fazem a animação de entrada.
	_ocultar_controles_ate_a_animacao()

	# Aguarda o VBoxContainer calcular as posições e tamanhos definitivos.
	await get_tree().process_frame
	await get_tree().process_frame

	_restaurar_estado_rede_existente()
	if not NetworkManager.esta_em_sala() and not NetworkManager.esta_conectando():
		animar_entrada_controles()
	else:
		# Ao restaurar uma sala/conexão já existente, o menu inicial não anima,
		# mas o botão VOLTAR ainda precisa ficar disponível imediatamente.
		_mostrar_controle_sem_animacao(btn_voltar)


func _conectar_sinais_rede() -> void:
	if not NetworkManager.conectado_ao_servidor.is_connected(_on_conectado_ao_servidor):
		NetworkManager.conectado_ao_servidor.connect(_on_conectado_ao_servidor)
	if not NetworkManager.falha_conexao.is_connected(_on_falha_conexao):
		NetworkManager.falha_conexao.connect(_on_falha_conexao)
	if not NetworkManager.servidor_desconectado.is_connected(_on_servidor_desconectado):
		NetworkManager.servidor_desconectado.connect(_on_servidor_desconectado)
	if not NetworkManager.jogador_conectado.is_connected(_on_lista_jogadores_alterada):
		NetworkManager.jogador_conectado.connect(_on_lista_jogadores_alterada)
	if not NetworkManager.jogador_desconectado.is_connected(_on_lista_jogadores_alterada):
		NetworkManager.jogador_desconectado.connect(_on_lista_jogadores_alterada)


func _configurar_estado_visual_inicial() -> void:
	texto_jogadores.visible = false
	painel_info_rede.visible = false
	btn_cancelar_conexao.visible = false
	btn_comecar.visible = false
	_mostrar_menu_inicial()


func _ocultar_controles_ate_a_animacao() -> void:
	var controles: Array[Control] = [btn_voltar, btn_criar, input_ip, btn_entrar]
	for controle in controles:
		controle.modulate.a = 0.0
		controle.scale = Vector2(0.96, 0.96)
		controle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		controle.focus_mode = Control.FOCUS_NONE


func _mostrar_controle_sem_animacao(controle: Control) -> void:
	controle.pivot_offset = controle.size * 0.5
	controle.modulate.a = 1.0
	controle.scale = Vector2.ONE
	controle.mouse_filter = Control.MOUSE_FILTER_STOP
	controle.focus_mode = Control.FOCUS_ALL


func _restaurar_estado_rede_existente() -> void:
	var mensagem_pendente := NetworkManager.consumir_mensagem_pendente_lobby()
	if mensagem_pendente != "":
		_mostrar_erro_rede(mensagem_pendente)
		return

	if NetworkManager.esta_hospedando():
		_esconder_menu_inicial()
		_mostrar_painel_host(NetworkManager.atualizar_ips_host())
		_atualizar_contador()
	elif NetworkManager.esta_conectado_como_cliente():
		_esconder_menu_inicial()
		_mostrar_painel_cliente_conectado()
		_atualizar_contador()
	elif NetworkManager.esta_conectando():
		_esconder_menu_inicial()
		_mostrar_estado_conectando(NetworkManager.ip_alvo_atual)
	elif NetworkManager.estado_rede == NetworkManager.EstadoRede.ERRO:
		_mostrar_erro_rede(NetworkManager.ultima_mensagem_rede)


func animar_entrada_controles() -> void:
	if _tween_entrada and _tween_entrada.is_valid():
		_tween_entrada.kill()

	var controles_verticais: Array[Control] = [btn_criar, input_ip, btn_entrar]
	var posicao_final_voltar: Vector2 = btn_voltar.position
	var posicoes_finais_verticais: Array[Vector2] = []

	_preparar_controle_para_entrada(btn_voltar)
	btn_voltar.position -= Vector2(distancia_entrada_voltar, 0.0)

	for controle in controles_verticais:
		posicoes_finais_verticais.append(controle.position)
		_preparar_controle_para_entrada(controle)
		controle.position -= Vector2(0.0, distancia_entrada_vertical)

	_tween_entrada = create_tween().set_parallel(true)
	_animar_controle_ate(btn_voltar, posicao_final_voltar, 0.0)

	for indice in controles_verticais.size():
		var atraso: float = float(indice + 1) * intervalo_entre_controles
		_animar_controle_ate(controles_verticais[indice], posicoes_finais_verticais[indice], atraso)

	await _tween_entrada.finished

	_finalizar_controle_entrada(btn_voltar, posicao_final_voltar)
	for indice in controles_verticais.size():
		_finalizar_controle_entrada(controles_verticais[indice], posicoes_finais_verticais[indice])

	if btn_criar.visible and not btn_criar.disabled:
		btn_criar.grab_focus()


func _preparar_controle_para_entrada(controle: Control) -> void:
	controle.pivot_offset = controle.size * 0.5
	controle.modulate.a = 0.0
	controle.scale = Vector2(0.96, 0.96)
	controle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controle.focus_mode = Control.FOCUS_NONE


func _animar_controle_ate(controle: Control, posicao_final: Vector2, atraso: float) -> void:
	(
		_tween_entrada
		. tween_property(controle, "position", posicao_final, duracao_entrada)
		. set_delay(atraso)
		. set_trans(Tween.TRANS_QUINT)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_tween_entrada
		. tween_property(controle, "modulate:a", 1.0, duracao_entrada * 0.72)
		. set_delay(atraso)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_tween_entrada
		. tween_property(controle, "scale", Vector2.ONE, duracao_entrada)
		. set_delay(atraso)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)


func _finalizar_controle_entrada(controle: Control, posicao_final: Vector2) -> void:
	controle.position = posicao_final
	controle.modulate.a = 1.0
	controle.scale = Vector2.ONE
	controle.mouse_filter = Control.MOUSE_FILTER_STOP
	controle.focus_mode = Control.FOCUS_ALL


func _on_btn_criar_pressed() -> void:
	_set_menu_interativo(false)
	texto_jogadores.visible = true
	texto_jogadores.text = "ABRINDO SALA LAN..."

	var erro: int = NetworkManager.criar_servidor()
	if erro != OK:
		_set_menu_interativo(true)
		_mostrar_erro_rede(NetworkManager.ultima_mensagem_rede)
		return

	_esconder_menu_inicial()
	_mostrar_painel_host(NetworkManager.ips_host_disponiveis)
	_atualizar_contador()


func _on_btn_entrar_pressed() -> void:
	var ip_digitado := input_ip.text.strip_edges()
	if ip_digitado.is_empty():
		_mostrar_erro_rede("Digite o IPv4 mostrado no aparelho que criou a sala.")
		input_ip.grab_focus()
		return
	if not NetworkManager.endereco_ipv4_valido(ip_digitado):
		_mostrar_erro_rede("IP inválido. Exemplo correto: 192.168.1.25")
		input_ip.grab_focus()
		return
	if NetworkManager.endereco_loopback(ip_digitado):
		_mostrar_erro_rede(
			"127.0.0.1 aponta para este aparelho. Use o IP mostrado no lobby do host."
		)
		input_ip.grab_focus()
		return

	_set_menu_interativo(false)
	_esconder_menu_inicial()
	_mostrar_estado_conectando(ip_digitado)
	var erro: int = NetworkManager.entrar_servidor(ip_digitado)
	if erro != OK:
		_set_menu_interativo(true)
		_mostrar_menu_inicial()
		_mostrar_erro_rede(NetworkManager.ultima_mensagem_rede)


func _on_input_ip_text_submitted(_novo_texto: String) -> void:
	if not btn_entrar.disabled:
		_on_btn_entrar_pressed()


func _mostrar_estado_conectando(ip_digitado: String) -> void:
	painel_info_rede.visible = true
	label_titulo_ip.visible = false
	seletor_ip_host.visible = false
	botoes_ip.visible = false
	btn_cancelar_conexao.visible = true
	btn_comecar.visible = false
	texto_jogadores.visible = true
	texto_jogadores.text = "CONECTANDO À SALA..."
	_definir_cor_status(Color(1.0, 0.78, 0.3))
	label_status_rede.text = "CONECTANDO EM %s:%d" % [ip_digitado, NetworkManager.PORT]
	label_dica_rede.text = (
		"Aguarde a confirmação do servidor. A tentativa será cancelada automaticamente após %.0f segundos."
		% NetworkManager.TIMEOUT_CONEXAO_SEGUNDOS
	)


func _on_conectado_ao_servidor() -> void:
	_esconder_menu_inicial()
	btn_cancelar_conexao.visible = false
	_mostrar_painel_cliente_conectado()
	_atualizar_contador()


func _mostrar_painel_cliente_conectado() -> void:
	painel_info_rede.visible = true
	label_titulo_ip.visible = false
	seletor_ip_host.visible = false
	botoes_ip.visible = false
	btn_comecar.visible = false
	_definir_cor_status(Color(0.45, 1.0, 0.55))
	label_status_rede.text = "CONECTADO AO HOST %s:%d" % [NetworkManager.ip_alvo_atual, NetworkManager.PORT]
	label_dica_rede.text = "Conexão confirmada. Aguarde o host iniciar a seleção de personagens."


func _on_falha_conexao(mensagem: String) -> void:
	_set_menu_interativo(true)
	btn_cancelar_conexao.visible = false
	_mostrar_menu_inicial()
	_mostrar_erro_rede(mensagem)
	input_ip.grab_focus()


func _on_servidor_desconectado(mensagem: String) -> void:
	_set_menu_interativo(true)
	btn_cancelar_conexao.visible = false
	btn_comecar.visible = false
	_mostrar_menu_inicial()
	_mostrar_erro_rede(mensagem)


func _mostrar_painel_host(ips: PackedStringArray) -> void:
	painel_info_rede.visible = true
	label_titulo_ip.visible = true
	seletor_ip_host.visible = true
	botoes_ip.visible = true
	btn_cancelar_conexao.visible = false
	btn_comecar.visible = true
	_definir_cor_status(Color(0.45, 1.0, 0.55))
	label_status_rede.text = "SALA LAN CRIADA — PORTA UDP %d" % NetworkManager.PORT
	label_dica_rede.text = (
		"Passe o IP selecionado para quem está no mesmo Wi-Fi. Se houver mais de um, escolha o da rede Wi-Fi. "
		+ "No Windows, permita o jogo no Firewall para redes privadas."
	)
	_preencher_seletor_ips(ips)


func _preencher_seletor_ips(ips: PackedStringArray) -> void:
	seletor_ip_host.clear()
	_ip_copiado_atual = ""

	if ips.is_empty():
		seletor_ip_host.add_item("IP LAN NÃO ENCONTRADO")
		seletor_ip_host.disabled = true
		btn_copiar_ip.disabled = true
		label_dica_rede.text = (
			"Nenhum IPv4 de rede foi detectado. Conecte o aparelho ao Wi-Fi e toque em ATUALIZAR IP."
		)
		return

	for endereco in ips:
		seletor_ip_host.add_item(endereco)
	seletor_ip_host.disabled = false
	btn_copiar_ip.disabled = false
	seletor_ip_host.select(0)
	_ip_copiado_atual = seletor_ip_host.get_item_text(0)


func _on_seletor_ip_host_item_selected(indice: int) -> void:
	if indice < 0 or indice >= seletor_ip_host.item_count:
		return
	_ip_copiado_atual = seletor_ip_host.get_item_text(indice)


func _on_btn_copiar_ip_pressed() -> void:
	if _ip_copiado_atual.is_empty() or not NetworkManager.endereco_ipv4_valido(_ip_copiado_atual):
		return
	DisplayServer.clipboard_set(_ip_copiado_atual)
	label_status_rede.text = "IP COPIADO: %s  —  PORTA UDP %d" % [_ip_copiado_atual, NetworkManager.PORT]


func _on_btn_atualizar_ip_pressed() -> void:
	if not NetworkManager.esta_hospedando():
		return
	var ips := NetworkManager.atualizar_ips_host()
	_preencher_seletor_ips(ips)
	label_status_rede.text = "SALA LAN CRIADA — PORTA UDP %d" % NetworkManager.PORT


func _on_btn_cancelar_conexao_pressed() -> void:
	NetworkManager.desconectar("Tentativa de conexão cancelada.")
	btn_cancelar_conexao.visible = false
	painel_info_rede.visible = false
	texto_jogadores.visible = false
	_mostrar_menu_inicial()
	_set_menu_interativo(true)
	input_ip.grab_focus()


func _mostrar_erro_rede(mensagem: String) -> void:
	painel_info_rede.visible = true
	label_titulo_ip.visible = false
	seletor_ip_host.visible = false
	botoes_ip.visible = false
	btn_comecar.visible = false
	btn_cancelar_conexao.visible = false
	texto_jogadores.visible = true
	texto_jogadores.text = "FALHA NA CONEXÃO"
	_definir_cor_status(Color(1.0, 0.35, 0.35))
	label_status_rede.text = mensagem
	label_dica_rede.text = (
		"Confira se os dois aparelhos estão no mesmo Wi-Fi, se o IP foi digitado corretamente e se a porta UDP %d "
		+ "está liberada no Firewall do computador host."
	) % NetworkManager.PORT


func _definir_cor_status(cor: Color) -> void:
	label_status_rede.add_theme_color_override("font_color", cor)


func _mostrar_menu_inicial() -> void:
	btn_criar.visible = true
	input_ip.visible = true
	btn_entrar.visible = true


func _esconder_menu_inicial() -> void:
	btn_criar.visible = false
	input_ip.visible = false
	btn_entrar.visible = false


func _set_menu_interativo(habilitado: bool) -> void:
	btn_criar.disabled = not habilitado
	input_ip.editable = habilitado
	btn_entrar.disabled = not habilitado
	var alpha := 1.0 if habilitado else 0.65
	btn_criar.modulate.a = alpha
	input_ip.modulate.a = alpha
	btn_entrar.modulate.a = alpha


func _on_lista_jogadores_alterada(_id: int) -> void:
	_atualizar_contador()


func _atualizar_contador() -> void:
	if not NetworkManager.esta_em_sala():
		return

	var total_jogadores := NetworkManager.total_jogadores_na_sala()
	texto_jogadores.visible = true
	texto_jogadores.text = "LOBBY — JOGADORES CONECTADOS (%d/%d)" % [total_jogadores, NetworkManager.MAX_JOGADORES]

	if not NetworkManager.esta_hospedando():
		btn_comecar.visible = false
		return

	btn_comecar.visible = true
	if total_jogadores >= 2:
		btn_comecar.disabled = false
		btn_comecar.text = "COMEÇAR PARTIDA"
		btn_comecar.modulate = Color.WHITE
	else:
		btn_comecar.disabled = true
		btn_comecar.text = "AGUARDANDO +1 JOGADOR..."
		btn_comecar.modulate = Color(0.72, 0.72, 0.72)


func _on_btn_comecar_pressed() -> void:
	if not NetworkManager.esta_hospedando():
		_mostrar_erro_rede("Somente o host pode iniciar a partida.")
		return
	if NetworkManager.total_jogadores_na_sala() < 2:
		return

	btn_comecar.disabled = true
	btn_comecar.text = "INICIANDO..."
	OnlineTransport.send_all(NetworkManager, &"iniciar_selecao_personagens", [], true, true)


func _on_btn_voltar_pressed() -> void:
	NetworkManager.desconectar("Você saiu da sala.")
	get_tree().change_scene_to_file("res://scenes/ui/tela_inicial/menu_principal.tscn")
