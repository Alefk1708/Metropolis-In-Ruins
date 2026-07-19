extends Node

signal avancar_solicitado
signal evento_recebido(tipo: String)

const CENA_MENU_PRINCIPAL: String = "res://scenes/ui/tela_inicial/menu_principal.tscn"
const CAMINHO_FONTE_PIXEL: String = "res://assets/fonts/m5x7.ttf"
const TOTAL_BLOCOS: int = 32
const INTERVALO_LETRA: float = 0.023
const JANELA_ANTI_DUPLICACAO_MS: int = 140
const TAMANHO_FONTE_TITULO: int = 36
const TAMANHO_FONTE_TEXTO: int = 34
const TAMANHO_FONTE_DICA: int = 22
const TAMANHO_FONTE_PROGRESSO: int = 22
const TAMANHO_FONTE_SAIR: int = 24

var _tabuleiro: Node = null
var _hud: CanvasLayer = null
var _camada_interface: CanvasLayer = null
var _raiz_interface: Control = null
var _mascaras: Array[ColorRect] = []
var _moldura_destaque: Panel = null
var _painel_fala: PanelContainer = null
var _titulo: Label = null
var _texto: RichTextLabel = null
var _dica: Label = null
var _progresso: Label = null
var _btn_sair: Button = null
var _transicao: ColorRect = null
var _painel_desafio: PanelContainer = null
var _label_desafio: Label = null
var _fonte_pixel: Font = null

var _alvo_atual: Control = null
var _alvo_tile_atual: int = -1
var _retangulo_alvo: Rect2 = Rect2()
var _digitando: bool = false
var _pular_digitacao: bool = false
var _bloco_concluido: bool = false
var _acao_esperada: String = ""
var _eventos_ocorridos: Dictionary = {}
var _passo_atual: int = 0
var _ultimo_clique_ms: int = -1000
var _ia_ja_jogou: bool = false
var _saindo: bool = false


func _enter_tree() -> void:
	Global.configurar_partida_tutorial()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tabuleiro = get_node_or_null("Tabuleiro")
	if _tabuleiro == null:
		push_error("[TUTORIAL] A cena do Tabuleiro não foi encontrada.")
		call_deferred("_sair_do_tutorial")
		return

	if _tabuleiro.has_signal("evento_tutorial"):
		_tabuleiro.connect("evento_tutorial", Callable(self, "_on_evento_tutorial"))
	if _tabuleiro.has_method("definir_bots_pausados"):
		_tabuleiro.call("definir_bots_pausados", true)
	_hud = _tabuleiro.get("hud") as CanvasLayer
	_criar_interface()
	call_deferred("_executar_fluxo")


func _exit_tree() -> void:
	get_tree().paused = false
	if Global.modo_tutorial:
		Global.limpar_partida_tutorial()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and not _saindo:
		call_deferred("_sair_do_tutorial")


func _process(_delta: float) -> void:
	if _raiz_interface == null or not _raiz_interface.visible:
		return
	_atualizar_destaque()


func _input(event: InputEvent) -> void:
	if _saindo:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_sair_do_tutorial()
		return
	# Nas etapas jogáveis o painel principal é ocultado. Nesse estado, o HUD
	# precisa receber os toques normalmente; apenas o botão Voltar continua
	# sendo tratado pelo controlador do tutorial.
	if _raiz_interface == null or not _raiz_interface.visible:
		return

	var clique: bool = false
	var posicao: Vector2 = Vector2(-1.0, -1.0)
	if event is InputEventScreenTouch:
		var toque: InputEventScreenTouch = event
		clique = toque.pressed
		posicao = toque.position
	elif event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event
		clique = mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT
		posicao = mouse.position
	elif event.is_action_pressed("ui_accept"):
		clique = true
	if not clique:
		return

	var agora_ms: int = Time.get_ticks_msec()
	if agora_ms - _ultimo_clique_ms < JANELA_ANTI_DUPLICACAO_MS:
		get_viewport().set_input_as_handled()
		return
	_ultimo_clique_ms = agora_ms

	if (
		_btn_sair != null
		and _btn_sair.is_visible_in_tree()
		and _btn_sair.get_global_rect().has_point(posicao)
	):
		get_viewport().set_input_as_handled()
		_sair_do_tutorial()
		return

	if _digitando:
		_pular_digitacao = true
		get_viewport().set_input_as_handled()
		return
	if not _bloco_concluido:
		get_viewport().set_input_as_handled()
		return

	if not _acao_esperada.is_empty():
		if (
			_alvo_atual != null
			and _alvo_atual.get_global_rect().has_point(posicao)
		):
			# A camada do tutorial fica acima do HUD e pode interceptar o toque,
			# principalmente em telas baixas nas quais o painel cruza o destaque.
			# Aciona o botão real de forma controlada e consome o evento para evitar
			# que o toque emulado do celular execute a ação duas vezes.
			if _acionar_controle_destacado():
				get_viewport().set_input_as_handled()
				return
			_pulsar_moldura()
			get_viewport().set_input_as_handled()
			return
		_pulsar_moldura()
		get_viewport().set_input_as_handled()
		return

	_bloco_concluido = false
	avancar_solicitado.emit()
	get_viewport().set_input_as_handled()


func _executar_fluxo() -> void:
	await _aguardar_evento("tabuleiro_pronto")
	if _saindo:
		return
	_hud = _tabuleiro.get("hud") as CanvasLayer
	if _tabuleiro.has_method("preparar_cenario_tutorial_expandido"):
		_tabuleiro.call("preparar_cenario_tutorial_expandido")
	_mostrar_interface(true)

	await _fase_abertura_e_compra()
	if _saindo:
		return
	await _fase_tiles_e_turno_da_ia()
	if _saindo:
		return
	await _fase_negociacao_guiada()
	if _saindo:
		return
	await _fase_construcao_guiada()
	if _saindo:
		return
	await _fase_partida_rapida()
	if not _saindo:
		_sair_do_tutorial()


func _fase_abertura_e_compra() -> void:
	await _falar(
		"BEM-VINDO À METRÓPOLE",
		"Você joga como Yasmin contra Igor, controlado pela IA. Esta aula usa as regras reais em uma partida curta. Durante uma fala, toque uma vez para revelar todo o texto; toque novamente para continuar.",
		null
	)
	await _falar(
		"SEU PAINEL",
		"Aqui ficam seu dinheiro, suas propriedades e sua reputação. Toda mudança de saldo aparece com animação, então você consegue acompanhar pagamentos e ganhos.",
		_alvo_hud("Control/CantoSupEsq_Jogador")
	)
	await _falar(
		"EVENTO GLOBAL",
		"O evento ativo altera as regras da cidade por uma rodada. Leia este painel antes de decidir comprar, construir ou negociar.",
		_alvo_hud("Control/CentroSup_Evento")
	)
	await _falar(
		"DETALHES DO EVENTO",
		"Este botão abre a descrição completa do evento e mostra exatamente quais efeitos estão valendo.",
		_alvo_hud("Control/CentroSup_Evento/BotaoEvento")
	)
	await _falar(
		"SEU TURNO",
		"Toque em GIRAR DADOS. O pino avançará pela soma dos dois resultados. Duplas permitem jogar novamente, mas três duplas seguidas levam à prisão.",
		_alvo_hud("Control/Centro_Dados/BotaoGirar"),
		"dados_rolados"
	)
	await _falar(
		"MOVIMENTO",
		"O pino se move sozinho e a câmera acompanha o trajeto. Ao parar, o terreno, uma carta ou uma casa especial será resolvido automaticamente.",
		null
	)
	await _aguardar_evento("compra_disponivel")
	await _falar(
		"TERRENO LIVRE",
		"Você caiu em uma propriedade sem dono. O painel mostra o nome, o preço e as duas decisões possíveis.",
		_alvo_hud("Control/Centro_AcaoTerreno")
	)
	await _falar(
		"COMPRAR",
		"Comprar desconta o preço do seu saldo e registra o terreno como seu. Depois, adversários que pararem nele pagarão aluguel.",
		_alvo_hud("Control/Centro_AcaoTerreno/Panel/VBox/HBoxBotoes/BtnComprar")
	)
	await _falar(
		"LEILÃO",
		"Se você não comprar, a propriedade vai a leilão. Todos podem disputar, e o maior lance válido vence.",
		_alvo_hud("Control/Centro_AcaoTerreno/Panel/VBox/HBoxBotoes/BtnLeilao")
	)
	await _falar(
		"SUA PRIMEIRA COMPRA",
		"Agora toque no botão COMPRAR destacado para adquirir este terreno.",
		_alvo_hud("Control/Centro_AcaoTerreno/Panel/VBox/HBoxBotoes/BtnComprar"),
		"propriedade_comprada"
	)
	await _falar(
		"INFORMAÇÕES DO TERRENO",
		"Este painel acompanha a casa atual: dono, aluguel, grupo, nível de construção e situações como hipoteca ou interdição.",
		_alvo_hud("Control/CantoSupDir_Propriedade/VBoxArea/Panel")
	)


func _fase_tiles_e_turno_da_ia() -> void:
	await _falar_tile(
		"PROPRIEDADES E GRUPOS",
		"Vila Operária pertence ao grupo Cinza. Terrenos da mesma cor formam um conjunto: possuir todos ativa o monopólio, aumenta o aluguel base e libera construções.",
		3
	)
	await _falar_tile(
		"CARTAS DA CIDADE",
		"Destino da Cidade e Ordem Urbana compram cartas com efeitos positivos, cobranças, deslocamentos ou sabotagens. Algumas resolvem na hora; outras ficam guardadas para o momento certo.",
		2
	)
	await _falar_tile(
		"TRANSPORTE E UTILIDADES",
		"Linhas de Metrô aumentam o aluguel conforme o dono reúne mais linhas. ENEM e SAEM usam os dados para calcular a cobrança e também podem ser alteradas por eventos globais.",
		5
	)
	await _falar_tile(
		"PORTAIS E ATALHOS",
		"Os portais Norte e Sul teleportam o pino entre os dois pontos sem percorrer as casas intermediárias. Certos efeitos podem bloquear temporariamente esses atalhos.",
		12
	)
	await _falar_tile(
		"CASAS ESPECIAIS",
		"Partida paga bônus ao completar uma volta; impostos cobram; Bônus Produtivo recompensa; Prisão e Vá para a Prisão alteram o movimento; Parque Livre não cobra. Zona de Obras, Acordo de Silêncio e Colapso Estrutural aplicam riscos próprios — Breno é imune ao silêncio.",
		17
	)
	await _falar(
		"VEZ DA IA",
		"Agora observe Igor jogar. A IA usa saldo, reserva de segurança e tipo de terreno para decidir se compra. Ela também avaliará a proposta que você fará em seguida.",
		null
	)

	_mostrar_interface(false)
	if _tabuleiro.has_method("definir_bots_pausados"):
		_tabuleiro.call("definir_bots_pausados", false)
	while (
		not _saindo
		and str(_tabuleiro.get("jogador_atual_id")) != "yasmin"
	):
		await evento_recebido
	if _tabuleiro.has_method("definir_bots_pausados"):
		_tabuleiro.call("definir_bots_pausados", true)
	_mostrar_interface(not _saindo)


func _fase_negociacao_guiada() -> void:
	await _falar(
		"NEGOCIAR COM A IA",
		"Toque em NEGOCIAR. Vamos oferecer $100 pela Periferia Norte de Igor. Se o valor recebido compensar o que entrega, a IA aceita; caso contrário, recusa.",
		_alvo_hud("Control/CantoDir_Construcao/VBox/HBoxBotoesInferior/BotaoNegociar"),
		"ui:negociacao_aberta"
	)
	await _aguardar_frames(2)
	await get_tree().create_timer(0.30, true, false, true).timeout

	var painel_negociacao: Node = _hud.get_node_or_null("PainelNegociacao")
	var proposta_preparada: bool = false
	if (
		painel_negociacao != null
		and painel_negociacao.has_method("preparar_proposta_tutorial")
	):
		proposta_preparada = bool(
			painel_negociacao.call(
				"preparar_proposta_tutorial",
				"igor",
				100,
				[1]
			)
		)
	if not proposta_preparada:
		push_error("[TUTORIAL] Não foi possível preparar a proposta guiada.")

	await _falar(
		"O QUE VOCÊ OFERECE",
		"A coluna verde reúne tudo que sai do seu patrimônio: dinheiro, propriedades, visitas sem aluguel e passes de transporte. Nesta proposta, você oferece $100.",
		_alvo_hud("PainelNegociacao/Centro/PainelPrincipal/VBoxRaiz/HBoxColunas/ColunaOferece")
	)
	await _falar(
		"O QUE VOCÊ PEDE",
		"A coluna laranja mostra o que você receberá. A Periferia Norte já está marcada. Sempre confira dono, nível, hipoteca e o resumo antes de enviar.",
		_alvo_hud("PainelNegociacao/Centro/PainelPrincipal/VBoxRaiz/HBoxColunas/ColunaPede")
	)
	await _falar(
		"ENVIAR A PROPOSTA",
		"Toque em ENVIAR PROPOSTA. Igor vai comparar o valor dos dois pacotes e responder após uma breve análise.",
		_alvo_hud("PainelNegociacao/Centro/PainelPrincipal/VBoxRaiz/HBoxBotoes/BtnAcao"),
		"negociacao_concluida"
	)
	await get_tree().create_timer(0.85, true, false, true).timeout
	await _falar_tile(
		"MONOPÓLIO COMPLETO",
		"A troca entregou a Periferia Norte a Yasmin. Como você já possui Vila Operária, agora controla todo o grupo Cinza e pode construir em suas propriedades.",
		3
	)


func _fase_construcao_guiada() -> void:
	await _falar(
		"GESTÃO DE PROPRIEDADES",
		"Toque em GESTÃO DE PROPRIEDADES. O painel reúne construir, hipotecar e resgatar para cada imóvel seu, além de mostrar custo, aluguel e nível atual.",
		_alvo_hud("Control/CantoDir_Construcao/VBox/HBoxBotoesInferior/BotaoAbrirConstrucao"),
		"ui:gestao_aberta"
	)
	var botao_construir: Button = await _aguardar_botao_construir(3)
	if botao_construir != null:
		await _falar(
			"CONSTRUIR O PRIMEIRO NÍVEL",
			"Toque em CONSTRUIR. A obra só é permitida porque o grupo está completo, o imóvel não está hipotecado, não há bloqueio ativo e você possui dinheiro suficiente.",
			botao_construir,
			"construcao_realizada"
		)
	else:
		push_error("[TUTORIAL] O botão de construção guiada não foi encontrado.")
		await _falar(
			"CONSTRUIR O PRIMEIRO NÍVEL",
			"Em uma partida normal, selecione CONSTRUIR no cartão da propriedade. O custo é descontado e o aluguel aumenta a cada nível.",
			_alvo_hud("Control/CantoDir_Construcao/VBox/PainelComBotao")
		)
		if _tabuleiro.has_method("definir_nivel_construcao_tutorial"):
			_tabuleiro.call("definir_nivel_construcao_tutorial", 3, 1)

	_fechar_gestao_propriedades()
	await get_tree().create_timer(0.30, true, false, true).timeout
	await _falar_tile(
		"NÍVEIS DE CONSTRUÇÃO",
		"Cada nova obra deve ser comprada separadamente e eleva o prédio do nível 1 ao 4. O custo aparece no painel e o aluguel cresce conforme a tabela do terreno. Agora veja uma prévia acelerada dos próximos níveis.",
		3
	)

	_mostrar_interface(false)
	_mostrar_desafio("DEMONSTRAÇÃO: PRÉDIO NÍVEL 2")
	for nivel: int in range(2, 6):
		var nome_nivel: String = (
			"HOTEL — NÍVEL 5"
			if nivel == 5
			else "PRÉDIO NÍVEL %d" % nivel
		)
		_atualizar_texto_desafio("DEMONSTRAÇÃO: " + nome_nivel)
		if _tabuleiro.has_method("definir_nivel_construcao_tutorial"):
			_tabuleiro.call("definir_nivel_construcao_tutorial", 3, nivel)
		await get_tree().create_timer(0.72, true, false, true).timeout
	_ocultar_desafio()
	_mostrar_interface(true)
	await _falar_tile(
		"HOTEL PRONTO",
		"O nível 5 representa o hotel e oferece o aluguel máximo do terreno. A prévia acelerou os níveis 2 a 5 apenas para demonstração; em uma partida normal, cada etapa exige uma nova construção válida.",
		3
	)


func _fase_partida_rapida() -> void:
	await _falar(
		"HABILIDADE",
		"Cada personagem possui um poder exclusivo. Yasmin usa Oferta Irrecusável. Depois do uso, acompanhe aqui os turnos de recarga.",
		_alvo_hud("Control/CantoInfEsq_Habilidade/Panel/HBox/BotaoHab")
	)
	await _falar(
		"RELATÓRIO DE MERCADO",
		"O relatório exclusivo de Yasmin calcula as regiões com maior chance de receber visitas nos próximos movimentos. Use a previsão para priorizar compras e construções.",
		_alvo_hud("Control/RelatorioYasmin/VBox/BotaoAbrirRelatorio")
	)
	await _falar(
		"CARTAS GUARDADAS",
		"Cartas que podem ser mantidas aparecem aqui. Algumas são usadas automaticamente quando a condição correta acontece; outras protegem uma decisão futura.",
		_alvo_hud("Control/CantoSupDir_Propriedade/VBoxArea/BtnCartasGuardadas")
	)
	await _falar(
		"PROMESSAS E REPUTAÇÃO",
		"Promessas ficam registradas publicamente. Cumprir ou quebrar um acordo afeta sua reputação, informação importante antes de aceitar negociações futuras.",
		_alvo_hud("Control/BtnTogglePromessas")
	)
	await _falar(
		"PARTIDA RÁPIDA",
		"Agora jogue duas rodadas contra Igor sem o painel de instrução. Você passará por uma casa de bônus e por um portal; a IA continuará comprando conforme sua estratégia. Use GIRAR DADOS quando for sua vez.",
		_alvo_hud("Control/RoundCounter")
	)

	var rodada_inicio_desafio: int = int(_tabuleiro.get("rodada_atual"))
	_mostrar_interface(false)
	_mostrar_desafio("PARTIDA RÁPIDA — SUA VEZ: GIRE OS DADOS")
	if _tabuleiro.has_method("definir_bots_pausados"):
		_tabuleiro.call("definir_bots_pausados", false)
	while not _saindo:
		var rodada_atual_desafio: int = int(_tabuleiro.get("rodada_atual"))
		var jogador_atual_desafio: String = str(
			_tabuleiro.get("jogador_atual_id")
		)
		if (
			rodada_atual_desafio >= rodada_inicio_desafio + 2
			and jogador_atual_desafio == "yasmin"
		):
			break
		await evento_recebido
	if _saindo:
		return
	if _tabuleiro.has_method("definir_bots_pausados"):
		_tabuleiro.call("definir_bots_pausados", true)
	_ocultar_desafio()
	_mostrar_interface(true)

	var resultado: Dictionary = {}
	if _tabuleiro.has_method("obter_resultado_tutorial_rapido"):
		var resultado_variant: Variant = _tabuleiro.call(
			"obter_resultado_tutorial_rapido"
		)
		if resultado_variant is Dictionary:
			resultado = resultado_variant
	var vencedor_id: String = str(resultado.get("vencedor_id", "yasmin"))
	var nome_vencedor: String = "VOCÊ" if vencedor_id == "yasmin" else "IGOR"
	var patrimonio_yasmin: int = int(resultado.get("patrimonio_yasmin", 0))
	var patrimonio_igor: int = int(resultado.get("patrimonio_igor", 0))
	await _falar(
		"TUTORIAL CONCLUÍDO",
		"Fim da partida rápida. Patrimônio de Yasmin: $%d. Patrimônio de Igor: $%d. Vencedor desta demonstração: %s. Você praticou compra, negociação, monopólio, construção, casas especiais e decisões contra a IA. Toque para voltar à tela inicial." % [
			patrimonio_yasmin,
			patrimonio_igor,
			nome_vencedor,
		],
		null
	)


func _falar_tile(titulo_fala: String, texto_fala: String, casa_id: int) -> void:
	if _saindo:
		return
	_mostrar_interface(false)
	if _tabuleiro.has_method("focar_na_casa"):
		_tabuleiro.call("focar_na_casa", casa_id)
	await get_tree().create_timer(0.88, true, false, true).timeout
	if _saindo:
		return
	_alvo_tile_atual = casa_id
	_mostrar_interface(true)
	await _falar(titulo_fala, texto_fala, null)
	_alvo_tile_atual = -1


func _aguardar_frames(quantidade: int) -> void:
	for _indice: int in range(maxi(0, quantidade)):
		await get_tree().process_frame


func _aguardar_botao_construir(casa_id: int) -> Button:
	for _tentativa: int in range(16):
		await get_tree().process_frame
		if _hud != null and _hud.has_method("obter_botao_construir"):
			var botao_variant: Variant = _hud.call(
				"obter_botao_construir",
				casa_id
			)
			if botao_variant is Button:
				var botao: Button = botao_variant as Button
				if not botao.disabled and botao.is_visible_in_tree():
					return botao
		await get_tree().create_timer(0.08, true, false, true).timeout
	return null


func _fechar_gestao_propriedades() -> void:
	if _hud == null or not is_instance_valid(_hud):
		return
	var aberta_variant: Variant = _hud.get("construcao_aberta")
	if not bool(aberta_variant):
		return
	var botao: BaseButton = _alvo_hud(
		"Control/CantoDir_Construcao/VBox/HBoxBotoesInferior/BotaoAbrirConstrucao"
	) as BaseButton
	if botao != null and not botao.disabled:
		botao.pressed.emit()


func _registrar_evento_local(tipo: String, dados: Dictionary = {}) -> void:
	if tipo.is_empty() or _saindo:
		return
	_eventos_ocorridos[tipo] = dados.duplicate(true)
	evento_recebido.emit(tipo)


func _mostrar_desafio(texto_objetivo: String) -> void:
	if _painel_desafio == null:
		return
	_atualizar_texto_desafio(texto_objetivo)
	_painel_desafio.visible = true
	_painel_desafio.modulate.a = 0.0
	_painel_desafio.scale = Vector2(0.94, 0.94)
	_painel_desafio.pivot_offset = _painel_desafio.size * 0.5
	var tween: Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.tween_property(_painel_desafio, "modulate:a", 1.0, 0.20)
	(
		tween
		. tween_property(_painel_desafio, "scale", Vector2.ONE, 0.28)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)


func _atualizar_texto_desafio(texto_objetivo: String) -> void:
	if _label_desafio != null:
		_label_desafio.text = texto_objetivo


func _ocultar_desafio() -> void:
	if _painel_desafio != null:
		_painel_desafio.visible = false


func _falar(
	titulo_fala: String,
	texto_fala: String,
	alvo: Control,
	evento_acao: String = ""
) -> void:
	if _saindo:
		return
	_passo_atual += 1
	_alvo_atual = alvo if alvo != null and alvo.is_visible_in_tree() else null
	_acao_esperada = evento_acao
	_bloco_concluido = false
	_pular_digitacao = false
	if not evento_acao.is_empty():
		_eventos_ocorridos.erase(evento_acao)

	_titulo.text = titulo_fala
	_progresso.text = "PASSO %02d/%02d" % [_passo_atual, TOTAL_BLOCOS]
	_texto.text = texto_fala
	_texto.visible_characters = 0
	_dica.text = ""
	_atualizar_layout_interface()
	await _animar_entrada_painel()
	await _digitar_texto(texto_fala)
	if _saindo:
		return
	_bloco_concluido = true
	if evento_acao.is_empty():
		_dica.text = "TOQUE PARA CONTINUAR"
		await avancar_solicitado
	else:
		_dica.text = "TOQUE NO CONTROLE DESTACADO"
		while not _saindo and not _eventos_ocorridos.has(evento_acao):
			await evento_recebido
	_acao_esperada = ""
	_bloco_concluido = false


func _digitar_texto(texto_fala: String) -> void:
	_digitando = true
	_pular_digitacao = false
	var total: int = texto_fala.length()
	var indice: int = 0
	while indice < total and not _saindo:
		if _pular_digitacao:
			_texto.visible_characters = -1
			break
		indice += 1
		_texto.visible_characters = indice
		var caractere: String = texto_fala.substr(indice - 1, 1)
		var intervalo: float = INTERVALO_LETRA
		if caractere in [".", "!", "?", ":", ";"]:
			intervalo = 0.07
		await get_tree().create_timer(intervalo, true, false, true).timeout
	_texto.visible_characters = -1
	_digitando = false


func _aguardar_evento(tipo: String) -> Dictionary:
	while not _saindo and not _eventos_ocorridos.has(tipo):
		await evento_recebido
	if _saindo:
		return {}
	var dados_variant: Variant = _eventos_ocorridos.get(tipo, {})
	if dados_variant is Dictionary:
		return Dictionary(dados_variant).duplicate(true)
	return {}


func _on_evento_tutorial(tipo: String, dados: Dictionary) -> void:
	_eventos_ocorridos[tipo] = dados.duplicate(true)
	if tipo == "turno_iniciado" and str(dados.get("jogador_id", "")) == "igor":
		_ia_ja_jogou = true
	if _painel_desafio != null and _painel_desafio.visible:
		if tipo == "turno_iniciado":
			var jogador_id: String = str(dados.get("jogador_id", ""))
			var rodada: int = int(dados.get("rodada", 0))
			if jogador_id == "yasmin":
				_atualizar_texto_desafio(
					"PARTIDA RÁPIDA — RODADA %d — SUA VEZ: GIRE OS DADOS" % rodada
				)
			elif jogador_id == "igor":
				_atualizar_texto_desafio(
					"PARTIDA RÁPIDA — RODADA %d — IGOR ESTÁ JOGANDO" % rodada
				)
		elif tipo == "dados_rolados":
			var soma: int = int(dados.get("dado1", 0)) + int(
				dados.get("dado2", 0)
			)
			_atualizar_texto_desafio(
				"PARTIDA RÁPIDA — RESULTADO %d — AGUARDE O MOVIMENTO" % soma
			)
	evento_recebido.emit(tipo)


func _alvo_hud(caminho: String) -> Control:
	if _hud == null or not is_instance_valid(_hud):
		return null
	return _hud.get_node_or_null(caminho) as Control


func _criar_interface() -> void:
	_fonte_pixel = load(CAMINHO_FONTE_PIXEL) as Font
	_camada_interface = CanvasLayer.new()
	_camada_interface.name = "CamadaTutorial"
	_camada_interface.layer = 2200
	_camada_interface.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_camada_interface)

	_raiz_interface = Control.new()
	_raiz_interface.name = "InterfaceTutorial"
	_raiz_interface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_raiz_interface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_camada_interface.add_child(_raiz_interface)

	for indice: int in range(4):
		var mascara: ColorRect = ColorRect.new()
		mascara.name = "Mascara%d" % indice
		mascara.color = Color(0.005, 0.008, 0.016, 0.78)
		mascara.mouse_filter = Control.MOUSE_FILTER_STOP
		_raiz_interface.add_child(mascara)
		_mascaras.append(mascara)

	_moldura_destaque = Panel.new()
	_moldura_destaque.name = "MolduraDestaque"
	_moldura_destaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_moldura_destaque.add_theme_stylebox_override(
		"panel",
		_criar_estilo_moldura()
	)
	_raiz_interface.add_child(_moldura_destaque)

	_painel_fala = PanelContainer.new()
	_painel_fala.name = "PainelFala"
	_painel_fala.mouse_filter = Control.MOUSE_FILTER_STOP
	_painel_fala.add_theme_stylebox_override(
		"panel",
		_criar_estilo_painel()
	)
	_raiz_interface.add_child(_painel_fala)

	var margem: MarginContainer = MarginContainer.new()
	margem.add_theme_constant_override("margin_left", 34)
	margem.add_theme_constant_override("margin_top", 24)
	margem.add_theme_constant_override("margin_right", 34)
	margem.add_theme_constant_override("margin_bottom", 22)
	_painel_fala.add_child(margem)

	var conteudo: VBoxContainer = VBoxContainer.new()
	conteudo.add_theme_constant_override("separation", 10)
	margem.add_child(conteudo)

	var cabecalho: HBoxContainer = HBoxContainer.new()
	conteudo.add_child(cabecalho)
	_titulo = Label.new()
	_titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_titulo.add_theme_color_override("font_color", Color(1.0, 0.84, 0.36))
	_titulo.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_titulo.add_theme_constant_override("outline_size", 5)
	_aplicar_fonte(_titulo, TAMANHO_FONTE_TITULO)
	cabecalho.add_child(_titulo)

	_progresso = Label.new()
	_progresso.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_progresso.add_theme_color_override("font_color", Color(0.56, 0.68, 0.78))
	_aplicar_fonte(_progresso, TAMANHO_FONTE_PROGRESSO)
	cabecalho.add_child(_progresso)

	var separador: ColorRect = ColorRect.new()
	separador.custom_minimum_size = Vector2(0.0, 4.0)
	separador.color = Color(0.72, 0.49, 0.18)
	separador.mouse_filter = Control.MOUSE_FILTER_IGNORE
	conteudo.add_child(separador)

	_texto = RichTextLabel.new()
	_texto.custom_minimum_size = Vector2(0.0, 170.0)
	_texto.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_texto.bbcode_enabled = false
	_texto.scroll_active = false
	_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_texto.add_theme_color_override("default_color", Color(0.92, 0.94, 0.96))
	_texto.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	_texto.add_theme_constant_override("outline_size", 3)
	_texto.add_theme_constant_override("line_separation", 6)
	_aplicar_fonte(_texto, TAMANHO_FONTE_TEXTO)
	conteudo.add_child(_texto)

	_dica = Label.new()
	_dica.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dica.add_theme_color_override("font_color", Color(0.48, 0.92, 0.72))
	_dica.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_dica.add_theme_constant_override("outline_size", 3)
	_aplicar_fonte(_dica, TAMANHO_FONTE_DICA)
	conteudo.add_child(_dica)

	_btn_sair = Button.new()
	_btn_sair.name = "BtnSairTutorial"
	_btn_sair.text = "SAIR"
	_btn_sair.custom_minimum_size = Vector2(132.0, 54.0)
	_btn_sair.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_btn_sair.position = Vector2(-156.0, 22.0)
	_btn_sair.add_theme_color_override("font_color", Color(1.0, 0.68, 0.62))
	_btn_sair.add_theme_color_override("font_hover_color", Color.WHITE)
	_aplicar_fonte(_btn_sair, TAMANHO_FONTE_SAIR)
	_aplicar_estilos_botao(_btn_sair)
	_btn_sair.pressed.connect(_sair_do_tutorial)
	_raiz_interface.add_child(_btn_sair)

	_transicao = ColorRect.new()
	_transicao.name = "TransicaoSaida"
	_transicao.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_transicao.color = Color(0.004, 0.005, 0.019, 0.0)
	_transicao.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transicao.visible = false
	_raiz_interface.add_child(_transicao)

	# Objetivo compacto usado enquanto o painel principal fica oculto e o aluno
	# joga livremente. Ele pertence diretamente ao CanvasLayer para continuar
	# visível durante a demonstração dos prédios e a partida rápida.
	_painel_desafio = PanelContainer.new()
	_painel_desafio.name = "PainelObjetivoTutorial"
	_painel_desafio.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var estilo_desafio: StyleBoxFlat = _criar_estilo_painel()
	estilo_desafio.bg_color = Color(0.02, 0.035, 0.05, 0.96)
	estilo_desafio.border_color = Color(0.42, 0.92, 0.70)
	estilo_desafio.shadow_size = 8
	_painel_desafio.add_theme_stylebox_override("panel", estilo_desafio)
	_camada_interface.add_child(_painel_desafio)

	var margem_desafio: MarginContainer = MarginContainer.new()
	margem_desafio.add_theme_constant_override("margin_left", 24)
	margem_desafio.add_theme_constant_override("margin_top", 14)
	margem_desafio.add_theme_constant_override("margin_right", 24)
	margem_desafio.add_theme_constant_override("margin_bottom", 14)
	_painel_desafio.add_child(margem_desafio)
	_label_desafio = Label.new()
	_label_desafio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_desafio.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label_desafio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label_desafio.add_theme_color_override("font_color", Color(0.60, 1.0, 0.80))
	_label_desafio.add_theme_color_override("font_outline_color", Color.BLACK)
	_label_desafio.add_theme_constant_override("outline_size", 3)
	_aplicar_fonte(_label_desafio, 24)
	margem_desafio.add_child(_label_desafio)
	_painel_desafio.visible = false

	get_viewport().size_changed.connect(_atualizar_layout_interface)
	_mostrar_interface(false)
	_atualizar_layout_interface()


func _mostrar_interface(mostrar: bool) -> void:
	if _raiz_interface != null:
		_raiz_interface.visible = mostrar


func _atualizar_layout_interface() -> void:
	if _painel_fala == null:
		return
	var tamanho_tela: Vector2 = get_viewport().get_visible_rect().size
	_atualizar_destaque()
	var margem_tela: float = clampf(tamanho_tela.x * 0.018, 18.0, 34.0)
	var largura: float = minf(tamanho_tela.x - margem_tela * 2.0, 1280.0)
	var altura: float = clampf(tamanho_tela.y * 0.34, 330.0, 410.0)
	var y: float = tamanho_tela.y - altura - margem_tela
	if not _retangulo_alvo.has_area():
		y = tamanho_tela.y - altura - margem_tela
	elif _retangulo_alvo.get_center().y > tamanho_tela.y * 0.60:
		y = margem_tela
	_painel_fala.position = Vector2((tamanho_tela.x - largura) * 0.5, y)
	_painel_fala.size = Vector2(largura, altura)
	_painel_fala.pivot_offset = _painel_fala.size * 0.5

	if _btn_sair != null:
		_btn_sair.position = Vector2(tamanho_tela.x - 156.0, 22.0)
	if _painel_desafio != null:
		var largura_desafio: float = minf(tamanho_tela.x - 32.0, 940.0)
		var altura_desafio: float = 86.0
		_painel_desafio.position = Vector2(
			(tamanho_tela.x - largura_desafio) * 0.5,
			18.0
		)
		_painel_desafio.size = Vector2(largura_desafio, altura_desafio)
		_painel_desafio.pivot_offset = _painel_desafio.size * 0.5


func _atualizar_destaque() -> void:
	if _mascaras.is_empty() or _moldura_destaque == null:
		return
	var tamanho_tela: Vector2 = get_viewport().get_visible_rect().size
	var rect: Rect2 = Rect2()
	if (
		_alvo_atual != null
		and is_instance_valid(_alvo_atual)
		and _alvo_atual.is_visible_in_tree()
	):
		rect = _alvo_atual.get_global_rect().grow(12.0)
	elif (
		_alvo_tile_atual >= 0
		and _tabuleiro != null
		and _tabuleiro.has_method("obter_retangulo_tile_tutorial")
	):
		var rect_tile_variant: Variant = _tabuleiro.call(
			"obter_retangulo_tile_tutorial",
			_alvo_tile_atual
		)
		if rect_tile_variant is Rect2:
			rect = (rect_tile_variant as Rect2).grow(14.0)

	if not rect.has_area():
		_retangulo_alvo = Rect2()
		_definir_retangulo(_mascaras[0], Rect2(Vector2.ZERO, tamanho_tela))
		for indice: int in range(1, _mascaras.size()):
			_definir_retangulo(_mascaras[indice], Rect2())
		_moldura_destaque.visible = false
		return

	rect.position.x = clampf(rect.position.x, 0.0, tamanho_tela.x)
	rect.position.y = clampf(rect.position.y, 0.0, tamanho_tela.y)
	rect.size.x = clampf(rect.size.x, 0.0, tamanho_tela.x - rect.position.x)
	rect.size.y = clampf(rect.size.y, 0.0, tamanho_tela.y - rect.position.y)
	_retangulo_alvo = rect

	_definir_retangulo(
		_mascaras[0],
		Rect2(0.0, 0.0, tamanho_tela.x, rect.position.y)
	)
	_definir_retangulo(
		_mascaras[1],
		Rect2(
			0.0,
			rect.end.y,
			tamanho_tela.x,
			maxf(0.0, tamanho_tela.y - rect.end.y)
		)
	)
	_definir_retangulo(
		_mascaras[2],
		Rect2(0.0, rect.position.y, rect.position.x, rect.size.y)
	)
	_definir_retangulo(
		_mascaras[3],
		Rect2(
			rect.end.x,
			rect.position.y,
			maxf(0.0, tamanho_tela.x - rect.end.x),
			rect.size.y
		)
	)

	var pulso: float = (sin(Time.get_ticks_msec() * 0.006) + 1.0) * 0.5
	var expansao: float = 3.0 + pulso * 4.0
	_moldura_destaque.visible = true
	_moldura_destaque.position = rect.position - Vector2.ONE * expansao
	_moldura_destaque.size = rect.size + Vector2.ONE * expansao * 2.0
	_moldura_destaque.modulate.a = 0.72 + pulso * 0.28


func _definir_retangulo(controle: Control, rect: Rect2) -> void:
	controle.position = rect.position
	controle.size = rect.size
	controle.visible = rect.size.x > 0.0 and rect.size.y > 0.0


func _animar_entrada_painel() -> void:
	_painel_fala.modulate.a = 0.0
	_painel_fala.scale = Vector2(0.94, 0.92)
	var tween: Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.tween_property(_painel_fala, "modulate:a", 1.0, 0.18)
	(
		tween
		. tween_property(_painel_fala, "scale", Vector2.ONE, 0.28)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	await tween.finished


func _pulsar_moldura() -> void:
	if _moldura_destaque == null or not _moldura_destaque.visible:
		return
	var tween: Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(
		_moldura_destaque,
		"modulate",
		Color(1.0, 0.48, 0.25, 1.0),
		0.10
	)
	tween.tween_property(
		_moldura_destaque,
		"modulate",
		Color.WHITE,
		0.18
	)


func _acionar_controle_destacado() -> bool:
	if _alvo_atual == null or not is_instance_valid(_alvo_atual):
		return false
	if not _alvo_atual is BaseButton:
		return false
	var botao: BaseButton = _alvo_atual as BaseButton
	if botao.disabled or not botao.is_visible_in_tree():
		return false
	botao.pressed.emit()
	if _acao_esperada.begins_with("ui:"):
		call_deferred("_registrar_evento_local", _acao_esperada, {})
	return true


func _sair_do_tutorial() -> void:
	if _saindo:
		return
	_saindo = true
	_bloco_concluido = false
	_pular_digitacao = true
	get_tree().paused = false
	if _tabuleiro != null and _tabuleiro.has_method("definir_bots_pausados"):
		_tabuleiro.call("definir_bots_pausados", true)
	Global.limpar_partida_tutorial()

	if _transicao != null:
		_raiz_interface.visible = true
		_transicao.visible = true
		_transicao.mouse_filter = Control.MOUSE_FILTER_STOP
		var tween: Tween = create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(_transicao, "color:a", 1.0, 0.34)
		await tween.finished
	get_tree().change_scene_to_file(CENA_MENU_PRINCIPAL)


func _criar_estilo_painel() -> StyleBoxFlat:
	var estilo: StyleBoxFlat = StyleBoxFlat.new()
	estilo.bg_color = Color(0.025, 0.035, 0.055, 0.985)
	estilo.border_color = Color(0.82, 0.58, 0.22)
	estilo.border_width_left = 5
	estilo.border_width_top = 5
	estilo.border_width_right = 5
	estilo.border_width_bottom = 5
	estilo.corner_radius_top_left = 4
	estilo.corner_radius_top_right = 4
	estilo.corner_radius_bottom_left = 4
	estilo.corner_radius_bottom_right = 4
	estilo.shadow_color = Color(0.0, 0.0, 0.0, 0.85)
	estilo.shadow_size = 14
	estilo.shadow_offset = Vector2(0.0, 7.0)
	return estilo


func _criar_estilo_moldura() -> StyleBoxFlat:
	var estilo: StyleBoxFlat = StyleBoxFlat.new()
	estilo.bg_color = Color(1.0, 0.74, 0.18, 0.035)
	estilo.border_color = Color(1.0, 0.78, 0.22)
	estilo.border_width_left = 6
	estilo.border_width_top = 6
	estilo.border_width_right = 6
	estilo.border_width_bottom = 6
	estilo.corner_radius_top_left = 3
	estilo.corner_radius_top_right = 3
	estilo.corner_radius_bottom_left = 3
	estilo.corner_radius_bottom_right = 3
	estilo.shadow_color = Color(1.0, 0.52, 0.08, 0.5)
	estilo.shadow_size = 10
	return estilo


func _aplicar_estilos_botao(botao: Button) -> void:
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = Color(0.14, 0.045, 0.055, 0.98)
	normal.border_color = Color(0.78, 0.25, 0.24)
	normal.border_width_left = 3
	normal.border_width_top = 3
	normal.border_width_right = 3
	normal.border_width_bottom = 3
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.25, 0.065, 0.07, 1.0)
	hover.border_color = Color(1.0, 0.48, 0.38)
	var pressionado: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	pressionado.bg_color = Color(0.08, 0.025, 0.032, 1.0)
	botao.add_theme_stylebox_override("normal", normal)
	botao.add_theme_stylebox_override("hover", hover)
	botao.add_theme_stylebox_override("pressed", pressionado)
	botao.add_theme_stylebox_override("focus", hover)


func _aplicar_fonte(controle: Control, tamanho: int) -> void:
	if controle is RichTextLabel:
		if _fonte_pixel != null:
			controle.add_theme_font_override("normal_font", _fonte_pixel)
		controle.add_theme_font_size_override("normal_font_size", tamanho)
		return
	if _fonte_pixel != null:
		controle.add_theme_font_override("font", _fonte_pixel)
	controle.add_theme_font_size_override("font_size", tamanho)
