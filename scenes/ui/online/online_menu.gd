extends Control

const AMARELO := Color("#f2b5a8")
const VERDE := Color("#83c99a")
const VERMELHO := Color("#e97982")
const AZUL := Color("#89aeea")
const CINZA := Color("#b8b4c1")
const BRANCO := Color("#faf7f8")

@onready var container_inicio: Control = %ContainerInicio
@onready var container_entrada_codigo: VBoxContainer = %ContainerEntradaCodigo
@onready var container_lobby_online: Control = %ContainerLobbyOnline
@onready var lista_jogadores_box: VBoxContainer = %ListaJogadoresBox

@onready var lbl_status_conexao: Label = %LblStatusConexao
@onready var lbl_mensagem_inicio: Label = %LblMensagemInicio
@onready var lbl_codigo_atual: Label = %LblCodigoAtual
@onready var lbl_contador_jogadores: Label = %LblContadorJogadores
@onready var lbl_estado_prontidao: Label = %LblEstadoProntidao
@onready var lbl_papel_local: Label = %LblPapelLocal
@onready var lbl_dica_lobby: Label = %LblDicaLobby

@onready var input_nome: LineEdit = %InputNome
@onready var input_codigo: LineEdit = %InputCodigo
@onready var painel_retomada: PanelContainer = %PainelRetomada
@onready var lbl_resumo_retomada: Label = %LblResumoRetomada
@onready var confirmacao_exclusao_salvamento: Control = %ConfirmacaoExcluirSalvamento
@onready var painel_confirmacao_exclusao: PanelContainer = %PainelConfirmacaoExclusao

@onready var btn_criar_sala: Button = %BtnCriarSala
@onready var btn_mostrar_entrada_codigo: Button = %BtnMostrarEntradaCodigo
@onready var btn_confirmar_entrada: Button = %BtnConfirmarEntrada
@onready var btn_retomar_partida: Button = %BtnRetomarPartida
@onready var btn_excluir_partida_salva: Button = %BtnExcluirPartidaSalva
@onready var btn_copiar_codigo: Button = %BtnCopiarCodigo
@onready var btn_pronto: Button = %BtnPronto
@onready var btn_iniciar_partida: Button = %BtnIniciarPartida
@onready var btn_sair_sala: Button = %BtnSairSala
@onready var btn_voltar: Button = %BtnVoltar

var linhas_jogadores: Array[Dictionary] = []
var _ocupado := false
var _retomada_solicitada: bool = false
var _contexto_retomada: Dictionary = {}
var _publicacao_retomada_agendada: bool = false


func _ready() -> void:
	_preparar_linhas_jogadores()
	_carregar_nome_salvo()
	_conectar_sinais_photon()
	_atualizar_estado(PhotonManager.recarregar_configuracao())
	_atualizar_lista_jogadores(PhotonManager.obter_jogadores_sala())
	_atualizar_painel_partida_salva()
	_animar_entrada()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if confirmacao_exclusao_salvamento.visible:
		_fechar_confirmacao_exclusao()
		get_viewport().set_input_as_handled()
		return
	if _ocupado:
		return
	if PhotonManager.esta_em_sala():
		_sair_sala()
	else:
		_voltar_menu()


func _preparar_linhas_jogadores() -> void:
	linhas_jogadores.clear()

	for painel in lista_jogadores_box.get_children():
		var linha := painel.get_node_or_null("Margem/Linha") as HBoxContainer
		if linha == null:
			continue

		var indicador := linha.get_node_or_null("Indicador") as Label
		var nome := linha.get_node_or_null("Nome") as Label
		var cargo := linha.get_node_or_null("Cargo") as Label
		var estado := linha.get_node_or_null("Estado") as Label

		if indicador == null or nome == null or cargo == null or estado == null:
			push_warning("Uma linha de jogador no online_menu.tscn está incompleta.")
			continue

		linhas_jogadores.append({
			"painel": painel,
			"indicador": indicador,
			"nome": nome,
			"cargo": cargo,
			"estado": estado,
		})


func _carregar_nome_salvo() -> void:
	input_nome.text = str(Progressao.obter_perfil().get("nome", "JOGADOR"))


func _animar_entrada() -> void:
	modulate.a = 0.0
	position.y = 14.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.24)
	tween.tween_property(self, "position:y", 0.0, 0.34).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_OUT
	)


func _conectar_sinais_photon() -> void:
	if not PhotonManager.estado_alterado.is_connected(_atualizar_estado):
		PhotonManager.estado_alterado.connect(_atualizar_estado)
	if not PhotonManager.sala_entrada.is_connected(_ao_entrar_sala):
		PhotonManager.sala_entrada.connect(_ao_entrar_sala)
	if not PhotonManager.sala_saida.is_connected(_ao_sair_sala):
		PhotonManager.sala_saida.connect(_ao_sair_sala)
	if not PhotonManager.erro_photon.is_connected(_ao_erro):
		PhotonManager.erro_photon.connect(_ao_erro)
	if not PhotonManager.jogadores_sala_alterados.is_connected(_ao_jogadores_sala_alterados):
		PhotonManager.jogadores_sala_alterados.connect(_ao_jogadores_sala_alterados)
	if not PhotonManager.pronto_local_alterado.is_connected(_ao_pronto_local_alterado):
		PhotonManager.pronto_local_alterado.connect(_ao_pronto_local_alterado)
	if not PhotonManager.host_alterado.is_connected(_ao_host_alterado):
		PhotonManager.host_alterado.connect(_ao_host_alterado)


func _atualizar_estado(resumo: Dictionary) -> void:
	var plugin_ok := bool(resumo.get("plugin_disponivel", false))
	var config_ok := bool(resumo.get("configuracao_valida", false))
	var conectado := bool(resumo.get("conectado", false))
	var em_sala := bool(resumo.get("em_sala", false))
	var entrando := bool(resumo.get("entrando_sala", false))
	var estado_atual := int(resumo.get("estado", 0))

	_ocupado = estado_atual in [
		PhotonManager.Estado.CONECTANDO,
		PhotonManager.Estado.ENTRANDO_SALA,
	]

	if not plugin_ok:
		_definir_status_conexao("SERVIÇO ONLINE: INDISPONÍVEL", VERMELHO)
	elif not config_ok:
		_definir_status_conexao("SERVIÇO ONLINE: NÃO CONFIGURADO", AMARELO)
	elif conectado:
		_definir_status_conexao("SERVIÇO ONLINE: CONECTADO", VERDE)
	elif _ocupado:
		_definir_status_conexao("SERVIÇO ONLINE: CONECTANDO...", AZUL)
	else:
		_definir_status_conexao("SERVIÇO ONLINE: DISPONÍVEL", VERDE)

	container_inicio.visible = not em_sala
	container_lobby_online.visible = em_sala
	btn_voltar.visible = not em_sala
	btn_voltar.disabled = _ocupado

	var pode_usar_online := plugin_ok and config_ok and not _ocupado and not em_sala
	btn_criar_sala.disabled = not pode_usar_online
	btn_criar_sala.text = "CRIANDO SALA..." if _ocupado else "CRIAR SALA"
	btn_mostrar_entrada_codigo.disabled = not pode_usar_online
	btn_confirmar_entrada.disabled = not pode_usar_online
	btn_confirmar_entrada.text = "ENTRANDO..." if entrando else "ENTRAR"
	btn_retomar_partida.disabled = (
		not pode_usar_online
		or not GerenciadorSalvamento.pode_retomar_nesta_instalacao()
	)
	input_nome.editable = not _ocupado and not em_sala
	input_codigo.editable = not _ocupado and not em_sala
	_atualizar_painel_partida_salva()

	_atualizar_mensagem_inicio(resumo, plugin_ok, config_ok, conectado, entrando, estado_atual)

	if em_sala:
		var codigo := str(resumo.get("codigo_sala", ""))
		lbl_codigo_atual.text = "CÓDIGO: %s" % (codigo if not codigo.is_empty() else "—")
		btn_copiar_codigo.disabled = codigo.is_empty() or codigo == "PARTIDA-RAPIDA"
		_atualizar_lista_jogadores(PhotonManager.obter_jogadores_sala())


func _atualizar_mensagem_inicio(
	resumo: Dictionary,
	plugin_ok: bool,
	config_ok: bool,
	conectado: bool,
	entrando: bool,
	estado_atual: int
) -> void:
	var texto := "Crie uma sala ou entre usando um código."
	var cor := CINZA

	if not plugin_ok:
		texto = "O módulo Photon Fusion não foi encontrado no projeto."
		cor = VERMELHO
	elif not config_ok:
		texto = "O modo online ainda não possui um App ID válido."
		cor = AMARELO
	elif estado_atual == PhotonManager.Estado.ERRO:
		texto = str(resumo.get("erro", resumo.get("mensagem", "Não foi possível conectar.")))
		cor = VERMELHO
	elif entrando:
		texto = "Conectando e entrando na sala..."
		cor = AZUL
	elif estado_atual == PhotonManager.Estado.CONECTANDO:
		texto = "Conectando ao serviço online..."
		cor = AZUL
	elif conectado:
		texto = "Conectado. Escolha como deseja jogar."
		cor = VERDE

	lbl_mensagem_inicio.text = texto
	lbl_mensagem_inicio.add_theme_color_override("font_color", cor)


func _definir_status_conexao(texto: String, cor: Color) -> void:
	lbl_status_conexao.text = texto
	lbl_status_conexao.add_theme_color_override("font_color", cor)


func _salvar_nome() -> void:
	var nome := input_nome.text.strip_edges()
	if nome.is_empty():
		input_nome.text = str(Progressao.obter_perfil().get("nome", "JOGADOR"))
		return

	Progressao.definir_nome(nome)
	input_nome.text = str(Progressao.obter_perfil().get("nome", nome))
	PhotonManager.definir_nome_local(input_nome.text)


func _atualizar_painel_partida_salva() -> void:
	var resumo: Dictionary = GerenciadorSalvamento.obter_resumo_partida_salva()
	painel_retomada.visible = not resumo.is_empty()
	if resumo.is_empty():
		_fechar_confirmacao_exclusao()
		return
	var rodada: int = int(resumo.get("rodada", 1))
	var quantidade: int = int(resumo.get("quantidade_participantes", 0))
	var data: String = str(resumo.get("salvo_em_texto", ""))
	lbl_resumo_retomada.text = (
		"Rodada %d  •  %d participantes  •  %s" % [rodada, quantidade, data]
	)
	var pode_retomar: bool = bool(resumo.get("pode_retomar", false))
	btn_retomar_partida.disabled = (
		_ocupado
		or PhotonManager.esta_em_sala()
		or not pode_retomar
		or not PhotonManager.plugin_disponivel
		or not PhotonManager.configuracao_valida
	)
	btn_retomar_partida.text = (
		"RETOMAR PARTIDA" if pode_retomar else "SALVAMENTO DO HOST ORIGINAL"
	)
	btn_excluir_partida_salva.disabled = _ocupado or PhotonManager.esta_em_sala()


func _solicitar_exclusao_partida_salva() -> void:
	if (
		_ocupado
		or PhotonManager.esta_em_sala()
		or not GerenciadorSalvamento.tem_partida_salva()
	):
		return
	confirmacao_exclusao_salvamento.visible = true
	confirmacao_exclusao_salvamento.modulate.a = 0.0
	painel_confirmacao_exclusao.scale = Vector2(0.94, 0.94)
	painel_confirmacao_exclusao.pivot_offset = painel_confirmacao_exclusao.size * 0.5
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(confirmacao_exclusao_salvamento, "modulate:a", 1.0, 0.16)
	(
		tween
		. tween_property(painel_confirmacao_exclusao, "scale", Vector2.ONE, 0.24)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	call_deferred("_focar_cancelar_exclusao")


func _cancelar_exclusao_partida_salva() -> void:
	_fechar_confirmacao_exclusao()


func _confirmar_exclusao_partida_salva() -> void:
	if _ocupado or PhotonManager.esta_em_sala():
		_fechar_confirmacao_exclusao()
		return
	var removida: bool = GerenciadorSalvamento.remover_partida_salva()
	_fechar_confirmacao_exclusao()
	_atualizar_painel_partida_salva()
	if not removida:
		lbl_mensagem_inicio.text = "Não foi possível excluir completamente a partida salva."
		lbl_mensagem_inicio.add_theme_color_override("font_color", VERMELHO)
		return

	_retomada_solicitada = false
	_contexto_retomada.clear()
	lbl_mensagem_inicio.text = "Partida salva excluída."
	lbl_mensagem_inicio.add_theme_color_override("font_color", VERDE)


func _fechar_confirmacao_exclusao() -> void:
	if confirmacao_exclusao_salvamento == null:
		return
	confirmacao_exclusao_salvamento.visible = false
	confirmacao_exclusao_salvamento.modulate.a = 1.0
	painel_confirmacao_exclusao.scale = Vector2.ONE


func _focar_cancelar_exclusao() -> void:
	if not confirmacao_exclusao_salvamento.visible:
		return
	var botao_cancelar: Button = %BtnCancelarExclusao
	botao_cancelar.grab_focus()


func _retomar_partida_salva() -> void:
	if _ocupado or PhotonManager.esta_em_sala():
		return
	_salvar_nome()
	var codigo_novo: String = PhotonManager.gerar_codigo_sala(7)
	var preparacao: Dictionary = GerenciadorSalvamento.preparar_sala_retomada(
		codigo_novo
	)
	if not bool(preparacao.get("sucesso", false)):
		lbl_mensagem_inicio.text = str(
			preparacao.get("mensagem", "Não foi possível preparar a retomada.")
		)
		lbl_mensagem_inicio.add_theme_color_override("font_color", VERMELHO)
		return

	_retomada_solicitada = true
	_contexto_retomada = Dictionary(preparacao.get("contexto", {})).duplicate(true)
	input_codigo.text = codigo_novo
	lbl_mensagem_inicio.text = "Criando uma nova sala para retomar a partida..."
	lbl_mensagem_inicio.add_theme_color_override("font_color", AZUL)
	var iniciou: bool = PhotonManager.entrar_ou_criar_sala(codigo_novo, 6)
	if not iniciou:
		_retomada_solicitada = false
		_contexto_retomada.clear()
		GerenciadorSalvamento.cancelar_preparacao_retomada()
		lbl_mensagem_inicio.text = "Não foi possível criar a sala de retomada."
		lbl_mensagem_inicio.add_theme_color_override("font_color", VERMELHO)
	_atualizar_painel_partida_salva()


func _criar_sala() -> void:
	if _ocupado:
		return

	_retomada_solicitada = false
	_contexto_retomada.clear()
	GerenciadorSalvamento.cancelar_preparacao_retomada()
	_salvar_nome()
	var codigo := PhotonManager.gerar_codigo_sala()
	input_codigo.text = codigo
	lbl_mensagem_inicio.text = "Criando a sala %s..." % codigo
	lbl_mensagem_inicio.add_theme_color_override("font_color", AZUL)
	PhotonManager.entrar_ou_criar_sala(codigo, 6)


func _mostrar_entrada_codigo() -> void:
	if _ocupado:
		return

	container_entrada_codigo.visible = not container_entrada_codigo.visible
	if container_entrada_codigo.visible:
		btn_mostrar_entrada_codigo.text = "FECHAR CÓDIGO"
		input_codigo.grab_focus()
		input_codigo.caret_column = input_codigo.text.length()
	else:
		btn_mostrar_entrada_codigo.text = "ENTRAR COM CÓDIGO"


func _entrar_com_codigo() -> void:
	if _ocupado:
		return

	_retomada_solicitada = false
	_contexto_retomada.clear()
	GerenciadorSalvamento.cancelar_preparacao_retomada()
	_salvar_nome()
	var codigo := PhotonManager.normalizar_codigo_sala(input_codigo.text)
	input_codigo.text = codigo
	if codigo.length() < 3:
		lbl_mensagem_inicio.text = "Digite um código de sala válido."
		lbl_mensagem_inicio.add_theme_color_override("font_color", VERMELHO)
		input_codigo.grab_focus()
		return

	PhotonManager.entrar_ou_criar_sala(codigo, 6)


func _codigo_enviado(_texto: String) -> void:
	_entrar_com_codigo()


func _copiar_codigo() -> void:
	var codigo := str(PhotonManager.obter_resumo().get("codigo_sala", ""))
	if codigo.is_empty() or codigo == "PARTIDA-RAPIDA":
		return

	DisplayServer.clipboard_set(codigo)
	lbl_dica_lobby.text = "Código %s copiado. Envie para os outros jogadores." % codigo
	lbl_dica_lobby.add_theme_color_override("font_color", VERDE)


func _ao_entrar_sala(codigo: String, _id_local: int, _host: bool) -> void:
	input_codigo.text = codigo
	_atualizar_estado(PhotonManager.obter_resumo())
	_atualizar_lista_jogadores(PhotonManager.obter_jogadores_sala())

	container_lobby_online.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(container_lobby_online, "modulate:a", 1.0, 0.25)

	if _retomada_solicitada:
		if not _host:
			_retomada_solicitada = false
			_contexto_retomada.clear()
			GerenciadorSalvamento.cancelar_preparacao_retomada()
			PhotonManager.sair_sala()
			lbl_mensagem_inicio.text = (
				"O código gerado já estava ocupado. Tente retomar novamente."
			)
			lbl_mensagem_inicio.add_theme_color_override("font_color", VERMELHO)
			return
		_contexto_retomada = GerenciadorSalvamento.obter_contexto_publico_retomada()
		_agendar_publicacao_contexto_retomada()


func _ao_sair_sala() -> void:
	if _retomada_solicitada or GerenciadorSalvamento.retomada_em_preparacao():
		GerenciadorSalvamento.cancelar_preparacao_retomada()
	_retomada_solicitada = false
	_contexto_retomada.clear()
	_atualizar_lista_jogadores([])
	_atualizar_estado(PhotonManager.obter_resumo())

	container_inicio.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(container_inicio, "modulate:a", 1.0, 0.22)

	container_entrada_codigo.visible = false
	btn_mostrar_entrada_codigo.text = "ENTRAR COM CÓDIGO"
	_atualizar_painel_partida_salva()


func _ao_jogadores_sala_alterados(jogadores: Array) -> void:
	_atualizar_lista_jogadores(jogadores)
	if PhotonManager.eh_host and GerenciadorSalvamento.retomada_em_preparacao():
		_agendar_publicacao_contexto_retomada()


func _agendar_publicacao_contexto_retomada() -> void:
	if _publicacao_retomada_agendada:
		return
	_publicacao_retomada_agendada = true
	call_deferred("_publicar_contexto_retomada")


func _publicar_contexto_retomada() -> void:
	_publicacao_retomada_agendada = false
	if not is_inside_tree() or not PhotonManager.eh_host:
		return
	if not GerenciadorSalvamento.retomada_em_preparacao():
		return
	var contexto: Dictionary = GerenciadorSalvamento.obter_contexto_publico_retomada()
	if contexto.is_empty():
		return
	OnlineTransport.send_all(
		self,
		&"_aplicar_contexto_retomada_rede",
		[contexto],
		true,
		true
	)


@rpc("authority", "call_local", "reliable")
func _aplicar_contexto_retomada_rede(contexto: Dictionary) -> void:
	if contexto.is_empty() or str(contexto.get("sessao_id", "")).is_empty():
		return
	var participantes_variant: Variant = contexto.get("participantes", [])
	if not participantes_variant is Array:
		return
	var participantes: Array = participantes_variant
	if participantes.is_empty():
		return
	_contexto_retomada = contexto.duplicate(true)
	_atualizar_lista_jogadores(PhotonManager.obter_jogadores_sala())


func _atualizar_lista_jogadores(jogadores: Array) -> void:
	if linhas_jogadores.is_empty():
		return
	var avaliacao_retomada: Dictionary = {}
	var jogadores_exibicao: Array = jogadores
	if _retomada_ativa():
		avaliacao_retomada = _avaliar_participantes_retomada(jogadores)
		jogadores_exibicao = Array(
			avaliacao_retomada.get("linhas", [])
		)

	for indice in range(linhas_jogadores.size()):
		var linha: Dictionary = linhas_jogadores[indice]
		var indicador: Label = linha["indicador"]
		var nome_label: Label = linha["nome"]
		var cargo_label: Label = linha["cargo"]
		var estado_label: Label = linha["estado"]

		if indice >= jogadores_exibicao.size():
			indicador.add_theme_color_override("font_color", Color("#53617a"))
			nome_label.text = "VAGA DISPONÍVEL"
			nome_label.add_theme_color_override("font_color", CINZA)
			cargo_label.text = "—"
			cargo_label.add_theme_color_override("font_color", CINZA)
			estado_label.text = "VAZIA"
			estado_label.add_theme_color_override("font_color", CINZA)
			continue

		var dados: Dictionary = jogadores_exibicao[indice]
		var eh_local: bool = int(dados.get("id", 0)) == PhotonManager.jogador_local_id
		var inativo: bool = bool(dados.get("inativo", false))
		var pronto: bool = bool(dados.get("pronto", false))
		var host: bool = bool(dados.get("host", false))

		if _retomada_ativa():
			var ausente: bool = bool(dados.get("retomada_ausente", false))
			var extra: bool = bool(dados.get("retomada_extra", false))
			var nome_salvo: String = str(
				dados.get("nome_salvo", dados.get("nome", "JOGADOR"))
			)
			var personagem: String = str(dados.get("personagem", ""))
			nome_label.text = "%s%s" % [
				nome_salvo,
				" (VOCÊ)" if eh_local else "",
			]
			cargo_label.text = personagem.to_upper() if not personagem.is_empty() else "NÃO CONVIDADO"
			if extra:
				indicador.add_theme_color_override("font_color", VERMELHO)
				nome_label.add_theme_color_override("font_color", VERMELHO)
				cargo_label.add_theme_color_override("font_color", VERMELHO)
				estado_label.text = "NÃO PARTICIPAVA"
				estado_label.add_theme_color_override("font_color", VERMELHO)
			elif ausente:
				indicador.add_theme_color_override("font_color", AMARELO)
				nome_label.add_theme_color_override("font_color", CINZA)
				cargo_label.add_theme_color_override("font_color", AMARELO)
				estado_label.text = "CONVIDAR"
				estado_label.add_theme_color_override("font_color", AMARELO)
			else:
				indicador.add_theme_color_override("font_color", VERDE)
				nome_label.add_theme_color_override("font_color", AMARELO if eh_local else BRANCO)
				cargo_label.add_theme_color_override("font_color", AZUL if host else CINZA)
				estado_label.text = "CONFIRMADO"
				estado_label.add_theme_color_override("font_color", VERDE)
			continue

		nome_label.text = "%s%s" % [str(dados.get("nome", "JOGADOR")), " (VOCÊ)" if eh_local else ""]
		nome_label.add_theme_color_override("font_color", AMARELO if eh_local else BRANCO)
		cargo_label.text = "HOST" if host else "JOGADOR"
		cargo_label.add_theme_color_override("font_color", AZUL if host else CINZA)

		if inativo:
			indicador.add_theme_color_override("font_color", AMARELO)
			estado_label.text = "RECONECTANDO"
			estado_label.add_theme_color_override("font_color", AMARELO)
		elif pronto:
			indicador.add_theme_color_override("font_color", VERDE)
			estado_label.text = "PRONTO"
			estado_label.add_theme_color_override("font_color", VERDE)
		else:
			indicador.add_theme_color_override("font_color", AZUL)
			estado_label.text = "AGUARDANDO"
			estado_label.add_theme_color_override("font_color", CINZA)

	if _retomada_ativa():
		_atualizar_controles_retomada(avaliacao_retomada)
		return

	var total: int = jogadores.size()
	lbl_contador_jogadores.text = "%d / 6" % total

	btn_pronto.visible = true
	btn_pronto.disabled = not PhotonManager.esta_em_sala()
	btn_pronto.text = "CANCELAR PRONTO" if PhotonManager.pronto_local else "DAR PRONTO"
	btn_pronto.modulate = Color(1.0, 0.84, 0.84) if PhotonManager.pronto_local else Color.WHITE

	var pode_iniciar := (
		PhotonManager.eh_host
		and total >= 2
		and PhotonManager.todos_jogadores_prontos()
	)
	btn_iniciar_partida.visible = PhotonManager.eh_host
	btn_iniciar_partida.disabled = not pode_iniciar
	btn_iniciar_partida.text = "COMEÇAR PARTIDA" if pode_iniciar else "AGUARDANDO PRONTOS"

	lbl_papel_local.text = "VOCÊ É O HOST" if PhotonManager.eh_host else "VOCÊ É JOGADOR"
	lbl_papel_local.add_theme_color_override("font_color", AMARELO if PhotonManager.eh_host else AZUL)

	if total < 2:
		lbl_estado_prontidao.text = "AGUARDANDO +1 JOGADOR..."
		lbl_estado_prontidao.add_theme_color_override("font_color", AMARELO)
	elif PhotonManager.todos_jogadores_prontos():
		lbl_estado_prontidao.text = "TODOS ESTÃO PRONTOS"
		lbl_estado_prontidao.add_theme_color_override("font_color", VERDE)
	elif PhotonManager.eh_host:
		lbl_estado_prontidao.text = "AGUARDANDO OS JOGADORES"
		lbl_estado_prontidao.add_theme_color_override("font_color", AMARELO)
	else:
		lbl_estado_prontidao.text = "AGUARDANDO O HOST"
		lbl_estado_prontidao.add_theme_color_override("font_color", AMARELO)

	if not PhotonManager.todos_jogadores_prontos():
		lbl_dica_lobby.text = (
			"Quando todos estiverem prontos, você poderá começar."
			if PhotonManager.eh_host
			else "Marque-se como pronto e aguarde o host começar."
		)
		lbl_dica_lobby.add_theme_color_override("font_color", BRANCO)


func _retomada_ativa() -> bool:
	if _contexto_retomada.is_empty():
		return false
	var participantes_variant: Variant = _contexto_retomada.get("participantes", [])
	if not participantes_variant is Array:
		return false
	var participantes: Array = participantes_variant
	return not participantes.is_empty()


func _avaliar_participantes_retomada(jogadores: Array) -> Dictionary:
	var participantes: Array = Array(_contexto_retomada.get("participantes", []))
	var jogadores_por_usuario: Dictionary = {}
	for jogador_variant in jogadores:
		if not jogador_variant is Dictionary:
			continue
		var jogador: Dictionary = jogador_variant
		if bool(jogador.get("inativo", false)):
			continue
		var user_id: String = str(jogador.get("user_id", ""))
		if not user_id.is_empty():
			jogadores_por_usuario[user_id] = jogador

	var ids_esperados: Array[String] = []
	var linhas: Array = []
	var ausentes: Array[String] = []
	var presentes: int = 0
	for participante_variant in participantes:
		if not participante_variant is Dictionary:
			continue
		var participante: Dictionary = participante_variant
		var user_id: String = str(participante.get("user_id", ""))
		if user_id.is_empty():
			continue
		ids_esperados.append(user_id)
		if jogadores_por_usuario.has(user_id):
			var linha_presente: Dictionary = Dictionary(
				jogadores_por_usuario[user_id]
			).duplicate(true)
			linha_presente["nome_salvo"] = str(participante.get("nome", "JOGADOR"))
			linha_presente["personagem"] = str(participante.get("personagem", ""))
			linha_presente["retomada_ausente"] = false
			linha_presente["retomada_extra"] = false
			linhas.append(linha_presente)
			presentes += 1
		else:
			var linha_ausente: Dictionary = participante.duplicate(true)
			linha_ausente["id"] = 0
			linha_ausente["nome_salvo"] = str(participante.get("nome", "JOGADOR"))
			linha_ausente["retomada_ausente"] = true
			linha_ausente["retomada_extra"] = false
			linhas.append(linha_ausente)
			ausentes.append(str(participante.get("nome", "JOGADOR")))

	var extras: int = 0
	for jogador_variant in jogadores:
		if not jogador_variant is Dictionary:
			continue
		var jogador: Dictionary = jogador_variant
		if bool(jogador.get("inativo", false)):
			continue
		var user_id: String = str(jogador.get("user_id", ""))
		if ids_esperados.has(user_id):
			continue
		var linha_extra: Dictionary = jogador.duplicate(true)
		linha_extra["retomada_ausente"] = false
		linha_extra["retomada_extra"] = true
		linha_extra["personagem"] = ""
		linhas.append(linha_extra)
		extras += 1

	var user_id_local: String = PhotonManager.obter_user_id_local()
	return {
		"linhas": linhas,
		"esperados": ids_esperados.size(),
		"presentes": presentes,
		"ausentes": ausentes,
		"extras": extras,
		"local_esperado": ids_esperados.has(user_id_local),
		"todos_confirmados": (
			presentes == ids_esperados.size()
			and not ids_esperados.is_empty()
			and extras == 0
		),
	}


func _atualizar_controles_retomada(avaliacao: Dictionary) -> void:
	var esperados: int = int(avaliacao.get("esperados", 0))
	var presentes: int = int(avaliacao.get("presentes", 0))
	var extras: int = int(avaliacao.get("extras", 0))
	var todos_confirmados: bool = bool(avaliacao.get("todos_confirmados", false))
	var local_esperado: bool = bool(avaliacao.get("local_esperado", false))
	var ausentes: Array = Array(avaliacao.get("ausentes", []))

	lbl_contador_jogadores.text = "%d / %d" % [presentes, esperados]
	btn_pronto.visible = false
	btn_iniciar_partida.visible = PhotonManager.eh_host
	btn_iniciar_partida.disabled = not todos_confirmados
	btn_iniciar_partida.text = (
		"RETOMAR PARTIDA" if todos_confirmados else "AGUARDANDO O GRUPO"
	)
	lbl_papel_local.text = (
		"VOCÊ É O HOST DA RETOMADA"
		if PhotonManager.eh_host
		else "VOCÊ É PARTICIPANTE"
	)
	lbl_papel_local.add_theme_color_override(
		"font_color", AMARELO if PhotonManager.eh_host else AZUL
	)

	if not local_esperado:
		lbl_estado_prontidao.text = "ESTA CONTA NÃO PARTICIPAVA DA PARTIDA"
		lbl_estado_prontidao.add_theme_color_override("font_color", VERMELHO)
	elif extras > 0:
		lbl_estado_prontidao.text = "HÁ UM JOGADOR NÃO CONVIDADO NA SALA"
		lbl_estado_prontidao.add_theme_color_override("font_color", VERMELHO)
	elif todos_confirmados:
		lbl_estado_prontidao.text = "GRUPO ORIGINAL CONFIRMADO"
		lbl_estado_prontidao.add_theme_color_override("font_color", VERDE)
	else:
		lbl_estado_prontidao.text = "AGUARDANDO %d PARTICIPANTE(S)" % (esperados - presentes)
		lbl_estado_prontidao.add_theme_color_override("font_color", AMARELO)

	var codigo: String = str(_contexto_retomada.get("codigo_sala", ""))
	if not ausentes.is_empty():
		lbl_dica_lobby.text = "Envie o código %s para: %s" % [
			codigo,
			", ".join(PackedStringArray(ausentes)),
		]
	elif todos_confirmados:
		lbl_dica_lobby.text = (
			"Todos voltaram. O host já pode carregar a rodada %d."
			% int(_contexto_retomada.get("rodada", 1))
		)
	else:
		lbl_dica_lobby.text = "Aguardando a validação dos participantes salvos."
	lbl_dica_lobby.add_theme_color_override(
		"font_color", VERDE if todos_confirmados else BRANCO
	)


func _iniciar_selecao_online() -> void:
	if not PhotonManager.eh_host:
		return
	if _retomada_ativa():
		_iniciar_retomada_online()
		return
	if PhotonManager.total_jogadores_sala() < 2:
		lbl_dica_lobby.text = "São necessários pelo menos dois jogadores."
		lbl_dica_lobby.add_theme_color_override("font_color", VERMELHO)
		return
	if not PhotonManager.todos_jogadores_prontos():
		lbl_dica_lobby.text = "Todos os jogadores precisam marcar PRONTO."
		lbl_dica_lobby.add_theme_color_override("font_color", VERMELHO)
		return

	btn_iniciar_partida.disabled = true
	Global.escolhas_da_mesa.clear()
	Global.user_ids_da_mesa.clear()
	Global.escolhas_por_user_id.clear()
	Global.modo_online = true
	Global.meu_peer_id = PhotonManager.jogador_local_id
	OnlineTransport.definir_fase_online("selecao", OnlineTransport.CENA_SELECAO)
	OnlineTransport.mudar_cena_para_todos(OnlineTransport.CENA_SELECAO, true)


func _iniciar_retomada_online() -> void:
	if not PhotonManager.eh_host or not _retomada_ativa() or _ocupado:
		return
	var preparacao: Dictionary = GerenciadorSalvamento.preparar_snapshot_retomada(
		PhotonManager.obter_jogadores_sala()
	)
	if not bool(preparacao.get("sucesso", false)):
		lbl_dica_lobby.text = str(
			preparacao.get("mensagem", "Não foi possível preparar o snapshot salvo.")
		)
		lbl_dica_lobby.add_theme_color_override("font_color", VERMELHO)
		return

	var escolhas: Dictionary = Dictionary(
		preparacao.get("escolhas_da_mesa", {})
	)
	var usuarios: Dictionary = Dictionary(
		preparacao.get("user_ids_da_mesa", {})
	)
	var escolhas_usuario: Dictionary = Dictionary(
		preparacao.get("escolhas_por_user_id", {})
	)
	_ocupado = true
	btn_iniciar_partida.disabled = true
	btn_iniciar_partida.text = "CARREGANDO..."
	var iniciou: bool = OnlineTransport.iniciar_tabuleiro_retomado(
		escolhas,
		usuarios,
		escolhas_usuario
	)
	if not iniciou:
		_ocupado = false
		btn_iniciar_partida.disabled = false
		btn_iniciar_partida.text = "RETOMAR PARTIDA"
		lbl_dica_lobby.text = "Não foi possível abrir o tabuleiro salvo."
		lbl_dica_lobby.add_theme_color_override("font_color", VERMELHO)


func _alternar_pronto() -> void:
	if _retomada_ativa():
		return
	PhotonManager.alternar_pronto_local()


func _sair_sala() -> void:
	if _ocupado:
		return
	if GerenciadorSalvamento.retomada_em_preparacao():
		GerenciadorSalvamento.cancelar_preparacao_retomada()
	_retomada_solicitada = false
	_contexto_retomada.clear()
	PhotonManager.sair_sala()


func _ao_pronto_local_alterado(_pronto: bool) -> void:
	_atualizar_lista_jogadores(PhotonManager.obter_jogadores_sala())


func _ao_host_alterado(_host: bool) -> void:
	_atualizar_estado(PhotonManager.obter_resumo())
	_atualizar_lista_jogadores(PhotonManager.obter_jogadores_sala())


func _ao_erro(_mensagem: String) -> void:
	if _retomada_solicitada and not PhotonManager.esta_em_sala():
		_retomada_solicitada = false
		_contexto_retomada.clear()
		GerenciadorSalvamento.cancelar_preparacao_retomada()
	_atualizar_estado(PhotonManager.obter_resumo())


func _voltar_menu() -> void:
	if _ocupado:
		return
	if PhotonManager.esta_em_sala():
		_sair_sala()
		return
	if PhotonManager.esta_conectado():
		PhotonManager.desconectar()
	if GerenciadorSalvamento.retomada_em_preparacao():
		GerenciadorSalvamento.cancelar_preparacao_retomada()
	_retomada_solicitada = false
	_contexto_retomada.clear()

	_ocupado = true
	btn_voltar.disabled = true
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.22)
	tween.tween_property(self, "position:y", 14.0, 0.22)
	await tween.finished

	var erro := get_tree().change_scene_to_file("res://scenes/ui/tela_inicial/menu_principal.tscn")
	if erro != OK:
		push_error("Não foi possível voltar ao menu principal. Código: %s" % erro)
		_ocupado = false
		btn_voltar.disabled = false
