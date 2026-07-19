extends CanvasLayer

# Gatilho para avisar o tabuleiro que os dados rolaram
signal dados_rolados(dado1: int, dado2: int)
signal acao_terreno_escolhida(comprou: bool)
signal lance_leilao_enviado(valor: int)
signal solicitar_construcao(casa_id: int)
signal solicitar_hipoteca(casa_id: int)
signal solicitar_habilidade(alvo_id: String, casa_id: int)
signal solicitar_fianca_prisao()
signal rolar_novamente()  # Emitido quando o jogador tira dupla
# --- NOVO: signal para pedir ao tabuleiro a lista de alvos válidos
#     para a habilidade do personagem. O tabuleiro computa a lista
#     (com base no estado do jogo) e chama mostrar_overlay_habilidade_com_alvos. ---
signal solicitar_opcoes_alvo(id_personagem: String)
# --- NOVO (Eleições Municipais): signal emitido quando o jogador vota. ---
signal voto_eleicao_enviado(pacote: String)
# Decisões interativas dos Eventos Globais (seguro, votação, compras e escolhas).
signal decisao_evento_enviada(decisao_id: int, acao: String, selecionados: Array)
# --- NOVO (Fase 1 — Negociação): signals para o tabuleiro ouvir ---
signal solicitar_negociacao(proposta: Dictionary)
signal responder_negociacao(id_proposta: String, aceita: bool, aceitador: String)
# --- NOVO (Fase 3 — Alianças): signals para proposta de aliança ---
signal solicitar_alianca(proposta: Dictionary)
signal responder_alianca(id_proposta: String, aceita: bool, aceitador: String)
# --- NOVO (Fase 4 — Promessas): signals para criar/quebrar promessa ---
signal solicitar_criar_promessa(texto: String, autor_id: String)
signal solicitar_quebrar_promessa(id_promessa: String)

# --- NOVO (Fase 1): referências ao botão de negociar e painel ativo ---
@onready var botao_negociar = $Control/CantoDir_Construcao/VBox/HBoxBotoesInferior/BotaoNegociar
# --- PainelNegociacao é uma instância permanente da cena separada
#     painel_negociacao.tscn, declarada dentro do hud_partida.tscn. ---
@onready var painel_negociacao = $PainelNegociacao
var _sinais_painel_neg_conectados: bool = false
var painel_negociacao_ativo = null  # mantido para compatibilidade com checagens existentes

# --- REFERÊNCIAS DE INTERFACE ---
@onready var overlay_escuro = $Control/OverlayEscuro
@onready var centro_dados = $Control/Centro_Dados
@onready var label_dado1 = $Control/Centro_Dados/HBoxDados/Dado1/Valor
@onready var label_dado2 = $Control/Centro_Dados/HBoxDados/Dado2/Valor
@onready var botao_girar = $Control/Centro_Dados/BotaoGirar

@onready var container_construcao = $Control/CantoDir_Construcao
@onready var btn_abrir_construcao = $Control/CantoDir_Construcao/VBox/HBoxBotoesInferior/BotaoAbrirConstrucao
@onready var panel_construcao = $Control/CantoDir_Construcao/VBox/PainelComBotao
@onready var lista_construcao = $Control/CantoDir_Construcao/VBox/PainelComBotao/PanelConteudo/MarginInterna/Scroll/ListaPropriedades

@onready var label_nome = $Control/CantoSupEsq_Jogador/Panel/VBox/Nome
@onready var label_dinheiro = $Control/CantoSupEsq_Jogador/Panel/VBox/Dinheiro
@onready var label_propriedades = $Control/CantoSupEsq_Jogador/Panel/VBox/Propriedades
var _label_reputacao_local: Label = null

# --- NOVO (Fase 2): Painel de imunidades abaixo do CantoSupEsq_Jogador ---
@onready var painel_imunidades = $Control/PainelImunidades
@onready var lista_imunidades = $Control/PainelImunidades/Margin/VBox/ListaImunidades

# --- NOVO (Fase 3): Painel de alianças abaixo do painel de imunidades ---
@onready var painel_aliancas = $Control/PainelAliancas
@onready var lista_aliancas = $Control/PainelAliancas/Margin/VBox/ListaAliancas

# --- NOVO (Fase 4 — Promessas): Painel retrátil de promessas ---
@onready var painel_promessas = $Control/PainelPromessas
@onready var btn_toggle_promessas = $Control/BtnTogglePromessas
@onready var btn_fechar_promessas = $Control/PainelPromessas/Margin/VBox/HBoxTitulo/BtnFechar
@onready var input_promessa = $Control/PainelPromessas/Margin/VBox/Formulario/InputPromessa
@onready var btn_criar_promessa = $Control/PainelPromessas/Margin/VBox/Formulario/BtnCriar
@onready var lista_promessas = $Control/PainelPromessas/Margin/VBox/ScrollPromessas/ListaPromessas
var _promessas_aberto: bool = false

@onready var label_casa_nome = $Control/CantoSupDir_Propriedade/VBoxArea/Panel/VBox/NomeCasa
@onready var label_casa_dono = $Control/CantoSupDir_Propriedade/VBoxArea/Panel/VBox/Dono
@onready var label_casa_aluguel = $Control/CantoSupDir_Propriedade/VBoxArea/Panel/VBox/Aluguel
@onready var label_casa_info = $Control/CantoSupDir_Propriedade/VBoxArea/Panel/VBox/InfoExtra
@onready var btn_cartas_guardadas: Button = %BtnCartasGuardadas
@onready var painel_cartas_guardadas: PanelContainer = %PainelCartasGuardadas
@onready var label_carta_casa_gratis: Label = %LabelCartaCasaGratis
@onready var label_carta_sair_prisao: Label = %LabelCartaSairPrisao

@onready var label_evento_titulo = $Control/CentroSup_Evento/Panel/VBox/Titulo
@onready var label_evento_nome = $Control/CentroSup_Evento/Panel/VBox/NomeEvento

@onready var botao_hab = $Control/CantoInfEsq_Habilidade/Panel/HBox/BotaoHab
@onready var label_hab_nome = $Control/CantoInfEsq_Habilidade/Panel/HBox/VBox/NomeHab
@onready var label_hab_recarga = $Control/CantoInfEsq_Habilidade/Panel/HBox/VBox/Recarga

@onready var container_dossie = $Control/DossieDiana
@onready var btn_dossie = $Control/DossieDiana/VBox/BotaoAbriDossie
@onready var panel_dossie = $Control/DossieDiana/VBox/PanelConteudo
@onready var label_dossie_texto = $Control/DossieDiana/VBox/PanelConteudo/ScrollDossie/TextoInfiltrado

@onready var container_relatorio = $Control/RelatorioYasmin
@onready var btn_relatorio = $Control/RelatorioYasmin/VBox/BotaoAbrirRelatorio
@onready var panel_relatorio = $Control/RelatorioYasmin/VBox/PanelConteudo
@onready var label_relatorio_texto = $Control/RelatorioYasmin/VBox/PanelConteudo/TextoRelatorio

@onready var painel_acao = $Control/Centro_AcaoTerreno
@onready var lbl_acao_titulo = $Control/Centro_AcaoTerreno/Panel/VBox/Titulo
@onready var lbl_acao_preco = $Control/Centro_AcaoTerreno/Panel/VBox/Preco
@onready var btn_comprar = $Control/Centro_AcaoTerreno/Panel/VBox/HBoxBotoes/BtnComprar
@onready var btn_leilao = $Control/Centro_AcaoTerreno/Panel/VBox/HBoxBotoes/BtnLeilao

@onready var painel_carta = $Control/Centro_CartaSorteada
@onready var lbl_carta_deck = $Control/Centro_CartaSorteada/Panel/VBox/DeckNome
@onready var lbl_carta_nome = $Control/Centro_CartaSorteada/Panel/VBox/CartaNome
@onready var lbl_carta_desc = $Control/Centro_CartaSorteada/Panel/VBox/Descricao

@onready var painel_leilao = $Control/Centro_Leilao
@onready var lbl_leilao_titulo = $Control/Centro_Leilao/Panel/VBox/Titulo
@onready var input_lance = $Control/Centro_Leilao/Panel/VBox/InputLance
@onready var btn_enviar_lance = $Control/Centro_Leilao/Panel/VBox/BtnEnviarLance
var _lance_minimo_interface: int = 0

@onready var btn_evento = $Control/CentroSup_Evento/BotaoEvento
@onready var painel_detalhes_evento = $Control/Centro_DetalhesEvento
@onready var label_detalhes_evento = $Control/Centro_DetalhesEvento/PanelConteudo/TextoDetalhes

# --- NOVOS: Nós adicionados para animações e mecânicas novas ---
@onready var container_hipoteca = $Control/Centro_BtnHipoteca
@onready var btn_hipoteca = $Control/Centro_BtnHipoteca/BtnHipoteca

@onready var overlay_habilidade = $Control/Centro_HabilidadeOverlay
@onready var fundo_hab = $Control/Centro_HabilidadeOverlay/FundoHab
@onready var painel_hab = $Control/Centro_HabilidadeOverlay/PainelHab
@onready var lbl_hab_titulo = $Control/Centro_HabilidadeOverlay/PainelHab/VBox/Titulo
@onready var lbl_hab_nome = $Control/Centro_HabilidadeOverlay/PainelHab/VBox/NomeHab
@onready var lbl_hab_desc = $Control/Centro_HabilidadeOverlay/PainelHab/VBox/Descricao
@onready var btn_confirmar_hab = $Control/Centro_HabilidadeOverlay/PainelHab/VBox/HBoxBotoesHab/BtnConfirmarHab
@onready var btn_cancelar_hab = $Control/Centro_HabilidadeOverlay/PainelHab/VBox/HBoxBotoesHab/BtnCancelarHab

@onready var container_falencia = $Control/Centro_Falencia
@onready var container_vitoria = $Control/Centro_Vitoria

@onready var barra_leilao = $Control/BarraLeilao
@onready var label_round = $Control/RoundCounter

# --- NOVO (Eleições Municipais): referências ao painel de votação ---
@onready var overlay_votacao = $Control/Centro_VotacaoEleicao
@onready var fundo_votacao = $Control/Centro_VotacaoEleicao/FundoVotacao
@onready var painel_votacao = $Control/Centro_VotacaoEleicao/PainelVotacao
@onready var label_subtitulo_votacao = $Control/Centro_VotacaoEleicao/PainelVotacao/VBox/Subtitulo
@onready var label_timer_votacao = $Control/Centro_VotacaoEleicao/PainelVotacao/VBox/TimerLabel
@onready var hbox_cards_votacao = $Control/Centro_VotacaoEleicao/PainelVotacao/VBox/HBoxCards
@onready var hbox_votos_votacao = $Control/Centro_VotacaoEleicao/PainelVotacao/VBox/VotosContainer
var _votacao_ja_votou: bool = false
var _cards_votacao_criados: bool = false
var _total_eleitores_votacao: int = 0
var _votos_visiveis_votacao: int = 0
var _tween_votacao: Tween = null

# --- EVENTOS GLOBAIS INTERATIVOS: overlay reutilizável criado por código ---
var _decisao_evento_root: Control = null
var _decisao_evento_backdrop: ColorRect = null
var _decisao_evento_painel: PanelContainer = null
var _decisao_evento_titulo: Label = null
var _decisao_evento_descricao: Label = null
var _decisao_evento_status: Label = null
var _decisao_evento_timer: Label = null
var _decisao_evento_scroll: ScrollContainer = null
var _decisao_evento_lista: VBoxContainer = null
var _decisao_evento_btn_recusar: Button = null
var _decisao_evento_btn_confirmar: Button = null
var _decisao_evento_botoes: Dictionary = {}
var _decisao_evento_selecionados: Array = []
var _decisao_evento_id: int = -1
var _decisao_evento_min: int = 0
var _decisao_evento_max: int = 1
var _decisao_evento_enviada: bool = false
var _decisao_evento_pode_responder: bool = false
var _decisao_evento_timer_geracao: int = 0
var _decisao_evento_tween: Tween = null

var detalhes_evento_aberto: bool = false
var descricao_evento_atual: String = ""

# --- NOVO: Estado da habilidade ativa (aguardando seleção de alvo) ---
var habilidade_em_selecao: bool = false
var habilidade_id_ativa: String = ""  # "yasmin", "breno", etc.
var casa_id_selecionada_hab: int = -1
# --- NOVO (UI de seleção de alvo): alvo_id selecionado pelo jogador.
#     Antes, alvo_id era sempre "" (tabuleiro preenchia com próximo jogador).
#     Agora o jogador seleciona explicitamente um alvo na lista. ---
var alvo_id_selecionado_hab: String = ""
# --- NOVO (UI de seleção de alvo): referências ao ScrollContainer e VBox
#     onde os botões de alvo são adicionados dinamicamente. Criados em _ready(). ---
var scroll_alvos_hab: ScrollContainer = null
var vbox_alvos_hab: VBoxContainer = null
var label_sem_alvos_hab: Label = null
var btn_alvo_selecionado: Button = null  # último botão clicado (para destaque visual)

# --- VARIÁVEIS DE ESTADO ---
var rodando_dados: bool = false
var dossie_aberto: bool = false
var relatorio_aberto: bool = false
var construcao_aberta: bool = false
var _cartas_guardadas_aberto: bool = false
var _qtd_cartas_casa_gratis: int = 0
var _qtd_cartas_sair_prisao: int = 0

# O saldo exibido acompanha o valor autoritativo por animação. Manter o alvo
# separado impede que snapshots repetidos do modo online reiniciem a contagem
# antes que ela termine.
const DINHEIRO_DURACAO_MINIMA: float = 0.42
const DINHEIRO_DURACAO_MAXIMA: float = 0.95
var _dinheiro_exibido: float = 0.0
var _dinheiro_alvo: int = 0
var _dinheiro_inicializado: bool = false
var _id_animacao_dinheiro: int = 0
var _tween_dinheiro: Tween = null

# --- Animações suaves dos painéis laterais/retráteis ---
# Cada painel mantém seu próprio tween e identificador. Isso evita que cliques
# rápidos sobreponham animações ou deixem o Control invisível com escala errada.
const PAINEL_ESCALA_INICIAL := Vector2(0.965, 0.94)
const PAINEL_ESCALA_FECHAR := Vector2(0.985, 0.965)
var _tweens_paineis: Dictionary = {}
var _ids_animacao_paineis: Dictionary = {}

# --- MODO ESPECTADOR E PLACAR FINAL ---
const FONTE_ESPECTADOR = preload("res://assets/fonts/PressStart2P.ttf")
const CENA_HUD_ESPECTADOR = preload("res://scenes/ui/hud_espectador/hud_espectador.tscn")
var _modo_espectador: bool = false
var _dados_espectador: Dictionary = {}
var _espectador_sujo: bool = true
var _espectador_tempo_refresh: float = 0.0
var _hud_espectador_novo: Control = null
var _placar_final_root: Control = null

func _ready():
								painel_acao.visible = false
								painel_acao.modulate.a = 0.0
								painel_leilao.visible = false
								painel_leilao.modulate.a = 0.0
								btn_enviar_lance.pressed.connect(_on_botao_enviar_lance)

								botao_girar.pressed.connect(_on_botao_girar_pressed)
								botao_hab.pressed.connect(_on_botao_habilidade_pressed)
								btn_dossie.pressed.connect(_on_botao_dossie_pressed)
								btn_relatorio.pressed.connect(_on_botao_relatorio_pressed)
								btn_comprar.pressed.connect(func(): _responder_acao_terreno(true))
								btn_leilao.pressed.connect(func(): _responder_acao_terreno(false))
								btn_abrir_construcao.pressed.connect(_on_botao_abrir_construcao_pressed)

								painel_cartas_guardadas.visible = false
								atualizar_cartas_guardadas(0, 0)

								painel_detalhes_evento.visible = false
								painel_detalhes_evento.modulate.a = 0.0
								btn_evento.pressed.connect(_on_botao_evento_pressed)

								centro_dados.modulate.a = 0.0
								centro_dados.visible = false
								overlay_escuro.modulate.a = 0.0
								overlay_escuro.visible = false

								# --- CORREÇÃO: Painéis de INFO (só display, sem interação) ficam com
								#     MOUSE_FILTER_IGNORE para que o toque passe direto para a câmera.
								#     Apenas botões, scroll containers e overlays modais mantêm STOP. ---
								_set_ignore_except_interactive($Control/CantoSupEsq_Jogador)
								_set_ignore_except_interactive($Control/CantoSupDir_Propriedade)
								_set_ignore_except_interactive($Control/CentroSup_Evento)
								_set_ignore_except_interactive($Control/CantoInfEsq_Habilidade)
								_set_ignore_except_interactive($Control/CantoDir_Construcao)

								# --- NOVO: Botão cancelar do overlay de habilidade ---
								btn_cancelar_hab.pressed.connect(_on_btn_cancelar_hab_pressed)

								# --- NOVO (UI de seleção de alvo): cria o ScrollContainer + VBox
								#     dinamicamente e insere ANTES dos botões Cancelar/Confirmar.
								#     Inicialmente invisível — só aparece para habilidades que
								#     precisam de seleção de alvo (todas as 6 ativas). ---
								_criar_lista_alvos_habilidade()

								# --- NOVO: Botão FECHAR do painel de gestão removido —
								#     agora o painel fecha clicando no próprio botão de Gestão (toggle). ---

								# --- NOVO (Fase 1 — Negociação): conecta o botão Negociar
								#     que agora é um nó permanente no .tscn, dentro do
								#     HBoxBotoesInferior ao lado do botão Gestão. ---
								if botao_negociar:
																botao_negociar.pressed.connect(_on_botao_negociar_pressed)

								# --- NOVO (Fase 4 — Promessas): conecta botões do painel retrátil de promessas ---
								if btn_toggle_promessas:
																btn_toggle_promessas.pressed.connect(_toggle_painel_promessas)
								if btn_fechar_promessas:
																btn_fechar_promessas.pressed.connect(_fechar_painel_promessas)
								if btn_criar_promessa:
																btn_criar_promessa.pressed.connect(_on_criar_promessa_pressed)
								# Botão de promessas começa visível (para o jogador poder abrir quando quiser)
								if btn_toggle_promessas:
																btn_toggle_promessas.visible = true
								if input_promessa:
									input_promessa.max_length = 180
									input_promessa.placeholder_text = "Acordo público: 5 turnos (máx. 3 ativos)"

								_criar_indicador_reputacao_local()
								_criar_interface_espectador()

# ============================================================================
# REPUTAÇÃO E XP DO JOGADOR LOCAL
# ============================================================================
func _criar_indicador_reputacao_local() -> void:
	if _label_reputacao_local != null and is_instance_valid(_label_reputacao_local):
		return
	var vbox = label_propriedades.get_parent()
	if vbox == null:
		return
	_label_reputacao_local = Label.new()
	_label_reputacao_local.name = "ReputacaoXP"
	var perfil = Progressao.obter_perfil()
	_label_reputacao_local.text = "NÍVEL %d | XP TOTAL %d | XP PARTIDA 0 | REP 50/100" % [int(perfil.get("nivel", 1)), int(perfil.get("xp_total", 0))]
	_label_reputacao_local.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label_reputacao_local.add_theme_font_override("font", FONTE_ESPECTADOR)
	_label_reputacao_local.add_theme_font_size_override("font_size", 13)
	_label_reputacao_local.add_theme_color_override("font_color", Color(0.95, 0.82, 0.38))
	_label_reputacao_local.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_label_reputacao_local.add_theme_constant_override("outline_size", 3)
	_label_reputacao_local.tooltip_text = "O XP da partida é salvo no perfil ao fim do jogo. Reputação 75+: recebe $40 em Eventos Globais; 25 ou menos: paga $40."
	vbox.add_child(_label_reputacao_local)

func atualizar_reputacao_jogador(reputacao: int, xp_partida: int) -> void:
	_criar_indicador_reputacao_local()
	if _label_reputacao_local == null:
		return
	var valor = clampi(reputacao, 0, 100)
	var perfil = Progressao.obter_perfil()
	_label_reputacao_local.text = "NÍVEL %d | XP TOTAL %d | XP PARTIDA %d | REP %d/100" % [
		int(perfil.get("nivel", 1)), int(perfil.get("xp_total", 0)), maxi(0, xp_partida), valor
	]
	var cor = Color(0.4, 1.0, 0.5) if valor >= 75 else (Color(0.95, 0.4, 0.4) if valor <= 25 else Color(0.9, 0.78, 0.35))
	_label_reputacao_local.add_theme_color_override("font_color", cor)

# ============================================================================
# ANIMAÇÕES REUTILIZÁVEIS DOS PAINÉIS DA HUD
# ============================================================================

func _cancelar_animacao_painel(painel: Control) -> void:
	if painel == null or not is_instance_valid(painel):
		return
	var chave := painel.get_instance_id()
	var tween: Tween = _tweens_paineis.get(chave)
	if tween != null and tween.is_valid():
		tween.kill()
	_tweens_paineis.erase(chave)

func _novo_id_animacao_painel(painel: Control) -> int:
	var chave := painel.get_instance_id()
	var novo_id := int(_ids_animacao_paineis.get(chave, 0)) + 1
	_ids_animacao_paineis[chave] = novo_id
	return novo_id

func _animar_abertura_painel(
	painel: Control,
	escala_inicial: Vector2 = PAINEL_ESCALA_INICIAL,
	duracao: float = 0.24
) -> void:
	if painel == null or not is_instance_valid(painel):
		return
	var chave := painel.get_instance_id()
	var animacao_id := _novo_id_animacao_painel(painel)
	_cancelar_animacao_painel(painel)

	painel.visible = true
	painel.modulate.a = 0.0
	painel.scale = escala_inicial

	# Controls dentro de Containers recebem tamanho/posição no frame de layout.
	# Esperar um frame garante que o pivô central use o tamanho final do painel.
	await get_tree().process_frame
	if not is_instance_valid(painel) or int(_ids_animacao_paineis.get(chave, 0)) != animacao_id:
		return

	painel.pivot_offset = Vector2.ZERO
	painel.pivot_offset_ratio = Vector2(0.5, 0.5)
	painel.scale = escala_inicial

	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tweens_paineis[chave] = tween
	tween.tween_property(painel, "modulate:a", 1.0, duracao * 0.72)
	tween.parallel().tween_property(painel, "scale", Vector2.ONE, duracao)
	tween.tween_callback(func() -> void:
		if int(_ids_animacao_paineis.get(chave, 0)) != animacao_id:
			return
		painel.modulate.a = 1.0
		painel.scale = Vector2.ONE
		_tweens_paineis.erase(chave)
	)

func _animar_fechamento_painel(
	painel: Control,
	escala_final: Vector2 = PAINEL_ESCALA_FECHAR,
	duracao: float = 0.16
) -> void:
	if painel == null or not is_instance_valid(painel):
		return
	if not painel.visible:
		painel.modulate.a = 1.0
		painel.scale = Vector2.ONE
		return

	var chave := painel.get_instance_id()
	var animacao_id := _novo_id_animacao_painel(painel)
	_cancelar_animacao_painel(painel)
	painel.pivot_offset = Vector2.ZERO
	painel.pivot_offset_ratio = Vector2(0.5, 0.5)

	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tweens_paineis[chave] = tween
	tween.tween_property(painel, "modulate:a", 0.0, duracao)
	tween.parallel().tween_property(painel, "scale", escala_final, duracao)
	tween.tween_callback(func() -> void:
		if int(_ids_animacao_paineis.get(chave, 0)) != animacao_id:
			return
		painel.visible = false
		painel.modulate.a = 1.0
		painel.scale = Vector2.ONE
		_tweens_paineis.erase(chave)
	)

func _ocultar_painel_imediato(painel: Control) -> void:
	if painel == null or not is_instance_valid(painel):
		return
	_novo_id_animacao_painel(painel)
	_cancelar_animacao_painel(painel)
	painel.visible = false
	painel.modulate.a = 1.0
	painel.scale = Vector2.ONE

# ============================================================================
# NOVO (Fase 1 — Negociação): BOTÃO "NEGOCIAR" E PAINEL DE NEGOCIAÇÃO
# ============================================================================
# O botão "Negociar" é um nó permanente do hud_partida.tscn, posicionado
# ao lado do botão "Gestão de Propriedades" dentro de um HBoxContainer.
# O painel de negociação é uma instância de painel_negociacao.tscn.
# Não montamos sua interface por script; apenas configuramos e chamamos exibir().

func _on_botao_negociar_pressed():
	if _modo_espectador:
		return
	abrir_painel_negociacao_proposta()

# Conecta os sinais do painel (uma única vez) à HUD.
func _conectar_sinais_painel_negociacao():
								if _sinais_painel_neg_conectados:
																return
								if painel_negociacao == null:
																return
								painel_negociacao.proposta_enviada.connect(_on_proposta_enviada_painel)
								painel_negociacao.proposta_respondida.connect(_on_proposta_respondida_painel)
								painel_negociacao.cancelado.connect(_on_painel_negociacao_fechado)
								# --- NOVO (Fase 3 — Alianças): conecta signal de proposta de aliança ---
								if painel_negociacao.has_signal("alianca_proposta"):
																painel_negociacao.alianca_proposta.connect(_on_alianca_proposta_painel)
								_sinais_painel_neg_conectados = true

# --- NOVO (Fase 3): handler do signal alianca_proposta do painel.
#     Repassa ao tabuleiro via signal solicitar_alianca. ---
func _on_alianca_proposta_painel(proposta: Dictionary):
								solicitar_alianca.emit(proposta)

# Abre o painel em MODO_PROPOSTA (jogador local monta a proposta).
# O tabuleiro fornece as referências necessárias.
func abrir_painel_negociacao_proposta():
								if _modo_espectador:
																return
								if painel_negociacao == null or not is_instance_valid(painel_negociacao):
																return
								if painel_negociacao.visible:
																# Já está aberto; não abre de novo
																return
								var meu_id = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
								if meu_id == "":
																return
								var tabuleiro = get_tree().get_first_node_in_group("tabuleiro_principal")
								if tabuleiro == null:
																return
								if not tabuleiro.has_method("fornecer_dados_para_negociacao"):
																return
								var refs = tabuleiro.fornecer_dados_para_negociacao()
								_conectar_sinais_painel_negociacao()
								painel_negociacao.configurar_como_proposta(
												meu_id,
												refs.dados_jogadores,
												refs.tabuleiro_data,
												refs.registro_props,
												refs.lista_turnos
								)
								painel_negociacao.exibir()
								painel_negociacao_ativo = painel_negociacao

# Handler: o painel emitiu uma proposta. Repassa ao tabuleiro via signal.
func _on_proposta_enviada_painel(proposta: Dictionary):
								solicitar_negociacao.emit(proposta)

# Handler: o receptor (em MODO_RESPOSTA) respondeu. Repassa ao tabuleiro.
func _on_proposta_respondida_painel(id_proposta: String, aceita: bool, aceitador: String):
								responder_negociacao.emit(id_proposta, aceita, aceitador)

# Handler: o painel foi cancelado/fechado pelo usuário.
func _on_painel_negociacao_fechado():
								painel_negociacao_ativo = null

# Mostra uma proposta recebida (chamado pelo tabuleiro quando uma proposta chega).
# Abre o painel em MODO_RESPOSTA.
func mostrar_proposta_recebida(proposta: Dictionary):
								if painel_negociacao == null or not is_instance_valid(painel_negociacao):
																return
								if painel_negociacao.visible:
																# Já há um painel aberto — não sobrescreve (o tabuleiro deve enfileirar).
																return
								var meu_id = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
								if meu_id == "":
																return
								var tabuleiro = get_tree().get_first_node_in_group("tabuleiro_principal")
								if tabuleiro == null:
																return
								if not tabuleiro.has_method("fornecer_dados_para_negociacao"):
																return
								var refs = tabuleiro.fornecer_dados_para_negociacao()
								_conectar_sinais_painel_negociacao()
								painel_negociacao.configurar_como_resposta(
												proposta,
												meu_id,
												refs.dados_jogadores,
												refs.tabuleiro_data,
												refs.registro_props
								)
								painel_negociacao.exibir()
								painel_negociacao_ativo = painel_negociacao

# Atualiza o status do painel ativo (chamado pelo tabuleiro após receber resposta da rede).
# Casos: "Proposta aceita! Executando...", "Proposta recusada.", etc.
func atualizar_status_negociacao(texto: String, cor: Color = Color(0.7, 0.7, 0.7, 1)):
								if painel_negociacao != null and is_instance_valid(painel_negociacao) and painel_negociacao.visible:
																painel_negociacao.mostrar_status(texto, cor)

# Fecha o painel ativo (chamado pelo tabuleiro após concluir a transação).
func fechar_painel_negociacao():
	if painel_negociacao != null and is_instance_valid(painel_negociacao):
		if painel_negociacao.has_method("esconder_animado"):
			painel_negociacao.esconder_animado()
		else:
			painel_negociacao.visible = false
	painel_negociacao_ativo = null

func bloquear_botao_negociar():
								if botao_negociar:
																botao_negociar.disabled = true
																botao_negociar.modulate = Color(0.5, 0.5, 0.5, 1)

func desbloquear_botao_negociar():
								if _modo_espectador:
																if botao_negociar:
																								botao_negociar.disabled = true
																return
								if botao_negociar:
																botao_negociar.disabled = false
																botao_negociar.modulate = Color(1, 1, 1, 1)

# ============================================================================
# SISTEMA DE DADOS COM ATUALIZAÇÃO VISUAL
# ============================================================================
func _on_botao_girar_pressed():
								if _modo_espectador:
																return
								if rodando_dados: return
								rodando_dados = true
								botao_girar.disabled = true
								
								# --- NOVO: Referências aos PanelContainers de cada dado para tumble 3D ---
								var dado1_panel = $Control/Centro_Dados/HBoxDados/Dado1
								var dado2_panel = $Control/Centro_Dados/HBoxDados/Dado2
								
								# Flicker rápido com números aleatórios (12 frames)
								for i in range(12):
																label_dado1.text = str(randi_range(1, 6))
																label_dado2.text = str(randi_range(1, 6))
																$Control/Centro_Dados/HBoxDados/SinalMais.modulate.a = 0.3 if i % 2 == 0 else 1.0
																# Tumble: rotação Z e leve pulo Y em cada frame
																dado1_panel.rotation_degrees = randf_range(-25, 25)
																dado2_panel.rotation_degrees = randf_range(-25, 25)
																dado1_panel.scale = Vector2(1.1, 1.1) if i % 2 == 0 else Vector2(0.95, 0.95)
																dado2_panel.scale = Vector2(0.95, 0.95) if i % 2 == 0 else Vector2(1.1, 1.1)
																await get_tree().create_timer(0.06).timeout
								
								var d1: int = randi_range(1, 6)
								var d2: int = randi_range(1, 6)
								var tabuleiro_ref: Node = get_tree().get_first_node_in_group(
									"tabuleiro_principal"
								)
								if (
									tabuleiro_ref != null
									and tabuleiro_ref.has_method("obter_resultado_dados_tutorial")
								):
																var resultado_variant: Variant = tabuleiro_ref.call(
																	"obter_resultado_dados_tutorial"
																)
																if resultado_variant is Vector2i:
																								var resultado_tutorial: Vector2i = resultado_variant
																								if (
																									resultado_tutorial.x in range(1, 7)
																									and resultado_tutorial.y in range(1, 7)
																								):
																																d1 = resultado_tutorial.x
																																d2 = resultado_tutorial.y
								label_dado1.text = str(d1)
								label_dado2.text = str(d2)
								$Control/Centro_Dados/HBoxDados/SinalMais.modulate.a = 1.0
								
								# --- NOVO: Quica e assenta os dados com squash elástico ---
								var tween_assentar = create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
								tween_assentar.parallel().tween_property(dado1_panel, "rotation_degrees", 0.0, 0.4)
								tween_assentar.parallel().tween_property(dado2_panel, "rotation_degrees", 0.0, 0.4)
								tween_assentar.parallel().tween_property(dado1_panel, "scale", Vector2(1.0, 1.0), 0.4)
								tween_assentar.parallel().tween_property(dado2_panel, "scale", Vector2(1.0, 1.0), 0.4)
								await tween_assentar.finished
								
								# Detecta dupla para feedback visual extra
								if d1 == d2:
																lbl_hab_titulo.text = "DUPLA!"
																# Pisca ambos dados de verde
																Animacoes.pulso_de_cor(dado1_panel, Color(0.4, 1.0, 0.4), 3, 0.15)
																Animacoes.pulso_de_cor(dado2_panel, Color(0.4, 1.0, 0.4), 3, 0.15)
								
								await get_tree().create_timer(0.6).timeout
								
								var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
								tween.parallel().tween_property(centro_dados, "modulate:a", 0.0, 0.4)
								tween.parallel().tween_property(overlay_escuro, "modulate:a", 0.0, 0.4)
								await tween.finished
								
								centro_dados.visible = false
								overlay_escuro.visible = false
								
								emit_signal("dados_rolados", d1, d2)

func mostrar_painel_dados():
								if _modo_espectador:
																esconder_painel_dados()
																return
								rodando_dados = false
								botao_girar.disabled = false
								
								centro_dados.visible = true
								overlay_escuro.visible = true
								
								var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
								tween.parallel().tween_property(centro_dados, "modulate:a", 1.0, 0.4)
								tween.parallel().tween_property(overlay_escuro, "modulate:a", 1.0, 0.4)

func esconder_painel_dados():
								centro_dados.visible = false
								centro_dados.modulate.a = 0.0
								overlay_escuro.visible = false
								overlay_escuro.modulate.a = 0.0

# ============================================================================
# ATUALIZAR INTERFACE DO PERSONAGEM ATUAL
# ============================================================================
# ANIMAÇÃO DO SALDO LOCAL
func _atualizar_texto_dinheiro_animado(valor: float) -> void:
	_dinheiro_exibido = valor
	label_dinheiro.text = "$ " + str(int(round(valor)))


func _concluir_animacao_dinheiro(saldo_esperado: int, animacao_id: int) -> void:
	if animacao_id != _id_animacao_dinheiro:
		return
	_dinheiro_exibido = float(saldo_esperado)
	_atualizar_texto_dinheiro_animado(_dinheiro_exibido)
	label_dinheiro.scale = Vector2.ONE
	label_dinheiro.self_modulate = Color.WHITE
	_tween_dinheiro = null


func _animar_atualizacao_dinheiro(novo_saldo: int) -> void:
	# A primeira leitura apenas estabelece o saldo inicial da partida. As
	# leituras seguintes, inclusive as vindas de RPC ou snapshot, são animadas.
	if not _dinheiro_inicializado:
		_dinheiro_inicializado = true
		_dinheiro_alvo = novo_saldo
		_dinheiro_exibido = float(novo_saldo)
		_atualizar_texto_dinheiro_animado(_dinheiro_exibido)
		return

	# O tabuleiro atualiza outros elementos da HUD com frequência. Se o saldo
	# autoritativo não mudou, preserva o Tween em andamento em vez de reiniciá-lo.
	if novo_saldo == _dinheiro_alvo:
		return

	_id_animacao_dinheiro += 1
	var animacao_id: int = _id_animacao_dinheiro
	if _tween_dinheiro != null and _tween_dinheiro.is_valid():
		_tween_dinheiro.kill()

	var saldo_inicial: float = _dinheiro_exibido
	var saldo_inicial_arredondado: int = int(round(saldo_inicial))
	var diferenca: int = novo_saldo - saldo_inicial_arredondado
	_dinheiro_alvo = novo_saldo

	if diferenca == 0:
		_concluir_animacao_dinheiro(novo_saldo, animacao_id)
		return

	var magnitude: int = absi(diferenca)
	var duracao: float = clampf(
		DINHEIRO_DURACAO_MINIMA + float(magnitude) / 900.0,
		DINHEIRO_DURACAO_MINIMA,
		DINHEIRO_DURACAO_MAXIMA
	)
	var escala_destaque: float = 1.08 if diferenca > 0 else 0.94
	var cor_destaque: Color = (
		Color(0.58, 1.0, 0.58, 1.0)
		if diferenca > 0
		else Color(1.0, 0.52, 0.52, 1.0)
	)

	label_dinheiro.pivot_offset = label_dinheiro.size * 0.5
	label_dinheiro.scale = Vector2(escala_destaque, escala_destaque)
	label_dinheiro.self_modulate = cor_destaque

	_tween_dinheiro = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween_dinheiro.tween_method(
		Callable(self, "_atualizar_texto_dinheiro_animado"),
		saldo_inicial,
		float(novo_saldo),
		duracao
	)
	_tween_dinheiro.parallel().tween_property(
		label_dinheiro, "scale", Vector2.ONE, duracao
	)
	_tween_dinheiro.parallel().tween_property(
		label_dinheiro, "self_modulate", Color.WHITE, duracao
	)
	_tween_dinheiro.tween_callback(
		Callable(self, "_concluir_animacao_dinheiro").bind(novo_saldo, animacao_id)
	)


# --- BUG FIX (HIGH #13): Antes, a comparação "nome.to_lower() == 'diana'"
#     nunca era true porque o nome é "Diana Ferro" (nome completo). O dossiê
#     da Diana NUNCA aparecia na UI. O mesmo valia para Yasmin.
#     SOLUÇÃO: usar begins_with() para comparar apenas o primeiro nome. ---
func atualizar_status_jogador(nome: String, dinheiro: int, qtd_propriedades: int):
								label_nome.text = nome.to_upper()
								_animar_atualizacao_dinheiro(dinheiro)
								label_propriedades.text = "PROPRIEDADES: " + str(qtd_propriedades)
								
								if nome.to_lower().begins_with("diana"):
																container_dossie.visible = true
								else:
																container_dossie.visible = false
																_ocultar_painel_imediato(panel_dossie)
																dossie_aberto = false
																
								if nome.to_lower().begins_with("yasmin"):
																container_relatorio.visible = true
								else:
																container_relatorio.visible = false
																_ocultar_painel_imediato(panel_relatorio)
																relatorio_aberto = false


# Um snapshot persistente só é criado entre decisões. Corrotinas de compra,
# leilão, carta ou votação não sobrevivem à troca de cena; impedir a gravação
# nesses poucos momentos evita retomar a partida sem o painel necessário.
func motivo_bloqueio_salvamento() -> String:
	if rodando_dados:
		return "AGUARDE A ROLAGEM DOS DADOS TERMINAR"
	var controles_decisao: Array = [
		painel_acao,
		painel_carta,
		painel_leilao,
		overlay_habilidade,
		overlay_votacao,
		container_falencia,
		container_vitoria,
		painel_negociacao,
		_decisao_evento_root,
	]
	for controle_variant in controles_decisao:
		if controle_variant is CanvasLayer:
			var camada: CanvasLayer = controle_variant
			if is_instance_valid(camada) and camada.visible:
				return "CONCLUA A DECISÃO ATUAL ANTES DE SALVAR"
			continue
		if not controle_variant is CanvasItem:
			continue
		var controle: CanvasItem = controle_variant
		if is_instance_valid(controle) and controle.visible:
			return "CONCLUA A DECISÃO ATUAL ANTES DE SALVAR"
	return ""

# ============================================================================
# NOVO (Fase 2): PAINEL DE IMUNIDADES
# ============================================================================
# Mostra as imunidades ativas do jogador local abaixo do CantoSupEsq_Jogador.
# O painel só fica visível se o jogador tiver pelo menos 1 imunidade ativa.
# Chamado pelo tabuleiro em _atualizar_hud_ciclo_turno().
func atualizar_painel_imunidades(imunidades: Array):
								if painel_imunidades == null or lista_imunidades == null:
																return
								# Limpa lista atual
								for child in lista_imunidades.get_children():
																child.queue_free()
								# Se não há imunidades, esconde o painel
								if imunidades.is_empty():
																painel_imunidades.visible = false
																return
								# Mostra o painel e preenche com cada imunidade do jogador local.
								# IMPORTANTE: este painel só mostra as IMUNIDADES DO PRÓPRIO JOGADOR
								# (as que ele concedeu ou recebeu via negociação). Outros jogadores
								# não veem suas imunidades aqui — só no dossiê da Diana.
								painel_imunidades.visible = true
								# Atualiza o título para deixar claro que são SUAS imunidades
								var titulo_label = lista_imunidades.get_parent().get_node_or_null("Titulo")
								if titulo_label:
																titulo_label.text = "🛡 SUAS IMUNIDADES"
								for imun in imunidades:
																var de_id = imun.get("de", "")
																var visitas = imun.get("visitas_restantes", 0)
																var turnos = imun.get("turnos_restantes", 0)
																# Tenta buscar o nome completo do jogador contra quem é imune
																# (mais legível que só o ID). Se não achar, usa o ID.
																var de_nome = de_id
																var tabuleiro_node = get_tree().get_first_node_in_group("tabuleiro_principal")
																if tabuleiro_node and tabuleiro_node.has_method("fornecer_dados_para_negociacao"):
																								var refs = tabuleiro_node.fornecer_dados_para_negociacao()
																								de_nome = refs.dados_jogadores.get(de_id, {}).get("nome", de_id)
																								# Pega só o primeiro nome (ex.: "Igor Volkov" → "Igor")
																								var espaco = de_nome.find(" ")
																								if espaco > 0:
																																de_nome = de_nome.substr(0, espaco)
																var lbl = Label.new()
																lbl.text = "vs " + de_nome.to_upper() + "\n" + str(visitas) + " visita(s) | " + str(turnos) + "T restante"
																lbl.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
																lbl.add_theme_font_size_override("font_size", 10)
																lbl.add_theme_color_override("font_color", Color(0.6, 0.95, 0.85, 1))
																lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
																lbl.add_theme_constant_override("outline_size", 4)
																lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
																lista_imunidades.add_child(lbl)

# ============================================================================
# NOVO (Fase 3): PAINEL DE ALIANÇAS
# ============================================================================
# Mostra as alianças ativas do jogador local abaixo do painel de imunidades.
# O painel só fica visível se o jogador tiver pelo menos 1 aliança ativa.
# Chamado pelo tabuleiro em _atualizar_hud_ciclo_turno().
func atualizar_painel_aliancas(aliancas: Array):
								if painel_aliancas == null or lista_aliancas == null:
																return
								# Limpa lista atual
								for child in lista_aliancas.get_children():
																child.queue_free()
								# Se não há alianças, esconde o painel
								if aliancas.is_empty():
																painel_aliancas.visible = false
																return
								# Mostra o painel e preenche com cada aliança do jogador local.
								painel_aliancas.visible = true
								for alianca in aliancas:
																var com_id = alianca.get("com", "")
																var turnos = alianca.get("turnos_restantes", 0)
																# Busca nome do aliado
																var com_nome = com_id
																var tabuleiro_node = get_tree().get_first_node_in_group("tabuleiro_principal")
																if tabuleiro_node and tabuleiro_node.has_method("fornecer_dados_para_negociacao"):
																								var refs = tabuleiro_node.fornecer_dados_para_negociacao()
																								com_nome = refs.dados_jogadores.get(com_id, {}).get("nome", com_id)
																								var espaco = com_nome.find(" ")
																								if espaco > 0:
																																com_nome = com_nome.substr(0, espaco)
																var lbl = Label.new()
																lbl.text = "com " + com_nome.to_upper() + "\n" + str(turnos) + "T restante"
																lbl.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
																lbl.add_theme_font_size_override("font_size", 10)
																lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.15, 1))
																lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
																lbl.add_theme_constant_override("outline_size", 4)
																lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
																lista_aliancas.add_child(lbl)

# ============================================================================
# ATUALIZAR INTERFACE DA PROPRIEDADE EM FOCO
# ============================================================================
func atualizar_info_casa(dados_casa: Dictionary, dono: String = "Nenhum"):
								label_casa_nome.text = dados_casa.get("nome", "Terreno Vazio").to_upper()
								label_casa_info.text = dados_casa.get("info_extra", "")
								
								if dados_casa.get("preco", 0) == 0:
																label_casa_dono.text = "TIPO: ESPECIAL"
																label_casa_aluguel.text = "ZONA DE EFEITO"
																return
																
								label_casa_dono.text = "DONO: " + dono.to_upper()
								if dono == "Nenhum":
																label_casa_aluguel.text = "COMPRA: $" + str(dados_casa.get("preco", 0))
								else:
																label_casa_aluguel.text = "ALUGUEL: $" + str(dados_casa.get("aluguel_atual", 10))

# ============================================================================
# EVENTOS GLOBAIS
# ============================================================================
func atualizar_evento_global(nome_evento: String, estavel: bool = false, descricao: String = ""):
								label_evento_nome.text = nome_evento.to_upper()
								descricao_evento_atual = descricao
								
								if detalhes_evento_aberto:
																label_detalhes_evento.text = descricao_evento_atual
								
								if estavel:
																label_evento_titulo.text = "ESTADO DA CIDADE"
																label_evento_titulo.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4, 1.0))
																label_evento_nome.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
								else:
																label_evento_titulo.text = "EVENTO GLOBAL ATIVO!"
																label_evento_titulo.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3, 1.0))
																label_evento_nome.add_theme_color_override("font_color", Color(0.95, 0.85, 0.15, 1.0))
																
																var tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_loops(3)
																tween.tween_property($Control/CentroSup_Evento, "modulate:a", 0.5, 0.4)
																tween.tween_property($Control/CentroSup_Evento, "modulate:a", 1.0, 0.4)

func _on_botao_evento_pressed():
								if descricao_evento_atual == "": return 
								
								detalhes_evento_aberto = !detalhes_evento_aberto
								
								if detalhes_evento_aberto:
																label_detalhes_evento.text = descricao_evento_atual
																painel_detalhes_evento.visible = true
																var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
																tween.tween_property(painel_detalhes_evento, "modulate:a", 1.0, 0.2)
								else:
																var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
																tween.tween_property(painel_detalhes_evento, "modulate:a", 0.0, 0.2)
																await tween.finished
																painel_detalhes_evento.visible = false

# ============================================================================
# CONTROLE DE HABILIDADES
# ============================================================================
func atualizar_habilidade(nome_hab: String, turnos_recarga: int):
								label_hab_nome.text = nome_hab.to_upper()
								if _modo_espectador:
																botao_hab.disabled = true
																botao_hab.modulate = Color(0.6, 0.6, 0.6, 0.8)
																label_hab_recarga.text = "MODO ESPECTADOR"
																return
								if turnos_recarga > 0:
																botao_hab.disabled = true
																botao_hab.modulate = Color(0.4, 0.4, 0.4, 1.0)
																label_hab_recarga.text = "AGUARDE: " + str(turnos_recarga) + " T"
								else:
																botao_hab.disabled = false
																botao_hab.modulate = Color(1.0, 1.0, 1.0, 1.0)
																label_hab_recarga.text = "PRONTA"

func _on_botao_habilidade_pressed():
								if _modo_espectador:
																return
								# --- NOVO (UI de seleção de alvo): ao clicar no botão de habilidade,
								#     emite um signal pedindo ao tabuleiro a lista de alvos válidos.
								#     O tabuleiro computa as opções (com base no estado do jogo) e
								#     chama mostrar_overlay_habilidade_com_alvos() com a lista populada.
								#     Antes, o overlay era mostrado direto com alvo automático/aleatório. ---
								var id_personagem = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
								if id_personagem == "":
																return
								# Emite signal — tabuleiro valida cooldown/eventos e computa opções
								emit_signal("solicitar_opcoes_alvo", id_personagem)

# ============================================================================
# RECURSOS EXCLUSIVOS: DOSSIÊ (DIANA) E RELATÓRIO (YASMIN)
# ============================================================================
func _on_botao_dossie_pressed():
	dossie_aberto = !dossie_aberto
	btn_dossie.text = "FECHAR DOSSIÊ" if dossie_aberto else "ABRIR DOSSIÊ"
	if dossie_aberto:
		_animar_abertura_painel(panel_dossie, Vector2(0.97, 0.94), 0.24)
	else:
		_animar_fechamento_painel(panel_dossie, Vector2(0.985, 0.96), 0.16)

func alimentar_dados_dossie(lista_jogadores_info: Array):
								var texto_final = "=== RELATÓRIO CONFIDENCIAL ===\n"
								for jog in lista_jogadores_info:
																texto_final += "\n• %s\n  Saldo: $%d | Ativos: %d\n" % [jog.nome.to_upper(), jog.dinheiro, jog.props]
																# --- NOVO (Fase 2): mostra imunidades ativas de cada jogador,
																#     se houver. A Diana pode ver quem tem imunidade contra quem,
																#     quantas visitas restam e por quantos turnos. ---
																var imun_txt = jog.get("imunidades", "nenhuma")
																texto_final += "  🛡 Imunidades: %s\n" % imun_txt
																# --- NOVO (Fase 3): mostra alianças ativas de cada jogador,
																#     se houver. A Diana pode ver quem é aliado de quem e
																#     por quantos turnos. ---
																var alianca_txt = jog.get("aliancas", "nenhuma")
																texto_final += "  🤝 Alianças: %s\n" % alianca_txt
																# --- NOVO (Fase 4): mostra promessas feitas e quebradas ---
																var promessa_txt = jog.get("promessas", "0 feitas")
																texto_final += "  📜 Promessas: %s\n" % promessa_txt
																texto_final += "  ⭐ Reputação: %d/100 | XP: %d\n" % [int(jog.get("reputacao", 50)), int(jog.get("xp_partida", 0))]
								label_dossie_texto.text = texto_final

# Fonte Anônima acrescenta ao dossiê a única previsão concedida na partida.
func alimentar_previsao_evento(nome_evento: String, descricao: String) -> void:
	var texto_atual: String = label_dossie_texto.text
	var marker: String = "\n=== FONTE ANÔNIMA ==="
	var indice_previsao: int = texto_atual.find(marker)
	if indice_previsao >= 0:
		texto_atual = texto_atual.substr(0, indice_previsao)

	var linhas_descricao: PackedStringArray = descricao.split("\n")
	var desc_curta: String = linhas_descricao[0] if not linhas_descricao.is_empty() else ""
	if linhas_descricao.size() > 1:
		var segunda_linha: String = linhas_descricao[1]
		if segunda_linha.strip_edges() != "":
			desc_curta = segunda_linha
	texto_atual += marker + "\n🔮 PRÓXIMO EVENTO:\n" + nome_evento.to_upper() + "\n" + desc_curta + "\n"
	label_dossie_texto.text = texto_atual

	if not dossie_aberto:
		dossie_aberto = true
		btn_dossie.text = "FECHAR DOSSIÊ"
		_animar_abertura_painel(panel_dossie, Vector2(0.97, 0.94), 0.24)

func limpar_previsao_evento() -> void:
	var marker: String = "\n=== FONTE ANÔNIMA ==="
	var indice_previsao: int = label_dossie_texto.text.find(marker)
	if indice_previsao >= 0:
		label_dossie_texto.text = label_dossie_texto.text.substr(0, indice_previsao)

func _on_botao_relatorio_pressed():
	relatorio_aberto = !relatorio_aberto
	btn_relatorio.text = "FECHAR RELATÓRIO" if relatorio_aberto else "ABRIR RELATÓRIO"
	if relatorio_aberto:
		_animar_abertura_painel(panel_relatorio, Vector2(0.97, 0.94), 0.24)
	else:
		_animar_fechamento_painel(panel_relatorio, Vector2(0.985, 0.96), 0.16)

func alimentar_dados_relatorio(dicas: Array):
								var texto_final = "=== RELATÓRIO DE MERCADO ===\n\nProbabilidade calculada pelas posições atuais e pela distribuição exata de 2d6 para os próximos 2 turnos da mesa:\n"
								for dica in dicas: texto_final += "\n• " + dica
								label_relatorio_texto.text = texto_final

# ============================================================================
# JANELA DE COMPRA DE TERRENO
# ============================================================================
func mostrar_painel_compra(nome_casa: String, preco: int, saldo_atual: int):
								lbl_acao_titulo.text = "PROPRIEDADE LIVRE\n" + nome_casa.to_upper()
								lbl_acao_preco.text = "VALOR: $" + str(preco)

								if saldo_atual >= preco:
																btn_comprar.disabled = false
																btn_comprar.text = "COMPRAR ($" + str(preco) + ")"
																btn_comprar.modulate = Color(1.0, 1.0, 1.0)
								else:
																btn_comprar.disabled = true
																btn_comprar.text = "SALDO INSUFICIENTE"
																btn_comprar.modulate = Color(0.5, 0.5, 0.5)

								painel_acao.visible = true
								var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
								tween.tween_property(painel_acao, "modulate:a", 1.0, 0.3)

func _responder_acao_terreno(comprou: bool):
								var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
								tween.tween_property(painel_acao, "modulate:a", 0.0, 0.2)
								await tween.finished
								painel_acao.visible = false
								emit_signal("acao_terreno_escolhida", comprou)

# ============================================================================
# SISTEMA DE LEILÃO
# ============================================================================
func abrir_janela_leilao(nome_casa: String, lance_minimo: int = 0):
	if _modo_espectador:
		painel_leilao.visible = false
		return
	_lance_minimo_interface = max(0, lance_minimo)
	lbl_leilao_titulo.text = "LEILÃO:\n" + nome_casa.to_upper()
	if _lance_minimo_interface > 0:
		lbl_leilao_titulo.text += "\nLANCE MÍNIMO: $" + str(_lance_minimo_interface)
	input_lance.text = ""
	input_lance.placeholder_text = "0 para passar" if _lance_minimo_interface <= 0 else "Mínimo $%d ou 0 para passar" % _lance_minimo_interface
	btn_enviar_lance.disabled = false
	btn_enviar_lance.text = "ENVIAR LANCE"
	painel_leilao.visible = true
	var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(painel_leilao, "modulate:a", 1.0, 0.3)

func _on_botao_enviar_lance():
	if _modo_espectador:
		return
	var valor = max(0, input_lance.text.to_int())
	if valor > 0 and valor < _lance_minimo_interface:
		btn_enviar_lance.text = "MÍNIMO $" + str(_lance_minimo_interface)
		input_lance.grab_focus()
		return
	btn_enviar_lance.disabled = true
	btn_enviar_lance.text = "AGUARDANDO..."
	emit_signal("lance_leilao_enviado", valor)


func fechar_janela_leilao():
								var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
								tween.tween_property(painel_leilao, "modulate:a", 0.0, 0.2)
								await tween.finished
								painel_leilao.visible = false

# ============================================================================
# ANIMAÇÃO DE COMPRA DE CARTAS
# ============================================================================
func mostrar_carta_sorteada(deck: String, nome: String, desc: String):
								# --- NOVO: Animação de flip 3D (eixo Y) ---
								# Esconde o conteúdo até a metade do flip
								for n in painel_carta.get_children():
																if n is VBoxContainer:
																								n.modulate.a = 0.0
								
								lbl_carta_deck.text = deck.to_upper()
								lbl_carta_nome.text = nome.to_upper()
								lbl_carta_desc.text = desc
								
								if deck == "Destino da Cidade":
																lbl_carta_deck.add_theme_color_override("font_color", Color(0.85, 0.25, 0.85))
								else:
																lbl_carta_deck.add_theme_color_override("font_color", Color(0.95, 0.65, 0.15))
								
								# Começa "de lado" (scale.x = 0) e girada
								painel_carta.scale = Vector2(0.0, 1.0)
								painel_carta.modulate.a = 1.0
								painel_carta.visible = true

								# --- CORREÇÃO: Define TODO o tween de entrada ANTES de começar a rodar.
								#     No Godot 4, não pode adicionar tween_property a um tween já started. ---
								var tween_in = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
								# Primeira metade do flip: scale 0 -> 1.15 (vira)
								tween_in.tween_property(painel_carta, "scale", Vector2(1.15, 1.15), 0.18)
								# No meio do flip, revela o conteúdo (callback)
								tween_in.tween_callback(_revelar_conteudo_carta)
								# Segunda metade: scale 1.15 -> 1.0 (assenta)
								tween_in.tween_property(painel_carta, "scale", Vector2(1.0, 1.0), 0.15)

								await tween_in.finished

								await get_tree().create_timer(4.5).timeout
								
								# Saída: gira e some (flip reverso)
								var tween_out = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
								tween_out.tween_property(painel_carta, "scale", Vector2(0.0, 1.0), 0.3)
								tween_out.parallel().tween_property(painel_carta, "modulate:a", 0.0, 0.3)
								await tween_out.finished
								painel_carta.visible = false

# --- Callback: revela o conteúdo da carta no meio do flip ---
func _revelar_conteudo_carta():
								for n in painel_carta.get_children():
																if n is VBoxContainer:
																								n.modulate.a = 1.0

# ============================================================================
# CARTAS GUARDADAS DO JOGADOR
# ============================================================================
func atualizar_cartas_guardadas(cartas_casa_gratis: int, cartas_sair_prisao: int) -> void:
	_qtd_cartas_casa_gratis = maxi(0, cartas_casa_gratis)
	_qtd_cartas_sair_prisao = maxi(0, cartas_sair_prisao)
	_atualizar_textos_cartas_guardadas()


func _atualizar_textos_cartas_guardadas() -> void:
	if btn_cartas_guardadas == null or not is_instance_valid(btn_cartas_guardadas):
		return
	var total: int = _qtd_cartas_casa_gratis + _qtd_cartas_sair_prisao
	var seta: String = "▲" if _cartas_guardadas_aberto else "▼"
	btn_cartas_guardadas.text = "CARTAS GUARDADAS: %d  %s" % [total, seta]

	if label_carta_casa_gratis != null and is_instance_valid(label_carta_casa_gratis):
		label_carta_casa_gratis.text = "CONSTRUIR GRÁTIS  x%d" % _qtd_cartas_casa_gratis
		label_carta_casa_gratis.modulate.a = 1.0 if _qtd_cartas_casa_gratis > 0 else 0.55
	if label_carta_sair_prisao != null and is_instance_valid(label_carta_sair_prisao):
		label_carta_sair_prisao.text = "SAIR DA PRISÃO  x%d" % _qtd_cartas_sair_prisao
		label_carta_sair_prisao.modulate.a = 1.0 if _qtd_cartas_sair_prisao > 0 else 0.55


func _on_btn_cartas_guardadas_pressed() -> void:
	if _modo_espectador:
		return
	_cartas_guardadas_aberto = not _cartas_guardadas_aberto
	_atualizar_textos_cartas_guardadas()
	if _cartas_guardadas_aberto:
		_animar_abertura_painel(painel_cartas_guardadas, Vector2(0.98, 0.92), 0.22)
	else:
		_animar_fechamento_painel(painel_cartas_guardadas, Vector2(0.99, 0.96), 0.16)


# ============================================================================
# SISTEMA DE CONSTRUÇÃO DE CASAS E HOTÉIS
# ============================================================================
func _on_botao_abrir_construcao_pressed():
	if _modo_espectador:
		return
	construcao_aberta = !construcao_aberta
	btn_abrir_construcao.text = "GESTÃO DE\nPROPRIEDADES ▲" if construcao_aberta else "GESTÃO DE\nPROPRIEDADES ▼"
	if construcao_aberta:
		_animar_abertura_painel(panel_construcao, Vector2(0.98, 0.93), 0.26)
	else:
		_animar_fechamento_painel(panel_construcao, Vector2(0.99, 0.96), 0.17)

func _on_btn_fechar_painel_pressed():
	construcao_aberta = false
	btn_abrir_construcao.text = "GESTÃO DE\nPROPRIEDADES ▼"
	_animar_fechamento_painel(panel_construcao, Vector2(0.99, 0.96), 0.17)

func popular_menu_construcao(propriedades: Array):
								for child in lista_construcao.get_children():
																child.queue_free()

								# --- Cabeçalho do painel ---
								var cabecalho = Label.new()
								cabecalho.text = "=== SUAS PROPRIEDADES ==="
								cabecalho.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
								cabecalho.add_theme_font_size_override("font_size", 16)
								cabecalho.add_theme_color_override("font_color", Color(0.95, 0.85, 0.15))
								cabecalho.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
								lista_construcao.add_child(cabecalho)

								if propriedades.is_empty():
																var lbl = Label.new()
																lbl.text = "\nVOCÊ AINDA NÃO TEM\nPROPRIEDADES.\n\nCOMPRE TERRENOS\nPARA COMEÇAR."
																lbl.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
																lbl.add_theme_font_size_override("font_size", 14)
																lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
																lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
																lbl.custom_minimum_size = Vector2(0, 200)
																lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
																lista_construcao.add_child(lbl)
																return

								for prop in propriedades:
																# --- Card container para cada propriedade ---
																var card = PanelContainer.new()
																card.name = "CardPropriedade_%d" % int(prop["id"])
																card.custom_minimum_size = Vector2(0, 0)
																var sb_card = StyleBoxFlat.new()
																sb_card.bg_color = Color(0.08, 0.08, 0.10, 0.95)
																sb_card.border_width_left = 4
																sb_card.border_width_right = 4
																sb_card.border_width_top = 4
																sb_card.border_width_bottom = 4
																sb_card.border_color = prop["cor"]
																sb_card.corner_radius_top_left = 6
																sb_card.corner_radius_top_right = 6
																sb_card.corner_radius_bottom_left = 6
																sb_card.corner_radius_bottom_right = 6
																sb_card.content_margin_left = 12
																sb_card.content_margin_right = 12
																sb_card.content_margin_top = 10
																sb_card.content_margin_bottom = 10
																card.add_theme_stylebox_override("panel", sb_card)
																lista_construcao.add_child(card)

																# VBox interna
																var vbox_card = VBoxContainer.new()
																vbox_card.add_theme_constant_override("separation", 6)
																card.add_child(vbox_card)

																# --- Linha 1: Nome + faixa de cor do grupo ---
																var hbox_topo = HBoxContainer.new()
																hbox_topo.add_theme_constant_override("separation", 8)
																vbox_card.add_child(hbox_topo)

																# Faixa de cor do grupo
																var faixa = ColorRect.new()
																faixa.custom_minimum_size = Vector2(8, 28)
																faixa.color = prop["cor"]
																faixa.size_flags_vertical = Control.SIZE_FILL
																hbox_topo.add_child(faixa)

																var lbl_nome = Label.new()
																var nome_limpo = prop["nome"].replace("\n", " ")
																lbl_nome.text = nome_limpo.to_upper()
																lbl_nome.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
																lbl_nome.add_theme_font_size_override("font_size", 14)
																lbl_nome.add_theme_color_override("font_color", Color(1, 1, 1))
																lbl_nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
																lbl_nome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
																hbox_topo.add_child(lbl_nome)

																# --- Linha 2: Nível de construção (barras visuais) ---
																var hbox_nivel = HBoxContainer.new()
																hbox_nivel.add_theme_constant_override("separation", 4)
																vbox_card.add_child(hbox_nivel)

																var lbl_nivel_txt = Label.new()
																lbl_nivel_txt.text = "NÍVEL:"
																lbl_nivel_txt.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
																lbl_nivel_txt.add_theme_font_size_override("font_size", 11)
																lbl_nivel_txt.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
																hbox_nivel.add_child(lbl_nivel_txt)

																# 5 barrinhas representando o nível (1-5)
																var nivel = prop.get("nivel", 0)
																for i in range(5):
																								var barra = ColorRect.new()
																								barra.custom_minimum_size = Vector2(20, 14)
																								if i < nivel:
																																if nivel == 5:
																																								barra.color = Color(1.0, 0.85, 0.15)  # Dourado para hotel
																																else:
																																								barra.color = prop["cor"]
																								else:
																																barra.color = Color(0.2, 0.2, 0.2, 0.5)
																								hbox_nivel.add_child(barra)

																var lbl_nivel_num = Label.new()
																if nivel == 5:
																								lbl_nivel_num.text = "HOTEL"
																								lbl_nivel_num.add_theme_color_override("font_color", Color(1.0, 0.85, 0.15))
																else:
																								lbl_nivel_num.text = str(nivel) + "/5"
																								lbl_nivel_num.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
																lbl_nivel_num.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
																lbl_nivel_num.add_theme_font_size_override("font_size", 11)
																hbox_nivel.add_child(lbl_nivel_num)

																# --- Linha 3: Aluguel atual + custo de construção ---
																var hbox_info = HBoxContainer.new()
																hbox_info.add_theme_constant_override("separation", 12)
																vbox_card.add_child(hbox_info)

																var lbl_aluguel = Label.new()
																lbl_aluguel.text = "ALUGUEL: $" + str(prop.get("aluguel_atual", 0))
																lbl_aluguel.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
																lbl_aluguel.add_theme_font_size_override("font_size", 11)
																lbl_aluguel.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
																lbl_aluguel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
																hbox_info.add_child(lbl_aluguel)

																# --- Linha 4: Estado de hipoteca (se aplicável) ---
																if prop.get("hipotecada", false):
																								var lbl_hip = Label.new()
																								lbl_hip.text = "HIPOTECADA — Sem aluguel"
																								lbl_hip.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
																								lbl_hip.add_theme_font_size_override("font_size", 11)
																								lbl_hip.add_theme_color_override("font_color", Color(0.95, 0.6, 0.2))
																								vbox_card.add_child(lbl_hip)

																# --- Linha 5: Botões de ação ---
																var hbox_botoes = HBoxContainer.new()
																hbox_botoes.add_theme_constant_override("separation", 8)
																vbox_card.add_child(hbox_botoes)

																# Botão CONSTRUIR
																var btn_construir = Button.new()
																btn_construir.name = "BtnConstruir_%d" % int(prop["id"])
																btn_construir.custom_minimum_size = Vector2(0, 56)
																btn_construir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
																btn_construir.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
																btn_construir.add_theme_font_size_override("font_size", 12)
																if not prop.get("pode_construir", false):
																								# Transporte/Utilidade ou sem monopólio — não pode construir
																								btn_construir.text = "NÃO PODE\nCONSTRUIR"
																								btn_construir.disabled = true
																								btn_construir.modulate = Color(0.5, 0.5, 0.5)
																elif nivel >= 5:
																								btn_construir.text = "HOTEL MÁX."
																								btn_construir.disabled = true
																								btn_construir.modulate = Color(0.5, 0.5, 0.5)
																elif prop.get("hipotecada", false):
																								btn_construir.text = "HIPOTECADA"
																								btn_construir.disabled = true
																								btn_construir.modulate = Color(0.5, 0.5, 0.5)
																elif prop.get("usar_carta_gratis", false):
																	btn_construir.text = "CONSTRUIR\nGRÁTIS"
																	btn_construir.add_theme_color_override("font_color", Color(0.55, 1.0, 0.62))
																	btn_construir.add_theme_color_override("font_hover_color", Color(0.78, 1.0, 0.82))
																	btn_construir.tooltip_text = "Usará 1 carta de construção gratuita."
																	btn_construir.pressed.connect(_avisar_construcao.bind(prop["id"]))
																elif prop["custo"] > prop["saldo_jogador"]:
																	btn_construir.text = "SEM $ (" + str(prop["custo"]) + ")"
																	btn_construir.disabled = true
																	btn_construir.modulate = Color(0.5, 0.5, 0.5)
																else:
																	btn_construir.text = "CONSTRUIR ($" + str(prop["custo"]) + ")"
																	btn_construir.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
																	btn_construir.pressed.connect(_avisar_construcao.bind(prop["id"]))
																hbox_botoes.add_child(btn_construir)

																# Botão HIPOTECAR / RESGATAR
																var btn_hipoteca = Button.new()
																btn_hipoteca.custom_minimum_size = Vector2(160, 56)
																btn_hipoteca.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
																btn_hipoteca.add_theme_font_size_override("font_size", 11)
																if prop.get("hipotecada", false):
																								var custo_resgate = int(prop.get("valor_resgate", 0))
																								btn_hipoteca.text = "RESGATAR\n$" + str(custo_resgate)
																								if custo_resgate > prop["saldo_jogador"]:
																																btn_hipoteca.disabled = true
																																btn_hipoteca.modulate = Color(0.5, 0.5, 0.5)
																								else:
																																btn_hipoteca.add_theme_color_override("font_color", Color(0.4, 0.95, 0.4))
																								btn_hipoteca.pressed.connect(_avisar_hipoteca.bind(prop["id"]))
																else:
																								btn_hipoteca.text = "HIPOTECAR\n+$" + str(prop.get("valor_hipoteca", 0))
																								btn_hipoteca.add_theme_color_override("font_color", Color(0.95, 0.6, 0.2))
																								btn_hipoteca.pressed.connect(_avisar_hipoteca.bind(prop["id"]))
																hbox_botoes.add_child(btn_hipoteca)

																# --- CORREÇÃO: Define IGNORE em todos os elementos não-botão do card,
																#     para que o arraste sobre o card passe para o ScrollContainer e faça scroll. ---
																_set_ignore_except_interactive(card)

								# --- NOVO (Fase 2 — Imunidades): mostra imunidades ativas do jogador
								#     local logo acima do rodapé. Cada imunidade mostra contra quem
								#     é, quantas visitas restam e quantos turnos restam. ---
								var meu_id_imunidades = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
								if meu_id_imunidades != "":
																var tabuleiro_imun = get_tree().get_first_node_in_group("tabuleiro_principal")
																if tabuleiro_imun and tabuleiro_imun.has_method("fornecer_dados_para_negociacao"):
																								var refs_imun = tabuleiro_imun.fornecer_dados_para_negociacao()
																								var dados_local = refs_imun.dados_jogadores.get(meu_id_imunidades, {})
																								var imunidades_ativas = dados_local.get("imunidades", [])
																								if imunidades_ativas.size() > 0:
																																var lbl_titulo_imun = Label.new()
																																lbl_titulo_imun.text = "\n=== IMUNIDADES ATIVAS ==="
																																lbl_titulo_imun.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
																																lbl_titulo_imun.add_theme_font_size_override("font_size", 12)
																																lbl_titulo_imun.add_theme_color_override("font_color", Color(0.4, 1.0, 0.8))
																																lbl_titulo_imun.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
																																lista_construcao.add_child(lbl_titulo_imun)

																																for imun in imunidades_ativas:
																																								var de_nome = refs_imun.dados_jogadores.get(imun.get("de", ""), {}).get("nome", imun.get("de", ""))
																																								var lbl_imun = Label.new()
																																								lbl_imun.text = "🛡 vs " + de_nome.to_upper() + "  |  " + str(imun.get("visitas_restantes", 0)) + " visita(s)  |  " + str(imun.get("turnos_restantes", 0)) + "T"
																																								lbl_imun.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
																																								lbl_imun.add_theme_font_size_override("font_size", 11)
																																								lbl_imun.add_theme_color_override("font_color", Color(0.6, 0.95, 0.85))
																																								lbl_imun.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
																																								lista_construcao.add_child(lbl_imun)

								# --- Rodapé com total de propriedades ---
								var rodape = Label.new()
								rodape.text = "\nTOTAL: " + str(propriedades.size()) + " PROPS"
								rodape.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
								rodape.add_theme_font_size_override("font_size", 12)
								rodape.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
								rodape.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
								lista_construcao.add_child(rodape)


func obter_botao_construir(casa_id: int) -> Button:
	if lista_construcao == null or not is_instance_valid(lista_construcao):
		return null
	var encontrados: Array[Node] = lista_construcao.find_children(
		"BtnConstruir_%d" % casa_id,
		"Button",
		true,
		false
	)
	for encontrado: Node in encontrados:
		if encontrado is Button and not encontrado.is_queued_for_deletion():
			return encontrado as Button
	return null

# Gatilho individual por botão
func _avisar_construcao(casa_id: int):
								emit_signal("solicitar_construcao", casa_id)

func _avisar_hipoteca(casa_id: int):
								emit_signal("solicitar_hipoteca", casa_id)

# ============================================================================
# NOVO: EVENTO GLOBAL CINEMÁTICO — banner deslizante + dim
# ============================================================================
# --- CORREÇÃO: Overlay DEDICADO para o evento cinemático.
#     Antes, esta função usava overlay_escuro (o mesmo nó que serve de fundo
#     para os dados). Quando um evento global aparecia junto com os dados
#     (ou enquanto os dados ainda estavam visíveis), o undim no final
#     escondia o overlay_escuro, fazendo o fundo preto dos dados sumir.
#     Agora criamos um ColorRect temporário só para o evento, e o
#     overlay_escuro dos dados permanece intocado. ---
func revelar_evento_cinematico(nome_evento: String, descricao: String, cor: Color = Color(0.95, 0.3, 0.3)):
								# Cria overlay temporário DEDICADO para o evento (não toca no overlay_escuro dos dados)
								var overlay_evento = ColorRect.new()
								overlay_evento.color = Color(0, 0, 0, 0.75)
								overlay_evento.set_anchors_preset(Control.PRESET_FULL_RECT)
								overlay_evento.mouse_filter = Control.MOUSE_FILTER_IGNORE
								overlay_evento.modulate.a = 0.0
								# z_index alto para garantir que fique à frente de toda a UI durante o cinematic
								overlay_evento.z_index = 90
								$Control.add_child(overlay_evento)
								
								# Dim parcial (apenas no overlay dedicado)
								var t_dim = create_tween()
								t_dim.tween_property(overlay_evento, "modulate:a", 1.0, 0.3)
								
								# Banner cinemático via Animacoes (adicionado depois, fica por cima do overlay_evento)
								Animacoes.banner_cinematico($Control, "EVENTO GLOBAL", nome_evento, cor, 3.0)
								
								await get_tree().create_timer(3.5).timeout
								
								# Remove o dim APENAS do overlay do evento (overlay_escuro dos dados fica intacto)
								var t_undim = create_tween()
								t_undim.tween_property(overlay_evento, "modulate:a", 0.0, 0.4)
								await t_undim.finished
								overlay_evento.queue_free()
								
								# Atualiza painel permanente de evento no topo
								atualizar_evento_global(nome_evento, false, descricao)

# ============================================================================
# NOVO: OVERLAY DE HABILIDADE ATIVA — exibe nome + descrição e aguarda alvo
# ============================================================================

# --- NOVO (UI de seleção de alvo): cria o ScrollContainer e VBox que vão
#     conter a lista de botões de alvo. Inserido entre a Descrição e os
#     botões Cancelar/Confirmar dentro do PainelHab. ---
func _criar_lista_alvos_habilidade():
								# Cria o ScrollContainer
								scroll_alvos_hab = ScrollContainer.new()
								scroll_alvos_hab.name = "ScrollAlvos"
								scroll_alvos_hab.custom_minimum_size = Vector2(700, 240)
								scroll_alvos_hab.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
								scroll_alvos_hab.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
								scroll_alvos_hab.visible = false  # invisível por padrão
								# Cria o VBox dentro do ScrollContainer
								vbox_alvos_hab = VBoxContainer.new()
								vbox_alvos_hab.name = "VBoxAlvos"
								vbox_alvos_hab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
								vbox_alvos_hab.add_theme_constant_override("separation", 6)
								scroll_alvos_hab.add_child(vbox_alvos_hab)
								# Cria um Label para a mensagem "sem alvos válidos"
								label_sem_alvos_hab = Label.new()
								label_sem_alvos_hab.name = "LabelSemAlvos"
								label_sem_alvos_hab.text = "Nenhum alvo válido disponível."
								label_sem_alvos_hab.add_theme_color_override("font_color", Color(0.9, 0.5, 0.3))
								label_sem_alvos_hab.add_theme_font_size_override("font_size", 14)
								label_sem_alvos_hab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
								label_sem_alvos_hab.visible = false
								# Insere ambos ANTES do HBoxBotoesHab (que é o último filho do VBox)
								var vbox_pai = painel_hab.get_node("VBox")
								vbox_pai.add_child(scroll_alvos_hab)
								vbox_pai.add_child(label_sem_alvos_hab)
								# Move ambos para ANTES do HBoxBotoesHab
								var idx_botoes = vbox_pai.get_node("HBoxBotoesHab").get_index()
								vbox_pai.move_child(scroll_alvos_hab, idx_botoes)
								vbox_pai.move_child(label_sem_alvos_hab, idx_botoes)

func mostrar_overlay_habilidade(id_personagem: String, nome_hab: String, desc_hab: String, cor_personagem: Color):
								# Desconecta o callback de fiança se estiver conectado (para evitar duplo disparo)
								if btn_confirmar_hab.pressed.is_connected(_on_btn_fianca_pressed):
																btn_confirmar_hab.pressed.disconnect(_on_btn_fianca_pressed)
								habilidade_em_selecao = true
								habilidade_id_ativa = id_personagem
								casa_id_selecionada_hab = -1
								alvo_id_selecionado_hab = ""
								btn_alvo_selecionado = null

								lbl_hab_titulo.text = "HABILIDADE DE " + id_personagem.to_upper()
								lbl_hab_titulo.add_theme_color_override("font_color", cor_personagem)
								lbl_hab_nome.text = nome_hab.to_upper()
								lbl_hab_desc.text = desc_hab

								# Botão de confirmar começa desabilitado (precisa escolher alvo)
								btn_confirmar_hab.disabled = true
								btn_confirmar_hab.text = "SELECIONE UM ALVO"

								overlay_habilidade.visible = true
								overlay_habilidade.modulate.a = 0.0
								painel_hab.scale = Vector2(0.7, 0.7)

								var tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
								tween.parallel().tween_property(overlay_habilidade, "modulate:a", 1.0, 0.3)
								tween.parallel().tween_property(painel_hab, "scale", Vector2(1.0, 1.0), 0.4)

								# Fundo escurecido
								fundo_hab.color = Color(0, 0, 0, 0.55)

								# Conecta o botão confirmar
								if not btn_confirmar_hab.pressed.is_connected(_on_confirmar_habilidade):
																btn_confirmar_hab.pressed.connect(_on_confirmar_habilidade)

# --- NOVO (UI de seleção de alvo): mostra o overlay já populado com a
#     lista de alvos válidos. Chamado pelo tabuleiro após computar as opções. ---
func mostrar_overlay_habilidade_com_alvos(id_personagem: String, nome_hab: String, desc_hab: String, cor_personagem: Color, opcoes: Array):
								mostrar_overlay_habilidade(id_personagem, nome_hab, desc_hab, cor_personagem)
								popular_lista_alvos(opcoes)

# --- NOVO (UI de seleção de alvo): popula o VBoxAlvos com um botão para
#     cada opção de alvo. Cada opção é um Dictionary com:
#       - "texto": texto completo do botão (com info extra)
#       - "texto_curto": texto curto para o botão Confirmar
#       - "alvo_id": ID do jogador alvo (string, pode ser "")
#       - "casa_id": ID da casa alvo (int, pode ser -1)
#       - "cor": cor opcional do botão (Color) ---
func popular_lista_alvos(opcoes: Array):
								# Limpa lista anterior
								if vbox_alvos_hab == null:
																return
								for child in vbox_alvos_hab.get_children():
																child.queue_free()
								btn_alvo_selecionado = null
								# Se não há opções, mostra mensagem e mantém confirmar desabilitado
								if opcoes.is_empty():
																scroll_alvos_hab.visible = false
																label_sem_alvos_hab.visible = true
																btn_confirmar_hab.disabled = true
																btn_confirmar_hab.text = "SEM ALVO VÁLIDO — CANCELE"
																return
								scroll_alvos_hab.visible = true
								label_sem_alvos_hab.visible = false
								# Cria um botão para cada opção
								for opt in opcoes:
																var btn = Button.new()
																btn.text = opt.get("texto", "?")
																btn.custom_minimum_size = Vector2(660, 68)
																btn.add_theme_font_size_override("font_size", 18)
																btn.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03, 1.0))
																btn.add_theme_constant_override("outline_size", 3)
																btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
																btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
																# Cor opcional do botão
																if opt.has("cor"):
																								btn.add_theme_color_override("font_color", opt["cor"])
																# Estado normal: levemente translúcido
																btn.modulate = Color(1, 1, 1, 0.85)
																# Captura valores para o callback (closure)
																var alvo_id_opt = opt.get("alvo_id", "")
																var casa_id_opt = opt.get("casa_id", -1)
																var texto_curto_opt = opt.get("texto_curto", opt.get("texto", ""))
																btn.pressed.connect(func(): _selecionar_alvo_lista(btn, alvo_id_opt, casa_id_opt, texto_curto_opt))
																vbox_alvos_hab.add_child(btn)

# --- NOVO (UI de seleção de alvo): handler interno chamado quando o
#     jogador clica em um botão da lista de alvos. ---
func _selecionar_alvo_lista(btn: Button, alvo_id: String, casa_id: int, texto_curto: String):
								# Atualiza seleção
								alvo_id_selecionado_hab = alvo_id
								casa_id_selecionada_hab = casa_id
								btn_alvo_selecionado = btn
								# Destaca visualmente o botão selecionado (amarelo brilhante)
								# e escurece os outros
								if vbox_alvos_hab:
																for c in vbox_alvos_hab.get_children():
																								if c is Button:
																																c.modulate = Color(0.6, 0.6, 0.6, 0.7)
																								if c == btn:
																																c.modulate = Color(1.0, 1.0, 0.4, 1.0)
								# Habilita o botão de confirmar
								btn_confirmar_hab.disabled = false
								btn_confirmar_hab.text = "CONFIRMAR: " + texto_curto.to_upper()

func definir_alvo_habilidade(alvo_id: String, casa_id: int):
								if not habilidade_em_selecao:
																return
								casa_id_selecionada_hab = casa_id
								alvo_id_selecionado_hab = alvo_id
								btn_confirmar_hab.disabled = false
								btn_confirmar_hab.text = "CONFIRMAR: " + alvo_id.to_upper() + " / CASA " + str(casa_id)

func _on_confirmar_habilidade():
								if not habilidade_em_selecao:
																return
								# Usa o alvo_id selecionado pelo jogador (em vez de "")
								var alvo = alvo_id_selecionado_hab
								var casa = casa_id_selecionada_hab
								# Esconde overlay
								var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
								tween.tween_property(overlay_habilidade, "modulate:a", 0.0, 0.25)
								await tween.finished
								overlay_habilidade.visible = false
								habilidade_em_selecao = false
								# Limpa a lista de alvos (esconde o scroll)
								if scroll_alvos_hab:
																scroll_alvos_hab.visible = false
																for child in vbox_alvos_hab.get_children():
																								child.queue_free()
								if label_sem_alvos_hab:
																label_sem_alvos_hab.visible = false
								emit_signal("solicitar_habilidade", alvo, casa)

# ============================================================================
# NOVO: CANCELAR HABILIDADE — fecha o overlay sem usar a habilidade
# ============================================================================
func _on_btn_cancelar_hab_pressed():
								habilidade_em_selecao = false
								habilidade_id_ativa = ""
								casa_id_selecionada_hab = -1
								alvo_id_selecionado_hab = ""
								btn_alvo_selecionado = null
								# Limpa a lista de alvos
								if scroll_alvos_hab:
																scroll_alvos_hab.visible = false
																if vbox_alvos_hab:
																								for child in vbox_alvos_hab.get_children():
																																child.queue_free()
								if label_sem_alvos_hab:
																label_sem_alvos_hab.visible = false
								var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
								tween.tween_property(overlay_habilidade, "modulate:a", 0.0, 0.25)
								await tween.finished
								overlay_habilidade.visible = false

# ============================================================================
# NOVO: HABILIDADE ATIVADA COM SUCESSO — flash + texto grande
# ============================================================================
func habilidade_ativada_sucesso(nome_hab: String, cor: Color):
								Animacoes.flash_de_tela($Control, cor, 0.6)
								Animacoes.banner_cinematico($Control, "HABILIDADE ATIVADA!", nome_hab, cor, 1.5)

# ============================================================================
# NOVO: MONOPÓLIO ALCANÇADO — banner dourado
# ============================================================================
func mostrar_monopolio(grupo: String):
								Animacoes.banner_cinematico($Control, "MONOPÓLIO!", "Grupo " + grupo + " completo", Color(1.0, 0.85, 0.15), 2.0)
								Animacoes.flash_de_tela($Control, Color(1.0, 0.85, 0.15, 0.5), 0.5)

# ============================================================================
# NOVO: BOTÃO DE HIPOTECA — exibe quando o jogador cai em propriedade própria
# ============================================================================
func mostrar_botao_hipoteca(nome_prop: String, valor_hipoteca: int, ja_hipotecada: bool = false):
								if ja_hipotecada:
																btn_hipoteca.text = "RESGATAR $" + str(int(valor_hipoteca * 1.1))
																btn_hipoteca.modulate = Color(0.4, 0.95, 0.4)
								else:
																btn_hipoteca.text = "HIPOTECAR $" + str(valor_hipoteca)
																btn_hipoteca.modulate = Color(0.95, 0.6, 0.2)
								
								container_hipoteca.visible = true
								container_hipoteca.modulate.a = 0.0
								var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
								tween.tween_property(container_hipoteca, "modulate:a", 1.0, 0.3)
								
								if not btn_hipoteca.pressed.is_connected(_on_btn_hipoteca_pressed):
																btn_hipoteca.pressed.connect(_on_btn_hipoteca_pressed)

func esconder_botao_hipoteca():
								if container_hipoteca.visible:
																var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
																tween.tween_property(container_hipoteca, "modulate:a", 0.0, 0.2)
																await tween.finished
																container_hipoteca.visible = false

func _on_btn_hipoteca_pressed():
								if _modo_espectador:
																return
								emit_signal("solicitar_hipoteca", -1)  # Tabuleiro sabe qual casa está em foco
								esconder_botao_hipoteca()

# ============================================================================
# BARRA DE CONTAGEM REGRESSIVA DO LEILÃO
# ============================================================================
var _tween_leilao: Tween = null
var _leilao_id_atual: int = 0  # incrementa a cada leilão — invalida timers antigos

func iniciar_barra_leilao(segundos: int = 25):
								if _modo_espectador:
																barra_leilao.visible = false
																return
								_leilao_id_atual += 1
								var meu_id = _leilao_id_atual
								# Mata tween anterior
								if _tween_leilao and _tween_leilao.is_valid():
																_tween_leilao.kill()
								barra_leilao.max_value = float(segundos)
								barra_leilao.value = float(segundos)
								barra_leilao.visible = true
								barra_leilao.modulate = Color(1, 1, 1, 1)
								_tween_leilao = create_tween().set_trans(Tween.TRANS_LINEAR)
								_tween_leilao.tween_property(barra_leilao, "value", 0.0, float(segundos))
								# Pulsa vermelho nos últimos 5 segundos — SÓ se este leilão ainda estiver ativo
								await get_tree().create_timer(float(segundos - 5)).timeout
								if barra_leilao.visible and _leilao_id_atual == meu_id:
																Animacoes.pulso_de_cor(barra_leilao, Color(1, 0.2, 0.2), 5, 0.18)

func parar_barra_leilao():
								barra_leilao.visible = false
								if _tween_leilao and _tween_leilao.is_valid():
																_tween_leilao.kill()
																_tween_leilao = null

# ============================================================================
# NOVO: CONTADOR DE RODADAS — atualiza e mostra no canto
# ============================================================================
func atualizar_round_counter(rodada: int):
								label_round.text = "RODADA " + str(rodada)
								label_round.visible = true
								label_round.modulate.a = 0.0
								var tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
								tween.tween_property(label_round, "modulate:a", 1.0, 0.3)
								tween.tween_interval(2.0)
								tween.tween_property(label_round, "modulate:a", 0.0, 0.5)

# ============================================================================
# NOVO: TELA DE FALÊNCIA — exibida quando um jogador é eliminado
# ============================================================================
func mostrar_tela_falencia(nome_jogador: String, mostrar_continuar: bool = true):
								# --- CORREÇÃO: O container_falencia começa com visible=false no .tscn.
								#     Sem torná-lo visível, o overlay adicionado como filho também
								#     fica invisível — a tela de falência nunca aparecia. ---
								container_falencia.visible = true
								# --- CORREÇÃO: O parâmetro mostrar_continuar controla se o botão
								#     "CONTINUAR ASSISTINDO" aparece. Quando o jogo acabou (vencedor
								#     declarado), os perdedores não devem ver esse botão — não há
								#     mais partida para assistir. ---
								Animacoes.tela_fim_de_jogo(container_falencia, "FALÊNCIA!", nome_jogador + " faliu e sai da partida.", Color(0.9, 0.2, 0.2), true, mostrar_continuar)

# ============================================================================
# NOVO: TELA DE VITÓRIA — último jogador em pé
# ============================================================================
func mostrar_tela_vitoria(nome_vencedor: String):
								# --- CORREÇÃO: Mesmo problema do container_falencia. ---
								container_vitoria.visible = true
								Animacoes.tela_fim_de_jogo(container_vitoria, "VITÓRIA!", nome_vencedor + " domina Metropolis!", Color(1.0, 0.85, 0.15), false)

# ============================================================================
# TELA DE DERROTA — fim da partida sem declarar o jogador como falido
# ============================================================================
func mostrar_tela_derrota(nome_jogador: String, nome_vencedor: String):
									container_falencia.visible = true
									var subtitulo = nome_jogador + " foi derrotado. " + nome_vencedor + " venceu a partida."
									Animacoes.tela_fim_de_jogo(container_falencia, "DERROTA", subtitulo, Color(0.85, 0.35, 0.35), false, false)

# ============================================================================
# NOVO: PAINEL DE PRISÃO — fiança e tentar dupla
# ============================================================================
func mostrar_painel_prisao(nome_jogador: String, tem_carta_sair: bool):
								# Desconecta o callback de habilidade se estiver conectado (para evitar duplo disparo)
								if btn_confirmar_hab.pressed.is_connected(_on_confirmar_habilidade):
																btn_confirmar_hab.pressed.disconnect(_on_confirmar_habilidade)
								# Reutiliza overlay_habilidade com texto específico
								lbl_hab_titulo.text = "VOCÊ ESTÁ PRESO"
								lbl_hab_titulo.add_theme_color_override("font_color", Color(0.85, 0.3, 0.3))
								lbl_hab_nome.text = nome_jogador.to_upper()
								var desc = "Escolha sua saída:\n• Pagar $50 de fiança\n• Tentar dupla nos dados (3 tentativas)"
								if tem_carta_sair:
																desc += "\n• Usar carta 'Sair da Cadeia Grátis'"
								lbl_hab_desc.text = desc

								btn_confirmar_hab.disabled = false
								btn_confirmar_hab.text = "USAR CARTA E SAIR" if tem_carta_sair else "PAGAR FIANÇA ($50)"

								overlay_habilidade.visible = true
								overlay_habilidade.modulate.a = 0.0
								var tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
								tween.parallel().tween_property(overlay_habilidade, "modulate:a", 1.0, 0.3)
								fundo_hab.color = Color(0, 0, 0, 0.7)

								if not btn_confirmar_hab.pressed.is_connected(_on_btn_fianca_pressed):
																btn_confirmar_hab.pressed.connect(_on_btn_fianca_pressed)

func _on_btn_fianca_pressed():
	# Aguarda a resposta autoritativa do servidor antes de fechar o painel.
	# Desabilitar imediatamente impede cliques duplos e cobranças repetidas.
	if btn_confirmar_hab.disabled:
		return
	btn_confirmar_hab.disabled = true
	emit_signal("solicitar_fianca_prisao")

func resolver_solicitacao_fianca(sucesso: bool, mensagem: String = "") -> void:
	if not sucesso:
		btn_confirmar_hab.disabled = false
		if mensagem != "":
			mostrar_aviso_turno(mensagem)
		return

	if btn_confirmar_hab.pressed.is_connected(_on_btn_fianca_pressed):
		btn_confirmar_hab.pressed.disconnect(_on_btn_fianca_pressed)
	var tween = create_tween()
	tween.tween_property(overlay_habilidade, "modulate:a", 0.0, 0.2)
	await tween.finished
	overlay_habilidade.visible = false
	overlay_habilidade.modulate.a = 1.0
	btn_confirmar_hab.disabled = false

# ============================================================================
# NOVO: AVISO DE INFLAÇÃO — pulso vermelho no saldo
# ============================================================================
func avisar_inflacao(multiplicador: float):
								Animacoes.pulso_de_cor(label_dinheiro, Color(1, 0.3, 0.3), 3, 0.2)
								Animacoes.banner_cinematico($Control, "INFLAÇÃO!", "Preços subirão em " + str(int((multiplicador - 1) * 100)) + "%", Color(1, 0.5, 0.2), 1.8)

# ============================================================================
# NOVO: HABILIDADE PRONTA — pulsa o botão de habilidade
# ============================================================================
func habilidade_pronta_aviso():
								Animacoes.pulso_de_cor(botao_hab, Color(0.4, 1.0, 0.4), 4, 0.2)

# ============================================================================
# CORREÇÃO: Define MOUSE_FILTER_IGNORE em todos os Controls que NÃO são
# interativos (botões, scroll containers, inputs). Assim, o toque sobre
# painéis de informação (labels, panels decorativos) passa direto para a
# câmera do tabuleiro, em vez de ser bloqueado.
# ============================================================================
func _set_ignore_except_interactive(no: Node):
								if no is Control:
																var c = no as Control
																# Apenas Buttons, ScrollContainers, LineEdits, ProgressBars e
																# TextEdits mantêm STOP. Todo o resto vira IGNORE.
																if not (c is Button or c is ScrollContainer or c is LineEdit or c is TextEdit or c is ProgressBar):
																								c.mouse_filter = Control.MOUSE_FILTER_IGNORE
								for child in no.get_children():
																_set_ignore_except_interactive(child)

# ============================================================================
# NOVO (Fase 4 — Promessas): SISTEMA DE PROMESSAS
# ============================================================================
# Painel retrátil que mostra todas as promessas públicas da partida.
# Qualquer jogador ativo pode criar uma promessa pública de texto livre. O
# servidor controla a duração, a conclusão, os reports e as consequências de
# reputação/XP. O conteúdo continua social: não é interpretado semanticamente.
# ============================================================================

# Toggle do painel: abre se fechado, fecha se aberto.
func _toggle_painel_promessas():
								_promessas_aberto = not _promessas_aberto
								if _promessas_aberto:
																_abrir_painel_promessas()
								else:
																_fechar_painel_promessas()

func _abrir_painel_promessas():
	_promessas_aberto = true
	if btn_toggle_promessas:
		btn_toggle_promessas.text = "📜 PROMESSAS ▲"
	if painel_promessas:
		_animar_abertura_painel(painel_promessas, Vector2(0.97, 0.92), 0.25)

func _fechar_painel_promessas():
	_promessas_aberto = false
	if btn_toggle_promessas:
		btn_toggle_promessas.text = "📜 PROMESSAS ▼"
	if painel_promessas:
		_animar_fechamento_painel(painel_promessas, Vector2(0.985, 0.95), 0.17)

func _on_criar_promessa_pressed():
								if _modo_espectador:
																return
								if input_promessa == null:
																return
								var texto = input_promessa.text.strip_edges()
								if texto == "":
																return
								var meu_id = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
								if meu_id == "":
																return
								solicitar_criar_promessa.emit(texto, meu_id)
								input_promessa.text = ""

# Atualiza a lista de promessas exibida (chamado pelo tabuleiro).
# Cada promessa é um Dictionary: { "id", "autor_id", "texto", "quebrada", "quebrada_por" }
func atualizar_painel_promessas(promessas: Array):
								if lista_promessas == null:
																return
								# Limpa lista atual
								for child in lista_promessas.get_children():
																child.queue_free()
								if promessas.is_empty():
																var lbl = Label.new()
																lbl.text = "(nenhuma promessa ainda)"
																lbl.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
																lbl.add_theme_font_size_override("font_size", 10)
																lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
																lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
																lista_promessas.add_child(lbl)
																return
								for promessa in promessas:
																var card = _criar_card_promessa(promessa)
																lista_promessas.add_child(card)

# Cria um card visual para uma promessa com duração, status e reputação.
func _criar_card_promessa(promessa: Dictionary) -> PanelContainer:
	var card = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	var status = str(promessa.get("status", "quebrada" if promessa.get("quebrada", false) else "ativa"))
	match status:
		"quebrada":
			sb.bg_color = Color(0.30, 0.10, 0.10, 0.96)
			sb.border_color = Color(0.95, 0.3, 0.3, 0.9)
		"cumprida":
			sb.bg_color = Color(0.08, 0.24, 0.12, 0.96)
			sb.border_color = Color(0.35, 0.95, 0.5, 0.9)
		"cancelada":
			sb.bg_color = Color(0.15, 0.15, 0.15, 0.96)
			sb.border_color = Color(0.55, 0.55, 0.55, 0.8)
		_:
			sb.bg_color = Color(0.12, 0.10, 0.06, 0.96)
			sb.border_color = Color(0.9, 0.8, 0.5, 0.75)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		sb.set_border_width(side, 3)
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", sb)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	card.add_child(vbox)
	var autor_id = str(promessa.get("autor_id", ""))
	var autor_nome = autor_id
	var reputacao = 50
	var tabuleiro_node = get_tree().get_first_node_in_group("tabuleiro_principal")
	if tabuleiro_node and tabuleiro_node.has_method("fornecer_dados_para_negociacao"):
		var refs = tabuleiro_node.fornecer_dados_para_negociacao()
		autor_nome = str(refs.dados_jogadores.get(autor_id, {}).get("nome", autor_id))
		reputacao = int(refs.dados_jogadores.get(autor_id, {}).get("reputacao", 50))

	var lbl_autor = Label.new()
	match status:
		"quebrada":
			lbl_autor.text = "ACORDO QUEBRADO — " + autor_nome.to_upper()
			lbl_autor.add_theme_color_override("font_color", Color(0.95, 0.4, 0.4))
		"cumprida":
			lbl_autor.text = "ACORDO CUMPRIDO — " + autor_nome.to_upper() + " (+80 XP)"
			lbl_autor.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
		"cancelada":
			lbl_autor.text = "ACORDO CANCELADO — " + autor_nome.to_upper()
			lbl_autor.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
		_:
			lbl_autor.text = "ACORDO ATIVO — " + autor_nome.to_upper()
			lbl_autor.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	lbl_autor.add_theme_font_override("font", FONTE_ESPECTADOR)
	lbl_autor.add_theme_font_size_override("font_size", 9)
	vbox.add_child(lbl_autor)

	var lbl_texto = Label.new()
	lbl_texto.text = "\"" + str(promessa.get("texto", "")) + "\""
	lbl_texto.add_theme_font_override("font", FONTE_ESPECTADOR)
	lbl_texto.add_theme_font_size_override("font_size", 10)
	lbl_texto.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	lbl_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(lbl_texto)

	var lbl_meta = Label.new()
	var restantes = int(promessa.get("turnos_restantes", 0))
	var totais = int(promessa.get("turnos_totais", 5))
	lbl_meta.text = "Reputação: %d/100 | Duração: %d/%d turnos restantes" % [reputacao, restantes, totais]
	if status == "quebrada":
		var reporter = str(promessa.get("reportada_por", ""))
		var reporter_nome = reporter
		if tabuleiro_node and tabuleiro_node.has_method("fornecer_dados_para_negociacao"):
			var refs_reporter = tabuleiro_node.fornecer_dados_para_negociacao()
			reporter_nome = str(refs_reporter.dados_jogadores.get(reporter, {}).get("nome", reporter))
		lbl_meta.text = "Penalidade: -20 reputação | Reportado por: " + reporter_nome.to_upper()
	lbl_meta.add_theme_font_override("font", FONTE_ESPECTADOR)
	lbl_meta.add_theme_font_size_override("font_size", 8)
	lbl_meta.add_theme_color_override("font_color", Color(0.72, 0.72, 0.72))
	lbl_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(lbl_meta)

	if status == "ativa" and not _modo_espectador:
		var hbox = HBoxContainer.new()
		hbox.alignment = BoxContainer.ALIGNMENT_END
		vbox.add_child(hbox)
		var btn_quebrar = Button.new()
		var meu_id = str(Global.escolhas_da_mesa.get(Global.meu_peer_id, ""))
		btn_quebrar.text = "ADMITIR QUEBRA" if meu_id == autor_id else "REPORTAR QUEBRA"
		btn_quebrar.custom_minimum_size = Vector2(0, 32)
		btn_quebrar.add_theme_font_override("font", FONTE_ESPECTADOR)
		btn_quebrar.add_theme_font_size_override("font_size", 8)
		btn_quebrar.add_theme_color_override("font_color", Color(0.95, 0.5, 0.3))
		btn_quebrar.pressed.connect(_on_quebrar_promessa_pressed.bind(str(promessa.get("id", ""))))
		hbox.add_child(btn_quebrar)
	return card

# Handler do botão "MARCAR QUEBRADA" — emite signal.
func _on_quebrar_promessa_pressed(id_promessa: String):
								if _modo_espectador:
																return
								solicitar_quebrar_promessa.emit(id_promessa)

# ============================================================================
# NOVO (Eleições Municipais): SISTEMA DE VOTAÇÃO
# ============================================================================
# Mostra o painel de votação com 3 cards clicáveis.
# cor_jogador: a cor do personagem local (para o bloco de feedback).
func _cancelar_tween_votacao() -> void:
	if _tween_votacao and _tween_votacao.is_valid():
		_tween_votacao.kill()
	_tween_votacao = null

func mostrar_painel_votacao(cor_jogador: Color, total_eleitores: int = 0):
	if _modo_espectador:
		if overlay_votacao:
			overlay_votacao.visible = false
		return
	if overlay_votacao == null:
		return
	_cancelar_tween_votacao()
	_votacao_ja_votou = false
	_total_eleitores_votacao = max(0, total_eleitores)
	_votos_visiveis_votacao = 0
	label_timer_votacao.text = "20s"
	label_timer_votacao.add_theme_color_override("font_color", Color(0.9, 0.5, 0.3))
	label_subtitulo_votacao.text = "Vote no pacote de políticas — 0/%d votos" % _total_eleitores_votacao

	for child in hbox_votos_votacao.get_children():
		child.queue_free()
	if not _cards_votacao_criados:
		_criar_cards_votacao(cor_jogador)
		_cards_votacao_criados = true
	else:
		_reabilitar_cards_votacao()

	# Modal verdadeiro: bloqueia cliques/toques no tabuleiro e na HUD inferior.
	overlay_votacao.mouse_filter = Control.MOUSE_FILTER_STOP
	fundo_votacao.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_votacao.visible = true
	overlay_votacao.modulate = Color.WHITE
	fundo_votacao.modulate.a = 0.0
	painel_votacao.modulate.a = 0.0
	painel_votacao.scale = Vector2(0.94, 0.94)
	await get_tree().process_frame
	painel_votacao.pivot_offset = painel_votacao.size * 0.5

	_tween_votacao = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween_votacao.tween_property(fundo_votacao, "modulate:a", 1.0, 0.22)
	_tween_votacao.tween_property(painel_votacao, "modulate:a", 1.0, 0.24)
	_tween_votacao.tween_property(painel_votacao, "scale", Vector2.ONE, 0.28)

func _criar_cards_votacao(cor_jogador: Color):
	if hbox_cards_votacao == null:
		return
	for child in hbox_cards_votacao.get_children():
		child.queue_free()
	var pacotes = [
		{
			"nome": "POPULISTA",
			"cor": Color(0.9, 0.3, 0.2),
			"desc": "-20% no aluguel dos\ndois grupos mais caros.\nOs dois grupos mais pobres\nganham +2 casas.\nPolítica permanente.",
			"id": "populista"
		},
		{
			"nome": "LIBERAL",
			"cor": Color(0.3, 0.7, 0.3),
			"desc": "Construções custam\n25% menos e não exigem\nmonopólio durante\n2 turnos.",
			"id": "liberal"
		},
		{
			"nome": "CONSERVADOR",
			"cor": Color(0.5, 0.4, 0.8),
			"desc": "Partida passa a pagar $300.\nImposto único de 10%\nsobre o valor recebido\nnas hipotecas.\nPolítica permanente.",
			"id": "conservador"
		}
	]
	for pacote in pacotes:
		hbox_cards_votacao.add_child(_criar_card_votacao(pacote, cor_jogador))

func _criar_card_votacao(pacote: Dictionary, cor_jogador: Color) -> PanelContainer:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(285, 260)
	card.focus_mode = Control.FOCUS_ALL
	card.tooltip_text = "Votar no pacote " + str(pacote["nome"])
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.10, 0.98)
	sb.border_width_left = 4
	sb.border_width_top = 4
	sb.border_width_right = 4
	sb.border_width_bottom = 4
	sb.border_color = pacote["cor"]
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	card.add_child(vbox)
	var lbl_nome = Label.new()
	lbl_nome.text = pacote["nome"]
	lbl_nome.add_theme_color_override("font_color", pacote["cor"])
	lbl_nome.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
	lbl_nome.add_theme_font_size_override("font_size", 18)
	lbl_nome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl_nome)

	var lbl_desc = Label.new()
	lbl_desc.text = pacote["desc"]
	lbl_desc.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88))
	lbl_desc.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
	lbl_desc.add_theme_font_size_override("font_size", 13)
	lbl_desc.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03, 1.0))
	lbl_desc.add_theme_constant_override("outline_size", 2)
	lbl_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(lbl_desc)

	var pacote_id = str(pacote["id"])
	card.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_card_votacao_clicado(pacote_id, card)
		elif event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_SPACE]:
			_on_card_votacao_clicado(pacote_id, card)
	)
	return card

func _reabilitar_cards_votacao():
	if hbox_cards_votacao == null:
		return
	for card in hbox_cards_votacao.get_children():
		card.modulate = Color.WHITE
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.focus_mode = Control.FOCUS_ALL

func _on_card_votacao_clicado(pacote_id: String, card: PanelContainer):
	if _votacao_ja_votou or pacote_id not in ["populista", "liberal", "conservador"]:
		return
	_votacao_ja_votou = true
	for item in hbox_cards_votacao.get_children():
		item.modulate = Color(0.38, 0.38, 0.38, 0.65)
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.focus_mode = Control.FOCUS_NONE
	card.modulate = Color(1.0, 1.0, 0.55, 1.0)
	label_subtitulo_votacao.text = "Voto enviado. Aguardando os demais jogadores..."
	voto_eleicao_enviado.emit(pacote_id)

func mostrar_voto_recebido(cor_jogador: Color):
	if hbox_votos_votacao == null:
		return
	_votos_visiveis_votacao += 1
	if _votacao_ja_votou:
		label_subtitulo_votacao.text = "Voto enviado — %d/%d votos recebidos" % [
			_votos_visiveis_votacao, _total_eleitores_votacao
		]
	else:
		label_subtitulo_votacao.text = "Vote no pacote de políticas — %d/%d votos" % [
			_votos_visiveis_votacao, _total_eleitores_votacao
		]
	var bloco = Panel.new()
	bloco.custom_minimum_size = Vector2(34, 34)
	var sb = StyleBoxFlat.new()
	sb.bg_color = cor_jogador
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(1, 1, 1, 0.65)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	bloco.add_theme_stylebox_override("panel", sb)
	bloco.modulate.a = 0.0
	hbox_votos_votacao.add_child(bloco)
	var tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(bloco, "modulate:a", 1.0, 0.25)

func atualizar_timer_votacao(segundos_restantes: int):
	if label_timer_votacao == null:
		return
	label_timer_votacao.text = str(max(0, segundos_restantes)) + "s"
	if segundos_restantes <= 5:
		label_timer_votacao.add_theme_color_override("font_color", Color(0.95, 0.3, 0.3))
	else:
		label_timer_votacao.add_theme_color_override("font_color", Color(0.9, 0.5, 0.3))

func mostrar_resultado_eleicao(pacote_vencedor: String, foi_empate: bool, contagem: Dictionary = {}):
	if label_timer_votacao == null:
		return
	_votacao_ja_votou = true
	for card in hbox_cards_votacao.get_children():
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.focus_mode = Control.FOCUS_NONE

	var votos_txt = "POP %d  |  LIB %d  |  CONS %d" % [
		int(contagem.get("populista", 0)),
		int(contagem.get("liberal", 0)),
		int(contagem.get("conservador", 0))
	]
	label_subtitulo_votacao.text = votos_txt
	match pacote_vencedor:
		"populista":
			label_timer_votacao.text = "VENCEDOR: POPULISTA"
		"liberal":
			label_timer_votacao.text = "VENCEDOR: LIBERAL"
		"conservador":
			label_timer_votacao.text = "VENCEDOR: CONSERVADOR"
		"paralisia":
			label_timer_votacao.text = "EMPATE: PARALISIA POLÍTICA — ALUGUÉIS CONGELADOS 1T"
	label_timer_votacao.add_theme_color_override("font_color", Color(0.95, 0.85, 0.15))

	_cancelar_tween_votacao()
	painel_votacao.scale = Vector2.ONE
	_tween_votacao = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween_votacao.tween_property(painel_votacao, "scale", Vector2(1.025, 1.025), 0.12)
	_tween_votacao.tween_property(painel_votacao, "scale", Vector2.ONE, 0.16)

func fechar_painel_votacao():
	if overlay_votacao == null or not overlay_votacao.visible:
		return
	_cancelar_tween_votacao()
	_tween_votacao = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween_votacao.tween_property(fundo_votacao, "modulate:a", 0.0, 0.20)
	_tween_votacao.tween_property(painel_votacao, "modulate:a", 0.0, 0.18)
	_tween_votacao.tween_property(painel_votacao, "scale", Vector2(0.97, 0.97), 0.20)
	_tween_votacao.chain().tween_callback(func():
		overlay_votacao.visible = false
		painel_votacao.scale = Vector2.ONE
		painel_votacao.modulate.a = 1.0
		fundo_votacao.modulate.a = 1.0
	)

# ============================================================================
# EVENTOS GLOBAIS INTERATIVOS — OVERLAY REUTILIZÁVEL
# ============================================================================

func _criar_overlay_decisao_evento() -> void:
	if _decisao_evento_root != null and is_instance_valid(_decisao_evento_root):
		return

	_decisao_evento_root = Control.new()
	_decisao_evento_root.name = "DecisaoEventoOverlay"
	_decisao_evento_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_decisao_evento_root.z_index = 700
	_decisao_evento_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_decisao_evento_root.visible = false
	$Control.add_child(_decisao_evento_root)

	_decisao_evento_backdrop = ColorRect.new()
	_decisao_evento_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_decisao_evento_backdrop.color = Color(0.01, 0.01, 0.02, 0.82)
	_decisao_evento_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_decisao_evento_root.add_child(_decisao_evento_backdrop)

	var centro = CenterContainer.new()
	centro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_decisao_evento_root.add_child(centro)

	_decisao_evento_painel = PanelContainer.new()
	_decisao_evento_painel.custom_minimum_size = Vector2(900, 600)
	_decisao_evento_painel.mouse_filter = Control.MOUSE_FILTER_STOP
	centro.add_child(_decisao_evento_painel)

	var estilo = StyleBoxFlat.new()
	estilo.bg_color = Color(0.055, 0.05, 0.07, 0.99)
	estilo.border_width_left = 5
	estilo.border_width_top = 5
	estilo.border_width_right = 5
	estilo.border_width_bottom = 5
	estilo.border_color = Color(0.85, 0.55, 0.18)
	estilo.corner_radius_top_left = 12
	estilo.corner_radius_top_right = 12
	estilo.corner_radius_bottom_left = 12
	estilo.corner_radius_bottom_right = 12
	_decisao_evento_painel.add_theme_stylebox_override("panel", estilo)

	var margem = MarginContainer.new()
	margem.add_theme_constant_override("margin_left", 28)
	margem.add_theme_constant_override("margin_right", 28)
	margem.add_theme_constant_override("margin_top", 24)
	margem.add_theme_constant_override("margin_bottom", 24)
	_decisao_evento_painel.add_child(margem)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margem.add_child(vbox)

	_decisao_evento_titulo = Label.new()
	_decisao_evento_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_decisao_evento_titulo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_decisao_evento_titulo.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
	_decisao_evento_titulo.add_theme_font_size_override("font_size", 21)
	vbox.add_child(_decisao_evento_titulo)

	_decisao_evento_descricao = Label.new()
	_decisao_evento_descricao.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_decisao_evento_descricao.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_decisao_evento_descricao.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
	_decisao_evento_descricao.add_theme_font_size_override("font_size", 11)
	_decisao_evento_descricao.add_theme_color_override("font_color", Color(0.9, 0.9, 0.88))
	vbox.add_child(_decisao_evento_descricao)

	_decisao_evento_status = Label.new()
	_decisao_evento_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_decisao_evento_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_decisao_evento_status.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
	_decisao_evento_status.add_theme_font_size_override("font_size", 10)
	_decisao_evento_status.add_theme_color_override("font_color", Color(0.95, 0.78, 0.3))
	vbox.add_child(_decisao_evento_status)

	_decisao_evento_scroll = ScrollContainer.new()
	_decisao_evento_scroll.custom_minimum_size = Vector2(820, 300)
	_decisao_evento_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_decisao_evento_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_decisao_evento_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_decisao_evento_scroll)

	_decisao_evento_lista = VBoxContainer.new()
	_decisao_evento_lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_decisao_evento_lista.add_theme_constant_override("separation", 8)
	_decisao_evento_scroll.add_child(_decisao_evento_lista)

	_decisao_evento_timer = Label.new()
	_decisao_evento_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_decisao_evento_timer.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
	_decisao_evento_timer.add_theme_font_size_override("font_size", 12)
	_decisao_evento_timer.add_theme_color_override("font_color", Color(0.95, 0.55, 0.2))
	vbox.add_child(_decisao_evento_timer)

	var botoes = HBoxContainer.new()
	botoes.alignment = BoxContainer.ALIGNMENT_CENTER
	botoes.add_theme_constant_override("separation", 20)
	vbox.add_child(botoes)

	_decisao_evento_btn_recusar = Button.new()
	_decisao_evento_btn_recusar.custom_minimum_size = Vector2(300, 58)
	_decisao_evento_btn_recusar.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
	_decisao_evento_btn_recusar.add_theme_font_size_override("font_size", 12)
	_decisao_evento_btn_recusar.pressed.connect(_on_decisao_evento_recusar)
	botoes.add_child(_decisao_evento_btn_recusar)

	_decisao_evento_btn_confirmar = Button.new()
	_decisao_evento_btn_confirmar.custom_minimum_size = Vector2(300, 58)
	_decisao_evento_btn_confirmar.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
	_decisao_evento_btn_confirmar.add_theme_font_size_override("font_size", 12)
	_decisao_evento_btn_confirmar.pressed.connect(_on_decisao_evento_confirmar)
	botoes.add_child(_decisao_evento_btn_confirmar)

func mostrar_decisao_evento(
	decisao_id: int,
	titulo: String,
	descricao: String,
	opcoes: Array,
	min_selecao: int,
	max_selecao: int,
	texto_confirmar: String,
	texto_recusar: String,
	duracao_segundos: int,
	cor_destaque: Color = Color(0.9, 0.55, 0.2),
	permitir_recusar: bool = true
) -> void:
	if _modo_espectador:
		return
	_criar_overlay_decisao_evento()
	_cancelar_tween_decisao_evento()
	_decisao_evento_timer_geracao += 1
	_decisao_evento_id = decisao_id
	_decisao_evento_min = max(0, min_selecao)
	_decisao_evento_max = max(_decisao_evento_min, max_selecao)
	_decisao_evento_enviada = false
	_decisao_evento_pode_responder = true
	_decisao_evento_selecionados.clear()
	_decisao_evento_botoes.clear()

	_decisao_evento_titulo.text = titulo.to_upper()
	_decisao_evento_titulo.add_theme_color_override("font_color", cor_destaque)
	_decisao_evento_descricao.text = descricao
	_decisao_evento_status.text = "Selecione uma opção." if not opcoes.is_empty() else "Confirme sua decisão."
	_decisao_evento_btn_confirmar.text = texto_confirmar
	_decisao_evento_btn_recusar.text = texto_recusar
	# Restaura explicitamente a visibilidade após uma tela de espera anterior.
	# Isso evita que o próximo jogador receba o prompt sem botão de confirmar.
	_decisao_evento_btn_confirmar.visible = true
	_decisao_evento_btn_recusar.visible = permitir_recusar
	_decisao_evento_btn_recusar.disabled = false

	for child in _decisao_evento_lista.get_children():
		child.queue_free()

	_decisao_evento_scroll.visible = not opcoes.is_empty()
	for opcao_variant in opcoes:
		if not (opcao_variant is Dictionary):
			continue
		var opcao: Dictionary = opcao_variant
		var opcao_id = str(opcao.get("id", ""))
		if opcao_id == "":
			continue
		var botao = Button.new()
		botao.toggle_mode = true
		botao.custom_minimum_size = Vector2(0, 96)
		botao.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nome = str(opcao.get("nome", opcao_id))
		var detalhe = str(opcao.get("detalhe", ""))
		botao.text = nome if detalhe == "" else nome + "\n" + detalhe
		botao.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
		botao.add_theme_font_size_override("font_size", 16)
		botao.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03, 1.0))
		botao.add_theme_constant_override("outline_size", 3)
		botao.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		botao.disabled = not bool(opcao.get("habilitado", true))
		botao.tooltip_text = detalhe
		botao.pressed.connect(_on_opcao_decisao_evento_pressed.bind(opcao_id))
		_decisao_evento_lista.add_child(botao)
		_decisao_evento_botoes[opcao_id] = botao

	_atualizar_estado_confirmacao_decisao_evento()
	_decisao_evento_root.visible = true
	_decisao_evento_root.modulate.a = 1.0
	_decisao_evento_backdrop.modulate.a = 0.0
	_decisao_evento_painel.modulate.a = 0.0
	_decisao_evento_painel.scale = Vector2(0.94, 0.94)
	await get_tree().process_frame
	if _decisao_evento_painel != null and is_instance_valid(_decisao_evento_painel):
		_decisao_evento_painel.pivot_offset = _decisao_evento_painel.size * 0.5
	_decisao_evento_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_decisao_evento_tween.tween_property(_decisao_evento_backdrop, "modulate:a", 1.0, 0.2)
	_decisao_evento_tween.tween_property(_decisao_evento_painel, "modulate:a", 1.0, 0.24)
	_decisao_evento_tween.tween_property(_decisao_evento_painel, "scale", Vector2.ONE, 0.28)
	_iniciar_timer_decisao_evento(decisao_id, duracao_segundos, true)

func mostrar_espera_decisao_evento(
	decisao_id: int,
	titulo: String,
	descricao: String,
	duracao_segundos: int,
	cor_destaque: Color = Color(0.9, 0.55, 0.2)
) -> void:
	if _modo_espectador:
		return
	_criar_overlay_decisao_evento()
	_cancelar_tween_decisao_evento()
	_decisao_evento_timer_geracao += 1
	_decisao_evento_id = decisao_id
	_decisao_evento_enviada = true
	_decisao_evento_pode_responder = false
	_decisao_evento_selecionados.clear()
	_decisao_evento_botoes.clear()
	_decisao_evento_titulo.text = titulo.to_upper()
	_decisao_evento_titulo.add_theme_color_override("font_color", cor_destaque)
	_decisao_evento_descricao.text = descricao
	_decisao_evento_status.text = "Aguardando as decisões dos jogadores..."
	_decisao_evento_scroll.visible = false
	_decisao_evento_btn_confirmar.visible = false
	_decisao_evento_btn_recusar.visible = false
	_decisao_evento_root.visible = true
	_decisao_evento_backdrop.modulate.a = 0.0
	_decisao_evento_painel.modulate.a = 0.0
	_decisao_evento_painel.scale = Vector2(0.96, 0.96)
	await get_tree().process_frame
	_decisao_evento_painel.pivot_offset = _decisao_evento_painel.size * 0.5
	_decisao_evento_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_decisao_evento_tween.tween_property(_decisao_evento_backdrop, "modulate:a", 1.0, 0.2)
	_decisao_evento_tween.tween_property(_decisao_evento_painel, "modulate:a", 1.0, 0.24)
	_decisao_evento_tween.tween_property(_decisao_evento_painel, "scale", Vector2.ONE, 0.28)
	_iniciar_timer_decisao_evento(decisao_id, duracao_segundos, false)

func _on_opcao_decisao_evento_pressed(opcao_id: String) -> void:
	if not _decisao_evento_pode_responder or _decisao_evento_enviada:
		return
	if not _decisao_evento_botoes.has(opcao_id):
		return
	var botao: Button = _decisao_evento_botoes[opcao_id]
	if _decisao_evento_max <= 1:
		_decisao_evento_selecionados.clear()
		for id in _decisao_evento_botoes.keys():
			var outro: Button = _decisao_evento_botoes[id]
			outro.button_pressed = (str(id) == opcao_id)
		if botao.button_pressed:
			_decisao_evento_selecionados.append(opcao_id)
	else:
		if botao.button_pressed:
			if _decisao_evento_selecionados.size() >= _decisao_evento_max:
				botao.button_pressed = false
			else:
				_decisao_evento_selecionados.append(opcao_id)
		else:
			_decisao_evento_selecionados.erase(opcao_id)
	_atualizar_estado_confirmacao_decisao_evento()

func _atualizar_estado_confirmacao_decisao_evento() -> void:
	if _decisao_evento_btn_confirmar == null:
		return
	var quantidade = _decisao_evento_selecionados.size()
	var valido = quantidade >= _decisao_evento_min and quantidade <= _decisao_evento_max
	_decisao_evento_btn_confirmar.disabled = not valido or _decisao_evento_enviada
	if _decisao_evento_status != null and _decisao_evento_pode_responder:
		if _decisao_evento_min == _decisao_evento_max and _decisao_evento_max > 1:
			_decisao_evento_status.text = "Selecione %d opção(ões): %d/%d" % [_decisao_evento_max, quantidade, _decisao_evento_max]
		elif _decisao_evento_max > 1:
			_decisao_evento_status.text = "Selecione entre %d e %d: %d selecionada(s)" % [_decisao_evento_min, _decisao_evento_max, quantidade]
		elif _decisao_evento_max == 1 and _decisao_evento_min == 1:
			_decisao_evento_status.text = "Selecione uma opção." if quantidade == 0 else "Opção selecionada. Confirme sua decisão."

func _on_decisao_evento_confirmar() -> void:
	_enviar_decisao_evento("confirmar")

func _on_decisao_evento_recusar() -> void:
	_enviar_decisao_evento("recusar")

func _enviar_decisao_evento(acao: String) -> void:
	if not _decisao_evento_pode_responder or _decisao_evento_enviada:
		return
	if acao == "confirmar":
		var quantidade = _decisao_evento_selecionados.size()
		if quantidade < _decisao_evento_min or quantidade > _decisao_evento_max:
			return
	_decisao_evento_enviada = true
	_decisao_evento_btn_confirmar.disabled = true
	_decisao_evento_btn_recusar.disabled = true
	for botao_variant in _decisao_evento_botoes.values():
		var botao: Button = botao_variant
		botao.disabled = true
	_decisao_evento_status.text = "Decisão enviada. Aguardando o servidor..."
	decisao_evento_enviada.emit(_decisao_evento_id, acao, _decisao_evento_selecionados.duplicate())

func _iniciar_timer_decisao_evento(decisao_id: int, duracao_segundos: int, emitir_timeout: bool) -> void:
	_decisao_evento_timer_geracao += 1
	var geracao = _decisao_evento_timer_geracao
	var segundos = max(0, duracao_segundos)
	while segundos >= 0:
		if geracao != _decisao_evento_timer_geracao or decisao_id != _decisao_evento_id:
			return
		if _decisao_evento_root == null or not _decisao_evento_root.visible:
			return
		_decisao_evento_timer.text = "TEMPO: %ds" % segundos
		_decisao_evento_timer.add_theme_color_override("font_color", Color(0.95, 0.3, 0.3) if segundos <= 5 else Color(0.95, 0.55, 0.2))
		if segundos == 0:
			break
		await get_tree().create_timer(1.0).timeout
		segundos -= 1
	if emitir_timeout and not _decisao_evento_enviada and decisao_id == _decisao_evento_id:
		_enviar_decisao_evento("tempo_esgotado")

func mostrar_resultado_decisao_evento(decisao_id: int, texto: String, cor: Color = Color(0.4, 0.9, 0.4)) -> void:
	if _decisao_evento_root == null or decisao_id != _decisao_evento_id:
		return
	_decisao_evento_enviada = true
	_decisao_evento_pode_responder = false
	_decisao_evento_status.text = texto
	_decisao_evento_status.add_theme_color_override("font_color", cor)
	_decisao_evento_timer.text = "RESULTADO REGISTRADO"
	if _decisao_evento_btn_confirmar != null:
		_decisao_evento_btn_confirmar.disabled = true
	if _decisao_evento_btn_recusar != null:
		_decisao_evento_btn_recusar.disabled = true
	for botao_variant in _decisao_evento_botoes.values():
		var botao: Button = botao_variant
		botao.disabled = true

func fechar_decisao_evento(decisao_id: int = -1) -> void:
	if _decisao_evento_root == null or not _decisao_evento_root.visible:
		return
	if decisao_id >= 0 and decisao_id != _decisao_evento_id:
		return
	_decisao_evento_timer_geracao += 1
	_decisao_evento_pode_responder = false
	_cancelar_tween_decisao_evento()
	_decisao_evento_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_decisao_evento_tween.tween_property(_decisao_evento_backdrop, "modulate:a", 0.0, 0.18)
	_decisao_evento_tween.tween_property(_decisao_evento_painel, "modulate:a", 0.0, 0.16)
	_decisao_evento_tween.tween_property(_decisao_evento_painel, "scale", Vector2(0.97, 0.97), 0.18)
	_decisao_evento_tween.chain().tween_callback(func():
		if _decisao_evento_root != null:
			_decisao_evento_root.visible = false
		_decisao_evento_btn_confirmar.visible = true
		_decisao_evento_btn_recusar.visible = true
		_decisao_evento_btn_confirmar.disabled = false
		_decisao_evento_btn_recusar.disabled = false
		_decisao_evento_painel.scale = Vector2.ONE
		_decisao_evento_painel.modulate.a = 1.0
		_decisao_evento_backdrop.modulate.a = 1.0
	)

func _cancelar_tween_decisao_evento() -> void:
	if _decisao_evento_tween != null and _decisao_evento_tween.is_valid():
		_decisao_evento_tween.kill()
	_decisao_evento_tween = null

# ============================================================================
# AVISO DE TURNO — exibido quando uma ação exige que seja a vez do jogador
# ============================================================================
var _aviso_root: Control = null
var _aviso_backdrop: ColorRect = null
var _aviso_panel: PanelContainer = null
var _aviso_center: CenterContainer = null
var _aviso_label: Label = null
var _aviso_botao_ok: Button = null
var _aviso_tween: Tween = null
var _aviso_animacao_id: int = 0

const AVISO_ESCALA_INICIAL := Vector2(0.84, 0.84)
const AVISO_ESCALA_DESTAQUE := Vector2(1.035, 1.035)
const AVISO_COR_FUNDO := Color(0.015, 0.01, 0.02, 0.58)

func _criar_painel_aviso_turno() -> void:
	if _aviso_root != null and is_instance_valid(_aviso_root):
		return

	_aviso_root = Control.new()
	_aviso_root.name = "AvisoTurnoOverlay"
	_aviso_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_aviso_root.z_index = 600
	_aviso_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_aviso_root.visible = false
	$Control.add_child(_aviso_root)

	# Fundo escuro separado do painel. Assim o fade não altera a opacidade do texto.
	_aviso_backdrop = ColorRect.new()
	_aviso_backdrop.name = "Fundo"
	_aviso_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_aviso_backdrop.color = Color(AVISO_COR_FUNDO.r, AVISO_COR_FUNDO.g, AVISO_COR_FUNDO.b, 0.0)
	_aviso_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aviso_root.add_child(_aviso_backdrop)

	_aviso_center = CenterContainer.new()
	_aviso_center.name = "Centro"
	_aviso_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_aviso_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aviso_root.add_child(_aviso_center)

	_aviso_panel = PanelContainer.new()
	_aviso_panel.name = "Painel"
	_aviso_panel.custom_minimum_size = Vector2(540, 0)
	_aviso_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_aviso_panel.pivot_offset_ratio = Vector2(0.5, 0.5)

	var estilo_painel := StyleBoxFlat.new()
	estilo_painel.bg_color = Color(0.075, 0.025, 0.035, 0.98)
	estilo_painel.border_width_left = 4
	estilo_painel.border_width_top = 4
	estilo_painel.border_width_right = 4
	estilo_painel.border_width_bottom = 4
	estilo_painel.border_color = Color(0.95, 0.28, 0.32)
	estilo_painel.corner_radius_top_left = 10
	estilo_painel.corner_radius_top_right = 10
	estilo_painel.corner_radius_bottom_left = 10
	estilo_painel.corner_radius_bottom_right = 10
	estilo_painel.content_margin_left = 28
	estilo_painel.content_margin_right = 28
	estilo_painel.content_margin_top = 24
	estilo_painel.content_margin_bottom = 24
	_aviso_panel.add_theme_stylebox_override("panel", estilo_painel)
	_aviso_center.add_child(_aviso_panel)

	var conteudo := VBoxContainer.new()
	conteudo.name = "Conteudo"
	conteudo.add_theme_constant_override("separation", 20)
	_aviso_panel.add_child(conteudo)

	_aviso_label = Label.new()
	_aviso_label.name = "Mensagem"
	_aviso_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aviso_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_aviso_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.18))
	_aviso_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_aviso_label.add_theme_constant_override("shadow_offset_x", 2)
	_aviso_label.add_theme_constant_override("shadow_offset_y", 2)
	_aviso_label.add_theme_font_size_override("font_size", 16)
	_aviso_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_aviso_label.custom_minimum_size = Vector2(460, 54)
	if ResourceLoader.exists("res://assets/fonts/PressStart2P.ttf"):
		_aviso_label.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
	conteudo.add_child(_aviso_label)

	_aviso_botao_ok = Button.new()
	_aviso_botao_ok.name = "BotaoOK"
	_aviso_botao_ok.text = "OK"
	_aviso_botao_ok.custom_minimum_size = Vector2(160, 48)
	_aviso_botao_ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_aviso_botao_ok.add_theme_font_size_override("font_size", 13)
	_aviso_botao_ok.add_theme_color_override("font_color", Color(0.45, 1.0, 0.48))
	_aviso_botao_ok.add_theme_color_override("font_hover_color", Color(0.75, 1.0, 0.76))
	_aviso_botao_ok.add_theme_color_override("font_pressed_color", Color(0.25, 0.8, 0.3))
	if ResourceLoader.exists("res://assets/fonts/PressStart2P.ttf"):
		_aviso_botao_ok.add_theme_font_override("font", load("res://assets/fonts/PressStart2P.ttf"))
	_aviso_botao_ok.pressed.connect(fechar_aviso_turno)
	conteudo.add_child(_aviso_botao_ok)


func _atualizar_pivo_painel_aviso() -> void:
	if _aviso_panel != null and is_instance_valid(_aviso_panel):
		# O scale passa a partir do centro, evitando que o painel "salte" para um lado.
		_aviso_panel.pivot_offset = Vector2.ZERO
		_aviso_panel.pivot_offset_ratio = Vector2(0.5, 0.5)


func _cancelar_animacao_aviso() -> void:
	if _aviso_tween != null and _aviso_tween.is_valid():
		_aviso_tween.kill()
	_aviso_tween = null


func mostrar_aviso_turno(mensagem: String) -> void:
	_criar_painel_aviso_turno()
	_aviso_animacao_id += 1
	var animacao_atual := _aviso_animacao_id
	_cancelar_animacao_aviso()

	_aviso_label.text = mensagem
	_aviso_root.visible = true
	_aviso_backdrop.color.a = 0.0
	_aviso_panel.modulate.a = 0.0

	# Aguarda o CenterContainer calcular o tamanho final antes de definir o pivô.
	await get_tree().process_frame
	if animacao_atual != _aviso_animacao_id:
		return
	if _aviso_root == null or not is_instance_valid(_aviso_root):
		return

	_atualizar_pivo_painel_aviso()
	# Containers podem restaurar scale para Vector2.ONE durante o layout inicial.
	# Por isso o estado inicial da animação é aplicado somente depois desse frame.
	_aviso_panel.scale = AVISO_ESCALA_INICIAL
	_aviso_botao_ok.grab_focus()

	# Fade do fundo e entrada curta com bounce suave, sempre a partir do centro.
	_aviso_tween = create_tween()
	_aviso_tween.tween_property(_aviso_backdrop, "color:a", AVISO_COR_FUNDO.a, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_aviso_tween.parallel().tween_property(_aviso_panel, "modulate:a", 1.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_aviso_tween.parallel().tween_property(_aviso_panel, "scale", AVISO_ESCALA_DESTAQUE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_aviso_tween.tween_property(_aviso_panel, "scale", Vector2.ONE, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func fechar_aviso_turno() -> void:
	if _aviso_root == null or not is_instance_valid(_aviso_root) or not _aviso_root.visible:
		return

	_aviso_animacao_id += 1
	var animacao_atual := _aviso_animacao_id
	_cancelar_animacao_aviso()

	# O painel não desaparece abruptamente: recua levemente e o fundo some junto.
	_aviso_tween = create_tween()
	_aviso_tween.tween_property(_aviso_panel, "scale", Vector2(0.94, 0.94), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_aviso_tween.parallel().tween_property(_aviso_panel, "modulate:a", 0.0, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_aviso_tween.parallel().tween_property(_aviso_backdrop, "color:a", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_aviso_tween.tween_callback(func() -> void:
		if animacao_atual != _aviso_animacao_id:
			return
		if _aviso_root != null and is_instance_valid(_aviso_root):
			_aviso_root.visible = false
		if _aviso_panel != null and is_instance_valid(_aviso_panel):
			_aviso_panel.scale = Vector2.ONE
			_aviso_panel.modulate.a = 1.0
	)


# ============================================================================
# HUD DE ESPECTADOR — COMPACTO E NÃO INTRUSIVO
# ============================================================================
func _process(delta: float) -> void:
	if not _modo_espectador:
		return
	_espectador_tempo_refresh += delta
	if _espectador_tempo_refresh >= 0.65 or _espectador_sujo:
		_espectador_tempo_refresh = 0.0
		_espectador_sujo = false
		var tabuleiro_node = get_tree().get_first_node_in_group("tabuleiro_principal")
		if tabuleiro_node and tabuleiro_node.has_method("obter_dados_espectador"):
			atualizar_dados_espectador(tabuleiro_node.obter_dados_espectador())

func _aplicar_fonte_espectador(no: Control, tamanho: int = 10) -> void:
	no.add_theme_font_override("font", FONTE_ESPECTADOR)
	no.add_theme_font_size_override("font_size", tamanho)

func _estilo_painel_espectador(cor_fundo: Color, cor_borda: Color, largura: int = 2) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = cor_fundo
	sb.border_color = cor_borda
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		sb.set_border_width(side, largura)
	sb.corner_radius_top_left = 7
	sb.corner_radius_top_right = 7
	sb.corner_radius_bottom_left = 7
	sb.corner_radius_bottom_right = 7
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

func _criar_interface_espectador() -> void:
	if _hud_espectador_novo != null and is_instance_valid(_hud_espectador_novo):
		return
	_hud_espectador_novo = CENA_HUD_ESPECTADOR.instantiate()
	_hud_espectador_novo.name = "HUD_Espectador_Falencia"
	$Control.add_child(_hud_espectador_novo)
	if _hud_espectador_novo.has_signal("seguimento_solicitado"):
		_hud_espectador_novo.connect("seguimento_solicitado", Callable(self, "_on_hud_espectador_seguimento_solicitado"))

func _ocultar_hud_partida_para_espectador() -> void:
	# Mantém somente o painel central do Evento Global. Todos os controles de
	# ação do jogador são substituídos pelo HUD compacto do espectador.
	var caminhos_ocultar: Array[String] = [
		"CantoSupEsq_Jogador",
		"PainelImunidades",
		"PainelAliancas",
		"CantoSupDir_Propriedade",
		"BtnTogglePromessas",
		"PainelPromessas",
		"CantoInfEsq_Habilidade",
		"Centro_Dados",
		"DossieDiana",
		"RelatorioYasmin",
		"Centro_AcaoTerreno",
		"Centro_Leilao",
		"Centro_CartaSorteada",
		"CantoDir_Construcao",
		"Centro_BtnHipoteca",
		"Centro_HabilidadeOverlay",
		"Centro_Falencia",
		"Centro_Vitoria",
		"BarraLeilao",
		"RoundCounter",
		"Centro_VotacaoEleicao",
		"OverlayEscuro",
	]
	for caminho in caminhos_ocultar:
		var no = $Control.get_node_or_null(caminho)
		if no is CanvasItem:
			no.visible = false
	$Control/CentroSup_Evento.visible = true
	$Control/CentroSup_Evento.z_index = 950
	painel_detalhes_evento.visible = false
	painel_detalhes_evento.z_index = 951
	detalhes_evento_aberto = false
	if painel_negociacao:
		painel_negociacao.visible = false

func ativar_modo_espectador() -> void:
	_criar_interface_espectador()
	_modo_espectador = true
	_ocultar_hud_partida_para_espectador()

	# Bloqueio defensivo: o jogador falido não pode acionar comandos por atalhos,
	# sinais antigos ou painéis que tentem reaparecer durante a partida.
	botao_girar.disabled = true
	botao_hab.disabled = true
	btn_hipoteca.disabled = true
	btn_abrir_construcao.disabled = true
	if botao_negociar:
		botao_negociar.disabled = true
	if input_promessa:
		input_promessa.editable = false
	if btn_criar_promessa:
		btn_criar_promessa.disabled = true
	if _decisao_evento_root:
		_decisao_evento_root.visible = false
	if overlay_votacao:
		overlay_votacao.visible = false

	var tabuleiro_node = get_tree().get_first_node_in_group("tabuleiro_principal")
	if tabuleiro_node:
		if tabuleiro_node.has_method("ativar_modo_espectador_local"):
			tabuleiro_node.ativar_modo_espectador_local()
		if tabuleiro_node.has_method("obter_dados_espectador"):
			atualizar_dados_espectador(tabuleiro_node.obter_dados_espectador())

	if _hud_espectador_novo and _hud_espectador_novo.has_method("mostrar"):
		_hud_espectador_novo.call("mostrar")

func esta_em_modo_espectador() -> bool:
	return _modo_espectador

func marcar_espectador_sujo() -> void:
	_espectador_sujo = true

func atualizar_dados_espectador(dados: Dictionary) -> void:
	_dados_espectador = dados.duplicate(true)
	if not _modo_espectador:
		return
	if _hud_espectador_novo and _hud_espectador_novo.has_method("atualizar_dados"):
		_hud_espectador_novo.call("atualizar_dados", _dados_espectador)

func _on_hud_espectador_seguimento_solicitado(jogador_id: String, automatico: bool) -> void:
	var tabuleiro_node = get_tree().get_first_node_in_group("tabuleiro_principal")
	if tabuleiro_node and tabuleiro_node.has_method("configurar_seguimento_espectador"):
		tabuleiro_node.configurar_seguimento_espectador(jogador_id, automatico)
	_espectador_sujo = true

# ============================================================================
# PLACAR FINAL COMPLETO
# ============================================================================
func mostrar_placar_final_completo(placar: Dictionary) -> void:
	if _placar_final_root and is_instance_valid(_placar_final_root):
		_placar_final_root.queue_free()
	_placar_final_root = Control.new()
	_placar_final_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_placar_final_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_placar_final_root.z_index = 1700
	$Control.add_child(_placar_final_root)
	var fundo = ColorRect.new()
	fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fundo.color = Color(0.01, 0.015, 0.025, 0.94)
	_placar_final_root.add_child(fundo)
	var centro = CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	_placar_final_root.add_child(centro)
	var painel = PanelContainer.new()
	painel.custom_minimum_size = Vector2(1380, 850)
	painel.add_theme_stylebox_override("panel", _estilo_painel_espectador(Color(0.035, 0.045, 0.065, 0.99), Color(1.0, 0.78, 0.18), 4))
	centro.add_child(painel)
	var margem = MarginContainer.new()
	for margem_nome in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margem.add_theme_constant_override(margem_nome, 20)
	painel.add_child(margem)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margem.add_child(vbox)
	var titulo = Label.new()
	titulo.text = "PLACAR FINAL COMPLETO"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	_aplicar_fonte_espectador(titulo, 22)
	vbox.add_child(titulo)
	var resumo = Label.new()
	resumo.text = "%d rodada(s) | %d turno(s) globais | Patrimônio considera caixa, propriedades e construções." % [int(placar.get("rodadas", 0)), int(placar.get("turnos", 0))]
	resumo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aplicar_fonte_espectador(resumo, 9)
	vbox.add_child(resumo)
	var progresso_local: Dictionary = placar.get("progressao_local", {})
	if not progresso_local.is_empty():
		var perfil_resumo = Label.new()
		var nivel_anterior = int(progresso_local.get("nivel_anterior", 1))
		var nivel_atual = int(progresso_local.get("nivel_atual", nivel_anterior))
		var texto_nivel = "NÍVEL %d" % nivel_atual
		if nivel_atual > nivel_anterior:
			texto_nivel = "SUBIU DE NÍVEL %d PARA %d!" % [nivel_anterior, nivel_atual]
		perfil_resumo.text = "SEU PERFIL — +%d XP | %s | XP TOTAL: %d" % [
			int(progresso_local.get("xp_ganho", 0)), texto_nivel, int(progresso_local.get("xp_total", 0))
		]
		perfil_resumo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		perfil_resumo.add_theme_color_override("font_color", Color(0.40, 0.90, 1.0) if nivel_atual == nivel_anterior else Color(0.45, 1.0, 0.55))
		_aplicar_fonte_espectador(perfil_resumo, 12)
		vbox.add_child(perfil_resumo)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	var lista = VBoxContainer.new()
	lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lista.add_theme_constant_override("separation", 10)
	scroll.add_child(lista)
	for jogador in placar.get("jogadores", []):
		var card = PanelContainer.new()
		var vencedor = bool(jogador.get("vencedor", false))
		var cor = Color(1.0, 0.8, 0.18) if vencedor else Color(0.35, 0.55, 0.72)
		card.add_theme_stylebox_override("panel", _estilo_painel_espectador(Color(0.06, 0.075, 0.10, 0.98), cor, 3 if vencedor else 2))
		lista.add_child(card)
		var info = Label.new()
		var status = "VENCEDOR" if vencedor else ("FALIU" if jogador.get("falido", false) else "FINALISTA")
		var recompensas_texto: Array[String] = []
		for recompensa in jogador.get("recompensas_xp", []):
			recompensas_texto.append("%s (+%d)" % [str(recompensa.get("descricao", "XP")), int(recompensa.get("valor", 0))])
		var detalhamento_xp = "Nenhum bônus de XP" if recompensas_texto.is_empty() else " • ".join(recompensas_texto)
		info.text = "%dº — %s [%s]\nCaixa final: $%d | Patrimônio final: $%d | Propriedades: %d | Hipotecas: %d | Monopólios: %d\nReputação: %d/100 | XP da partida: %d | Eliminações: %d | Habilidades: %d | Acordos de 5T: %d\nXP: %s" % [
			int(jogador.get("colocacao", 0)), str(jogador.get("nome", jogador.get("id", ""))).to_upper(), status,
			int(jogador.get("dinheiro", 0)), int(jogador.get("patrimonio", 0)), int(jogador.get("quantidade_propriedades", 0)),
			int(jogador.get("hipotecas", 0)), int(jogador.get("monopolios", 0)), int(jogador.get("reputacao", 50)),
			int(jogador.get("xp_partida", 0)), int(jogador.get("eliminacoes", 0)), int(jogador.get("habilidades_usadas", 0)),
			int(jogador.get("acordos_5_turnos", 0)), detalhamento_xp]
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55) if vencedor else Color(0.88, 0.9, 0.94))
		_aplicar_fonte_espectador(info, 10)
		card.add_child(info)
	var fechar = Button.new()
	fechar.text = "FECHAR PLACAR"
	fechar.custom_minimum_size = Vector2(260, 54)
	fechar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_aplicar_fonte_espectador(fechar, 10)
	fechar.pressed.connect(func():
		if _placar_final_root and is_instance_valid(_placar_final_root):
			_placar_final_root.queue_free()
		_placar_final_root = null
	)
	vbox.add_child(fechar)
