extends Node2D

signal evento_tutorial(tipo: String, dados: Dictionary)

# ============================================================================
# METROPOLIS IN RUINS - MOTOR DE GAMEPLAY COMPLETO
# ============================================================================

# --- REFERÊNCIAS DE NÓS ---
@onready var camera: Camera2D = $CameraDoTabuleiro
@onready var menu_pause = $MenuPause

var pino_cena = preload("res://scenes/gameplay/tabuleiro/pino_personagem.tscn")
var hud_cena = preload("res://scenes/ui/hud_partida/hud_partida.tscn")
const BOT_JOGADOR_SCRIPT = preload("res://scenes/entities/bot/bot_jogador.gd")

var arrastando_camera = false
var posicao_mouse_anterior = Vector2()
var toques_ativos = {} 
var distancia_toque_anterior = 0.0
var cinematica_rodando = true

# --- CÂMERA: MODO SEGUIR PINO ---
var pino_seguido: Node2D = null  # Pino sendo acompanhado pela câmera
var seguindo_pino: bool = false  # true = câmera em modo "seguir pino"

var pinos_jogadores := {}
var pinos_por_casa: Dictionary = {}
var registro_propriedades := {}
var cor_por_jogador := {}
var lista_turnos := ["yasmin", "breno", "mira", "igor", "diana", "kofi"]
var indice_turno_atual := 0
var jogador_atual_id: String = "yasmin"
var hud: CanvasLayer
var _bots_jogadores: Dictionary = {}
var _bots_pausados: bool = false
var _cenario_tutorial_expandido_preparado: bool = false
var _menu_pause_bloqueando_acoes: bool = false
var _pausa_global_ativa: bool = false
var _peer_iniciador_pausa: int = 0
var _personagem_iniciador_pausa: String = ""
var _nome_iniciador_pausa: String = ""
var _desistencia_local_pendente: bool = false
var _partida_sendo_salva_e_encerrada: bool = false
var _aguardando_confirmacao_vitoria_desistencia: bool = false
var _vitoria_desistencia_confirmada_no_vencedor: bool = false
var _vencedor_desistencia_aguardado: String = ""
var _token_desistencia_online_atual: String = ""
var _tokens_desistencia_processados: Dictionary = {}
const TEMPO_MAXIMO_CONFIRMACAO_VITORIA_DESISTENCIA: float = 9.0
const ATRASO_CONFIRMACAO_TELA_VITORIA: float = 3.0

var lances_leilao_atuais = {}
var leilao_em_andamento = false
var casa_em_leilao = -1

# --- VARIÁVEIS DE ESTADO E EVENTOS GLOBAIS ---
var rodada_atual: int = 1
# Oferta Irrecusável balanceada: registra em qual rodada cada ativo mudou de
# dono. Uma propriedade só pode ser alvo depois de permanecer 2 rodadas com o
# mesmo adversário.
var rodada_aquisicao_propriedade: Dictionary = {}
var evento_ativo: String = "MERCADO ESTÁVEL"
var ultimo_evento_sorteado: String = ""

# --- GDD: Relatório de Mercado da Yasmin. As áreas são recalculadas no
#     começo de CADA rodada a partir da posição real dos jogadores e da
#     distribuição exata de 2d6. O painel mostra a chance de pelo menos um
#     jogador cair em cada ativo comprável nos próximos 2 turnos da mesa. ---
var tendencias_fixas: Array = []
var tendencias_turnos_restantes: int = 0  # Mantido para compatibilidade de save; agora vale 1 rodada.
var proximo_evento_global: String = ""  # Para Fonte Anônima da Diana
var proximo_evento_descricao: String = ""

# --- GDD: Imunidade Política do Breno é uma decisão única por partida. ---
const EVENTOS_NEGATIVOS_BRENO := [
	"Bolha Imobiliária — Expansão",
	"Bolha Imobiliária — Estouro",
	"Greve Geral",
	"Onda de Calor Extremo",
	"Enchente da Bacia Norte",
	"Vendaval e Queda de Granizo",
	"Crise do Crédito",
	"Migração em Massa",
	"Boom das Startups",
	"Taxa Progressiva",
	"Estiagem e Crise Hídrica",
	"Gentrificação Acelerada",
	"Protestos contra Especulação",
	"Inflação Acelerada",
	"Intervenção Federal",
	"Apagão Digital",
	"Revolução dos Carros Autônomos",
	"Ilha de Calor Urbano e Seca Florestal",
	"Escândalo de Corrupção na Prefeitura"
]
var _imunidade_breno_bloqueando_acoes: bool = false
var _breno_evento_imune_atual: String = ""
var _evento_resolvido_apos_decisao_breno: String = ""

# Distribuição exata da soma de dois dados de seis faces.
const DISTRIBUICAO_2D6 := {
	2: 1.0 / 36.0, 3: 2.0 / 36.0, 4: 3.0 / 36.0, 5: 4.0 / 36.0,
	6: 5.0 / 36.0, 7: 6.0 / 36.0, 8: 5.0 / 36.0, 9: 4.0 / 36.0,
	10: 3.0 / 36.0, 11: 2.0 / 36.0, 12: 1.0 / 36.0
}

# --- SISTEMA DE CARTAS E INFLAÇÃO ---
var multiplicador_inflacao_global: float = 1.0
var deck_destino_atual = []
var deck_ordem_atual = []

var deck_destino_base = [
								{"nome": "Auditoria Fiscal", "desc": "Pague 10% do seu saldo ao banco. Mínimo de $50.", "tipo_efeito": "auditoria_fiscal", "valor": 0.10},
								{"nome": "Investidor Anjo", "desc": "Receba $200 do banco.", "tipo_efeito": "ganha_dinheiro", "valor": 200},
								{"nome": "Contrato de Publicidade", "desc": "Receba $30 de cada jogador.", "tipo_efeito": "rouba_todos", "valor": 30},
								{"nome": "Vazamento de Óleo", "desc": "Se você possui propriedade na Zona Portuária, pague $200 em multa ambiental.", "tipo_efeito": "vazamento_oleo_condicional", "valor": 200},
								{"nome": "Herança Inesperada", "desc": "Receba gratuitamente uma propriedade aleatória ainda pertencente ao banco.", "tipo_efeito": "heranca_propriedade", "valor": 0},
								{"nome": "Falsa Promessa", "desc": "A prefeitura mentiu na obra. Avance 3 casas.", "tipo_efeito": "move_frente", "valor": 3},
								{"nome": "Investigação Patrimonial", "desc": "Seu saldo total fica público para todos por 2 turnos.", "tipo_efeito": "revelar_saldo", "valor": 0},
								{"nome": "Processo por Dano", "desc": "Pague $150 de custas judiciais.", "tipo_efeito": "perde_dinheiro", "valor": 150},
								{"nome": "Inspeção Estrutural", "desc": "O CREA achou rachaduras! Pague $40 por cada nível de construção (Casa/Hotel) que você possui.", "tipo_efeito": "perde_por_nivel", "valor": 40},
								{"nome": "Desapropriação", "desc": "A prefeitura tomou espaço para fazer uma praça. Você perdeu 1 Nível de construção na sua melhor propriedade.", "tipo_efeito": "perde_melhor_casa", "valor": 1},
								{"nome": "Sair da Cadeia", "desc": "Você encontrou um brecha legal! Guarde esta carta — ela pode ser usada para sair da prisão gratuitamente.", "tipo_efeito": "ganha_carta_sair_prisao", "valor": 1},
								{"nome": "Multação de Trânsito", "desc": "Excesso de velocidade na avenida! Pague $75.", "tipo_efeito": "perde_dinheiro", "valor": 75},
								{"nome": "Reforma de Calçada", "desc": "A prefeitura exigiu reforma. Pague $25 por propriedade.", "tipo_efeito": "perde_por_propriedade", "valor": 25},
								{"nome": "Dividendo Surpresa", "desc": "Seus investimentos renderam! Receba $10 por propriedade.", "tipo_efeito": "ganha_por_propriedade", "valor": 10},
								{"nome": "Inspeção Sanitária", "desc": "Multa de higiene! Pague $30 por cada nível de construção.", "tipo_efeito": "perde_por_nivel", "valor": 30},
								{"nome": "Retroativa Legal", "desc": "Uma lei retroativa te prejudicou. Volte 2 casas.", "tipo_efeito": "move_tras", "valor": 2},
								{"nome": "Leilão Cancelado", "desc": "O leilão foi cancelado. Avance 2 casas.", "tipo_efeito": "move_frente", "valor": 2},
								{"nome": "Taxa de Licenciamento", "desc": "Pague $100 pela renovação de licenças.", "tipo_efeito": "perde_dinheiro", "valor": 100},
								{"nome": "Recebimento de Aluguel", "desc": "Inquilinos pagaram adiantado! Receba $175.", "tipo_efeito": "ganha_dinheiro", "valor": 175},
								{"nome": "Multa Ambiental", "desc": "Sua propriedade poluiu! Pague $20 por propriedade.", "tipo_efeito": "perde_por_propriedade", "valor": 20},
								{"nome": "Valorização Surpresa", "desc": "Sua propriedade mais barata dobra o aluguel por 2 turnos.", "tipo_efeito": "valorizacao_surpresa", "valor": 0},
								{"nome": "Embargo Judicial", "desc": "Uma de suas propriedades é interditada por 1 turno.", "tipo_efeito": "embargo_judicial", "valor": 0},
								{"nome": "Despejo Judicial", "desc": "Você pode remover 1 casa de uma propriedade de um adversário.", "tipo_efeito": "despejo_judicial", "valor": 0},
								{"nome": "Prêmio de Arquitetura", "desc": "Sua construção mais cara ganha +50% de aluguel por 1 turno.", "tipo_efeito": "premio_arquitetura", "valor": 0}
]

var deck_ordem_base = [
								{"nome": "Reforma da Fachada", "desc": "O bairro melhorou! Receba $50 de cada jogador.", "tipo_efeito": "rouba_todos", "valor": 50},
								{"nome": "Conta de Água", "desc": "A tarifa do SAEM subiu. Pague $75.", "tipo_efeito": "perde_dinheiro", "valor": 75},
								{"nome": "Festa de Rua", "desc": "Todos os jogadores no mesmo bairro recebem $50 do banco.", "tipo_efeito": "festa_rua", "valor": 50},
								{"nome": "Barulho de Obra", "desc": "O jogador à sua esquerda perde $30 por incômodo.", "tipo_efeito": "barulho_esquerda", "valor": 30},
								{"nome": "Inspeção Municipal", "desc": "Se você tem mais de 2 hotéis, pague $100 de taxa de segurança.", "tipo_efeito": "inspecao_hoteis", "valor": 100},
								{"nome": "Reembolso Tributário", "desc": "O contador achou uma brecha. Receba $15 por propriedade.", "tipo_efeito": "ganha_por_propriedade", "valor": 15},
								{"nome": "Subsídio Habitacional", "desc": "Construa 1 casa gratuitamente em uma propriedade sua.", "tipo_efeito": "subsidio_casa_gratis", "valor": 0},
								{"nome": "Mercado em Baixa", "desc": "Perda nos investimentos. Pague $100.", "tipo_efeito": "perde_dinheiro", "valor": 100},
								{"nome": "Incentivo à Construção", "desc": "O governo está financiando obras! Receba $50 por cada nível de construção (Casa/Hotel) que você possui.", "tipo_efeito": "ganha_por_nivel", "valor": 50},
								{"nome": "Sair da Cadeia Grátis", "desc": "Guarde esta carta para sair da prisão sem pagar.", "tipo_efeito": "ganha_carta_sair_prisao", "valor": 1},
								{"nome": "Doação Anônima", "desc": "Um benfeitor depositou $250 na sua conta.", "tipo_efeito": "ganha_dinheiro", "valor": 250},
								{"nome": "Convocação Popular", "desc": "Você organizou um evento! Receba $20 de cada jogador.", "tipo_efeito": "rouba_todos", "valor": 20},
								{"nome": "Multa de Barulho", "desc": "Vizinhos reclamaram! Pague $40 a cada jogador.", "tipo_efeito": "paga_todos", "valor": 40},
								{"nome": "Reforma Voluntária", "desc": "Moradores reformaram a praça. Receba $80.", "tipo_efeito": "ganha_dinheiro", "valor": 80},
								{"nome": "Taxa de Coleta", "desc": "Serviço de lixo aumentou. Pague $60.", "tipo_efeito": "perde_dinheiro", "valor": 60},
								{"nome": "Bônus de Produtividade", "desc": "Receba $25 por propriedade.", "tipo_efeito": "ganha_por_propriedade", "valor": 25},
								{"nome": "Reparo de Esgoto", "desc": "Pague $35 por cada nível de construção.", "tipo_efeito": "perde_por_nivel", "valor": 35},
								{"nome": "Patrocínio Local", "desc": "Um comércio local te patrocinou! Receba $120.", "tipo_efeito": "ganha_dinheiro", "valor": 120},
								{"nome": "Multa de Ocupação", "desc": "Ocupação irregular! Pague $15 por propriedade.", "tipo_efeito": "perde_por_propriedade", "valor": 15},
								{"nome": "Incêndio no Galpão", "desc": "Propriedade no grupo Cinza ou Marrom: destruir 1 casa.", "tipo_efeito": "incendio_galpao", "valor": 0},
								{"nome": "Novo Parque Público", "desc": "A propriedade vizinha à casa da carta ganha +20% de aluguel por 3 turnos.", "tipo_efeito": "novo_parque", "valor": 0},
								{"nome": "Bloqueio de Tráfego", "desc": "Todos os jogadores não podem usar atalhos ou portais por 1 turno.", "tipo_efeito": "bloqueio_trafego", "valor": 0},
								{"nome": "Ação Coletiva de Moradores", "desc": "Qualquer hotel ativo: aluguel reduzido a 50% por 1 turno.", "tipo_efeito": "acao_coletiva", "valor": 0}
]

var eventos_globais_db = [
								{"nome": "Bolha Imobiliária — Expansão", "descricao": "Todo mundo quer comprar. O mercado sobe sem parar.\n\nEFEITO:\nTodos os aluguéis sobem 25%. Donos de Monopólios ganham $200 de bônus imediato."},
								{"nome": "Bolha Imobiliária — Estouro", "descricao": "A pergunta foi feita. A resposta era o que temiam.\n\nEFEITO:\nAluguéis caem 40%. Todos os jogadores perdem imediatamente 10% do dinheiro em caixa por pânico financeiro."},
								{"nome": "Greve Geral", "descricao": "Os trabalhadores cruzam os braços. Não é pedido. É exigência.\n\nEFEITO:\nMetrôs não cobram aluguel. Nenhuma construção permitida. Quem tem mais de 4 propriedades paga $150 de multa solidária."},
								{"nome": "Onda de Calor Extremo", "descricao": "A cidade sangra. Condicionadores de ar explodem.\n\nEFEITO:\nAs Utilidades (ENEM e SAEM) dobram os aluguéis cobrados dos afetados."},
								{"nome": "Enchente da Bacia Norte", "descricao": "As chuvas não param. As favelas afundam.\n\nEFEITO:\nAluguéis nos grupos Rosa e Marrom ficam zerados. Grupo Laranja (áreas altas) ganha +15% de aluguel."},
								{"nome": "Vendaval e Queda de Granizo", "descricao": "Tempestade extratropical atinge a cidade sem aviso.\n\nEFEITO:\nHotéis perdem 1 nível (viram 4 casas). 2 propriedades aleatórias têm construções zeradas. Linhas de metro param por 1 turno. Seguro retroativo: jogadores com +$500 podem pagar $200 para proteger 2 propriedades. (Mira sofre 50% menos dano)."},
								{"nome": "Crise do Crédito", "descricao": "Os bancos param de emprestar. O mercado congela.\n\nEFEITO:\nConstruções ficam bloqueadas por 2 turnos e preços finais de leilão caem 30%. Jogadores com mais de $500 podem comprar propriedades hipotecadas de adversários por 60% do valor de tabela."},
								{"nome": "Migração em Massa", "descricao": "Milhares chegam a Metropolis. A cidade não estava pronta.\n\nEFEITO:\nPropriedades Rosa e Marrom dobram aluguel por 3 turnos. Verde e Azul-Escuro perdem 10%. O banco abre leilão especial de até 2 terrenos baratos, com lance inicial de 50% do valor."},
								{"nome": "Boom das Startups", "descricao": "Cinco unicórnios anunciam expansão para Metropolis no mesmo mês.\n\nEFEITO:\nGrupo Verde (Eco-Hub) e Vermelho (Zona Financeira) dobram seus aluguéis."},
								{"nome": "Taxa Progressiva", "descricao": "O governo anuncia imposto sobre patrimônio imobiliário.\n\nEFEITO:\nCada jogador paga 5% do valor total de suas propriedades ao banco. Jogadores com menos de 3 propriedades são isentos. (Breno pode usar Imunidade Política para cancelar)."},
								# --- NOVOS: 9 eventos adicionais conforme GDD ---
								{"nome": "Estiagem e Crise Hídrica", "descricao": "Os reservatórios atingem 15% da capacidade. Racionamento obrigatório.\n\nEFEITO:\nSAEM triplica o aluguel, o grupo Verde ganha 20%, ninguém pode construir e quem não possui SAEM paga $25 por turno. Uma votação pode reduzir a duração de 3 para 1 turno, ao custo coletivo de $100 por jogador."},
								{"nome": "Gentrificação Acelerada", "descricao": "Startup anuncia 'revitalização' do bairro mais pobre. Moradores recebem aviso na sexta à noite.\n\nEFEITO:\nGrupo Cinza dobra o preço de compra e seus aluguéis sobem 50% permanentemente. Durante uma janela especial, donos podem vender propriedades Cinza ao banco por 150% do valor de tabela."},
								{"nome": "Protestos contra Especulação", "descricao": "Ruas transbordam. Faixas dizem 'Morar Não é Luxo'. O mercado ignora.\n\nEFEITO:\nAluguéis de hotéis reduzidos a 50% por 2 turnos. Quem tem mais de 2 hotéis paga $100 por hotel."},
								{"nome": "Inflação Acelerada", "descricao": "Preços sobem. Salários ficam. A conta do aluguel, nem se fala.\n\nEFEITO:\nPreços de construção sobem 30%. Bônus da Partida sobe para $250 por 3 turnos. Hipotecas ativas pagam 15% de juros extras."},
								{"nome": "Nova Lei de Zoneamento", "descricao": "Câmara aprova lei às 3h da manhã. Coincidentemente, beneficia exatamente quem doou para as campanhas.\n\nEFEITO:\nUm grupo passa a construir hotel com apenas 3 casas; seus donos recebem $150. Breno pode pagar $200 para escolher o grupo em vez do sorteio. O grupo fica vulnerável a enchentes e estiagens por 2 turnos."},
								{"nome": "Eleições Municipais", "descricao": "Candidatos prometem tudo. Eleitores desacreditam. Mercado oscila.\n\nEFEITO:\nTodos os jogadores votam em um de tres pacotes de politicas. O mais votado vira realidade. Empate = paralisia politica: alugueis congelados por 1 turno."},
								{"nome": "Intervenção Federal", "descricao": "Governo federal, alegando 'crise nacional', assume controle temporário das utilidades públicas.\n\nEFEITO:\nENEM e SAEM têm aluguéis congelados por 2 turnos. Donos recebem $100/turno de compensação estatal."},
								{"nome": "Apagão Digital", "descricao": "Ataque cibernetico derruba infraestrutura de dados de Metropolis. Tudo para.\n\nEFEITO:\nNenhuma construção ou negociação é possível por 1 turno. Habilidades ativas desativadas por 1 turno. Eco-Hub e Zona Financeira perdem 1 nível de construção. O dono da ENEM cobra $50 de cada outro jogador ativo."},
								{"nome": "Revolução dos Carros Autônomos", "descricao": "Onibus autônomos chegam. Motoristas perdem emprego. Mobilidade fica 30% mais barata.\n\nEFEITO:\nLinhas de Metro perdem 30% do aluguel permanentemente. Quem não tem Linhas recebe $50/turno de bônus."},
								{"nome": "Ilha de Calor Urbano e Seca Florestal", "descricao": "O último parque da cidade pega fogo. A Prefeitura nega relação com desmatamento.\n\nEFEITO:\nEco-Hub perde 30% de aluguel. 1 propriedade Verde interditada 2T. Corredor Cultural e Boemia +10% aluguel. Kofi imune à interdição."},
								{"nome": "Escândalo de Corrupção na Prefeitura", "descricao": "Documentos vazados provam que 60% das licitações eram fraudadas.\n\nEFEITO:\nJogadores com +3 propriedades pagam $75. 2 obras embargadas 2T. Breno pode usar Imunidade Política."}
]

var dados_economia_jogadores := {
								"yasmin": {"nome": "Yasmin Khalil", "dinheiro": 1500, "propriedades_compradas": 0, "recarga_hab": 0,
										"alvos_oferta_irrecusavel": [],
																"preso": false, "turnos_preso": 0, "duplas_consecutivas": 0, "cartas_sair_prisao": 0, "cartas_construcao_gratis": 0,
																"propriedades_lista": [], "falido": false, "vencedor": false,
																"imunidades": [], "aliancas": []},
								"breno": {"nome": "Breno Vasquez", "dinheiro": 1500, "propriedades_compradas": 0, "recarga_hab": 0, "usou_imunidade": false, "evento_imune_atual": "",
																"preso": false, "turnos_preso": 0, "duplas_consecutivas": 0, "cartas_sair_prisao": 0, "cartas_construcao_gratis": 0,
																"propriedades_lista": [], "falido": false, "vencedor": false,
																"imunidades": [], "aliancas": []},
								"mira": {"nome": "Mira Santos", "dinheiro": 1500, "propriedades_compradas": 0, "recarga_hab": 0,
																"preso": false, "turnos_preso": 0, "duplas_consecutivas": 0, "cartas_sair_prisao": 0, "cartas_construcao_gratis": 0,
																"propriedades_lista": [], "falido": false, "vencedor": false,
																"imunidades": [], "aliancas": []},
								"igor": {"nome": "Igor Volkov", "dinheiro": 1500, "propriedades_compradas": 0, "recarga_hab": 0, "divida_ativa": 0, "divida_original": 0, "turnos_divida": 0, "credor_divida": "", "usou_abutre": false,
																"preso": false, "turnos_preso": 0, "duplas_consecutivas": 0, "cartas_sair_prisao": 0, "cartas_construcao_gratis": 0,
																"propriedades_lista": [], "falido": false, "vencedor": false,
																"imunidades": [], "aliancas": []},
								"diana": {"nome": "Diana Ferro", "dinheiro": 1500, "propriedades_compradas": 0, "recarga_hab": 0,
																"fonte_anonima_usada": false, "fonte_anonima_evento_previsto": "",
																"preso": false, "turnos_preso": 0, "duplas_consecutivas": 0, "cartas_sair_prisao": 0, "cartas_construcao_gratis": 0,
																"propriedades_lista": [], "falido": false, "vencedor": false,
																"imunidades": [], "aliancas": []},
								"kofi": {"nome": "Kofi Mensah", "dinheiro": 1500, "propriedades_compradas": 0, "recarga_hab": 0,
																"preso": false, "turnos_preso": 0, "duplas_consecutivas": 0, "cartas_sair_prisao": 0, "cartas_construcao_gratis": 0,
																"propriedades_lista": [], "falido": false, "vencedor": false,
																"imunidades": [], "aliancas": []}
}

# --- NOVO: Variáveis de estado do tabuleiro ---
var ultimo_dado1: int = 1
var ultimo_dado2: int = 1
var acordo_silencio_ativo: bool = false  # Bloqueia negociações no turno, exceto para Breno
var turno_construcao_bloqueada: bool = false  # Zona de Obras: bloqueia obras até a troca de turno
var ultimo_grupo_zoneamento: String = ""  # Beneficiado pela Nova Lei de Zoneamento
var jogadores_ativos: Array = []  # Lista de IDs que ainda não faliram
# --- Eleições Municipais: estado autoritativo da votação ---
const ELEICAO_PACOTES_VALIDOS := ["populista", "liberal", "conservador"]
const ELEICAO_DURACAO_VOTACAO_SEGUNDOS := 20
const ELEICAO_DURACAO_RESULTADO_SEGUNDOS := 3.0
# O GDD não fixa o valor do imposto conservador. Foi adotado 10% do valor
# obtido na hipoteca (metade do valor de face), mantendo a regra centralizada.
const ELEICAO_IMPOSTO_HIPOTECA_PERCENTUAL := 0.10

var _votos_eleicao: Dictionary = {}  # { personagem_id: pacote }
var _votacao_eleicao_ativa: bool = false
var _eleicao_bloqueando_acoes: bool = false
var _eleicao_id_atual: int = 0
var _eleicao_jogadores_elegiveis: Array = []
var _eleicao_resultado_aplicado_id: int = -1
var _eleicao_falencias_pendentes: Array = []
var _pacote_eleicao_vencedor: String = ""  # histórico do último resultado

# --- EVENTOS GLOBAIS INTERATIVOS (GDD): estado autoritativo da sessão ---
const EVENTO_DECISAO_DURACAO_SEGUNDOS := 20
const EVENTO_RESULTADO_DURACAO_SEGUNDOS := 2.5
const EVENTOS_GDD_INTERATIVOS := [
	"Vendaval e Queda de Granizo",
	"Crise do Crédito",
	"Migração em Massa",
	"Estiagem e Crise Hídrica",
	"Gentrificação Acelerada",
	"Nova Lei de Zoneamento"
]
var _evento_interativo_bloqueando_acoes: bool = false
var _fluxo_evento_interativo_ativo: bool = false
var _fluxo_evento_interativo_nome: String = ""
var _sessao_decisao_evento_id: int = 0
var _sessao_decisao_evento_ativa: bool = false
var _sessao_decisao_evento_prompts: Dictionary = {}
var _sessao_decisao_evento_respostas: Dictionary = {}
var _falencias_pendentes_evento: Array = []
# --- NOVO (Ilha de Calor Urbano): estado de interdição ---
var _ilha_calor_prop_interditada: int = -1  # casa_id da prop interditada
var _ilha_calor_interditacao_turnos: int = 0  # turnos restantes
# --- NOVO (Escândalo de Corrupção): estado de embargo de obras ---
var _corrupcao_props_embargadas: Array = []  # lista de casa_ids embargadas
var _corrupcao_embargo_turnos: int = 0  # turnos restantes
# --- NOVO (Cartas): efeitos temporários de cartas ---
var _carta_valorizacao_casa: int = -1  # casa_id com aluguel dobrado
var _carta_valorizacao_turnos: int = 0
var _carta_embargo_judicial_casa: int = -1  # casa_id interditada por carta
var _carta_embargo_judicial_turnos: int = 0
var _carta_parque_casa: int = -1  # casa_id com +20% aluguel
var _carta_parque_turnos: int = 0
var _carta_acao_coletiva_ativa: bool = false  # hotéis aluguel 50%
var _carta_bloqueio_trafego: bool = false  # portais bloqueados
var _carta_premio_casa: int = -1  # casa_id com +50% aluguel (Prêmio Arquitetura)
var _carta_premio_turnos: int = 0
# --- NOVO (Eventos parciais): flags temporárias ---
var _protestos_bloqueio_hotel: bool = false  # Protestos: sem novo hotel 2T
var _protestos_bloqueio_turnos: int = 0
var _carros_autonomos_permanente: bool = false  # Revolução: -30% metro permanente

# --- SISTEMA CENTRAL DE EFEITOS TEMPORÁRIOS/PERMANENTES ---
# Cada efeito é independente do banner `evento_ativo`, portanto efeitos de 2/3/4
# turnos continuam funcionando mesmo depois que outro Evento Global é revelado.
# turnos_restantes = -1 significa efeito permanente.
var efeitos_temporarios: Dictionary = {}
var _sequencia_efeitos: int = 0

# ============================================================================
# ESPECTADOR, HISTÓRICO, PLACAR E REPUTAÇÃO
# ============================================================================
const MAX_HISTORICO_ACOES := 80
const PROMESSA_DURACAO_PADRAO := 5
const REPUTACAO_INICIAL := 50
const REPUTACAO_BONUS_CUMPRIDA := 10
const REPUTACAO_PENALIDADE_QUEBRA := 20
const REPUTACAO_LIMITE_BONUS_EVENTO := 75
const REPUTACAO_LIMITE_PENALIDADE_EVENTO := 25
const REPUTACAO_VALOR_EVENTO := 40
const XP_VITORIA := 500
const XP_SEGUNDO_LUGAR := 300
const XP_TERCEIRO_LUGAR := 200
const XP_ELIMINACAO := 50
const XP_MONOPOLIO := 75
const XP_TRES_EVENTOS_SEGUROS := 100
const XP_CINCO_HABILIDADES := 50
const XP_ACORDO_CINCO_TURNOS := 80
const CREDOR_FALENCIA_BANCO := "__banco__"

var ordem_original_partida: Array = []
var _contador_turnos_globais: int = 0
var _contador_acoes_historico: int = 0
var _historico_acoes: Array = []
var _snapshots_finais: Dictionary = {}
var _partida_encerrada: bool = false
var _resultado_progressao_local: Dictionary = {}
var _evento_xp_em_andamento: bool = false
var _evento_xp_nome: String = ""
var _evento_xp_perdas_construcao: Dictionary = {}
# Obrigações abertas desde a última verificação de solvência.
# Estrutura: { devedor_id: { credor_id ou CREDOR_FALENCIA_BANCO: valor } }.
# O registro permite corrigir pagamentos creditados integralmente antes da
# liquidação automática e ratear apenas o caixa que de fato restou.
var obrigacoes_falencia_pendentes: Dictionary = {}

# Estado local: cada peer decide se está assistindo e qual pino acompanhar.
var modo_espectador_local: bool = false
var espectador_auto_seguir: bool = true
var espectador_alvo_id: String = ""


const ZOOM_MIN = Vector2(0.15, 0.15)
const ZOOM_MAX = Vector2(3.0, 3.0)
const PASSO_BASE = 300.0
const TAMANHO_UNICO = Vector2(240, 240)
const CAMINHO_TILE_CONSTRUCAO := "res://assets/textures/casas/tile_base_construcao.png"
const CAMINHO_SPRITE_CONSTRUCAO_BASE := "res://assets/textures/casas/nivel_"
const ESCALA_TILE_CONSTRUCAO := 1.0
# Os níveis agora usam artes de prédios, mais verticais que as antigas casas.
# A caixa retangular permite que ocupem mais altura sem alargar demais o lote.
const ESCALA_LARGURA_SPRITE_CONSTRUCAO := 1.18
const ESCALA_ALTURA_SPRITE_CONSTRUCAO := 1.38
# Mantém a base no mesmo Y usado pela escala antiga (0,24 da altura do lote),
# fazendo o aumento acontecer para cima e preservando a faixa do proprietário.
const ANCORA_BASE_Y_SPRITE_CONSTRUCAO := 0.24
const DURACAO_ANIMACAO_OBRA := 1.4
const DURACAO_SURGIMENTO_CONSTRUCAO := 0.42
var _construcoes_visuais_em_andamento: Dictionary = {}

# --- NOVO: Limites da câmera para não mostrar fundo preto fora da cidade ---
# A cidade é gerada com grid_radius=15 e tile_size=240, então vai de
# -15*240=-3600 a +16*240=3840 em X (31 tiles) e igual em Y.
# Adicionamos uma margem de 1 tile (240px) de cada lado para que a borda
# da cidade fique visível sem revelar o vazio escuro além dela.
const CIDADE_RAIO_GRID = 15
const CIDADE_TILE_SIZE = 240
const CIDADE_MARGEM = 240.0  # margem extra para a borda da cidade respirar
const CAMINHO_BASE_LOTE_INTERIOR := "res://assets/textures/fundo/base_lote_interior.png"
const CAMINHO_BASE_LOTE_TOPO := "res://assets/textures/fundo/base_lote_topo.png"
const CAMINHO_BASE_LOTE_CANTO := "res://assets/textures/fundo/base_lote_canto.png"
const CAMINHOS_CONSTRUCOES_CIDADE := [
	"res://assets/textures/fundo/construcoes/obra_baixa_tapumes.png",
	"res://assets/textures/fundo/construcoes/obra_alta_estrutura.png",
	"res://assets/textures/fundo/construcoes/obra_media_alvenaria.png",
	"res://assets/textures/fundo/construcoes/oficina_abandonada.png",
	"res://assets/textures/fundo/construcoes/padaria_abandonada.png",
	"res://assets/textures/fundo/construcoes/mercearia_abandonada.png",
	"res://assets/textures/fundo/construcoes/predio_industrial.png",
	"res://assets/textures/fundo/construcoes/hotel_abandonado.png",
	"res://assets/textures/fundo/construcoes/predio_residencial.png",
]
const LARGURA_RELATIVA_CONSTRUCAO_CIDADE := 0.90
const ALTURA_MAXIMA_RELATIVA_CONSTRUCAO_CIDADE := 1.65
const OFFSET_BASE_RELATIVO_CONSTRUCAO_CIDADE := 0.40
# Limites world-space do centro da câmera:
# Centro do tile mais externo = ±15 * 240 = ±3600; somamos meio tile + margem.
var CIDADE_LIMITE_X: float = (CIDADE_RAIO_GRID * CIDADE_TILE_SIZE) + (CIDADE_TILE_SIZE / 2.0) + CIDADE_MARGEM
var CIDADE_LIMITE_Y: float = CIDADE_LIMITE_X
# Resolução do viewport (lida em _ready) — usada para calcular o zoom mínimo
# que ainda mantém a cidade inteira visível sem mostrar fundo preto.
var VIEWPORT_LARGURA: float = 1920.0
var VIEWPORT_ALTURA: float = 1080.0

var fonte_pixel = preload("res://assets/fonts/m5x7.ttf")
var escala_camada = [1.0, 0.88, 0.78, 0.68]
var sequencia_espiral = [6, 6, 5, 5, 4, 4, 3, 3, 2, 2, 1, 1]
var direcoes = [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]

var cores_grupos = {
								"Cinza": Color(0.35, 0.35, 0.35),
								"Marrom": Color(0.6, 0.4, 0.2),
								"Rosa": Color(0.9, 0.4, 0.7),
								"Laranja": Color(1.0, 0.6, 0.1),
								"Vermelho": Color(0.8, 0.1, 0.15),
								"Amarelo": Color(0.9, 0.8, 0.1),
								"Verde": Color(0.15, 0.7, 0.3),
								"Azul-Escuro": Color(0.1, 0.2, 0.5),
								"Utilidade": Color(0.3, 0.6, 0.8),
								"Transporte": Color(0.2, 0.2, 0.25),
								"Especial": Color(0.85, 0.85, 0.85),
								"Portal": Color(0.1, 0.8, 0.9)
}

# Tabela fixa de aluguel por nível. As propriedades comuns usam valores
# individuais alinhados ao GDD, em vez de fórmulas baseadas no preço.
# Nível 0 = terreno vazio, níveis 1 a 4 = casas e nível 5 = hotel.
const CHAVE_ALUGUEL_POR_NIVEL := {
	0: "aluguel_base",
	1: "aluguel_1_casa",
	2: "aluguel_2_casas",
	3: "aluguel_3_casas",
	4: "aluguel_4_casas",
	5: "aluguel_hotel",
}

var tabuleiro = {
								0:  {"nome": "Partida", "tipo": "especial", "grupo": "Especial", "preco": 0, "imagem": "partida.png"},
								1:  {"nome": "Periferia\nNorte", "tipo": "propriedade", "grupo": "Cinza", "preco": 60, "nivel": 0, "aluguel_base": 4, "aluguel_1_casa": 20, "aluguel_2_casas": 55, "aluguel_3_casas": 110, "aluguel_4_casas": 180, "aluguel_hotel": 250},
								2:  {"nome": "Destino da Cidade", "tipo": "carta", "grupo": "Especial", "preco": 0, "imagem": "destino.png"},
								3:  {"nome": "Vila\nOperária", "tipo": "propriedade", "grupo": "Cinza", "preco": 80, "nivel": 0, "aluguel_base": 6, "aluguel_1_casa": 25, "aluguel_2_casas": 65, "aluguel_3_casas": 125, "aluguel_4_casas": 200, "aluguel_hotel": 250},
								4:  {"nome": "Imposto de\nRenda", "tipo": "especial", "grupo": "Especial", "preco": 0, "imagem": "imposto_renda.png"},
								5:  {"nome": "Linha\nVermelha", "tipo": "transporte", "grupo": "Transporte", "preco": 200, "imagem": "transporte.png"},
								6:  {"nome": "Zona\nPortuária", "tipo": "propriedade", "grupo": "Marrom", "preco": 100, "nivel": 0, "aluguel_base": 8, "aluguel_1_casa": 30, "aluguel_2_casas": 90, "aluguel_3_casas": 180, "aluguel_4_casas": 300, "aluguel_hotel": 400},
								7:  {"nome": "Bônus\nProdutivo", "tipo": "especial", "grupo": "Especial", "preco": 0, "imagem": "bonus.png"},
								8:  {"nome": "Docas\nVelhas", "tipo": "propriedade", "grupo": "Marrom", "preco": 120, "nivel": 0, "aluguel_base": 12, "aluguel_1_casa": 35, "aluguel_2_casas": 100, "aluguel_3_casas": 200, "aluguel_4_casas": 325, "aluguel_hotel": 400},
								9:  {"nome": "Ordem\nUrbana", "tipo": "carta", "grupo": "Especial", "preco": 0, "imagem": "ordem.png"},
								10: {"nome": "Prisão/\nVisita", "tipo": "especial", "grupo": "Especial", "preco": 0, "imagem": "prisao_visita.png"},
								11: {"nome": "Bairro\nBoemia", "tipo": "propriedade", "grupo": "Rosa", "preco": 140, "nivel": 0, "aluguel_base": 12, "aluguel_1_casa": 40, "aluguel_2_casas": 120, "aluguel_3_casas": 260, "aluguel_4_casas": 430, "aluguel_hotel": 550},
								12: {"nome": "Portal\nNorte", "tipo": "portal", "grupo": "Portal", "preco": 0, "imagem": "portal.png"},
								13: {"nome": "Corredor\nCultural", "tipo": "propriedade", "grupo": "Rosa", "preco": 160, "nivel": 0, "aluguel_base": 16, "aluguel_1_casa": 45, "aluguel_2_casas": 135, "aluguel_3_casas": 285, "aluguel_4_casas": 460, "aluguel_hotel": 550},
								14: {"nome": "ENEM\n(Energia)", "tipo": "utilidade", "grupo": "Utilidade", "preco": 150, "imagem": "energia.png"},
								15: {"nome": "Avenida\nComercial", "tipo": "propriedade", "grupo": "Laranja", "preco": 180, "nivel": 0, "aluguel_base": 16, "aluguel_1_casa": 55, "aluguel_2_casas": 165, "aluguel_3_casas": 360, "aluguel_4_casas": 560, "aluguel_hotel": 700},
								16: {"nome": "Linha\nAmarela", "tipo": "transporte", "grupo": "Transporte", "preco": 200, "imagem": "transporte.png"},
								17: {"nome": "Zona de\nObras", "tipo": "especial", "grupo": "Especial", "preco": 0, "imagem": "obras.png"},
								18: {"nome": "Shopping\nDistrict", "tipo": "propriedade", "grupo": "Laranja", "preco": 200, "nivel": 0, "aluguel_base": 20, "aluguel_1_casa": 60, "aluguel_2_casas": 180, "aluguel_3_casas": 390, "aluguel_4_casas": 590, "aluguel_hotel": 700},
								19: {"nome": "Ordem\nUrbana", "tipo": "carta", "grupo": "Especial", "preco": 0, "imagem": "ordem.png"},
								20: {"nome": "Parque\nLivre", "tipo": "especial", "grupo": "Especial", "preco": 0, "imagem": "parque.png"},
								21: {"nome": "Zona\nFinanceira", "tipo": "propriedade", "grupo": "Vermelho", "preco": 220, "nivel": 0, "aluguel_base": 20, "aluguel_1_casa": 65, "aluguel_2_casas": 200, "aluguel_3_casas": 440, "aluguel_4_casas": 700, "aluguel_hotel": 900},
								22: {"nome": "Acordo de\nSilêncio", "tipo": "especial", "grupo": "Especial", "preco": 0, "imagem": "silencio.png"},
								23: {"nome": "Torre dos\nBancos", "tipo": "propriedade", "grupo": "Vermelho", "preco": 240, "nivel": 0, "aluguel_base": 24, "aluguel_1_casa": 70, "aluguel_2_casas": 215, "aluguel_3_casas": 470, "aluguel_4_casas": 740, "aluguel_hotel": 900},
								24: {"nome": "Linha\nAzul", "tipo": "transporte", "grupo": "Transporte", "preco": 200, "imagem": "transporte.png"},
								25: {"nome": "Colina\nResidenc.", "tipo": "propriedade", "grupo": "Amarelo", "preco": 260, "nivel": 0, "aluguel_base": 24, "aluguel_1_casa": 80, "aluguel_2_casas": 235, "aluguel_3_casas": 520, "aluguel_4_casas": 830, "aluguel_hotel": 1100},
								26: {"nome": "Destino da\nCidade", "tipo": "carta", "grupo": "Especial", "preco": 0, "imagem": "destino.png"},
								27: {"nome": "Condomínio\nFechado", "tipo": "propriedade", "grupo": "Amarelo", "preco": 280, "nivel": 0, "aluguel_base": 28, "aluguel_1_casa": 85, "aluguel_2_casas": 250, "aluguel_3_casas": 550, "aluguel_4_casas": 870, "aluguel_hotel": 1100},
								28: {"nome": "Portal\nSul", "tipo": "portal", "grupo": "Portal", "preco": 0, "imagem": "portal.png"},
								29: {"nome": "SAEM\n(Água)", "tipo": "utilidade", "grupo": "Utilidade", "preco": 150, "imagem": "agua.png"},
								30: {"nome": "Vá para\na Prisão", "tipo": "especial", "grupo": "Especial", "preco": 0, "imagem": "va_para_prisao.png"},
								31: {"nome": "Eco-Hub", "tipo": "propriedade", "grupo": "Verde", "preco": 300, "nivel": 0, "aluguel_base": 28, "aluguel_1_casa": 90, "aluguel_2_casas": 270, "aluguel_3_casas": 600, "aluguel_4_casas": 950, "aluguel_hotel": 1300},
								32: {"nome": "Ordem\nUrbana", "tipo": "carta", "grupo": "Especial", "preco": 0, "imagem": "ordem.png"},
								33: {"nome": "Colapso\nEstrut.", "tipo": "especial", "grupo": "Especial", "preco": 0, "imagem": "colapso.png"},
								34: {"nome": "Parque\nTecnol.", "tipo": "propriedade", "grupo": "Verde", "preco": 320, "nivel": 0, "aluguel_base": 32, "aluguel_1_casa": 95, "aluguel_2_casas": 290, "aluguel_3_casas": 630, "aluguel_4_casas": 1000, "aluguel_hotel": 1300},
								35: {"nome": "Linha\nVerde", "tipo": "transporte", "grupo": "Transporte", "preco": 200, "imagem": "transporte.png"},
								36: {"nome": "Destino da\nCidade", "tipo": "carta", "grupo": "Especial", "preco": 0, "imagem": "destino.png"},
								37: {"nome": "Penthouse\nDistrict", "tipo": "propriedade", "grupo": "Azul-Escuro", "preco": 350, "nivel": 0, "aluguel_base": 35, "aluguel_1_casa": 110, "aluguel_2_casas": 350, "aluguel_3_casas": 800, "aluguel_4_casas": 1350, "aluguel_hotel": 2000},
								38: {"nome": "Imposto de\nLuxo", "tipo": "especial", "grupo": "Especial", "preco": 0, "imagem": "imposto_luxo.png"},
								39: {"nome": "Ilha\nExclusiva", "tipo": "propriedade", "grupo": "Azul-Escuro", "preco": 400, "nivel": 0, "aluguel_base": 50, "aluguel_1_casa": 130, "aluguel_2_casas": 400, "aluguel_3_casas": 900, "aluguel_4_casas": 1500, "aluguel_hotel": 2000}
}

# ============================================================================
# TABELAS DE ECONOMIA — ALUGUÉIS FIXOS DO GDD
# ============================================================================
const CAMPOS_SNAPSHOT_ONLINE: Array[String] = [
	"registro_propriedades",
	"lista_turnos",
	"indice_turno_atual",
	"jogador_atual_id",
	"lances_leilao_atuais",
	"leilao_em_andamento",
	"casa_em_leilao",
	"rodada_atual",
	"rodada_aquisicao_propriedade",
	"evento_ativo",
	"ultimo_evento_sorteado",
	"tendencias_fixas",
	"tendencias_turnos_restantes",
	"proximo_evento_global",
	"proximo_evento_descricao",
	"_imunidade_breno_bloqueando_acoes",
	"_breno_evento_imune_atual",
	"_evento_resolvido_apos_decisao_breno",
	"multiplicador_inflacao_global",
	"deck_destino_atual",
	"deck_ordem_atual",
	"dados_economia_jogadores",
	"obrigacoes_falencia_pendentes",
	"ultimo_dado1",
	"ultimo_dado2",
	"acordo_silencio_ativo",
	"turno_construcao_bloqueada",
	"ultimo_grupo_zoneamento",
	"jogadores_ativos",
	"_votos_eleicao",
	"_votacao_eleicao_ativa",
	"_eleicao_bloqueando_acoes",
	"_eleicao_id_atual",
	"_eleicao_jogadores_elegiveis",
	"_eleicao_resultado_aplicado_id",
	"_eleicao_falencias_pendentes",
	"_pacote_eleicao_vencedor",
	"_evento_interativo_bloqueando_acoes",
	"_fluxo_evento_interativo_ativo",
	"_fluxo_evento_interativo_nome",
	"_sessao_decisao_evento_id",
	"_sessao_decisao_evento_ativa",
	"_sessao_decisao_evento_prompts",
	"_sessao_decisao_evento_respostas",
	"_falencias_pendentes_evento",
	"_ilha_calor_prop_interditada",
	"_ilha_calor_interditacao_turnos",
	"_corrupcao_props_embargadas",
	"_corrupcao_embargo_turnos",
	"_carta_valorizacao_casa",
	"_carta_valorizacao_turnos",
	"_carta_embargo_judicial_casa",
	"_carta_embargo_judicial_turnos",
	"_carta_parque_casa",
	"_carta_parque_turnos",
	"_carta_acao_coletiva_ativa",
	"_carta_bloqueio_trafego",
	"_carta_premio_casa",
	"_carta_premio_turnos",
	"_protestos_bloqueio_hotel",
	"_protestos_bloqueio_turnos",
	"_carros_autonomos_permanente",
	"efeitos_temporarios",
	"_sequencia_efeitos",
	"ordem_original_partida",
	"_contador_turnos_globais",
	"_contador_acoes_historico",
	"_historico_acoes",
	"_snapshots_finais",
	"_pausa_global_ativa",
	"_peer_iniciador_pausa",
	"_personagem_iniciador_pausa",
	"_nome_iniciador_pausa",
	"_partida_encerrada",
	"_evento_xp_em_andamento",
	"_evento_xp_nome",
	"_evento_xp_perdas_construcao",
	"_dupla_pendente",
	"_leilao_counter",
	"_leilao_falencia_ativo",
	"_props_leilao_falencia",
	"_fila_resolucoes_abutre",
	"_processando_resolucoes_abutre",
	"_abutre_bloqueando_acoes",
	"_leilao_evento_ativo",
	"_props_leilao_evento",
	"_leilao_contexto_atual",
	"_leilao_lance_minimo_atual",
	"_propostas_negociacao_pendentes",
	"_promessas_globais",
]

var _sincronizacao_online_concluida: bool = false
var _jogadores_desconectados_online: Dictionary = {}
var _cinematica_abertura_iniciada: bool = false
var _cinematica_abertura_concluida: bool = false
var _tween_cinematica_abertura: Tween = null
var _tentativas_snapshot_inicial: int = 0
var _ultimo_snapshot_online_aplicado: int = -1
var _layout_tabuleiro_pronto: bool = false
var _aviso_layout_tabuleiro_emitido: bool = false

# ============================================================================
# INICIALIZAÇÃO
# ============================================================================
var _processando_dados: bool = false
# Mantém o autosave fora do intervalo entre uma rolagem/carta e a liberação do
# próximo turno. Nesse período o estado já pode ter mudado, mas a corrotina que
# concluirá a jogada ainda não pode ser reconstruída ao recarregar a cena.
var _resolucao_turno_em_andamento: bool = false
# --- NOVO (GDD §5.2): Flag que indica que o jogador tirou dupla e deve
#     rolar novamente após o movimento. Sincronizada via RPC. ---
var _dupla_pendente: bool = false

var _lance_local_leilao: int = -1
var _leilao_timeout: bool = false
var _leilao_counter: int = 0  # ID único por leilão — invalida timers antigos

# --- NOVO (GDD §9.1): Sistema de leilão na falência.
#     Quando um jogador falencia, suas propriedades vão a leilão uma por uma
#     entre os jogadores restantes. Apenas o server inicia cada leilão.
#     _finalizar_leilao_rede verifica a flag para não passar o turno. ---
var _leilao_falencia_ativo: bool = false
var _props_leilao_falencia: Array = []  # fila de propriedades a leiloar
var _fila_resolucoes_abutre: Array = []
var _processando_resolucoes_abutre: bool = false
var _abutre_bloqueando_acoes: bool = false

# Leilão especial de Migração em Massa. Usa o mesmo motor de lances, mas
# não encerra o turno e exige lance mínimo de 50% do valor de tabela.
var _leilao_evento_ativo: bool = false
var _props_leilao_evento: Array = []
var _leilao_contexto_atual: String = "normal"
var _leilao_lance_minimo_atual: int = 0

# --- NOVO: Handler do timeout local do leilão ---
const RECARGAS_HABILIDADES = {
								"yasmin": 5, "breno": 5, "mira": 4, "igor": 6, "diana": 3, "kofi": 4
}

const NOMES_HABILIDADES = {
								"yasmin": "Oferta Irrecusável",
								"breno": "Decreto Emergencial",
								"mira": "Retrofit Urbano",
								"igor": "Especulação Imobiliária",
								"diana": "Vazamento Seletivo",
								"kofi": "Mutirão"
}

const DESC_HABILIDADES = {
								"yasmin": "Compre por 150% do valor uma propriedade vazia de um grupo em que você já possui terreno. Não desmonta monopólios, exige 2 rodadas de posse e cada adversário só pode ser alvo uma vez.",
								"breno": "Dobre os aluguéis de um grupo de cor por 2 turnos. Preferência automática: seus monopólios primeiro.",
								"mira": "Converta 2 casas em 1 hotel instantaneamente em uma propriedade sua, sem pagar a diferença.",
								"igor": "Dobre o aluguel base de qualquer terreno vazio (seu ou de outros) por 3 turnos.",
								"diana": "Anule o próximo aluguel que um adversário deveria receber. O efeito permanece até acontecer.",
								"kofi": "Construa IMEDIATAMENTE 1 casa em uma propriedade sua pagando apenas 60% do custo."
}

# --- NOVO (UI de seleção de alvo): descrições curtas usadas no overlay.
#     São mais detalhadas que DESC_HABILIDADES porque explicam COMO selecionar
#     o alvo. ---
const DESC_HABILIDADES_UI = {
								"yasmin": "Selecione uma propriedade VAZIA de um grupo em que Yasmin já possui terreno. O dono não pode ter monopólio, deve possuir o ativo há 2 rodadas e não pode já ter sido alvo. Custo: 150% do valor de tabela.",
								"breno": "Selecione um GRUPO DE COR para dobrar os aluguéis por 2 turnos. Afeta todos os jogadores (inclusive Breno). Dica: prefira grupos onde você tem monopólio.",
								"mira": "Selecione uma SUA propriedade com EXATAMENTE 2 casas. Ela será convertida em HOTEL instantaneamente (grátis).",
								"igor": "Selecione qualquer TERRENO VAZIO (nível 0, de qualquer dono). O aluguel base dele será dobrado por 3 turnos.",
								"diana": "Selecione um OPONENTE. O próximo aluguel válido que ele receber será anulado; o efeito não expira por turnos.",
								"kofi": "Selecione uma SUA propriedade (nível < 5). Uma casa será construída IMEDIATAMENTE pagando 60% do custo (40% OFF)."
}

# --- NOVO (UI de seleção de alvo): chamado quando o jogador clica no botão de
#     habilidade. Valida cooldown e bloqueios de evento, depois computa a lista
#     de alvos válidos e mostra o overlay com a lista populada. ---
var _propostas_negociacao_pendentes: Dictionary = {}

# --- NOVO (Fase 4 — Promessas): lista global de promessas públicas.
#     Cada promessa é um Dictionary: {
#       "id": "prom_xxx",          # ID único
#       "autor_id": "yasmin",       # quem fez a promessa
#       "texto": "Não vou...",      # texto livre
#       "quebrada": false,          # se foi marcada como quebrada
#       "quebrada_por": ""          # quem marcou como quebrada
#     }
#     Visível para todos os jogadores. Sem enforce mecânico. ---
var _promessas_globais: Array = []

# --- Função pública: fornece as referências de dados para o painel da HUD ---
# Retorna um Dictionary com chaves: dados_jogadores, tabuleiro_data, registro_props.
# A HUD chama isto via get_tree().get_first_node_in_group("tabuleiro_principal").

# ============================================================================
# CONTRATOS INTERNOS PARA OS MÓDULOS
# Não contêm regras de jogo. As implementações reais estão nos scripts filhos.
# ============================================================================

@warning_ignore("unused_parameter")
func _obter_aluguel_tabela(casa_id: int, nivel: int = -1) -> int:
	push_error("Contrato interno chamado sem implementação: _obter_aluguel_tabela")
	return 0

@warning_ignore("unused_parameter")
func _validar_tabelas_aluguel() -> void:
	push_error("Contrato interno chamado sem implementação: _validar_tabelas_aluguel")
	pass

@warning_ignore("unused_parameter")
func _ready() -> void:
	push_error("Contrato interno chamado sem implementação: _ready")
	pass

@warning_ignore("unused_parameter")
func _cor_visual_personagem(personagem_id: String) -> Color:
	push_error("Contrato interno chamado sem implementação: _cor_visual_personagem")
	return Color.WHITE

@warning_ignore("unused_parameter")
func _configurar_bots_locais() -> void:
	push_error("Contrato interno chamado sem implementação: _configurar_bots_locais")
	pass

@warning_ignore("unused_parameter")
func _eh_jogador_bot(id_jogador: String) -> bool:
	push_error("Contrato interno chamado sem implementação: _eh_jogador_bot")
	return false

@warning_ignore("unused_parameter")
func definir_bots_pausados(pausados: bool) -> void:
	push_error("Contrato interno chamado sem implementação: definir_bots_pausados")
	pass

@warning_ignore("unused_parameter")
func executar_rolagem_bot(
	id_jogador: String,
	dado1: int,
	dado2: int
) -> void:
	push_error("Contrato interno chamado sem implementação: executar_rolagem_bot")
	pass

@warning_ignore("unused_parameter")
func obter_resultado_dados_tutorial() -> Vector2i:
	push_error("Contrato interno chamado sem implementação: obter_resultado_dados_tutorial")
	return Vector2i.ZERO

@warning_ignore("unused_parameter")
func _solicitar_turno_bot(id_jogador: String) -> void:
	push_error("Contrato interno chamado sem implementação: _solicitar_turno_bot")
	pass

@warning_ignore("unused_parameter")
func _emitir_evento_tutorial(tipo: String, dados: Dictionary = {}) -> void:
	push_error("Contrato interno chamado sem implementação: _emitir_evento_tutorial")
	pass

@warning_ignore("unused_parameter")
func preparar_cenario_tutorial_expandido() -> void:
	push_error("Contrato interno chamado sem implementação: preparar_cenario_tutorial_expandido")
	pass

@warning_ignore("unused_parameter")
func obter_retangulo_tile_tutorial(casa_id: int) -> Rect2:
	push_error("Contrato interno chamado sem implementação: obter_retangulo_tile_tutorial")
	return Rect2()

@warning_ignore("unused_parameter")
func definir_nivel_construcao_tutorial(casa_id: int, nivel: int) -> bool:
	push_error("Contrato interno chamado sem implementação: definir_nivel_construcao_tutorial")
	return false

@warning_ignore("unused_parameter")
func obter_resultado_tutorial_rapido() -> Dictionary:
	push_error("Contrato interno chamado sem implementação: obter_resultado_tutorial_rapido")
	return {}

@warning_ignore("unused_parameter")
func _preparar_espera_snapshot_online() -> void:
	push_error("Contrato interno chamado sem implementação: _preparar_espera_snapshot_online")
	pass

@warning_ignore("unused_parameter")
func _iniciar_sincronizacao_online() -> void:
	push_error("Contrato interno chamado sem implementação: _iniciar_sincronizacao_online")
	pass

@warning_ignore("unused_parameter")
func _publicar_snapshot_inicial_online() -> void:
	push_error("Contrato interno chamado sem implementação: _publicar_snapshot_inicial_online")
	pass

@warning_ignore("unused_parameter")
func _vigiar_entrada_visual_online() -> void:
	push_error("Contrato interno chamado sem implementação: _vigiar_entrada_visual_online")
	pass

@warning_ignore("unused_parameter")
func _exit_tree() -> void:
	push_error("Contrato interno chamado sem implementação: _exit_tree")
	pass

@warning_ignore("unused_parameter")
func validar_salvamento_partida() -> String:
	push_error("Contrato interno chamado sem implementação: validar_salvamento_partida")
	return ""

@warning_ignore("unused_parameter")
func criar_snapshot_online() -> Dictionary:
	push_error("Contrato interno chamado sem implementação: criar_snapshot_online")
	return {}

@warning_ignore("unused_parameter")
func _criar_estado_tabuleiro_mutavel() -> Dictionary:
	push_error("Contrato interno chamado sem implementação: _criar_estado_tabuleiro_mutavel")
	return {}

@warning_ignore("unused_parameter")
func _aplicar_estado_tabuleiro_mutavel(estado_tabuleiro: Dictionary) -> void:
	push_error("Contrato interno chamado sem implementação: _aplicar_estado_tabuleiro_mutavel")
	pass

@warning_ignore("unused_parameter")
func aplicar_snapshot_online(snapshot: Dictionary) -> void:
	push_error("Contrato interno chamado sem implementação: aplicar_snapshot_online")
	pass

@warning_ignore("unused_parameter")
func _sincronizar_pinos_com_snapshot(estados_pinos: Dictionary) -> void:
	push_error("Contrato interno chamado sem implementação: _sincronizar_pinos_com_snapshot")
	pass

@warning_ignore("unused_parameter")
func _reconstruir_visuais_apos_snapshot(estados_pinos: Dictionary) -> void:
	push_error("Contrato interno chamado sem implementação: _reconstruir_visuais_apos_snapshot")
	pass

@warning_ignore("unused_parameter")
func _on_jogador_desconectado_online(peer_id: int, inativo: bool) -> void:
	push_error("Contrato interno chamado sem implementação: _on_jogador_desconectado_online")
	pass

@warning_ignore("unused_parameter")
func _on_jogador_reconectado_online(id_antigo: int, id_novo: int, _user_id: String) -> void:
	push_error("Contrato interno chamado sem implementação: _on_jogador_reconectado_online")
	pass

@warning_ignore("unused_parameter")
func _on_host_alterado_online(eh_novo_host: bool) -> void:
	push_error("Contrato interno chamado sem implementação: _on_host_alterado_online")
	pass

@warning_ignore("unused_parameter")
func _on_dados_rolados_recebidos(d1: int, d2: int):
	push_error("Contrato interno chamado sem implementação: _on_dados_rolados_recebidos")
	pass

@warning_ignore("unused_parameter")
func _avancar_turno():
	push_error("Contrato interno chamado sem implementação: _avancar_turno")
	pass

@warning_ignore("unused_parameter")
func _atualizar_hud_ciclo_turno():
	push_error("Contrato interno chamado sem implementação: _atualizar_hud_ciclo_turno")
	pass

@warning_ignore("unused_parameter")
func _atualizar_hud_minha_casa():
	push_error("Contrato interno chamado sem implementação: _atualizar_hud_minha_casa")
	pass

@warning_ignore("unused_parameter")
func _atualizar_menu_construcao():
	push_error("Contrato interno chamado sem implementação: _atualizar_menu_construcao")
	pass

@warning_ignore("unused_parameter")
func _processar_terreno_pousado(casa_id: int) -> void:
	push_error("Contrato interno chamado sem implementação: _processar_terreno_pousado")
	pass

@warning_ignore("unused_parameter")
func _executar_casa_especial(casa_id: int):
	push_error("Contrato interno chamado sem implementação: _executar_casa_especial")
	pass

@warning_ignore("unused_parameter")
func _ir_para_prisao_rede(id_jogador: String):
	push_error("Contrato interno chamado sem implementação: _ir_para_prisao_rede")
	pass

@warning_ignore("unused_parameter")
func _sair_da_prisao_rede(id_jogador: String):
	push_error("Contrato interno chamado sem implementação: _sair_da_prisao_rede")
	pass

@warning_ignore("unused_parameter")
func _continuar_preso_passar_turno_rede():
	push_error("Contrato interno chamado sem implementação: _continuar_preso_passar_turno_rede")
	pass

@warning_ignore("unused_parameter")
func _registrar_obrigacao_falencia(
	devedor_id: String,
	credor_id: String,
	valor: int
) -> void:
	push_error("Contrato interno chamado sem implementação: _registrar_obrigacao_falencia")
	pass

@warning_ignore("unused_parameter")
func _limpar_obrigacoes_falencia(devedor_id: String) -> void:
	push_error("Contrato interno chamado sem implementação: _limpar_obrigacoes_falencia")
	pass

@warning_ignore("unused_parameter")
func _aplicar_mudanca_dinheiro_rede(
	id_jogador: String,
	valor: int,
	origem: String = "carta_evento",
	adiar_verificacao_falencia: bool = false,
	eliminador_id: String = ""
) -> void:
	push_error("Contrato interno chamado sem implementação: _aplicar_mudanca_dinheiro_rede")
	pass

@warning_ignore("unused_parameter")
func _quantidade_linhas_metro(jogador_id: String) -> int:
	push_error("Contrato interno chamado sem implementação: _quantidade_linhas_metro")
	return 0

@warning_ignore("unused_parameter")
func _conceder_passes_transporte(concedente_id: String, beneficiario_id: String, quantidade: int) -> void:
	push_error("Contrato interno chamado sem implementação: _conceder_passes_transporte")
	pass

@warning_ignore("unused_parameter")
func _consumir_passe_transporte(beneficiario_id: String, dono_linha_id: String) -> bool:
	push_error("Contrato interno chamado sem implementação: _consumir_passe_transporte")
	return false

@warning_ignore("unused_parameter")
func _pagar_aluguel_rede(pagador: String, recebedor: String, valor: int, casa_id: int = -1):
	push_error("Contrato interno chamado sem implementação: _pagar_aluguel_rede")
	pass

@warning_ignore("unused_parameter")
func _efetuar_compra_rede(id_comprador: String, casa_id: int):
	push_error("Contrato interno chamado sem implementação: _efetuar_compra_rede")
	pass

@warning_ignore("unused_parameter")
func _sacar_carta_no_servidor(nome_deck: String):
	push_error("Contrato interno chamado sem implementação: _sacar_carta_no_servidor")
	pass

@warning_ignore("unused_parameter")
func _disparar_inflacao_global():
	push_error("Contrato interno chamado sem implementação: _disparar_inflacao_global")
	pass

@warning_ignore("unused_parameter")
func _aplicar_mudanca_carta(
	id_jogador: String,
	valor: int,
	credor_id: String = "",
	registrar_obrigacao: bool = true
) -> int:
	push_error("Contrato interno chamado sem implementação: _aplicar_mudanca_carta")
	return 0

@warning_ignore("unused_parameter")
func _propriedades_do_jogador_para_carta(id_jogador: String, exigir_construcao: bool = false) -> Array:
	push_error("Contrato interno chamado sem implementação: _propriedades_do_jogador_para_carta")
	return []

@warning_ignore("unused_parameter")
func _indice_deterministico_carta(opcoes: Array, alvo_id: String, carta_nome: String) -> int:
	push_error("Contrato interno chamado sem implementação: _indice_deterministico_carta")
	return 0

@warning_ignore("unused_parameter")
func _conceder_propriedade_gratis_carta(alvo_id: String, carta_nome: String) -> int:
	push_error("Contrato interno chamado sem implementação: _conceder_propriedade_gratis_carta")
	return 0

@warning_ignore("unused_parameter")
func _proximo_jogador_ativo(id_jogador: String) -> String:
	push_error("Contrato interno chamado sem implementação: _proximo_jogador_ativo")
	return ""

@warning_ignore("unused_parameter")
func _propriedade_vizinha_da_posicao(posicao: int) -> int:
	push_error("Contrato interno chamado sem implementação: _propriedade_vizinha_da_posicao")
	return 0

@warning_ignore("unused_parameter")
func _grupo_bairro_vizinho_da_posicao(posicao: int) -> String:
	push_error("Contrato interno chamado sem implementação: _grupo_bairro_vizinho_da_posicao")
	return ""

@warning_ignore("unused_parameter")
func _aplicar_carta_rede(alvo_id: String, nome_deck: String, carta_nome: String, carta_desc: String, tipo_efeito: String, valor: float):
	push_error("Contrato interno chamado sem implementação: _aplicar_carta_rede")
	pass

@warning_ignore("unused_parameter")
func _iniciar_leilao_rede(id_casa: int, lance_minimo: int = 0, contexto: String = "normal"):
	push_error("Contrato interno chamado sem implementação: _iniciar_leilao_rede")
	pass

@warning_ignore("unused_parameter")
func _on_leilao_timeout_local():
	push_error("Contrato interno chamado sem implementação: _on_leilao_timeout_local")
	pass

@warning_ignore("unused_parameter")
func _on_lance_local_recebido(valor: int):
	push_error("Contrato interno chamado sem implementação: _on_lance_local_recebido")
	pass

@warning_ignore("unused_parameter")
func _receber_lance_no_servidor(id_jogador: String, valor: int):
	push_error("Contrato interno chamado sem implementação: _receber_lance_no_servidor")
	pass

@warning_ignore("unused_parameter")
func _calcular_vencedor_leilao():
	push_error("Contrato interno chamado sem implementação: _calcular_vencedor_leilao")
	pass

@warning_ignore("unused_parameter")
func _finalizar_leilao_rede(id_vencedor: String, valor_pago: int, casa_id: int):
	push_error("Contrato interno chamado sem implementação: _finalizar_leilao_rede")
	pass

@warning_ignore("unused_parameter")
func _finalizar_pouso_e_passar_turno():
	push_error("Contrato interno chamado sem implementação: _finalizar_pouso_e_passar_turno")
	pass

@warning_ignore("unused_parameter")
func _set_dupla_status_rede(jogador_id: String, is_dupla: bool, duplas_count: int):
	push_error("Contrato interno chamado sem implementação: _set_dupla_status_rede")
	pass

@warning_ignore("unused_parameter")
func _executar_portal_atalho(casa_id: int):
	push_error("Contrato interno chamado sem implementação: _executar_portal_atalho")
	pass

@warning_ignore("unused_parameter")
func _sincronizar_movimento_na_rede(id_do_personagem: String, passos: int):
	push_error("Contrato interno chamado sem implementação: _sincronizar_movimento_na_rede")
	pass

@warning_ignore("unused_parameter")
func _processar_passagem_de_turno():
	push_error("Contrato interno chamado sem implementação: _processar_passagem_de_turno")
	pass

@warning_ignore("unused_parameter")
func _avancar_turno_rede():
	push_error("Contrato interno chamado sem implementação: _avancar_turno_rede")
	pass

@warning_ignore("unused_parameter")
func _mudar_turno_no_servidor():
	push_error("Contrato interno chamado sem implementação: _mudar_turno_no_servidor")
	pass

@warning_ignore("unused_parameter")
func _e_imune_a_confisco(jogador_id: String) -> bool:
	push_error("Contrato interno chamado sem implementação: _e_imune_a_confisco")
	return false

@warning_ignore("unused_parameter")
func _sabotagem_bloqueada_por_raizes(jogador_id: String, carta_nome: String) -> bool:
	push_error("Contrato interno chamado sem implementação: _sabotagem_bloqueada_por_raizes")
	return false

@warning_ignore("unused_parameter")
func _tem_monopolio(id_jogador: String, grupo: String) -> bool:
	push_error("Contrato interno chamado sem implementação: _tem_monopolio")
	return false

@warning_ignore("unused_parameter")
func _sao_aliados(id_a: String, id_b: String) -> bool:
	push_error("Contrato interno chamado sem implementação: _sao_aliados")
	return false

@warning_ignore("unused_parameter")
func _pode_construir(id_jogador: String, grupo: String) -> bool:
	push_error("Contrato interno chamado sem implementação: _pode_construir")
	return false

@warning_ignore("unused_parameter")
func _acoes_bloqueadas_por_evento() -> bool:
	push_error("Contrato interno chamado sem implementação: _acoes_bloqueadas_por_evento")
	return false

@warning_ignore("unused_parameter")
func _acao_bloqueada_por_eleicao(mostrar_feedback: bool = false) -> bool:
	push_error("Contrato interno chamado sem implementação: _acao_bloqueada_por_eleicao")
	return false

@warning_ignore("unused_parameter")
func _ativar_efeito_temporario(chave: String, tipo: String, turnos: int, dados: Dictionary = {}, pular_proximo_decremento: bool = false) -> void:
	push_error("Contrato interno chamado sem implementação: _ativar_efeito_temporario")
	pass

@warning_ignore("unused_parameter")
func _criar_efeito_unico(prefixo: String, tipo: String, turnos: int, dados: Dictionary = {}, pular_proximo_decremento: bool = false) -> String:
	push_error("Contrato interno chamado sem implementação: _criar_efeito_unico")
	return ""

@warning_ignore("unused_parameter")
func _tem_efeito_temporario(chave: String) -> bool:
	push_error("Contrato interno chamado sem implementação: _tem_efeito_temporario")
	return false

@warning_ignore("unused_parameter")
func _efeitos_ativos_por_tipo(tipo: String) -> Array:
	push_error("Contrato interno chamado sem implementação: _efeitos_ativos_por_tipo")
	return []

@warning_ignore("unused_parameter")
func _efeito_aplica_na_casa(efeito: Dictionary, casa_id: int) -> bool:
	push_error("Contrato interno chamado sem implementação: _efeito_aplica_na_casa")
	return false

@warning_ignore("unused_parameter")
func _construcao_bloqueada_por_efeito(id_jogador: String, casa_id: int) -> bool:
	push_error("Contrato interno chamado sem implementação: _construcao_bloqueada_por_efeito")
	return false

@warning_ignore("unused_parameter")
func _decrementar_efeitos_temporarios() -> void:
	push_error("Contrato interno chamado sem implementação: _decrementar_efeitos_temporarios")
	pass

@warning_ignore("unused_parameter")
func _ao_expirar_efeito_temporario(efeito: Dictionary) -> void:
	push_error("Contrato interno chamado sem implementação: _ao_expirar_efeito_temporario")
	pass

@warning_ignore("unused_parameter")
func _ativar_inverno_startups_rede() -> void:
	push_error("Contrato interno chamado sem implementação: _ativar_inverno_startups_rede")
	pass

@warning_ignore("unused_parameter")
func _jogador_possui_grupo(jogador_id: String, grupos: Array) -> bool:
	push_error("Contrato interno chamado sem implementação: _jogador_possui_grupo")
	return false

@warning_ignore("unused_parameter")
func _jogador_possui_nome(jogador_id: String, trecho_nome: String) -> bool:
	push_error("Contrato interno chamado sem implementação: _jogador_possui_nome")
	return false

@warning_ignore("unused_parameter")
func _processar_efeitos_periodicos_do_turno(jogador_id: String) -> void:
	push_error("Contrato interno chamado sem implementação: _processar_efeitos_periodicos_do_turno")
	pass

@warning_ignore("unused_parameter")
func _obter_aluguel_congelado(casa_id: int, jogador_afetado: String = "") -> int:
	push_error("Contrato interno chamado sem implementação: _obter_aluguel_congelado")
	return 0

@warning_ignore("unused_parameter")
func _aplicar_efeitos_ao_aluguel(casa_id: int, aluguel_base: int, jogador_afetado: String = "") -> int:
	push_error("Contrato interno chamado sem implementação: _aplicar_efeitos_ao_aluguel")
	return 0

@warning_ignore("unused_parameter")
func _calcular_valor_propriedade(casa_id: int) -> int:
	push_error("Contrato interno chamado sem implementação: _calcular_valor_propriedade")
	return 0

@warning_ignore("unused_parameter")
func _calcular_preco_compra(casa_id: int) -> int:
	push_error("Contrato interno chamado sem implementação: _calcular_preco_compra")
	return 0

@warning_ignore("unused_parameter")
func _multiplicador_preco_leilao() -> float:
	push_error("Contrato interno chamado sem implementação: _multiplicador_preco_leilao")
	return 0.0

@warning_ignore("unused_parameter")
func _calcular_bonus_partida(jogador_id: String) -> int:
	push_error("Contrato interno chamado sem implementação: _calcular_bonus_partida")
	return 0

@warning_ignore("unused_parameter")
func _calcular_custo_resgate_hipoteca(casa_id: int) -> int:
	push_error("Contrato interno chamado sem implementação: _calcular_custo_resgate_hipoteca")
	return 0

@warning_ignore("unused_parameter")
func _negociacoes_bloqueadas_por_efeito(jogador_id: String = "") -> bool:
	push_error("Contrato interno chamado sem implementação: _negociacoes_bloqueadas_por_efeito")
	return false

@warning_ignore("unused_parameter")
func _acordo_silencio_bloqueia(jogador_id: String) -> bool:
	push_error("Contrato interno chamado sem implementação: _acordo_silencio_bloqueia")
	return false

@warning_ignore("unused_parameter")
func _habilidades_bloqueadas_por_efeito(jogador_id: String = "") -> bool:
	push_error("Contrato interno chamado sem implementação: _habilidades_bloqueadas_por_efeito")
	return false

@warning_ignore("unused_parameter")
func _calcular_aluguel(casa_id: int, dono_id: String, pagador_id: String = "") -> int:
	push_error("Contrato interno chamado sem implementação: _calcular_aluguel")
	return 0

@warning_ignore("unused_parameter")
func _posicao_final_para_relatorio(posicao: int) -> int:
	push_error("Contrato interno chamado sem implementação: _posicao_final_para_relatorio")
	return 0

@warning_ignore("unused_parameter")
func _probabilidade_trafego_jogador_1_turno(posicao_inicial: int, casa_alvo: int) -> float:
	push_error("Contrato interno chamado sem implementação: _probabilidade_trafego_jogador_1_turno")
	return 0.0

@warning_ignore("unused_parameter")
func _proximos_jogadores_do_relatorio(quantidade: int = 2) -> Array:
	push_error("Contrato interno chamado sem implementação: _proximos_jogadores_do_relatorio")
	return []

@warning_ignore("unused_parameter")
func _gerar_tendencias_yasmin():
	push_error("Contrato interno chamado sem implementação: _gerar_tendencias_yasmin")
	pass

@warning_ignore("unused_parameter")
func _pre_sortear_proximo_evento() -> void:
	push_error("Contrato interno chamado sem implementação: _pre_sortear_proximo_evento")
	pass

@warning_ignore("unused_parameter")
func _sincronizar_proximo_evento_rede(nome_ev: String, desc_ev: String) -> void:
	push_error("Contrato interno chamado sem implementação: _sincronizar_proximo_evento_rede")
	pass

@warning_ignore("unused_parameter")
func _sortear_evento_global() -> void:
	push_error("Contrato interno chamado sem implementação: _sortear_evento_global")
	pass

@warning_ignore("unused_parameter")
func _aplicar_evento_global(nome: String, status: String, descricao: String = ""):
	push_error("Contrato interno chamado sem implementação: _aplicar_evento_global")
	pass

@warning_ignore("unused_parameter")
func _deve_oferecer_imunidade_breno(nome_evento: String) -> bool:
	push_error("Contrato interno chamado sem implementação: _deve_oferecer_imunidade_breno")
	return false

@warning_ignore("unused_parameter")
func _iniciar_decisao_imunidade_breno(nome_evento: String) -> void:
	push_error("Contrato interno chamado sem implementação: _iniciar_decisao_imunidade_breno")
	pass

@warning_ignore("unused_parameter")
func _definir_bloqueio_imunidade_breno_rede(ativo: bool) -> void:
	push_error("Contrato interno chamado sem implementação: _definir_bloqueio_imunidade_breno_rede")
	pass

@warning_ignore("unused_parameter")
func _resolver_evento_global_rede(nome_evento: String, usar_imunidade: bool) -> void:
	push_error("Contrato interno chamado sem implementação: _resolver_evento_global_rede")
	pass

@warning_ignore("unused_parameter")
func _breno_ignora_evento(nome_evento: String = "") -> bool:
	push_error("Contrato interno chamado sem implementação: _breno_ignora_evento")
	return false

@warning_ignore("unused_parameter")
func _aplicar_taxa_drenagem_para_grupos(grupos_afetados: Array) -> void:
	push_error("Contrato interno chamado sem implementação: _aplicar_taxa_drenagem_para_grupos")
	pass

@warning_ignore("unused_parameter")
func _aplicar_taxa_enem_apagao() -> void:
	push_error("Contrato interno chamado sem implementação: _aplicar_taxa_enem_apagao")
	pass

@warning_ignore("unused_parameter")
func _aplicar_dano_evento_em_casa(casa_id: int, reducao: int = 1, zerar: bool = false) -> void:
	push_error("Contrato interno chamado sem implementação: _aplicar_dano_evento_em_casa")
	pass

@warning_ignore("unused_parameter")
func _propriedades_com_grupos(grupos: Array, somente_com_construcao: bool = false) -> Array:
	push_error("Contrato interno chamado sem implementação: _propriedades_com_grupos")
	return []

@warning_ignore("unused_parameter")
func _valor_total_propriedades(jogador_id: String) -> int:
	push_error("Contrato interno chamado sem implementação: _valor_total_propriedades")
	return 0

@warning_ignore("unused_parameter")
func _processar_evento_gdd(nome_evento: String) -> void:
	push_error("Contrato interno chamado sem implementação: _processar_evento_gdd")
	pass

@warning_ignore("unused_parameter")
func _jogadores_ativos_para_evento() -> Array:
	push_error("Contrato interno chamado sem implementação: _jogadores_ativos_para_evento")
	return []

@warning_ignore("unused_parameter")
func _iniciar_fluxo_evento_interativo(nome_evento: String) -> void:
	push_error("Contrato interno chamado sem implementação: _iniciar_fluxo_evento_interativo")
	pass

@warning_ignore("unused_parameter")
func _executar_fluxo_evento_interativo(nome_evento: String) -> void:
	push_error("Contrato interno chamado sem implementação: _executar_fluxo_evento_interativo")
	pass

@warning_ignore("unused_parameter")
func _definir_bloqueio_evento_interativo_rede(ativo: bool, nome_evento: String = "") -> void:
	push_error("Contrato interno chamado sem implementação: _definir_bloqueio_evento_interativo_rede")
	pass

@warning_ignore("unused_parameter")
func _encerrar_fluxo_evento_interativo() -> void:
	push_error("Contrato interno chamado sem implementação: _encerrar_fluxo_evento_interativo")
	pass

@warning_ignore("unused_parameter")
func _executar_sessao_decisoes(
	prompts: Dictionary,
	duracao: int,
	titulo_espera: String,
	descricao_espera: String,
	cor_espera: Color
) -> Dictionary:
	push_error("Contrato interno chamado sem implementação: _executar_sessao_decisoes")
	return {}

@warning_ignore("unused_parameter")
func _mostrar_espera_decisao_evento_rede(
	decisao_id: int,
	alvos: Array,
	titulo: String,
	descricao: String,
	duracao: int,
	cor: Color
) -> void:
	push_error("Contrato interno chamado sem implementação: _mostrar_espera_decisao_evento_rede")
	pass

@warning_ignore("unused_parameter")
func _mostrar_decisao_evento_rede(
	alvo_id: String,
	decisao_id: int,
	prompt: Dictionary,
	duracao: int
) -> void:
	push_error("Contrato interno chamado sem implementação: _mostrar_decisao_evento_rede")
	pass

@warning_ignore("unused_parameter")
func _fechar_decisao_evento_rede(decisao_id: int) -> void:
	push_error("Contrato interno chamado sem implementação: _fechar_decisao_evento_rede")
	pass

@warning_ignore("unused_parameter")
func _on_hud_decisao_evento(decisao_id: int, acao: String, selecionados: Array) -> void:
	push_error("Contrato interno chamado sem implementação: _on_hud_decisao_evento")
	pass

@warning_ignore("unused_parameter")
func _receber_decisao_evento_servidor(
	decisao_id: int,
	acao: String,
	selecionados: Array
) -> void:
	push_error("Contrato interno chamado sem implementação: _receber_decisao_evento_servidor")
	pass

@warning_ignore("unused_parameter")
func _opcao_propriedade_evento(casa_id: int, detalhe_extra: String = "") -> Dictionary:
	push_error("Contrato interno chamado sem implementação: _opcao_propriedade_evento")
	return {}

@warning_ignore("unused_parameter")
func _fluxo_vendaval_seguro() -> void:
	push_error("Contrato interno chamado sem implementação: _fluxo_vendaval_seguro")
	pass

@warning_ignore("unused_parameter")
func _resolver_vendaval_rede(protegidas: Dictionary, propriedades_zeradas: Array) -> void:
	push_error("Contrato interno chamado sem implementação: _resolver_vendaval_rede")
	pass

@warning_ignore("unused_parameter")
func _fluxo_estiagem_votacao() -> void:
	push_error("Contrato interno chamado sem implementação: _fluxo_estiagem_votacao")
	pass

@warning_ignore("unused_parameter")
func _resolver_estiagem_rede(aprovada: bool, votos_sim: int, total_votos: int) -> void:
	push_error("Contrato interno chamado sem implementação: _resolver_estiagem_rede")
	pass

@warning_ignore("unused_parameter")
func _preco_compra_crise_credito(casa_id: int) -> int:
	push_error("Contrato interno chamado sem implementação: _preco_compra_crise_credito")
	return 0

@warning_ignore("unused_parameter")
func _hipotecadas_disponiveis_para(comprador_id: String) -> Array:
	push_error("Contrato interno chamado sem implementação: _hipotecadas_disponiveis_para")
	return []

@warning_ignore("unused_parameter")
func _fluxo_crise_credito_compras() -> void:
	push_error("Contrato interno chamado sem implementação: _fluxo_crise_credito_compras")
	pass

@warning_ignore("unused_parameter")
func _comprar_hipotecada_crise_rede(comprador_id: String, casa_id: int) -> void:
	push_error("Contrato interno chamado sem implementação: _comprar_hipotecada_crise_rede")
	pass

@warning_ignore("unused_parameter")
func _preco_venda_gentrificacao(casa_id: int) -> int:
	push_error("Contrato interno chamado sem implementação: _preco_venda_gentrificacao")
	return 0

@warning_ignore("unused_parameter")
func _cinzas_vendaveis_do_jogador(jogador_id: String) -> Array:
	push_error("Contrato interno chamado sem implementação: _cinzas_vendaveis_do_jogador")
	return []

@warning_ignore("unused_parameter")
func _fluxo_gentrificacao_vendas() -> void:
	push_error("Contrato interno chamado sem implementação: _fluxo_gentrificacao_vendas")
	pass

@warning_ignore("unused_parameter")
func _aplicar_dano_gentrificacao_rede(casas_atingidas: Array) -> void:
	push_error("Contrato interno chamado sem implementação: _aplicar_dano_gentrificacao_rede")
	pass

@warning_ignore("unused_parameter")
func _vender_cinza_ao_banco_rede(jogador_id: String, casa_id: int) -> void:
	push_error("Contrato interno chamado sem implementação: _vender_cinza_ao_banco_rede")
	pass

@warning_ignore("unused_parameter")
func _grupos_residenciais_gdd() -> Array:
	push_error("Contrato interno chamado sem implementação: _grupos_residenciais_gdd")
	return []

@warning_ignore("unused_parameter")
func _fluxo_nova_lei_zoneamento() -> void:
	push_error("Contrato interno chamado sem implementação: _fluxo_nova_lei_zoneamento")
	pass

@warning_ignore("unused_parameter")
func _aplicar_nova_lei_zoneamento_rede(grupo: String, breno_pagou: bool) -> void:
	push_error("Contrato interno chamado sem implementação: _aplicar_nova_lei_zoneamento_rede")
	pass

@warning_ignore("unused_parameter")
func _grupos_vulneraveis_clima(tipo_evento: String) -> Array:
	push_error("Contrato interno chamado sem implementação: _grupos_vulneraveis_clima")
	return []

@warning_ignore("unused_parameter")
func _selecionar_terrenos_migracao() -> Array:
	push_error("Contrato interno chamado sem implementação: _selecionar_terrenos_migracao")
	return []

@warning_ignore("unused_parameter")
func _fluxo_migracao_leilao_especial() -> bool:
	push_error("Contrato interno chamado sem implementação: _fluxo_migracao_leilao_especial")
	return false

@warning_ignore("unused_parameter")
func _iniciar_fila_leilao_evento_rede(terrenos: Array) -> void:
	push_error("Contrato interno chamado sem implementação: _iniciar_fila_leilao_evento_rede")
	pass

@warning_ignore("unused_parameter")
func _iniciar_proximo_leilao_evento_agendado() -> void:
	push_error("Contrato interno chamado sem implementação: _iniciar_proximo_leilao_evento_agendado")
	pass

@warning_ignore("unused_parameter")
func _iniciar_proximo_leilao_evento_rede() -> void:
	push_error("Contrato interno chamado sem implementação: _iniciar_proximo_leilao_evento_rede")
	pass

@warning_ignore("unused_parameter")
func _processar_efeitos_imediatos_evento(nome_evento: String):
	push_error("Contrato interno chamado sem implementação: _processar_efeitos_imediatos_evento")
	pass

@warning_ignore("unused_parameter")
func _mostrar_alerta_meio_da_tela(texto: String):
	push_error("Contrato interno chamado sem implementação: _mostrar_alerta_meio_da_tela")
	pass

@warning_ignore("unused_parameter")
func _inicializar_meta_partida() -> void:
	push_error("Contrato interno chamado sem implementação: _inicializar_meta_partida")
	pass

@warning_ignore("unused_parameter")
func _garantir_meta_jogador(jogador_id: String) -> void:
	push_error("Contrato interno chamado sem implementação: _garantir_meta_jogador")
	pass

@warning_ignore("unused_parameter")
func _conceder_xp_partida(jogador_id: String, valor: int, chave: String, descricao: String) -> bool:
	push_error("Contrato interno chamado sem implementação: _conceder_xp_partida")
	return false

@warning_ignore("unused_parameter")
func _registrar_uso_habilidade_xp(jogador_id: String) -> void:
	push_error("Contrato interno chamado sem implementação: _registrar_uso_habilidade_xp")
	pass

@warning_ignore("unused_parameter")
func _grupos_monopolio_atuais(jogador_id: String) -> Array:
	push_error("Contrato interno chamado sem implementação: _grupos_monopolio_atuais")
	return []

@warning_ignore("unused_parameter")
func _verificar_novos_monopolios_xp(jogador_id: String) -> void:
	push_error("Contrato interno chamado sem implementação: _verificar_novos_monopolios_xp")
	pass

@warning_ignore("unused_parameter")
func _iniciar_rastreamento_evento_xp(nome_evento: String) -> void:
	push_error("Contrato interno chamado sem implementação: _iniciar_rastreamento_evento_xp")
	pass

@warning_ignore("unused_parameter")
func _marcar_perda_construcao_evento_xp(jogador_id: String) -> void:
	push_error("Contrato interno chamado sem implementação: _marcar_perda_construcao_evento_xp")
	pass

@warning_ignore("unused_parameter")
func _finalizar_rastreamento_evento_xp() -> void:
	push_error("Contrato interno chamado sem implementação: _finalizar_rastreamento_evento_xp")
	pass

@warning_ignore("unused_parameter")
func _creditar_eliminacao_xp(eliminador_id: String, falido_id: String) -> void:
	push_error("Contrato interno chamado sem implementação: _creditar_eliminacao_xp")
	pass

@warning_ignore("unused_parameter")
func _alterar_reputacao(jogador_id: String, delta: int, motivo: String) -> void:
	push_error("Contrato interno chamado sem implementação: _alterar_reputacao")
	pass

@warning_ignore("unused_parameter")
func _aplicar_impacto_reputacao_evento(nome_evento: String) -> void:
	push_error("Contrato interno chamado sem implementação: _aplicar_impacto_reputacao_evento")
	pass

@warning_ignore("unused_parameter")
func _registrar_acao(tipo: String, texto: String, jogador_id: String = "", dados_extras: Dictionary = {}) -> void:
	push_error("Contrato interno chamado sem implementação: _registrar_acao")
	pass

@warning_ignore("unused_parameter")
func _contar_monopolios_do_jogador(jogador_id: String) -> int:
	push_error("Contrato interno chamado sem implementação: _contar_monopolios_do_jogador")
	return 0

@warning_ignore("unused_parameter")
func _propriedades_para_estatistica(jogador_id: String) -> Array:
	push_error("Contrato interno chamado sem implementação: _propriedades_para_estatistica")
	return []

@warning_ignore("unused_parameter")
func _snapshot_atual_jogador(jogador_id: String) -> Dictionary:
	push_error("Contrato interno chamado sem implementação: _snapshot_atual_jogador")
	return {}

@warning_ignore("unused_parameter")
func _registrar_snapshot_final(jogador_id: String, colocacao: int) -> void:
	push_error("Contrato interno chamado sem implementação: _registrar_snapshot_final")
	pass

@warning_ignore("unused_parameter")
func _calcular_previsao_vitoria() -> Dictionary:
	push_error("Contrato interno chamado sem implementação: _calcular_previsao_vitoria")
	return {}

@warning_ignore("unused_parameter")
func _nome_efeito_espectador(efeito: Dictionary) -> String:
	push_error("Contrato interno chamado sem implementação: _nome_efeito_espectador")
	return ""

@warning_ignore("unused_parameter")
func _eventos_ativos_para_espectador() -> Array:
	push_error("Contrato interno chamado sem implementação: _eventos_ativos_para_espectador")
	return []

@warning_ignore("unused_parameter")
func obter_dados_espectador() -> Dictionary:
	push_error("Contrato interno chamado sem implementação: obter_dados_espectador")
	return {}

@warning_ignore("unused_parameter")
func ativar_modo_espectador_local() -> void:
	push_error("Contrato interno chamado sem implementação: ativar_modo_espectador_local")
	pass

@warning_ignore("unused_parameter")
func configurar_seguimento_espectador(jogador_id: String, automatico: bool) -> void:
	push_error("Contrato interno chamado sem implementação: configurar_seguimento_espectador")
	pass

@warning_ignore("unused_parameter")
func _atualizar_alvo_camera_espectador() -> void:
	push_error("Contrato interno chamado sem implementação: _atualizar_alvo_camera_espectador")
	pass

@warning_ignore("unused_parameter")
func _persistir_progressao_local(placar: Dictionary) -> Dictionary:
	push_error("Contrato interno chamado sem implementação: _persistir_progressao_local")
	return {}

@warning_ignore("unused_parameter")
func _montar_placar_final(vencedor_id: String) -> Dictionary:
	push_error("Contrato interno chamado sem implementação: _montar_placar_final")
	return {}

@warning_ignore("unused_parameter")
func _process(delta: float):
	push_error("Contrato interno chamado sem implementação: _process")
	pass

@warning_ignore("unused_parameter")
func _mouse_sobre_hud(pos_tela: Vector2) -> bool:
	push_error("Contrato interno chamado sem implementação: _mouse_sobre_hud")
	return false

@warning_ignore("unused_parameter")
func _coletar_controls_ativos(raiz: Control) -> Array:
	push_error("Contrato interno chamado sem implementação: _coletar_controls_ativos")
	return []

@warning_ignore("unused_parameter")
func _input(event):
	push_error("Contrato interno chamado sem implementação: _input")
	pass

@warning_ignore("unused_parameter")
func _aplicar_zoom(fator: float):
	push_error("Contrato interno chamado sem implementação: _aplicar_zoom")
	pass

@warning_ignore("unused_parameter")
func _limitar_posicao_camera():
	push_error("Contrato interno chamado sem implementação: _limitar_posicao_camera")
	pass

@warning_ignore("unused_parameter")
func _posicionar_camera_inicio_cinematica() -> void:
	push_error("Contrato interno chamado sem implementação: _posicionar_camera_inicio_cinematica")
	pass

@warning_ignore("unused_parameter")
func _iniciar_cinematica_abertura() -> void:
	push_error("Contrato interno chamado sem implementação: _iniciar_cinematica_abertura")
	pass

@warning_ignore("unused_parameter")
func _verificar_tween_cinematica() -> void:
	push_error("Contrato interno chamado sem implementação: _verificar_tween_cinematica")
	pass

@warning_ignore("unused_parameter")
func _concluir_cinematica_abertura(forcar: bool = false) -> void:
	push_error("Contrato interno chamado sem implementação: _concluir_cinematica_abertura")
	pass

@warning_ignore("unused_parameter")
func _notificar_tabuleiro_pronto_tutorial() -> void:
	push_error("Contrato interno chamado sem implementação: _notificar_tabuleiro_pronto_tutorial")
	pass

@warning_ignore("unused_parameter")
func focar_na_casa(id_casa: int):
	push_error("Contrato interno chamado sem implementação: focar_na_casa")
	pass

@warning_ignore("unused_parameter")
func _calcular_espiral():
	push_error("Contrato interno chamado sem implementação: _calcular_espiral")
	pass

@warning_ignore("unused_parameter")
func _get_camada(idx: int) -> int:
	push_error("Contrato interno chamado sem implementação: _get_camada")
	return 0

@warning_ignore("unused_parameter")
func _get_tamanho_casa(id: int) -> Vector2:
	push_error("Contrato interno chamado sem implementação: _get_tamanho_casa")
	return Vector2.ZERO

@warning_ignore("unused_parameter")
func _get_ponto_borda(pos: Vector2, dir: Vector2, tamanho: Vector2) -> Vector2:
	push_error("Contrato interno chamado sem implementação: _get_ponto_borda")
	return Vector2.ZERO

@warning_ignore("unused_parameter")
func _gerar_tabuleiro():
	push_error("Contrato interno chamado sem implementação: _gerar_tabuleiro")
	pass

@warning_ignore("unused_parameter")
func spawnar_pino(id_jogador: String, cor_do_grupo: Color):
	push_error("Contrato interno chamado sem implementação: spawnar_pino")
	pass

@warning_ignore("unused_parameter")
func _desenhar_ruas():
	push_error("Contrato interno chamado sem implementação: _desenhar_ruas")
	pass

@warning_ignore("unused_parameter")
func _desenhar_casa(id: int):
	push_error("Contrato interno chamado sem implementação: _desenhar_casa")
	pass

@warning_ignore("unused_parameter")
func _atualizar_visual_dono(casa_id: int):
	push_error("Contrato interno chamado sem implementação: _atualizar_visual_dono")
	pass

@warning_ignore("unused_parameter")
func _adicionar_pino_na_casa(pino: PinoPersonagem, casa_id: int) -> void:
	push_error("Contrato interno chamado sem implementação: _adicionar_pino_na_casa")
	pass

@warning_ignore("unused_parameter")
func _remover_pino_da_casa(pino: PinoPersonagem, casa_id: int) -> void:
	push_error("Contrato interno chamado sem implementação: _remover_pino_da_casa")
	pass

@warning_ignore("unused_parameter")
func _validar_layout_tabuleiro() -> bool:
	push_error("Contrato interno chamado sem implementação: _validar_layout_tabuleiro")
	return false

@warning_ignore("unused_parameter")
func _garantir_layout_tabuleiro() -> bool:
	push_error("Contrato interno chamado sem implementação: _garantir_layout_tabuleiro")
	return false

@warning_ignore("unused_parameter")
func _obter_posicao_casa_segura(casa_id: int) -> Vector2:
	push_error("Contrato interno chamado sem implementação: _obter_posicao_casa_segura")
	return Vector2.ZERO

@warning_ignore("unused_parameter")
func _reposicionar_pinos_na_casa(casa_id: int) -> void:
	push_error("Contrato interno chamado sem implementação: _reposicionar_pinos_na_casa")
	pass

@warning_ignore("unused_parameter")
func _verificar_permissao_de_clique() -> void:
	push_error("Contrato interno chamado sem implementação: _verificar_permissao_de_clique")
	pass

@warning_ignore("unused_parameter")
func _gerar_cidade_de_fundo():
	push_error("Contrato interno chamado sem implementação: _gerar_cidade_de_fundo")
	pass

@warning_ignore("unused_parameter")
func _hash_posicao_construcao_cidade(pos: Vector2i, sal: int) -> int:
	push_error("Contrato interno chamado sem implementação: _hash_posicao_construcao_cidade")
	return 0

@warning_ignore("unused_parameter")
func _modulo_positivo_cidade(valor: int, divisor: int) -> int:
	push_error("Contrato interno chamado sem implementação: _modulo_positivo_cidade")
	return 0

@warning_ignore("unused_parameter")
func _obter_indice_construcao_cidade(pos: Vector2i, quantidade: int) -> int:
	push_error("Contrato interno chamado sem implementação: _obter_indice_construcao_cidade")
	return 0

@warning_ignore("unused_parameter")
func _contar_conexoes_rua(pos: Vector2i, mapa: Dictionary) -> Dictionary:
	push_error("Contrato interno chamado sem implementação: _contar_conexoes_rua")
	return {}

@warning_ignore("unused_parameter")
func _calcular_rotacao_bifurcacao(conexoes: Dictionary) -> float:
	push_error("Contrato interno chamado sem implementação: _calcular_rotacao_bifurcacao")
	return 0.0

@warning_ignore("unused_parameter")
func _classificar_variante_base_cidade(pos: Vector2i, mapa: Dictionary) -> Dictionary:
	push_error("Contrato interno chamado sem implementação: _classificar_variante_base_cidade")
	return {}

@warning_ignore("unused_parameter")
func _eh_rua_ou_praca(tipo: Variant) -> bool:
	push_error("Contrato interno chamado sem implementação: _eh_rua_ou_praca")
	return false

@warning_ignore("unused_parameter")
func _criar_bloco(pai: Node2D, pos: Vector2, tamanho: float, cor: Color, altura_sombra: float = 0.0):
	push_error("Contrato interno chamado sem implementação: _criar_bloco")
	pass

@warning_ignore("unused_parameter")
func _criar_arvore(pai: Node2D, pos: Vector2):
	push_error("Contrato interno chamado sem implementação: _criar_arvore")
	pass

@warning_ignore("unused_parameter")
func _criar_poste(pai: Node2D, pos: Vector2):
	push_error("Contrato interno chamado sem implementação: _criar_poste")
	pass

@warning_ignore("unused_parameter")
func _criar_carro(pai: Node2D, pos: Vector2, direcao: Vector2, cor: Color, rng: RandomNumberGenerator):
	push_error("Contrato interno chamado sem implementação: _criar_carro")
	pass

@warning_ignore("unused_parameter")
func _grupo_zoneamento_permite_hotel_com_3_casas(grupo: String) -> bool:
	push_error("Contrato interno chamado sem implementação: _grupo_zoneamento_permite_hotel_com_3_casas")
	return false

@warning_ignore("unused_parameter")
func _nivel_destino_construcao(casa_id: int) -> int:
	push_error("Contrato interno chamado sem implementação: _nivel_destino_construcao")
	return 0

@warning_ignore("unused_parameter")
func _calcular_custo_construcao(id_jogador: String, casa_id: int) -> int:
	push_error("Contrato interno chamado sem implementação: _calcular_custo_construcao")
	return 0

@warning_ignore("unused_parameter")
func _motivo_construcao_invalida(id_jogador: String, casa_id: int, usar_carta_gratis: bool = false) -> String:
	push_error("Contrato interno chamado sem implementação: _motivo_construcao_invalida")
	return ""

@warning_ignore("unused_parameter")
func _on_hud_solicitar_construcao(casa_id: int):
	push_error("Contrato interno chamado sem implementação: _on_hud_solicitar_construcao")
	pass

@warning_ignore("unused_parameter")
func _efetuar_construcao_rede(id_jogador: String, casa_id: int):
	push_error("Contrato interno chamado sem implementação: _efetuar_construcao_rede")
	pass

@warning_ignore("unused_parameter")
func _atualizar_imagem_construcao(casa_id: int):
	push_error("Contrato interno chamado sem implementação: _atualizar_imagem_construcao")
	pass

@warning_ignore("unused_parameter")
func _destruir_casa_aleatoria(jogador_id: String):
	push_error("Contrato interno chamado sem implementação: _destruir_casa_aleatoria")
	pass

@warning_ignore("unused_parameter")
func _contar_hoteis_do_jogador(jogador_id: String) -> int:
	push_error("Contrato interno chamado sem implementação: _contar_hoteis_do_jogador")
	return 0

@warning_ignore("unused_parameter")
func _contar_hipotecas_do_jogador(jogador_id: String) -> int:
	push_error("Contrato interno chamado sem implementação: _contar_hipotecas_do_jogador")
	return 0

@warning_ignore("unused_parameter")
func _reduzir_nivel_em_grupo(jogador_id: String, grupo: String, qtd: int):
	push_error("Contrato interno chamado sem implementação: _reduzir_nivel_em_grupo")
	pass

@warning_ignore("unused_parameter")
func _on_hud_solicitar_opcoes_alvo(id_personagem: String):
	push_error("Contrato interno chamado sem implementação: _on_hud_solicitar_opcoes_alvo")
	pass

@warning_ignore("unused_parameter")
func _computar_opcoes_alvo_habilidade(id_personagem: String) -> Array:
	push_error("Contrato interno chamado sem implementação: _computar_opcoes_alvo_habilidade")
	return []

@warning_ignore("unused_parameter")
func _registrar_aquisicao_propriedade(casa_id: int, dono_id: String) -> void:
	push_error("Contrato interno chamado sem implementação: _registrar_aquisicao_propriedade")
	pass

@warning_ignore("unused_parameter")
func _rodadas_com_propriedade(casa_id: int, dono_id: String) -> int:
	push_error("Contrato interno chamado sem implementação: _rodadas_com_propriedade")
	return 0

@warning_ignore("unused_parameter")
func _yasmin_possui_terreno_no_grupo(yasmin_id: String, grupo: String) -> bool:
	push_error("Contrato interno chamado sem implementação: _yasmin_possui_terreno_no_grupo")
	return false

@warning_ignore("unused_parameter")
func _yasmin_ja_usou_contra(yasmin_id: String, alvo_id: String) -> bool:
	push_error("Contrato interno chamado sem implementação: _yasmin_ja_usou_contra")
	return false

@warning_ignore("unused_parameter")
func _preco_oferta_irrecusavel(casa_id: int) -> int:
	push_error("Contrato interno chamado sem implementação: _preco_oferta_irrecusavel")
	return 0

@warning_ignore("unused_parameter")
func _motivo_oferta_yasmin_invalida(yasmin_id: String, alvo_id: String, casa_id: int) -> String:
	push_error("Contrato interno chamado sem implementação: _motivo_oferta_yasmin_invalida")
	return ""

@warning_ignore("unused_parameter")
func _opcoes_yasmin(yasmin_id: String) -> Array:
	push_error("Contrato interno chamado sem implementação: _opcoes_yasmin")
	return []

@warning_ignore("unused_parameter")
func _opcoes_breno(breno_id: String) -> Array:
	push_error("Contrato interno chamado sem implementação: _opcoes_breno")
	return []

@warning_ignore("unused_parameter")
func _opcoes_mira(mira_id: String) -> Array:
	push_error("Contrato interno chamado sem implementação: _opcoes_mira")
	return []

@warning_ignore("unused_parameter")
func _opcoes_igor(igor_id: String) -> Array:
	push_error("Contrato interno chamado sem implementação: _opcoes_igor")
	return []

@warning_ignore("unused_parameter")
func _opcoes_diana(diana_id: String) -> Array:
	push_error("Contrato interno chamado sem implementação: _opcoes_diana")
	return []

@warning_ignore("unused_parameter")
func _opcoes_kofi(kofi_id: String) -> Array:
	push_error("Contrato interno chamado sem implementação: _opcoes_kofi")
	return []

@warning_ignore("unused_parameter")
func _on_hud_solicitar_habilidade(alvo_id: String, casa_id: int):
	push_error("Contrato interno chamado sem implementação: _on_hud_solicitar_habilidade")
	pass

@warning_ignore("unused_parameter")
func _ativar_habilidade_rede(id_personagem: String, alvo_id: String, casa_id: int):
	push_error("Contrato interno chamado sem implementação: _ativar_habilidade_rede")
	pass

@warning_ignore("unused_parameter")
func _habilidade_yasmin(yasmin_id: String, alvo_id: String, casa_id: int) -> bool:
	push_error("Contrato interno chamado sem implementação: _habilidade_yasmin")
	return false

@warning_ignore("unused_parameter")
func _habilidade_breno(breno_id: String, casa_id: int) -> bool:
	push_error("Contrato interno chamado sem implementação: _habilidade_breno")
	return false

@warning_ignore("unused_parameter")
func _habilidade_mira(mira_id: String, casa_id: int) -> bool:
	push_error("Contrato interno chamado sem implementação: _habilidade_mira")
	return false

@warning_ignore("unused_parameter")
func _habilidade_igor(igor_id: String, casa_id: int) -> bool:
	push_error("Contrato interno chamado sem implementação: _habilidade_igor")
	return false

@warning_ignore("unused_parameter")
func _habilidade_diana(diana_id: String, alvo_id: String) -> bool:
	push_error("Contrato interno chamado sem implementação: _habilidade_diana")
	return false

@warning_ignore("unused_parameter")
func _habilidade_kofi(kofi_id: String, casa_id: int) -> bool:
	push_error("Contrato interno chamado sem implementação: _habilidade_kofi")
	return false

@warning_ignore("unused_parameter")
func _on_hud_solicitar_hipoteca(casa_id: int):
	push_error("Contrato interno chamado sem implementação: _on_hud_solicitar_hipoteca")
	pass

@warning_ignore("unused_parameter")
func _hipotecar_rede(jogador_id: String, casa_id: int):
	push_error("Contrato interno chamado sem implementação: _hipotecar_rede")
	pass

@warning_ignore("unused_parameter")
func _resgatar_hipoteca_rede(jogador_id: String, casa_id: int):
	push_error("Contrato interno chamado sem implementação: _resgatar_hipoteca_rede")
	pass

@warning_ignore("unused_parameter")
func _on_hud_solicitar_fianca_prisao():
	push_error("Contrato interno chamado sem implementação: _on_hud_solicitar_fianca_prisao")
	pass

@warning_ignore("unused_parameter")
func _solicitar_fianca_prisao_servidor():
	push_error("Contrato interno chamado sem implementação: _solicitar_fianca_prisao_servidor")
	pass

@warning_ignore("unused_parameter")
func _notificar_falha_fianca_local(mensagem: String):
	push_error("Contrato interno chamado sem implementação: _notificar_falha_fianca_local")
	pass

@warning_ignore("unused_parameter")
func _servidor_processar_fianca(jogador_id: String) -> void:
	push_error("Contrato interno chamado sem implementação: _servidor_processar_fianca")
	pass

@warning_ignore("unused_parameter")
func _aplicar_resultado_fianca_rede(jogador_id: String, sucesso: bool, novo_saldo: int, novas_cartas: int, forma_saida: String, mensagem: String):
	push_error("Contrato interno chamado sem implementação: _aplicar_resultado_fianca_rede")
	pass

@warning_ignore("unused_parameter")
func _personagem_por_peer_pause(peer_id: int) -> String:
	push_error("Contrato interno chamado sem implementação: _personagem_por_peer_pause")
	return ""

@warning_ignore("unused_parameter")
func _personagem_local_pause() -> String:
	push_error("Contrato interno chamado sem implementação: _personagem_local_pause")
	return ""

@warning_ignore("unused_parameter")
func _peer_do_personagem_pause(personagem_id: String) -> int:
	push_error("Contrato interno chamado sem implementação: _peer_do_personagem_pause")
	return 0

@warning_ignore("unused_parameter")
func _on_menu_pause_visibilidade_alterada(aberto: bool) -> void:
	push_error("Contrato interno chamado sem implementação: _on_menu_pause_visibilidade_alterada")
	pass

@warning_ignore("unused_parameter")
func _nome_jogador_para_pausa(personagem_id: String) -> String:
	push_error("Contrato interno chamado sem implementação: _nome_jogador_para_pausa")
	return ""

@warning_ignore("unused_parameter")
func _on_menu_pause_solicitar_pausa() -> void:
	push_error("Contrato interno chamado sem implementação: _on_menu_pause_solicitar_pausa")
	pass

@warning_ignore("unused_parameter")
func _on_menu_pause_solicitar_retomada() -> void:
	push_error("Contrato interno chamado sem implementação: _on_menu_pause_solicitar_retomada")
	pass

@warning_ignore("unused_parameter")
func _on_solicitacao_estado_pausa_online(
	peer_solicitante: int,
	deseja_pausar: bool
) -> void:
	push_error("Contrato interno chamado sem implementação: _on_solicitacao_estado_pausa_online")
	pass

@warning_ignore("unused_parameter")
func _on_estado_pausa_partida_online(
	ativo: bool,
	peer_iniciador: int,
	personagem_iniciador: String,
	nome_iniciador: String
) -> void:
	push_error("Contrato interno chamado sem implementação: _on_estado_pausa_partida_online")
	pass

@warning_ignore("unused_parameter")
func _solicitar_estado_pausa_servidor(deseja_pausar: bool) -> void:
	push_error("Contrato interno chamado sem implementação: _solicitar_estado_pausa_servidor")
	pass

@warning_ignore("unused_parameter")
func _publicar_estado_pausa_host(
	ativo: bool,
	peer_iniciador: int,
	personagem_iniciador: String,
	nome_iniciador: String
) -> bool:
	push_error("Contrato interno chamado sem implementação: _publicar_estado_pausa_host")
	return false

@warning_ignore("unused_parameter")
func _processar_solicitacao_estado_pausa(
	peer_solicitante: int,
	deseja_pausar: bool,
	forcar: bool = false
) -> bool:
	push_error("Contrato interno chamado sem implementação: _processar_solicitacao_estado_pausa")
	return false

@warning_ignore("unused_parameter")
func _forcar_retomada_pausa_host() -> bool:
	push_error("Contrato interno chamado sem implementação: _forcar_retomada_pausa_host")
	return false

@warning_ignore("unused_parameter")
func _aplicar_estado_pausa_rede(
	ativo: bool,
	peer_iniciador: int,
	personagem_iniciador: String,
	nome_iniciador: String
) -> void:
	push_error("Contrato interno chamado sem implementação: _aplicar_estado_pausa_rede")
	pass

@warning_ignore("unused_parameter")
func _aplicar_interface_estado_pausa_atual() -> void:
	push_error("Contrato interno chamado sem implementação: _aplicar_interface_estado_pausa_atual")
	pass

@warning_ignore("unused_parameter")
func _on_menu_pause_solicitar_salvamento() -> void:
	push_error("Contrato interno chamado sem implementação: _on_menu_pause_solicitar_salvamento")
	pass

@warning_ignore("unused_parameter")
func _on_menu_pause_solicitar_salvar_e_sair() -> void:
	push_error("Contrato interno chamado sem implementação: _on_menu_pause_solicitar_salvar_e_sair")
	pass

@warning_ignore("unused_parameter")
func _solicitar_salvamento_ao_host(salvar_e_sair: bool) -> void:
	push_error("Contrato interno chamado sem implementação: _solicitar_salvamento_ao_host")
	pass

@warning_ignore("unused_parameter")
func _solicitar_salvamento_servidor(salvar_e_sair: bool) -> void:
	push_error("Contrato interno chamado sem implementação: _solicitar_salvamento_servidor")
	pass

@warning_ignore("unused_parameter")
func _processar_solicitacao_salvamento(
	peer_solicitante: int,
	salvar_e_sair: bool
) -> void:
	push_error("Contrato interno chamado sem implementação: _processar_solicitacao_salvamento")
	pass

@warning_ignore("unused_parameter")
func _enviar_resultado_salvamento(
	peer_destino: int,
	sucesso: bool,
	mensagem: String,
	encerrando: bool
) -> void:
	push_error("Contrato interno chamado sem implementação: _enviar_resultado_salvamento")
	pass

@warning_ignore("unused_parameter")
func _notificar_resultado_salvamento_rede(
	sucesso: bool,
	mensagem: String,
	encerrando: bool
) -> void:
	push_error("Contrato interno chamado sem implementação: _notificar_resultado_salvamento_rede")
	pass

@warning_ignore("unused_parameter")
func _notificar_resultado_salvamento_local(
	sucesso: bool,
	mensagem: String,
	encerrando: bool
) -> void:
	push_error("Contrato interno chamado sem implementação: _notificar_resultado_salvamento_local")
	pass

@warning_ignore("unused_parameter")
func _finalizar_salvar_e_sair_rede() -> void:
	push_error("Contrato interno chamado sem implementação: _finalizar_salvar_e_sair_rede")
	pass

@warning_ignore("unused_parameter")
func _on_menu_pause_solicitar_desistencia() -> void:
	push_error("Contrato interno chamado sem implementação: _on_menu_pause_solicitar_desistencia")
	pass

@warning_ignore("unused_parameter")
func _on_solicitacao_desistencia_partida_online(peer_solicitante: int) -> void:
	push_error("Contrato interno chamado sem implementação: _on_solicitacao_desistencia_partida_online")
	pass

@warning_ignore("unused_parameter")
func _solicitar_desistencia_servidor() -> void:
	push_error("Contrato interno chamado sem implementação: _solicitar_desistencia_servidor")
	pass

@warning_ignore("unused_parameter")
func _notificar_falha_desistencia_rede(mensagem: String) -> void:
	push_error("Contrato interno chamado sem implementação: _notificar_falha_desistencia_rede")
	pass

@warning_ignore("unused_parameter")
func _processar_solicitacao_desistencia(peer_id: int) -> bool:
	push_error("Contrato interno chamado sem implementação: _processar_solicitacao_desistencia")
	return false

@warning_ignore("unused_parameter")
func _on_resultado_desistencia_partida_online(
	token: String,
	jogador_desistente: String,
	vencedor: String
) -> void:
	push_error("Contrato interno chamado sem implementação: _on_resultado_desistencia_partida_online")
	pass

@warning_ignore("unused_parameter")
func _on_confirmacao_vitoria_desistencia_online(
	token: String,
	peer_confirmando: int,
	vencedor: String
) -> void:
	push_error("Contrato interno chamado sem implementação: _on_confirmacao_vitoria_desistencia_online")
	pass

@warning_ignore("unused_parameter")
func _confirmar_vitoria_por_desistencia_rede(
	vencedor_id: String,
	jogador_desistente_id: String
) -> void:
	push_error("Contrato interno chamado sem implementação: _confirmar_vitoria_por_desistencia_rede")
	pass

@warning_ignore("unused_parameter")
func _confirmar_apresentacao_vitoria_desistencia_apos_delay(vencedor_id: String) -> void:
	push_error("Contrato interno chamado sem implementação: _confirmar_apresentacao_vitoria_desistencia_apos_delay")
	pass

@warning_ignore("unused_parameter")
func _confirmar_apresentacao_vitoria_desistencia_servidor(vencedor_id: String) -> void:
	push_error("Contrato interno chamado sem implementação: _confirmar_apresentacao_vitoria_desistencia_servidor")
	pass

@warning_ignore("unused_parameter")
func _resolver_desistencia_rede(jogador_id: String, vencedor_id: String = "") -> void:
	push_error("Contrato interno chamado sem implementação: _resolver_desistencia_rede")
	pass

@warning_ignore("unused_parameter")
func _sair_para_menu_apos_desistencia() -> void:
	push_error("Contrato interno chamado sem implementação: _sair_para_menu_apos_desistencia")
	pass

@warning_ignore("unused_parameter")
func _verificar_falencia(jogador_id: String, eliminador_id: String = ""):
	push_error("Contrato interno chamado sem implementação: _verificar_falencia")
	pass

@warning_ignore("unused_parameter")
func _oferecer_abutre_igor(props_disponiveis: Array) -> Dictionary:
	push_error("Contrato interno chamado sem implementação: _oferecer_abutre_igor")
	return {}

@warning_ignore("unused_parameter")
func _enfileirar_resolucao_abutre(props_disponiveis: Array) -> void:
	push_error("Contrato interno chamado sem implementação: _enfileirar_resolucao_abutre")
	pass

@warning_ignore("unused_parameter")
func _processar_fila_resolucoes_abutre() -> void:
	push_error("Contrato interno chamado sem implementação: _processar_fila_resolucoes_abutre")
	pass

@warning_ignore("unused_parameter")
func _definir_bloqueio_abutre_rede(ativo: bool) -> void:
	push_error("Contrato interno chamado sem implementação: _definir_bloqueio_abutre_rede")
	pass

@warning_ignore("unused_parameter")
func _aplicar_resultado_abutre_rede(casa_comprada: int, props_restantes: Array) -> void:
	push_error("Contrato interno chamado sem implementação: _aplicar_resultado_abutre_rede")
	pass

@warning_ignore("unused_parameter")
func _finalizar_resolucoes_abutre_rede() -> void:
	push_error("Contrato interno chamado sem implementação: _finalizar_resolucoes_abutre_rede")
	pass

@warning_ignore("unused_parameter")
func _distribuir_caixa_remanescente_falencia(jogador_id: String) -> void:
	push_error("Contrato interno chamado sem implementação: _distribuir_caixa_remanescente_falencia")
	pass

@warning_ignore("unused_parameter")
func _declarar_falencia_rede(jogador_id: String, eliminador_id: String = ""):
	push_error("Contrato interno chamado sem implementação: _declarar_falencia_rede")
	pass

@warning_ignore("unused_parameter")
func _iniciar_leilao_falencia_agendado():
	push_error("Contrato interno chamado sem implementação: _iniciar_leilao_falencia_agendado")
	pass

@warning_ignore("unused_parameter")
func _iniciar_proximo_leilao_falencia():
	push_error("Contrato interno chamado sem implementação: _iniciar_proximo_leilao_falencia")
	pass

@warning_ignore("unused_parameter")
func _verificar_vitoria():
	push_error("Contrato interno chamado sem implementação: _verificar_vitoria")
	pass

@warning_ignore("unused_parameter")
func _tem_monopolio_total(jogador_id: String) -> bool:
	push_error("Contrato interno chamado sem implementação: _tem_monopolio_total")
	return false

@warning_ignore("unused_parameter")
func _aplicar_criterios_desempate(candidatos: Array) -> String:
	push_error("Contrato interno chamado sem implementação: _aplicar_criterios_desempate")
	return ""

@warning_ignore("unused_parameter")
func _calcular_patrimonio(jogador_id: String) -> int:
	push_error("Contrato interno chamado sem implementação: _calcular_patrimonio")
	return 0

@warning_ignore("unused_parameter")
func _declarar_vencedor_rede(
	vencedor_id: String,
	jogador_desistente_id: String = ""
) -> void:
	push_error("Contrato interno chamado sem implementação: _declarar_vencedor_rede")
	pass

@warning_ignore("unused_parameter")
func _init_jogadores_ativos():
	push_error("Contrato interno chamado sem implementação: _init_jogadores_ativos")
	pass

@warning_ignore("unused_parameter")
func _conectar_sinais_hud_novos():
	push_error("Contrato interno chamado sem implementação: _conectar_sinais_hud_novos")
	pass

@warning_ignore("unused_parameter")
func fornecer_dados_para_negociacao() -> Dictionary:
	push_error("Contrato interno chamado sem implementação: fornecer_dados_para_negociacao")
	return {}

@warning_ignore("unused_parameter")
func _peer_id_do(personagem_id: String) -> int:
	push_error("Contrato interno chamado sem implementação: _peer_id_do")
	return 0

@warning_ignore("unused_parameter")
func _on_hud_solicitar_negociacao(proposta: Dictionary):
	push_error("Contrato interno chamado sem implementação: _on_hud_solicitar_negociacao")
	pass

@warning_ignore("unused_parameter")
func _on_hud_solicitar_alianca(proposta: Dictionary):
	push_error("Contrato interno chamado sem implementação: _on_hud_solicitar_alianca")
	pass

@warning_ignore("unused_parameter")
func _enviar_proposta_negociacao_rede(proposta: Dictionary):
	push_error("Contrato interno chamado sem implementação: _enviar_proposta_negociacao_rede")
	pass

@warning_ignore("unused_parameter")
func _responder_negociacao_bot(id_proposta: String) -> void:
	push_error("Contrato interno chamado sem implementação: _responder_negociacao_bot")
	pass

@warning_ignore("unused_parameter")
func _valor_pacote_negociacao_bot(pacote: Dictionary) -> int:
	push_error("Contrato interno chamado sem implementação: _valor_pacote_negociacao_bot")
	return 0

@warning_ignore("unused_parameter")
func _agendar_timeout_proposta(id_proposta: String):
	push_error("Contrato interno chamado sem implementação: _agendar_timeout_proposta")
	pass

@warning_ignore("unused_parameter")
func _on_hud_responder_negociacao(id_proposta: String, aceita: bool, aceitador: String):
	push_error("Contrato interno chamado sem implementação: _on_hud_responder_negociacao")
	pass

@warning_ignore("unused_parameter")
func _responder_proposta_negociacao_rede(id_proposta: String, aceita: bool, aceitador: String):
	push_error("Contrato interno chamado sem implementação: _responder_proposta_negociacao_rede")
	pass

@warning_ignore("unused_parameter")
func _validar_proposta_para_execucao(proposta: Dictionary) -> Array:
	push_error("Contrato interno chamado sem implementação: _validar_proposta_para_execucao")
	return []

@warning_ignore("unused_parameter")
func _executar_negociacao_rede(proposta: Dictionary):
	push_error("Contrato interno chamado sem implementação: _executar_negociacao_rede")
	pass

@warning_ignore("unused_parameter")
func _verificar_monopolio_apos_negociacao(jogador_id: String, props_recebidas: Array):
	push_error("Contrato interno chamado sem implementação: _verificar_monopolio_apos_negociacao")
	pass

@warning_ignore("unused_parameter")
func _validar_alianca_para_execucao(proposta: Dictionary) -> Array:
	push_error("Contrato interno chamado sem implementação: _validar_alianca_para_execucao")
	return []

@warning_ignore("unused_parameter")
func _executar_alianca_rede(proposta: Dictionary):
	push_error("Contrato interno chamado sem implementação: _executar_alianca_rede")
	pass

@warning_ignore("unused_parameter")
func _calcular_taxa_alianca(recebedor_id: String, pagador_id: String) -> float:
	push_error("Contrato interno chamado sem implementação: _calcular_taxa_alianca")
	return 0.0

@warning_ignore("unused_parameter")
func _on_hud_solicitar_criar_promessa(texto: String, autor_id: String):
	push_error("Contrato interno chamado sem implementação: _on_hud_solicitar_criar_promessa")
	pass

@warning_ignore("unused_parameter")
func _solicitar_criar_promessa_servidor(texto: String):
	push_error("Contrato interno chamado sem implementação: _solicitar_criar_promessa_servidor")
	pass

@warning_ignore("unused_parameter")
func _servidor_criar_promessa(autor_id: String, texto: String) -> void:
	push_error("Contrato interno chamado sem implementação: _servidor_criar_promessa")
	pass

@warning_ignore("unused_parameter")
func _on_hud_solicitar_quebrar_promessa(id_promessa: String):
	push_error("Contrato interno chamado sem implementação: _on_hud_solicitar_quebrar_promessa")
	pass

@warning_ignore("unused_parameter")
func _solicitar_quebrar_promessa_servidor(id_promessa: String):
	push_error("Contrato interno chamado sem implementação: _solicitar_quebrar_promessa_servidor")
	pass

@warning_ignore("unused_parameter")
func _servidor_reportar_quebra(id_promessa: String, reporter_id: String) -> void:
	push_error("Contrato interno chamado sem implementação: _servidor_reportar_quebra")
	pass

@warning_ignore("unused_parameter")
func _criar_promessa_rede(id_promessa: String, autor_id: String, texto: String, duracao_turnos: int = PROMESSA_DURACAO_PADRAO):
	push_error("Contrato interno chamado sem implementação: _criar_promessa_rede")
	pass

@warning_ignore("unused_parameter")
func _quebrar_promessa_rede(id_promessa: String, reportada_por: String):
	push_error("Contrato interno chamado sem implementação: _quebrar_promessa_rede")
	pass

@warning_ignore("unused_parameter")
func _processar_promessas_ao_avancar_turno() -> void:
	push_error("Contrato interno chamado sem implementação: _processar_promessas_ao_avancar_turno")
	pass

@warning_ignore("unused_parameter")
func _cancelar_promessas_do_jogador(jogador_id: String) -> void:
	push_error("Contrato interno chamado sem implementação: _cancelar_promessas_do_jogador")
	pass

@warning_ignore("unused_parameter")
func _atualizar_hud_promessas():
	push_error("Contrato interno chamado sem implementação: _atualizar_hud_promessas")
	pass

@warning_ignore("unused_parameter")
func _jogadores_elegiveis_para_eleicao() -> Array:
	push_error("Contrato interno chamado sem implementação: _jogadores_elegiveis_para_eleicao")
	return []

@warning_ignore("unused_parameter")
func _personagem_do_peer(peer_id: int) -> String:
	push_error("Contrato interno chamado sem implementação: _personagem_do_peer")
	return ""

@warning_ignore("unused_parameter")
func _on_hud_voto_eleicao(pacote: String):
	push_error("Contrato interno chamado sem implementação: _on_hud_voto_eleicao")
	pass

@warning_ignore("unused_parameter")
func _receber_voto_eleicao(votacao_id: int, pacote: String):
	push_error("Contrato interno chamado sem implementação: _receber_voto_eleicao")
	pass

@warning_ignore("unused_parameter")
func _mostrar_voto_recebido_rede(votacao_id: int, cor_jogador: Color):
	push_error("Contrato interno chamado sem implementação: _mostrar_voto_recebido_rede")
	pass

@warning_ignore("unused_parameter")
func _iniciar_votacao_eleicao():
	push_error("Contrato interno chamado sem implementação: _iniciar_votacao_eleicao")
	pass

@warning_ignore("unused_parameter")
func _mostrar_painel_votacao_rede(votacao_id: int, duracao: int, total_eleitores: int):
	push_error("Contrato interno chamado sem implementação: _mostrar_painel_votacao_rede")
	pass

@warning_ignore("unused_parameter")
func _iniciar_countdown_votacao(votacao_id: int, duracao: int):
	push_error("Contrato interno chamado sem implementação: _iniciar_countdown_votacao")
	pass

@warning_ignore("unused_parameter")
func _finalizar_votacao_eleicao(votacao_id: int):
	push_error("Contrato interno chamado sem implementação: _finalizar_votacao_eleicao")
	pass

@warning_ignore("unused_parameter")
func _encerrar_eleicao_apos_resultado(votacao_id: int):
	push_error("Contrato interno chamado sem implementação: _encerrar_eleicao_apos_resultado")
	pass

@warning_ignore("unused_parameter")
func _anunciar_resultado_eleicao(votacao_id: int, vencedor: String, foi_empate: bool, contagem: Dictionary):
	push_error("Contrato interno chamado sem implementação: _anunciar_resultado_eleicao")
	pass

@warning_ignore("unused_parameter")
func _encerrar_eleicao_rede(votacao_id: int):
	push_error("Contrato interno chamado sem implementação: _encerrar_eleicao_rede")
	pass

@warning_ignore("unused_parameter")
func _media_preco_grupo(grupo: String) -> float:
	push_error("Contrato interno chamado sem implementação: _media_preco_grupo")
	return 0.0

@warning_ignore("unused_parameter")
func _grupos_residenciais_ordenados_por_preco() -> Array:
	push_error("Contrato interno chamado sem implementação: _grupos_residenciais_ordenados_por_preco")
	return []

@warning_ignore("unused_parameter")
func _aplicar_pacote_eleicao(pacote: String):
	push_error("Contrato interno chamado sem implementação: _aplicar_pacote_eleicao")
	pass
