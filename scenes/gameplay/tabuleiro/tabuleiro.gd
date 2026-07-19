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
func _obter_aluguel_tabela(casa_id: int, nivel: int = -1) -> int:
	if not tabuleiro.has(casa_id):
		return 0
	var dados_casa: Dictionary = tabuleiro[casa_id]
	if dados_casa.get("tipo", "") != "propriedade":
		return 0
	var nivel_consultado = int(dados_casa.get("nivel", 0)) if nivel < 0 else nivel
	nivel_consultado = clampi(nivel_consultado, 0, 5)
	var chave = str(CHAVE_ALUGUEL_POR_NIVEL.get(nivel_consultado, "aluguel_base"))
	return max(0, int(dados_casa.get(chave, 0)))

func _validar_tabelas_aluguel() -> void:
	for casa_id in tabuleiro.keys():
		var dados_casa: Dictionary = tabuleiro[casa_id]
		if dados_casa.get("tipo", "") != "propriedade":
			continue
		var valor_anterior = -1
		for nivel in range(6):
			var chave = str(CHAVE_ALUGUEL_POR_NIVEL[nivel])
			if not dados_casa.has(chave):
				push_error("Tabela de aluguel incompleta na casa %d (%s): falta %s." % [casa_id, dados_casa.get("nome", ""), chave])
				continue
			var valor = int(dados_casa[chave])
			if valor < 0:
				push_error("Aluguel negativo na casa %d (%s), nível %d." % [casa_id, dados_casa.get("nome", ""), nivel])
			if valor_anterior > valor:
				push_warning("Tabela de aluguel não crescente na casa %d (%s), nível %d." % [casa_id, dados_casa.get("nome", ""), nivel])
			valor_anterior = valor

# ============================================================================
# SINCRONIZAÇÃO ONLINE — PHOTON FUSION
# ============================================================================
# RPCs representam ações pontuais. Este snapshot concentra o estado durável da
# partida para reconexão e recuperação após troca do Master Client.
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
func _ready() -> void:
	# Garante que a introdução local continue processando mesmo se algum fluxo
	# online alterar temporariamente o modo de processamento da cena.
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	_validar_tabelas_aluguel()
	_calcular_espiral()
	_layout_tabuleiro_pronto = _validar_layout_tabuleiro()

	var vp: Vector2 = get_viewport_rect().size
	if vp.x > 0.0 and vp.y > 0.0:
		VIEWPORT_LARGURA = vp.x
		VIEWPORT_ALTURA = vp.y

	add_to_group("tabuleiro_principal")
	if OnlineTransport.usando_photon():
		call_deferred("_iniciar_sincronizacao_online")

	deck_destino_atual = deck_destino_base.duplicate()
	deck_destino_atual.shuffle()
	deck_ordem_atual = deck_ordem_base.duplicate()
	deck_ordem_atual.shuffle()

	hud = hud_cena.instantiate()
	add_child(hud)
	hud.solicitar_construcao.connect(_on_hud_solicitar_construcao)
	if menu_pause != null:
		menu_pause.solicitar_pausa.connect(_on_menu_pause_solicitar_pausa)
		menu_pause.solicitar_retomada.connect(_on_menu_pause_solicitar_retomada)
		menu_pause.solicitar_desistencia.connect(_on_menu_pause_solicitar_desistencia)
		menu_pause.solicitar_salvamento.connect(_on_menu_pause_solicitar_salvamento)
		menu_pause.solicitar_salvar_e_sair.connect(_on_menu_pause_solicitar_salvar_e_sair)
		menu_pause.visibilidade_alterada.connect(_on_menu_pause_visibilidade_alterada)
	var hud_control: Control = hud.get_node("Control") as Control
	if hud_control != null:
		hud_control.modulate.a = 0.0
	hud.dados_rolados.connect(_on_dados_rolados_recebidos)
	_conectar_sinais_hud_novos()
	_init_jogadores_ativos()

	lista_turnos.clear()
	cor_por_jogador.clear()
	var personagens_escolhidos: Array = []
	if not Global.ordem_partida_local.is_empty():
		personagens_escolhidos = Global.ordem_partida_local.duplicate()
		for escolha_variant: Variant in Global.escolhas_da_mesa.values():
			var escolha_id: String = str(escolha_variant)
			if not escolha_id.is_empty() and not personagens_escolhidos.has(escolha_id):
				personagens_escolhidos.append(escolha_id)
	else:
		personagens_escolhidos = Global.escolhas_da_mesa.values()
		personagens_escolhidos.sort()
	for personagem_variant in personagens_escolhidos:
		var personagem_id: String = str(personagem_variant)
		if personagem_id.is_empty() or lista_turnos.has(personagem_id):
			continue
		lista_turnos.append(personagem_id)
		var cor_personagem: Color = _cor_visual_personagem(personagem_id)
		cor_por_jogador[personagem_id] = cor_personagem
		spawnar_pino(personagem_id, cor_personagem)

	# Fallback exclusivo para a partida local sem escolhas. Em Photon, o
	# snapshot do host substituirá esta composição assim que chegar.
	if lista_turnos.is_empty():
		lista_turnos = ["yasmin", "igor"]
		for fallback_variant in lista_turnos:
			var fallback_id: String = str(fallback_variant)
			var fallback_cor: Color = _cor_visual_personagem(fallback_id)
			cor_por_jogador[fallback_id] = fallback_cor
			spawnar_pino(fallback_id, fallback_cor)

	_configurar_bots_locais()

	ordem_original_partida = lista_turnos.duplicate()
	jogadores_ativos = lista_turnos.duplicate()
	_inicializar_meta_partida()
	_registrar_acao("sistema", "Partida iniciada com %d jogadores." % ordem_original_partida.size())

	_gerar_cidade_de_fundo()
	_gerar_tabuleiro()
	_layout_tabuleiro_pronto = _validar_layout_tabuleiro()

	indice_turno_atual = 0
	jogador_atual_id = str(lista_turnos[indice_turno_atual])

	if not Global.modo_tutorial:
		GerenciadorSalvamento.registrar_tabuleiro(self)
	var retomada_aplicada: bool = false
	if OnlineTransport.usando_photon() and OnlineTransport.is_host():
		var snapshot_retomada: Dictionary = (
			GerenciadorSalvamento.consumir_snapshot_retomada()
		)
		if not snapshot_retomada.is_empty():
			aplicar_snapshot_online(snapshot_retomada)
			retomada_aplicada = _sincronizacao_online_concluida
			if retomada_aplicada:
				GerenciadorSalvamento.confirmar_retomada_carregada()
				_registrar_acao(
					"sistema",
					"Partida salva retomada com todos os participantes."
				)

	# O convidado Photon só monta a HUD depois do snapshot autoritativo. Antes,
	# a atualização usava dados incompletos e podia interromper o _ready(),
	# deixando a câmera afastada e a interface com alpha zero.
	if retomada_aplicada:
		_sincronizacao_online_concluida = true
		_atualizar_hud_ciclo_turno()
		_atualizar_hud_minha_casa()
		if not _cinematica_abertura_iniciada:
			_iniciar_cinematica_abertura()
	elif OnlineTransport.usando_photon() and not OnlineTransport.is_host():
		# A apresentação visual não depende mais da chegada do snapshot. O estado
		# inicial já existe localmente após a seleção sincronizada; o snapshot do
		# host corrige qualquer diferença em paralelo. Assim, atraso ou perda de
		# pacote nunca deixa o convidado preso na visão distante.
		_preparar_espera_snapshot_online()
		_atualizar_hud_ciclo_turno()
		_atualizar_hud_minha_casa()
		_iniciar_cinematica_abertura()
	else:
		_sincronizacao_online_concluida = true
		_atualizar_hud_ciclo_turno()
		_iniciar_cinematica_abertura()


func _cor_visual_personagem(personagem_id: String) -> Color:
	match personagem_id:
		"breno":
			return cores_grupos["Verde"]
		"mira":
			return cores_grupos["Azul-Escuro"]
		"igor":
			return cores_grupos["Laranja"]
		"diana":
			return cores_grupos["Vermelho"]
		"kofi":
			return cores_grupos["Amarelo"]
		_:
			return cores_grupos["Rosa"]


func _configurar_bots_locais() -> void:
	for jogador_variant: Variant in Global.jogadores_controlados_por_bot:
		var id_jogador: String = str(jogador_variant)
		if id_jogador.is_empty() or not lista_turnos.has(id_jogador):
			continue
		if _bots_jogadores.has(id_jogador):
			continue

		var bot: Node = BOT_JOGADOR_SCRIPT.new()
		bot.name = "Bot_%s" % id_jogador.capitalize()
		add_child(bot)
		bot.call("configurar", self, id_jogador, id_jogador.hash())

		var resultados: Array[Vector2i] = []
		var resultados_variant: Variant = Global.dados_tutorial_bots.get(
			id_jogador,
			[]
		)
		if resultados_variant is Array:
			for resultado_variant: Variant in resultados_variant:
				if resultado_variant is Vector2i:
					resultados.append(resultado_variant)
		if not resultados.is_empty():
			bot.call("definir_resultados_forcados", resultados)
		bot.call("definir_pausado", _bots_pausados)
		_bots_jogadores[id_jogador] = bot


func _eh_jogador_bot(id_jogador: String) -> bool:
	return _bots_jogadores.has(id_jogador)


func definir_bots_pausados(pausados: bool) -> void:
	_bots_pausados = pausados
	for bot_variant: Variant in _bots_jogadores.values():
		var bot: Node = bot_variant as Node
		if bot != null and is_instance_valid(bot):
			bot.call("definir_pausado", pausados)


func executar_rolagem_bot(
	id_jogador: String,
	dado1: int,
	dado2: int
) -> void:
	if not _eh_jogador_bot(id_jogador) or id_jogador != jogador_atual_id:
		return
	if _acoes_bloqueadas_por_evento() or _menu_pause_bloqueando_acoes:
		call_deferred("_solicitar_turno_bot", id_jogador)
		return
	var d1: int = clampi(dado1, 1, 6)
	var d2: int = clampi(dado2, 1, 6)
	_on_dados_rolados_recebidos(d1, d2)


func obter_resultado_dados_tutorial() -> Vector2i:
	if not Global.modo_tutorial:
		return Vector2i.ZERO
	return Global.consumir_dados_tutorial_jogador()


func _solicitar_turno_bot(id_jogador: String) -> void:
	if id_jogador != jogador_atual_id or not _bots_jogadores.has(id_jogador):
		return
	var bot: Node = _bots_jogadores.get(id_jogador) as Node
	if bot == null or not is_instance_valid(bot):
		return
	bot.call_deferred("executar_turno")


func _emitir_evento_tutorial(tipo: String, dados: Dictionary = {}) -> void:
	if Global.modo_tutorial:
		evento_tutorial.emit(tipo, dados)


# Prepara a única propriedade inicial de Igor usada pela aula de negociação.
# Yasmin compra a outra propriedade Cinza durante o fluxo; ao receber esta em
# troca, forma um monopólio real e o botão de construção é liberado normalmente.
func preparar_cenario_tutorial_expandido() -> void:
	if not Global.modo_tutorial or _cenario_tutorial_expandido_preparado:
		return
	if not tabuleiro.has(1) or not dados_economia_jogadores.has("igor"):
		return
	_cenario_tutorial_expandido_preparado = true

	var dados_igor: Dictionary = dados_economia_jogadores["igor"]
	var propriedades_variant: Variant = dados_igor.get("propriedades_lista", [])
	var propriedades_igor: Array = []
	if propriedades_variant is Array:
		propriedades_igor = propriedades_variant
	if not propriedades_igor.has(1):
		propriedades_igor.append(1)
	var preco_inicial: int = int(tabuleiro[1].get("preco", 0))
	dados_igor["propriedades_lista"] = propriedades_igor
	dados_igor["propriedades_compradas"] = propriedades_igor.size()
	dados_igor["dinheiro"] = maxi(
		0,
		int(dados_igor.get("dinheiro", 0)) - preco_inicial
	)
	registro_propriedades[1] = "igor"
	_registrar_aquisicao_propriedade(1, "igor")
	_atualizar_visual_dono(1)
	_atualizar_hud_minha_casa()
	_atualizar_hud_ciclo_turno()
	_atualizar_menu_construcao()
	_emitir_evento_tutorial(
		"cenario_tutorial_preparado",
		{"dono_id": "igor", "casa_id": 1, "preco": preco_inicial}
	)


# Converte o retângulo do tile no mundo para coordenadas da tela. O controlador
# usa este recorte para escurecer o restante da cidade durante as explicações.
func obter_retangulo_tile_tutorial(casa_id: int) -> Rect2:
	if not Global.modo_tutorial or not tabuleiro.has(casa_id):
		return Rect2()
	var centro_local: Vector2 = tabuleiro[casa_id].get("pos", Vector2.ZERO)
	var metade: Vector2 = _get_tamanho_casa(casa_id) * 0.5
	var transformacao_tela: Transform2D = get_viewport().get_canvas_transform()
	var cantos_locais: Array[Vector2] = [
		centro_local - metade,
		centro_local + Vector2(metade.x, -metade.y),
		centro_local + metade,
		centro_local + Vector2(-metade.x, metade.y),
	]
	var minimo: Vector2 = Vector2(INF, INF)
	var maximo: Vector2 = Vector2(-INF, -INF)
	for canto_local: Vector2 in cantos_locais:
		var canto_tela: Vector2 = transformacao_tela * to_global(canto_local)
		minimo = minimo.min(canto_tela)
		maximo = maximo.max(canto_tela)
	return Rect2(minimo, maximo - minimo)


# Os níveis 2 a 5 são uma demonstração visual acelerada. A primeira obra é
# paga e validada pelo fluxo normal; os níveis seguintes apenas ilustram como
# o prédio evolui, sem registrar compras fictícias no histórico da partida.
func definir_nivel_construcao_tutorial(casa_id: int, nivel: int) -> bool:
	if not Global.modo_tutorial or not tabuleiro.has(casa_id):
		return false
	if str(registro_propriedades.get(casa_id, "")) != "yasmin":
		return false
	if str(tabuleiro[casa_id].get("tipo", "")) != "propriedade":
		return false
	tabuleiro[casa_id]["nivel"] = clampi(nivel, 0, 5)
	_atualizar_imagem_construcao(casa_id)
	var camada_predios: Node = get_node_or_null("Camada_02_Predios")
	if camada_predios != null:
		var container: Node2D = camada_predios.get_node_or_null(
			"Casa_%d/ContainerConstrucao" % casa_id
		) as Node2D
		if container != null:
			container.scale = Vector2(0.78, 0.78)
			container.modulate.a = 0.35
			var tween_visual: Tween = create_tween()
			tween_visual.set_parallel(true)
			(
				tween_visual
				. tween_property(container, "scale", Vector2.ONE, 0.34)
				. set_trans(Tween.TRANS_BACK)
				. set_ease(Tween.EASE_OUT)
			)
			tween_visual.tween_property(container, "modulate:a", 1.0, 0.22)
	_atualizar_hud_minha_casa()
	_atualizar_hud_ciclo_turno()
	_atualizar_menu_construcao()
	return true


func obter_resultado_tutorial_rapido() -> Dictionary:
	if not Global.modo_tutorial:
		return {}
	var candidatos: Array = []
	for jogador_id: String in ["yasmin", "igor"]:
		if (
			dados_economia_jogadores.has(jogador_id)
			and not bool(dados_economia_jogadores[jogador_id].get("falido", false))
		):
			candidatos.append(jogador_id)
	if candidatos.is_empty():
		return {}
	var vencedor_id: String = str(candidatos[0])
	if candidatos.size() > 1:
		vencedor_id = _aplicar_criterios_desempate(candidatos)
	return {
		"vencedor_id": vencedor_id,
		"patrimonio_yasmin": _calcular_patrimonio("yasmin"),
		"patrimonio_igor": _calcular_patrimonio("igor"),
	}


func _preparar_espera_snapshot_online() -> void:
	cinematica_rodando = true
	_posicionar_camera_inicio_cinematica()
	call_deferred("_vigiar_entrada_visual_online")


func _iniciar_sincronizacao_online() -> void:
	Global.modo_online = true
	Global.meu_peer_id = OnlineTransport.local_player_id()
	OnlineTransport.definir_fase_online("tabuleiro", OnlineTransport.CENA_TABULEIRO)
	if not OnlineTransport.jogador_desconectado.is_connected(_on_jogador_desconectado_online):
		OnlineTransport.jogador_desconectado.connect(_on_jogador_desconectado_online)
	if not OnlineTransport.jogador_reconectado.is_connected(_on_jogador_reconectado_online):
		OnlineTransport.jogador_reconectado.connect(_on_jogador_reconectado_online)
	if not OnlineTransport.host_alterado.is_connected(_on_host_alterado_online):
		OnlineTransport.host_alterado.connect(_on_host_alterado_online)
	if not OnlineTransport.solicitacao_pausa_partida_recebida.is_connected(
		_on_solicitacao_estado_pausa_online
	):
		OnlineTransport.solicitacao_pausa_partida_recebida.connect(
			_on_solicitacao_estado_pausa_online
		)
	if not OnlineTransport.estado_pausa_partida_recebido.is_connected(
		_on_estado_pausa_partida_online
	):
		OnlineTransport.estado_pausa_partida_recebido.connect(
			_on_estado_pausa_partida_online
		)
	if not OnlineTransport.solicitacao_desistencia_partida_recebida.is_connected(
		_on_solicitacao_desistencia_partida_online
	):
		OnlineTransport.solicitacao_desistencia_partida_recebida.connect(
			_on_solicitacao_desistencia_partida_online
		)
	if not OnlineTransport.resultado_desistencia_partida_recebido.is_connected(
		_on_resultado_desistencia_partida_online
	):
		OnlineTransport.resultado_desistencia_partida_recebido.connect(
			_on_resultado_desistencia_partida_online
		)
	if not OnlineTransport.confirmacao_vitoria_desistencia_recebida.is_connected(
		_on_confirmacao_vitoria_desistencia_online
	):
		OnlineTransport.confirmacao_vitoria_desistencia_recebida.connect(
			_on_confirmacao_vitoria_desistencia_online
		)

	var resultado_pendente: Dictionary = OnlineTransport.obter_resultado_desistencia_pendente()
	if not resultado_pendente.is_empty():
		call_deferred(
			"_on_resultado_desistencia_partida_online",
			str(resultado_pendente.get("token", "")),
			str(resultado_pendente.get("jogador_desistente", "")),
			str(resultado_pendente.get("vencedor", ""))
		)

	var estado_pausa_transporte: Dictionary = OnlineTransport.obter_estado_pausa_partida()
	if bool(estado_pausa_transporte.get("ativo", false)):
		call_deferred(
			"_on_estado_pausa_partida_online",
			true,
			int(estado_pausa_transporte.get("peer_iniciador", 0)),
			str(estado_pausa_transporte.get("personagem_iniciador", "")),
			str(estado_pausa_transporte.get("nome_iniciador", ""))
		)
	if OnlineTransport.is_host():
		_sincronizacao_online_concluida = true
		call_deferred("_publicar_snapshot_inicial_online")
		return

	# Reenvia o pedido algumas vezes. O primeiro pacote pode chegar enquanto o
	# nó remoto ainda está mudando de cena e acabar aguardando/expirando na fila.
	for tentativa in range(6):
		if _sincronizacao_online_concluida or not is_inside_tree():
			return
		_tentativas_snapshot_inicial = tentativa + 1
		await get_tree().create_timer(0.65 if tentativa == 0 else 1.25).timeout
		if _sincronizacao_online_concluida or not is_inside_tree():
			return
		OnlineTransport.solicitar_snapshot_tabuleiro()

	if not _sincronizacao_online_concluida:
		push_warning("[PHOTON] Snapshot inicial ainda não chegou após 6 tentativas.")


func _publicar_snapshot_inicial_online() -> void:
	# O host publica o estado em mais de um momento porque os clientes podem
	# terminar a troca de cena em frames diferentes. A transferência é dividida
	# em partes pelo OnlineTransport para não enviar um RPC gigante.
	for atraso_variant in [0.45, 1.25, 2.50]:
		var atraso: float = float(atraso_variant)
		await get_tree().create_timer(atraso).timeout
		if not is_inside_tree() or not OnlineTransport.usando_photon():
			return
		if not OnlineTransport.is_host():
			return
		if not OnlineTransport.has_method(&"publicar_snapshot_tabuleiro"):
			push_error(
				"[PHOTON] OnlineTransport incompatível: falta publicar_snapshot_tabuleiro()."
			)
			return
		OnlineTransport.publicar_snapshot_tabuleiro()


func _vigiar_entrada_visual_online() -> void:
	# Watchdog visual: mesmo se o snapshot atrasar ou um Tween for interrompido,
	# o convidado nunca permanece preso na visão distante com a HUD invisível.
	await get_tree().create_timer(10.0).timeout
	if not is_inside_tree() or _cinematica_abertura_concluida:
		return
	push_warning("[PHOTON] Watchdog liberou a apresentação do tabuleiro.")
	if not _cinematica_abertura_iniciada:
		_iniciar_cinematica_abertura()
	await get_tree().create_timer(5.0).timeout
	if is_inside_tree() and not _cinematica_abertura_concluida:
		_concluir_cinematica_abertura(true)


func _exit_tree() -> void:
	# Nunca deixa a próxima cena herdando SceneTree.paused caso o tabuleiro seja
	# fechado por desconexão, desistência ou troca de cena durante uma pausa.
	get_tree().paused = false
	GerenciadorSalvamento.desregistrar_tabuleiro(self)
	if OnlineTransport.jogador_desconectado.is_connected(_on_jogador_desconectado_online):
		OnlineTransport.jogador_desconectado.disconnect(_on_jogador_desconectado_online)
	if OnlineTransport.jogador_reconectado.is_connected(_on_jogador_reconectado_online):
		OnlineTransport.jogador_reconectado.disconnect(_on_jogador_reconectado_online)
	if OnlineTransport.host_alterado.is_connected(_on_host_alterado_online):
		OnlineTransport.host_alterado.disconnect(_on_host_alterado_online)
	if OnlineTransport.solicitacao_pausa_partida_recebida.is_connected(
		_on_solicitacao_estado_pausa_online
	):
		OnlineTransport.solicitacao_pausa_partida_recebida.disconnect(
			_on_solicitacao_estado_pausa_online
		)
	if OnlineTransport.estado_pausa_partida_recebido.is_connected(
		_on_estado_pausa_partida_online
	):
		OnlineTransport.estado_pausa_partida_recebido.disconnect(
			_on_estado_pausa_partida_online
		)
	if OnlineTransport.solicitacao_desistencia_partida_recebida.is_connected(
		_on_solicitacao_desistencia_partida_online
	):
		OnlineTransport.solicitacao_desistencia_partida_recebida.disconnect(
			_on_solicitacao_desistencia_partida_online
		)
	if OnlineTransport.resultado_desistencia_partida_recebido.is_connected(
		_on_resultado_desistencia_partida_online
	):
		OnlineTransport.resultado_desistencia_partida_recebido.disconnect(
			_on_resultado_desistencia_partida_online
		)
	if OnlineTransport.confirmacao_vitoria_desistencia_recebida.is_connected(
		_on_confirmacao_vitoria_desistencia_online
	):
		OnlineTransport.confirmacao_vitoria_desistencia_recebida.disconnect(
			_on_confirmacao_vitoria_desistencia_online
		)


func validar_salvamento_partida() -> String:
	if _partida_encerrada:
		return "A PARTIDA JÁ FOI ENCERRADA"
	if _partida_sendo_salva_e_encerrada:
		return "A PARTIDA JÁ ESTÁ SENDO SALVA"
	if OnlineTransport.usando_photon() and not _sincronizacao_online_concluida:
		return "AGUARDE A SINCRONIZAÇÃO ONLINE TERMINAR"
	if cinematica_rodando or _processando_dados:
		return "AGUARDE A AÇÃO ATUAL TERMINAR"
	if _resolucao_turno_em_andamento:
		return "AGUARDE A JOGADA ATUAL TERMINAR"
	if leilao_em_andamento or _leilao_evento_ativo or _leilao_falencia_ativo:
		return "CONCLUA O LEILÃO ATUAL ANTES DE SALVAR"
	if (
		_evento_interativo_bloqueando_acoes
		or _fluxo_evento_interativo_ativo
		or _sessao_decisao_evento_ativa
		or _imunidade_breno_bloqueando_acoes
		or _votacao_eleicao_ativa
		or _eleicao_bloqueando_acoes
	):
		return "CONCLUA O EVENTO ATUAL ANTES DE SALVAR"
	if (
		_processando_resolucoes_abutre
		or _abutre_bloqueando_acoes
		or not _fila_resolucoes_abutre.is_empty()
		or not _falencias_pendentes_evento.is_empty()
		or not _eleicao_falencias_pendentes.is_empty()
		or not _propostas_negociacao_pendentes.is_empty()
		or _desistencia_local_pendente
		or _aguardando_confirmacao_vitoria_desistencia
	):
		return "AGUARDE A RESOLUÇÃO ATUAL TERMINAR"
	for pino_variant in pinos_jogadores.values():
		if not pino_variant is Node:
			continue
		var pino: Node = pino_variant
		if bool(pino.get("esta_movendo")):
			return "AGUARDE O MOVIMENTO TERMINAR"
	if hud != null and is_instance_valid(hud) and hud.has_method(
		&"motivo_bloqueio_salvamento"
	):
		var motivo_hud_variant: Variant = hud.call(&"motivo_bloqueio_salvamento")
		var motivo_hud: String = str(motivo_hud_variant).strip_edges()
		if not motivo_hud.is_empty():
			return motivo_hud
	return ""


func criar_snapshot_online() -> Dictionary:
	var estado: Dictionary = {}
	for campo in CAMPOS_SNAPSHOT_ONLINE:
		var valor = get(campo)
		if valor is Dictionary or valor is Array:
			estado[campo] = valor.duplicate(true)
		else:
			estado[campo] = valor

	var pinos: Dictionary = {}
	for personagem_variant in pinos_jogadores.keys():
		var personagem := str(personagem_variant)
		var pino = pinos_jogadores[personagem_variant]
		if pino == null:
			continue
		pinos[personagem] = {
			"casa_atual": int(pino.get("casa_atual")),
			"preso": bool(pino.get("preso")),
		}

	return {
		"versao": 1,
		"criado_em_ms": Time.get_ticks_msec(),
		"estado": estado,
		"tabuleiro_mutavel": _criar_estado_tabuleiro_mutavel(),
		"pinos": pinos,
		"escolhas_da_mesa": Global.escolhas_da_mesa.duplicate(true),
		"user_ids_da_mesa": Global.user_ids_da_mesa.duplicate(true),
		"escolhas_por_user_id": Global.escolhas_por_user_id.duplicate(true),
	}


func _criar_estado_tabuleiro_mutavel() -> Dictionary:
	# A estrutura estática do tabuleiro (nomes, imagens, preços e posições) já
	# existe em todos os clientes. Enviar o dicionário completo tornava o RPC
	# enorme e incluía dados desnecessários. Só estes campos mudam em partida.
	var resultado: Dictionary = {}
	for casa_variant in tabuleiro.keys():
		var casa_id: int = int(casa_variant)
		var dados_casa: Dictionary = tabuleiro[casa_id]
		resultado[casa_id] = {
			"nivel": int(dados_casa.get("nivel", 0)),
			"hipotecada": bool(dados_casa.get("hipotecada", false)),
		}
	return resultado


func _aplicar_estado_tabuleiro_mutavel(estado_tabuleiro: Dictionary) -> void:
	for casa_variant in estado_tabuleiro.keys():
		var casa_id: int = int(casa_variant)
		if not tabuleiro.has(casa_id):
			continue
		var dados_variant: Variant = estado_tabuleiro[casa_variant]
		if not dados_variant is Dictionary:
			continue
		var dados_casa: Dictionary = dados_variant
		tabuleiro[casa_id]["nivel"] = int(dados_casa.get("nivel", 0))
		tabuleiro[casa_id]["hipotecada"] = bool(
			dados_casa.get("hipotecada", false)
		)


func aplicar_snapshot_online(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	var criado_em_ms: int = int(snapshot.get("criado_em_ms", 0))
	if criado_em_ms > 0 and criado_em_ms <= _ultimo_snapshot_online_aplicado:
		return
	if criado_em_ms > 0:
		_ultimo_snapshot_online_aplicado = criado_em_ms
	var estado_variant: Variant = snapshot.get("estado", {})
	if not estado_variant is Dictionary:
		return
	var estado: Dictionary = estado_variant
	for campo in CAMPOS_SNAPSHOT_ONLINE:
		if not estado.has(campo):
			continue
		var valor = estado[campo]
		if valor is Dictionary or valor is Array:
			set(campo, valor.duplicate(true))
		else:
			set(campo, valor)

	Global.escolhas_da_mesa = Dictionary(snapshot.get("escolhas_da_mesa", {})).duplicate(true)
	Global.user_ids_da_mesa = Dictionary(snapshot.get("user_ids_da_mesa", {})).duplicate(true)
	Global.escolhas_por_user_id = Dictionary(snapshot.get("escolhas_por_user_id", {})).duplicate(true)
	Global.meu_peer_id = OnlineTransport.local_player_id()

	var tabuleiro_mutavel_variant: Variant = snapshot.get("tabuleiro_mutavel", {})
	if tabuleiro_mutavel_variant is Dictionary:
		_aplicar_estado_tabuleiro_mutavel(tabuleiro_mutavel_variant)
	_sincronizar_pinos_com_snapshot(Dictionary(snapshot.get("pinos", {})))
	_sincronizacao_online_concluida = true
	_atualizar_hud_ciclo_turno()
	_atualizar_hud_minha_casa()
	if hud and hud.has_method("atualizar_round_counter"):
		hud.atualizar_round_counter(rodada_atual)
	var personagem_local: String = str(
		Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
	)
	if (
		not personagem_local.is_empty()
		and bool(dados_economia_jogadores.get(personagem_local, {}).get("falido", false))
		and hud
		and hud.has_method("ativar_modo_espectador")
	):
		hud.ativar_modo_espectador()
	if not _cinematica_abertura_iniciada:
		_iniciar_cinematica_abertura()
	elif _cinematica_abertura_concluida:
		_verificar_permissao_de_clique()
	_aplicar_interface_estado_pausa_atual()
	print("[PHOTON] Snapshot da partida aplicado com sucesso.")


func _sincronizar_pinos_com_snapshot(estados_pinos: Dictionary) -> void:
	# Remove pinos temporários criados antes de o estado autoritativo chegar.
	for personagem_variant in pinos_jogadores.keys().duplicate():
		var personagem_id: String = str(personagem_variant)
		if lista_turnos.has(personagem_id):
			continue
		var pino_existente: Node = pinos_jogadores.get(personagem_variant) as Node
		if pino_existente != null and is_instance_valid(pino_existente):
			pino_existente.queue_free()
		pinos_jogadores.erase(personagem_variant)

	# Cria qualquer personagem que não existia quando a cena abriu no cliente.
	for personagem_variant in lista_turnos:
		var personagem_id: String = str(personagem_variant)
		var cor_personagem: Color = _cor_visual_personagem(personagem_id)
		cor_por_jogador[personagem_id] = cor_personagem
		if not pinos_jogadores.has(personagem_id):
			spawnar_pino(personagem_id, cor_personagem)

	_reconstruir_visuais_apos_snapshot(estados_pinos)


func _reconstruir_visuais_apos_snapshot(estados_pinos: Dictionary) -> void:
	if not _garantir_layout_tabuleiro():
		push_warning(
			"[PHOTON] Snapshot recebido antes de o layout do tabuleiro ficar pronto."
		)
		return
	pinos_por_casa.clear()
	for personagem_variant in pinos_jogadores.keys():
		var personagem := str(personagem_variant)
		var pino = pinos_jogadores[personagem_variant]
		if pino == null:
			continue
		var dados_pino: Dictionary = Dictionary(estados_pinos.get(personagem, {}))
		var casa_destino := int(dados_pino.get("casa_atual", pino.get("casa_atual")))
		casa_destino = clampi(casa_destino, 0, 39)
		pino.set("casa_atual", casa_destino)
		pino.set("preso", bool(dados_pino.get("preso", false)))
		_adicionar_pino_na_casa(pino, casa_destino)
		if bool(pino.get("preso")) and pino.has_method("ativar_barras_prisao"):
			pino.call("ativar_barras_prisao")
		elif pino.has_method("desativar_barras_prisao"):
			pino.call("desativar_barras_prisao")

	for casa_variant in tabuleiro.keys():
		var casa_id := int(casa_variant)
		_atualizar_visual_dono(casa_id)
		_atualizar_imagem_construcao(casa_id)


func _on_jogador_desconectado_online(peer_id: int, inativo: bool) -> void:
	if _partida_sendo_salva_e_encerrada:
		return
	# Evita que a sala fique presa caso o jogador que abriu o pause perca a
	# conexão ou abandone enquanto os demais aguardam.
	if (
		OnlineTransport.is_host()
		and _pausa_global_ativa
		and peer_id == _peer_iniciador_pausa
	):
		_forcar_retomada_pausa_host()

	var personagem := str(Global.escolhas_da_mesa.get(peer_id, ""))
	if personagem.is_empty():
		personagem = str(_jogadores_desconectados_online.get(peer_id, ""))
	if personagem.is_empty():
		return

	if inativo:
		_jogadores_desconectados_online[peer_id] = personagem
		if jogador_atual_id == personagem and hud:
			hud.esconder_painel_dados()
		_mostrar_alerta_meio_da_tela(
			"CONEXÃO INTERROMPIDA\n%s tem até 120 segundos para retornar." % personagem.to_upper()
		)
		return

	_jogadores_desconectados_online.erase(peer_id)
	if not OnlineTransport.is_host():
		return
	if not dados_economia_jogadores.has(personagem):
		return
	if bool(dados_economia_jogadores[personagem].get("falido", false)):
		return
	_mostrar_alerta_meio_da_tela(
		"JOGADOR ABANDONOU\n%s foi removido da partida." % personagem.to_upper()
	)
	OnlineTransport.send_all(
		self,
		&"_declarar_falencia_rede",
		[personagem, ""],
		false,
		true
	)


func _on_jogador_reconectado_online(id_antigo: int, id_novo: int, _user_id: String) -> void:
	var personagem := str(_jogadores_desconectados_online.get(id_antigo, ""))
	_jogadores_desconectados_online.erase(id_antigo)
	if not personagem.is_empty():
		_jogadores_desconectados_online.erase(id_novo)
		_mostrar_alerta_meio_da_tela(
			"JOGADOR RECONECTADO\n%s voltou à partida." % personagem.to_upper()
		)
	if OnlineTransport.is_host():
		# O OnlineTransport envia o snapshot ao cliente assim que a cena dele abre.
		call_deferred("_verificar_permissao_de_clique")


func _on_host_alterado_online(eh_novo_host: bool) -> void:
	if not OnlineTransport.usando_photon():
		return
	if eh_novo_host:
		_mostrar_alerta_meio_da_tela(
			"NOVO HOST\nEsta instância assumiu a coordenação da partida."
		)
		_sincronizacao_online_concluida = true
		if _pausa_global_ativa:
			var peers_ativos: Array[int] = OnlineTransport.get_peer_ids(true)
			peers_ativos.append(OnlineTransport.local_player_id())
			if not peers_ativos.has(_peer_iniciador_pausa):
				_forcar_retomada_pausa_host()
			else:
				_publicar_estado_pausa_host(
					true,
					_peer_iniciador_pausa,
					_personagem_iniciador_pausa,
					_nome_iniciador_pausa
				)
	else:
		_mostrar_alerta_meio_da_tela("HOST ALTERADO\nA partida continuará com o novo coordenador.")
	_verificar_permissao_de_clique()


# ============================================================================
# LÓGICA DE TURNOS E DADOS
# ============================================================================

# --- Guard anti-RPC-duplicado: garante que cada rolagem só processa uma vez ---
var _processando_dados: bool = false
# Mantém o autosave fora do intervalo entre uma rolagem/carta e a liberação do
# próximo turno. Nesse período o estado já pode ter mudado, mas a corrotina que
# concluirá a jogada ainda não pode ser reconstruída ao recarregar a cena.
var _resolucao_turno_em_andamento: bool = false
# --- NOVO (GDD §5.2): Flag que indica que o jogador tirou dupla e deve
#     rolar novamente após o movimento. Sincronizada via RPC. ---
var _dupla_pendente: bool = false

func _on_dados_rolados_recebidos(d1: int, d2: int):
								if _acoes_bloqueadas_por_evento():
																return
								# --- Guard: previne processamento duplo da mesma rolagem ---
								if _processando_dados:
																return
								_processando_dados = true
								_emitir_evento_tutorial(
																"dados_rolados",
																{
																								"jogador_id": jogador_atual_id,
																								"dado1": d1,
																								"dado2": d2,
																}
								)

								# Armazena últimos dados para a fórmula de utilidades
								ultimo_dado1 = d1
								ultimo_dado2 = d2

								var dados_jogador = dados_economia_jogadores[jogador_atual_id]

								# --- SISTEMA DE PRISÃO — Verifica se o jogador está preso ---
								if dados_jogador.get("preso", false):
																if d1 == d2:
																								# Tirou dupla: sai da prisão e move
																								# --- CORREÇÃO: Usa RPC para sincronizar a liberação em TODOS os peers.
																								#     Antes, só o peer que clicou em "Girar" removia as barras —
																								#     os outros viam as barras presas para sempre. ---
																								OnlineTransport.send_all(self, &"_sair_da_prisao_rede", [jogador_atual_id], false, true)
																								if pinos_jogadores.has(jogador_atual_id):
																																pinos_jogadores[jogador_atual_id].mostrar_texto_flutuante("DUPLA! LIVRE!", Color(0.4, 1.0, 0.4))
																								OnlineTransport.send_all(self, &"_sincronizar_movimento_na_rede", [jogador_atual_id, d1 + d2], false, true)
																else:
																								dados_jogador["turnos_preso"] += 1
																								if dados_jogador["turnos_preso"] >= 3:
																																# 3 tentativas sem dupla: paga $50 e sai
																																# --- CORREÇÃO: Usa RPC para sincronizar a liberação em TODOS os peers.
																																#     Antes, só o peer que clicou em "Girar" removia as barras —
																																#     os outros viam as barras presas para sempre. ---
																																OnlineTransport.send_all(self, &"_sair_da_prisao_rede", [jogador_atual_id], false, true)
																																# --- CORREÇÃO: Sincroniza a cobrança dos $50 via RPC.
																																#     Antes era só `dados_jogador["dinheiro"] -= 50` local,
																																#     que só diminuía no peer que clicou em girar. Os outros
																																#     peers não viam a cobrança — jogador saía "de graça"
																																#     na visão dos outros. ---
																																# --- BUG #7: fiança de prisão é "casa_especial" — Imunidade do Breno não dispara. ---
																																OnlineTransport.send_all(self, &"_aplicar_mudanca_dinheiro_rede", [jogador_atual_id, -50, "casa_especial"], false, true)
																																if pinos_jogadores.has(jogador_atual_id):
																																								pinos_jogadores[jogador_atual_id].mostrar_texto_flutuante("PAGOU $50", Color(0.9, 0.3, 0.3))
																																OnlineTransport.send_all(self, &"_sincronizar_movimento_na_rede", [jogador_atual_id, d1 + d2], false, true)
																								else:
																																# Continua preso
																																if pinos_jogadores.has(jogador_atual_id):
																																								pinos_jogadores[jogador_atual_id].mostrar_texto_flutuante("AINDA PRESO", Color(0.9, 0.3, 0.3))
																																# --- CORREÇÃO DO BUG DA PRISÃO EM MULTIPLAYER:
																																#     Antes havia `if OnlineTransport.is_host(): _finalizar_pouso_e_passar_turno()`.
																																#     O problema: _on_dados_rolados_recebidos roda LOCALMENTE no peer que
																																#     clicou em girar (não necessariamente o server). Se o jogador preso
																																#     estiver no peer 2 (client), is_server() retorna false e o turno
																																#     NUNCA passa — o painel de dados some e o jogo trava.
																																#     Solução: chamar _continuar_preso_passar_turno_rede.rpc() que é
																																#     call_local em todos os peers. Dentro dele, apenas o server
																																#     dispara _avancar_turno_rede (via _processar_passagem_de_turno). ---
																																OnlineTransport.send_all(self, &"_continuar_preso_passar_turno_rede", [], false, true)
																_processando_dados = false
																return

								# --- NOVO (GDD §5.2): Sistema de Duplas.
								#     - Tirar dupla (d1 == d2): jogador rola novamente após o movimento.
								#     - 3 duplas seguidas: vai preso.
								#     Implementação: antes de mover, verifica se é dupla.
								#     Se for, incrementa duplas_consecutivas e seta _dupla_pendente
								#     via RPC (para sincronizar com todos os peers). Se 3 duplas,
								#     envia para a prisão em vez de mover. ---
								var passos = d1 + d2
								var is_dupla = (d1 == d2)

								if is_dupla:
																var dados_jog = dados_economia_jogadores[jogador_atual_id]
																dados_jog["duplas_consecutivas"] = dados_jog.get("duplas_consecutivas", 0) + 1
																if dados_jog["duplas_consecutivas"] >= 3:
																								# 3 duplas = prisão! Não move, vai direto preso.
																								dados_jog["duplas_consecutivas"] = 0
																								_dupla_pendente = false
																								OnlineTransport.send_all(self, &"_set_dupla_status_rede", [jogador_atual_id, false, 0], false, true)
																								if pinos_jogadores.has(jogador_atual_id):
																																pinos_jogadores[jogador_atual_id].mostrar_texto_flutuante("3 DUPLAS! PRESO!", Color(0.9, 0.3, 0.3))
																								# Envia para a prisão (RPC para todos os peers)
																								# --- BUG FIX (CRITICAL #1): Padronizado — sempre espera 1s
																								#     antes de enviar para a prisão, independente de ser server
																								#     ou client. Antes, server esperava e client não, causando
																								#     timing inconsistente entre peers. ---
																								await get_tree().create_timer(1.0).timeout
																								OnlineTransport.send_all(self, &"_ir_para_prisao_rede", [jogador_atual_id], false, true)
																								_processando_dados = false
																								return
																# Menos de 3 duplas — seta flag para rolar novamente
																OnlineTransport.send_all(self, &"_set_dupla_status_rede", [jogador_atual_id, true, dados_jog["duplas_consecutivas"]], false, true)
								else:
																# Não é dupla — reseta contador
																dados_economia_jogadores[jogador_atual_id]["duplas_consecutivas"] = 0
																OnlineTransport.send_all(self, &"_set_dupla_status_rede", [jogador_atual_id, false, 0], false, true)

								# --- Texto flutuante mostrando os dados ANTES do movimento ---
								if pinos_jogadores.has(jogador_atual_id):
																pinos_jogadores[jogador_atual_id].mostrar_texto_flutuante(
																								"DADOS: " + str(d1) + "+" + str(d2) + " = " + str(passos),
																								Color(0.95, 0.85, 0.15)
																)

								OnlineTransport.send_all(self, &"_sincronizar_movimento_na_rede", [jogador_atual_id, passos], false, true)
								_processando_dados = false

func _avancar_turno():
								indice_turno_atual = (indice_turno_atual + 1) % lista_turnos.size()
								jogador_atual_id = lista_turnos[indice_turno_atual]
								
								_atualizar_hud_ciclo_turno()
								_verificar_permissao_de_clique()

func _atualizar_hud_ciclo_turno():
								var meu_personagem_local = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
								if meu_personagem_local == "" or not dados_economia_jogadores.has(meu_personagem_local): return
								
								var dados_locais = dados_economia_jogadores[meu_personagem_local]
								hud.atualizar_status_jogador(dados_locais["nome"], dados_locais["dinheiro"], dados_locais["propriedades_compradas"])
								if hud.has_method("atualizar_reputacao_jogador"):
									hud.atualizar_reputacao_jogador(int(dados_locais.get("reputacao", REPUTACAO_INICIAL)), int(dados_locais.get("xp_partida", 0)))
								# --- NOVO (Fase 2): atualiza o painel de imunidades abaixo do
								#     CantoSupEsq_Jogador com as imunidades ativas do jogador local. ---
								if hud.has_method("atualizar_painel_imunidades"):
																hud.atualizar_painel_imunidades(dados_locais.get("imunidades", []))
								# --- NOVO (Fase 3): atualiza o painel de alianças abaixo do
								#     painel de imunidades com as alianças ativas do jogador local. ---
								if hud.has_method("atualizar_painel_aliancas"):
																hud.atualizar_painel_aliancas(dados_locais.get("aliancas", []))
								# --- NOVO (Fase 4): atualiza o painel de promessas (lista global) ---
								if hud.has_method("atualizar_painel_promessas"):
																hud.atualizar_painel_promessas(_promessas_globais)
								if hud.has_method("atualizar_cartas_guardadas"):
									hud.atualizar_cartas_guardadas(
										int(dados_locais.get("cartas_construcao_gratis", 0)),
										int(dados_locais.get("cartas_sair_prisao", 0))
									)
								
								var nome_da_habilidade = "Poder Especial"
								match meu_personagem_local:
																"yasmin": nome_da_habilidade = "Oferta Irrecusável"
																"breno": nome_da_habilidade = "Decreto Emergencial"
																"mira": nome_da_habilidade = "Retrofit Urbano"
																"igor": nome_da_habilidade = "Especulação Imobiliária" 
																"diana": nome_da_habilidade = "Vazamento Seletivo"
																"kofi": nome_da_habilidade = "Mutirão" 
								
								hud.atualizar_habilidade(nome_da_habilidade, dados_locais["recarga_hab"])
								
								if meu_personagem_local == "diana":
																var payload_espionagem = []
																# --- CORREÇÃO: iterar sobre lista_turnos (jogadores ativos na partida)
																#     em vez de dados_economia_jogadores.keys() (que tem os 6 personagens
																#     fixos do dicionário base). Antes, o dossiê mostrava personagens que
																#     não estavam na partida. Agora só mostra quem está jogando.
																#     Também pula falidos (mesmo que ainda estejam em lista_turnos por
																#     algum motivo de sincronização, não devem aparecer no dossiê). ---
																for id in lista_turnos:
																								if id == "diana":
																																continue
																								if not dados_economia_jogadores.has(id):
																																continue
																								if dados_economia_jogadores[id].get("falido", false):
																																continue
																								# --- NOVO (Fase 2): inclui imunidades ativas de cada jogador
																								#     no dossiê da Diana, para que ela possa ver quem tem
																								#     imunidade contra quem e por quantas visitas/turnos. ---
																								var imunidades_txt = ""
																								var imunidades_lista = dados_economia_jogadores[id].get("imunidades", [])
																								if imunidades_lista.size() > 0:
																																var partes: Array = []
																																for imun in imunidades_lista:
																																								var de_id = imun.get("de", "")
																																								var de_nome_curto = dados_economia_jogadores.get(de_id, {}).get("nome", de_id)
																																								# Pega só o primeiro nome (ex.: "Yasmin Khalil" → "Yasmin")
																																								var primeiro_espaco = de_nome_curto.find(" ")
																																								if primeiro_espaco > 0:
																																																de_nome_curto = de_nome_curto.substr(0, primeiro_espaco)
																																								partes.append(de_nome_curto + "(" + str(imun.get("visitas_restantes", 0)) + "v/" + str(imun.get("turnos_restantes", 0)) + "T)")
																																								imunidades_txt = ", ".join(partes)
																								else:
																																imunidades_txt = "nenhuma"
																								# --- NOVO (Fase 3): inclui alianças ativas de cada jogador
																								#     no dossiê da Diana, para que ela possa ver quem é aliado
																								#     de quem e por quantos turnos. ---
																								var aliancas_txt = ""
																								var aliancas_lista = dados_economia_jogadores[id].get("aliancas", [])
																								if aliancas_lista.size() > 0:
																																var partes_al: Array = []
																																for alianca in aliancas_lista:
																																								var com_id = alianca.get("com", "")
																																								var com_nome_curto = dados_economia_jogadores.get(com_id, {}).get("nome", com_id)
																																								var espaco_al = com_nome_curto.find(" ")
																																								if espaco_al > 0:
																																																com_nome_curto = com_nome_curto.substr(0, espaco_al)
																																								partes_al.append(com_nome_curto + "(" + str(alianca.get("turnos_restantes", 0)) + "T)")
																																								aliancas_txt = ", ".join(partes_al)
																								else:
																																aliancas_txt = "nenhuma"
																								# --- NOVO (Fase 4): conta promessas feitas e quebradas ---
																								var promessas_feitas = 0
																								var promessas_quebradas = 0
																								for p in _promessas_globais:
																																if p.get("autor_id", "") == id:
																																								promessas_feitas += 1
																																								if p.get("quebrada", false):
																																																promessas_quebradas += 1
																								var promessas_txt = str(promessas_feitas) + " feitas"
																								if promessas_quebradas > 0:
																																promessas_txt += " (" + str(promessas_quebradas) + " quebradas!)"
																								payload_espionagem.append({
																																"nome": dados_economia_jogadores[id]["nome"],
																																"dinheiro": dados_economia_jogadores[id]["dinheiro"],
																																"props": dados_economia_jogadores[id]["propriedades_compradas"],
																																"imunidades": imunidades_txt,
																																"aliancas": aliancas_txt,
																													"promessas": promessas_txt,
																													"reputacao": int(dados_economia_jogadores[id].get("reputacao", REPUTACAO_INICIAL)),
																													"xp_partida": int(dados_economia_jogadores[id].get("xp_partida", 0))
																								})
																hud.alimentar_dados_dossie(payload_espionagem)
																hud.container_dossie.visible = true
								
								if meu_personagem_local == "yasmin":
																# --- BUG #4/#5 FIX: Usa tendências FIXAS geradas no início da rodada
																#     (em _avancar_turno_rede) em vez de sortear aleatoriamente a
																#     cada atualização da HUD. As tendências permanecem as mesmas
																#     por 2 rodadas, permitindo que Yasmin realmente use a info. ---
																if tendencias_fixas.is_empty():
																								# Fallback: gera agora se ainda não foram geradas
																								_gerar_tendencias_yasmin()
																hud.alimentar_dados_relatorio(tendencias_fixas.duplicate())
																hud.container_relatorio.visible = true
								
								# Fonte Anônima revela um único Evento Global por partida. A previsão
								# permanece no dossiê somente até o evento previsto ser revelado.
								if meu_personagem_local == "diana" and dados_economia_jogadores.has("diana"):
																var evento_previsto: String = str(dados_economia_jogadores["diana"].get("fonte_anonima_evento_previsto", ""))
																if evento_previsto != "" and evento_previsto == proximo_evento_global and hud.has_method("alimentar_previsao_evento"):
																								hud.alimentar_previsao_evento(proximo_evento_global, proximo_evento_descricao)

								_atualizar_hud_minha_casa()
								_atualizar_menu_construcao()
								GerenciadorSalvamento.marcar_estado_alterado(self)

func _atualizar_hud_minha_casa():
								var meu_personagem_local = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
								if meu_personagem_local == "" or not pinos_jogadores.has(meu_personagem_local):
																return
																
								var minha_casa_id = pinos_jogadores[meu_personagem_local].casa_atual
								var dados_casa = tabuleiro[minha_casa_id].duplicate() 
								var dono_nome = "Nenhum"
								var dono_id = ""
								
								if registro_propriedades.has(minha_casa_id):
																dono_id = registro_propriedades[minha_casa_id]
																dono_nome = dados_economia_jogadores[dono_id]["nome"]
																dados_casa["aluguel_atual"] = _calcular_aluguel(minha_casa_id, dono_id)
								else:
																dados_casa["aluguel_atual"] = _calcular_aluguel(minha_casa_id, "")
																
								var info = ""
								var grupo = dados_casa.get("grupo", "")

								if dados_casa["tipo"] == "propriedade":
																info += "🏢 Construção: Nível " + str(dados_casa.get("nivel", 0)) + "/5\n"
																if dono_id != "" and _tem_monopolio(dono_id, grupo):
																								info += "👑 MONOPÓLIO ATIVO: Aluguel Base Dobrado!\n"

								elif dados_casa["tipo"] == "transporte":
																var linhas_dono = 0
																if dono_id != "":
																								for id in tabuleiro.keys():
																																if tabuleiro[id].get("grupo") == "Transporte" and registro_propriedades.has(id) and registro_propriedades[id] == dono_id:
																																								linhas_dono += 1
																info += "🚆 Linhas do Dono: " + str(linhas_dono) + "/4\n(Aluguel: $25, $50, $100 ou $200)\n"

								elif dados_casa["tipo"] == "utilidade":
																info += "⚡ Serviços: Cobra um multiplicador dos dados.\n"

								if evento_ativo == "Bolha Imobiliária — Expansão":
																info += "📈 Mercado Aquecido: Aluguel +25%\n"
								elif evento_ativo == "Bolha Imobiliária — Estouro":
																info += "📉 Bolha Estourou: Aluguel -40%\n"
								elif evento_ativo == "Greve Geral" and grupo == "Transporte":
																info += "🛑 Greve Geral: Catraca Livre (Aluguel $0)\n"
								elif evento_ativo == "Onda de Calor Extremo" and grupo == "Utilidade":
																info += "🔥 Superaquecimento: Lucros Dobrados\n"
								elif evento_ativo == "Enchente da Bacia Norte":
																if grupo in ["Rosa", "Marrom"]:
																								info += "🌊 Bairro Alagado: Aluguel $0\n"
																elif grupo == "Laranja":
																								info += "📈 Procura por Área Seca: Aluguel +15%\n"
								elif evento_ativo == "Migração em Massa":
																if grupo in ["Rosa", "Marrom"]:
																								info += "📈 Superlotação: Aluguel x2\n"
																elif grupo in ["Verde", "Azul-Escuro"]:
																								info += "📉 Pânico da Elite: Aluguel -10%\n"
								elif evento_ativo == "Boom das Startups" and grupo in ["Verde", "Vermelho"]:
																info += "🚀 Especulação Tech: Aluguel x2\n"

								if multiplicador_inflacao_global > 1.0:
																var porc = int((multiplicador_inflacao_global - 1.0) * 100)
																info += "💸 Inflação Global: +" + str(porc) + "%\n"

								# --- NOVO: Mostra estado de hipoteca ---
								if dados_casa.get("hipotecada", false):
																info += "🔒 HIPOTECADA — Sem aluguel\n"

								# --- NOVO: Mostra modificadores de habilidade ativos ---
								for pid in lista_turnos:
																var dados_p = dados_economia_jogadores[pid]
																if dados_p.get("decreto_turnos", 0) > 0 and dados_p.get("decreto_grupo", "") == grupo:
																								info += "⚖️ DECRETO DO BRENO: 2x aluguel (" + str(dados_p["decreto_turnos"]) + "T)\n"
																if dados_p.get("especulacao_turnos", 0) > 0 and dados_p.get("especulacao_casa", -1) == minha_casa_id:
																								info += "📈 ESPECULAÇÃO DO IGOR: 2x aluguel (" + str(dados_p["especulacao_turnos"]) + "T)\n"

								dados_casa["info_extra"] = info
								hud.atualizar_info_casa(dados_casa, dono_nome)

								# --- CORREÇÃO: O botão flutuante de hipoteca foi movido para o painel
								#     de Gestão de Propriedades. Aqui apenas garantimos que ele fique escondido. ---
								hud.esconder_botao_hipoteca()

func _atualizar_menu_construcao():
	var meu_personagem_local = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
	if meu_personagem_local == "" or not dados_economia_jogadores.has(meu_personagem_local):
		return

	var props_disponiveis: Array = []
	var dados_locais: Dictionary = dados_economia_jogadores[meu_personagem_local]
	var meu_saldo: int = int(dados_locais.get("dinheiro", 0))
	var tem_carta_gratis: bool = int(dados_locais.get("cartas_construcao_gratis", 0)) > 0

	# Lista todas as propriedades para permitir construir, hipotecar e resgatar.
	for id in tabuleiro.keys():
		var dados: Dictionary = tabuleiro[id]
		if dados.get("tipo") not in ["propriedade", "transporte", "utilidade"]:
			continue
		if not registro_propriedades.has(id) or registro_propriedades[id] != meu_personagem_local:
			continue

		var grupo: String = str(dados.get("grupo", ""))
		var propriedade_valida_para_obra: bool = (
			dados.get("tipo", "") == "propriedade"
			and _construcoes_visuais_em_andamento.is_empty()
			and not dados.get("hipotecada", false)
			and int(dados.get("nivel", 0)) < 5
			and not _construcao_bloqueada_por_efeito(meu_personagem_local, int(id))
		)
		var pode_construir_pago: bool = (
			propriedade_valida_para_obra
			and (
				dados_locais.get("mutirao_ativo", false)
				or _pode_construir(meu_personagem_local, grupo)
			)
		)
		# A carta permite construir em qualquer propriedade própria válida,
		# mesmo sem monopólio, conforme o texto da própria carta.
		var usar_carta_gratis: bool = propriedade_valida_para_obra and tem_carta_gratis
		var pode_construir: bool = pode_construir_pago or usar_carta_gratis
		var custo_casa: int = _calcular_custo_construcao(meu_personagem_local, int(id))
		var aluguel_atual: int = _calcular_aluguel(int(id), meu_personagem_local)
		var valor_hipoteca: int = int(_calcular_valor_propriedade(int(id)) * 0.5)
		var custo_resgate: int = _calcular_custo_resgate_hipoteca(int(id))

		props_disponiveis.append({
			"id": id,
			"nome": dados["nome"],
			"nivel": dados.get("nivel", 0),
			"custo": custo_casa,
			"saldo_jogador": meu_saldo,
			"cor": cores_grupos.get(grupo, Color.WHITE),
			"pode_construir": pode_construir,
			"usar_carta_gratis": usar_carta_gratis,
			"aluguel_atual": aluguel_atual,
			"hipotecada": dados.get("hipotecada", false),
			"valor_hipoteca": valor_hipoteca,
			"valor_resgate": custo_resgate
		})

	if hud.has_method("popular_menu_construcao"):
		hud.popular_menu_construcao(props_disponiveis)

# ============================================================================
# PROCESSAMENTO DE TERRENO (COMPRA, LEILÃO, ALUGUEL E ESPECIAIS)
# ============================================================================
func _processar_terreno_pousado(casa_id: int) -> void:
	var dados_casa_variant: Variant = tabuleiro.get(casa_id, {})
	if not dados_casa_variant is Dictionary:
		_finalizar_pouso_e_passar_turno()
		return
	var dados_casa: Dictionary = dados_casa_variant

	if str(dados_casa.get("tipo", "")) == "carta":
		if OnlineTransport.is_host():
			var nome_deck: String = str(dados_casa.get("nome", ""))
			_sacar_carta_no_servidor(nome_deck)
		return

	if int(dados_casa.get("preco", 0)) == 0:
		if str(dados_casa.get("tipo", "")) == "portal":
			_executar_portal_atalho(casa_id)
		elif str(dados_casa.get("tipo", "")) == "especial" and casa_id != 0:
			_executar_casa_especial(casa_id)
		else:
			_finalizar_pouso_e_passar_turno()
		return

	if not registro_propriedades.has(casa_id):
		var meu_personagem_local: String = str(
			Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
		)
		if jogador_atual_id == meu_personagem_local:
			var custo: int = _calcular_preco_compra(casa_id)
			var meu_saldo: int = int(
				dados_economia_jogadores[jogador_atual_id]["dinheiro"]
			)
			hud.mostrar_painel_compra(
				str(dados_casa.get("nome", "PROPRIEDADE")),
				custo,
				meu_saldo
			)
			_emitir_evento_tutorial(
				"compra_disponivel",
				{
					"jogador_id": jogador_atual_id,
					"casa_id": casa_id,
					"nome": str(dados_casa.get("nome", "")),
					"custo": custo,
				}
			)
			var comprou_variant: Variant = await hud.acao_terreno_escolhida
			var comprou: bool = bool(comprou_variant)
			if comprou:
				OnlineTransport.send_all(
					self,
					&"_efetuar_compra_rede",
					[jogador_atual_id, casa_id],
					false,
					true
				)
			else:
				print("Compra recusada. Iniciando Leilão...")
				OnlineTransport.send_all(
					self,
					&"_iniciar_leilao_rede",
					[casa_id],
					false,
					true
				)
		elif _eh_jogador_bot(jogador_atual_id):
			var bot: Node = _bots_jogadores.get(jogador_atual_id) as Node
			var custo_bot: int = _calcular_preco_compra(casa_id)
			var saldo_bot: int = int(
				dados_economia_jogadores[jogador_atual_id]["dinheiro"]
			)
			var comprar_bot: bool = false
			if bot != null and is_instance_valid(bot):
				var decisao_variant: Variant = await bot.call(
					"decidir_compra",
					casa_id,
					dados_casa,
					saldo_bot,
					custo_bot
				)
				comprar_bot = bool(decisao_variant)
			if comprar_bot and saldo_bot >= custo_bot:
				OnlineTransport.send_all(
					self,
					&"_efetuar_compra_rede",
					[jogador_atual_id, casa_id],
					false,
					true
				)
			else:
				_finalizar_pouso_e_passar_turno()
		return

	var dono_id: String = str(registro_propriedades[casa_id])
	if dono_id == jogador_atual_id:
		_finalizar_pouso_e_passar_turno()
		return
	var taxa_aluguel: int = _calcular_aluguel(
		casa_id,
		dono_id,
		jogador_atual_id
	)
	if taxa_aluguel > 0:
		if OnlineTransport.is_host():
			OnlineTransport.send_all(
				self,
				&"_pagar_aluguel_rede",
				[jogador_atual_id, dono_id, taxa_aluguel, casa_id],
				false,
				true
			)
	else:
		_finalizar_pouso_e_passar_turno()

func _executar_casa_especial(casa_id: int):
								var dados = dados_economia_jogadores[jogador_atual_id]
								var mudanca_dinheiro = 0
								
								match casa_id:
																4:
																								# --- BUG FIX (LOW #13): Antes, patrimônio estimado usava
																								#     propriedades_compradas * 100 (valor arbitrário). Agora soma o
																								#     preço real de cada propriedade. ---
																								var patrimonio_estimado = dados["dinheiro"]
																								for cid in dados.get("propriedades_lista", []):
																																if tabuleiro.has(cid):
																																								patrimonio_estimado += tabuleiro[cid].get("preco", 0)
																								var dez_porcento = int(patrimonio_estimado * 0.1)
																								mudanca_dinheiro = -min(200, dez_porcento)
																								_mostrar_alerta_meio_da_tela("IMPOSTO DE RENDA\nO Leão pegou: $" + str(abs(mudanca_dinheiro)))
																7:
																								mudanca_dinheiro = 100
																								_mostrar_alerta_meio_da_tela("BÔNUS DE PRODUTIVIDADE\nRecebeu $" + str(mudanca_dinheiro))
																10:
																								_mostrar_alerta_meio_da_tela("PENITENCIÁRIA\nApenas de visita...")
																17:
																								mudanca_dinheiro = -50
																								turno_construcao_bloqueada = true
																								_mostrar_alerta_meio_da_tela("ZONA DE OBRAS\nTaxa de congestionamento: Pague $50\nConstruções bloqueadas até o fim do turno.")
																20:
																								_mostrar_alerta_meio_da_tela("PARQUE LIVRE\nRespire fundo... Nenhuma crise aqui.")
																22:
																								_mostrar_alerta_meio_da_tela("ACORDO DE SILÊNCIO\nAs negociações estão bloqueadas neste turno.\nBreno é imune.")
																								# --- BUG FIX (LOW #9): Implementa o bloqueio real de negociações.
																								#     Antes, o alerta dizia "bloqueadas" mas nada era bloqueado.
																								#     Agora seta a flag acordo_silencio_ativo, que é checada em
																								#     _on_hud_solicitar_negociacao e _on_hud_solicitar_alianca. ---
																								acordo_silencio_ativo = true
																30:
																								_mostrar_alerta_meio_da_tela("VÁ PARA A PRISÃO!\nVocê foi detido por investigação fiscal.")
																								if OnlineTransport.is_host():
																																await get_tree().create_timer(1.5).timeout
																																OnlineTransport.send_all(self, &"_ir_para_prisao_rede", [jogador_atual_id], false, true)
																								return
																33:
																								# --- BUG FIX (LOW #14): Antes, o alerta dizia "Uma de suas
																								#     casas será destruída" MESMO se o jogador não tinha
																								#     construções. Agora checa antes e mostra mensagem apropriada. ---
																								var tem_constr = false
																								for id_chk in dados.get("propriedades_lista", []):
																																if tabuleiro.has(id_chk) and tabuleiro[id_chk].get("nivel", 0) > 0:
																																								tem_constr = true
																																								break
																								if tem_constr:
																																_mostrar_alerta_meio_da_tela("COLAPSO ESTRUTURAL!\nUma de suas casas será destruída.")
																																_destruir_casa_aleatoria(jogador_atual_id)
																								else:
																																_mostrar_alerta_meio_da_tela("COLAPSO ESTRUTURAL!\nSorte sua: não havia construções para destruir.")
																38:
																								mudanca_dinheiro = -100
																								_mostrar_alerta_meio_da_tela("IMPOSTO DE LUXO\nPague $100 ao banco.")

								if mudanca_dinheiro != 0:
																# --- CORREÇÃO CRÍTICA: Só o server envia o RPC de mudança de dinheiro.
																#     Antes, TODOS os peers chamavam _aplicar_mudanca_dinheiro_rede.rpc(),
																#     fazendo a função rodar N vezes por peer, debitando N vezes o valor. ---
																# --- BUG #7: Passa origem="casa_especial" para que a Imunidade do Breno
																#     NÃO dispare em casas especiais (só dispara em cartas/eventos). ---
																if OnlineTransport.is_host():
																								OnlineTransport.send_all(self, &"_aplicar_mudanca_dinheiro_rede", [jogador_atual_id, mudanca_dinheiro, "casa_especial"], false, true)
								
								# --- CORREÇÃO CRÍTICA: _finalizar_pouso_e_passar_turno deve ser
								#     chamado em TODOS os peers, não só no server. Se o jogador
								#     tirou dupla, _finalizar_pouso_e_passar_turno precisa rodar
								#     em todos os peers para mostrar os dados novamente.
								#     Antes, só o server chamava — o client travava sem dados.
								#     O guard `if OnlineTransport.is_host()` dentro de _finalizar_pouso_e_passar_turno
								#     já garante que só o server passa o turno. ---
								await get_tree().create_timer(2.0).timeout
								_finalizar_pouso_e_passar_turno()

@rpc("any_peer", "call_local")
func _ir_para_prisao_rede(id_jogador: String):
	if not pinos_jogadores.has(id_jogador) or not dados_economia_jogadores.has(id_jogador):
		return
	var pino = pinos_jogadores[id_jogador]
	var dados_jogador: Dictionary = dados_economia_jogadores[id_jogador]

	_remover_pino_da_casa(pino, pino.casa_atual)
	pino.casa_atual = 10
	pino.position = tabuleiro[10]["pos"]
	_adicionar_pino_na_casa(pino, 10)

	# Ir para a prisão cancela qualquer nova rolagem por dupla.
	_dupla_pendente = false
	dados_jogador["duplas_consecutivas"] = 0
	dados_jogador["turnos_preso"] = 0

	# A carta é consumida automaticamente na próxima prisão. O jogador é
	# levado à casa 10, mas não fica preso e não paga fiança.
	var cartas_disponiveis: int = int(dados_jogador.get("cartas_sair_prisao", 0))
	if cartas_disponiveis > 0:
		dados_jogador["cartas_sair_prisao"] = cartas_disponiveis - 1
		dados_jogador["preso"] = false
		pino.desativar_barras_prisao()
		pino.mostrar_texto_flutuante("CARTA USADA! VOCÊ ESTÁ LIVRE!", Color(1.0, 0.84, 0.38))
		var nome_jogador: String = str(dados_jogador.get("nome", id_jogador))
		_registrar_acao(
			"prisao",
			"%s usou automaticamente uma carta e não ficou preso." % nome_jogador,
			id_jogador
		)
		_atualizar_hud_ciclo_turno()
		if OnlineTransport.is_host():
			_finalizar_pouso_e_passar_turno()
		return

	dados_jogador["preso"] = true
	pino.ativar_barras_prisao()
	pino.tremer(4.0, 0.4)
	_atualizar_hud_ciclo_turno()

	if OnlineTransport.is_host():
		_finalizar_pouso_e_passar_turno()

# --- CORREÇÃO CRÍTICA DO BUG DAS BARRAS DE PRISÃO EM MULTIPLAYER:
#     Quando um jogador é liberado da prisão por tirar DUPLA ou após 3 turnos
#     (pagando $50), a lógica de liberação estava dentro de _on_dados_rolados_recebidos
#     que roda APENAS no peer que clicou em "Girar". Os outros peers nunca recebiam
#     a chamada desativar_barras_prisao() — as barras ficavam presas na visão dos
#     outros jogadores mesmo depois do jogador ser liberado.
#     Este RPC roda em TODOS os peers (call_local), garantindo que:
#     1) O estado "preso" seja atualizado em todos os peers.
#     2) As barras visuais sejam removidas em todos os peers.
#     A fiança e a carta usam o fluxo autoritativo de
#     _aplicar_resultado_fianca_rede, que também sincroniza todos os peers. ---
@rpc("any_peer", "call_local")
func _sair_da_prisao_rede(id_jogador: String):
								if not dados_economia_jogadores.has(id_jogador):
																return
								var dados = dados_economia_jogadores[id_jogador]
								dados["preso"] = false
								dados["turnos_preso"] = 0
								if pinos_jogadores.has(id_jogador):
																pinos_jogadores[id_jogador].desativar_barras_prisao()

# --- CORREÇÃO DO BUG DA PRISÃO EM MULTIPLAYER:
#     RPC call_local: roda em TODOS os peers. Apenas o server dispara
#     _processar_passagem_de_turno() que por sua vez chama _avancar_turno_rede.rpc()
#     (broadcast authority). O await 1.5s acontece só no server, mas o broadcast
#     garante que todos os peers avancem o turno juntos.
#     Antes, o if OnlineTransport.is_host() estava em _on_dados_rolados_recebidos,
#     que roda LOCALMENTE no peer que clicou em girar — se fosse o peer 2 (client),
#     o turno nunca passava. ---
@rpc("any_peer", "call_local")
func _continuar_preso_passar_turno_rede():
								if OnlineTransport.is_host():
																_resolucao_turno_em_andamento = true
																await get_tree().create_timer(1.5).timeout
																_processar_passagem_de_turno()

func _registrar_obrigacao_falencia(
	devedor_id: String,
	credor_id: String,
	valor: int
) -> void:
	if valor <= 0 or not dados_economia_jogadores.has(devedor_id):
		return
	if dados_economia_jogadores[devedor_id].get("falido", false):
		return

	var credor_normalizado: String = credor_id
	if (
		credor_normalizado == ""
		or credor_normalizado == devedor_id
		or not dados_economia_jogadores.has(credor_normalizado)
	):
		credor_normalizado = CREDOR_FALENCIA_BANCO

	var obrigacoes: Dictionary = obrigacoes_falencia_pendentes.get(devedor_id, {})
	obrigacoes = obrigacoes.duplicate(true)
	obrigacoes[credor_normalizado] = (
		int(obrigacoes.get(credor_normalizado, 0)) + valor
	)
	obrigacoes_falencia_pendentes[devedor_id] = obrigacoes


func _limpar_obrigacoes_falencia(devedor_id: String) -> void:
	obrigacoes_falencia_pendentes.erase(devedor_id)


@rpc("any_peer", "call_local")
func _aplicar_mudanca_dinheiro_rede(
	id_jogador: String,
	valor: int,
	origem: String = "carta_evento",
	adiar_verificacao_falencia: bool = false,
	eliminador_id: String = ""
) -> void:
	if not dados_economia_jogadores.has(id_jogador):
		return

	var dados: Dictionary = dados_economia_jogadores[id_jogador]

	# A Imunidade Política não é mais consumida automaticamente. Ela só é
	# acionada pela decisão do Breno ao revelar um Evento Global negativo.
	if id_jogador == "breno" and origem == "evento_global" and _breno_ignora_evento():
		return

	if valor != 0:
		if valor < 0:
			_registrar_obrigacao_falencia(
				id_jogador,
				eliminador_id,
				abs(valor)
			)
		dados["dinheiro"] += valor
		var cor_txt: Color = Color(0.3, 0.9, 0.3) if valor > 0 else Color(0.9, 0.3, 0.3)
		var sinal: String = "+$" if valor > 0 else "-$"
		if pinos_jogadores.has(id_jogador):
			pinos_jogadores[id_jogador].mostrar_texto_flutuante(
				sinal + str(abs(valor)), cor_txt
			)

	_atualizar_hud_ciclo_turno()
	if valor < 0 and not adiar_verificacao_falencia:
		_verificar_falencia(id_jogador, eliminador_id)

func _quantidade_linhas_metro(jogador_id: String) -> int:
	var total = 0
	for cid in registro_propriedades.keys():
		if registro_propriedades[cid] == jogador_id and tabuleiro.get(cid, {}).get("grupo", "") == "Transporte":
			total += 1
	return total

func _conceder_passes_transporte(concedente_id: String, beneficiario_id: String, quantidade: int) -> void:
	if quantidade <= 0 or not dados_economia_jogadores.has(beneficiario_id):
		return
	var passes: Array = dados_economia_jogadores[beneficiario_id].get("passes_transporte", [])
	var encontrou = false
	for passe in passes:
		if passe.get("de", "") == concedente_id:
			passe["usos_restantes"] = int(passe.get("usos_restantes", 0)) + quantidade
			encontrou = true
			break
	if not encontrou:
		passes.append({"de": concedente_id, "usos_restantes": quantidade})
	dados_economia_jogadores[beneficiario_id]["passes_transporte"] = passes
	if pinos_jogadores.has(beneficiario_id):
		pinos_jogadores[beneficiario_id].mostrar_texto_flutuante("+" + str(quantidade) + " PASSE(S) DE METRÔ", Color(0.25, 0.85, 1.0))

func _consumir_passe_transporte(beneficiario_id: String, dono_linha_id: String) -> bool:
	if not dados_economia_jogadores.has(beneficiario_id):
		return false
	var passes: Array = dados_economia_jogadores[beneficiario_id].get("passes_transporte", [])
	var atualizados: Array = []
	var consumiu = false
	for passe in passes:
		var usos = int(passe.get("usos_restantes", 0))
		if not consumiu and passe.get("de", "") == dono_linha_id and usos > 0:
			usos -= 1
			passe["usos_restantes"] = usos
			consumiu = true
		if usos > 0:
			atualizados.append(passe)
	dados_economia_jogadores[beneficiario_id]["passes_transporte"] = atualizados
	return consumiu

@rpc("any_peer", "call_local")
func _pagar_aluguel_rede(pagador: String, recebedor: String, valor: int, casa_id: int = -1):
								var valor_final = valor
								# Passes de Transporte: consome uma utilização quando o jogador cai em uma
								# Linha de Metrô pertencente ao emissor do passe.
								if valor_final > 0 and casa_id >= 0 and tabuleiro.get(casa_id, {}).get("grupo", "") == "Transporte":
																if _consumir_passe_transporte(pagador, recebedor):
																								valor_final = 0
																								if pinos_jogadores.has(pagador):
																																pinos_jogadores[pagador].mostrar_texto_flutuante("PASSE DE METRÔ! ALUGUEL $0", Color(0.25, 0.85, 1.0))
								
								# --- NOVO (Fase 2 — Imunidades temporárias): verifica se o pagador
								#     tem imunidade contra o recebedor. Cada imunidade é um Dictionary
								#     { "de": recebedor_id, "visitas_restantes": N, "turnos_restantes": M }.
								#     A primeira imunidade aplicável zera o aluguel e consome 1 visita.
								#     Expira por visitas OU por turnos (o que vier primeiro).
								#     Importante: rodamos ANTES do Vazamento da Diana, porque a
								#     imunidade é específica do pagador→recebedor, enquanto o
								#     vazamento anula qualquer aluguel recebido (mais abrangente).
								#     Se ambos estivessem ativos, a imunidade tem precedência por ser
								#     mais restritiva e o jogador "decidiu" usá-la ao aceitar a
								#     negociação que a concedeu. ---
								if valor_final > 0:
																# --- CORREÇÃO CRÍTICA: Reescreve a lista de imunidades em vez de usar
																#     remove_at(i) em uma referência de .get(). O remove_at era frágil
																#     e podia não persistir a remoção, deixando a imunidade ativa mesmo
																#     após as visitas acabarem. Agora reconstruímos a lista explicitamente
																#     e escrevemos de volta no dicionário, garantindo persistência. ---
																var imunidades_pagador = dados_economia_jogadores[pagador].get("imunidades", [])
																var novas_imunidades: Array = []
																var imunidade_consumida = false
																for imun in imunidades_pagador:
																								if not imunidade_consumida and imun.get("de", "") == recebedor and imun.get("visitas_restantes", 0) > 0 and imun.get("turnos_restantes", 0) > 0:
																																# Consome 1 visita
																																imun["visitas_restantes"] = imun["visitas_restantes"] - 1
																																# Zera o aluguel
																																valor_final = 0
																																imunidade_consumida = true
																																# Feedback visual
																																if pinos_jogadores.has(pagador):
																																								pinos_jogadores[pagador].mostrar_texto_flutuante("IMUNIDADE! ALUGUEL $0", Color(0.4, 1.0, 0.8))
																																if pinos_jogadores.has(recebedor):
																																								pinos_jogadores[recebedor].mostrar_texto_flutuante("IMUNIZADO", Color(0.5, 0.8, 0.7))
																																# Mantém a imunidade na lista apenas se ainda tem visitas E turnos
																																if imun["visitas_restantes"] > 0 and imun["turnos_restantes"] > 0:
																																								novas_imunidades.append(imun)
																								else:
																																novas_imunidades.append(imun)
																# Escreve a nova lista de volta no dicionário (garante persistência)
																dados_economia_jogadores[pagador]["imunidades"] = novas_imunidades
								
								# --- Vazamento Seletivo da Diana — zera o próximo aluguel recebido ---
								if valor_final > 0 and dados_economia_jogadores[recebedor].get("vazamento_ativo", false):
																valor_final = 0
																dados_economia_jogadores[recebedor]["vazamento_ativo"] = false
																dados_economia_jogadores[recebedor].erase("vazamento_turnos")
																if pinos_jogadores.has(recebedor):
																								pinos_jogadores[recebedor].mostrar_texto_flutuante("VAZAMENTO!", Color(0.8, 0.2, 0.8))
																if pinos_jogadores.has(pagador):
																								pinos_jogadores[pagador].mostrar_texto_flutuante("ALUGUEL EVAPOROU", Color(0.5, 0.8, 0.5))
								
								if pagador == "igor" and valor_final > dados_economia_jogadores["igor"]["dinheiro"] / 2:
																var limite_pagamento = int(dados_economia_jogadores["igor"]["dinheiro"] / 2)
																var excedente = valor_final - limite_pagamento
																valor_final = limite_pagamento
																# --- BUG #12 FIX: Hedge Fund do Igor (GDD): paga 25% do excedente
																#     por 2 turnos = 50% total (perdoa 50%). Antes, o código pagava
																#     excedente/2 por turno por 2 turnos = 100% total (Igor pagava
																#     o dobro do que o GDD especifica). Agora armazenamos o excedente
																#     ORIGINAL em divida_original e pagamos 25% dele a cada turno. ---
																# --- BUG FIX (MED #9): Antes, a nova divida SOBRESCREVIA a antiga
																#     (divida_ativa = excedente, nao +=). Se Igor ja tinha divida ativa e
																#     caiu em outra propriedade cara, a divida anterior era perdida. Agora
																#     ACUMULAMOS: somamos o novo excedente a divida existente.
																var divida_anterior = dados_economia_jogadores["igor"].get("divida_ativa", 0)
																dados_economia_jogadores["igor"]["divida_ativa"] = divida_anterior + excedente
																dados_economia_jogadores["igor"]["divida_original"] = divida_anterior + excedente
																dados_economia_jogadores["igor"]["turnos_divida"] = 2
																dados_economia_jogadores["igor"]["credor_divida"] = recebedor
																if pinos_jogadores.has("igor"): pinos_jogadores["igor"].mostrar_texto_flutuante("HEDGE FUND ATIVO", Color(0.8, 0.8, 0.2))
								
								_registrar_obrigacao_falencia(pagador, recebedor, valor_final)
								dados_economia_jogadores[pagador]["dinheiro"] -= valor_final
								dados_economia_jogadores[recebedor]["dinheiro"] += valor_final
								
								# --- NOVO (Fase 3 — Alianças): Bônus de +10% no aluguel para o dono
								#     aliado, financiado pelo BANCO (não pelo pagador).
								#     Regra do GDD: "aliança concede +10% de aluguel nas propriedades do aliado".
								#     Interpretação correta: se A e B são aliados, e A cai numa propriedade
								#     de B, B recebe +10% extra (de bônus). O A paga só o valor normal.
								#     Os 10% extras vêm do banco (subsidio), não do bolso do pagador.
								#     Isso torna a aliança uma VANTAGEM real, não uma penalidade. ---
								if valor_final > 0 and _sao_aliados(pagador, recebedor):
																var bonus_alianca = max(1, int(valor_final * 0.10))  # CORREÇÃO: mínimo $1
																if bonus_alianca > 0:
																								dados_economia_jogadores[recebedor]["dinheiro"] += bonus_alianca
																								if pinos_jogadores.has(recebedor):
																																pinos_jogadores[recebedor].mostrar_texto_flutuante("BÔNUS ALIANÇA +$" + str(bonus_alianca), Color(0.95, 0.85, 0.15))
								
								# --- CORREÇÃO: Só mostra "-$X" / "+$X" se houve pagamento real.
								#     Se valor_final == 0 (imunidade ou vazamento), o feedback
								#     específico já foi dado acima — não mostramos "-$0" que
								#     ficaria confuso na tela. ---
								if valor_final > 0:
																if pinos_jogadores.has(pagador):
																								pinos_jogadores[pagador].mostrar_texto_flutuante("-$" + str(valor_final), Color(0.9, 0.3, 0.3))
																if pinos_jogadores.has(recebedor):
																								pinos_jogadores[recebedor].mostrar_texto_flutuante("+$" + str(valor_final), Color(0.3, 0.9, 0.3))
								
								# --- Animação de transferência de moedas do pagador ao recebedor ---
								if pinos_jogadores.has(pagador) and pinos_jogadores.has(recebedor) and valor_final > 0:
																Animacoes.transferencia_moedas(self, pinos_jogadores[pagador].position, pinos_jogadores[recebedor].position, Color(1, 0.85, 0.15), 8)
								
								_atualizar_hud_minha_casa()
								_atualizar_hud_ciclo_turno()
								var nome_pagador_hist = dados_economia_jogadores.get(pagador, {}).get("nome", pagador)
								var nome_recebedor_hist = dados_economia_jogadores.get(recebedor, {}).get("nome", recebedor)
								var nome_prop_hist = str(tabuleiro.get(casa_id, {}).get("nome", "propriedade")).replace("\n", " ")
								if valor_final > 0:
									_registrar_acao("aluguel", "%s pagou $%d a %s em %s." % [nome_pagador_hist, valor_final, nome_recebedor_hist, nome_prop_hist], pagador)
								else:
									_registrar_acao("aluguel", "%s teve aluguel zerado em %s." % [nome_pagador_hist, nome_prop_hist], pagador)
				
								# --- NOVO: Verifica falência após pagamento ---
								_verificar_falencia(pagador, recebedor)
								
								if OnlineTransport.is_host():
																_processar_passagem_de_turno()

@rpc("any_peer", "call_local")
func _efetuar_compra_rede(id_comprador: String, casa_id: int):
								var custo = _calcular_preco_compra(casa_id)
								dados_economia_jogadores[id_comprador]["dinheiro"] -= custo
								dados_economia_jogadores[id_comprador]["propriedades_compradas"] += 1
								dados_economia_jogadores[id_comprador]["propriedades_lista"].append(casa_id)
								registro_propriedades[casa_id] = id_comprador
								_registrar_aquisicao_propriedade(casa_id, id_comprador)
								_verificar_novos_monopolios_xp(id_comprador)
								var nome_comp_hist = dados_economia_jogadores.get(id_comprador, {}).get("nome", id_comprador)
								var nome_casa_comp_hist = str(tabuleiro.get(casa_id, {}).get("nome", "propriedade")).replace("\n", " ")
								_registrar_acao("compra", "%s comprou %s por $%d." % [nome_comp_hist, nome_casa_comp_hist, custo], id_comprador)
				
								if pinos_jogadores.has(id_comprador):
																pinos_jogadores[id_comprador].mostrar_texto_flutuante("-$" + str(custo), Color(0.9, 0.3, 0.3))
								
								_atualizar_visual_dono(casa_id)
								
								# --- NOVO: Animação de explosão de moedas na compra ---
								var pos_casa = tabuleiro[casa_id].get("pos", Vector2.ZERO)
								Animacoes.explosao_particulas(self, pos_casa, Color(1, 0.85, 0.15), 14, 80)
								Animacoes.flash_de_tela(hud.get_node("Control"), Color(0.95, 0.85, 0.15, 0.3), 0.3)
								
								# --- NOVO: Verifica se completou monopólio ---
								var grupo = tabuleiro[casa_id].get("grupo", "")
								if grupo not in ["Especial", "Utilidade", "Transporte", "Portal"]:
																if _tem_monopolio(id_comprador, grupo):
																								hud.mostrar_monopolio(grupo)
																								if pinos_jogadores.has(id_comprador):
																																pinos_jogadores[id_comprador].celebrar()
								
								_atualizar_hud_minha_casa()
								_atualizar_hud_ciclo_turno()
								_emitir_evento_tutorial(
																"propriedade_comprada",
																{
																	"jogador_id": id_comprador,
																	"casa_id": casa_id,
																	"custo": int(custo),
																}
								)
								
								# --- NOVO: Verifica falência após compra ---
								_verificar_falencia(id_comprador)
								
								if OnlineTransport.is_host():
																_processar_passagem_de_turno()

# ============================================================================
# SISTEMA DE CARTAS DE DESTINO E ORDEM URBANA
# ============================================================================
func _sacar_carta_no_servidor(nome_deck: String):
								var carta_sacada
								var is_destino = (nome_deck == "Destino da Cidade")

								if is_destino:
																if deck_destino_atual.is_empty():
																								_disparar_inflacao_global()
																								deck_destino_atual = deck_destino_base.duplicate()
																								deck_destino_atual.shuffle()
																carta_sacada = deck_destino_atual.pop_back()
								else:
																if deck_ordem_atual.is_empty():
																								_disparar_inflacao_global()
																								deck_ordem_atual = deck_ordem_base.duplicate()
																								deck_ordem_atual.shuffle()
																carta_sacada = deck_ordem_atual.pop_back()

								OnlineTransport.send_all(self, &"_aplicar_carta_rede", [jogador_atual_id, nome_deck, carta_sacada["nome"], carta_sacada["desc"], carta_sacada["tipo_efeito"], carta_sacada["valor"]], false, true)

func _disparar_inflacao_global():
								multiplicador_inflacao_global += 0.15
								OnlineTransport.send_all(self, &"_mostrar_alerta_meio_da_tela", ["INFLAÇÃO GALOPANTE!\nO Baralho reiniciou.\nTodos os aluguéis subiram +15% permanentemente!"], false, true)

func _aplicar_mudanca_carta(
	id_jogador: String,
	valor: int,
	credor_id: String = "",
	registrar_obrigacao: bool = true
) -> int:
	if valor == 0 or not dados_economia_jogadores.has(id_jogador):
		return 0
	# Cartas de Destino/Ordem não gastam a Imunidade Política. O uso acontece
	# somente na janela de decisão de um Evento Global negativo.
	if valor < 0 and registrar_obrigacao:
		_registrar_obrigacao_falencia(id_jogador, credor_id, abs(valor))
	dados_economia_jogadores[id_jogador]["dinheiro"] += valor
	if pinos_jogadores.has(id_jogador):
		var cor_txt = Color(0.3, 0.9, 0.3) if valor > 0 else Color(0.9, 0.3, 0.3)
		var sinal = "+$" if valor > 0 else "-$"
		pinos_jogadores[id_jogador].mostrar_texto_flutuante(sinal + str(abs(valor)), cor_txt)
	return valor

func _propriedades_do_jogador_para_carta(id_jogador: String, exigir_construcao: bool = false) -> Array:
	var resultado: Array = []
	for cid in registro_propriedades.keys():
		if registro_propriedades[cid] != id_jogador or not tabuleiro.has(cid):
			continue
		var grupo = tabuleiro[cid].get("grupo", "")
		if grupo in ["Especial", "Utilidade", "Transporte", "Portal"]:
			continue
		if exigir_construcao and int(tabuleiro[cid].get("nivel", 0)) <= 0:
			continue
		resultado.append(int(cid))
	resultado.sort()
	return resultado

func _indice_deterministico_carta(opcoes: Array, alvo_id: String, carta_nome: String) -> int:
	if opcoes.is_empty():
		return -1
	var base = rodada_atual + lista_turnos.find(alvo_id) + carta_nome.length()
	return posmod(base, opcoes.size())

func _conceder_propriedade_gratis_carta(alvo_id: String, carta_nome: String) -> int:
	var disponiveis: Array = []
	for cid in tabuleiro.keys():
		if registro_propriedades.has(cid):
			continue
		var dados_casa = tabuleiro[cid]
		if int(dados_casa.get("preco", 0)) <= 0:
			continue
		if dados_casa.get("tipo", "") not in ["propriedade", "utilidade", "transporte"]:
			continue
		disponiveis.append(int(cid))
	disponiveis.sort()
	var idx = _indice_deterministico_carta(disponiveis, alvo_id, carta_nome)
	if idx < 0:
		return -1
	var casa_id = int(disponiveis[idx])
	registro_propriedades[casa_id] = alvo_id
	_registrar_aquisicao_propriedade(casa_id, alvo_id)
	var dados_jogador = dados_economia_jogadores[alvo_id]
	dados_jogador["propriedades_compradas"] = int(dados_jogador.get("propriedades_compradas", 0)) + 1
	var lista_props: Array = dados_jogador.get("propriedades_lista", [])
	if not lista_props.has(casa_id):
		lista_props.append(casa_id)
	dados_jogador["propriedades_lista"] = lista_props
	_atualizar_visual_dono(casa_id)
	_verificar_novos_monopolios_xp(alvo_id)
	var grupo = tabuleiro[casa_id].get("grupo", "")
	if _tem_monopolio(alvo_id, grupo) and hud and hud.has_method("mostrar_monopolio"):
		hud.mostrar_monopolio(grupo)
	return casa_id

func _proximo_jogador_ativo(id_jogador: String) -> String:
	if lista_turnos.is_empty():
		return ""
	var inicio = lista_turnos.find(id_jogador)
	if inicio < 0:
		inicio = 0
	for deslocamento in range(1, lista_turnos.size() + 1):
		var candidato = lista_turnos[(inicio + deslocamento) % lista_turnos.size()]
		if candidato != id_jogador and not dados_economia_jogadores.get(candidato, {}).get("falido", false):
			return candidato
	return ""

func _propriedade_vizinha_da_posicao(posicao: int) -> int:
	# As cartas de Ordem Urbana ficam entre bairros. Procura primeiro a casa
	# imediatamente anterior e depois a seguinte, expandindo a distância apenas
	# se uma delas não for uma propriedade.
	var total_casas = tabuleiro.size()
	if total_casas <= 0:
		return -1
	for distancia in range(1, total_casas):
		for candidato_bruto in [posicao - distancia, posicao + distancia]:
			var candidato = posmod(candidato_bruto, total_casas)
			if tabuleiro.has(candidato) and tabuleiro[candidato].get("tipo", "") == "propriedade":
				return candidato
	return -1

func _grupo_bairro_vizinho_da_posicao(posicao: int) -> String:
	var propriedade = _propriedade_vizinha_da_posicao(posicao)
	if propriedade < 0:
		return ""
	return str(tabuleiro[propriedade].get("grupo", ""))

@rpc("any_peer", "call_local")
func _aplicar_carta_rede(alvo_id: String, nome_deck: String, carta_nome: String, carta_desc: String, tipo_efeito: String, valor: float):
	if not dados_economia_jogadores.has(alvo_id):
		return
	_resolucao_turno_em_andamento = true
	var meu_personagem_local = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
	if alvo_id == meu_personagem_local:
		hud.mostrar_carta_sorteada(nome_deck, carta_nome, carta_desc)
	else:
		var nome_jogador = dados_economia_jogadores[alvo_id].get("nome", alvo_id)
		_mostrar_alerta_meio_da_tela(nome_jogador.to_upper() + "\nESTÁ LENDO UMA CARTA...")

	# A animação da carta termina antes de alterar o estado econômico.
	await get_tree().create_timer(2.5).timeout
	var nome_carta_jogador = dados_economia_jogadores.get(alvo_id, {}).get("nome", alvo_id)
	_registrar_acao("carta", "%s sacou %s: %s." % [nome_carta_jogador, nome_deck, carta_nome], alvo_id)
	var p_dados = dados_economia_jogadores[alvo_id]
	var mudanca = 0
	var credores_falencia: Dictionary = {}

	match tipo_efeito:
		"ganha_dinheiro":
			mudanca = int(valor)
		"perde_dinheiro":
			mudanca = -int(valor)
		"perde_porcentagem_dinheiro":
			mudanca = -int(p_dados.get("dinheiro", 0) * valor)
		"auditoria_fiscal":
			mudanca = -max(50, int(p_dados.get("dinheiro", 0) * valor))
		"perde_por_propriedade":
			mudanca = -(int(p_dados.get("propriedades_compradas", 0)) * int(valor))
		"ganha_por_propriedade":
			mudanca = int(p_dados.get("propriedades_compradas", 0)) * int(valor)
		"perde_por_nivel", "ganha_por_nivel":
			var total_niveis = 0
			for cid in registro_propriedades.keys():
				if registro_propriedades[cid] == alvo_id:
					total_niveis += int(tabuleiro[cid].get("nivel", 0))
			mudanca = total_niveis * int(valor)
			if tipo_efeito == "perde_por_nivel":
				mudanca *= -1
		"ganha_se_tiver_casa":
			if not _propriedades_do_jogador_para_carta(alvo_id, true).is_empty():
				mudanca = int(valor)
		"perde_melhor_casa":
			var props: Array = _propriedades_do_jogador_para_carta(alvo_id, true)
			if props.is_empty() or _sabotagem_bloqueada_por_raizes(alvo_id, carta_nome):
				pass
			else:
				var melhor: int = -1
				for cid_variant in props:
					var cid: int = int(cid_variant)
					if melhor < 0 or int(tabuleiro[cid].get("nivel", 0)) > int(tabuleiro[melhor].get("nivel", 0)):
						melhor = cid
				if melhor >= 0:
					tabuleiro[melhor]["nivel"] = max(0, int(tabuleiro[melhor].get("nivel", 0)) - 1)
					_atualizar_imagem_construcao(melhor)
		"rouba_todos":
			var total_recebido = 0
			for pid in lista_turnos:
				if pid == alvo_id or dados_economia_jogadores.get(pid, {}).get("falido", false):
					continue
				var aplicado = _aplicar_mudanca_carta(pid, -int(valor), alvo_id)
				if aplicado < 0:
					credores_falencia[pid] = alvo_id
				total_recebido += abs(min(0, aplicado))
			_aplicar_mudanca_carta(alvo_id, total_recebido)
		"paga_todos":
			var receptores: Array = []
			for pid in lista_turnos:
				if pid != alvo_id and not dados_economia_jogadores.get(pid, {}).get("falido", false):
					receptores.append(pid)
			var total = int(valor) * receptores.size()
			for pid in receptores:
				_registrar_obrigacao_falencia(alvo_id, str(pid), int(valor))
			var aplicado = _aplicar_mudanca_carta(alvo_id, -total, "", false)
			if aplicado < 0:
				for pid in receptores:
					_aplicar_mudanca_carta(pid, int(valor))
		"move_frente", "move_tras":
			if OnlineTransport.is_host():
				var passos = int(valor) if tipo_efeito == "move_frente" else -int(valor)
				OnlineTransport.send_all(self, &"_sincronizar_movimento_na_rede", [alvo_id, passos], false, true)
			return
		"ganha_carta_sair_prisao":
			p_dados["cartas_sair_prisao"] = int(p_dados.get("cartas_sair_prisao", 0)) + 1
			if pinos_jogadores.has(alvo_id):
				pinos_jogadores[alvo_id].mostrar_texto_flutuante("CARTA GUARDADA: SAIR DA PRISÃO", Color(1.0, 0.84, 0.38))
		"valorizacao_surpresa":
			var props = _propriedades_do_jogador_para_carta(alvo_id)
			if not props.is_empty():
				var mais_barata = props[0]
				for cid in props:
					if int(tabuleiro[cid].get("preco", 0)) < int(tabuleiro[mais_barata].get("preco", 0)):
						mais_barata = cid
				_criar_efeito_unico("carta_valorizacao", "multiplicador_aluguel", 2, {"casa_id": mais_barata, "multiplicador": 2.0, "origem": "carta"}, true)
		"embargo_judicial":
			var props: Array = _propriedades_do_jogador_para_carta(alvo_id)
			if props.is_empty() or _sabotagem_bloqueada_por_raizes(alvo_id, carta_nome):
				pass
			else:
				var idx: int = _indice_deterministico_carta(props, alvo_id, carta_nome)
				if idx >= 0:
					_criar_efeito_unico("carta_embargo", "interdicao", 1, {"casa_id": props[idx], "origem": "carta"}, true)
		"despejo_judicial":
			var candidatas: Array = []
			var encontrou_construcao_kofi: bool = false
			for cid in registro_propriedades.keys():
				if registro_propriedades[cid] != alvo_id and int(tabuleiro[cid].get("nivel", 0)) > 0:
					var grupo = tabuleiro[cid].get("grupo", "")
					if grupo not in ["Especial", "Utilidade", "Transporte", "Portal"]:
						var dono_candidato: String = str(registro_propriedades[cid])
						if _e_imune_a_confisco(dono_candidato):
							encontrou_construcao_kofi = true
							continue
						candidatas.append(int(cid))
			candidatas.sort()
			var idx: int = _indice_deterministico_carta(candidatas, alvo_id, carta_nome)
			if idx >= 0:
				var cid_escolhida: int = int(candidatas[idx])
				tabuleiro[cid_escolhida]["nivel"] = max(0, int(tabuleiro[cid_escolhida].get("nivel", 0)) - 1)
				_atualizar_imagem_construcao(cid_escolhida)
			elif encontrou_construcao_kofi:
				_sabotagem_bloqueada_por_raizes("kofi", carta_nome)
		"premio_arquitetura":
			var props = _propriedades_do_jogador_para_carta(alvo_id, true)
			var mais_cara = -1
			var maior_investimento = -1
			for cid in props:
				var investimento = int(tabuleiro[cid].get("preco", 0)) * int(tabuleiro[cid].get("nivel", 0))
				if investimento > maior_investimento:
					maior_investimento = investimento
					mais_cara = cid
			if mais_cara >= 0:
				_criar_efeito_unico("carta_premio", "multiplicador_aluguel", 1, {"casa_id": mais_cara, "multiplicador": 1.5, "origem": "carta"}, true)
		"incendio_galpao":
			var candidatas: Array = []
			for cid in _propriedades_do_jogador_para_carta(alvo_id, true):
				if tabuleiro[cid].get("grupo", "") in ["Cinza", "Marrom"]:
					candidatas.append(cid)
			if candidatas.is_empty() or _sabotagem_bloqueada_por_raizes(alvo_id, carta_nome):
				pass
			else:
				var idx: int = _indice_deterministico_carta(candidatas, alvo_id, carta_nome)
				if idx >= 0:
					var cid_escolhida: int = int(candidatas[idx])
					tabuleiro[cid_escolhida]["nivel"] = max(0, int(tabuleiro[cid_escolhida].get("nivel", 0)) - 1)
					_atualizar_imagem_construcao(cid_escolhida)
		"novo_parque":
			var posicao_carta = int(pinos_jogadores[alvo_id].casa_atual) if pinos_jogadores.has(alvo_id) else -1
			var propriedade_vizinha = _propriedade_vizinha_da_posicao(posicao_carta)
			if propriedade_vizinha >= 0:
				_criar_efeito_unico("carta_parque", "multiplicador_aluguel", 3, {"casa_id": propriedade_vizinha, "multiplicador": 1.2, "origem": "carta"}, true)
		"bloqueio_trafego":
			_ativar_efeito_temporario("carta_bloqueio_trafego", "bloqueio_portal", 1, {"origem": "carta"}, true)
		"acao_coletiva":
			_criar_efeito_unico("carta_acao_coletiva", "multiplicador_aluguel", 1, {"nivel": 5, "multiplicador": 0.5, "origem": "carta"}, true)
		"vazamento_oleo_condicional":
			if _jogador_possui_nome(alvo_id, "Portuária"):
				mudanca = -int(valor)
		"heranca_propriedade":
			var casa_recebida = _conceder_propriedade_gratis_carta(alvo_id, carta_nome)
			if casa_recebida >= 0 and pinos_jogadores.has(alvo_id):
				pinos_jogadores[alvo_id].mostrar_texto_flutuante("HERANÇA: " + str(tabuleiro[casa_recebida].get("nome", "PROPRIEDADE")).replace("\n", " "), Color(0.4, 1.0, 0.4))
		"revelar_saldo":
			_criar_efeito_unico("carta_saldo_publico", "saldo_revelado", 2, {"jogador_id": alvo_id, "origem": "carta"}, true)
			_mostrar_alerta_meio_da_tela("INVESTIGAÇÃO PATRIMONIAL\n" + str(p_dados.get("nome", alvo_id)).to_upper() + " possui $" + str(p_dados.get("dinheiro", 0)) + " em caixa.")
		"festa_rua":
			var grupo_bairro = ""
			if pinos_jogadores.has(alvo_id):
				grupo_bairro = _grupo_bairro_vizinho_da_posicao(int(pinos_jogadores[alvo_id].casa_atual))
			for pid in lista_turnos:
				if dados_economia_jogadores.get(pid, {}).get("falido", false) or not pinos_jogadores.has(pid):
					continue
				var cid = int(pinos_jogadores[pid].casa_atual)
				if grupo_bairro != "" and str(tabuleiro.get(cid, {}).get("grupo", "")) == grupo_bairro:
					_aplicar_mudanca_carta(pid, int(valor))
		"barulho_esquerda":
			var esquerda = _proximo_jogador_ativo(alvo_id)
			if esquerda != "":
				var aplicado_barulho = _aplicar_mudanca_carta(
					esquerda,
					-int(valor),
					alvo_id
				)
				if aplicado_barulho < 0:
					credores_falencia[esquerda] = alvo_id
		"inspecao_hoteis":
			var total_hoteis = 0
			for cid in _propriedades_do_jogador_para_carta(alvo_id):
				if int(tabuleiro[cid].get("nivel", 0)) >= 5:
					total_hoteis += 1
			if total_hoteis > 2:
				mudanca = -int(valor)
		"subsidio_casa_gratis":
			p_dados["cartas_construcao_gratis"] = int(p_dados.get("cartas_construcao_gratis", 0)) + 1
			if pinos_jogadores.has(alvo_id):
				pinos_jogadores[alvo_id].mostrar_texto_flutuante("CARTA GUARDADA: CONSTRUÇÃO GRÁTIS", Color(0.48, 1.0, 0.58))

	if mudanca != 0:
		_aplicar_mudanca_carta(alvo_id, mudanca)
	_atualizar_hud_ciclo_turno()
	for pid in lista_turnos.duplicate():
		_verificar_falencia(pid, str(credores_falencia.get(pid, "")))
	if OnlineTransport.is_host():
		await get_tree().create_timer(3.0).timeout
		_processar_passagem_de_turno()


# ============================================================================
# MOTOR DE LEILÃO
# ============================================================================
@rpc("any_peer", "call_local")
func _iniciar_leilao_rede(id_casa: int, lance_minimo: int = 0, contexto: String = "normal"):
								_resolucao_turno_em_andamento = true
								casa_em_leilao = id_casa
								lances_leilao_atuais.clear()
								leilao_em_andamento = true
								_leilao_lance_minimo_atual = max(0, lance_minimo)
								_leilao_contexto_atual = contexto

								var dados_casa = tabuleiro[id_casa]
								hud.abrir_janela_leilao(dados_casa["nome"], _leilao_lance_minimo_atual)
								if hud.has_method("iniciar_barra_leilao"):
																hud.iniciar_barra_leilao(25)

								# --- CORREÇÃO DO LEILÃO: Cada peer tem 25s para enviar seu lance.
								#     Se o tempo acabar e o jogador não deu lance, envia $0 (passou).
								#     O server recebe todos os lances e finaliza.
								#     Usa um ID único por leilão para invalidar timers antigos.
								#     Jogadores FALIDOS não participam do leilão. ---
								_leilao_counter += 1
								var meu_leilao_id = _leilao_counter
								_lance_local_leilao = -1  # -1 = ainda não deu lance
								_leilao_timeout = false

								# Verifica se o jogador local está falido
								var meu_personagem_leilao = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
								var jogador_local_falido = false
								if meu_personagem_leilao != "" and dados_economia_jogadores.has(meu_personagem_leilao):
																if dados_economia_jogadores[meu_personagem_leilao].get("falido", false):
																								jogador_local_falido = true
																								# Não abre a janela de leilão para o falido
																								hud.fechar_janela_leilao()
																								if hud.has_method("parar_barra_leilao"):
																																hud.parar_barra_leilao()

								if not jogador_local_falido:
																var timer = get_tree().create_timer(25.0)
																timer.timeout.connect(_on_leilao_timeout_local)

																# Conecta o signal do lance para capturar o valor
																if not hud.lance_leilao_enviado.is_connected(_on_lance_local_recebido):
																										hud.lance_leilao_enviado.connect(_on_lance_local_recebido)
																# Espera até que o lance seja recebido OU o timeout dispare
																while _lance_local_leilao == -1 and not _leilao_timeout:
																										await get_tree().create_timer(0.1).timeout
																if timer.timeout.is_connected(_on_leilao_timeout_local):
																										timer.timeout.disconnect(_on_leilao_timeout_local)
																if hud.lance_leilao_enviado.is_connected(_on_lance_local_recebido):
																										hud.lance_leilao_enviado.disconnect(_on_lance_local_recebido)

																# Se timeout e sem lance, usa $0
																if _lance_local_leilao == -1:
																										_lance_local_leilao = 0
																# Envia o lance (ou $0) para o server
																if meu_personagem_leilao != "":
																										if OnlineTransport.is_host():
																											_receber_lance_no_servidor(meu_personagem_leilao, _lance_local_leilao)
																										else:
																											OnlineTransport.send_host(self, &"_receber_lance_no_servidor", [meu_personagem_leilao, _lance_local_leilao], false)
								else:
																# --- CORRECAO CRITICA: Jogadores FALIDOS nao participam do leilao.
																#     Antes, o falido enviava $0 automaticamente para o server.
																#     O server contava esse $0 como um lance valido, fazendo o
																#     leilao fechar antes de todos os jogadores ATIVOS enviarem
																#     seus lances. Resultado: o primeiro a dar lance ganhava a
																#     propriedade sem os outros poderem ofertar.
																#     Agora o falido simplesmente NAO ENVIA lance - o server
																#     so conta lances de jogadores nao-falidos. ---
																pass

								# --- Apenas o server faz o timeout final e garante que o leilão fecha.
								#     Usa o ID do leilão para garantir que só finaliza se for o MESMO leilão
								#     (timers de leilões anteriores não interferem nos novos). ---
								if OnlineTransport.is_host():
																await get_tree().create_timer(27.0).timeout
																if leilao_em_andamento and _leilao_counter == meu_leilao_id:
																								if lances_leilao_atuais.is_empty():
																																OnlineTransport.send_all(self, &"_finalizar_leilao_rede", ["Nenhum", 0, casa_em_leilao], true, true)
																								else:
																																_calcular_vencedor_leilao()

# --- NOVO: Variáveis de estado do leilão local ---
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
func _on_leilao_timeout_local():
								_leilao_timeout = true
								# Se o jogador ainda não deu lance, marca como $0
								if _lance_local_leilao == -1:
																_lance_local_leilao = 0

# --- NOVO: Handler local do sinal de lance (captura o valor) ---
func _on_lance_local_recebido(valor: int):
								if _eleicao_bloqueando_acoes:
																return
								_lance_local_leilao = valor

@rpc("any_peer", "call_local")
func _receber_lance_no_servidor(id_jogador: String, valor: int):
								if _eleicao_bloqueando_acoes:
																return
								if not OnlineTransport.is_host() or not leilao_em_andamento: return

								# O servidor associa o RPC ao personagem do peer remetente. Isso impede
								# que um cliente envie um lance em nome de outro jogador.
								var peer_remetente = OnlineTransport.get_remote_sender_id()
								if peer_remetente <= 0:
									peer_remetente = OnlineTransport.local_player_id()
								var personagem_remetente = str(Global.escolhas_da_mesa.get(peer_remetente, ""))
								if personagem_remetente == "" or personagem_remetente != id_jogador:
									return
								# Cada participante envia apenas um lance por leilão.
								if lances_leilao_atuais.has(id_jogador):
									return
								
								# --- CORRECAO CRITICA: Rejeita lances de jogadores FALIDOS.
								#     Mesmo que o cliente do falido envie um lance (por bug ou race condition),
								#     o server NAO deve conta-lo. Antes, o lance $0 do falido era contado,
								#     fazendo o leilao fechar antes de todos os jogadores ATIVOS enviarem
								#     seus lances - o primeiro a dar lance ganhava a propriedade sem os
								#     outros poderem ofertar. ---
								if dados_economia_jogadores.has(id_jogador) and dados_economia_jogadores[id_jogador].get("falido", false):
																return
								
								# Validação autoritativa: lances negativos, acima do saldo ou abaixo
								# do mínimo especial contam como passe ($0).
								valor = max(0, valor)
								var saldo = int(dados_economia_jogadores.get(id_jogador, {}).get("dinheiro", 0))
								if valor > saldo or (valor > 0 and valor < _leilao_lance_minimo_atual):
																valor = 0
								lances_leilao_atuais[id_jogador] = valor
								
								# --- CORREÇÃO: Conta apenas jogadores NÃO falidos (jogadores ativos).
								#     Antes usava Global.escolhas_da_mesa.size() que inclui falidos.
								#     Com 2 jogadores onde 1 faliu, o leilão esperava 2 lances mas só
								#     recebia 1 (o falido não joga) — ficava preso para sempre. ---
								var jogadores_ativos = 0
								for peer_id in Global.escolhas_da_mesa.keys():
																var p_id = Global.escolhas_da_mesa[peer_id]
																if dados_economia_jogadores.has(p_id) and not dados_economia_jogadores[p_id].get("falido", false):
																								jogadores_ativos += 1
								if lances_leilao_atuais.size() >= jogadores_ativos:
																_calcular_vencedor_leilao()

func _calcular_vencedor_leilao():
								var vencedor = ""
								var maior_lance = -1
								var empate = false
								
								for jogador in lances_leilao_atuais:
																var lance = lances_leilao_atuais[jogador]
																if lance > maior_lance:
																								maior_lance = lance
																								vencedor = jogador
																								empate = false
																elif lance == maior_lance and lance > 0:
																								empate = true
																								
								if empate and lances_leilao_atuais.has("yasmin") and lances_leilao_atuais["yasmin"] == maior_lance:
																vencedor = "yasmin"
																
								if vencedor != "" and maior_lance > 0:
																var valor_final = maior_lance
																if vencedor == "yasmin": valor_final = max(1, int(maior_lance * 0.95))  # CORREÇÃO: mínimo $1
																valor_final = max(1, int(round(valor_final * _multiplicador_preco_leilao())))
																OnlineTransport.send_all(self, &"_finalizar_leilao_rede", [vencedor, valor_final, casa_em_leilao], true, true)
								else:
																OnlineTransport.send_all(self, &"_finalizar_leilao_rede", ["Nenhum", 0, casa_em_leilao], true, true)

@rpc("authority", "call_local")
func _finalizar_leilao_rede(id_vencedor: String, valor_pago: int, casa_id: int):
								leilao_em_andamento = false
								hud.fechar_janela_leilao()
								# --- NOVO (GDD §5.3): Para a barra de timer do leilão. ---
								if hud.has_method("parar_barra_leilao"):
																hud.parar_barra_leilao()
								
								if id_vencedor != "Nenhum":
																dados_economia_jogadores[id_vencedor]["dinheiro"] -= valor_pago
																dados_economia_jogadores[id_vencedor]["propriedades_compradas"] += 1
																# --- CORREÇÃO: Registra a propriedade na lista do jogador,
																#     igual à função de compra direta. Sem isso, o painel
																#     "Suas Propriedades" (que itera sobre propriedades_lista)
																#     não mostra a casa arrematada em leilão. ---
																dados_economia_jogadores[id_vencedor]["propriedades_lista"].append(casa_id)
																registro_propriedades[casa_id] = id_vencedor
																_registrar_aquisicao_propriedade(casa_id, id_vencedor)
																_verificar_novos_monopolios_xp(id_vencedor)
																
																if pinos_jogadores.has(id_vencedor):
																								pinos_jogadores[id_vencedor].mostrar_texto_flutuante("-$" + str(valor_pago), Color(0.9, 0.3, 0.3))
																								
																_atualizar_visual_dono(casa_id)
																
																# --- CORREÇÃO: Animação de explosão de moedas na compra por leilão,
																#     igual à compra direta, para feedback visual consistente. ---
																var pos_casa = tabuleiro[casa_id].get("pos", Vector2.ZERO)
																Animacoes.explosao_particulas(self, pos_casa, Color(1, 0.85, 0.15), 14, 80)
																Animacoes.flash_de_tela(hud.get_node("Control"), Color(0.95, 0.85, 0.15, 0.3), 0.3)
																
																# --- CORREÇÃO: Verifica se o leilão completou um monopólio.
																#     Antes a compra em leilão nunca disparava o banner de
																#     MONOPÓLIO nem a animação de celebração do pino. ---
																var grupo_leilao = tabuleiro[casa_id].get("grupo", "")
																if grupo_leilao not in ["Especial", "Utilidade", "Transporte", "Portal"]:
																								if _tem_monopolio(id_vencedor, grupo_leilao):
																																hud.mostrar_monopolio(grupo_leilao)
																																if pinos_jogadores.has(id_vencedor):
																																								pinos_jogadores[id_vencedor].celebrar()
								
								_atualizar_hud_minha_casa()
								_atualizar_hud_ciclo_turno()
								
								# --- CORREÇÃO: Verifica falência do vencedor caso o lance tenha
								#     comprometido todo o seu saldo. ---
								if id_vencedor != "Nenhum":
																_verificar_falencia(id_vencedor)
								
								# --- NOVO (GDD §9.1): Se for leilão de falência, NÃO passa o turno.
								#     Em vez disso, o server inicia o próximo leilão da fila. ---
								if _leilao_falencia_ativo:
																if OnlineTransport.is_host():
																																await get_tree().create_timer(2.0).timeout
																																if not _abutre_bloqueando_acoes and not _processando_resolucoes_abutre:
																																	OnlineTransport.send_all(self, &"_iniciar_proximo_leilao_falencia", [], true, true)
								elif _leilao_evento_ativo:
																if OnlineTransport.is_host():
																																await get_tree().create_timer(1.4).timeout
																																OnlineTransport.send_all(self, &"_iniciar_proximo_leilao_evento_rede", [], true, true)
								else:
																if OnlineTransport.is_host():
																																_processar_passagem_de_turno()


func _finalizar_pouso_e_passar_turno():
								# --- NOVO (GDD §5.2): Se o jogador tirou dupla, não passa o turno.
								#     Em vez disso, permite que ele role novamente. ---
								if _dupla_pendente:
																_dupla_pendente = false
																_processando_dados = false
																_verificar_permissao_de_clique()
																if pinos_jogadores.has(jogador_atual_id):
																								pinos_jogadores[jogador_atual_id].mostrar_texto_flutuante("DUPLA! ROLE NOVAMENTE!", Color(0.4, 1.0, 0.4))
																return
								if OnlineTransport.is_host():
																_processar_passagem_de_turno()

# --- NOVO (GDD §5.2): RPC para sincronizar o status de dupla entre todos os peers.
#     _on_dados_rolados_recebidos roda localmente; este RPC propaga o status
#     para que _finalizar_pouso_e_passar_turno (que roda em todos os peers via
#     _sincronizar_movimento_na_rede) possa tomar a decisão correta. ---
@rpc("any_peer", "call_local")
func _set_dupla_status_rede(jogador_id: String, is_dupla: bool, duplas_count: int):
								if jogador_id == jogador_atual_id:
																dados_economia_jogadores[jogador_id]["duplas_consecutivas"] = duplas_count
																_dupla_pendente = is_dupla

func _executar_portal_atalho(casa_id: int):
								# --- NOVO (Cartas): Bloqueio de Tráfego — portais bloqueados ---
								if not _efeitos_ativos_por_tipo("bloqueio_portal").is_empty():
												if pinos_jogadores.has(jogador_atual_id):
																pinos_jogadores[jogador_atual_id].mostrar_texto_flutuante("TRÁFEGO BLOQUEADO!", Color(0.9, 0.5, 0.2))
												_finalizar_pouso_e_passar_turno()
												return
								var destino = 28 if casa_id == 12 else 12
								var pino = pinos_jogadores[jogador_atual_id]

								# --- CORREÇÃO: Teleporte INSTANTÂNEO em vez de pular 16 casas ---
								# Remove o pino da casa atual
								_remover_pino_da_casa(pino, pino.casa_atual)

								# Animação: pino "entra" no portal (encolhe e some)
								var tween_entra = pino.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
								tween_entra.parallel().tween_property(pino.visual_node, "scale", Vector2(0.1, 0.1), 0.3)
								tween_entra.parallel().tween_property(pino, "modulate:a", 0.0, 0.3)

								# Efeito visual no portal de origem
								var pos_origem = tabuleiro[casa_id].get("pos", Vector2.ZERO)
								Animacoes.explosao_particulas(self, pos_origem, Color(0.1, 0.8, 0.9), 12, 60)

								# Texto flutuante explicando o teleporte
								pino.mostrar_texto_flutuante("PORTAL! " + str(casa_id) + " → " + str(destino), Color(0.1, 0.8, 0.9))

								await tween_entra.finished

								# Teleporta instantaneamente para o destino
								pino.casa_atual = destino
								pino.position = tabuleiro[destino]["pos"]
								_adicionar_pino_na_casa(pino, destino)

								# Efeito visual no portal de destino
								var pos_destino = tabuleiro[destino].get("pos", Vector2.ZERO)
								Animacoes.explosao_particulas(self, pos_destino, Color(0.1, 0.8, 0.9), 12, 60)

								# Animação: pino "sai" do portal (expandir e aparecer)
								pino.visual_node.scale = Vector2(0.1, 0.1)
								pino.modulate.a = 0.0
								var tween_sai = pino.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
								tween_sai.parallel().tween_property(pino.visual_node, "scale", Vector2(1.0, 1.0), 0.4)
								tween_sai.parallel().tween_property(pino, "modulate:a", 1.0, 0.3)

								await tween_sai.finished

								var meu_personagem_local = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
								if jogador_atual_id == meu_personagem_local:
																await focar_na_casa(destino)

								_finalizar_pouso_e_passar_turno()

# ============================================================================
# LÓGICA MULTIPLAYER DE MOVIMENTO E TURNOS
# ============================================================================
@rpc("any_peer", "call_local")
func _sincronizar_movimento_na_rede(id_do_personagem: String, passos: int):
								if not pinos_jogadores.has(id_do_personagem): return
								_resolucao_turno_em_andamento = true
								
								var pino = pinos_jogadores[id_do_personagem]
								var casa_antiga = pino.casa_atual
								
								var meu_personagem_local = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
								
								# Liga o seguimento antes da animação. Jogadores ativos seguem o próprio
								# pino; espectadores seguem o turno automaticamente ou o alvo manual.
								var deve_seguir_movimento: bool = (
									id_do_personagem == meu_personagem_local
									or (Global.modo_tutorial and _eh_jogador_bot(id_do_personagem))
								)
								if modo_espectador_local:
									deve_seguir_movimento = (espectador_auto_seguir and id_do_personagem == jogador_atual_id) or (not espectador_auto_seguir and id_do_personagem == espectador_alvo_id)
								if deve_seguir_movimento:
									pino_seguido = pino
									seguindo_pino = true
								
								# --- NOVO: se passos for negativo (carta move_tras), usa mover_casas_tras ---
								if passos > 0:
																await pino.mover_casas(passos, tabuleiro, self)
								else:
																await pino.mover_casas_tras(-passos, tabuleiro, self)
								var casa_nova = pino.casa_atual
								
								if casa_nova < casa_antiga and passos > 0:

								
																var bonus = _calcular_bonus_partida(id_do_personagem)
																								
																dados_economia_jogadores[id_do_personagem]["dinheiro"] += bonus
																pino.mostrar_texto_flutuante("+$" + str(bonus), Color(0.3, 0.9, 0.3))
																_atualizar_hud_ciclo_turno()
								
								# Após animação, centraliza no destino. Em modo espectador o seguimento
								# permanece ativo para acompanhar o alvo também quando ele está parado.
								if deve_seguir_movimento:
									if not modo_espectador_local:
										seguindo_pino = false
										pino_seguido = null
									await focar_na_casa(pino.casa_atual)
									if modo_espectador_local:
										pino_seguido = pino
										seguindo_pino = true

								var nome_mov = dados_economia_jogadores.get(id_do_personagem, {}).get("nome", id_do_personagem)
								var nome_casa_mov = str(tabuleiro.get(pino.casa_atual, {}).get("nome", "casa " + str(pino.casa_atual))).replace("\n", " ")
								_registrar_acao("movimento", "%s moveu %d casa(s) e parou em %s." % [nome_mov, passos, nome_casa_mov], id_do_personagem)
								_processar_terreno_pousado(pino.casa_atual)

func _processar_passagem_de_turno():
								if OnlineTransport.is_host():
																_resolucao_turno_em_andamento = true
								# A Fase de Evento precisa terminar antes que o turno avance.
								if _acoes_bloqueadas_por_evento():
																return
								# --- CORREÇÃO CRÍTICA: Se há leilão de falência em andamento (ou agendado),
								#     NÃO passa o turno. O leilão de falência chama _verificar_vitoria() ou
								#     _verificar_permissao_de_clique() quando termina.
								#     Antes, o turno era avançado durante o leilão de falência, fazendo:
								#     1) O índice do turno avançar 2x (uma pelo _pagar_aluguel_rede que
								#        disparou a falência, outra pelo próprio leilão) — pulando o
								#        próximo jogador.
								#     2) Os dados aparecerem para o jogador errado, ou em alguns casos
								#        travarem completamente (dados não aparecem mais para ninguém).
								#     Isso explica o bug onde, após um jogador falir, os dados sumiam
								#     para os jogadores restantes algumas rodadas depois. ---
								if _leilao_falencia_ativo:
																return
								await get_tree().create_timer(1.5).timeout
								# Checa novamente após o await (o leilão pode ter iniciado durante a espera)
								if _leilao_falencia_ativo:
																return
								OnlineTransport.send_all(self, &"_avancar_turno_rede", [], true, true)

@rpc("authority", "call_local")
func _avancar_turno_rede():
								# Segurança: nenhum RPC ou atalho pode avançar a rodada durante a votação.
								if _acoes_bloqueadas_por_evento():
																return
								indice_turno_atual = (indice_turno_atual + 1) % lista_turnos.size()
								jogador_atual_id = lista_turnos[indice_turno_atual]
								_contador_turnos_globais += 1
								_processar_promessas_ao_avancar_turno()
								_atualizar_alvo_camera_espectador()

								# Atualiza o relógio central antes de iniciar as ações do novo jogador.
								_decrementar_efeitos_temporarios()
								_processar_efeitos_periodicos_do_turno(jogador_atual_id)

								# --- BUG FIX (LOW #9): Reset do Acordo de Silêncio a cada novo turno.
								#     A flag acordo_silencio_ativo é setada quando alguém cai na casa 22
								#     e deve durar apenas aquele turno. Como _avancar_turno_rede é
								#     chamado quando o turno passa, resetamos aqui. ---
								acordo_silencio_ativo = false
								# Zona de Obras bloqueia somente o jogador que caiu nela, até esta troca.
								turno_construcao_bloqueada = false
								# --- NOVO (Ilha de Calor): Decrementa interdição ---
								if _ilha_calor_interditacao_turnos > 0:
												_ilha_calor_interditacao_turnos -= 1
												if _ilha_calor_interditacao_turnos <= 0:
																_ilha_calor_prop_interditada = -1
								# --- NOVO (Escândalo de Corrupção): Decrementa embargo ---
								if _corrupcao_embargo_turnos > 0:
												_corrupcao_embargo_turnos -= 1
												if _corrupcao_embargo_turnos <= 0:
																_corrupcao_props_embargadas.clear()
								# --- NOVO (Cartas): Decrementa efeitos temporários ---
								if _carta_valorizacao_turnos > 0:
												_carta_valorizacao_turnos -= 1
												if _carta_valorizacao_turnos <= 0:
																_carta_valorizacao_casa = -1
								if _carta_embargo_judicial_turnos > 0:
												_carta_embargo_judicial_turnos -= 1
												if _carta_embargo_judicial_turnos <= 0:
																_carta_embargo_judicial_casa = -1
								if _carta_parque_turnos > 0:
												_carta_parque_turnos -= 1
												if _carta_parque_turnos <= 0:
																_carta_parque_casa = -1
								if _carta_bloqueio_trafego:
												_carta_bloqueio_trafego = false
								if _carta_premio_turnos > 0:
												_carta_premio_turnos -= 1
												if _carta_premio_turnos <= 0:
																_carta_premio_casa = -1
								if _carta_acao_coletiva_ativa:
												_carta_acao_coletiva_ativa = false
								# --- NOVO (Protestos): Decrementa bloqueio de hotel ---
								if _protestos_bloqueio_turnos > 0:
												_protestos_bloqueio_turnos -= 1
												if _protestos_bloqueio_turnos <= 0:
																_protestos_bloqueio_hotel = false

								# --- NOVO (GDD §5.2): Reset duplas_consecutivas do novo jogador
								#     (cada turno começa com contador zerado — só acumula dentro
								#     do mesmo turno quando o jogador tira dupla e rola novamente). ---
								var dados_novo = dados_economia_jogadores.get(jogador_atual_id)
								if dados_novo:
																dados_novo["duplas_consecutivas"] = 0
								# --- BUG FIX (HIGH #19 + MED #27/#28):
								#     HIGH #19: Antes, a recarga de habilidade era decrementada
								#     APENAS para o novo jogador atual. Resultado: "recarga 4 turnos"
								#     significava 4 voltas completas do jogador (até 24 turnos reais
								#     em partida de 6). Agora decrementa a recarga de TODOS os
								#     jogadores a cada turno — "4 turnos" = 4 turnos reais.
								#     MED #27/#28: hud.habilidade_pronta_aviso() era chamado em
								#     TODOS os peers (porque _avancar_turno_rede é call_local).
								#     Agora só pulsa o botão no peer do jogador cuja habilidade
								#     ficou pronta. ---
								for jid_recarga in lista_turnos:
																var dados_rec = dados_economia_jogadores.get(jid_recarga)
																if dados_rec and dados_rec.get("recarga_hab", 0) > 0:
																								dados_rec["recarga_hab"] -= 1
																								if dados_rec["recarga_hab"] == 0:
																																if pinos_jogadores.has(jid_recarga):
																																								pinos_jogadores[jid_recarga].mostrar_texto_flutuante("HABILIDADE PRONTA!", Color(0.4, 1.0, 0.4))
																																# Só pulsa o botão de habilidade no peer do jogador local
																																if jid_recarga == Global.escolhas_da_mesa.get(Global.meu_peer_id, ""):
																																								hud.habilidade_pronta_aviso()
								# Decrementa Breno's Decreto Emergencial (do novo jogador atual)
								if dados_novo and dados_novo.get("decreto_turnos", 0) > 0:
																dados_novo["decreto_turnos"] -= 1
																if dados_novo["decreto_turnos"] == 0:
																								dados_novo.erase("decreto_grupo")
								# Decrementa Igor's Especulação (do novo jogador atual)
								if dados_novo and dados_novo.get("especulacao_turnos", 0) > 0:
																dados_novo["especulacao_turnos"] -= 1
																if dados_novo["especulacao_turnos"] == 0:
																								dados_novo.erase("especulacao_casa")

								# --- NOVO (Fase 2 — Imunidades): decrementa turnos_restantes de
								#     TODAS as imunidades de TODOS os jogadores. Isso garante que
								#     "imunidade expira por turnos" funcione independentemente de
								#     quem é o jogador atual. Após decrementar, remove imunidades
								#     expiradas (turnos_restantes == 0).
								#     OBS: visitas_restantes só é decrementado quando a imunidade
								#     é realmente usada em _pagar_aluguel_rede; aqui só cuidamos
								#     do prazo por turnos. ---
								for jid in lista_turnos:
																var imunidades = dados_economia_jogadores[jid].get("imunidades", [])
																if imunidades.is_empty():
																								continue
																# Decrementa turnos_restantes de cada imunidade
																for imun in imunidades:
																								if imun.get("turnos_restantes", 0) > 0:
																																imun["turnos_restantes"] = imun["turnos_restantes"] - 1
																# Remove as que expiraram por turnos (e também por visitas,
																# caso visitas_restantes tenha chegado a 0 em _pagar_aluguel_rede
																# mas a entrada ainda não foi removida — cenário raro)
																var imunidades_validas: Array = []
																for imun in imunidades:
																								if imun.get("turnos_restantes", 0) > 0 and imun.get("visitas_restantes", 0) > 0:
																																imunidades_validas.append(imun)
																								else:
																																# Feedback visual de expiração (só se o jogador afetado for o local)
																																if jid == Global.escolhas_da_mesa.get(Global.meu_peer_id, "") and pinos_jogadores.has(jid):
																																								pinos_jogadores[jid].mostrar_texto_flutuante("IMUNIDADE EXPIROU", Color(0.8, 0.6, 0.3))
																dados_economia_jogadores[jid]["imunidades"] = imunidades_validas

								# --- NOVO (Fase 3 — Alianças): decrementa turnos_restantes de
								#     TODAS as alianças de TODOS os jogadores. Mesma lógica das
								#     imunidades: roda para todos os jogadores independentemente
								#     de quem é o jogador atual, pois alianças expiram por turnos
								#     globais. Remove as que expiraram (turnos_restantes == 0). ---
								for jid_al in lista_turnos:
																var aliancas = dados_economia_jogadores[jid_al].get("aliancas", [])
																if aliancas.is_empty():
																								continue
																# Decrementa turnos_restantes de cada aliança
																for alianca in aliancas:
																								if alianca.get("turnos_restantes", 0) > 0:
																																alianca["turnos_restantes"] = alianca["turnos_restantes"] - 1
																# Remove as que expiraram
																var aliancas_validas: Array = []
																for alianca in aliancas:
																								if alianca.get("turnos_restantes", 0) > 0:
																																aliancas_validas.append(alianca)
																								else:
																																# Feedback visual de expiração (só se o jogador afetado for o local)
																																if jid_al == Global.escolhas_da_mesa.get(Global.meu_peer_id, "") and pinos_jogadores.has(jid_al):
																																								pinos_jogadores[jid_al].mostrar_texto_flutuante("ALIANÇA EXPIROU", Color(0.8, 0.6, 0.3))
																dados_economia_jogadores[jid_al]["aliancas"] = aliancas_validas

								var igor_dados = dados_economia_jogadores.get("igor")
								if jogador_atual_id == "igor" and igor_dados and igor_dados.get("turnos_divida", 0) > 0:
																# --- BUG #12 FIX: Hedge Fund paga 25% do excedente ORIGINAL por
																#     turno, por 2 turnos (50% total). O restante é PERDOADO.
																#     Antes, pagava excedente/2 por turno = 100% total. ---
																var divida_orig = int(igor_dados.get("divida_original", igor_dados["divida_ativa"]))
																var parcela = int(divida_orig * 0.25)
																# --- BUG FIX (MED #11): Antes, no último turno (turnos_divida == 1),
																#     pagava 50% da divida_ativa — que já havia sido reduzida pela
																#     parcela do turno anterior. Resultado: Igor pagava ~62% do
																#     excedente em vez de 50%. Agora SEMPRE paga 25% do divida_original
																#     (constante), e no último turno perdoa o restante. ---
																var credor = igor_dados["credor_divida"]

																_registrar_obrigacao_falencia("igor", str(credor), parcela)
																igor_dados["dinheiro"] -= parcela
																if dados_economia_jogadores.has(credor):
																								dados_economia_jogadores[credor]["dinheiro"] += parcela

																if pinos_jogadores.has("igor"): pinos_jogadores["igor"].mostrar_texto_flutuante("-$" + str(parcela) + " (Dívida Hedge)", Color(0.9, 0.5, 0.3))
																if pinos_jogadores.has(credor): pinos_jogadores[credor].mostrar_texto_flutuante("+$" + str(parcela) + " (Dívida Hedge)", Color(0.5, 0.9, 0.3))

																igor_dados["divida_ativa"] -= parcela
																igor_dados["turnos_divida"] -= 1
																# Quando os 2 turnos acabam, o restante da dívida é PERDOADO
																# (Hedge Fund perdoa 50% do excedente conforme GDD).
																if igor_dados["turnos_divida"] <= 0:
																								if igor_dados["divida_ativa"] > 0 and pinos_jogadores.has("igor"):
																																pinos_jogadores["igor"].mostrar_texto_flutuante("HEDGE: DÍVIDA RESTANTE PERDOADA", Color(0.3, 0.9, 0.3))
																								igor_dados["divida_ativa"] = 0
																								igor_dados["divida_original"] = 0
																								igor_dados["credor_divida"] = ""
																# --- CORREÇÃO: A parcela da dívida pode deixar o Igor
																#     negativo, disparando o sistema de salvamento/falência. ---
																_verificar_falencia("igor", str(credor))

								if indice_turno_atual == 0:
																rodada_atual += 1
																hud.atualizar_round_counter(rodada_atual)
																
																# GDD: no início de cada rodada, recalcula o tráfego previsto
																# usando as posições atuais e os próximos dois movimentos.
																_gerar_tendencias_yasmin()
																
																if OnlineTransport.is_host() and not Global.modo_tutorial:
																								if rodada_atual % 3 == 0:
																																_sortear_evento_global()
																																# --- NOVO (Fonte Anônima da Diana): pré-sortei o PRÓXIMO evento
																																#     global após revelar o atual. Diana pode ver essa info. ---
																																_pre_sortear_proximo_evento()
																								elif rodada_atual % 3 == 1:
																																OnlineTransport.send_all(self, &"_aplicar_evento_global", ["MERCADO ESTÁVEL", "estavel", "A cidade respira temporariamente.\n\nEFEITO:\nNenhuma crise ativa. Aluguéis operam com valores base normais."], true, true)
																																# Mesmo em rodada estável, pré-sortei o próximo evento
																																_pre_sortear_proximo_evento()

								# Reavalia a vitória também no fim de cada turno. Isso cobre o caso
								# em que o último sobrevivente só depois recupera saldo e compra sua
								# primeira propriedade.
								_verificar_vitoria()
								if _partida_encerrada:
																return
								_atualizar_hud_ciclo_turno()
								_emitir_evento_tutorial(
																"turno_iniciado",
																{"jogador_id": jogador_atual_id, "rodada": rodada_atual}
								)
								_verificar_permissao_de_clique()

@rpc("authority", "call_local")
func _mudar_turno_no_servidor():
								await get_tree().create_timer(1.0).timeout
								_avancar_turno()

# ============================================================================
# REGRAS DE MONOPÓLIO E CONSTRUÇÃO
# ============================================================================

# --- BUG #17 FIX: Função genérica que verifica se um jogador é imune a
#     confisco de propriedades. Atualmente, apenas o Kofi tem essa imunidade
#     (habilidade passiva Raízes). Centralizar em uma função permite estender
#     facilmente para outros personagens no futuro. ---
func _e_imune_a_confisco(jogador_id: String) -> bool:
								if jogador_id == "kofi":
																return true
								return false

func _sabotagem_bloqueada_por_raizes(jogador_id: String, carta_nome: String) -> bool:
	if not _e_imune_a_confisco(jogador_id):
		return false
	if pinos_jogadores.has(jogador_id):
		pinos_jogadores[jogador_id].mostrar_texto_flutuante(
			"RAÍZES: PROPRIEDADE PROTEGIDA",
			Color(0.45, 0.95, 0.55)
		)
	_registrar_acao(
		"habilidade",
		"Raízes protegeu as propriedades de Kofi contra " + carta_nome + ".",
		jogador_id
	)
	return true

func _tem_monopolio(id_jogador: String, grupo: String) -> bool:
								if grupo in ["Especial", "Utilidade", "Transporte", "Portal"]: return false
								
								var total_no_grupo = 0
								var propriedades_do_jogador = 0
								for id in tabuleiro.keys():
																if tabuleiro[id].get("grupo") == grupo:
																								total_no_grupo += 1
																								if registro_propriedades.has(id) and registro_propriedades[id] == id_jogador:
																																propriedades_do_jogador += 1
																																
								return propriedades_do_jogador == total_no_grupo and total_no_grupo > 0

# --- NOVO (Fase 3 — Alianças): verifica se dois jogadores são aliados.
#     Cada jogador tem uma lista "aliancas" com dicts { "com": outro_id, "turnos_restantes": N }.
#     A aliança é bidirecional: se A tem aliança com B, B também tem com A.
#     Retorna true se ambos têm aliança ativa (turnos_restantes > 0) um com o outro. ---
func _sao_aliados(id_a: String, id_b: String) -> bool:
								if id_a == "" or id_b == "" or id_a == id_b:
																return false
								if not dados_economia_jogadores.has(id_a) or not dados_economia_jogadores.has(id_b):
																return false
								# Verifica se A tem aliança ativa com B
								var a_tem = false
								for alianca in dados_economia_jogadores[id_a].get("aliancas", []):
																if alianca.get("com", "") == id_b and alianca.get("turnos_restantes", 0) > 0:
																								a_tem = true
																								break
								if not a_tem:
																return false
								# Verifica se B tem aliança ativa com A (bidirecional)
								for alianca in dados_economia_jogadores[id_b].get("aliancas", []):
																if alianca.get("com", "") == id_a and alianca.get("turnos_restantes", 0) > 0:
																								return true
								return false

func _pode_construir(id_jogador: String, grupo: String) -> bool:
	# Bloqueios específicos por casa são verificados em
	# _motivo_construcao_invalida. Aqui avaliamos somente posse do grupo.
	if grupo in ["Especial", "Utilidade", "Transporte", "Portal", ""]:
		return false
	for efeito in _efeitos_ativos_por_tipo("regra_construcao_livre"):
		var grupos = efeito.get("grupos", [])
		if grupos.is_empty() or grupos.has(grupo):
			return true
	if _tem_monopolio(id_jogador, grupo):
		return true
	if id_jogador == "mira":
		var prop_jogador = 0
		for id in tabuleiro.keys():
			if tabuleiro[id].get("grupo", "") == grupo and registro_propriedades.get(id, "") == id_jogador:
				prop_jogador += 1
		return prop_jogador >= 2
	return false

func _acoes_bloqueadas_por_evento() -> bool:
	return (
		_menu_pause_bloqueando_acoes
		or _eleicao_bloqueando_acoes
		or _evento_interativo_bloqueando_acoes
		or _imunidade_breno_bloqueando_acoes
		or _abutre_bloqueando_acoes
	)

func _acao_bloqueada_por_eleicao(mostrar_feedback: bool = false) -> bool:
	# Nome mantido para compatibilidade com os chamadores antigos.
	if not _acoes_bloqueadas_por_evento():
		return false
	if mostrar_feedback and hud and hud.has_method("mostrar_aviso_turno"):
		var mensagem = "A votação municipal precisa terminar antes desta ação."
		if _menu_pause_bloqueando_acoes:
			mensagem = "Feche o menu de pausa para continuar a partida."
		elif _evento_interativo_bloqueando_acoes:
			mensagem = "A decisão do Evento Global precisa terminar antes desta ação."
		elif _imunidade_breno_bloqueando_acoes:
			mensagem = "Breno precisa decidir se usará a Imunidade Política."
		elif _abutre_bloqueando_acoes:
			mensagem = "Igor precisa decidir sua primeira oferta do Abutre do Mercado."
		hud.mostrar_aviso_turno(mensagem)
	return true

func _ativar_efeito_temporario(chave: String, tipo: String, turnos: int, dados: Dictionary = {}, pular_proximo_decremento: bool = false) -> void:
	var efeito = dados.duplicate(true)
	# Um evento ignorado pelo Breno grava a exceção dentro do próprio efeito.
	# Assim a proteção continua correta mesmo depois que outro evento for revelado.
	if str(efeito.get("origem", "")) == "evento" and _breno_ignora_evento():
		var excecoes: Array = efeito.get("jogadores_excecao", []).duplicate()
		if not excecoes.has("breno"):
			excecoes.append("breno")
		efeito["jogadores_excecao"] = excecoes
	efeito["chave"] = chave
	efeito["tipo"] = tipo
	efeito["turnos_restantes"] = turnos
	efeito["pular_proximo_decremento"] = pular_proximo_decremento
	efeito["atraso_turnos"] = int(efeito.get("atraso_turnos", 0))
	efeitos_temporarios[chave] = efeito

func _criar_efeito_unico(prefixo: String, tipo: String, turnos: int, dados: Dictionary = {}, pular_proximo_decremento: bool = false) -> String:
	_sequencia_efeitos += 1
	var chave = prefixo + "_" + str(_sequencia_efeitos)
	# _ativar_efeito_temporario registra a exceção do Breno inclusive em
	# efeitos permanentes (turnos = -1) originados pelo evento ignorado.
	_ativar_efeito_temporario(chave, tipo, turnos, dados, pular_proximo_decremento)
	return chave

func _tem_efeito_temporario(chave: String) -> bool:
	if not efeitos_temporarios.has(chave):
		return false
	return int(efeitos_temporarios[chave].get("atraso_turnos", 0)) <= 0

func _efeitos_ativos_por_tipo(tipo: String) -> Array:
	var resultado: Array = []
	for efeito in efeitos_temporarios.values():
		if efeito.get("tipo", "") == tipo and int(efeito.get("atraso_turnos", 0)) <= 0:
			resultado.append(efeito)
	return resultado

func _efeito_aplica_na_casa(efeito: Dictionary, casa_id: int) -> bool:
	if not tabuleiro.has(casa_id):
		return false
	var dono = str(registro_propriedades.get(casa_id, ""))
	if dono != "" and efeito.get("jogadores_excecao", []).has(dono):
		return false
	var dados_casa = tabuleiro[casa_id]
	if efeito.has("casa_id") and int(efeito["casa_id"]) != casa_id:
		return false
	if efeito.has("casas_ids") and not efeito.get("casas_ids", []).has(casa_id):
		return false
	if efeito.has("grupo") and str(efeito["grupo"]) != str(dados_casa.get("grupo", "")):
		return false
	if efeito.has("grupos") and not efeito.get("grupos", []).has(dados_casa.get("grupo", "")):
		return false
	if efeito.has("tipo_casa") and str(efeito["tipo_casa"]) != str(dados_casa.get("tipo", "")):
		return false
	if efeito.has("nivel") and int(efeito["nivel"]) != int(dados_casa.get("nivel", 0)):
		return false
	if efeito.has("nome_contem") and str(dados_casa.get("nome", "")).find(str(efeito["nome_contem"])) < 0:
		return false
	return true

func _construcao_bloqueada_por_efeito(id_jogador: String, casa_id: int) -> bool:
	if turno_construcao_bloqueada and id_jogador == jogador_atual_id:
		return true
	for efeito in _efeitos_ativos_por_tipo("bloqueio_construcao"):
		if efeito.get("jogadores_excecao", []).has(id_jogador):
			continue
		if not _efeito_aplica_na_casa(efeito, casa_id):
			continue
		if efeito.get("somente_hotel", false) and _nivel_destino_construcao(casa_id) < 5:
			continue
		return true
	for efeito in _efeitos_ativos_por_tipo("interdicao"):
		if efeito.get("jogadores_excecao", []).has(id_jogador):
			continue
		if _efeito_aplica_na_casa(efeito, casa_id):
			return true
	return false

func _decrementar_efeitos_temporarios() -> void:
	var chaves = efeitos_temporarios.keys().duplicate()
	for chave in chaves:
		if not efeitos_temporarios.has(chave):
			continue
		var efeito: Dictionary = efeitos_temporarios[chave]
		var atraso = int(efeito.get("atraso_turnos", 0))
		if atraso > 0:
			efeito["atraso_turnos"] = atraso - 1
			efeitos_temporarios[chave] = efeito
			continue
		if efeito.get("pular_proximo_decremento", false):
			efeito["pular_proximo_decremento"] = false
			efeitos_temporarios[chave] = efeito
			continue
		var turnos = int(efeito.get("turnos_restantes", -1))
		if turnos < 0:
			continue
		turnos -= 1
		efeito["turnos_restantes"] = turnos
		if turnos <= 0:
			efeitos_temporarios.erase(chave)
			_ao_expirar_efeito_temporario(efeito)
		else:
			efeitos_temporarios[chave] = efeito

func _ao_expirar_efeito_temporario(efeito: Dictionary) -> void:
	var acao = str(efeito.get("ao_expirar", ""))
	if acao == "chance_estouro_bolha" and OnlineTransport.is_host():
		if randf() < 0.40:
			var desc = "A bolha estourou. Aluguéis caem 40% por 3 turnos, hotéis perdem um nível e todos perdem 10% do caixa."
			OnlineTransport.send_all(self, &"_aplicar_evento_global", ["Bolha Imobiliária — Estouro", "alerta", desc], true, true)
	elif acao == "chance_inverno_startups" and OnlineTransport.is_host():
		if randf() < 0.25:
			OnlineTransport.send_all(self, &"_ativar_inverno_startups_rede", [], true, true)

@rpc("authority", "call_local")
func _ativar_inverno_startups_rede() -> void:
	_ativar_efeito_temporario("inverno_startups", "multiplicador_aluguel", 1, {
		"grupos": ["Verde", "Vermelho"], "multiplicador": 0.5, "origem": "evento"
	})
	for pid in lista_turnos:
		if dados_economia_jogadores.get(pid, {}).get("falido", false):
			continue
		var tem_premium = _jogador_possui_grupo(pid, ["Verde", "Azul-Escuro"])
		if not tem_premium:
			dados_economia_jogadores[pid]["dinheiro"] += 50
		for cid in dados_economia_jogadores[pid].get("propriedades_lista", []):
			if tabuleiro.has(cid) and tabuleiro[cid].get("grupo", "") == "Verde" and tabuleiro[cid].get("nivel", 0) > 0:
				tabuleiro[cid]["nivel"] = max(0, int(tabuleiro[cid]["nivel"]) - 2)
				_atualizar_imagem_construcao(cid)
	_mostrar_alerta_meio_da_tela("INVERNO DAS STARTUPS!\nEfeitos do boom foram invertidos por 1 turno.")

func _jogador_possui_grupo(jogador_id: String, grupos: Array) -> bool:
	for cid in registro_propriedades.keys():
		if registro_propriedades[cid] == jogador_id and grupos.has(tabuleiro[cid].get("grupo", "")):
			return true
	return false

func _jogador_possui_nome(jogador_id: String, trecho_nome: String) -> bool:
	for cid in registro_propriedades.keys():
		if registro_propriedades[cid] == jogador_id and str(tabuleiro[cid].get("nome", "")).find(trecho_nome) >= 0:
			return true
	return false

func _processar_efeitos_periodicos_do_turno(jogador_id: String) -> void:
	if not dados_economia_jogadores.has(jogador_id) or dados_economia_jogadores[jogador_id].get("falido", false):
		return
	for efeito in _efeitos_ativos_por_tipo("efeito_periodico"):
		if efeito.get("jogadores_excecao", []).has(jogador_id):
			continue
		var regra = str(efeito.get("regra", ""))
		var valor = int(efeito.get("valor", 0))
		var aplicar = false
		match regra:
			"sem_transporte_ou_utilidade":
				aplicar = not _jogador_possui_grupo(jogador_id, ["Transporte", "Utilidade", "Verde"])
			"sem_saem":
				aplicar = not _jogador_possui_nome(jogador_id, "SAEM")
			"dono_utilidade":
				aplicar = _jogador_possui_grupo(jogador_id, ["Utilidade"])
			"sem_transporte":
				aplicar = not _jogador_possui_grupo(jogador_id, ["Transporte"])
			"sem_premium":
				aplicar = not _jogador_possui_grupo(jogador_id, ["Verde", "Azul-Escuro"])
		if aplicar and valor != 0:
			var origem = "evento_global" if str(efeito.get("origem", "")) == "evento" else "carta_evento"
			_aplicar_mudanca_dinheiro_rede(jogador_id, valor, origem)

	for efeito in _efeitos_ativos_por_tipo("saldo_revelado"):
		if str(efeito.get("jogador_id", "")) != jogador_id:
			continue
		var dados = dados_economia_jogadores.get(jogador_id, {})
		var nome_publico = str(dados.get("nome", jogador_id)).to_upper()
		_mostrar_alerta_meio_da_tela("SALDO SOB INVESTIGAÇÃO\n" + nome_publico + ": $" + str(dados.get("dinheiro", 0)))

func _obter_aluguel_congelado(casa_id: int, jogador_afetado: String = "") -> int:
	# Retorna o valor final capturado no início do congelamento. Um jogador
	# listado como exceção do evento mantém o aluguel normal para si.
	for efeito in _efeitos_ativos_por_tipo("congelar_aluguel"):
		if jogador_afetado != "" and efeito.get("jogadores_excecao", []).has(jogador_afetado):
			continue
		if not _efeito_aplica_na_casa(efeito, casa_id):
			continue
		var valores = efeito.get("valores_por_casa", {})
		if valores.has(casa_id):
			return max(0, int(valores[casa_id]))
	return -1

func _aplicar_efeitos_ao_aluguel(casa_id: int, aluguel_base: int, jogador_afetado: String = "") -> int:
	var aluguel = aluguel_base
	for efeito in _efeitos_ativos_por_tipo("aluguel_zero"):
		if jogador_afetado != "" and efeito.get("jogadores_excecao", []).has(jogador_afetado):
			continue
		if _efeito_aplica_na_casa(efeito, casa_id):
			return 0
	for efeito in _efeitos_ativos_por_tipo("interdicao"):
		if jogador_afetado != "" and efeito.get("jogadores_excecao", []).has(jogador_afetado):
			continue
		if _efeito_aplica_na_casa(efeito, casa_id):
			return 0
	for efeito in _efeitos_ativos_por_tipo("multiplicador_aluguel"):
		if jogador_afetado != "" and efeito.get("jogadores_excecao", []).has(jogador_afetado):
			continue
		if _efeito_aplica_na_casa(efeito, casa_id):
			aluguel = int(round(aluguel * float(efeito.get("multiplicador", 1.0))))
	return max(0, aluguel)

func _calcular_valor_propriedade(casa_id: int) -> int:
	if not tabuleiro.has(casa_id):
		return 0
	var valor = int(tabuleiro[casa_id].get("preco", 0))
	for efeito in _efeitos_ativos_por_tipo("multiplicador_valor_propriedade"):
		if _efeito_aplica_na_casa(efeito, casa_id):
			valor = int(ceil(valor * float(efeito.get("multiplicador", 1.0))))
	return max(0, valor)

func _calcular_preco_compra(casa_id: int) -> int:
	var preco = _calcular_valor_propriedade(casa_id)
	for efeito in _efeitos_ativos_por_tipo("multiplicador_preco_compra"):
		if _efeito_aplica_na_casa(efeito, casa_id):
			preco = int(ceil(preco * float(efeito.get("multiplicador", 1.0))))
	return max(0, preco)

func _multiplicador_preco_leilao() -> float:
	var multiplicador = 1.0
	for efeito in _efeitos_ativos_por_tipo("multiplicador_preco_leilao"):
		multiplicador *= float(efeito.get("multiplicador", 1.0))
	return multiplicador

func _calcular_bonus_partida(jogador_id: String) -> int:
	var bonus = 200
	for efeito in _efeitos_ativos_por_tipo("bonus_partida"):
		if efeito.get("jogadores_excecao", []).has(jogador_id):
			continue
		bonus = max(bonus, int(efeito.get("valor", bonus)))
	if jogador_id == "breno":
		bonus = int(round(bonus * 1.5))
	return bonus

func _calcular_custo_resgate_hipoteca(casa_id: int) -> int:
	if not tabuleiro.has(casa_id):
		return 0
	var custo = int(ceil(_calcular_valor_propriedade(casa_id) * 0.5 * 1.10))
	var taxa_extra = 0.0
	var dono = str(registro_propriedades.get(casa_id, ""))
	for efeito in _efeitos_ativos_por_tipo("juros_hipoteca_extra"):
		if dono != "" and efeito.get("jogadores_excecao", []).has(dono):
			continue
		taxa_extra += float(efeito.get("taxa", 0.0))
	if taxa_extra > 0.0:
		custo = int(ceil(custo * (1.0 + taxa_extra)))
	return custo

func _negociacoes_bloqueadas_por_efeito(jogador_id: String = "") -> bool:
	for efeito in _efeitos_ativos_por_tipo("bloqueio_negociacao"):
		if jogador_id != "" and efeito.get("jogadores_excecao", []).has(jogador_id):
			continue
		return true
	return false

func _acordo_silencio_bloqueia(jogador_id: String) -> bool:
	return acordo_silencio_ativo and jogador_id != "breno"

func _habilidades_bloqueadas_por_efeito(jogador_id: String = "") -> bool:
	for efeito in _efeitos_ativos_por_tipo("bloqueio_habilidade"):
		if jogador_id != "" and efeito.get("jogadores_excecao", []).has(jogador_id):
			continue
		return true
	return false

func _calcular_aluguel(casa_id: int, dono_id: String, pagador_id: String = "") -> int:
	if not tabuleiro.has(casa_id):
		return 0
	var dados_casa = tabuleiro[casa_id]
	var grupo = str(dados_casa.get("grupo", ""))
	var aluguel_base = 0

	if grupo == "Transporte":
		var qtd_linhas = 0
		if dono_id != "":
			for id in tabuleiro.keys():
				if tabuleiro[id].get("grupo", "") == "Transporte" and registro_propriedades.get(id, "") == dono_id:
					qtd_linhas += 1
		match qtd_linhas:
			1: aluguel_base = 25
			2: aluguel_base = 50
			3: aluguel_base = 100
			_: aluguel_base = 200 if qtd_linhas >= 4 else 0
	elif grupo == "Utilidade":
		var soma_dados = ultimo_dado1 + ultimo_dado2
		var utilidades_do_dono = 0
		if dono_id != "":
			for id in tabuleiro.keys():
				if tabuleiro[id].get("grupo", "") == "Utilidade" and registro_propriedades.get(id, "") == dono_id:
					utilidades_do_dono += 1
		aluguel_base = soma_dados * (10 if utilidades_do_dono >= 2 else 4)
	else:
		var nivel = clampi(int(dados_casa.get("nivel", 0)), 0, 5)
		aluguel_base = _obter_aluguel_tabela(casa_id, nivel)

		# O monopólio dobra somente o aluguel do terreno sem construções,
		# conforme a regra do GDD. Casas e hotel já usam seus valores fixos.
		if nivel == 0 and dono_id != "" and _tem_monopolio(dono_id, grupo):
			aluguel_base *= 2

	# Hipoteca sempre tem precedência sobre modificadores positivos.
	if dados_casa.get("hipotecada", false):
		return 0

	# Um congelamento usa o valor FINAL capturado no instante da votação/evento.
	# Retornar aqui impede que Decreto, Especulação ou inflação sejam aplicados
	# novamente sobre o valor congelado.
	var aluguel_congelado = _obter_aluguel_congelado(casa_id, pagador_id)
	if aluguel_congelado >= 0:
		return aluguel_congelado

	# Eventos e cartas com duração são processados pelo gerenciador central.
	aluguel_base = _aplicar_efeitos_ao_aluguel(casa_id, aluguel_base, pagador_id)
	if aluguel_base <= 0:
		return 0

	# Habilidades ativas continuam acumulando com os efeitos globais.
	for pid in lista_turnos:
		var dados_p = dados_economia_jogadores.get(pid, {})
		if dados_p.get("decreto_turnos", 0) > 0 and dados_p.get("decreto_grupo", "") == grupo:
			aluguel_base *= 2
			break
	for pid in lista_turnos:
		var dados_p2 = dados_economia_jogadores.get(pid, {})
		if dados_p2.get("especulacao_turnos", 0) > 0 and int(dados_p2.get("especulacao_casa", -1)) == casa_id:
			aluguel_base *= 2
			break

	aluguel_base = int(round(aluguel_base * multiplicador_inflacao_global))
	return max(0, aluguel_base)

# ============================================================================
# MOTOR DE EVENTOS GLOBAIS E EFEITOS IMEDIATOS
# ============================================================================

# Relatório de Mercado: calcula a chance das casas nos próximos dois turnos reais da mesa.
func _posicao_final_para_relatorio(posicao: int) -> int:
	var total_casas = max(1, tabuleiro.size())
	var final = posmod(posicao, total_casas)
	# Portais e "Vá para a Prisão" alteram o destino final conhecido.
	if final == 12:
		return 28
	if final == 28:
		return 12
	if final == 30:
		return 10
	return final

func _probabilidade_trafego_jogador_1_turno(posicao_inicial: int, casa_alvo: int) -> float:
	var probabilidade = 0.0
	for soma_variant in DISTRIBUICAO_2D6.keys():
		var soma = int(soma_variant)
		var destino = _posicao_final_para_relatorio(posicao_inicial + soma)
		if destino == casa_alvo:
			probabilidade += float(DISTRIBUICAO_2D6[soma_variant])
	return clampf(probabilidade, 0.0, 1.0)

func _proximos_jogadores_do_relatorio(quantidade: int = 2) -> Array:
	var resultado: Array = []
	if lista_turnos.is_empty() or quantidade <= 0:
		return resultado
	var inicio = clampi(indice_turno_atual, 0, lista_turnos.size() - 1)
	var limite = lista_turnos.size() * 2
	for deslocamento in range(limite):
		var indice = (inicio + deslocamento) % lista_turnos.size()
		var pid = str(lista_turnos[indice])
		if not dados_economia_jogadores.has(pid):
			continue
		if dados_economia_jogadores[pid].get("falido", false):
			continue
		resultado.append(pid)
		if resultado.size() >= quantidade:
			break
	return resultado

func _gerar_tendencias_yasmin():
	var candidatos: Array = []
	var proximos_jogadores = _proximos_jogadores_do_relatorio(2)
	for cid_variant in tabuleiro.keys():
		var cid = int(cid_variant)
		var dados_casa: Dictionary = tabuleiro[cid]
		if int(dados_casa.get("preco", 0)) <= 0:
			continue
		if str(dados_casa.get("tipo", "")) not in ["propriedade", "utilidade", "transporte"]:
			continue

		var prob_nenhum = 1.0
		for pid in proximos_jogadores:
			if not pinos_jogadores.has(pid):
				continue
			var posicao = int(pinos_jogadores[pid].casa_atual)
			var prob_jogador = _probabilidade_trafego_jogador_1_turno(posicao, cid)
			prob_nenhum *= (1.0 - prob_jogador)
		var prob_total = clampf(1.0 - prob_nenhum, 0.0, 1.0)
		candidatos.append({"casa_id": cid, "prob": prob_total})

	candidatos.sort_custom(func(a, b):
		if is_equal_approx(float(a["prob"]), float(b["prob"])):
			return int(a["casa_id"]) < int(b["casa_id"])
		return float(a["prob"]) > float(b["prob"])
	)

	tendencias_fixas.clear()
	for i in range(min(3, candidatos.size())):
		var item: Dictionary = candidatos[i]
		var cid = int(item["casa_id"])
		var nome = str(tabuleiro[cid].get("nome", "Propriedade")).replace("\n", " ").to_upper()
		var dono = str(registro_propriedades.get(cid, ""))
		var situacao = "LIVRE"
		if dono != "":
			situacao = "DE " + str(dados_economia_jogadores.get(dono, {}).get("nome", dono)).to_upper()
		tendencias_fixas.append(
			nome + " — " + ("%.1f" % (float(item["prob"]) * 100.0)) + "% — " + situacao
		)
	tendencias_turnos_restantes = 1

func _pre_sortear_proximo_evento() -> void:
	if not OnlineTransport.is_host():
		return
	var eventos_validos: Array = []
	for evento_variant in eventos_globais_db:
		var evento: Dictionary = evento_variant
		if evento["nome"] != ultimo_evento_sorteado and evento["nome"] != evento_ativo:
			eventos_validos.append(evento)
	if eventos_validos.is_empty():
		OnlineTransport.send_all(
			self,
			&"_sincronizar_proximo_evento_rede",
			["", ""],
			true,
			true
		)
		return
	var evento_sorteado: Dictionary = eventos_validos.pick_random()
	OnlineTransport.send_all(
		self,
		&"_sincronizar_proximo_evento_rede",
		[evento_sorteado["nome"], evento_sorteado["descricao"]],
		true,
		true
	)

# RPC que sincroniza o próximo evento sorteado em TODOS os peers.
@rpc("authority", "call_local")
func _sincronizar_proximo_evento_rede(nome_ev: String, desc_ev: String) -> void:
	proximo_evento_global = nome_ev
	proximo_evento_descricao = desc_ev
	if (
		nome_ev == ""
		or not lista_turnos.has("diana")
		or not dados_economia_jogadores.has("diana")
	):
		return

	var dados_diana: Dictionary = dados_economia_jogadores["diana"]
	if dados_diana.get("falido", false):
		return
	if not bool(dados_diana.get("fonte_anonima_usada", false)):
		dados_diana["fonte_anonima_usada"] = true
		dados_diana["fonte_anonima_evento_previsto"] = nome_ev
		_registrar_acao(
			"habilidade",
			"Diana recebeu uma previsão única da Fonte Anônima.",
			"diana"
		)

	var evento_previsto: String = str(
		dados_diana.get("fonte_anonima_evento_previsto", "")
	)
	var meu_id: String = str(Global.escolhas_da_mesa.get(Global.meu_peer_id, ""))
	if (
		meu_id == "diana"
		and evento_previsto == nome_ev
		and hud
		and hud.has_method("alimentar_previsao_evento")
	):
		hud.alimentar_previsao_evento(nome_ev, desc_ev)

func _sortear_evento_global() -> void:
	var eventos_validos: Array = []
	for evento_variant in eventos_globais_db:
		var evento: Dictionary = evento_variant
		if evento["nome"] != ultimo_evento_sorteado:
			eventos_validos.append(evento)
	if eventos_validos.is_empty():
		return

	# O pré-sorteio passa a ser a fonte autoritativa. Assim, a única previsão
	# recebida por Diana sempre corresponde ao evento que será revelado.
	var evento_escolhido: Dictionary = {}
	for evento_variant in eventos_validos:
		var evento_candidato: Dictionary = evento_variant
		if str(evento_candidato["nome"]) == proximo_evento_global:
			evento_escolhido = evento_candidato
			break
	if evento_escolhido.is_empty():
		evento_escolhido = eventos_validos.pick_random()

	ultimo_evento_sorteado = str(evento_escolhido["nome"])
	OnlineTransport.send_all(
		self,
		&"_aplicar_evento_global",
		[evento_escolhido["nome"], "alerta", evento_escolhido["descricao"]],
		true,
		true
	)

@rpc("authority", "call_local")
func _aplicar_evento_global(nome: String, status: String, descricao: String = ""):
	if status != "estavel" and dados_economia_jogadores.has("diana"):
		var dados_diana: Dictionary = dados_economia_jogadores["diana"]
		if str(dados_diana.get("fonte_anonima_evento_previsto", "")) == nome:
			dados_diana["fonte_anonima_evento_previsto"] = ""
			var meu_id: String = str(Global.escolhas_da_mesa.get(Global.meu_peer_id, ""))
			if meu_id == "diana" and hud and hud.has_method("limpar_previsao_evento"):
				hud.limpar_previsao_evento()
	if status == "estavel":
		_finalizar_rastreamento_evento_xp()
		_breno_evento_imune_atual = ""
		if dados_economia_jogadores.has("breno"):
			dados_economia_jogadores["breno"]["evento_imune_atual"] = ""
	else:
		_iniciar_rastreamento_evento_xp(nome)

	evento_ativo = nome
	if status != "estavel":
		_registrar_acao("evento", "Evento Global: " + nome + ".")

	if status == "estavel":
		hud.atualizar_evento_global(nome, true, descricao)
		return

	var cor_evento = Color(0.95, 0.3, 0.3)
	match nome:
		"Bolha Imobiliária — Expansão": cor_evento = Color(0.2, 0.9, 0.3)
		"Bolha Imobiliária — Estouro": cor_evento = Color(0.9, 0.2, 0.2)
		"Greve Geral": cor_evento = Color(0.9, 0.6, 0.1)
		"Onda de Calor Extremo": cor_evento = Color(1.0, 0.4, 0.0)
		"Enchente da Bacia Norte": cor_evento = Color(0.2, 0.5, 0.9)
		"Vendaval e Queda de Granizo": cor_evento = Color(0.6, 0.7, 0.95)
		"Crise do Crédito": cor_evento = Color(0.5, 0.5, 0.5)
		"Migração em Massa": cor_evento = Color(0.8, 0.6, 0.3)
		"Boom das Startups": cor_evento = Color(0.3, 0.9, 0.5)
		"Taxa Progressiva": cor_evento = Color(0.7, 0.3, 0.7)
		"Gentrificação Acelerada": cor_evento = Color(0.95, 0.4, 0.6)
		"Protestos contra Especulação": cor_evento = Color(0.9, 0.3, 0.2)
		"Inflação Acelerada": cor_evento = Color(0.95, 0.5, 0.1)
		"Nova Lei de Zoneamento": cor_evento = Color(0.5, 0.4, 0.8)
		"Eleições Municipais": cor_evento = Color(0.3, 0.6, 0.9)
		"Intervenção Federal": cor_evento = Color(0.3, 0.3, 0.4)
		"Apagão Digital": cor_evento = Color(0.1, 0.1, 0.15)
		"Revolução dos Carros Autônomos": cor_evento = Color(0.4, 0.9, 0.8)
		"Ilha de Calor Urbano e Seca Florestal": cor_evento = Color(0.9, 0.4, 0.1)
		"Escândalo de Corrupção na Prefeitura": cor_evento = Color(0.6, 0.2, 0.2)

	hud.revelar_evento_cinematico(nome, descricao, cor_evento)
	_mostrar_alerta_meio_da_tela("ALERTA GLOBAL:\n" + nome)

	# Todos os peers calculam a mesma elegibilidade para esconder os dados no
	# primeiro frame. Somente o servidor abre e resolve a decisão.
	if _deve_oferecer_imunidade_breno(nome):
		_imunidade_breno_bloqueando_acoes = true
		hud.esconder_painel_dados()
		if OnlineTransport.is_host():
			_iniciar_decisao_imunidade_breno.call_deferred(nome)
	elif OnlineTransport.is_host():
		OnlineTransport.send_all(self, &"_resolver_evento_global_rede", [nome, false], true, true)

func _deve_oferecer_imunidade_breno(nome_evento: String) -> bool:
	if not EVENTOS_NEGATIVOS_BRENO.has(nome_evento):
		return false
	if not lista_turnos.has("breno") or not dados_economia_jogadores.has("breno"):
		return false
	var dados_breno: Dictionary = dados_economia_jogadores["breno"]
	return not dados_breno.get("falido", false) and not dados_breno.get("usou_imunidade", false)

func _iniciar_decisao_imunidade_breno(nome_evento: String) -> void:
	if not OnlineTransport.is_host():
		return
	OnlineTransport.send_all(self, &"_definir_bloqueio_imunidade_breno_rede", [true], true, true)
	# Aguarda a animação de revelação antes de abrir o modal.
	await get_tree().create_timer(4.05).timeout
	if not _deve_oferecer_imunidade_breno(nome_evento):
		OnlineTransport.send_all(self, &"_resolver_evento_global_rede", [nome_evento, false], true, true)
		return

	var descricao = "Use sua única Imunidade Política para ignorar completamente este Evento Global."
	if nome_evento == "Taxa Progressiva":
		descricao += "\n\nREGRA ESPECIAL: ao usar agora, a Taxa Progressiva será cancelada para TODOS os jogadores."
	var prompts := {
		"breno": {
			"titulo": "IMUNIDADE POLÍTICA",
			"descricao": descricao,
			"opcoes": [{
				"id": "usar_imunidade",
				"nome": "IGNORAR " + nome_evento.to_upper(),
				"detalhe": "Uso único nesta partida.",
				"habilitado": true
			}],
			"min": 1,
			"max": 1,
			"texto_confirmar": "USAR IMUNIDADE",
			"texto_recusar": "ACEITAR EVENTO",
			"permitir_recusar": true,
			"cor": Color(0.95, 0.78, 0.18)
		}
	}
	var respostas = await _executar_sessao_decisoes(
		prompts,
		EVENTO_DECISAO_DURACAO_SEGUNDOS,
		"DECISÃO DE BRENO",
		"Breno está decidindo se usa a Imunidade Política.",
		Color(0.95, 0.78, 0.18)
	)
	var resposta: Dictionary = respostas.get("breno", {})
	var usar = (
		str(resposta.get("acao", "")) == "confirmar"
		and resposta.get("selecionados", []).has("usar_imunidade")
	)
	OnlineTransport.send_all(self, &"_resolver_evento_global_rede", [nome_evento, usar], true, true)

@rpc("authority", "call_local")
func _definir_bloqueio_imunidade_breno_rede(ativo: bool) -> void:
	_imunidade_breno_bloqueando_acoes = ativo
	if ativo:
		if hud:
			hud.esconder_painel_dados()
	elif not _acoes_bloqueadas_por_evento() and not leilao_em_andamento:
		_verificar_permissao_de_clique()

@rpc("authority", "call_local")
func _resolver_evento_global_rede(nome_evento: String, usar_imunidade: bool) -> void:
	# Captura se o evento passou pela janela de decisão antes de liberar o
	# bloqueio; isso evita repetir a espera cinematográfica quando Breno recusa.
	var houve_decisao_breno = _imunidade_breno_bloqueando_acoes
	_imunidade_breno_bloqueando_acoes = false
	_breno_evento_imune_atual = ""
	if dados_economia_jogadores.has("breno"):
		dados_economia_jogadores["breno"]["evento_imune_atual"] = ""

	if usar_imunidade and _deve_oferecer_imunidade_breno(nome_evento):
		dados_economia_jogadores["breno"]["usou_imunidade"] = true
		dados_economia_jogadores["breno"]["evento_imune_atual"] = nome_evento
		_breno_evento_imune_atual = nome_evento
		if pinos_jogadores.has("breno"):
			pinos_jogadores["breno"].mostrar_texto_flutuante("IMUNIDADE POLÍTICA!", Color(0.95, 0.82, 0.2))
		_registrar_acao("habilidade", "Breno usou Imunidade Política contra " + nome_evento + ".", "breno")

		if nome_evento == "Taxa Progressiva":
			Animacoes.banner_cinematico(
				hud.get_node("Control"),
				"TAXA CANCELADA",
				"Breno anulou integralmente a Taxa Progressiva para toda a cidade.",
				Color(0.95, 0.78, 0.18),
				3.0
			)
			_atualizar_hud_ciclo_turno()
			_verificar_permissao_de_clique()
			return

	if houve_decisao_breno:
		_evento_resolvido_apos_decisao_breno = nome_evento
	_processar_evento_gdd(nome_evento)
	_aplicar_impacto_reputacao_evento(nome_evento)
	Animacoes.tremer_camera(camera, 4.0, 0.4)
	if nome_evento == "Eleições Municipais" and OnlineTransport.is_host():
		_iniciar_votacao_eleicao()
	if not _acoes_bloqueadas_por_evento() and not leilao_em_andamento:
		_verificar_permissao_de_clique()

func _breno_ignora_evento(nome_evento: String = "") -> bool:
	var alvo = nome_evento if nome_evento != "" else evento_ativo
	return (
		alvo != ""
		and _breno_evento_imune_atual == alvo
		and dados_economia_jogadores.has("breno")
		and str(dados_economia_jogadores["breno"].get("evento_imune_atual", "")) == alvo
	)

func _aplicar_taxa_drenagem_para_grupos(grupos_afetados: Array) -> void:
	if grupos_afetados.is_empty():
		return
	var dono_saem = ""
	for cid in registro_propriedades.keys():
		if str(tabuleiro.get(cid, {}).get("nome", "")).find("SAEM") >= 0:
			dono_saem = str(registro_propriedades[cid])
			break
	if dono_saem == "" or dados_economia_jogadores.get(dono_saem, {}).get("falido", false):
		return
	for pid in lista_turnos:
		if pid == dono_saem or dados_economia_jogadores.get(pid, {}).get("falido", false):
			continue
		if _jogador_possui_grupo(pid, grupos_afetados):
			_aplicar_mudanca_dinheiro_rede(pid, -75, "evento_global", false, dono_saem)
			_aplicar_mudanca_dinheiro_rede(dono_saem, 75, "evento_global")

func _aplicar_taxa_enem_apagao() -> void:
	var dono_enem: String = ""
	for cid_variant in registro_propriedades.keys():
		var cid: int = int(cid_variant)
		if str(tabuleiro.get(cid, {}).get("nome", "")).find("ENEM") >= 0:
			dono_enem = str(registro_propriedades[cid])
			break
	if (
		dono_enem == ""
		or dados_economia_jogadores.get(dono_enem, {}).get("falido", false)
		or (dono_enem == "breno" and _breno_ignora_evento())
	):
		return

	var pagadores_insolventes: Array = []
	var pagadores_ativos: Array = lista_turnos.duplicate()
	for pid_variant in pagadores_ativos:
		var pid: String = str(pid_variant)
		if pid == dono_enem or dados_economia_jogadores.get(pid, {}).get("falido", false):
			continue
		if pid == "breno" and _breno_ignora_evento():
			continue
		_aplicar_mudanca_dinheiro_rede(pid, -50, "evento_global", true, dono_enem)
		_aplicar_mudanca_dinheiro_rede(dono_enem, 50, "evento_global")
		if int(dados_economia_jogadores[pid].get("dinheiro", 0)) < 0:
			pagadores_insolventes.append(pid)

	# O evento é simultâneo: processar Kofi por último permite que a
	# Solidariedade de outras falências do mesmo apagão ainda possa salvá-lo.
	if pagadores_insolventes.has("kofi"):
		pagadores_insolventes.erase("kofi")
		pagadores_insolventes.append("kofi")
	for pid_variant in pagadores_insolventes:
		_verificar_falencia(str(pid_variant), dono_enem)

func _aplicar_dano_evento_em_casa(casa_id: int, reducao: int = 1, zerar: bool = false) -> void:
	if not tabuleiro.has(casa_id):
		return
	var dono_evento = str(registro_propriedades.get(casa_id, ""))
	if dono_evento == "breno" and _breno_ignora_evento():
		return
	var nivel_atual = int(tabuleiro[casa_id].get("nivel", 0))
	if nivel_atual <= 0:
		return
	var dono = str(registro_propriedades.get(casa_id, ""))
	var nivel_destino = 0 if zerar else max(0, nivel_atual - reducao)
	if dono == "mira":
		# Resistência Estrutural: recebe somente metade do dano, arredondado
		# a favor da personagem quando o nível é indivisível.
		nivel_destino = int(ceil((nivel_atual + nivel_destino) / 2.0))
		if pinos_jogadores.has(dono):
			pinos_jogadores[dono].mostrar_texto_flutuante("RESISTÊNCIA ESTRUTURAL!", Color(0.3, 0.9, 0.3))
	if nivel_destino < nivel_atual:
		_marcar_perda_construcao_evento_xp(dono)
	tabuleiro[casa_id]["nivel"] = nivel_destino
	_atualizar_imagem_construcao(casa_id)

func _propriedades_com_grupos(grupos: Array, somente_com_construcao: bool = false) -> Array:
	var resultado: Array = []
	for cid in tabuleiro.keys():
		if not registro_propriedades.has(cid):
			continue
		if not grupos.has(tabuleiro[cid].get("grupo", "")):
			continue
		if somente_com_construcao and int(tabuleiro[cid].get("nivel", 0)) <= 0:
			continue
		resultado.append(int(cid))
	resultado.sort()
	return resultado

func _valor_total_propriedades(jogador_id: String) -> int:
	var total = 0
	for cid in dados_economia_jogadores.get(jogador_id, {}).get("propriedades_lista", []):
		if tabuleiro.has(cid):
			total += _calcular_valor_propriedade(int(cid))
	return total

func _processar_evento_gdd(nome_evento: String) -> void:
	if nome_evento == "MERCADO ESTÁVEL":
		return

	match nome_evento:
		"Bolha Imobiliária — Expansão":
			_ativar_efeito_temporario("bolha_expansao_aluguel", "multiplicador_aluguel", 3, {
				"multiplicador": 1.25, "origem": "evento", "ao_expirar": "chance_estouro_bolha"
			})
			_ativar_efeito_temporario("bolha_expansao_construcao", "multiplicador_custo_construcao", 3, {
				"multiplicador": 1.20, "origem": "evento"
			})
			for pid in lista_turnos:
				var tem_monopolio = false
				for grupo in ["Cinza", "Marrom", "Rosa", "Laranja", "Vermelho", "Amarelo", "Verde", "Azul-Escuro"]:
					if _tem_monopolio(pid, grupo):
						tem_monopolio = true
						break
				if tem_monopolio:
					_aplicar_mudanca_dinheiro_rede(pid, 200, "evento_global")

		"Bolha Imobiliária — Estouro":
			_ativar_efeito_temporario("bolha_estouro_aluguel", "multiplicador_aluguel", 3, {
				"multiplicador": 0.60, "origem": "evento"
			})
			for pid in lista_turnos:
				var perda = int(dados_economia_jogadores[pid].get("dinheiro", 0) * 0.10)
				_aplicar_mudanca_dinheiro_rede(pid, -perda, "evento_global")
				var propriedades: Array = dados_economia_jogadores[pid].get("propriedades_lista", []).duplicate()
				propriedades.sort()
				for cid in propriedades:
					if tabuleiro.has(cid) and int(tabuleiro[cid].get("nivel", 0)) == 5:
						_aplicar_dano_evento_em_casa(cid, 1, false)
				var idx_desvalorizada = _indice_deterministico_carta(propriedades, pid, "estouro_bolha")
				if idx_desvalorizada >= 0:
					var cid_desvalorizada = int(propriedades[idx_desvalorizada])
					_criar_efeito_unico("bolha_desvalorizacao", "multiplicador_valor_propriedade", -1, {
						"casa_id": cid_desvalorizada, "multiplicador": 0.70, "origem": "evento"
					})
			if dados_economia_jogadores.has("igor"):
				dados_economia_jogadores["igor"]["usou_abutre"] = false

		"Greve Geral":
			_ativar_efeito_temporario("greve_metro", "aluguel_zero", 2, {"grupo": "Transporte", "origem": "evento"})
			_ativar_efeito_temporario("greve_construcao", "bloqueio_construcao", 1, {"origem": "evento"})
			for pid in lista_turnos:
				if int(dados_economia_jogadores[pid].get("propriedades_compradas", 0)) > 4:
					_aplicar_mudanca_dinheiro_rede(pid, -150, "evento_global")
			if lista_turnos.has("kofi"):
				_aplicar_mudanca_dinheiro_rede("kofi", 200, "evento_global")

		"Onda de Calor Extremo":
			_ativar_efeito_temporario("onda_calor_utilidades", "multiplicador_aluguel", 2, {
				"grupo": "Utilidade", "multiplicador": 2.0, "origem": "evento"
			})
			_ativar_efeito_temporario("onda_calor_sobrevivencia", "efeito_periodico", 2, {
				"regra": "sem_transporte_ou_utilidade", "valor": -30, "origem": "evento"
			})
			for cid in _propriedades_com_grupos(["Cinza", "Marrom"], true):
				var dono_casa = str(registro_propriedades.get(cid, ""))
				if dono_casa != "" and _jogador_possui_grupo(dono_casa, ["Verde"]):
					continue
				_aplicar_dano_evento_em_casa(cid, 1, false)
			for pid in lista_turnos:
				if _jogador_possui_grupo(pid, ["Verde"]):
					_aplicar_mudanca_dinheiro_rede(pid, 100, "evento_global")

		"Enchente da Bacia Norte":
			var grupos_afetados: Array = ["Rosa", "Marrom"]
			# Nova Lei de Zoneamento: durante 2 turnos, o grupo selecionado
			# também perde a proteção climática e sofre os efeitos urbanos.
			for grupo_extra in _grupos_vulneraveis_clima("enchente"):
				if not grupos_afetados.has(grupo_extra):
					grupos_afetados.append(grupo_extra)
			_ativar_efeito_temporario("enchente_bairros", "aluguel_zero", 1, {
				"grupos": grupos_afetados, "origem": "evento"
			})
			_ativar_efeito_temporario("enchente_laranja", "multiplicador_aluguel", 2, {
				"grupo": "Laranja", "multiplicador": 1.15, "origem": "evento"
			})
			for cid in _propriedades_com_grupos(grupos_afetados, true):
				_aplicar_dano_evento_em_casa(cid, 1, false)
			_aplicar_taxa_drenagem_para_grupos(grupos_afetados)

		"Vendaval e Queda de Granizo":
			# O dano é resolvido somente depois da janela de seguro retroativo.
			_ativar_efeito_temporario("vendaval_metro", "aluguel_zero", 1, {
				"grupo": "Transporte", "origem": "evento"
			})

		"Crise do Crédito":
			_ativar_efeito_temporario("crise_credito_construcao", "bloqueio_construcao", 2, {
				"jogadores_excecao": ["igor"], "origem": "evento"
			})
			_ativar_efeito_temporario("crise_credito_leilao", "multiplicador_preco_leilao", 2, {
				"multiplicador": 0.70, "origem": "evento"
			})

		"Migração em Massa":
			_ativar_efeito_temporario("migracao_populares", "multiplicador_aluguel", 3, {
				"grupos": ["Rosa", "Marrom"], "multiplicador": 2.0, "origem": "evento"
			})
			_ativar_efeito_temporario("migracao_premium", "multiplicador_aluguel", 3, {
				"grupos": ["Verde", "Azul-Escuro"], "multiplicador": 0.90, "origem": "evento"
			})
			_ativar_efeito_temporario("migracao_valorizacao", "multiplicador_valor_propriedade", -1, {
				"grupos": ["Cinza", "Marrom"], "multiplicador": 1.20, "origem": "evento"
			})

		"Boom das Startups":
			_ativar_efeito_temporario("boom_startups_aluguel", "multiplicador_aluguel", 3, {
				"grupos": ["Verde", "Vermelho"], "multiplicador": 2.0,
				"origem": "evento", "ao_expirar": "chance_inverno_startups"
			})
			_ativar_efeito_temporario("boom_startups_exclusao", "efeito_periodico", 3, {
				"regra": "sem_premium", "valor": -50, "origem": "evento"
			})
			for cid in _propriedades_com_grupos(["Verde"], true):
				if str(registro_propriedades.get(cid, "")) == "breno" and _breno_ignora_evento():
					continue
				tabuleiro[cid]["nivel"] = min(5, int(tabuleiro[cid].get("nivel", 0)) + 2)
				_atualizar_imagem_construcao(cid)

		"Taxa Progressiva":
			for pid in lista_turnos:
				if int(dados_economia_jogadores[pid].get("propriedades_compradas", 0)) >= 3:
					var imposto = int(ceil(_valor_total_propriedades(pid) * 0.05))
					_aplicar_mudanca_dinheiro_rede(pid, -imposto, "evento_global")

		"Estiagem e Crise Hídrica":
			# A duração (3 ou 1 turno) depende da votação coletiva.
			pass

		"Gentrificação Acelerada":
			_ativar_efeito_temporario("gentrificacao_aluguel", "multiplicador_aluguel", -1, {
				"grupo": "Cinza", "multiplicador": 1.50, "origem": "evento"
			})
			_ativar_efeito_temporario("gentrificacao_compra", "multiplicador_preco_compra", -1, {
				"grupo": "Cinza", "multiplicador": 2.0, "origem": "evento"
			})
			# O dano aleatório do Bairro Boemia é escolhido pelo servidor junto
			# da janela interativa, evitando sorteios divergentes entre peers.

		"Protestos contra Especulação":
			_ativar_efeito_temporario("protestos_hotel_aluguel", "multiplicador_aluguel", 2, {
				"nivel": 5, "multiplicador": 0.50, "origem": "evento"
			})
			_ativar_efeito_temporario("protestos_hotel_construcao", "bloqueio_construcao", 2, {
				"somente_hotel": true, "origem": "evento"
			})
			var hoteis_adversarios_kofi = 0
			for pid in lista_turnos:
				var hoteis = _contar_hoteis_do_jogador(pid)
				if hoteis > 2:
					_aplicar_mudanca_dinheiro_rede(pid, -(hoteis * 100), "evento_global")
				if pid != "kofi":
					hoteis_adversarios_kofi += hoteis
			if lista_turnos.has("kofi") and hoteis_adversarios_kofi > 0:
				_aplicar_mudanca_dinheiro_rede("kofi", hoteis_adversarios_kofi * 50, "evento_global")

		"Inflação Acelerada":
			_ativar_efeito_temporario("inflacao_construcao", "multiplicador_custo_construcao", 3, {
				"multiplicador": 1.30, "origem": "evento"
			})
			_ativar_efeito_temporario("inflacao_partida", "bonus_partida", 3, {
				"valor": 250, "origem": "evento"
			})
			_ativar_efeito_temporario("inflacao_hipoteca", "juros_hipoteca_extra", 3, {
				"taxa": 0.15, "origem": "evento"
			})

		"Nova Lei de Zoneamento":
			# O grupo só é definido depois da escolha opcional de Breno.
			pass

		"Eleições Municipais":
			# O painel de votação existente continua sendo usado. Os efeitos dos
			# pacotes são ativados em _aplicar_pacote_eleicao.
			pass

		"Intervenção Federal":
			var valores_congelados: Dictionary = {}
			for cid in tabuleiro.keys():
				if tabuleiro[cid].get("grupo", "") == "Utilidade":
					var dono = str(registro_propriedades.get(cid, ""))
					valores_congelados[cid] = _calcular_aluguel(int(cid), dono)
			_ativar_efeito_temporario("intervencao_congelamento", "congelar_aluguel", 2, {
				"grupo": "Utilidade", "valores_por_casa": valores_congelados, "origem": "evento"
			})
			_ativar_efeito_temporario("intervencao_compensacao", "efeito_periodico", 2, {
				"regra": "dono_utilidade", "valor": 100, "origem": "evento"
			})

		"Apagão Digital":
			_ativar_efeito_temporario("apagao_construcao", "bloqueio_construcao", 1, {"origem": "evento"})
			_ativar_efeito_temporario("apagao_negociacao", "bloqueio_negociacao", 1, {"origem": "evento"})
			_ativar_efeito_temporario("apagao_habilidades", "bloqueio_habilidade", 1, {"origem": "evento"})
			_aplicar_taxa_enem_apagao()
			for cid in _propriedades_com_grupos(["Verde", "Vermelho"], true):
				_aplicar_dano_evento_em_casa(cid, 1, false)

		"Revolução dos Carros Autônomos":
			if not _tem_efeito_temporario("carros_metro"):
				_ativar_efeito_temporario("carros_metro", "multiplicador_aluguel", -1, {
					"grupo": "Transporte", "multiplicador": 0.70, "origem": "evento"
				})
				_ativar_efeito_temporario("carros_amarelo", "multiplicador_aluguel", -1, {
					"grupo": "Amarelo", "multiplicador": 1.15, "origem": "evento"
				})
				_ativar_efeito_temporario("carros_bonus", "efeito_periodico", -1, {
					"regra": "sem_transporte", "valor": 50, "origem": "evento"
				})

		"Ilha de Calor Urbano e Seca Florestal":
			_ativar_efeito_temporario("ilha_calor_verde", "multiplicador_aluguel", 4, {
				"grupo": "Verde", "multiplicador": 0.70, "origem": "evento"
			})
			_ativar_efeito_temporario("ilha_calor_rosa", "multiplicador_aluguel", 4, {
				"grupo": "Rosa", "multiplicador": 1.10, "origem": "evento"
			})
			var verdes = _propriedades_com_grupos(["Verde"], false)
			for cid in verdes:
				if str(registro_propriedades.get(cid, "")) != "kofi":
					_ativar_efeito_temporario("ilha_interdicao_" + str(cid), "interdicao", 2, {
						"casa_id": cid, "origem": "evento"
					})
					break

		"Escândalo de Corrupção na Prefeitura":
			for pid in lista_turnos:
				if int(dados_economia_jogadores[pid].get("propriedades_compradas", 0)) > 3:
					_aplicar_mudanca_dinheiro_rede(pid, -75, "evento_global")
			var obras = _propriedades_com_grupos(["Cinza", "Marrom", "Rosa", "Laranja", "Vermelho", "Amarelo", "Verde", "Azul-Escuro"], true)
			var embargadas: Array = []
			for cid in obras:
				if int(tabuleiro[cid].get("nivel", 0)) < 5:
					embargadas.append(cid)
					if embargadas.size() >= 2:
						break
			if not embargadas.is_empty():
				_ativar_efeito_temporario("corrupcao_embargo", "interdicao", 2, {
					"casas_ids": embargadas, "origem": "evento"
				})

	# Ramificações com escolha são executadas pelo servidor após o banner
	# cinemático. As demais máquinas recebem somente RPCs validados.
	if OnlineTransport.is_host() and EVENTOS_GDD_INTERATIVOS.has(nome_evento):
		# A função assíncrona bloqueia as ações antes do primeiro await; assim os
		# dados não ficam clicáveis por um frame entre o banner e a decisão.
		_iniciar_fluxo_evento_interativo(nome_evento)

	# Taxas periódicas começam no turno em que o evento é revelado.
	_processar_efeitos_periodicos_do_turno(jogador_atual_id)
	_atualizar_hud_ciclo_turno()
	_atualizar_menu_construcao()

# ============================================================================
# EVENTOS GLOBAIS INTERATIVOS — RAMIFICAÇÕES COMPLETAS DO GDD
# ============================================================================

func _jogadores_ativos_para_evento() -> Array:
	var ativos: Array = []
	if lista_turnos.is_empty():
		return ativos

	# Decisões sequenciais começam pelo jogador do turno atual e seguem a ordem
	# da mesa. Breno é removido apenas do evento que escolheu ignorar.
	var inicio = clampi(indice_turno_atual, 0, lista_turnos.size() - 1)
	for deslocamento in range(lista_turnos.size()):
		var indice = (inicio + deslocamento) % lista_turnos.size()
		var pid = str(lista_turnos[indice])
		if not dados_economia_jogadores.has(pid):
			continue
		if dados_economia_jogadores[pid].get("falido", false):
			continue
		if pid == "breno" and _breno_ignora_evento(_fluxo_evento_interativo_nome):
			continue
		ativos.append(pid)
	return ativos

func _iniciar_fluxo_evento_interativo(nome_evento: String) -> void:
	if not OnlineTransport.is_host() or _fluxo_evento_interativo_ativo:
		return
	_fluxo_evento_interativo_ativo = true
	_fluxo_evento_interativo_nome = nome_evento
	_falencias_pendentes_evento.clear()
	OnlineTransport.send_all(self, &"_definir_bloqueio_evento_interativo_rede", [true, nome_evento], true, true)
	# A preparação acima é síncrona. O restante é agendado para não transformar
	# _processar_evento_gdd em coroutine nem deixar os dados ativos por um frame.
	_executar_fluxo_evento_interativo.call_deferred(nome_evento)

func _executar_fluxo_evento_interativo(nome_evento: String) -> void:
	# Quando houve decisão da Imunidade Política, o banner já terminou.
	# Nos demais eventos preservamos a espera cinematográfica original.
	if _evento_resolvido_apos_decisao_breno == nome_evento:
		_evento_resolvido_apos_decisao_breno = ""
		await get_tree().create_timer(0.25).timeout
	else:
		await get_tree().create_timer(4.05).timeout
	if not _fluxo_evento_interativo_ativo or _fluxo_evento_interativo_nome != nome_evento:
		return

	var aguarda_fila_de_leilao = false
	match nome_evento:
		"Vendaval e Queda de Granizo":
			await _fluxo_vendaval_seguro()
		"Crise do Crédito":
			await _fluxo_crise_credito_compras()
		"Migração em Massa":
			aguarda_fila_de_leilao = _fluxo_migracao_leilao_especial()
		"Estiagem e Crise Hídrica":
			await _fluxo_estiagem_votacao()
		"Gentrificação Acelerada":
			await _fluxo_gentrificacao_vendas()
		"Nova Lei de Zoneamento":
			await _fluxo_nova_lei_zoneamento()

	# A Migração termina somente depois que os dois leilões especiais acabam.
	if not aguarda_fila_de_leilao:
		_encerrar_fluxo_evento_interativo()

@rpc("authority", "call_local")
func _definir_bloqueio_evento_interativo_rede(ativo: bool, nome_evento: String = "") -> void:
	_evento_interativo_bloqueando_acoes = ativo
	if ativo:
		if hud:
			hud.esconder_painel_dados()
		if nome_evento != "":
			_fluxo_evento_interativo_nome = nome_evento
	else:
		if hud and hud.has_method("fechar_decisao_evento"):
			hud.fechar_decisao_evento()
		# Leilões de falência mantêm os dados escondidos até a fila terminar.
		if _leilao_falencia_ativo or leilao_em_andamento:
			if hud:
				hud.esconder_painel_dados()
		else:
			_verificar_permissao_de_clique()

func _encerrar_fluxo_evento_interativo() -> void:
	if not OnlineTransport.is_host():
		return
	_sessao_decisao_evento_ativa = false
	OnlineTransport.send_all(self, &"_fechar_decisao_evento_rede", [-1], true, true)
	_fluxo_evento_interativo_ativo = false
	_fluxo_evento_interativo_nome = ""

	# Custos coletivos podem deixar alguém insolvente. A liquidação começa antes
	# de liberar as ações, evitando que os dados reapareçam atrás do leilão.
	var pendentes = _falencias_pendentes_evento.duplicate()
	_falencias_pendentes_evento.clear()
	# Solidariedade pode salvar Kofi quando outro jogador quebra pelo mesmo
	# custo coletivo. Processá-lo por último torna o resultado simultâneo e
	# independente da posição dele na lista de turnos.
	if pendentes.has("kofi"):
		pendentes.erase("kofi")
		pendentes.append("kofi")
	for pid in pendentes:
		if dados_economia_jogadores.has(pid):
			_verificar_falencia(pid)

	OnlineTransport.send_all(self, &"_definir_bloqueio_evento_interativo_rede", [false, ""], true, true)

func _executar_sessao_decisoes(
	prompts: Dictionary,
	duracao: int,
	titulo_espera: String,
	descricao_espera: String,
	cor_espera: Color
) -> Dictionary:
	if not OnlineTransport.is_host() or prompts.is_empty():
		return {}

	_sessao_decisao_evento_id += 1
	var id_sessao = _sessao_decisao_evento_id
	_sessao_decisao_evento_ativa = true
	_sessao_decisao_evento_prompts = prompts.duplicate(true)
	_sessao_decisao_evento_respostas.clear()

	var alvos: Array = prompts.keys()
	OnlineTransport.send_all(self, &"_mostrar_espera_decisao_evento_rede", [id_sessao,
		alvos,
		titulo_espera,
		descricao_espera,
		duracao,
		cor_espera], true, true)
	for pid in alvos:
		OnlineTransport.send_all(self, &"_mostrar_decisao_evento_rede", [pid, id_sessao, prompts[pid], duracao], true, true)

	var tempo_passado = 0.0
	while (
		_sessao_decisao_evento_ativa
		and id_sessao == _sessao_decisao_evento_id
		and _sessao_decisao_evento_respostas.size() < prompts.size()
		and tempo_passado < float(duracao)
	):
		await get_tree().create_timer(0.1).timeout
		tempo_passado += 0.1

	for pid in alvos:
		if not _sessao_decisao_evento_respostas.has(pid):
			_sessao_decisao_evento_respostas[pid] = {
				"acao": "tempo_esgotado",
				"selecionados": []
			}

	var respostas = _sessao_decisao_evento_respostas.duplicate(true)
	_sessao_decisao_evento_ativa = false
	_sessao_decisao_evento_prompts.clear()
	_sessao_decisao_evento_respostas.clear()
	OnlineTransport.send_all(self, &"_fechar_decisao_evento_rede", [id_sessao], true, true)
	await get_tree().create_timer(0.22).timeout
	return respostas

@rpc("authority", "call_local")
func _mostrar_espera_decisao_evento_rede(
	decisao_id: int,
	alvos: Array,
	titulo: String,
	descricao: String,
	duracao: int,
	cor: Color
) -> void:
	var meu_id = str(Global.escolhas_da_mesa.get(Global.meu_peer_id, ""))
	if meu_id == "" or alvos.has(meu_id):
		return
	if hud and hud.has_method("mostrar_espera_decisao_evento"):
		hud.mostrar_espera_decisao_evento(decisao_id, titulo, descricao, duracao, cor)

@rpc("authority", "call_local")
func _mostrar_decisao_evento_rede(
	alvo_id: String,
	decisao_id: int,
	prompt: Dictionary,
	duracao: int
) -> void:
	var meu_id = str(Global.escolhas_da_mesa.get(Global.meu_peer_id, ""))
	if meu_id != alvo_id:
		return
	if not hud or not hud.has_method("mostrar_decisao_evento"):
		return
	hud.mostrar_decisao_evento(
		decisao_id,
		str(prompt.get("titulo", "DECISÃO DO EVENTO")),
		str(prompt.get("descricao", "")),
		prompt.get("opcoes", []),
		int(prompt.get("min", 0)),
		int(prompt.get("max", 1)),
		str(prompt.get("texto_confirmar", "CONFIRMAR")),
		str(prompt.get("texto_recusar", "RECUSAR")),
		duracao,
		prompt.get("cor", Color(0.9, 0.55, 0.2)),
		bool(prompt.get("permitir_recusar", true))
	)

@rpc("authority", "call_local")
func _fechar_decisao_evento_rede(decisao_id: int) -> void:
	if hud and hud.has_method("fechar_decisao_evento"):
		hud.fechar_decisao_evento(decisao_id)

func _on_hud_decisao_evento(decisao_id: int, acao: String, selecionados: Array) -> void:
	# O host resolve localmente; clientes enviam somente ao servidor. Isso evita
	# depender do comportamento de RPC para o próprio peer em partidas hospedadas.
	if OnlineTransport.is_host():
		_receber_decisao_evento_servidor(decisao_id, acao, selecionados)
	else:
		OnlineTransport.send_host(self, &"_receber_decisao_evento_servidor", [decisao_id, acao, selecionados], false)

@rpc("any_peer", "call_local")
func _receber_decisao_evento_servidor(
	decisao_id: int,
	acao: String,
	selecionados: Array
) -> void:
	if not OnlineTransport.is_host() or not _sessao_decisao_evento_ativa:
		return
	if decisao_id != _sessao_decisao_evento_id:
		return

	var peer_id = OnlineTransport.get_remote_sender_id()
	if peer_id <= 0:
		peer_id = OnlineTransport.local_player_id()
	var personagem_id = str(Global.escolhas_da_mesa.get(peer_id, ""))
	if personagem_id == "" or not _sessao_decisao_evento_prompts.has(personagem_id):
		return
	if _sessao_decisao_evento_respostas.has(personagem_id):
		return

	var prompt: Dictionary = _sessao_decisao_evento_prompts[personagem_id]
	if acao not in ["confirmar", "recusar", "tempo_esgotado"]:
		return
	if acao == "recusar" and not bool(prompt.get("permitir_recusar", true)):
		return

	var permitidos: Array = []
	for opcao_variant in prompt.get("opcoes", []):
		if not (opcao_variant is Dictionary):
			continue
		var opcao: Dictionary = opcao_variant
		if bool(opcao.get("habilitado", true)):
			permitidos.append(str(opcao.get("id", "")))

	var limpos: Array = []
	for selecionado in selecionados:
		var id_limpo = str(selecionado)
		if permitidos.has(id_limpo) and not limpos.has(id_limpo):
			limpos.append(id_limpo)

	if acao == "confirmar":
		var minimo = int(prompt.get("min", 0))
		var maximo = int(prompt.get("max", 1))
		if limpos.size() < minimo or limpos.size() > maximo:
			return
	elif acao == "tempo_esgotado":
		limpos.clear()

	_sessao_decisao_evento_respostas[personagem_id] = {
		"acao": acao,
		"selecionados": limpos
	}

func _opcao_propriedade_evento(casa_id: int, detalhe_extra: String = "") -> Dictionary:
	var dados_casa = tabuleiro.get(casa_id, {})
	var detalhe = "Grupo %s | Valor $%d | Construção N%d" % [
		str(dados_casa.get("grupo", "")),
		int(dados_casa.get("preco", 0)),
		int(dados_casa.get("nivel", 0))
	]
	if detalhe_extra != "":
		detalhe += " | " + detalhe_extra
	return {
		"id": str(casa_id),
		"nome": str(dados_casa.get("nome", "Terreno")).replace("\n", " "),
		"detalhe": detalhe,
		"habilitado": true
	}

# ---------------------------------------------------------------------------
# VENDAVAL — seguro retroativo e proteção de duas propriedades
# ---------------------------------------------------------------------------
func _fluxo_vendaval_seguro() -> void:
	var prompts: Dictionary = {}
	var quantidades_exigidas: Dictionary = {}
	for pid in _jogadores_ativos_para_evento():
		var dados = dados_economia_jogadores[pid]
		if int(dados.get("dinheiro", 0)) <= 500:
			continue
		var construidas: Array = []
		for cid in dados.get("propriedades_lista", []):
			if tabuleiro.has(cid) and int(tabuleiro[cid].get("nivel", 0)) > 0:
				construidas.append(int(cid))
		if construidas.is_empty():
			continue
		construidas.sort()
		var quantidade = min(2, construidas.size())
		quantidades_exigidas[pid] = quantidade
		var opcoes: Array = []
		for cid in construidas:
			opcoes.append(_opcao_propriedade_evento(cid, "PROTEGÍVEL"))
		prompts[pid] = {
			"titulo": "SEGURO RETROATIVO — VENDAVAL",
			"descricao": "Pague $200 para proteger %d propriedade(s) de TODO o dano deste vendaval. Você possui mais de $500 e pode contratar o seguro." % quantidade,
			"opcoes": opcoes,
			"min": quantidade,
			"max": quantidade,
			"texto_confirmar": "PAGAR $200 E PROTEGER",
			"texto_recusar": "ASSUMIR O RISCO",
			"permitir_recusar": true,
			"cor": Color(0.6, 0.75, 1.0)
		}

	var respostas: Dictionary = {}
	if not prompts.is_empty():
		respostas = await _executar_sessao_decisoes(
			prompts,
			EVENTO_DECISAO_DURACAO_SEGUNDOS,
			"VENDAVAL — SEGURO RETROATIVO",
			"Jogadores elegíveis estão escolhendo quais propriedades proteger.",
			Color(0.6, 0.75, 1.0)
		)

	var protegidas: Dictionary = {}
	var todas_protegidas: Array = []
	for pid in respostas.keys():
		var resposta: Dictionary = respostas[pid]
		var selecionados: Array = resposta.get("selecionados", [])
		if resposta.get("acao", "") != "confirmar":
			continue
		if selecionados.size() != int(quantidades_exigidas.get(pid, 0)):
			continue
		if int(dados_economia_jogadores[pid].get("dinheiro", 0)) <= 500:
			continue
		var validas: Array = []
		for id_texto in selecionados:
			var cid = int(str(id_texto))
			if (
				tabuleiro.has(cid)
				and registro_propriedades.get(cid, "") == pid
				and int(tabuleiro[cid].get("nivel", 0)) > 0
			):
				validas.append(cid)
		if validas.size() == selecionados.size():
			protegidas[pid] = validas
			for cid in validas:
				if not todas_protegidas.has(cid):
					todas_protegidas.append(cid)

	var candidatas = _propriedades_com_grupos(
		["Cinza", "Marrom", "Rosa", "Laranja", "Vermelho", "Amarelo", "Verde", "Azul-Escuro"],
		true
	)
	for protegida in todas_protegidas:
		candidatas.erase(protegida)
	candidatas.shuffle()
	var zeradas: Array = []
	for i in range(min(2, candidatas.size())):
		zeradas.append(int(candidatas[i]))
	OnlineTransport.send_all(self, &"_resolver_vendaval_rede", [protegidas, zeradas], true, true)
	await get_tree().create_timer(EVENTO_RESULTADO_DURACAO_SEGUNDOS).timeout

@rpc("authority", "call_local")
func _resolver_vendaval_rede(protegidas: Dictionary, propriedades_zeradas: Array) -> void:
	var ids_protegidos: Array = []
	for pid in protegidas.keys():
		var lista: Array = protegidas[pid]
		if lista.is_empty():
			continue
		_aplicar_mudanca_dinheiro_rede(pid, -200, "decisao_evento")
		for cid in lista:
			if not ids_protegidos.has(int(cid)):
				ids_protegidos.append(int(cid))
		if pinos_jogadores.has(pid):
			pinos_jogadores[pid].mostrar_texto_flutuante("SEGURO ATIVADO!", Color(0.55, 0.8, 1.0))

	# Primeiro, todos os hotéis desprotegidos perdem um nível.
	for cid in registro_propriedades.keys():
		var casa_id = int(cid)
		if ids_protegidos.has(casa_id):
			continue
		if int(tabuleiro[casa_id].get("nivel", 0)) == 5:
			_aplicar_dano_evento_em_casa(casa_id, 1, false)

	# Em seguida, as duas propriedades sorteadas perdem todas as construções.
	for cid_variant in propriedades_zeradas:
		var casa_id = int(cid_variant)
		if ids_protegidos.has(casa_id):
			continue
		_aplicar_dano_evento_em_casa(casa_id, 99, true)

	_atualizar_hud_ciclo_turno()
	_atualizar_menu_construcao()
	_mostrar_alerta_meio_da_tela(
		"VENDAVAL RESOLVIDO\n%d propriedade(s) segurada(s); %d obra(s) atingida(s)." % [
			ids_protegidos.size(), propriedades_zeradas.size()
		]
	)

# ---------------------------------------------------------------------------
# ESTIAGEM — votação coletiva para reduzir a duração
# ---------------------------------------------------------------------------
func _fluxo_estiagem_votacao() -> void:
	var prompts: Dictionary = {}
	var ativos = _jogadores_ativos_para_evento()
	for pid in ativos:
		prompts[pid] = {
			"titulo": "VOTAÇÃO — CRISE HÍDRICA",
			"descricao": "Reduzir a estiagem de 3 para 1 turno? Se a maioria aprovar, TODOS os jogadores ativos pagarão $100.",
			"opcoes": [
				{"id": "sim", "nome": "SIM — REDUZIR PARA 1 TURNO", "detalhe": "Custo coletivo de $100 por jogador", "habilitado": true},
				{"id": "nao", "nome": "NÃO — MANTER 3 TURNOS", "detalhe": "Sem custo coletivo", "habilitado": true}
			],
			"min": 1,
			"max": 1,
			"texto_confirmar": "CONFIRMAR VOTO",
			"texto_recusar": "",
			"permitir_recusar": false,
			"cor": Color(0.2, 0.65, 0.9)
		}

	var respostas = await _executar_sessao_decisoes(
		prompts,
		EVENTO_DECISAO_DURACAO_SEGUNDOS,
		"VOTAÇÃO — CRISE HÍDRICA",
		"A cidade decide se pagará para abreviar o racionamento.",
		Color(0.2, 0.65, 0.9)
	)
	var votos_sim = 0
	for resposta_variant in respostas.values():
		var resposta: Dictionary = resposta_variant
		if resposta.get("acao", "") == "confirmar" and resposta.get("selecionados", []).has("sim"):
			votos_sim += 1
	var aprovada = votos_sim * 2 > ativos.size()
	OnlineTransport.send_all(self, &"_resolver_estiagem_rede", [aprovada, votos_sim, ativos.size()], true, true)
	await get_tree().create_timer(EVENTO_RESULTADO_DURACAO_SEGUNDOS).timeout

@rpc("authority", "call_local")
func _resolver_estiagem_rede(aprovada: bool, votos_sim: int, total_votos: int) -> void:
	var duracao = 1 if aprovada else 3
	_ativar_efeito_temporario("estiagem_saem", "multiplicador_aluguel", duracao, {
		"nome_contem": "SAEM", "multiplicador": 3.0, "origem": "evento"
	})
	_ativar_efeito_temporario("estiagem_verde", "multiplicador_aluguel", duracao, {
		"grupo": "Verde", "multiplicador": 1.20, "origem": "evento"
	})
	_ativar_efeito_temporario("estiagem_construcao", "bloqueio_construcao", duracao, {
		"origem": "evento"
	})
	_ativar_efeito_temporario("estiagem_racionamento", "efeito_periodico", duracao, {
		"regra": "sem_saem", "valor": -25, "origem": "evento"
	})

	# Regra operacional da vulnerabilidade do Zoneamento: o grupo perde um nível
	# de construção quando atingido por uma estiagem durante a janela de 2 turnos.
	for grupo in _grupos_vulneraveis_clima("estiagem"):
		for cid in _propriedades_com_grupos([grupo], true):
			_aplicar_dano_evento_em_casa(cid, 1, false)

	if aprovada:
		for pid in _jogadores_ativos_para_evento():
			_aplicar_mudanca_dinheiro_rede(pid, -100, "decisao_evento", true)
			if OnlineTransport.is_host() and not _falencias_pendentes_evento.has(pid):
				_falencias_pendentes_evento.append(pid)

	# A taxa do racionamento começa ainda no turno da revelação.
	_processar_efeitos_periodicos_do_turno(jogador_atual_id)
	_atualizar_hud_ciclo_turno()
	_atualizar_menu_construcao()
	var resultado = "APROVADA" if aprovada else "REJEITADA"
	_mostrar_alerta_meio_da_tela(
		"VOTAÇÃO DA ESTIAGEM: %s\nSIM %d/%d — duração: %d turno(s)." % [
			resultado, votos_sim, total_votos, duracao
		]
	)

# ---------------------------------------------------------------------------
# CRISE DO CRÉDITO — compra de propriedades hipotecadas por 60%
# ---------------------------------------------------------------------------
func _preco_compra_crise_credito(casa_id: int) -> int:
	return int(ceil(float(tabuleiro.get(casa_id, {}).get("preco", 0)) * 0.60))

func _hipotecadas_disponiveis_para(comprador_id: String) -> Array:
	var resultado: Array = []
	if not dados_economia_jogadores.has(comprador_id):
		return resultado
	var saldo = int(dados_economia_jogadores[comprador_id].get("dinheiro", 0))
	for cid in registro_propriedades.keys():
		var casa_id = int(cid)
		var vendedor = str(registro_propriedades[casa_id])
		if vendedor == comprador_id:
			continue
		# Raízes (Kofi): propriedades dele não podem ser tomadas à força por
		# eventos ou sabotagem direta. A compra da crise é compulsória ao vendedor.
		if vendedor == "kofi":
			continue
		if dados_economia_jogadores.get(vendedor, {}).get("falido", false):
			continue
		if not bool(tabuleiro[casa_id].get("hipotecada", false)):
			continue
		if _preco_compra_crise_credito(casa_id) <= saldo:
			resultado.append(casa_id)
	resultado.sort()
	return resultado

func _fluxo_crise_credito_compras() -> void:
	var houve_compra = false
	for comprador in _jogadores_ativos_para_evento():
		var limite_seguranca = 0
		while limite_seguranca < 32:
			limite_seguranca += 1
			if int(dados_economia_jogadores[comprador].get("dinheiro", 0)) <= 500:
				break
			var disponiveis = _hipotecadas_disponiveis_para(comprador)
			if disponiveis.is_empty():
				break
			var opcoes: Array = []
			for cid in disponiveis:
				var vendedor = str(registro_propriedades[cid])
				var nome_vendedor = str(dados_economia_jogadores.get(vendedor, {}).get("nome", vendedor))
				var preco = _preco_compra_crise_credito(cid)
				opcoes.append(_opcao_propriedade_evento(
					cid,
					"Vendedor: %s | Preço da crise: $%d | Permanece hipotecada até o resgate" % [nome_vendedor, preco]
				))
			var prompt = {
				comprador: {
					"titulo": "CRISE DO CRÉDITO — OPORTUNIDADE",
					"descricao": "Você possui mais de $500. Escolha uma propriedade hipotecada de um adversário para comprar por 60% do valor, ou encerre suas compras.",
					"opcoes": opcoes,
					"min": 1,
					"max": 1,
					"texto_confirmar": "COMPRAR SELECIONADA",
					"texto_recusar": "ENCERRAR COMPRAS",
					"permitir_recusar": true,
					"cor": Color(0.65, 0.65, 0.68)
				}
			}
			var respostas = await _executar_sessao_decisoes(
				prompt,
				EVENTO_DECISAO_DURACAO_SEGUNDOS,
				"CRISE DO CRÉDITO",
				"Um investidor está avaliando propriedades hipotecadas.",
				Color(0.65, 0.65, 0.68)
			)
			var resposta: Dictionary = respostas.get(comprador, {})
			if resposta.get("acao", "") != "confirmar":
				break
			var selecionados: Array = resposta.get("selecionados", [])
			if selecionados.size() != 1:
				break
			var casa_id = int(str(selecionados[0]))
			if not disponiveis.has(casa_id):
				break
			OnlineTransport.send_all(self, &"_comprar_hipotecada_crise_rede", [comprador, casa_id], true, true)
			houve_compra = true
			await get_tree().create_timer(0.45).timeout

	if not houve_compra:
		_mostrar_alerta_meio_da_tela("CRISE DO CRÉDITO\nNenhuma propriedade hipotecada foi comprada.")
	else:
		_mostrar_alerta_meio_da_tela("CRISE DO CRÉDITO\nJanela de aquisições encerrada.")
	await get_tree().create_timer(1.2).timeout

@rpc("authority", "call_local")
func _comprar_hipotecada_crise_rede(comprador_id: String, casa_id: int) -> void:
	if not dados_economia_jogadores.has(comprador_id) or not tabuleiro.has(casa_id):
		return
	if not registro_propriedades.has(casa_id):
		return
	var vendedor_id = str(registro_propriedades[casa_id])
	if vendedor_id == comprador_id or not dados_economia_jogadores.has(vendedor_id):
		return
	if vendedor_id == "kofi":
		return
	if not bool(tabuleiro[casa_id].get("hipotecada", false)):
		return
	var preco = _preco_compra_crise_credito(casa_id)
	if int(dados_economia_jogadores[comprador_id].get("dinheiro", 0)) <= 500:
		return
	if int(dados_economia_jogadores[comprador_id].get("dinheiro", 0)) < preco:
		return

	dados_economia_jogadores[comprador_id]["dinheiro"] -= preco
	dados_economia_jogadores[vendedor_id]["dinheiro"] += preco
	dados_economia_jogadores[vendedor_id]["propriedades_lista"].erase(casa_id)
	dados_economia_jogadores[vendedor_id]["propriedades_compradas"] = max(
		0, int(dados_economia_jogadores[vendedor_id].get("propriedades_compradas", 0)) - 1
	)
	if not dados_economia_jogadores[comprador_id]["propriedades_lista"].has(casa_id):
		dados_economia_jogadores[comprador_id]["propriedades_lista"].append(casa_id)
		dados_economia_jogadores[comprador_id]["propriedades_compradas"] += 1
	registro_propriedades[casa_id] = comprador_id
	_registrar_aquisicao_propriedade(casa_id, comprador_id)
	# A compra transfere o ativo, mas não quita a dívida com o banco. O novo
	# proprietário precisa resgatar a hipoteca pelas regras normais.
	tabuleiro[casa_id]["hipotecada"] = true

	_atualizar_visual_dono(casa_id)
	_verificar_novos_monopolios_xp(comprador_id)
	_atualizar_hud_minha_casa()
	_atualizar_hud_ciclo_turno()
	_atualizar_menu_construcao()
	if pinos_jogadores.has(comprador_id):
		pinos_jogadores[comprador_id].mostrar_texto_flutuante("COMPRA DA CRISE -$%d" % preco, Color(0.9, 0.55, 0.2))
	if pinos_jogadores.has(vendedor_id):
		pinos_jogadores[vendedor_id].mostrar_texto_flutuante("ATIVO VENDIDO +$%d" % preco, Color(0.35, 0.9, 0.4))

# ---------------------------------------------------------------------------
# GENTRIFICAÇÃO — venda voluntária de propriedades Cinza por 150%
# ---------------------------------------------------------------------------
func _preco_venda_gentrificacao(casa_id: int) -> int:
	return int(ceil(float(tabuleiro.get(casa_id, {}).get("preco", 0)) * 1.50))

func _cinzas_vendaveis_do_jogador(jogador_id: String) -> Array:
	var resultado: Array = []
	for cid in dados_economia_jogadores.get(jogador_id, {}).get("propriedades_lista", []):
		if not tabuleiro.has(cid):
			continue
		if str(tabuleiro[cid].get("grupo", "")) != "Cinza":
			continue
		# O GDD permite vender qualquer propriedade Cinza já possuída. Caso ela
		# esteja hipotecada, a venda ao banco encerra a hipoteca junto com o ativo.
		resultado.append(int(cid))
	resultado.sort()
	return resultado

func _fluxo_gentrificacao_vendas() -> void:
	# O GDD determina duas propriedades aleatórias do Bairro Boemia. Somente o
	# servidor sorteia e distribui os IDs, mantendo o estado idêntico nos peers.
	var candidatas_rosa = _propriedades_com_grupos(["Rosa"], true)
	candidatas_rosa.shuffle()
	var rosa_atingidas: Array = []
	for i in range(min(2, candidatas_rosa.size())):
		rosa_atingidas.append(int(candidatas_rosa[i]))
	OnlineTransport.send_all(self, &"_aplicar_dano_gentrificacao_rede", [rosa_atingidas], true, true)
	await get_tree().create_timer(0.35).timeout

	var vendas_realizadas = 0
	for pid in _jogadores_ativos_para_evento():
		var limite_seguranca = 0
		while limite_seguranca < 8:
			limite_seguranca += 1
			var vendaveis = _cinzas_vendaveis_do_jogador(pid)
			if vendaveis.is_empty():
				break
			var opcoes: Array = []
			for cid in vendaveis:
				var preco = _preco_venda_gentrificacao(cid)
				opcoes.append(_opcao_propriedade_evento(
					cid,
					"Banco paga $%d (150%%). Construções e eventual hipoteca serão encerradas" % preco
				))
			var prompts = {
				pid: {
					"titulo": "GENTRIFICAÇÃO — JANELA DE VENDA",
					"descricao": "Venda uma propriedade Cinza ao banco por 150% do valor de tabela. Construções e eventual hipoteca são encerradas. Você pode repetir até encerrar.",
					"opcoes": opcoes,
					"min": 1,
					"max": 1,
					"texto_confirmar": "VENDER AO BANCO",
					"texto_recusar": "ENCERRAR VENDAS",
					"permitir_recusar": true,
					"cor": Color(0.78, 0.55, 0.68)
				}
			}
			var respostas = await _executar_sessao_decisoes(
				prompts,
				EVENTO_DECISAO_DURACAO_SEGUNDOS,
				"GENTRIFICAÇÃO ACELERADA",
				"Proprietários do grupo Cinza estão avaliando a oferta do banco.",
				Color(0.78, 0.55, 0.68)
			)
			var resposta: Dictionary = respostas.get(pid, {})
			if resposta.get("acao", "") != "confirmar":
				break
			var selecionados: Array = resposta.get("selecionados", [])
			if selecionados.size() != 1:
				break
			var casa_id = int(str(selecionados[0]))
			if not vendaveis.has(casa_id):
				break
			OnlineTransport.send_all(self, &"_vender_cinza_ao_banco_rede", [pid, casa_id], true, true)
			vendas_realizadas += 1
			await get_tree().create_timer(0.4).timeout

	_mostrar_alerta_meio_da_tela(
		"GENTRIFICAÇÃO\nJanela encerrada: %d propriedade(s) vendida(s)." % vendas_realizadas
	)
	await get_tree().create_timer(1.2).timeout

@rpc("authority", "call_local")
func _aplicar_dano_gentrificacao_rede(casas_atingidas: Array) -> void:
	var aplicadas: Array = []
	for cid_variant in casas_atingidas:
		var casa_id = int(cid_variant)
		if not tabuleiro.has(casa_id):
			continue
		if str(tabuleiro[casa_id].get("grupo", "")) != "Rosa":
			continue
		if not registro_propriedades.has(casa_id):
			continue
		if int(tabuleiro[casa_id].get("nivel", 0)) <= 0:
			continue
		if aplicadas.has(casa_id) or aplicadas.size() >= 2:
			continue
		aplicadas.append(casa_id)
		_aplicar_dano_evento_em_casa(casa_id, 1, false)
	if not aplicadas.is_empty():
		_atualizar_menu_construcao()

@rpc("authority", "call_local")
func _vender_cinza_ao_banco_rede(jogador_id: String, casa_id: int) -> void:
	if not dados_economia_jogadores.has(jogador_id) or not tabuleiro.has(casa_id):
		return
	if registro_propriedades.get(casa_id, "") != jogador_id:
		return
	if str(tabuleiro[casa_id].get("grupo", "")) != "Cinza":
		return
	var valor = _preco_venda_gentrificacao(casa_id)
	dados_economia_jogadores[jogador_id]["dinheiro"] += valor
	dados_economia_jogadores[jogador_id]["propriedades_lista"].erase(casa_id)
	dados_economia_jogadores[jogador_id]["propriedades_compradas"] = max(
		0, int(dados_economia_jogadores[jogador_id].get("propriedades_compradas", 0)) - 1
	)
	registro_propriedades.erase(casa_id)
	tabuleiro[casa_id]["nivel"] = 0
	tabuleiro[casa_id]["hipotecada"] = false
	_atualizar_imagem_construcao(casa_id)
	_atualizar_visual_dono(casa_id)
	_atualizar_hud_minha_casa()
	_atualizar_hud_ciclo_turno()
	_atualizar_menu_construcao()
	if pinos_jogadores.has(jogador_id):
		pinos_jogadores[jogador_id].mostrar_texto_flutuante("VENDA GENTRIFICADA +$%d" % valor, Color(0.45, 0.95, 0.55))

# ---------------------------------------------------------------------------
# NOVA LEI DE ZONEAMENTO — escolha opcional de Breno e vulnerabilidade
# ---------------------------------------------------------------------------
func _grupos_residenciais_gdd() -> Array:
	return ["Cinza", "Marrom", "Rosa", "Laranja", "Vermelho", "Amarelo", "Verde", "Azul-Escuro"]

func _fluxo_nova_lei_zoneamento() -> void:
	var grupos = _grupos_residenciais_gdd()
	var grupo_escolhido = ""
	var breno_pagou = false
	if (
		dados_economia_jogadores.has("breno")
		and not dados_economia_jogadores["breno"].get("falido", false)
		and int(dados_economia_jogadores["breno"].get("dinheiro", 0)) >= 200
		and lista_turnos.has("breno")
	):
		var opcoes: Array = []
		for grupo in grupos:
			opcoes.append({
				"id": grupo,
				"nome": grupo.to_upper(),
				"detalhe": "Hotel liberado com 3 casas; vulnerável ao clima por 2 turnos",
				"habilitado": true
			})
		var prompts = {
			"breno": {
				"titulo": "LOBBY DE ZONEAMENTO — BRENO",
				"descricao": "Pague $200 para escolher qual grupo será beneficiado. Recusar mantém o sorteio aleatório.",
				"opcoes": opcoes,
				"min": 1,
				"max": 1,
				"texto_confirmar": "PAGAR $200 E ESCOLHER",
				"texto_recusar": "DEIXAR O SORTEIO",
				"permitir_recusar": true,
				"cor": Color(0.55, 0.45, 0.85)
			}
		}
		var respostas = await _executar_sessao_decisoes(
			prompts,
			EVENTO_DECISAO_DURACAO_SEGUNDOS,
			"NOVA LEI DE ZONEAMENTO",
			"Breno está decidindo se usará sua influência política.",
			Color(0.55, 0.45, 0.85)
		)
		var resposta: Dictionary = respostas.get("breno", {})
		var selecionados: Array = resposta.get("selecionados", [])
		if (
			resposta.get("acao", "") == "confirmar"
			and selecionados.size() == 1
			and grupos.has(str(selecionados[0]))
			and int(dados_economia_jogadores["breno"].get("dinheiro", 0)) >= 200
		):
			grupo_escolhido = str(selecionados[0])
			breno_pagou = true

	if grupo_escolhido == "":
		grupo_escolhido = str(grupos.pick_random())
	OnlineTransport.send_all(self, &"_aplicar_nova_lei_zoneamento_rede", [grupo_escolhido, breno_pagou], true, true)
	await get_tree().create_timer(EVENTO_RESULTADO_DURACAO_SEGUNDOS).timeout

@rpc("authority", "call_local")
func _aplicar_nova_lei_zoneamento_rede(grupo: String, breno_pagou: bool) -> void:
	if not _grupos_residenciais_gdd().has(grupo):
		return
	if breno_pagou:
		_aplicar_mudanca_dinheiro_rede("breno", -200, "decisao_evento", true)
		if OnlineTransport.is_host() and not _falencias_pendentes_evento.has("breno"):
			_falencias_pendentes_evento.append("breno")
	ultimo_grupo_zoneamento = grupo
	var chave = "zoneamento_" + grupo.to_lower().replace("-", "_")
	_ativar_efeito_temporario(chave, "regra_zoneamento", -1, {
		"grupo": grupo, "origem": "evento"
	})
	_criar_efeito_unico("zoneamento_vulnerabilidade", "vulnerabilidade_climatica", 2, {
		"grupo": grupo,
		"eventos": ["enchente", "estiagem"],
		"origem": "evento"
	})

	for pid in _jogadores_ativos_para_evento():
		if _jogador_possui_grupo(pid, [grupo]):
			_aplicar_mudanca_dinheiro_rede(pid, 150, "evento_global")

	# Se uma crise climática anterior ainda estiver ativa, a vulnerabilidade
	# começa imediatamente em vez de esperar outro sorteio global.
	if _tem_efeito_temporario("enchente_bairros"):
		# Rosa e Marrom já receberam integralmente a enchente original. A lei
		# não duplica dano nem taxa nesses grupos; apenas amplia a crise para
		# um grupo que antes estava protegido.
		if grupo not in ["Rosa", "Marrom"]:
			_criar_efeito_unico("zoneamento_enchente", "aluguel_zero", 1, {
				"grupo": grupo, "origem": "evento"
			})
			for cid in _propriedades_com_grupos([grupo], true):
				_aplicar_dano_evento_em_casa(cid, 1, false)
			_aplicar_taxa_drenagem_para_grupos([grupo])
	elif _tem_efeito_temporario("estiagem_construcao"):
		for cid in _propriedades_com_grupos([grupo], true):
			_aplicar_dano_evento_em_casa(cid, 1, false)

	_atualizar_hud_ciclo_turno()
	_atualizar_menu_construcao()
	var origem = "ESCOLHIDO POR BRENO" if breno_pagou else "SORTEADO"
	_mostrar_alerta_meio_da_tela(
		"NOVA LEI DE ZONEAMENTO\n%s — %s\nHotel com 3 casas; vulnerabilidade climática por 2 turnos." % [
			grupo.to_upper(), origem
		]
	)

func _grupos_vulneraveis_clima(tipo_evento: String) -> Array:
	var grupos: Array = []
	for efeito in _efeitos_ativos_por_tipo("vulnerabilidade_climatica"):
		if not efeito.get("eventos", []).has(tipo_evento):
			continue
		var grupo = str(efeito.get("grupo", ""))
		if grupo != "" and not grupos.has(grupo):
			grupos.append(grupo)
	return grupos

# ---------------------------------------------------------------------------
# MIGRAÇÃO EM MASSA — fila de dois leilões especiais
# ---------------------------------------------------------------------------
func _selecionar_terrenos_migracao() -> Array:
	var candidatos: Array = []
	for cid in tabuleiro.keys():
		if registro_propriedades.has(cid):
			continue
		if str(tabuleiro[cid].get("tipo", "")) != "propriedade":
			continue
		if str(tabuleiro[cid].get("grupo", "")) not in ["Cinza", "Marrom"]:
			continue
		candidatos.append(int(cid))
	candidatos.sort_custom(func(a, b):
		var preco_a = int(tabuleiro[a].get("preco", 0))
		var preco_b = int(tabuleiro[b].get("preco", 0))
		if preco_a == preco_b:
			return int(a) < int(b)
		return preco_a < preco_b
	)
	var selecionados: Array = []
	for i in range(min(2, candidatos.size())):
		selecionados.append(candidatos[i])
	return selecionados

func _fluxo_migracao_leilao_especial() -> bool:
	var terrenos = _selecionar_terrenos_migracao()
	if terrenos.is_empty():
		_mostrar_alerta_meio_da_tela(
			"MIGRAÇÃO EM MASSA\nNão há terrenos baratos disponíveis para o leilão especial."
		)
		return false
	OnlineTransport.send_all(self, &"_iniciar_fila_leilao_evento_rede", [terrenos], true, true)
	return true

@rpc("authority", "call_local")
func _iniciar_fila_leilao_evento_rede(terrenos: Array) -> void:
	# A autoridade envia a mesma fila validada para todos os peers. IDs repetidos,
	# inválidos ou já comprados são descartados antes de qualquer janela abrir.
	_leilao_evento_ativo = true
	_props_leilao_evento.clear()
	for cid_variant in terrenos:
		var cid = int(cid_variant)
		if not tabuleiro.has(cid):
			continue
		if registro_propriedades.has(cid):
			continue
		if str(tabuleiro[cid].get("tipo", "")) != "propriedade":
			continue
		if str(tabuleiro[cid].get("grupo", "")) not in ["Cinza", "Marrom"]:
			continue
		if not _props_leilao_evento.has(cid):
			_props_leilao_evento.append(cid)

	if OnlineTransport.is_host():
		_iniciar_proximo_leilao_evento_agendado.call_deferred()

func _iniciar_proximo_leilao_evento_agendado() -> void:
	if not OnlineTransport.is_host() or not _leilao_evento_ativo:
		return
	await get_tree().create_timer(0.55).timeout
	if _leilao_evento_ativo and not leilao_em_andamento:
		OnlineTransport.send_all(self, &"_iniciar_proximo_leilao_evento_rede", [], true, true)

@rpc("authority", "call_local")
func _iniciar_proximo_leilao_evento_rede() -> void:
	if not _leilao_evento_ativo:
		return

	# Caso algum terreno deixe de estar disponível por uma sincronização tardia,
	# ele é ignorado de forma determinística em todas as máquinas.
	while not _props_leilao_evento.is_empty():
		var proxima_casa = int(_props_leilao_evento.pop_front())
		if registro_propriedades.has(proxima_casa) or not tabuleiro.has(proxima_casa):
			continue
		var lance_minimo = int(ceil(float(tabuleiro[proxima_casa].get("preco", 0)) * 0.50))
		if OnlineTransport.is_host():
			OnlineTransport.send_all(self, &"_iniciar_leilao_rede", [proxima_casa, lance_minimo, "migracao"], false, true)
		return

	_leilao_evento_ativo = false
	_leilao_contexto_atual = "normal"
	_leilao_lance_minimo_atual = 0
	_mostrar_alerta_meio_da_tela("MIGRAÇÃO EM MASSA\nLeilões especiais encerrados.")
	if OnlineTransport.is_host():
		_encerrar_fluxo_evento_interativo()

func _processar_efeitos_imediatos_evento(nome_evento: String):
								for p_id in lista_turnos:
																var dados = dados_economia_jogadores[p_id]
																var props = dados["propriedades_compradas"]
																var mudanca_dinheiro = 0
																
																match nome_evento:
																								"Bolha Imobiliária — Expansão":
																																var tem_algum_monopolio = false
																																for grupo in cores_grupos.keys():
																																								if _tem_monopolio(p_id, grupo): tem_algum_monopolio = true
																																if tem_algum_monopolio: mudanca_dinheiro = 200
																																# --- NOVO (Bolha Expansão): 40% chance de estouro automático ---
																																# Será processado após todos os efeitos imediatos
																								"Bolha Imobiliária — Estouro":
																																mudanca_dinheiro = -int(dados["dinheiro"] * 0.1)
																																# --- NOVO (Bolha Estouro): Hotéis perdem 1 nível. Igor Abutre disponível. ---
																																# Reduz 1 nível em todas as props com hotel (nível 5) do jogador
																																for id_be in dados.get("propriedades_lista", []):
																																				if tabuleiro.has(id_be) and tabuleiro[id_be].get("nivel", 0) == 5:
																																								if p_id == "mira":
																																												pass  # Mira mantém hotel (Resistência Estrutural)
																																								else:
																																												tabuleiro[id_be]["nivel"] = 4
																																												_atualizar_imagem_construcao(id_be)
																																# Igor: Abutre do Mercado disponível novamente
																																if p_id == "igor":
																																				dados_economia_jogadores["igor"]["usou_abutre"] = false
																								"Greve Geral":
																																if p_id == "kofi": mudanca_dinheiro = 200
																																if props > 4: mudanca_dinheiro -= 150
																								"Taxa Progressiva":
																																# --- GDD Tabela 41: Taxa Progressiva de Propriedades ---
																																# 5% do valor total das propriedades (arredondado para cima).
																																# Jogadores com menos de 3 propriedades sao isentos.
																																# Breno: Imunidade Politica pode cancelar (ja tratado genericamente).
																																if props >= 3:
																																								var valor_total_props = 0
																																								for id_t in dados.get("propriedades_lista", []):
																																																if tabuleiro.has(id_t):
																																																								valor_total_props += tabuleiro[id_t].get("preco", 0)
																																								var taxa = int(ceil(valor_total_props * 0.05))
																																								if taxa > 0:
																																																mudanca_dinheiro = -taxa
																								"Vendaval e Queda de Granizo":
																																# --- GDD Tabela 30: Vendaval e Queda de Granizo ---
																																# 1. Hotéis perdem 1 nível (hotel → 4 casas). Mira mantém (50% menos dano).
																																# 2. 2 propriedades aleatórias zeradas. Mira perde metade dos níveis.
																																# 3. Seguro retroativo: >$500 paga $200, protege 2 props mais valiosas.
																																var props_com_construcao = []
																																for id_v in dados.get("propriedades_lista", []):
																																								if tabuleiro.has(id_v) and tabuleiro[id_v].get("nivel", 0) > 0:
																																																props_com_construcao.append(id_v)
																																																# Hotéis perdem 1 nível (vira 4 casas)
																																																if tabuleiro[id_v].get("nivel", 0) == 5:
																																																								if p_id == "mira":
																																																																# Mira: 50% menos dano = 0 níveis perdidos (int(1 * 0.5) = 0)
																																																																pass  # Mira mantém o hotel
																																																								else:
																																																																tabuleiro[id_v]["nivel"] = 4
																																																																_atualizar_imagem_construcao(id_v)
																																# 2. Zerar 2 propriedades aleatórias (seguro protege as 2 mais valiosas)
																																if props_com_construcao.size() > 0:
																																								var props_para_zerar = props_com_construcao.duplicate()
																																								# Seguro retroativo: se tem >$500, paga $200 e protege 2 mais valiosas
																																								if dados["dinheiro"] > 500 and props_para_zerar.size() > 2:
																																																mudanca_dinheiro -= 200  # paga o seguro
																																																# Ordena por preço (mais valiosas primeiro) e remove as protegidas
																																																props_para_zerar.sort_custom(func(a, b): return tabuleiro[a].get("preco", 0) > tabuleiro[b].get("preco", 0))
																																																if dados["dinheiro"] > 500:
																																																								while props_para_zerar.size() > max(0, props_com_construcao.size() - 2):
																																																																if props_para_zerar.is_empty(): break
																																																																props_para_zerar.pop_front()  # remove as 2 mais valiosas (protegidas)
																																								# Zera até 2 propriedades restantes
																																								props_para_zerar.shuffle()
																																								var zerar_count = min(2, props_para_zerar.size())
																																								for z in range(zerar_count):
																																																var id_z = props_para_zerar[z]
																																																if p_id == "mira":
																																																								# Mira: perde metade dos níveis em vez de zerar
																																																								var nivel_atual = tabuleiro[id_z].get("nivel", 0)
																																																								tabuleiro[id_z]["nivel"] = max(0, int(nivel_atual * 0.5))
																																																else:
																																																								tabuleiro[id_z]["nivel"] = 0
																																																_atualizar_imagem_construcao(id_z)
																																																if pinos_jogadores.has(p_id):
																																																								pinos_jogadores[p_id].mostrar_texto_flutuante("VENDAVAL! Obra destruída!", Color(0.6, 0.7, 0.95))
																								# --- NOVOS: Handlers dos 9 eventos adicionais ---
																								"Enchente da Bacia Norte":
																												# --- GDD Tabela 29: Enchente ---
																												_reduzir_nivel_em_grupo(p_id, "Rosa", 1)
																												_reduzir_nivel_em_grupo(p_id, "Marrom", 1)
																												if props > 0:
																																for id_saem in tabuleiro.keys():
																																				if tabuleiro[id_saem].get("nome", "").find("SAEM") >= 0 and registro_propriedades.has(id_saem):
																																								var dono_saem = registro_propriedades[id_saem]
																																								if dono_saem != p_id and not dados_economia_jogadores.get(dono_saem, {}).get("falido", false):
																																												dados_economia_jogadores[dono_saem]["dinheiro"] += 75
																																												dados["dinheiro"] -= 75
																																												if pinos_jogadores.has(dono_saem):
																																																pinos_jogadores[dono_saem].mostrar_texto_flutuante("DRENAGEM +$75", Color(0.3, 0.7, 0.3))
																																								break
																								"Onda de Calor Extremo":
																												# --- GDD Tabela 28: Onda de Calor ---
																												_reduzir_nivel_em_grupo(p_id, "Cinza", 1)
																												_reduzir_nivel_em_grupo(p_id, "Marrom", 1)
																												var tem_metro_util = false
																												for id_oc in tabuleiro.keys():
																																if tabuleiro[id_oc].get("grupo", "") in ["Transporte", "Utilidade"] and registro_propriedades.has(id_oc) and registro_propriedades[id_oc] == p_id:
																																				tem_metro_util = true
																																				break
																												if not tem_metro_util:
																																mudanca_dinheiro = -30
																												var tem_verde = false
																												for id_oc2 in tabuleiro.keys():
																																if tabuleiro[id_oc2].get("grupo", "") == "Verde" and registro_propriedades.has(id_oc2) and registro_propriedades[id_oc2] == p_id:
																																				tem_verde = true
																																				break
																												if tem_verde:
																																mudanca_dinheiro += 100
																								"Estiagem e Crise Hídrica":
																																# Quem não tem SAEM paga $25
																																var tem_saem = false
																																for id in tabuleiro.keys():
																																								if tabuleiro[id].get("nome", "").find("SAEM") >= 0 and registro_propriedades.has(id) and registro_propriedades[id] == p_id:
																																																tem_saem = true
																																if not tem_saem: mudanca_dinheiro = -25
																								"Gentrificação Acelerada":
																																# Bairro Boemia perde 1 casa em 2 propriedades aleatórias (efeito negativo)
																																if p_id == "yasmin" and props > 0:
																																								mudanca_dinheiro = 150  # Yasmin pode vender Cinza por 150%
																																								# --- NOVO (Gentrificação): Boemia (Rosa) -1 casa em 2 props ---
																																								var props_rosa = []
																																								for id_g in dados.get("propriedades_lista", []):
																																												if tabuleiro.has(id_g) and tabuleiro[id_g].get("grupo", "") == "Rosa" and tabuleiro[id_g].get("nivel", 0) > 0:
																																																props_rosa.append(id_g)
																																								if not props_rosa.is_empty():
																																												props_rosa.shuffle()
																																												var destruir_count = min(2, props_rosa.size())
																																												for d in range(destruir_count):
																																																var id_d = props_rosa[d]
																																																if p_id == "mira":
																																																				tabuleiro[id_d]["nivel"] = max(0, int(tabuleiro[id_d]["nivel"] * 0.5))
																																																else:
																																																				tabuleiro[id_d]["nivel"] = max(0, tabuleiro[id_d]["nivel"] - 1)
																																																_atualizar_imagem_construcao(id_d)
																								"Protestos contra Especulação":
																																# Quem tem mais de 2 hotéis paga $100 por hotel
																																var hoteis = _contar_hoteis_do_jogador(p_id)
																																if hoteis > 2:
																																								mudanca_dinheiro = -(hoteis * 100)
																																if p_id == "kofi" and hoteis > 0:
																																								mudanca_dinheiro += hoteis * 50  # Kofi ganha fundo de resistência
																																								# --- NOVO (Protestos): Bloqueia hotel 2T ---
																																								_protestos_bloqueio_hotel = true
																																								_protestos_bloqueio_turnos = 2
																								"Inflação Acelerada":
																																# Jogadores com hipotecas ativas pagam 15% extra
																																var total_hipotecas = _contar_hipotecas_do_jogador(p_id)
																																if total_hipotecas > 0:
																																								mudanca_dinheiro = -(total_hipotecas * 20)
																																# Breno recebe bônus extra na Partida
																																if p_id == "breno":
																																								mudanca_dinheiro += 100
																								"Nova Lei de Zoneamento":
																																# Sorteia um grupo aleatório; donos ganham $150
																																if ultimo_grupo_zoneamento == "":
																																								var grupos_possiveis = ["Cinza", "Marrom", "Rosa", "Laranja", "Vermelho", "Amarelo", "Verde", "Azul-Escuro"]
																																								ultimo_grupo_zoneamento = grupos_possiveis.pick_random()
																																if _tem_monopolio(p_id, ultimo_grupo_zoneamento):
																																								mudanca_dinheiro = 150
																								"Eleições Municipais":
																																# --- GDD Tabela 45: Eleições Municipais — votação em 3 pacotes. ---
																																# Não processa efeito imediato aqui. A votação é iniciada pelo server
																																# em _processar_efeitos_imediatos_evento, após o reveal cinemático.
																																# O efeito real é aplicado em _aplicar_pacote_eleicao() após contagem.
																																pass  # Efeito processado via sistema de votação
																								"Intervenção Federal":
																																# Donos de ENEM/SAEM recebem $100 de compensação
																																var tem_utilidade = false
																																for id in tabuleiro.keys():
																																								if tabuleiro[id].get("grupo") == "Utilidade" and registro_propriedades.has(id) and registro_propriedades[id] == p_id:
																																																tem_utilidade = true
																																if tem_utilidade:
																																								mudanca_dinheiro = 100
																								"Apagão Digital":
																																# Eco-Hub e Zona Financeira perdem 1 nível de construção
																																_reduzir_nivel_em_grupo(p_id, "Verde", 1)
																																_reduzir_nivel_em_grupo(p_id, "Vermelho", 1)
																																# --- NOVO (Apagão Digital): Bloqueia negociações por 1 turno ---
																																acordo_silencio_ativo = true  # Reusa a flag de bloqueio de negociação
																								"Boom das Startups":
																												# --- GDD Tabela 46: Boom das Startups ---
																												# Sem premium (Verde/Azul-Escuro) paga $50. +2 levels em props Verde. 25% inverno.
																												var tem_premium = false
																												for id_bs in tabuleiro.keys():
																																if tabuleiro[id_bs].get("grupo", "") in ["Verde", "Azul-Escuro"] and registro_propriedades.has(id_bs) and registro_propriedades[id_bs] == p_id:
																																				tem_premium = true
																																				break
																												if not tem_premium:
																																mudanca_dinheiro = -50
																												# +2 níveis em props Verde já desenvolvidas (apenas 1x, no 1º jogador)
																												if not dados.get("_boom_casas_adicionadas", false):
																																for id_bs2 in dados.get("propriedades_lista", []):
																																				if tabuleiro.has(id_bs2) and tabuleiro[id_bs2].get("grupo", "") == "Verde" and tabuleiro[id_bs2].get("nivel", 0) > 0:
																																								tabuleiro[id_bs2]["nivel"] = min(5, tabuleiro[id_bs2]["nivel"] + 2)
																																								_atualizar_imagem_construcao(id_bs2)
																																dados["_boom_casas_adicionadas"] = true
																								"Revolução dos Carros Autônomos":
																																# Quem não tem Linhas de Metro recebe $50
																																var tem_linha = false
																																for id in tabuleiro.keys():
																																								if tabuleiro[id].get("grupo") == "Transporte" and registro_propriedades.has(id) and registro_propriedades[id] == p_id:
																																																tem_linha = true
																																if not tem_linha:
																																								mudanca_dinheiro = 50
																																								# --- NOVO (Revolução Carros): -30% metro permanente ---
																																								_carros_autonomos_permanente = true
																								"Ilha de Calor Urbano e Seca Florestal":
																																# --- GDD Tabela 32: Ilha de Calor Urbano e Seca Florestal ---
																																# 1 prop Verde interditada 2T (Kofi imune). -30% Verde e +10% Rosa no _calcular_aluguel.
																																# So executa 1x (no primeiro jogador processado) - a interdicao e global.
																																if _ilha_calor_interditacao_turnos == 0 and _ilha_calor_prop_interditada == -1:
																																				var props_verde = []
																																				for id_ic in tabuleiro.keys():
																																								if tabuleiro[id_ic].get("grupo", "") == "Verde" and registro_propriedades.has(id_ic):
																																												var dono_ic = registro_propriedades[id_ic]
																																												# Kofi e imune a interdicao
																																												if dono_ic != "kofi":
																																																props_verde.append(id_ic)
																																				if not props_verde.is_empty():
																																								props_verde.shuffle()
																																								_ilha_calor_prop_interditada = props_verde[0]
																																								_ilha_calor_interditacao_turnos = 2
																																								if pinos_jogadores.has(p_id):
																																												pinos_jogadores[p_id].mostrar_texto_flutuante("VERDE INTERDITADA 2T!", Color(0.9, 0.4, 0.1))
																								"Escândalo de Corrupção na Prefeitura":
																																# --- GDD Tabela 37: Escandalo de Corrupcao na Prefeitura ---
																																# +3 props pagam $75. 2 obras embargadas 2T. Breno: Imunidade ja tratada genericamente.
																																if props > 3:
																																				mudanca_dinheiro = -75
																																# Embarga 2 propriedades com construcao (níveis 1-4) - so 1x (global)
																																if _corrupcao_embargo_turnos == 0 and _corrupcao_props_embargadas.is_empty():
																																				var props_com_obra = []
																																				for id_ec in dados.get("propriedades_lista", []):
																																								if tabuleiro.has(id_ec) and tabuleiro[id_ec].get("nivel", 0) > 0 and tabuleiro[id_ec].get("nivel", 0) < 5:
																																												props_com_obra.append(id_ec)
																																				if not props_com_obra.is_empty():
																																								props_com_obra.shuffle()
																																								var embargo_count = min(2, props_com_obra.size())
																																								for e in range(embargo_count):
																																												_corrupcao_props_embargadas.append(props_com_obra[e])
																																								_corrupcao_embargo_turnos = 2
																																								if pinos_jogadores.has(p_id):
																																												pinos_jogadores[p_id].mostrar_texto_flutuante("OBRA EMBARGADA 2T!", Color(0.6, 0.2, 0.2))

																if mudanca_dinheiro != 0:
																								dados["dinheiro"] += mudanca_dinheiro
																								if pinos_jogadores.has(p_id):
																																var cor_txt = Color(0.3, 0.9, 0.3) if mudanca_dinheiro > 0 else Color(0.9, 0.3, 0.3)
																																var sinal = "+$" if mudanca_dinheiro > 0 else "-$"
																																pinos_jogadores[p_id].mostrar_texto_flutuante(sinal + str(abs(mudanca_dinheiro)), cor_txt)
																																
								_atualizar_hud_ciclo_turno()
								# --- CORREÇÃO: Aplica o sistema de salvamento/falência para cada
								#     jogador que ficou negativo após os efeitos imediatos do evento.
								#     Antes, eventos como "Taxa Progressiva" (-$50/prop), "Vendaval"
								#     (-$100/prop), "Bolha Estouro" (-10% dinheiro) etc. podiam
								#     deixar jogadores negativos sem nunca disparar a venda automática
								#     de obras/hipoteca. Agora todos são checados. ---
								for p_id_chk in lista_turnos:
																_verificar_falencia(p_id_chk)

@rpc("any_peer", "call_local")
func _mostrar_alerta_meio_da_tela(texto: String):
								var float_label = Label.new()
								float_label.text = texto
								float_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
								float_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
								float_label.add_theme_constant_override("outline_size", 8)
								float_label.add_theme_font_size_override("font_size", 60)

								# --- CORREÇÃO: Tamanho fixo grande + centralização real na tela ---
								var largura = 1000
								var altura = 250
								float_label.custom_minimum_size = Vector2(largura, altura)
								float_label.size = Vector2(largura, altura)
								float_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
								float_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
								float_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

								# Usa o centro real da tela (get_screen_center_position) para posicionar
								var centro_tela = camera.get_screen_center_position()
								float_label.position = centro_tela - Vector2(largura / 2.0, altura / 2.0)
								float_label.z_index = 300
								add_child(float_label)

								var tween = create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
								tween.tween_property(float_label, "position", float_label.position + Vector2(0, -100), 2.5)
								tween.parallel().tween_property(float_label, "modulate:a", 0.0, 2.5)
								tween.tween_callback(float_label.queue_free)

# ============================================================================
# DADOS DO ESPECTADOR, HISTÓRICO, PREVISÃO E PLACAR
# ============================================================================
func _inicializar_meta_partida() -> void:
	for jogador_id in ordem_original_partida:
		_garantir_meta_jogador(str(jogador_id))

func _garantir_meta_jogador(jogador_id: String) -> void:
	if not dados_economia_jogadores.has(jogador_id):
		return
	var dados = dados_economia_jogadores[jogador_id]
	if not dados.has("reputacao"):
		dados["reputacao"] = REPUTACAO_INICIAL
	if not dados.has("xp_partida"):
		dados["xp_partida"] = 0
	if not dados.has("recompensas_xp"):
		dados["recompensas_xp"] = []
	if not dados.has("chaves_xp_recebidas"):
		dados["chaves_xp_recebidas"] = []
	if not dados.has("promessas_cumpridas"):
		dados["promessas_cumpridas"] = 0
	if not dados.has("promessas_quebradas"):
		dados["promessas_quebradas"] = 0
	if not dados.has("acordos_5_turnos"):
		dados["acordos_5_turnos"] = 0
	if not dados.has("habilidades_usadas"):
		dados["habilidades_usadas"] = 0
	if not dados.has("monopolios_premiados"):
		dados["monopolios_premiados"] = []
	if not dados.has("eventos_sem_perder_construcao"):
		dados["eventos_sem_perder_construcao"] = 0
	if not dados.has("bonus_eventos_seguros"):
		dados["bonus_eventos_seguros"] = 0
	if not dados.has("eliminacoes"):
		dados["eliminacoes"] = 0
	if not dados.has("eliminacoes_creditadas"):
		dados["eliminacoes_creditadas"] = []

func _conceder_xp_partida(jogador_id: String, valor: int, chave: String, descricao: String) -> bool:
	if valor <= 0 or not dados_economia_jogadores.has(jogador_id):
		return false
	_garantir_meta_jogador(jogador_id)
	var dados = dados_economia_jogadores[jogador_id]
	var chaves: Array = dados.get("chaves_xp_recebidas", [])
	if chave != "" and chaves.has(chave):
		return false
	if chave != "":
		chaves.append(chave)
		dados["chaves_xp_recebidas"] = chaves
	dados["xp_partida"] = int(dados.get("xp_partida", 0)) + valor
	var recompensas: Array = dados.get("recompensas_xp", [])
	recompensas.append({"chave": chave, "descricao": descricao, "valor": valor})
	dados["recompensas_xp"] = recompensas
	var nome_jogador = str(dados.get("nome", jogador_id))
	_registrar_acao("xp", "%s recebeu +%d XP: %s." % [nome_jogador, valor, descricao], jogador_id)
	if pinos_jogadores.has(jogador_id):
		pinos_jogadores[jogador_id].mostrar_texto_flutuante("+%d XP" % valor, Color(0.55, 0.9, 1.0))
	var personagem_local = str(Global.escolhas_da_mesa.get(Global.meu_peer_id, ""))
	if personagem_local == jogador_id and hud and hud.has_method("atualizar_reputacao_jogador"):
		hud.atualizar_reputacao_jogador(int(dados.get("reputacao", REPUTACAO_INICIAL)), int(dados.get("xp_partida", 0)))
	return true


func _registrar_uso_habilidade_xp(jogador_id: String) -> void:
	_garantir_meta_jogador(jogador_id)
	var dados = dados_economia_jogadores[jogador_id]
	dados["habilidades_usadas"] = int(dados.get("habilidades_usadas", 0)) + 1
	if int(dados["habilidades_usadas"]) >= 5:
		_conceder_xp_partida(jogador_id, XP_CINCO_HABILIDADES, "cinco_habilidades", "Usou a habilidade ativa 5 vezes")


func _grupos_monopolio_atuais(jogador_id: String) -> Array:
	var grupos: Array = []
	for grupo in ["Cinza", "Marrom", "Rosa", "Laranja", "Vermelho", "Amarelo", "Verde", "Azul-Escuro"]:
		if _tem_monopolio(jogador_id, grupo):
			grupos.append(grupo)
	return grupos


func _verificar_novos_monopolios_xp(jogador_id: String) -> void:
	if not dados_economia_jogadores.has(jogador_id):
		return
	_garantir_meta_jogador(jogador_id)
	var dados = dados_economia_jogadores[jogador_id]
	var premiados: Array = dados.get("monopolios_premiados", [])
	for grupo in _grupos_monopolio_atuais(jogador_id):
		if premiados.has(grupo):
			continue
		premiados.append(grupo)
		_conceder_xp_partida(jogador_id, XP_MONOPOLIO, "monopolio_" + str(grupo), "Completou o monopólio " + str(grupo))
	dados["monopolios_premiados"] = premiados


func _iniciar_rastreamento_evento_xp(nome_evento: String) -> void:
	_finalizar_rastreamento_evento_xp()
	_evento_xp_em_andamento = true
	_evento_xp_nome = nome_evento
	_evento_xp_perdas_construcao.clear()
	for jogador_id in ordem_original_partida:
		if dados_economia_jogadores.has(jogador_id) and not dados_economia_jogadores[jogador_id].get("falido", false):
			_evento_xp_perdas_construcao[jogador_id] = false


func _marcar_perda_construcao_evento_xp(jogador_id: String) -> void:
	if not _evento_xp_em_andamento or jogador_id == "":
		return
	if _evento_xp_perdas_construcao.has(jogador_id):
		_evento_xp_perdas_construcao[jogador_id] = true


func _finalizar_rastreamento_evento_xp() -> void:
	if not _evento_xp_em_andamento:
		return
	for jogador_id in _evento_xp_perdas_construcao.keys():
		if not dados_economia_jogadores.has(jogador_id):
			continue
		_garantir_meta_jogador(jogador_id)
		var dados = dados_economia_jogadores[jogador_id]
		if dados.get("falido", false):
			dados["eventos_sem_perder_construcao"] = 0
			continue
		if bool(_evento_xp_perdas_construcao.get(jogador_id, false)):
			dados["eventos_sem_perder_construcao"] = 0
		else:
			dados["eventos_sem_perder_construcao"] = int(dados.get("eventos_sem_perder_construcao", 0)) + 1
			if int(dados["eventos_sem_perder_construcao"]) >= 3:
				if _conceder_xp_partida(jogador_id, XP_TRES_EVENTOS_SEGUROS, "tres_eventos_seguros", "Sobreviveu a 3 eventos sem perder construções"):
					dados["bonus_eventos_seguros"] = int(dados.get("bonus_eventos_seguros", 0)) + 1
	_evento_xp_em_andamento = false
	_evento_xp_nome = ""
	_evento_xp_perdas_construcao.clear()


func _creditar_eliminacao_xp(eliminador_id: String, falido_id: String) -> void:
	if eliminador_id == "" or eliminador_id == falido_id:
		return
	if not dados_economia_jogadores.has(eliminador_id) or not dados_economia_jogadores.has(falido_id):
		return
	if dados_economia_jogadores[eliminador_id].get("falido", false):
		return
	_garantir_meta_jogador(eliminador_id)
	var dados = dados_economia_jogadores[eliminador_id]
	var creditadas: Array = dados.get("eliminacoes_creditadas", [])
	if creditadas.has(falido_id):
		return
	creditadas.append(falido_id)
	dados["eliminacoes_creditadas"] = creditadas
	dados["eliminacoes"] = int(dados.get("eliminacoes", 0)) + 1
	var nome_falido = str(dados_economia_jogadores[falido_id].get("nome", falido_id))
	_conceder_xp_partida(eliminador_id, XP_ELIMINACAO, "eliminacao_" + falido_id, "Eliminou " + nome_falido)


func _alterar_reputacao(jogador_id: String, delta: int, motivo: String) -> void:
	_garantir_meta_jogador(jogador_id)
	if not dados_economia_jogadores.has(jogador_id):
		return
	var dados = dados_economia_jogadores[jogador_id]
	var anterior = int(dados.get("reputacao", REPUTACAO_INICIAL))
	dados["reputacao"] = clampi(anterior + delta, 0, 100)
	if delta != 0 and pinos_jogadores.has(jogador_id):
		var sinal = "+" if delta > 0 else ""
		pinos_jogadores[jogador_id].mostrar_texto_flutuante("REP " + sinal + str(delta), Color(0.4, 1.0, 0.5) if delta > 0 else Color(0.95, 0.4, 0.4))
	if hud:
		var personagem_local = str(Global.escolhas_da_mesa.get(Global.meu_peer_id, ""))
		if personagem_local == jogador_id and hud.has_method("atualizar_reputacao_jogador"):
			hud.atualizar_reputacao_jogador(int(dados.get("reputacao", REPUTACAO_INICIAL)), int(dados.get("xp_partida", 0)))
		if hud.has_method("marcar_espectador_sujo"):
			hud.marcar_espectador_sujo()

func _aplicar_impacto_reputacao_evento(nome_evento: String) -> void:
	for jogador_id in lista_turnos.duplicate():
		if not dados_economia_jogadores.has(jogador_id) or dados_economia_jogadores[jogador_id].get("falido", false):
			continue
		if jogador_id == "breno" and _breno_ignora_evento(nome_evento):
			continue
		_garantir_meta_jogador(jogador_id)
		var reputacao = int(dados_economia_jogadores[jogador_id].get("reputacao", REPUTACAO_INICIAL))
		var nome = dados_economia_jogadores[jogador_id].get("nome", jogador_id)
		if reputacao >= REPUTACAO_LIMITE_BONUS_EVENTO:
			_aplicar_mudanca_dinheiro_rede(jogador_id, REPUTACAO_VALOR_EVENTO, "reputacao_evento")
			_registrar_acao("reputacao", "%s recebeu $%d por alta credibilidade durante %s." % [nome, REPUTACAO_VALOR_EVENTO, nome_evento], jogador_id)
		elif reputacao <= REPUTACAO_LIMITE_PENALIDADE_EVENTO:
			_aplicar_mudanca_dinheiro_rede(jogador_id, -REPUTACAO_VALOR_EVENTO, "reputacao_evento")
			_registrar_acao("reputacao", "%s pagou $%d por baixa credibilidade durante %s." % [nome, REPUTACAO_VALOR_EVENTO, nome_evento], jogador_id)

func _registrar_acao(tipo: String, texto: String, jogador_id: String = "", dados_extras: Dictionary = {}) -> void:
	if texto.strip_edges() == "":
		return
	if not _historico_acoes.is_empty():
		var ultima = _historico_acoes[-1]
		if ultima.get("texto", "") == texto and int(ultima.get("turno", -1)) == _contador_turnos_globais:
			return
	_contador_acoes_historico += 1
	var entrada = dados_extras.duplicate(true)
	entrada["id"] = _contador_acoes_historico
	entrada["tipo"] = tipo
	entrada["texto"] = texto
	entrada["jogador_id"] = jogador_id
	entrada["rodada"] = rodada_atual
	entrada["turno"] = _contador_turnos_globais
	_historico_acoes.append(entrada)
	while _historico_acoes.size() > MAX_HISTORICO_ACOES:
		_historico_acoes.pop_front()
	if hud and hud.has_method("marcar_espectador_sujo"):
		hud.marcar_espectador_sujo()

func _contar_monopolios_do_jogador(jogador_id: String) -> int:
	var grupos: Dictionary = {}
	for casa_id in tabuleiro.keys():
		var grupo = str(tabuleiro[casa_id].get("grupo", ""))
		if grupo in ["", "Especial", "Utilidade", "Transporte", "Portal"]:
			continue
		grupos[grupo] = true
	var total = 0
	for grupo in grupos.keys():
		if _tem_monopolio(jogador_id, str(grupo)):
			total += 1
	return total

func _propriedades_para_estatistica(jogador_id: String) -> Array:
	var resultado: Array = []
	for casa_id in registro_propriedades.keys():
		if registro_propriedades[casa_id] != jogador_id or not tabuleiro.has(casa_id):
			continue
		var dados_casa = tabuleiro[casa_id]
		resultado.append({
			"id": int(casa_id),
			"nome": str(dados_casa.get("nome", "Casa " + str(casa_id))).replace("\n", " "),
			"grupo": str(dados_casa.get("grupo", "")),
			"preco": int(dados_casa.get("preco", 0)),
			"nivel": int(dados_casa.get("nivel", 0)),
			"hipotecada": bool(dados_casa.get("hipotecada", false)),
			"aluguel_estimado": int(_calcular_aluguel(int(casa_id), jogador_id)),
		})
	resultado.sort_custom(func(a, b): return int(a.get("id", 0)) < int(b.get("id", 0)))
	return resultado

func _snapshot_atual_jogador(jogador_id: String) -> Dictionary:
	_garantir_meta_jogador(jogador_id)
	var dados = dados_economia_jogadores.get(jogador_id, {})
	var props = _propriedades_para_estatistica(jogador_id)
	var niveis = 0
	for prop in props:
		niveis += int(prop.get("nivel", 0))
	return {
		"id": jogador_id,
		"nome": str(dados.get("nome", jogador_id)),
		"falido": bool(dados.get("falido", false)),
		"vencedor": bool(dados.get("vencedor", false)),
		"dinheiro": int(dados.get("dinheiro", 0)),
		"patrimonio": int(_calcular_patrimonio(jogador_id)),
		"propriedades": props,
		"quantidade_propriedades": props.size(),
		"hipotecas": int(_contar_hipotecas_do_jogador(jogador_id)),
		"monopolios": int(_contar_monopolios_do_jogador(jogador_id)),
		"niveis_construcao": niveis,
		"reputacao": int(dados.get("reputacao", REPUTACAO_INICIAL)),
		"xp_partida": int(dados.get("xp_partida", 0)),
		"recompensas_xp": dados.get("recompensas_xp", []).duplicate(true),
		"habilidades_usadas": int(dados.get("habilidades_usadas", 0)),
		"monopolios_premiados": dados.get("monopolios_premiados", []).duplicate(),
		"eventos_sem_perder_construcao": int(dados.get("eventos_sem_perder_construcao", 0)),
		"bonus_eventos_seguros": int(dados.get("bonus_eventos_seguros", 0)),
		"eliminacoes": int(dados.get("eliminacoes", 0)),
		"promessas_cumpridas": int(dados.get("promessas_cumpridas", 0)),
		"promessas_quebradas": int(dados.get("promessas_quebradas", 0)),
		"acordos_5_turnos": int(dados.get("acordos_5_turnos", 0)),
		"casa_atual": int(pinos_jogadores[jogador_id].casa_atual) if pinos_jogadores.has(jogador_id) else -1,
	}

func _registrar_snapshot_final(jogador_id: String, colocacao: int) -> void:
	if not dados_economia_jogadores.has(jogador_id):
		return
	var snapshot = _snapshot_atual_jogador(jogador_id)
	snapshot["colocacao"] = colocacao
	_snapshots_finais[jogador_id] = snapshot.duplicate(true)

func _calcular_previsao_vitoria() -> Dictionary:
	var previsao: Dictionary = {}
	var pontuacoes: Dictionary = {}
	var total_pontos = 0.0
	var vivos: Array = []
	for jogador_id in ordem_original_partida:
		if dados_economia_jogadores.has(jogador_id) and not dados_economia_jogadores[jogador_id].get("falido", false):
			vivos.append(jogador_id)
	if vivos.size() == 1:
		for jogador_id in ordem_original_partida:
			previsao[jogador_id] = 100.0 if jogador_id == vivos[0] else 0.0
		return previsao
	for jogador_id in ordem_original_partida:
		if not vivos.has(jogador_id):
			pontuacoes[jogador_id] = 0.0
			continue
		var snapshot = _snapshot_atual_jogador(jogador_id)
		var pontos = maxf(1.0, float(maxi(0, int(snapshot.get("patrimonio", 0)))))
		pontos += float(snapshot.get("quantidade_propriedades", 0)) * 90.0
		pontos += float(snapshot.get("monopolios", 0)) * 220.0
		pontos += float(snapshot.get("niveis_construcao", 0)) * 55.0
		pontos += float(snapshot.get("reputacao", REPUTACAO_INICIAL)) * 2.0
		pontos -= float(snapshot.get("hipotecas", 0)) * 80.0
		pontos = maxf(1.0, pontos)
		pontuacoes[jogador_id] = pontos
		total_pontos += pontos
	for jogador_id in ordem_original_partida:
		var pontos = float(pontuacoes.get(jogador_id, 0.0))
		previsao[jogador_id] = snappedf((pontos / total_pontos) * 100.0, 0.1) if total_pontos > 0.0 else 0.0
	return previsao

func _nome_efeito_espectador(efeito: Dictionary) -> String:
	if efeito.has("nome") and str(efeito.get("nome", "")).strip_edges() != "":
		return str(efeito["nome"])
	var chave = str(efeito.get("chave", "")).strip_edges()
	if chave != "":
		return chave.replace("_", " ").capitalize()
	var tipo = str(efeito.get("tipo", "efeito"))
	return tipo.replace("_", " ").capitalize()

func _eventos_ativos_para_espectador() -> Array:
	var eventos: Array = []
	if evento_ativo != "" and evento_ativo != "MERCADO ESTÁVEL":
		eventos.append({"nome": evento_ativo, "turnos": -1, "origem": "Evento Global atual"})
	for efeito in efeitos_temporarios.values():
		if int(efeito.get("atraso_turnos", 0)) > 0:
			continue
		eventos.append({
			"nome": _nome_efeito_espectador(efeito),
			"turnos": int(efeito.get("turnos_restantes", -1)),
			"origem": str(efeito.get("origem", "efeito ativo")),
		})
	return eventos

func obter_dados_espectador() -> Dictionary:
	var previsao = _calcular_previsao_vitoria()
	var jogadores: Array = []
	for jogador_id in ordem_original_partida:
		var item: Dictionary
		if dados_economia_jogadores.get(jogador_id, {}).get("falido", false) and _snapshots_finais.has(jogador_id):
			item = _snapshots_finais[jogador_id].duplicate(true)
			item["falido"] = true
			item["snapshot_falencia"] = true
		else:
			item = _snapshot_atual_jogador(jogador_id)
		item["previsao_vitoria"] = float(previsao.get(jogador_id, 0.0))
		item["em_turno"] = jogador_id == jogador_atual_id
		jogadores.append(item)
	return {
		"jogadores": jogadores,
		"historico": _historico_acoes.duplicate(true),
		"eventos_ativos": _eventos_ativos_para_espectador(),
		"promessas": _promessas_globais.duplicate(true),
		"evento_atual": evento_ativo,
		"rodada": rodada_atual,
		"turno_global": _contador_turnos_globais,
		"jogador_atual_id": jogador_atual_id,
		"auto_seguir": espectador_auto_seguir,
		"alvo_seguido": espectador_alvo_id,
	}

func ativar_modo_espectador_local() -> void:
	modo_espectador_local = true
	espectador_auto_seguir = true
	espectador_alvo_id = jogador_atual_id
	_atualizar_alvo_camera_espectador()

func configurar_seguimento_espectador(jogador_id: String, automatico: bool) -> void:
	if not modo_espectador_local:
		return
	espectador_auto_seguir = automatico
	if automatico:
		espectador_alvo_id = jogador_atual_id
	elif ordem_original_partida.has(jogador_id) and not dados_economia_jogadores.get(jogador_id, {}).get("falido", false):
		espectador_alvo_id = jogador_id
	_atualizar_alvo_camera_espectador()

func _atualizar_alvo_camera_espectador() -> void:
	if not modo_espectador_local:
		return
	var alvo = jogador_atual_id if espectador_auto_seguir else espectador_alvo_id
	if alvo == "" or not pinos_jogadores.has(alvo) or dados_economia_jogadores.get(alvo, {}).get("falido", false):
		for candidato in lista_turnos:
			if pinos_jogadores.has(candidato):
				alvo = candidato
				break
	if alvo == "" or not pinos_jogadores.has(alvo):
		return
	espectador_alvo_id = alvo
	pino_seguido = pinos_jogadores[alvo]
	seguindo_pino = true
	focar_na_casa(pino_seguido.casa_atual)

func _persistir_progressao_local(placar: Dictionary) -> Dictionary:
	var personagem_local := str(Global.escolhas_da_mesa.get(Global.meu_peer_id, ""))
	if personagem_local == "":
		return {}
	for linha in placar.get("jogadores", []):
		if str(linha.get("id", "")) != personagem_local:
			continue
		var resumo := {
			"xp_ganho": int(linha.get("xp_partida", 0)),
			"colocacao": int(linha.get("colocacao", 0)),
			"eliminacoes": int(linha.get("eliminacoes", 0)),
			"monopolios": linha.get("monopolios_premiados", []).size(),
			"habilidades_usadas": int(linha.get("habilidades_usadas", 0)),
			"acordos_cumpridos": int(linha.get("acordos_5_turnos", 0)),
			"bonus_eventos_seguros": int(linha.get("bonus_eventos_seguros", 0)),
		}
		_resultado_progressao_local = Progressao.aplicar_resultado_partida(resumo)
		return _resultado_progressao_local.duplicate(true)
	return {}


func _montar_placar_final(vencedor_id: String) -> Dictionary:
	var linhas: Array = []
	for jogador_id in ordem_original_partida:
		var linha: Dictionary
		if _snapshots_finais.has(jogador_id):
			linha = _snapshots_finais[jogador_id].duplicate(true)
		else:
			linha = _snapshot_atual_jogador(jogador_id)
		linha["vencedor"] = jogador_id == vencedor_id
		if jogador_id == vencedor_id:
			linha["colocacao"] = 1
		linhas.append(linha)
	linhas.sort_custom(func(a, b):
		if bool(a.get("vencedor", false)) != bool(b.get("vencedor", false)):
			return bool(a.get("vencedor", false))
		var pos_a = int(a.get("colocacao", 999))
		var pos_b = int(b.get("colocacao", 999))
		if pos_a != pos_b:
			return pos_a < pos_b
		return int(a.get("patrimonio", 0)) > int(b.get("patrimonio", 0))
	)
	for i in range(linhas.size()):
		linhas[i]["colocacao"] = i + 1
	return {
		"vencedor_id": vencedor_id,
		"rodadas": rodada_atual,
		"turnos": _contador_turnos_globais,
		"jogadores": linhas,
		"historico": _historico_acoes.duplicate(true),
	}

# ============================================================================
# CÂMERA E GEOMETRIA
# ============================================================================

# Atualiza a câmera a cada frame para seguir o pino enquanto ele se move
func _process(delta: float):
								if seguindo_pino and pino_seguido and is_instance_valid(pino_seguido) and camera:
																# lerp de 10×delta: responsivo o suficiente para não perder o pino de vista,
																# suave o suficiente para não tremer nos saltos tile a tile
																camera.position = camera.position.lerp(pino_seguido.position, delta * 10.0)
																# --- NOVO: limita a posição para não mostrar fundo preto ---
																_limitar_posicao_camera()

# --- Helper: verifica se o mouse/toque está sobre algum Control da HUD que
#     realmente captura mouse (mouse_filter = STOP e visível na árvore). ---
func _mouse_sobre_hud(pos_tela: Vector2) -> bool:
								if not hud or not is_instance_valid(hud):
																return false
								var control = hud.get_node_or_null("Control")
								if not control:
																return false
								for child in _coletar_controls_ativos(control):
																if child is Control and child.is_visible_in_tree() and child.get_global_rect().has_point(pos_tela):
																								return true
								return false

func _coletar_controls_ativos(raiz: Control) -> Array:
								var result: Array = []
								for c in raiz.get_children():
																if c is Control:
																								if c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
																																result.append(c)
																								result.append_array(_coletar_controls_ativos(c))
								return result

# --- CORREÇÃO: Usar _input (recebe TODOS os eventos, inclusive touch raw no mobile).
#     _unhandled_input não recebia os InputEventScreenTouch/ScreenDrag originais
#     no mobile, impedindo o movimento da câmera. ---
func _input(event):
								if _menu_pause_bloqueando_acoes:
																arrastando_camera = false
																toques_ativos.clear()
																return
								if _acoes_bloqueadas_por_evento():
																# Não movimenta a câmera durante a votação, mas não marca o evento
																# como tratado: os cards modais ainda precisam receber clique/teclado.
																arrastando_camera = false
																toques_ativos.clear()
																return
								if cinematica_rodando: return

								# === TOUCH (mobile) ===
								if event is InputEventScreenTouch:
																if event.pressed:
																								toques_ativos[event.index] = event.position
																								# Verifica se o toque começou sobre a HUD (botão, painel, etc.)
																								if _mouse_sobre_hud(event.position):
																																arrastando_camera = false
																								elif toques_ativos.size() == 1:
																																arrastando_camera = true
																																posicao_mouse_anterior = event.position
																else:
																								toques_ativos.erase(event.index)
																								if toques_ativos.is_empty():
																																arrastando_camera = false
																																distancia_toque_anterior = 0.0
																																if modo_espectador_local:
																																	_atualizar_alvo_camera_espectador()
																return

								if event is InputEventScreenDrag:
																# Atualiza a posição atual do toque
																toques_ativos[event.index] = event.position
																# --- PINCH-TO-ZOOM (2 dedos) ---
																if toques_ativos.size() >= 2:
																								var touches = toques_ativos.values()
																								var dist_atual = touches[0].distance_to(touches[1])
																								if distancia_toque_anterior > 0.0:
																																var fator = dist_atual / distancia_toque_anterior
																																_aplicar_zoom(fator)
																								distancia_toque_anterior = dist_atual
																								return
																# --- ARRASTAR CÂMERA (1 dedo, não começou na HUD) ---
																if arrastando_camera:
																								var delta = event.position - posicao_mouse_anterior
																								if camera:
																																camera.position -= delta / camera.zoom.x
																																# --- NOVO: limita posição para não mostrar fundo preto ---
																																_limitar_posicao_camera()
																								posicao_mouse_anterior = event.position
																								seguindo_pino = false
																return

								# === MOUSE (PC) ===
								if event is InputEventMouseButton:
																if event.button_index == MOUSE_BUTTON_LEFT:
																								if _mouse_sobre_hud(event.position):
																																arrastando_camera = false
																																if not event.pressed and modo_espectador_local:
																																	_atualizar_alvo_camera_espectador()
																																return
																								arrastando_camera = event.pressed
																								posicao_mouse_anterior = event.position
																								if not event.pressed and modo_espectador_local:
																									_atualizar_alvo_camera_espectador()
																elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
																								if not _mouse_sobre_hud(event.position):
																																_aplicar_zoom(1.1)
																elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
																								if not _mouse_sobre_hud(event.position):
																																_aplicar_zoom(0.9)
								elif event is InputEventMouseMotion and arrastando_camera:
																var delta = event.position - posicao_mouse_anterior
																if camera:
																								camera.position -= delta / camera.zoom.x
																								# --- NOVO: limita posição para não mostrar fundo preto ---
																								_limitar_posicao_camera()
																posicao_mouse_anterior = event.position
																seguindo_pino = false

func _aplicar_zoom(fator: float):
								if not camera: return
								var z = camera.zoom * fator
								# Zoom mínimo dinâmico: garante que a câmera nunca afaste tanto
								# a ponto de mostrar o fundo preto além dos limites da cidade.
								# Fórmula: zoom_min = viewport_pixels / cidade_size_world
								# (viewport em pixels dividido pelo tamanho da cidade em world units)
								var largura_cidade = CIDADE_LIMITE_X * 2.0
								var altura_cidade = CIDADE_LIMITE_Y * 2.0
								var zoom_min_visivel_x = VIEWPORT_LARGURA / largura_cidade
								var zoom_min_visivel_y = VIEWPORT_ALTURA / altura_cidade
								var zoom_min_visivel = max(zoom_min_visivel_x, zoom_min_visivel_y)
								# Usa o maior entre o ZOOM_MIN original e o visivel calculado
								var zoom_min_efetivo = max(ZOOM_MIN.x, zoom_min_visivel)
								z.x = clamp(z.x, zoom_min_efetivo, ZOOM_MAX.x)
								z.y = clamp(z.y, zoom_min_efetivo, ZOOM_MAX.y)
								camera.zoom = z
								# Após mudar o zoom, reposiciona a câmera para que continue
								# dentro dos limites válidos (o zoom pode ter expandido a área visível).
								_limitar_posicao_camera()

# --- NOVO: Claustro a posição da câmera dentro dos limites da cidade para
#     nunca revelar o fundo preto externo. Leva em conta o zoom atual: quanto
#     mais afastado (zoom menor), maior a área visível e menor a faixa onde
#     o centro da câmera pode ficar. ---
func _limitar_posicao_camera():
								if not camera: return
								# Tamanho da área visível em world units (depende do zoom)
								var half_view_w = (VIEWPORT_LARGURA / camera.zoom.x) / 2.0
								var half_view_h = (VIEWPORT_ALTURA / camera.zoom.y) / 2.0
								# Margem máxima que o centro da câmera pode se afastar da origem
								# sem revelar o vazio: limite_da_cidade - metade_do_viewport
								var max_x = CIDADE_LIMITE_X - half_view_w
								var max_y = CIDADE_LIMITE_Y - half_view_h
								# Se o viewport for maior que a cidade (zoom muito pequeno), o centro
								# fica preso na origem — usa max() com 0 para evitar limites negativos.
								max_x = max(max_x, 0.0)
								max_y = max(max_y, 0.0)
								var nova_pos = camera.position
								nova_pos.x = clamp(nova_pos.x, -max_x, max_x)
								nova_pos.y = clamp(nova_pos.y, -max_y, max_y)
								camera.position = nova_pos

func _posicionar_camera_inicio_cinematica() -> void:
	if camera == null:
		return
	camera.position = Vector2.ZERO
	var largura_cidade: float = CIDADE_LIMITE_X * 2.0
	var altura_cidade: float = CIDADE_LIMITE_Y * 2.0
	var zoom_min_visivel: float = max(
		VIEWPORT_LARGURA / largura_cidade,
		VIEWPORT_ALTURA / altura_cidade
	)
	var zoom_inicial: float = max(0.2, zoom_min_visivel)
	camera.zoom = Vector2(zoom_inicial, zoom_inicial)


func _iniciar_cinematica_abertura() -> void:
	if _cinematica_abertura_iniciada or not is_inside_tree():
		return
	_cinematica_abertura_iniciada = true
	_cinematica_abertura_concluida = false
	cinematica_rodando = true
	_posicionar_camera_inicio_cinematica()

	if is_instance_valid(_tween_cinematica_abertura):
		_tween_cinematica_abertura.kill()
	_tween_cinematica_abertura = create_tween()
	_tween_cinematica_abertura.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween_cinematica_abertura.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	_tween_cinematica_abertura.set_trans(Tween.TRANS_SINE)
	_tween_cinematica_abertura.set_ease(Tween.EASE_IN_OUT)
	_tween_cinematica_abertura.tween_interval(1.0)
	if camera != null and tabuleiro.has(0):
		_tween_cinematica_abertura.tween_property(camera, "position", tabuleiro[0]["pos"], 2.0)
		_tween_cinematica_abertura.parallel().tween_property(
			camera,
			"zoom",
			Vector2(1.2, 1.2),
			2.0
		)
	_tween_cinematica_abertura.tween_callback(_concluir_cinematica_abertura)

	# Segundo watchdog, curto e específico do Tween.
	_verificar_tween_cinematica.call_deferred()


func _verificar_tween_cinematica() -> void:
	await get_tree().create_timer(4.5).timeout
	if is_inside_tree() and not _cinematica_abertura_concluida:
		push_warning("[TABULEIRO] A cinemática não concluiu no prazo; finalizando com segurança.")
		_concluir_cinematica_abertura(true)


func _concluir_cinematica_abertura(forcar: bool = false) -> void:
	if _cinematica_abertura_concluida:
		return
	_cinematica_abertura_concluida = true
	cinematica_rodando = false

	if forcar and camera != null and tabuleiro.has(0):
		camera.position = Vector2(tabuleiro[0]["pos"])
		camera.zoom = Vector2(1.2, 1.2)

	var hud_control: Control = null
	if hud != null and is_instance_valid(hud):
		hud_control = hud.get_node_or_null("Control") as Control
	if hud_control == null:
		_notificar_tabuleiro_pronto_tutorial()
		_verificar_permissao_de_clique()
		return

	hud_control.visible = true
	if forcar:
		hud_control.modulate.a = 1.0
		_notificar_tabuleiro_pronto_tutorial()
		_verificar_permissao_de_clique()
		return

	var tween_hud: Tween = create_tween()
	tween_hud.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween_hud.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	tween_hud.set_trans(Tween.TRANS_QUAD)
	tween_hud.set_ease(Tween.EASE_OUT)
	tween_hud.tween_property(hud_control, "modulate:a", 1.0, 0.8)
	tween_hud.tween_callback(_notificar_tabuleiro_pronto_tutorial)
	tween_hud.tween_callback(_verificar_permissao_de_clique)


func _notificar_tabuleiro_pronto_tutorial() -> void:
	_emitir_evento_tutorial(
		"tabuleiro_pronto",
		{"jogador_id": jogador_atual_id, "rodada": rodada_atual}
	)


func focar_na_casa(id_casa: int):
								if not camera: return
								var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
								tween.tween_property(camera, "position", tabuleiro[id_casa]["pos"], 0.8)
								tween.parallel().tween_property(camera, "zoom", Vector2(1.2, 1.2), 0.8)

func _calcular_espiral():
								var idx_dir = 0
								var pos_atual = Vector2(0, 0)
								var posicoes_brutas = []
								
								for passos in sequencia_espiral:
																var dir = direcoes[idx_dir]
																for p in range(passos):
																								posicoes_brutas.append(pos_atual)
																								pos_atual += dir * PASSO_BASE
																idx_dir = (idx_dir + 1) % 4
								
								var min_pos = Vector2(99999, 99999)
								var max_pos = Vector2(-99999, -99999)
								for pb in posicoes_brutas:
																min_pos = min_pos.min(pb)
																max_pos = max_pos.max(pb)
								var centro = (min_pos + max_pos) / 2.0
								
								for i in range(40):
																tabuleiro[i]["pos"] = posicoes_brutas[i] - centro
																tabuleiro[i]["camada"] = _get_camada(i)
																tabuleiro[i]["escala"] = escala_camada[tabuleiro[i]["camada"]]

func _get_camada(idx: int) -> int:
								if idx <= 19: return 0
								elif idx <= 31: return 1
								elif idx <= 35: return 2
								else: return 3

func _get_tamanho_casa(id: int) -> Vector2:
								var escala = tabuleiro[id].get("escala", 1.0)
								return TAMANHO_UNICO * escala

func _get_ponto_borda(pos: Vector2, dir: Vector2, tamanho: Vector2) -> Vector2:
								if abs(dir.x) > abs(dir.y):
																return pos + Vector2(tamanho.x / 2.0, 0) if dir.x > 0 else pos - Vector2(tamanho.x / 2.0, 0)
								else:
																return pos + Vector2(0, tamanho.y / 2.0) if dir.y > 0 else pos - Vector2(0, tamanho.y / 2.0)

func _gerar_tabuleiro():
								_desenhar_ruas()
								for id_casa in tabuleiro.keys():
																_desenhar_casa(id_casa)

func spawnar_pino(id_jogador: String, cor_do_grupo: Color):
								var instancia = pino_cena.instantiate()
								add_child(instancia)
								
								if not instancia.has_method("configurar"):
																var script_pino = load("res://scenes/gameplay/tabuleiro/pino_personagem.gd")
																instancia.set_script(script_pino)
																instancia._ready()
																
								instancia.configurar(cor_do_grupo, id_jogador)
								
								if tabuleiro.has(0):
																instancia.position = tabuleiro[0]["pos"]
																instancia.casa_atual = 0
																_adicionar_pino_na_casa(instancia, 0)
								
								pinos_jogadores[id_jogador] = instancia

func _desenhar_ruas():
								var camada_ruas = get_node_or_null("Camada_01_Ruas")
								if not camada_ruas:
																camada_ruas = Node2D.new()
																camada_ruas.name = "Camada_01_Ruas"
																camada_ruas.z_index = -1
																add_child(camada_ruas)
								
								var rua = Line2D.new()
								rua.width = 28
								rua.default_color = Color(0.12, 0.12, 0.16, 1.0)
								rua.joint_mode = Line2D.LINE_JOINT_ROUND
								rua.z_index = -1
								
								for i in range(40):
																var atual = tabuleiro[i]["pos"]
																var prox = tabuleiro[(i + 1) % 40]["pos"]
																var dir = (prox - atual).normalized()
																var tam_atual = _get_tamanho_casa(i)
																var tam_prox = _get_tamanho_casa((i + 1) % 40)
																
																var ponto_saida = _get_ponto_borda(atual, dir, tam_atual)
																var ponto_chegada = _get_ponto_borda(prox, -dir, tam_prox)
																
																if i == 39:
																								var ponto_meio = (ponto_saida + ponto_chegada) / 2.0
																								rua.add_point(ponto_saida)
																								rua.add_point(ponto_meio)
																								rua.add_point(ponto_chegada)
																else:
																								rua.add_point(ponto_saida)
																								rua.add_point(ponto_chegada)
								camada_ruas.add_child(rua)

func _desenhar_casa(id: int):
	var dados = tabuleiro[id]
	var escala = dados.get("escala", 1.0)
	var tamanho = _get_tamanho_casa(id)
	var eh_tile_construcao = dados.get("tipo", "") == "propriedade"
	var cor_bairro: Color = cores_grupos.get(str(dados.get("grupo", "")), Color(0.72, 0.69, 0.62))

	var node = Node2D.new()
	node.position = dados["pos"]
	node.name = "Casa_" + str(id)
	node.z_index = 10

	if eh_tile_construcao:
		var tile_base = TextureRect.new()
		tile_base.name = "TileBase"
		tile_base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tile_base.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tile_base.size = tamanho * ESCALA_TILE_CONSTRUCAO
		tile_base.position = Vector2(-tile_base.size.x / 2.0, -tile_base.size.y / 2.0)
		tile_base.z_index = 0
		if ResourceLoader.exists(CAMINHO_TILE_CONSTRUCAO):
			var tex_tile = load(CAMINHO_TILE_CONSTRUCAO)
			if tex_tile:
				tile_base.texture = tex_tile
		else:
			var fallback_bg = ColorRect.new()
			fallback_bg.size = tamanho + Vector2(16, 16)
			fallback_bg.position = Vector2(-fallback_bg.size.x / 2.0, -fallback_bg.size.y / 2.0)
			fallback_bg.color = cor_bairro
			node.add_child(fallback_bg)
		node.add_child(tile_base)

		# A moldura identifica visualmente o bairro sem substituir a arte do chão.
		var borda_grupo = ReferenceRect.new()
		borda_grupo.name = "BordaGrupo"
		borda_grupo.size = tamanho + Vector2(12, 12)
		borda_grupo.position = Vector2(-borda_grupo.size.x / 2.0, -borda_grupo.size.y / 2.0)
		borda_grupo.editor_only = false
		borda_grupo.border_color = cor_bairro
		borda_grupo.border_width = 10.0 * escala
		borda_grupo.z_index = 2
		node.add_child(borda_grupo)

		var sombra = ColorRect.new()
		sombra.name = "SombraConstrucao"
		sombra.size = Vector2(tamanho.x * 0.48, tamanho.y * 0.10)
		sombra.position = Vector2(-sombra.size.x / 2.0, tamanho.y * 0.08)
		sombra.color = Color(0.0, 0.0, 0.0, 0.18)
		sombra.z_index = 1
		node.add_child(sombra)

		var container_construcao = Node2D.new()
		container_construcao.name = "ContainerConstrucao"
		container_construcao.z_index = 5
		node.add_child(container_construcao)

		var sprite_construcao = TextureRect.new()
		sprite_construcao.name = "SpriteConstrucao"
		sprite_construcao.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite_construcao.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite_construcao.size = Vector2(
			tamanho.x * ESCALA_LARGURA_SPRITE_CONSTRUCAO,
			tamanho.y * ESCALA_ALTURA_SPRITE_CONSTRUCAO
		)
		sprite_construcao.position = Vector2(
			-sprite_construcao.size.x / 2.0,
			tamanho.y * ANCORA_BASE_Y_SPRITE_CONSTRUCAO - sprite_construcao.size.y
		)
		sprite_construcao.z_index = 0
		container_construcao.add_child(sprite_construcao)
	else:
		var bg = ColorRect.new()
		bg.size = tamanho + Vector2(16, 16)
		bg.position = Vector2(-bg.size.x / 2, -bg.size.y / 2)
		bg.color = cor_bairro
		node.add_child(bg)

		var caminho_imagem = ""
		var img_especial = dados.get("imagem", "default.png")
		caminho_imagem = "res://assets/textures/casas/" + img_especial
		if ResourceLoader.exists(caminho_imagem):
			var tex = load(caminho_imagem)
			if tex:
				var tex_rect = TextureRect.new()
				tex_rect.texture = tex
				tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tex_rect.size = tamanho
				tex_rect.position = Vector2(-tamanho.x / 2, -tamanho.y / 2)
				node.add_child(tex_rect)

		var borda = ReferenceRect.new()
		borda.size = tamanho
		borda.position = Vector2(-tamanho.x / 2, -tamanho.y / 2)
		borda.editor_only = false
		borda.border_color = Color(1, 1, 1, 0.4)
		borda.border_width = 5.0 * escala
		node.add_child(borda)

	var faixa_dono = ColorRect.new()
	faixa_dono.size = Vector2(tamanho.x, 25 * escala)
	faixa_dono.position = Vector2(-tamanho.x / 2, (tamanho.y / 2) - faixa_dono.size.y)
	faixa_dono.name = "FaixaDono"
	faixa_dono.visible = false
	faixa_dono.z_index = 18 if eh_tile_construcao else 2
	node.add_child(faixa_dono)

	var label = Label.new()
	label.text = dados["nome"]
	label.custom_minimum_size = Vector2(tamanho.x - 16, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	if fonte_pixel:
		label.add_theme_font_override("font", fonte_pixel)
	if eh_tile_construcao:
		label.size = Vector2(tamanho.x - 20.0, 54.0 * escala)
		label.position = Vector2(-label.size.x / 2.0, -tamanho.y / 2.0 - 8.0 * escala)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", int(28 * escala))
		label.add_theme_color_override("font_color", Color.WHITE)
		label.z_index = 25
	else:
		label.position = Vector2(-tamanho.x / 2 + 8, -tamanho.y / 2 + 12)
		label.add_theme_font_size_override("font_size", int(44 * escala))
	node.add_child(label)

	var camada = get_node_or_null("Camada_02_Predios")
	if not camada:
		camada = Node2D.new()
		camada.name = "Camada_02_Predios"
		camada.z_index = 10
		add_child(camada)
	camada.add_child(node)
	if eh_tile_construcao:
		_atualizar_imagem_construcao(id)

func _atualizar_visual_dono(casa_id: int):
								var nome_casa = "Casa_" + str(casa_id)
								var camada = get_node_or_null("Camada_02_Predios")
								if not camada or not camada.has_node(nome_casa):
																return
								var node_casa = camada.get_node(nome_casa)
								if not node_casa.has_node("FaixaDono"):
																return
								var faixa = node_casa.get_node("FaixaDono")
								# --- CORREÇÃO: Se a propriedade não tem dono (registro_propriedades
								#     não tem a casa), ESCONDE a faixa visual. Antes, a função
								#     retornava sem fazer nada — a faixa continuava visível com a
								#     cor do falido, fazendo parecer que a prop ainda era dele. ---
								if not registro_propriedades.has(casa_id):
																faixa.visible = false
																return
								var dono_id = registro_propriedades[casa_id]
								faixa.color = cor_por_jogador.get(dono_id, Color.WHITE)
								faixa.visible = true

func _adicionar_pino_na_casa(pino: PinoPersonagem, casa_id: int) -> void:
	if pino == null or not is_instance_valid(pino):
		return
	var casa_segura: int = clampi(casa_id, 0, 39)
	if not pinos_por_casa.has(casa_segura):
		pinos_por_casa[casa_segura] = []
	var pinos_variant: Variant = pinos_por_casa[casa_segura]
	if not pinos_variant is Array:
		pinos_por_casa[casa_segura] = []
	var pinos_casa: Array = pinos_por_casa[casa_segura]
	if not pinos_casa.has(pino):
		pinos_casa.append(pino)
	_reposicionar_pinos_na_casa(casa_segura)


func _remover_pino_da_casa(pino: PinoPersonagem, casa_id: int) -> void:
	var casa_segura: int = clampi(casa_id, 0, 39)
	if not pinos_por_casa.has(casa_segura):
		return
	var pinos_variant: Variant = pinos_por_casa[casa_segura]
	if not pinos_variant is Array:
		pinos_por_casa.erase(casa_segura)
		return
	var pinos_casa: Array = pinos_variant
	pinos_casa.erase(pino)
	_reposicionar_pinos_na_casa(casa_segura)


func _validar_layout_tabuleiro() -> bool:
	for casa_id in range(40):
		if not tabuleiro.has(casa_id):
			return false
		var dados_variant: Variant = tabuleiro[casa_id]
		if not dados_variant is Dictionary:
			return false
		var dados_casa: Dictionary = dados_variant
		if not dados_casa.has("pos") or not dados_casa["pos"] is Vector2:
			return false
	return true


func _garantir_layout_tabuleiro() -> bool:
	if _layout_tabuleiro_pronto and _validar_layout_tabuleiro():
		return true

	# O snapshot pode chegar no mesmo instante em que a cena do convidado ainda
	# está concluindo sua inicialização. Recalcular o layout é determinístico e
	# restaura as chaves `pos`, `camada` e `escala` sem alterar o estado da partida.
	_calcular_espiral()
	_layout_tabuleiro_pronto = _validar_layout_tabuleiro()
	if not _layout_tabuleiro_pronto and not _aviso_layout_tabuleiro_emitido:
		_aviso_layout_tabuleiro_emitido = true
		push_error(
			"[TABULEIRO] Não foi possível reconstruir as posições das 40 casas."
		)
	return _layout_tabuleiro_pronto


func _obter_posicao_casa_segura(casa_id: int) -> Vector2:
	var casa_segura: int = clampi(casa_id, 0, 39)
	if _garantir_layout_tabuleiro():
		var dados_casa: Dictionary = tabuleiro[casa_segura]
		var pos_variant: Variant = dados_casa.get("pos", Vector2.ZERO)
		if pos_variant is Vector2:
			return pos_variant

	# Último recurso: usa a posição do nó visual já desenhado. Isso evita que
	# uma inconsistência transitória do dicionário interrompa a sincronização.
	var casa_node: Node2D = get_node_or_null(
		"Camada_02_Predios/Casa_%d" % casa_segura
	) as Node2D
	if casa_node != null:
		return casa_node.position
	return Vector2.ZERO


func _reposicionar_pinos_na_casa(casa_id: int) -> void:
	var casa_segura: int = clampi(casa_id, 0, 39)
	if not pinos_por_casa.has(casa_segura):
		return
	var pinos_variant: Variant = pinos_por_casa[casa_segura]
	if not pinos_variant is Array:
		pinos_por_casa.erase(casa_segura)
		return

	var pinos_validos: Array[PinoPersonagem] = []
	for pino_variant in pinos_variant:
		var pino: PinoPersonagem = pino_variant as PinoPersonagem
		if pino == null or not is_instance_valid(pino):
			continue
		pinos_validos.append(pino)
	pinos_por_casa[casa_segura] = pinos_validos

	var total: int = pinos_validos.size()
	if total == 0:
		return

	var pos_casa: Vector2 = _obter_posicao_casa_segura(casa_segura)
	var escala: float = 1.0
	if tabuleiro.has(casa_segura) and tabuleiro[casa_segura] is Dictionary:
		var dados_casa: Dictionary = tabuleiro[casa_segura]
		escala = float(dados_casa.get("escala", 1.0))
	var raio: float = 50.0 * escala

	if total == 1:
		pinos_validos[0].aplicar_offset(Vector2.ZERO, pos_casa)
		return

	for indice in range(total):
		var angulo: float = (2.0 * PI * float(indice)) / float(total)
		var offset: Vector2 = Vector2(cos(angulo), sin(angulo)) * raio
		pinos_validos[indice].aplicar_offset(offset, pos_casa)


func _verificar_permissao_de_clique() -> void:
	var meu_personagem_local: String = str(
		Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
	)

	# A votação pertence à Fase de Evento Global. Dados e ações só são
	# liberados quando o resultado terminar de ser exibido.
	if _acoes_bloqueadas_por_evento():
		hud.esconder_painel_dados()
		return
	_resolucao_turno_em_andamento = false

	# Safety reset: uma interrupção anterior nunca pode bloquear a nova rolagem.
	_processando_dados = false

	if _eh_jogador_bot(jogador_atual_id):
		hud.esconder_painel_dados()
		_emitir_evento_tutorial(
			"turno_bot_aguardando",
			{"jogador_id": jogador_atual_id}
		)
		call_deferred("_solicitar_turno_bot", jogador_atual_id)
		return

	if jogador_atual_id != meu_personagem_local:
		hud.esconder_painel_dados()
		return

	var dados_variant: Variant = dados_economia_jogadores.get(
		meu_personagem_local,
		{}
	)
	var dados_jogador: Dictionary = {}
	if dados_variant is Dictionary:
		dados_jogador = dados_variant
	if bool(dados_jogador.get("preso", false)):
		if hud.has_method("mostrar_painel_prisao"):
			hud.mostrar_painel_prisao(
				str(dados_jogador.get("nome", meu_personagem_local)),
				int(dados_jogador.get("cartas_sair_prisao", 0)) > 0
			)
		# O jogador também pode tentar obter uma dupla para sair.
		hud.mostrar_painel_dados()
	else:
		hud.mostrar_painel_dados()
		if meu_personagem_local == "diana":
			hud.container_dossie.visible = true


# ============================================================================
# GERAÇÃO PROCEDURAL DO FUNDO DA CIDADE
# ============================================================================
func _gerar_cidade_de_fundo():
								const COR_FUNDO = Color(0.05, 0.06, 0.08)
								const COR_PRACA = Color(0.18, 0.40, 0.22)
								const COR_PRACA_DETALHE = Color(0.22, 0.48, 0.28)
								
								var tex_rua = null
								var tex_rua_bifurcacao = null
								var tex_rua_boeiro = null
								var tex_rua_pedestre = null
								var tex_praca_borda = null
								var tex_praca_canto = null
								var tex_praca_interior = null
								var tex_praca_fonte = null
								
								# O chão dos lotes é independente das futuras construções. As peças de
								# topo e canto são rotacionadas para que todas as calçadas se encaixem.
								var tex_base_lote_interior: Texture2D = null
								var tex_base_lote_topo: Texture2D = null
								var tex_base_lote_canto: Texture2D = null
								
								var caminho_rua = "res://assets/textures/fundo/rua.png"
								var caminho_rua_bifurcacao = "res://assets/textures/fundo/rua_bifurcacao.png"
								var caminho_rua_boeiro = "res://assets/textures/fundo/rua_boeiro.png"
								var caminho_rua_pedestre = "res://assets/textures/fundo/rua_pedestre.png"
								var caminho_praca_borda = "res://assets/textures/fundo/calcada_praca_topo.png"
								var caminho_praca_canto = "res://assets/textures/fundo/calcada_praca_canto.png"
								var caminho_praca_interior = "res://assets/textures/fundo/praca_interior.png"
								var caminho_praca_fonte = "res://assets/textures/fundo/praca_centro_fonte.png"
								
								if ResourceLoader.exists(caminho_rua): tex_rua = load(caminho_rua)
								if ResourceLoader.exists(caminho_rua_bifurcacao): tex_rua_bifurcacao = load(caminho_rua_bifurcacao)
								if ResourceLoader.exists(caminho_rua_boeiro): tex_rua_boeiro = load(caminho_rua_boeiro)
								if ResourceLoader.exists(caminho_rua_pedestre): tex_rua_pedestre = load(caminho_rua_pedestre)
								if ResourceLoader.exists(caminho_praca_borda): tex_praca_borda = load(caminho_praca_borda)
								if ResourceLoader.exists(caminho_praca_canto): tex_praca_canto = load(caminho_praca_canto)
								if ResourceLoader.exists(caminho_praca_interior): tex_praca_interior = load(caminho_praca_interior)
								if ResourceLoader.exists(caminho_praca_fonte): tex_praca_fonte = load(caminho_praca_fonte)
								
								if ResourceLoader.exists(CAMINHO_BASE_LOTE_INTERIOR):
																tex_base_lote_interior = load(CAMINHO_BASE_LOTE_INTERIOR) as Texture2D
								if ResourceLoader.exists(CAMINHO_BASE_LOTE_TOPO):
																tex_base_lote_topo = load(CAMINHO_BASE_LOTE_TOPO) as Texture2D
								if ResourceLoader.exists(CAMINHO_BASE_LOTE_CANTO):
																tex_base_lote_canto = load(CAMINHO_BASE_LOTE_CANTO) as Texture2D

								var texturas_base_lote: Dictionary = {
																"interior": tex_base_lote_interior,
																"topo": tex_base_lote_topo,
																"canto": tex_base_lote_canto,
								}
								var texturas_construcoes_cidade: Array[Texture2D] = []
								for caminho_construcao: String in CAMINHOS_CONSTRUCOES_CIDADE:
																if not ResourceLoader.exists(caminho_construcao):
																								continue
																var textura_construcao: Texture2D = load(caminho_construcao) as Texture2D
																if textura_construcao != null:
																								texturas_construcoes_cidade.append(textura_construcao)
								
								var fundo_node: Node2D = get_node_or_null("Camada_Fundo_Cidade") as Node2D
								if fundo_node != null:
																fundo_node.queue_free()
								
								fundo_node = Node2D.new()
								fundo_node.name = "Camada_Fundo_Cidade"
								fundo_node.z_index = -4
								add_child(fundo_node)
								
								var fundo_base: ColorRect = ColorRect.new()
								fundo_base.color = COR_FUNDO
								fundo_base.size = Vector2(15000, 15000)
								fundo_base.position = Vector2(-7500, -7500)
								fundo_base.z_index = -2
								fundo_node.add_child(fundo_base)

								# Os prédios usam a base do sprite como origem do Y-sort. Assim as
								# construções das linhas inferiores cobrem corretamente as que estão atrás.
								var camada_construcoes: Node2D = Node2D.new()
								camada_construcoes.name = "Camada_Construcoes_Cidade"
								camada_construcoes.z_index = 0
								camada_construcoes.y_sort_enabled = true
								fundo_node.add_child(camada_construcoes)
								
								var grid_radius: int = CIDADE_RAIO_GRID
								var tile_size: int = CIDADE_TILE_SIZE
								var mapa_logico: Dictionary = {}
								var rng: RandomNumberGenerator = RandomNumberGenerator.new()
								rng.seed = 12345
								
								var raio_praca: int = 4
								var raio_anel: int = raio_praca + 1
								
								# =========================================================================
								# 1. MAPEAMENTO LÓGICO DA CIDADE
								# =========================================================================
								for x in range(-grid_radius, grid_radius + 1):
																for y in range(-grid_radius, grid_radius + 1):
																								var pos_grid = Vector2i(x, y)
																								
																								if abs(x) <= raio_praca and abs(y) <= raio_praca:
																																mapa_logico[pos_grid] = "praca"
																																continue
																								
																								var is_anel = (abs(x) == raio_anel and abs(y) <= raio_anel) or (abs(y) == raio_anel and abs(x) <= raio_anel)
																								var is_arteria = (x == 0 or y == 0)
																								var is_grade = (x % 5 == 0) or (y % 5 == 0)
																								
																								if is_anel or is_arteria or is_grade:
																																mapa_logico[pos_grid] = "rua"
																								else:
																																mapa_logico[pos_grid] = "lote"
								
								# =========================================================================
								# 1.5 IDENTIFICA BIFURCAÇÕES, PEDESTRES E BOEIROS
								# =========================================================================
								# A textura rua_pedestre.png tem a faixa NO TOPO (rotação = 0).
								# Rotações dos tiles pedestre em relação à bifurcação adjacente:
								#   Tile ABAIXO  → faixa no topo    → 0
								#   Tile ACIMA   → faixa na base    → PI
								#   Tile ESQUERDA→ faixa na direita → PI/2
								#   Tile DIREITA → faixa na esquerda→ -PI/2

								var tiles_pedestre = {}     # Vector2i → float (rotação)
								var tiles_bifurcacao = {}   # Vector2i → info de conexões
								var tiles_boeiro = {}       # Vector2i → float (rotação)
								
								# Primeiro passo: identifica todas as bifurcações
								for pos in mapa_logico.keys():
																if mapa_logico[pos] != "rua": continue
																var conexoes = _contar_conexoes_rua(pos, mapa_logico)
																if conexoes.total >= 3:
																								tiles_bifurcacao[pos] = conexoes
								
								# Segundo passo: marca tiles de pedestre com rotação correta
								for bif_pos in tiles_bifurcacao.keys():
																var conexoes = tiles_bifurcacao[bif_pos]
																
																if conexoes.cima:
																								var pos_anterior = bif_pos + Vector2i(0, -1)
																								if mapa_logico.get(pos_anterior) == "rua" and not tiles_bifurcacao.has(pos_anterior):
																																tiles_pedestre[pos_anterior] = PI
																if conexoes.baixo:
																								var pos_anterior = bif_pos + Vector2i(0, 1)
																								if mapa_logico.get(pos_anterior) == "rua" and not tiles_bifurcacao.has(pos_anterior):
																																tiles_pedestre[pos_anterior] = 0.0
																if conexoes.esquerda:
																								var pos_anterior = bif_pos + Vector2i(-1, 0)
																								if mapa_logico.get(pos_anterior) == "rua" and not tiles_bifurcacao.has(pos_anterior):
																																tiles_pedestre[pos_anterior] = PI / 2.0
																if conexoes.direita:
																								var pos_anterior = bif_pos + Vector2i(1, 0)
																								if mapa_logico.get(pos_anterior) == "rua" and not tiles_bifurcacao.has(pos_anterior):
																																tiles_pedestre[pos_anterior] = -PI / 2.0
								
								# Terceiro passo: boeiros aleatórios em retas (~6% por tile)
								const CHANCE_BOEIRO = 0.1
								for pos in mapa_logico.keys():
																if mapa_logico[pos] != "rua": continue
																if tiles_bifurcacao.has(pos): continue
																if tiles_pedestre.has(pos): continue
																
																var conexoes = _contar_conexoes_rua(pos, mapa_logico)
																var eh_reta_v = conexoes.cima and conexoes.baixo and not conexoes.esquerda and not conexoes.direita
																var eh_reta_h = conexoes.esquerda and conexoes.direita and not conexoes.cima and not conexoes.baixo
																
																if (eh_reta_v or eh_reta_h) and rng.randf() < CHANCE_BOEIRO:
																								tiles_boeiro[pos] = PI / 2.0 if eh_reta_h else 0.0
								
								# =========================================================================
								# 2. RENDERIZAÇÃO DOS BLOCOS BASE
								# =========================================================================
								for pos in mapa_logico.keys():
																var tipo = mapa_logico[pos]
																var world_pos = Vector2(pos.x, pos.y) * tile_size
																var cor_base = COR_FUNDO
																
																match tipo:
																								"praca":
																																var abs_x: int = abs(pos.x)
																																var abs_y: int = abs(pos.y)
																																var eh_centro: bool = (pos.x == 0 and pos.y == 0)
																																var eh_borda: bool = (abs_x == raio_praca or abs_y == raio_praca)
																																var eh_canto: bool = (abs_x == raio_praca and abs_y == raio_praca)
																																
																																var tex_a_usar = null
																																var rotacao: float = 0.0
																																
																																if eh_centro and tex_praca_fonte:
																																								tex_a_usar = tex_praca_fonte
																																								rotacao = 0.0
																																elif eh_canto and tex_praca_canto:
																																								tex_a_usar = tex_praca_canto
																																								if pos.x > 0 and pos.y < 0: rotacao = 0.0
																																								elif pos.x > 0 and pos.y > 0: rotacao = PI / 2.0
																																								elif pos.x < 0 and pos.y > 0: rotacao = PI
																																								elif pos.x < 0 and pos.y < 0: rotacao = -PI / 2.0
																																elif eh_borda and tex_praca_borda:
																																								tex_a_usar = tex_praca_borda
																																								if pos.y == -raio_praca: rotacao = 0.0
																																								elif pos.x == raio_praca: rotacao = PI / 2.0
																																								elif pos.y == raio_praca: rotacao = PI
																																								elif pos.x == -raio_praca: rotacao = -PI / 2.0
																																elif tex_praca_interior:
																																								tex_a_usar = tex_praca_interior
																																								rotacao = 0.0
																																
																																if tex_a_usar:
																																								var sprite = Sprite2D.new()
																																								sprite.texture = tex_a_usar
																																								var escala = tile_size / float(tex_a_usar.get_width())
																																								sprite.scale = Vector2(escala, escala)
																																								sprite.position = world_pos
																																								sprite.rotation = rotacao
																																								sprite.z_index = -1
																																								fundo_node.add_child(sprite)
																																else:
																																								cor_base = COR_PRACA if rng.randf() > 0.3 else COR_PRACA_DETALHE
																																								_criar_bloco(fundo_node, world_pos, tile_size, cor_base, -4.0)
																																continue
																																
																								"rua":
																																var tex_a_usar = null
																																var rotacao: float = 0.0
																																
																																# Faixa de pedestre — rotação aponta para a bifurcação adjacente
																																if tiles_pedestre.has(pos):
																																								tex_a_usar = tex_rua_pedestre
																																								rotacao = tiles_pedestre[pos]
																																
																																# Bifurcação (T ou +)
																																elif tiles_bifurcacao.has(pos):
																																								tex_a_usar = tex_rua_bifurcacao
																																								rotacao = _calcular_rotacao_bifurcacao(tiles_bifurcacao[pos])
																																
																																# Boeiro aleatório em reta
																																elif tiles_boeiro.has(pos):
																																								tex_a_usar = tex_rua_boeiro
																																								rotacao = tiles_boeiro[pos]
																																
																																# Reta ou curva
																																else:
																																								var conexoes = _contar_conexoes_rua(pos, mapa_logico)
																																								
																																								if conexoes.total <= 1:
																																																tex_a_usar = tex_rua_boeiro
																																																if conexoes.esquerda or conexoes.direita:
																																																								rotacao = PI / 2.0
																																								elif conexoes.cima and conexoes.baixo and not conexoes.esquerda and not conexoes.direita:
																																																tex_a_usar = tex_rua
																																																rotacao = 0.0
																																								elif conexoes.esquerda and conexoes.direita and not conexoes.cima and not conexoes.baixo:
																																																tex_a_usar = tex_rua
																																																rotacao = PI / 2.0
																																								else:
																																																tex_a_usar = tex_rua
																																																if conexoes.cima and conexoes.direita: rotacao = 0.0
																																																elif conexoes.direita and conexoes.baixo: rotacao = PI / 2.0
																																																elif conexoes.baixo and conexoes.esquerda: rotacao = PI
																																																elif conexoes.esquerda and conexoes.cima: rotacao = -PI / 2.0
																																																else: rotacao = 0.0
																																
																																if tex_a_usar:
																																								var sprite = Sprite2D.new()
																																								sprite.texture = tex_a_usar
																																								var escala = tile_size / float(tex_a_usar.get_width())
																																								sprite.scale = Vector2(escala, escala)
																																								sprite.position = world_pos
																																								sprite.rotation = rotacao
																																								sprite.z_index = -1
																																								fundo_node.add_child(sprite)
																																else:
																																								_criar_bloco(fundo_node, world_pos, tile_size, Color(0.22, 0.23, 0.25), -1.0)
																																continue
																																
																								# Cada lote recebe primeiro a base rotacionada e sempre uma
																								# construção sem rotação, ancorada pela entrada na parte baixa do lote.
																								"lote":
																										var info_tile: Dictionary = _classificar_variante_base_cidade(pos, mapa_logico)
																										var variante: String = str(info_tile.get("variante", "interior"))
																										var rotacao_tile: float = float(info_tile.get("rotacao", 0.0))
																										var textura_variant: Variant = texturas_base_lote.get(variante)
																										if textura_variant is Texture2D:
																												var textura_base: Texture2D = textura_variant as Texture2D
																												var sprite_base: Sprite2D = Sprite2D.new()
																												sprite_base.texture = textura_base
																												var escala_base: float = tile_size / float(textura_base.get_width())
																												sprite_base.scale = Vector2(escala_base, escala_base)
																												sprite_base.position = world_pos
																												sprite_base.rotation = rotacao_tile
																												sprite_base.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
																												sprite_base.z_index = -1
																												fundo_node.add_child(sprite_base)
																										else:
																												_criar_bloco(fundo_node, world_pos, tile_size, Color(0.48, 0.49, 0.51), 0.0)

																										if not texturas_construcoes_cidade.is_empty():
																												var indice_construcao: int = _obter_indice_construcao_cidade(pos, texturas_construcoes_cidade.size())
																												if indice_construcao >= 0:
																														var textura_predio: Texture2D = texturas_construcoes_cidade[indice_construcao]
																														var largura_textura: float = float(textura_predio.get_width())
																														var altura_textura: float = float(textura_predio.get_height())
																														if largura_textura > 0.0 and altura_textura > 0.0:
																																var escala_largura: float = (float(tile_size) * LARGURA_RELATIVA_CONSTRUCAO_CIDADE) / largura_textura
																																var escala_altura: float = (float(tile_size) * ALTURA_MAXIMA_RELATIVA_CONSTRUCAO_CIDADE) / altura_textura
																																var escala_predio: float = minf(escala_largura, escala_altura)
																																var sprite_predio: Sprite2D = Sprite2D.new()
																																sprite_predio.texture = textura_predio
																																sprite_predio.scale = Vector2(escala_predio, escala_predio)
																																sprite_predio.offset = Vector2(0.0, -altura_textura / 2.0)
																																sprite_predio.rotation = 0.0
																																sprite_predio.position = world_pos + Vector2(0.0, roundf(float(tile_size) * OFFSET_BASE_RELATIVO_CONSTRUCAO_CIDADE))
																																sprite_predio.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
																																sprite_predio.z_index = 0
																																camada_construcoes.add_child(sprite_predio)


# Mantém a mesma ocupação e a mesma escolha de sprites em todas as máquinas,
# inclusive no modo online, sem depender da ordem interna de um Dictionary.
func _hash_posicao_construcao_cidade(pos: Vector2i, sal: int) -> int:
	var valor: int = pos.x * 92837111
	valor = valor ^ (pos.y * 689287499)
	valor = valor ^ (sal * 283923481)
	valor = valor ^ (valor >> 13)
	return valor * 127412617


func _modulo_positivo_cidade(valor: int, divisor: int) -> int:
	if divisor <= 0:
		return 0
	var resultado: int = valor % divisor
	if resultado < 0:
		resultado += divisor
	return resultado


func _obter_indice_construcao_cidade(pos: Vector2i, quantidade: int) -> int:
	if quantidade <= 0:
		return -1
	return _modulo_positivo_cidade(_hash_posicao_construcao_cidade(pos, 29), quantidade)


# ============================================================================
# FUNÇÕES DE ANÁLISE DE RUA
# ============================================================================
func _contar_conexoes_rua(pos: Vector2i, mapa: Dictionary) -> Dictionary:
								var conexoes = {
																"cima": false,
																"baixo": false,
																"esquerda": false,
																"direita": false,
																"total": 0
								}
								
								if mapa.get(pos + Vector2i(0, -1)) == "rua":
																conexoes.cima = true
																conexoes.total += 1
								if mapa.get(pos + Vector2i(0, 1)) == "rua":
																conexoes.baixo = true
																conexoes.total += 1
								if mapa.get(pos + Vector2i(-1, 0)) == "rua":
																conexoes.esquerda = true
																conexoes.total += 1
								if mapa.get(pos + Vector2i(1, 0)) == "rua":
																conexoes.direita = true
																conexoes.total += 1
								
								return conexoes

func _calcular_rotacao_bifurcacao(conexoes: Dictionary) -> float:
								if conexoes.cima and conexoes.baixo and conexoes.esquerda and conexoes.direita:
																return 0.0
								if not conexoes.cima: return 0.0
								elif not conexoes.baixo: return PI
								elif not conexoes.esquerda: return PI / 2.0
								elif not conexoes.direita: return -PI / 2.0
								return 0.0


# ============================================================================
# CLASSIFICAÇÃO DAS BASES DOS LOTES DA CIDADE
# ============================================================================
# Identifica se um lote usa a base "interior", "topo" ou "canto" conforme
# suas bordas públicas. Isso monta quadras completas sem incluir construções.
#
# Convenção das texturas:
#   - interior: concreto sólido, sem calçada
#   - topo:     calçada na borda superior (1 rua adjacente)
#   - canto:    calçada em L no canto superior direito (2 ruas adjacentes em L)
#
# Rotações aplicadas (sentido horário, padrão Godot Sprite2D.rotation):
#   TOPO (calçada no norte por padrão):
#     - rua ao norte (cima)    → rotacao = 0.0       (calçada continua no norte)
#     - rua ao leste (direita) → rotacao = PI / 2    (calçada rotaciona para leste)
#     - rua ao sul (baixo)     → rotacao = PI        (calçada rotaciona para sul)
#     - rua ao oeste (esquerda)→ rotacao = -PI / 2   (calçada rotaciona para oeste)
#
#   CANTO (calçada no canto NE por padrão — norte + leste):
#     - ruas NE (cima + direita)        → rotacao = 0.0
#     - ruas SE (direita + baixo)       → rotacao = PI / 2
#     - ruas SW (baixo + esquerda)      → rotacao = PI
#     - ruas NW (esquerda + cima)       → rotacao = -PI / 2
#
# Retorna: { "variante": String, "rotacao": float }
func _classificar_variante_base_cidade(pos: Vector2i, mapa: Dictionary) -> Dictionary:
								var tem_rua_cima: bool = _eh_rua_ou_praca(mapa.get(pos + Vector2i(0, -1)))
								var tem_rua_baixo: bool = _eh_rua_ou_praca(mapa.get(pos + Vector2i(0, 1)))
								var tem_rua_esquerda: bool = _eh_rua_ou_praca(mapa.get(pos + Vector2i(-1, 0)))
								var tem_rua_direita: bool = _eh_rua_ou_praca(mapa.get(pos + Vector2i(1, 0)))
								
								var variante: String = "interior"
								var rotacao: float = 0.0
								
								# Conta quantos lados tem rua/praca
								var lados_com_rua: int = 0
								if tem_rua_cima: lados_com_rua += 1
								if tem_rua_baixo: lados_com_rua += 1
								if tem_rua_esquerda: lados_com_rua += 1
								if tem_rua_direita: lados_com_rua += 1
								
								if lados_com_rua == 0:
																# Miolo da quadra: base sólida, sem calçada.
																variante = "interior"
																rotacao = 0.0
								elif lados_com_rua == 1:
																# Apenas 1 rua adjacente → variante TOPO
																variante = "topo"
																if tem_rua_cima:
																								rotacao = 0.0
																elif tem_rua_direita:
																								rotacao = PI / 2.0
																elif tem_rua_baixo:
																								rotacao = PI
																elif tem_rua_esquerda:
																								rotacao = -PI / 2.0
								else:
																# 2+ ruas adjacentes → variante CANTO
																# Procura por um par de ruas adjacentes (formando um canto).
																# Prioriza NE > SE > SW > NW para consistência visual.
																variante = "canto"
																if tem_rua_cima and tem_rua_direita:
																								rotacao = 0.0          # Canto NE
																elif tem_rua_direita and tem_rua_baixo:
																								rotacao = PI / 2.0      # Canto SE
																elif tem_rua_baixo and tem_rua_esquerda:
																								rotacao = PI            # Canto SW
																elif tem_rua_esquerda and tem_rua_cima:
																								rotacao = -PI / 2.0     # Canto NW
																else:
																								# Casos especiais: 2 lados opostos (passagem) ou 3+ lados.
																								# Para passagem (N+S ou E+W): usa TOPO voltado para o norte ou leste.
																								# Para 3+ lados: usa CANTO no primeiro par encontrado.
																								if tem_rua_cima and tem_rua_baixo and not tem_rua_esquerda and not tem_rua_direita:
																																variante = "topo"
																																rotacao = 0.0
																								elif tem_rua_esquerda and tem_rua_direita and not tem_rua_cima and not tem_rua_baixo:
																																variante = "topo"
																																rotacao = PI / 2.0
																								elif tem_rua_cima:
																																variante = "topo"
																																rotacao = 0.0
																								elif tem_rua_direita:
																																variante = "topo"
																																rotacao = PI / 2.0
																								elif tem_rua_baixo:
																																variante = "topo"
																																rotacao = PI
																								elif tem_rua_esquerda:
																																variante = "topo"
																																rotacao = -PI / 2.0
								
								return {"variante": variante, "rotacao": rotacao}


# Helper: verifica se um valor do mapa_logico representa uma área pública
# (rua ou praça) que exige calçada na borda do lote.
# Tiles fora do mapa (null) também são tratados como "rua" para que os
# lotes nas bordas externas da cidade tenham calçada voltada para fora.
func _eh_rua_ou_praca(tipo: Variant) -> bool:
								if tipo == null:
																return true  # borda externa do mapa
								var s = str(tipo)
								return s == "rua" or s == "praca"


# ============================================================================
# FUNÇÕES AUXILIARES DE CONSTRUÇÃO VETORIAL
# ============================================================================
func _criar_bloco(pai: Node2D, pos: Vector2, tamanho: float, cor: Color, altura_sombra: float = 0.0):
								if altura_sombra > 0:
																var sombra = ColorRect.new()
																sombra.color = Color(0, 0, 0, 0.25)
																sombra.size = Vector2(tamanho, tamanho)
																sombra.position = pos - Vector2(tamanho/2, tamanho/2) + Vector2(altura_sombra * 3, altura_sombra * 3)
																sombra.z_index = 1
																pai.add_child(sombra)
								
								var bloco = ColorRect.new()
								bloco.color = cor
								bloco.size = Vector2(tamanho - 4, tamanho - 4)
								bloco.position = pos - Vector2((tamanho - 4)/2, (tamanho - 4)/2)
								bloco.z_index = 2
								pai.add_child(bloco)

func _criar_arvore(pai: Node2D, pos: Vector2):
								var tronco = ColorRect.new()
								tronco.color = Color(0.35, 0.25, 0.15)
								tronco.size = Vector2(10, 14)
								tronco.position = pos - Vector2(5, 7)
								tronco.z_index = 4
								pai.add_child(tronco)
								
								var tamanhos = [22, 18, 20]
								var offsets = [Vector2(-8, -18), Vector2(2, -16), Vector2(-6, -12)]
								for i in range(3):
																var folha = ColorRect.new()
																folha.color = Color(0.15, 0.55, 0.25)
																var s = tamanhos[i]
																folha.size = Vector2(s, s)
																folha.position = pos + offsets[i] - Vector2(s/2, s/2)
																folha.z_index = 4
																pai.add_child(folha)

func _criar_poste(pai: Node2D, pos: Vector2):
								var poste = ColorRect.new()
								poste.color = Color(0.60, 0.60, 0.55)
								poste.size = Vector2(6, 28)
								poste.position = pos - Vector2(3, 14)
								poste.z_index = 4
								pai.add_child(poste)
								
								var luz = ColorRect.new()
								luz.color = Color(0.95, 0.85, 0.50)
								luz.size = Vector2(12, 8)
								luz.position = pos - Vector2(6, 18)
								luz.z_index = 4
								pai.add_child(luz)

func _criar_carro(pai: Node2D, pos: Vector2, direcao: Vector2, cor: Color, rng: RandomNumberGenerator):
								var carro = Node2D.new()
								carro.position = pos + Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 60))
								carro.z_index = 4
								carro.rotation = direcao.angle()
								pai.add_child(carro)
								
								var corpo = ColorRect.new()
								corpo.color = cor
								corpo.size = Vector2(36, 18)
								corpo.position = Vector2(-18, -9)
								carro.add_child(corpo)
								
								var teto = ColorRect.new()
								teto.color = Color(0.3, 0.35, 0.4)
								teto.size = Vector2(18, 14)
								teto.position = Vector2(-6, -7)
								carro.add_child(teto)
								
								var farol_e = ColorRect.new()
								farol_e.color = Color(0.9, 0.9, 0.7)
								farol_e.size = Vector2(4, 6)
								farol_e.position = Vector2(14, -7)
								carro.add_child(farol_e)
								
								var farol_d = ColorRect.new()
								farol_d.color = Color(0.9, 0.9, 0.7)
								farol_d.size = Vector2(4, 6)
								farol_d.position = Vector2(14, 1)
								carro.add_child(farol_d)

# ============================================================================
# SISTEMA DE OBRAS (CASAS E HOTÉIS)
# ============================================================================
func _grupo_zoneamento_permite_hotel_com_3_casas(grupo: String) -> bool:
	return _tem_efeito_temporario("zoneamento_" + grupo.to_lower().replace("-", "_"))

func _nivel_destino_construcao(casa_id: int) -> int:
	if not tabuleiro.has(casa_id):
		return 0
	var nivel_atual = int(tabuleiro[casa_id].get("nivel", 0))
	var grupo = str(tabuleiro[casa_id].get("grupo", ""))
	# Nova Lei de Zoneamento: no grupo beneficiado, 3 casas já permitem hotel.
	if nivel_atual == 3 and _grupo_zoneamento_permite_hotel_com_3_casas(grupo):
		return 5
	return min(5, nivel_atual + 1)

func _calcular_custo_construcao(id_jogador: String, casa_id: int) -> int:
	if not tabuleiro.has(casa_id) or not dados_economia_jogadores.has(id_jogador):
		return 0
	var dados_casa = tabuleiro[casa_id]
	var nivel_atual = int(dados_casa.get("nivel", 0))
	var custo = int(dados_casa.get("preco", 0) * 0.5 * (nivel_atual + 1))

	if id_jogador == "mira":
		custo = int(ceil(custo * 0.8))
	if dados_economia_jogadores[id_jogador].get("mutirao_ativo", false):
		custo = int(ceil(custo * 0.6))
	for efeito in _efeitos_ativos_por_tipo("multiplicador_custo_construcao"):
		if not _efeito_aplica_na_casa(efeito, casa_id):
			continue
		custo = int(ceil(custo * float(efeito.get("multiplicador", 1.0))))
	return max(0, custo)

func _motivo_construcao_invalida(id_jogador: String, casa_id: int, usar_carta_gratis: bool = false) -> String:
	if not dados_economia_jogadores.has(id_jogador):
		return "Jogador inválido."
	if not tabuleiro.has(casa_id):
		return "Propriedade inválida."
	var dados_casa: Dictionary = tabuleiro[casa_id]
	var dados_jogador: Dictionary = dados_economia_jogadores[id_jogador]
	if dados_casa.get("tipo", "") != "propriedade":
		return "Casas e hotéis só podem ser construídos em propriedades."
	if not registro_propriedades.has(casa_id) or registro_propriedades[casa_id] != id_jogador:
		return "Esta propriedade não pertence a você."
	if dados_jogador.get("falido", false):
		return "Jogadores falidos não podem construir."
	if int(dados_casa.get("nivel", 0)) >= 5:
		return "Esta propriedade já possui hotel."
	if not _construcoes_visuais_em_andamento.is_empty():
		return "Aguarde a animação da obra atual terminar."
	if dados_casa.get("hipotecada", false):
		return "Resgate a hipoteca antes de construir."
	if _construcao_bloqueada_por_efeito(id_jogador, casa_id):
		return "Construções estão bloqueadas por um efeito ativo."
	if usar_carta_gratis and int(dados_jogador.get("cartas_construcao_gratis", 0)) <= 0:
		return "Você não possui uma carta de construção gratuita."
	if (
		not usar_carta_gratis
		and not dados_jogador.get("mutirao_ativo", false)
		and not _pode_construir(id_jogador, str(dados_casa.get("grupo", "")))
	):
		return "Você precisa do monopólio deste grupo (Mira precisa de 2 propriedades)."
	if not usar_carta_gratis:
		var custo: int = _calcular_custo_construcao(id_jogador, casa_id)
		if int(dados_jogador.get("dinheiro", 0)) < custo:
			return "Saldo insuficiente. Custo: $" + str(custo) + "."
	return ""


func _on_hud_solicitar_construcao(casa_id: int):
	if _acao_bloqueada_por_eleicao(true):
		return
	var meu_personagem_local = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
	if meu_personagem_local == "" or not dados_economia_jogadores.has(meu_personagem_local):
		return
	if jogador_atual_id != meu_personagem_local:
		if hud and hud.has_method("mostrar_aviso_turno"):
			hud.mostrar_aviso_turno("Aguarde sua vez para construir!")
		return

	var usar_carta_gratis: bool = int(
		dados_economia_jogadores[meu_personagem_local].get("cartas_construcao_gratis", 0)
	) > 0
	var motivo: String = _motivo_construcao_invalida(
		meu_personagem_local,
		casa_id,
		usar_carta_gratis
	)
	if motivo != "":
		if hud and hud.has_method("mostrar_aviso_turno"):
			hud.mostrar_aviso_turno(motivo)
		elif pinos_jogadores.has(meu_personagem_local):
			pinos_jogadores[meu_personagem_local].mostrar_texto_flutuante(motivo, Color(0.9, 0.3, 0.3))
		return
	OnlineTransport.send_all(self, &"_efetuar_construcao_rede", [meu_personagem_local, casa_id], false, true)


@rpc("any_peer", "call_local")
func _efetuar_construcao_rede(id_jogador: String, casa_id: int):
	if _acoes_bloqueadas_por_evento():
		return
	if not dados_economia_jogadores.has(id_jogador):
		return

	# O uso da carta é recalculado em todos os peers a partir do estado
	# sincronizado, em vez de confiar em um valor enviado pelo cliente.
	var dados_jogador: Dictionary = dados_economia_jogadores[id_jogador]
	var usar_carta_gratis: bool = int(dados_jogador.get("cartas_construcao_gratis", 0)) > 0
	var motivo: String = _motivo_construcao_invalida(id_jogador, casa_id, usar_carta_gratis)
	if motivo != "":
		if pinos_jogadores.has(id_jogador):
			pinos_jogadores[id_jogador].mostrar_texto_flutuante(motivo, Color(0.9, 0.3, 0.3))
		return

	_construcoes_visuais_em_andamento[casa_id] = true
	_atualizar_menu_construcao()

	var dados_casa: Dictionary = tabuleiro[casa_id]
	var custo_casa: int = 0 if usar_carta_gratis else _calcular_custo_construcao(id_jogador, casa_id)
	var nivel_anterior: int = int(dados_casa.get("nivel", 0))
	var nivel_destino: int = _nivel_destino_construcao(casa_id)

	if usar_carta_gratis:
		dados_jogador["cartas_construcao_gratis"] = maxi(
			0,
			int(dados_jogador.get("cartas_construcao_gratis", 0)) - 1
		)
	else:
		dados_jogador["dinheiro"] = int(dados_jogador.get("dinheiro", 0)) - custo_casa
		if dados_jogador.get("mutirao_ativo", false):
			dados_jogador["mutirao_ativo"] = false

	dados_casa["nivel"] = nivel_destino
	var nome_construtor_hist: String = str(dados_jogador.get("nome", id_jogador))
	var nome_prop_constr_hist: String = str(dados_casa.get("nome", "propriedade")).replace("\n", " ")
	if usar_carta_gratis:
		_registrar_acao(
			"construcao",
			"%s elevou %s ao nível %d usando uma carta de construção gratuita." % [
				nome_construtor_hist,
				nome_prop_constr_hist,
				nivel_destino
			],
			id_jogador
		)
	else:
		_registrar_acao(
			"construcao",
			"%s elevou %s ao nível %d por $%d." % [
				nome_construtor_hist,
				nome_prop_constr_hist,
				nivel_destino,
				custo_casa
			],
			id_jogador
		)

	if pinos_jogadores.has(id_jogador):
		if usar_carta_gratis:
			pinos_jogadores[id_jogador].mostrar_texto_flutuante("OBRA GRÁTIS!", Color(0.48, 1.0, 0.58))
		else:
			pinos_jogadores[id_jogador].mostrar_texto_flutuante("OBRA: -$" + str(custo_casa), Color(0.8, 0.6, 0.2))

	_atualizar_hud_ciclo_turno()
	var pos_casa: Vector2 = dados_casa.get("pos", Vector2.ZERO)
	var cor_grupo: Color = cores_grupos.get(dados_casa.get("grupo", ""), Color(0.6, 0.5, 0.3))

	await Animacoes.animacao_construcao_completa(self, pos_casa, cor_grupo, DURACAO_ANIMACAO_OBRA)

	if not is_inside_tree() or not tabuleiro.has(casa_id):
		_construcoes_visuais_em_andamento.erase(casa_id)
		return

	_atualizar_imagem_construcao(casa_id)
	var camada = get_node_or_null("Camada_02_Predios")
	if camada and camada.has_node("Casa_" + str(casa_id)):
		var node_casa = camada.get_node("Casa_" + str(casa_id))
		if node_casa.has_node("ContainerConstrucao"):
			var alvo_animacao := node_casa.get_node("ContainerConstrucao") as Node2D
			if alvo_animacao:
				await Animacoes.construcao_aparecer_suave(alvo_animacao, DURACAO_SURGIMENTO_CONSTRUCAO)

	_construcoes_visuais_em_andamento.erase(casa_id)

	if nivel_destino == 5 and nivel_anterior < 5:
		Animacoes.flash_de_tela(hud.get_node("Control"), Color(1.0, 0.85, 0.15, 0.6), 0.7)
		Animacoes.tremer_camera(camera, 6.0, 0.5)
		Animacoes.explosao_particulas(self, pos_casa, Color(1.0, 0.85, 0.15), 20, 100)
		if pinos_jogadores.has(id_jogador):
			pinos_jogadores[id_jogador].celebrar()
		Animacoes.banner_cinematico(hud.get_node("Control"), "HOTEL CONSTRUÍDO!", dados_casa["nome"], Color(1.0, 0.85, 0.15), 1.5)

	_atualizar_hud_ciclo_turno()
	_atualizar_hud_minha_casa()
	_atualizar_menu_construcao()
	_emitir_evento_tutorial(
		"construcao_realizada",
		{
			"jogador_id": id_jogador,
			"casa_id": casa_id,
			"nivel": nivel_destino,
			"custo": custo_casa,
		}
	)


func _atualizar_imagem_construcao(casa_id: int):
	if not tabuleiro.has(casa_id):
		return
	var dados = tabuleiro[casa_id]
	if dados.get("tipo", "") != "propriedade":
		return
	var nome_casa = "Casa_" + str(casa_id)
	var camada = get_node_or_null("Camada_02_Predios")
	if not camada or not camada.has_node(nome_casa):
		return
	var node_casa = camada.get_node(nome_casa)
	if not node_casa.has_node("ContainerConstrucao/SpriteConstrucao"):
		return
	var sprite_construcao = node_casa.get_node("ContainerConstrucao/SpriteConstrucao")
	var nivel = int(dados.get("nivel", 0))
	if nivel <= 0:
		sprite_construcao.visible = false
		sprite_construcao.texture = null
		return
	var caminho_imagem = CAMINHO_SPRITE_CONSTRUCAO_BASE + str(clamp(nivel, 1, 5)) + ".png"
	if ResourceLoader.exists(caminho_imagem):
		var tex = load(caminho_imagem)
		if tex:
			sprite_construcao.texture = tex
			sprite_construcao.visible = true
	else:
		sprite_construcao.visible = false
		sprite_construcao.texture = null

func _destruir_casa_aleatoria(jogador_id: String):
								# Encontra propriedades do jogador com nível > 0
								var candidatas = []
								for id in tabuleiro.keys():
																if registro_propriedades.has(id) and registro_propriedades[id] == jogador_id:
																								if tabuleiro[id].get("nivel", 0) > 0:
																																candidatas.append(id)
								if candidatas.is_empty():
																if pinos_jogadores.has(jogador_id):
																								pinos_jogadores[jogador_id].mostrar_texto_flutuante("SEM CASAS PARA DESTRUIR", Color(0.8, 0.6, 0.2))
																return
								var id_destruir = candidatas.pick_random()
								tabuleiro[id_destruir]["nivel"] -= 1
								_atualizar_imagem_construcao(id_destruir)
								if pinos_jogadores.has(jogador_id):
																pinos_jogadores[jogador_id].mostrar_texto_flutuante("CASA DESTRUÍDA!", Color(0.9, 0.3, 0.3))
																pinos_jogadores[jogador_id].tremer(5.0, 0.4)
								var pos_casa = tabuleiro[id_destruir].get("pos", Vector2.ZERO)
								Animacoes.explosao_particulas(self, pos_casa, Color(0.9, 0.3, 0.2), 14, 60)

func _contar_hoteis_do_jogador(jogador_id: String) -> int:
								var count = 0
								for id in tabuleiro.keys():
																if registro_propriedades.has(id) and registro_propriedades[id] == jogador_id:
																								if tabuleiro[id].get("nivel", 0) == 5:
																																count += 1
								return count

func _contar_hipotecas_do_jogador(jogador_id: String) -> int:
								var count = 0
								for id in tabuleiro.keys():
																if registro_propriedades.has(id) and registro_propriedades[id] == jogador_id:
																								if tabuleiro[id].get("hipotecada", false):
																																count += 1
								return count

func _reduzir_nivel_em_grupo(jogador_id: String, grupo: String, qtd: int):
								for id in tabuleiro.keys():
																if tabuleiro[id].get("grupo") == grupo and registro_propriedades.has(id) and registro_propriedades[id] == jogador_id:
																								if tabuleiro[id].get("nivel", 0) > 0:
																																# --- BUG #8 FIX: Resistência Estrutural da Mira protege TODOS
																																#     os eventos que reduzem nível de construção, não só o
																																#     Vendaval. Antes, só o Vendaval tinha o desconto de 50%
																																#     codificado inline; o Apagão Digital chamava esta função
																																#     sem proteção. Agora a Mira perde apenas METADE do nível
																																#     (arredondado para baixo) em qualquer evento destrutivo. ---
																																if jogador_id == "mira":
																																								var reducao_mira = max(1, int(qtd * 0.5))
																																								tabuleiro[id]["nivel"] = max(0, tabuleiro[id]["nivel"] - reducao_mira)
																																								if pinos_jogadores.has("mira"):
																																																pinos_jogadores["mira"].mostrar_texto_flutuante("RESISTÊNCIA ESTRUTURAL!", Color(0.3, 0.9, 0.3))
																																else:
																																								tabuleiro[id]["nivel"] = max(0, tabuleiro[id]["nivel"] - qtd)
																																_atualizar_imagem_construcao(id)

# ============================================================================
# NOVO: SISTEMA DE HABILIDADES ATIVAS (6 personagens)
# ============================================================================
# Cooldowns (turnos): Yasmin=5, Breno=5, Mira=4, Igor=6, Diana=3, Kofi=4
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
func _on_hud_solicitar_opcoes_alvo(id_personagem: String):
								if _acao_bloqueada_por_eleicao(true):
																return
								var meu_personagem_local = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
								# Segurança: só o jogador local pode pedir suas próprias opções
								# Verifica se é a vez do jogador
								if jogador_atual_id != meu_personagem_local:
												if hud and hud.has_method("mostrar_aviso_turno"):
																hud.mostrar_aviso_turno("Aguarde sua vez para usar habilidades!")
												return
								if dados_economia_jogadores[id_personagem].get("recarga_hab", 0) > 0:
																																if pinos_jogadores.has(id_personagem):
																																								pinos_jogadores[id_personagem].mostrar_texto_flutuante("HABILIDADE EM RECARGA", Color(0.9, 0.3, 0.3))
																																return
								# Apagão Digital desativa habilidades
								if _habilidades_bloqueadas_por_efeito(id_personagem):
																																if pinos_jogadores.has(id_personagem):
																																								pinos_jogadores[id_personagem].mostrar_texto_flutuante("APAGÃO DESATIVA HABILIDADES", Color(0.5, 0.5, 0.5))
																																return
								# Bloqueio extra para Kofi: eventos que bloqueiam construção
								if id_personagem == "kofi" and _opcoes_kofi(id_personagem).is_empty():
																																if pinos_jogadores.has(id_personagem):
																																								pinos_jogadores[id_personagem].mostrar_texto_flutuante("CONSTRUÇÃO BLOQUEADA POR EVENTO", Color(0.9, 0.3, 0.3))
																																return
								# Computa as opções de alvo
								var opcoes = _computar_opcoes_alvo_habilidade(id_personagem)
								# Mostra o overlay com a lista populada
								var nome_hab = NOMES_HABILIDADES.get(id_personagem, "Habilidade")
								var desc_hab = DESC_HABILIDADES_UI.get(id_personagem, DESC_HABILIDADES.get(id_personagem, ""))
								var cor_pers = cor_por_jogador.get(id_personagem, Color.WHITE)
								if hud and hud.has_method("mostrar_overlay_habilidade_com_alvos"):
																																hud.mostrar_overlay_habilidade_com_alvos(id_personagem, nome_hab, desc_hab, cor_pers, opcoes)

# --- NOVO (UI de seleção de alvo): computa a lista de opções de alvo válidas
#     para a habilidade do personagem. Cada opção é um Dictionary:
#       { "texto": str, "texto_curto": str, "alvo_id": str, "casa_id": int, "cor": Color }
#     Retorna Array vazio se não há alvos válidos (HUD mostra mensagem). ---
func _computar_opcoes_alvo_habilidade(id_personagem: String) -> Array:
								var opcoes: Array = []
								match id_personagem:
																																"yasmin":
																																								opcoes = _opcoes_yasmin(id_personagem)
																																"breno":
																																								opcoes = _opcoes_breno(id_personagem)
																																"mira":
																																								opcoes = _opcoes_mira(id_personagem)
																																"igor":
																																								opcoes = _opcoes_igor(id_personagem)
																																"diana":
																																								opcoes = _opcoes_diana(id_personagem)
																																"kofi":
																																								opcoes = _opcoes_kofi(id_personagem)
								return opcoes

# ---------------------------------------------------------------------------
# YASMIN — OFERTA IRRECUSÁVEL BALANCEADA
# ---------------------------------------------------------------------------
func _registrar_aquisicao_propriedade(casa_id: int, dono_id: String) -> void:
	# Chamado sempre que um ativo muda de dono. O registro inclui o dono para
	# impedir que um dado antigo torne elegível uma propriedade recém-transferida.
	rodada_aquisicao_propriedade[casa_id] = {
		"dono_id": dono_id,
		"rodada": rodada_atual
	}

func _rodadas_com_propriedade(casa_id: int, dono_id: String) -> int:
	var registro: Dictionary = rodada_aquisicao_propriedade.get(casa_id, {})
	if str(registro.get("dono_id", "")) != dono_id:
		return 0
	return max(0, rodada_atual - int(registro.get("rodada", rodada_atual)))

func _yasmin_possui_terreno_no_grupo(yasmin_id: String, grupo: String) -> bool:
	for cid in tabuleiro.keys():
		if int(cid) < 0 or not tabuleiro.has(cid):
			continue
		if str(tabuleiro[cid].get("tipo", "")) != "propriedade":
			continue
		if str(tabuleiro[cid].get("grupo", "")) != grupo:
			continue
		if str(registro_propriedades.get(cid, "")) == yasmin_id:
			return true
	return false

func _yasmin_ja_usou_contra(yasmin_id: String, alvo_id: String) -> bool:
	var usados: Array = dados_economia_jogadores.get(yasmin_id, {}).get("alvos_oferta_irrecusavel", [])
	return usados.has(alvo_id)

func _preco_oferta_irrecusavel(casa_id: int) -> int:
	return int(ceil(float(tabuleiro.get(casa_id, {}).get("preco", 0)) * 1.50))

func _motivo_oferta_yasmin_invalida(yasmin_id: String, alvo_id: String, casa_id: int) -> String:
	if not dados_economia_jogadores.has(yasmin_id) or not dados_economia_jogadores.has(alvo_id):
		return "JOGADOR INVÁLIDO"
	if casa_id < 0 or not tabuleiro.has(casa_id):
		return "PROPRIEDADE INVÁLIDA"
	if str(tabuleiro[casa_id].get("tipo", "")) != "propriedade":
		return "APENAS PROPRIEDADES"
	if str(registro_propriedades.get(casa_id, "")) != alvo_id:
		return "O DONO MUDOU"
	if alvo_id == yasmin_id:
		return "PROPRIEDADE PRÓPRIA"
	if dados_economia_jogadores[alvo_id].get("falido", false):
		return "ALVO FORA DA PARTIDA"
	if _e_imune_a_confisco(alvo_id):
		return "ALVO IMUNE (RAÍZES)"
	if _yasmin_ja_usou_contra(yasmin_id, alvo_id):
		return "ALVO JÁ UTILIZADO"
	if int(tabuleiro[casa_id].get("nivel", 0)) != 0:
		return "A PROPRIEDADE TEM CONSTRUÇÕES"
	var grupo = str(tabuleiro[casa_id].get("grupo", ""))
	if grupo in ["", "Especial", "Utilidade", "Transporte", "Portal"]:
		return "GRUPO INVÁLIDO"
	if not _yasmin_possui_terreno_no_grupo(yasmin_id, grupo):
		return "YASMIN NÃO POSSUI TERRENO DO GRUPO"
	if _tem_monopolio(alvo_id, grupo):
		return "MONOPÓLIO PROTEGIDO"
	if _rodadas_com_propriedade(casa_id, alvo_id) < 2:
		return "POSSE RECENTE: AGUARDE 2 RODADAS"
	return ""

# --- Yasmin: somente ativos vazios, maduros e ligados à estratégia de grupo. ---
func _opcoes_yasmin(yasmin_id: String) -> Array:
	var opcoes: Array = []
	var meu_dinheiro = int(dados_economia_jogadores.get(yasmin_id, {}).get("dinheiro", 0))
	for id_variant in tabuleiro.keys():
		var id = int(id_variant)
		if not registro_propriedades.has(id):
			continue
		var dono_id = str(registro_propriedades[id])
		if _motivo_oferta_yasmin_invalida(yasmin_id, dono_id, id) != "":
			continue

		var dono_nome = str(dados_economia_jogadores[dono_id].get("nome", dono_id))
		var grupo = str(tabuleiro[id].get("grupo", ""))
		var preco = _preco_oferta_irrecusavel(id)
		var rodadas_posse = _rodadas_com_propriedade(id, dono_id)
		var pode_comprar = "✓" if meu_dinheiro >= preco else "✗ SEM $"
		opcoes.append({
			"texto": str(tabuleiro[id].get("nome", "Propriedade")).replace("\n", " ") +
				"  |  " + grupo + "  |  Dono: " + dono_nome +
				"  |  Posse: " + str(rodadas_posse) + " rodadas" +
				"  |  Oferta 150%: $" + str(preco) + "  |  " + pode_comprar,
			"texto_curto": str(tabuleiro[id].get("nome", "Propriedade")).replace("\n", " "),
			"alvo_id": dono_id,
			"casa_id": id,
			"cor": Color(0.95, 0.5, 0.85) if meu_dinheiro >= preco else Color(0.6, 0.3, 0.3)
		})

	# Prioriza as ofertas mais baratas; em empate, mantém a ordem do tabuleiro.
	opcoes.sort_custom(func(a, b):
		var preco_a = _preco_oferta_irrecusavel(int(a["casa_id"]))
		var preco_b = _preco_oferta_irrecusavel(int(b["casa_id"]))
		return preco_a < preco_b if preco_a != preco_b else int(a["casa_id"]) < int(b["casa_id"])
	)
	return opcoes

func _opcoes_breno(breno_id: String) -> Array:
								var opcoes: Array = []
								var grupos = ["Cinza", "Marrom", "Rosa", "Laranja", "Vermelho", "Amarelo", "Verde", "Azul-Escuro"]
								for grp in grupos:
																																var total = 0
																																var minhas = 0
																																var primeira_casa = -1
																																for id in tabuleiro.keys():
																																								if tabuleiro[id].get("grupo", "") == grp:
																																																total += 1
																																																if primeira_casa < 0:
																																																																primeira_casa = id
																																																if registro_propriedades.has(id) and registro_propriedades[id] == breno_id:
																																																																minhas += 1
																																if total == 0:
																																								continue
																																var status = "MONOPÓLIO ★" if minhas == total else (str(minhas) + "/" + str(total) + " props")
																																var cor_grp = cores_grupos.get(grp, Color.WHITE)
																																opcoes.append({
																																																"texto": grp.to_upper() + "  |  " + status + "  |  Dobra aluguel 2x por 2 turnos",
																																																"texto_curto": grp,
																																																"alvo_id": "",
																																																"casa_id": primeira_casa,
																																																"cor": cor_grp
																																								})
								return opcoes

# --- Mira: suas propriedades com nível 2 a 4 (convertíveis em hotel) ---
func _opcoes_mira(mira_id: String) -> Array:
	var opcoes: Array = []
	for id in tabuleiro.keys():
		if not registro_propriedades.has(id) or registro_propriedades[id] != mira_id:
			continue
		var nivel = int(tabuleiro[id].get("nivel", 0))
		if nivel != 2:
			continue
		var grp = str(tabuleiro[id].get("grupo", ""))
		if grp in ["Especial", "Utilidade", "Transporte", "Portal"]:
			continue
		if _construcao_bloqueada_por_efeito(mira_id, int(id)):
			continue
		opcoes.append({
			"texto": tabuleiro[id]["nome"].replace("\n", " ") + "  |  2 CASAS → HOTEL  |  GRÁTIS",
			"texto_curto": tabuleiro[id]["nome"].replace("\n", " "),
			"alvo_id": "",
			"casa_id": id,
			"cor": Color(0.4, 0.7, 1.0)
		})
	opcoes.sort_custom(func(a, b): return int(a["casa_id"]) < int(b["casa_id"]))
	return opcoes

func _opcoes_igor(igor_id: String) -> Array:
								var opcoes: Array = []
								for id in tabuleiro.keys():
																																if not registro_propriedades.has(id):
																																								continue
																																if tabuleiro[id].get("nivel", 0) != 0:
																																								continue
																																var grp = tabuleiro[id].get("grupo", "")
																																if grp in ["Especial", "Utilidade", "Transporte", "Portal"]:
																																								continue
																																var dono_id = registro_propriedades[id]
																																var dono_nome = dados_economia_jogadores[dono_id]["nome"]
																																var proprio = " (SUA)" if dono_id == igor_id else ""
																																opcoes.append({
																																																"texto": tabuleiro[id]["nome"].replace("\n", " ") + "  |  Dono: " + dono_nome + proprio + "  |  Aluguel 2x por 3 turnos",
																																																"texto_curto": tabuleiro[id]["nome"].replace("\n", " "),
																																																"alvo_id": "",
																																																"casa_id": id,
																																																"cor": Color(1.0, 0.7, 0.2)
																																								})
								return opcoes

# --- Diana: oponentes vivos (não ela, não falidos, não já vazados) ---
func _opcoes_diana(diana_id: String) -> Array:
								var opcoes: Array = []
								for pid in lista_turnos:
																																if pid == diana_id:
																																								continue
																																if not dados_economia_jogadores.has(pid):
																																								continue
																																if dados_economia_jogadores[pid].get("falido", false):
																																								continue
																																if dados_economia_jogadores[pid].get("vazamento_ativo", false):
																																								continue  # já vazado
																																var nome = dados_economia_jogadores[pid]["nome"]
																																var money = dados_economia_jogadores[pid]["dinheiro"]
																																var props = dados_economia_jogadores[pid]["propriedades_compradas"]
																																var cor_pers = cor_por_jogador.get(pid, Color.WHITE)
																																opcoes.append({
																																																"texto": nome + "  |  $" + str(money) + "  |  " + str(props) + " props",
																																																"texto_curto": nome.split(" ")[0],
																																																"alvo_id": pid,
																																																"casa_id": -1,
																																																"cor": cor_pers
																																								})
								return opcoes

# --- Kofi: suas propriedades com nível < 5, mostrando custo com 40% OFF ---
func _opcoes_kofi(kofi_id: String) -> Array:
	var opcoes: Array = []
	var meu_dinheiro = int(dados_economia_jogadores.get(kofi_id, {}).get("dinheiro", 0))
	var mutirao_anterior = dados_economia_jogadores[kofi_id].get("mutirao_ativo", false)
	dados_economia_jogadores[kofi_id]["mutirao_ativo"] = true
	for id in tabuleiro.keys():
		if registro_propriedades.get(id, "") != kofi_id:
			continue
		var nivel = int(tabuleiro[id].get("nivel", 0))
		var grupo = tabuleiro[id].get("grupo", "")
		if nivel >= 5 or grupo in ["Especial", "Utilidade", "Transporte", "Portal"]:
			continue
		if tabuleiro[id].get("hipotecada", false) or _construcao_bloqueada_por_efeito(kofi_id, id):
			continue
		var custo = _calcular_custo_construcao(kofi_id, id)
		var destino = _nivel_destino_construcao(id)
		var destino_txt = "HOTEL" if destino >= 5 else str(destino)
		var pode_pagar = "✓" if meu_dinheiro >= custo else "✗ SEM $"
		opcoes.append({
			"texto": tabuleiro[id]["nome"].replace("\n", " ") + "  |  Nível " + str(nivel) + " → " + destino_txt + "  |  Custo: $" + str(custo) + "  |  " + pode_pagar,
			"texto_curto": tabuleiro[id]["nome"].replace("\n", " "),
			"alvo_id": "",
			"casa_id": id,
			"cor": Color(0.95, 0.85, 0.3) if meu_dinheiro >= custo else Color(0.6, 0.5, 0.2)
		})
	dados_economia_jogadores[kofi_id]["mutirao_ativo"] = mutirao_anterior
	return opcoes

func _on_hud_solicitar_habilidade(alvo_id: String, casa_id: int):
								if _acao_bloqueada_por_eleicao(true):
																return
								var meu_personagem_local = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
								# Turno já verificado em _on_hud_solicitar_opcoes_alvo
								# Verifica cooldown
								if dados_economia_jogadores[meu_personagem_local].get("recarga_hab", 0) > 0:
																if pinos_jogadores.has(meu_personagem_local):
																								pinos_jogadores[meu_personagem_local].mostrar_texto_flutuante("HABILIDADE EM RECARGA", Color(0.9, 0.3, 0.3))
																return
								# Apagão Digital desativa habilidades
								if _habilidades_bloqueadas_por_efeito(meu_personagem_local):
																if pinos_jogadores.has(meu_personagem_local):
																								pinos_jogadores[meu_personagem_local].mostrar_texto_flutuante("APAGÃO DESATIVA HABILIDADES", Color(0.5, 0.5, 0.5))
																return
								# --- NOVO (UI de seleção de alvo): alvo_id agora vem sempre preenchido
								#     pela nova UI de seleção. Mantemos um fallback de segurança que
								#     pega o próximo jogador caso o alvo esteja vazio (compatibilidade). ---
								if alvo_id == "":
																# Pega o próximo jogador na lista de turnos (fallback de segurança)
																var idx_atual = lista_turnos.find(meu_personagem_local)
																var prox_idx = (idx_atual + 1) % lista_turnos.size()
																alvo_id = lista_turnos[prox_idx]
								OnlineTransport.send_all(self, &"_ativar_habilidade_rede", [meu_personagem_local, alvo_id, casa_id], false, true)

@rpc("any_peer", "call_local")
func _ativar_habilidade_rede(id_personagem: String, alvo_id: String, casa_id: int):
								if _acoes_bloqueadas_por_evento():
																return
								var dados = dados_economia_jogadores[id_personagem]
								var nome_hab = NOMES_HABILIDADES.get(id_personagem, "Habilidade")
								var desc_hab = DESC_HABILIDADES.get(id_personagem, "")
								var cor_pers = cor_por_jogador.get(id_personagem, Color.WHITE)
								
								# Animação: overlay + flash + tint no pino
								hud.habilidade_ativada_sucesso(nome_hab, cor_pers)
								if pinos_jogadores.has(id_personagem):
																pinos_jogadores[id_personagem].ativar_tint_habilidade(cor_pers, 1.5)
								
								# --- BUG #1 FIX: Cada _habilidade_*() retorna bool indicando se
								#     o efeito foi aplicado com sucesso. O cooldown só é aplicado
								#     se a habilidade realmente teve efeito (retornou true).
								#     Antes, ativar a habilidade sem alvo válido (ex: Yasmin em Kofi
								#     imune, Mira sem propriedade com 2+ casas) ainda setava o cooldown,
								#     fazendo o jogador perder a habilidade por 4-6 turnos sem efeito. ---
								var sucesso: bool = false
								match id_personagem:
																"yasmin":
																								sucesso = _habilidade_yasmin(id_personagem, alvo_id, casa_id)
																"breno":
																								sucesso = _habilidade_breno(id_personagem, casa_id)
																"mira":
																								sucesso = _habilidade_mira(id_personagem, casa_id)
																"igor":
																								sucesso = _habilidade_igor(id_personagem, casa_id)
																"diana":
																								sucesso = _habilidade_diana(id_personagem, alvo_id)
																"kofi":
																								sucesso = _habilidade_kofi(id_personagem, casa_id)
								
								# Aplica cooldown SÓ se a habilidade teve efeito
								if sucesso:
																dados["recarga_hab"] = RECARGAS_HABILIDADES.get(id_personagem, 4)
																_registrar_uso_habilidade_xp(id_personagem)
								_atualizar_hud_ciclo_turno()

# Yasmin: Oferta Irrecusável — compra estratégica por 150% do valor de tabela.
# Retorna true somente quando todas as restrições de balanceamento são cumpridas.
func _habilidade_yasmin(yasmin_id: String, alvo_id: String, casa_id: int) -> bool:
	var motivo = _motivo_oferta_yasmin_invalida(yasmin_id, alvo_id, casa_id)
	if motivo != "":
		if pinos_jogadores.has(yasmin_id):
			pinos_jogadores[yasmin_id].mostrar_texto_flutuante(motivo, Color(0.9, 0.3, 0.3))
		return false

	var preco = _preco_oferta_irrecusavel(casa_id)
	if int(dados_economia_jogadores[yasmin_id].get("dinheiro", 0)) < preco:
		if pinos_jogadores.has(yasmin_id):
			pinos_jogadores[yasmin_id].mostrar_texto_flutuante("SALDO INSUFICIENTE: $" + str(preco), Color(0.9, 0.3, 0.3))
		return false

	# Transfere 150% do valor de tabela ao antigo dono.
	dados_economia_jogadores[yasmin_id]["dinheiro"] -= preco
	dados_economia_jogadores[alvo_id]["dinheiro"] += preco
	registro_propriedades[casa_id] = yasmin_id
	_registrar_aquisicao_propriedade(casa_id, yasmin_id)

	dados_economia_jogadores[alvo_id]["propriedades_compradas"] = max(
		0, int(dados_economia_jogadores[alvo_id].get("propriedades_compradas", 0)) - 1
	)
	dados_economia_jogadores[alvo_id]["propriedades_lista"].erase(casa_id)
	if not dados_economia_jogadores[yasmin_id]["propriedades_lista"].has(casa_id):
		dados_economia_jogadores[yasmin_id]["propriedades_lista"].append(casa_id)
		dados_economia_jogadores[yasmin_id]["propriedades_compradas"] = int(
			dados_economia_jogadores[yasmin_id].get("propriedades_compradas", 0)
		) + 1

	# O mesmo adversário não pode ser atingido novamente nesta partida.
	var alvos_usados: Array = dados_economia_jogadores[yasmin_id].get("alvos_oferta_irrecusavel", [])
	if not alvos_usados.has(alvo_id):
		alvos_usados.append(alvo_id)
	dados_economia_jogadores[yasmin_id]["alvos_oferta_irrecusavel"] = alvos_usados

	_atualizar_visual_dono(casa_id)
	_verificar_novos_monopolios_xp(yasmin_id)
	var nome_propriedade = str(tabuleiro[casa_id].get("nome", "Propriedade")).replace("\n", " ")
	_registrar_acao(
		"habilidade",
		"Yasmin adquiriu %s de %s por $%d (150%% do valor de tabela)." % [
			nome_propriedade,
			str(dados_economia_jogadores[alvo_id].get("nome", alvo_id)),
			preco
		],
		yasmin_id
	)

	if pinos_jogadores.has(yasmin_id):
		pinos_jogadores[yasmin_id].mostrar_texto_flutuante("OFERTA 150%! -$" + str(preco), Color(0.9, 0.3, 0.8))
	if pinos_jogadores.has(alvo_id):
		pinos_jogadores[alvo_id].mostrar_texto_flutuante("VENDA FORÇADA +$" + str(preco), Color(0.9, 0.55, 0.25))
	if pinos_jogadores.has(yasmin_id) and pinos_jogadores.has(alvo_id):
		Animacoes.transferencia_moedas(
			self,
			pinos_jogadores[yasmin_id].position,
			pinos_jogadores[alvo_id].position,
			Color(0.95, 0.3, 0.8),
			10
		)

	_verificar_falencia(yasmin_id)
	return true

func _habilidade_breno(breno_id: String, casa_id: int) -> bool:
								# Interação do GDD: durante a Intervenção Federal, o Decreto estende
								# gratuitamente o congelamento e a compensação estatal por +1 turno.
								if _tem_efeito_temporario("intervencao_congelamento"):
									for chave in ["intervencao_congelamento", "intervencao_compensacao"]:
										if efeitos_temporarios.has(chave):
											efeitos_temporarios[chave]["turnos_restantes"] = int(efeitos_temporarios[chave].get("turnos_restantes", 0)) + 1
									if pinos_jogadores.has(breno_id):
										pinos_jogadores[breno_id].mostrar_texto_flutuante("INTERVENÇÃO +1 TURNO!", Color(0.3, 0.9, 0.8))
									return true

								var grupo_escolhido = ""
								# 1) Se o jogador selecionou uma casa, usa o grupo dela
								if casa_id >= 0 and tabuleiro.has(casa_id):
																grupo_escolhido = tabuleiro[casa_id].get("grupo", "")
								# 2) Se ainda não temos grupo, escolhe estrategicamente
								if grupo_escolhido == "" or grupo_escolhido in ["Especial", "Utilidade", "Transporte", "Portal"]:
																var grupos_proprios = []
																var grupos_monopolio = []
																var todos_grupos = ["Cinza", "Marrom", "Rosa", "Laranja", "Vermelho", "Amarelo", "Verde", "Azul-Escuro"]
																for grp in todos_grupos:
																								if _tem_monopolio(breno_id, grp):
																																grupos_monopolio.append(grp)
																								else:
																																# Verifica se Breno tem pelo menos 1 propriedade nesse grupo
																																for cid in tabuleiro.keys():
																																								if tabuleiro[cid].get("grupo", "") == grp and registro_propriedades.has(cid) and registro_propriedades[cid] == breno_id:
																																																grupos_proprios.append(grp)
																																																break
																# Prioridade 1: grupo onde Breno tem monopólio (2x o beneficia diretamente)
																if not grupos_monopolio.is_empty():
																								grupo_escolhido = grupos_monopolio.pick_random()
																# Prioridade 2: grupo onde Breno tem pelo menos 1 propriedade
																elif not grupos_proprios.is_empty():
																								grupo_escolhido = grupos_proprios.pick_random()
																# Prioridade 3: sorteia um grupo qualquer (afeta adversários)
																else:
																								grupo_escolhido = todos_grupos.pick_random()
								# Marca o grupo com multiplicador 2x por 2 turnos
								dados_economia_jogadores[breno_id]["decreto_grupo"] = grupo_escolhido
								dados_economia_jogadores[breno_id]["decreto_turnos"] = 2
								if pinos_jogadores.has(breno_id):
																pinos_jogadores[breno_id].mostrar_texto_flutuante("DECRETO: " + grupo_escolhido.to_upper() + " 2X!", Color(0.3, 0.9, 0.3))
								return true

# Mira: Retrofit Urbano — converte 2 casas em 1 hotel instantaneamente (grátis)
# Retorna true se aplicado com sucesso.
func _habilidade_mira(mira_id: String, casa_id: int) -> bool:
	var candidatas: Array = []
	for id in tabuleiro.keys():
		if (
			registro_propriedades.get(id, "") == mira_id
			and int(tabuleiro[id].get("nivel", 0)) == 2
			and not _construcao_bloqueada_por_efeito(mira_id, int(id))
		):
			candidatas.append(id)
	if candidatas.is_empty():
		if pinos_jogadores.has(mira_id):
			var mensagem: String = (
				"CONSTRUÇÃO BLOQUEADA NESTE TURNO"
				if turno_construcao_bloqueada and mira_id == jogador_atual_id
				else "PRECISA DE EXATAMENTE 2 CASAS"
			)
			pinos_jogadores[mira_id].mostrar_texto_flutuante(mensagem, Color(0.9, 0.3, 0.3))
		return false
	var id_alvo = candidatas[0] if casa_id < 0 else casa_id
	if not candidatas.has(id_alvo):
		if pinos_jogadores.has(mira_id):
			pinos_jogadores[mira_id].mostrar_texto_flutuante("ALVO SEM EXATAMENTE 2 CASAS", Color(0.9, 0.3, 0.3))
		return false
	tabuleiro[id_alvo]["nivel"] = 5
	_atualizar_imagem_construcao(id_alvo)
	var pos_casa = tabuleiro[id_alvo].get("pos", Vector2.ZERO)
	Animacoes.flash_de_tela(hud.get_node("Control"), Color(0.3, 0.9, 0.3, 0.5), 0.6)
	Animacoes.tremer_camera(camera, 5.0, 0.4)
	Animacoes.explosao_particulas(self, pos_casa, Color(0.3, 0.9, 0.3), 16, 90)
	if pinos_jogadores.has(mira_id):
		pinos_jogadores[mira_id].mostrar_texto_flutuante("RETROFIT! 2 CASAS → HOTEL", Color(0.3, 0.9, 0.3))
		pinos_jogadores[mira_id].celebrar()
	return true

func _habilidade_igor(igor_id: String, casa_id: int) -> bool:
								# Procura terreno vazio (qualquer propriedade não desenvolvida)
								var candidatas = []
								for id in tabuleiro.keys():
																if registro_propriedades.has(id):
																								if tabuleiro[id].get("nivel", 0) == 0:
																																var grp = tabuleiro[id].get("grupo", "")
																																if grp not in ["Especial", "Utilidade", "Transporte", "Portal"]:
																																								candidatas.append(id)
								if candidatas.is_empty():
																if pinos_jogadores.has(igor_id):
																								pinos_jogadores[igor_id].mostrar_texto_flutuante("SEM TERRENOS VAZIOS", Color(0.9, 0.3, 0.3))
																return false
								var id_alvo = candidatas.pick_random() if casa_id < 0 else casa_id
								if not candidatas.has(id_alvo):
																id_alvo = candidatas[0]
								dados_economia_jogadores[igor_id]["especulacao_casa"] = id_alvo
								dados_economia_jogadores[igor_id]["especulacao_turnos"] = 3
								if pinos_jogadores.has(igor_id):
																pinos_jogadores[igor_id].mostrar_texto_flutuante("ESPECULAÇÃO! ALUGUEL 2X POR 3T", Color(1.0, 0.6, 0.0))
								return true

# Diana: Vazamento Seletivo — anula próximo aluguel recebido pelo alvo
# Retorna true se aplicado com sucesso.
# --- BUG #14 FIX: O GDD descreve o Vazamento como "anula o PRÓXIMO aluguel recebido
#     pelo alvo NESTE TURNO". Antes, a flag vazamento_ativo ficava ativa INDEFINIDAMENTE
#     até o alvo receber um aluguel — podendo durar muitos turnos. Agora expira ao fim
#     do próximo turno do alvo (controlado em _avancar_turno_rede). ---
func _habilidade_diana(diana_id: String, alvo_id: String) -> bool:
	if alvo_id == diana_id or alvo_id == "" or not dados_economia_jogadores.has(alvo_id):
		if pinos_jogadores.has(diana_id):
			pinos_jogadores[diana_id].mostrar_texto_flutuante("ALVO INVÁLIDO", Color(0.9, 0.3, 0.3))
		return false
	if dados_economia_jogadores[alvo_id].get("vazamento_ativo", false):
		if pinos_jogadores.has(diana_id):
			pinos_jogadores[diana_id].mostrar_texto_flutuante("ALVO JÁ VAZADO", Color(0.9, 0.3, 0.3))
		return false
	dados_economia_jogadores[alvo_id]["vazamento_ativo"] = true
	dados_economia_jogadores[alvo_id].erase("vazamento_turnos")
	if pinos_jogadores.has(diana_id):
		pinos_jogadores[diana_id].mostrar_texto_flutuante("VAZAMENTO EM " + alvo_id.to_upper(), Color(0.8, 0.2, 0.8))
	if pinos_jogadores.has(alvo_id):
		pinos_jogadores[alvo_id].tremer(4.0, 0.4)
	return true

func _habilidade_kofi(kofi_id: String, casa_id: int) -> bool:
	var candidatas: Array = []
	for id in tabuleiro.keys():
		if registro_propriedades.get(id, "") != kofi_id:
			continue
		if tabuleiro[id].get("tipo", "") != "propriedade":
			continue
		if int(tabuleiro[id].get("nivel", 0)) >= 5 or tabuleiro[id].get("hipotecada", false):
			continue
		if _construcao_bloqueada_por_efeito(kofi_id, int(id)):
			continue
		candidatas.append(int(id))
	if candidatas.is_empty():
		if pinos_jogadores.has(kofi_id):
			pinos_jogadores[kofi_id].mostrar_texto_flutuante("SEM PROPRIEDADE VÁLIDA", Color(0.9, 0.3, 0.3))
		return false

	var id_alvo = candidatas[0] if casa_id < 0 else casa_id
	if not candidatas.has(id_alvo):
		id_alvo = candidatas[0]

	# A flag libera a regra "qualquer propriedade" e é consumida somente após
	# uma construção bem-sucedida. O custo central aplica os 40% de desconto.
	dados_economia_jogadores[kofi_id]["mutirao_ativo"] = true
	var motivo = _motivo_construcao_invalida(kofi_id, id_alvo)
	if motivo != "":
		dados_economia_jogadores[kofi_id]["mutirao_ativo"] = false
		if pinos_jogadores.has(kofi_id):
			pinos_jogadores[kofi_id].mostrar_texto_flutuante(motivo, Color(0.9, 0.3, 0.3))
		return false

	_efetuar_construcao_rede(kofi_id, id_alvo)
	return true

# ============================================================================
# NOVO: SISTEMA DE HIPOTECA
# ============================================================================
func _on_hud_solicitar_hipoteca(casa_id: int):
	if _acao_bloqueada_por_eleicao(true):
		return
	var meu_personagem_local = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
	if jogador_atual_id != meu_personagem_local:
		if hud and hud.has_method("mostrar_aviso_turno"):
			hud.mostrar_aviso_turno("Aguarde sua vez para hipotecar!")
		return
	if casa_id < 0 and pinos_jogadores.has(meu_personagem_local):
		casa_id = pinos_jogadores[meu_personagem_local].casa_atual
	if casa_id < 0 or not tabuleiro.has(casa_id):
		return
	if registro_propriedades.get(casa_id, "") != meu_personagem_local:
		if pinos_jogadores.has(meu_personagem_local):
			pinos_jogadores[meu_personagem_local].mostrar_texto_flutuante("ESSA PROP NÃO É SUA", Color(0.9, 0.3, 0.3))
		return
	if tabuleiro[casa_id].get("hipotecada", false):
		OnlineTransport.send_all(self, &"_resgatar_hipoteca_rede", [meu_personagem_local, casa_id], false, true)
	else:
		OnlineTransport.send_all(self, &"_hipotecar_rede", [meu_personagem_local, casa_id], false, true)

@rpc("any_peer", "call_local")
func _hipotecar_rede(jogador_id: String, casa_id: int):
								if _acoes_bloqueadas_por_evento():
																return
								if not registro_propriedades.has(casa_id) or registro_propriedades[casa_id] != jogador_id:
																return
								if tabuleiro[casa_id].get("hipotecada", false):
																return
								# --- BUG FIX (HIGH #3): Verifica monopólio. Em Monopoly clássico (e
								#     provavelmente no GDD), você não pode hipotecar uma propriedade de
								#     um grupo onde há construções. Precisa vender TODAS as construções
								#     do grupo antes de hipotecar qualquer propriedade do grupo.
								#     Antes, o jogador podia hipotecar uma propriedade de um grupo onde
								#     tinha hotel — bug de regra. ---
								var grp = tabuleiro[casa_id].get("grupo", "")
								if grp not in ["Especial", "Utilidade", "Transporte", "Portal"]:
																# Verifica se há construções em qualquer propriedade do mesmo grupo
																var tem_construcao_no_grupo = false
																for id_chk in tabuleiro.keys():
																								if tabuleiro[id_chk].get("grupo", "") == grp:
																																if registro_propriedades.has(id_chk) and registro_propriedades[id_chk] == jogador_id:
																																								if tabuleiro[id_chk].get("nivel", 0) > 0:
																																																tem_construcao_no_grupo = true
																																																break
																if tem_construcao_no_grupo:
																								if pinos_jogadores.has(jogador_id):
																																pinos_jogadores[jogador_id].mostrar_texto_flutuante("VENHA CONSTRUÇÕES DO GRUPO PRIMEIRO", Color(0.9, 0.3, 0.3))
																								return
								var valor_hipoteca = int(_calcular_valor_propriedade(casa_id) * 0.5)
								tabuleiro[casa_id]["hipotecada"] = true
								dados_economia_jogadores[jogador_id]["dinheiro"] += valor_hipoteca
								var nome_hip_hist = dados_economia_jogadores.get(jogador_id, {}).get("nome", jogador_id)
								var prop_hip_hist = str(tabuleiro.get(casa_id, {}).get("nome", "propriedade")).replace("\n", " ")
								_registrar_acao("hipoteca", "%s hipotecou %s e recebeu $%d." % [nome_hip_hist, prop_hip_hist, valor_hipoteca], jogador_id)
								if pinos_jogadores.has(jogador_id):
																pinos_jogadores[jogador_id].mostrar_texto_flutuante("HIPOTECADA +$" + str(valor_hipoteca), Color(0.95, 0.6, 0.2))
								_atualizar_visual_dono(casa_id)
								_atualizar_hud_ciclo_turno()

@rpc("any_peer", "call_local")
func _resgatar_hipoteca_rede(jogador_id: String, casa_id: int):
								if _acoes_bloqueadas_por_evento():
																return
								if not registro_propriedades.has(casa_id) or registro_propriedades[casa_id] != jogador_id:
																return
								if not tabuleiro[casa_id].get("hipotecada", false):
																return
								var custo_resgate = _calcular_custo_resgate_hipoteca(casa_id)
								if dados_economia_jogadores[jogador_id]["dinheiro"] < custo_resgate:
																if pinos_jogadores.has(jogador_id):
																								pinos_jogadores[jogador_id].mostrar_texto_flutuante("SALDO INSUFICIENTE", Color(0.9, 0.3, 0.3))
																return
								dados_economia_jogadores[jogador_id]["dinheiro"] -= custo_resgate
								tabuleiro[casa_id]["hipotecada"] = false
								var nome_resgate_hist = dados_economia_jogadores.get(jogador_id, {}).get("nome", jogador_id)
								var prop_resgate_hist = str(tabuleiro.get(casa_id, {}).get("nome", "propriedade")).replace("\n", " ")
								_registrar_acao("hipoteca", "%s resgatou %s por $%d." % [nome_resgate_hist, prop_resgate_hist, custo_resgate], jogador_id)
								if pinos_jogadores.has(jogador_id):
																pinos_jogadores[jogador_id].mostrar_texto_flutuante("RESGATADA -$" + str(custo_resgate), Color(0.4, 0.9, 0.4))
								_atualizar_visual_dono(casa_id)
								_atualizar_hud_ciclo_turno()

# ============================================================================
# NOVO: SISTEMA DE FIANÇA DA PRISÃO
# ============================================================================
func _on_hud_solicitar_fianca_prisao():
	if _acao_bloqueada_por_eleicao(true) or _acoes_bloqueadas_por_evento():
		if hud and hud.has_method("resolver_solicitacao_fianca"):
			hud.resolver_solicitacao_fianca(false, "Aguarde o evento atual terminar.")
		return

	var meu_personagem_local = str(Global.escolhas_da_mesa.get(Global.meu_peer_id, ""))
	if meu_personagem_local == "" or not dados_economia_jogadores.has(meu_personagem_local):
		if hud and hud.has_method("resolver_solicitacao_fianca"):
			hud.resolver_solicitacao_fianca(false, "Não foi possível identificar o jogador local.")
		return
	if jogador_atual_id != meu_personagem_local:
		if hud and hud.has_method("resolver_solicitacao_fianca"):
			hud.resolver_solicitacao_fianca(false, "Aguarde sua vez para pagar a fiança.")
		return
	if not dados_economia_jogadores[meu_personagem_local].get("preso", false):
		if hud and hud.has_method("resolver_solicitacao_fianca"):
			hud.resolver_solicitacao_fianca(false, "Você já está livre.")
		_verificar_permissao_de_clique()
		return

	# A cobrança e a libertação são decididas somente pelo servidor. O cliente
	# não envia o personagem no RPC: o servidor o identifica pelo peer remoto,
	# evitando pagar a fiança em nome de outro jogador ou duplicar a cobrança.
	if OnlineTransport.is_host():
		_servidor_processar_fianca(meu_personagem_local)
	else:
		OnlineTransport.send_host(self, &"_solicitar_fianca_prisao_servidor", [], false)

@rpc("any_peer", "call_remote", "reliable")
func _solicitar_fianca_prisao_servidor():
	if not OnlineTransport.is_host():
		return
	var peer_remetente = OnlineTransport.get_remote_sender_id()
	var jogador_id = _personagem_do_peer(peer_remetente)
	if jogador_id == "":
		OnlineTransport.send_player(peer_remetente, self, &"_notificar_falha_fianca_local", ["Não foi possível identificar seu personagem no servidor."], false, true)
		return
	_servidor_processar_fianca(jogador_id)

@rpc("authority", "call_remote", "reliable")
func _notificar_falha_fianca_local(mensagem: String):
	if hud and hud.has_method("resolver_solicitacao_fianca"):
		hud.resolver_solicitacao_fianca(false, mensagem)

func _servidor_processar_fianca(jogador_id: String) -> void:
	if not OnlineTransport.is_host():
		return
	if jogador_id == "" or not dados_economia_jogadores.has(jogador_id):
		return
	if _acoes_bloqueadas_por_evento():
		OnlineTransport.send_all(self, &"_aplicar_resultado_fianca_rede", [jogador_id, false, -1, -1, "", "Aguarde o evento atual terminar."], true, true)
		return
	if jogador_atual_id != jogador_id:
		OnlineTransport.send_all(self, &"_aplicar_resultado_fianca_rede", [jogador_id, false, -1, -1, "", "Aguarde sua vez para pagar a fiança."], true, true)
		return

	var dados = dados_economia_jogadores[jogador_id]
	if dados.get("falido", false):
		OnlineTransport.send_all(self, &"_aplicar_resultado_fianca_rede", [jogador_id, false, -1, -1, "", "Jogadores falidos não podem realizar esta ação."], true, true)
		return
	if not dados.get("preso", false):
		OnlineTransport.send_all(self, &"_aplicar_resultado_fianca_rede", [jogador_id, false, int(dados.get("dinheiro", 0)), int(dados.get("cartas_sair_prisao", 0)), "", "Você já está livre."], true, true)
		return

	var novo_saldo = int(dados.get("dinheiro", 0))
	var novas_cartas = int(dados.get("cartas_sair_prisao", 0))
	var forma_saida = "fianca"
	if novas_cartas > 0:
		novas_cartas -= 1
		forma_saida = "carta"
	elif novo_saldo >= 50:
		novo_saldo -= 50
	else:
		OnlineTransport.send_all(self, &"_aplicar_resultado_fianca_rede", [jogador_id, false, novo_saldo, novas_cartas, "", "Você não possui $50 para pagar a fiança."], true, true)
		return

	OnlineTransport.send_all(self, &"_aplicar_resultado_fianca_rede", [jogador_id, true, novo_saldo, novas_cartas, forma_saida, ""], true, true)

@rpc("authority", "call_local", "reliable")
func _aplicar_resultado_fianca_rede(jogador_id: String, sucesso: bool, novo_saldo: int, novas_cartas: int, forma_saida: String, mensagem: String):
	if not dados_economia_jogadores.has(jogador_id):
		return
	var dados = dados_economia_jogadores[jogador_id]
	var personagem_local = str(Global.escolhas_da_mesa.get(Global.meu_peer_id, ""))

	if not sucesso:
		if pinos_jogadores.has(jogador_id) and mensagem != "":
			pinos_jogadores[jogador_id].mostrar_texto_flutuante(mensagem.to_upper(), Color(0.9, 0.3, 0.3))
		if personagem_local == jogador_id and hud and hud.has_method("resolver_solicitacao_fianca"):
			hud.resolver_solicitacao_fianca(false, mensagem)
		return

	# O servidor envia os valores finais, em vez de apenas a diferença. Isso
	# corrige eventuais divergências entre host e cliente e impede cobrança dupla.
	dados["dinheiro"] = novo_saldo
	dados["cartas_sair_prisao"] = novas_cartas
	dados["preso"] = false
	dados["turnos_preso"] = 0
	dados["duplas_consecutivas"] = 0
	if pinos_jogadores.has(jogador_id):
		var pino = pinos_jogadores[jogador_id]
		pino.desativar_barras_prisao()
		if forma_saida == "carta":
			pino.mostrar_texto_flutuante("CARTA USADA! LIVRE!", Color(0.4, 1.0, 0.4))
		else:
			pino.mostrar_texto_flutuante("FIANÇA PAGA! LIVRE!", Color(0.4, 1.0, 0.4))

	var nome_jogador = str(dados.get("nome", jogador_id))
	if forma_saida == "carta":
		_registrar_acao("prisao", "%s usou uma carta e saiu da prisão." % nome_jogador, jogador_id)
	else:
		_registrar_acao("prisao", "%s pagou $50 e saiu da prisão." % nome_jogador, jogador_id)

	if personagem_local == jogador_id and hud and hud.has_method("resolver_solicitacao_fianca"):
		hud.resolver_solicitacao_fianca(true, "")
	_atualizar_hud_ciclo_turno()
	_verificar_falencia(jogador_id)
	_verificar_permissao_de_clique()

# ============================================================================
# MENU DE PAUSA E DESISTÊNCIA
# ============================================================================
func _personagem_por_peer_pause(peer_id: int) -> String:
	if peer_id <= 0:
		return ""

	# Primeiro usa o helper geral, que já trata o peer local e o modo debug.
	var personagem_direto := _personagem_do_peer(peer_id)
	if not personagem_direto.is_empty():
		return personagem_direto

	# As chaves podem chegar como int ou String depois de snapshot/Photon.
	for chave_variant in Global.escolhas_da_mesa.keys():
		if int(chave_variant) == peer_id:
			return str(Global.escolhas_da_mesa[chave_variant])

	# Fallback estável por user_id, necessário após reconexão ou migração host.
	if OnlineTransport.usando_photon():
		var user_id := PhotonManager.obter_user_id_jogador(peer_id)
		if not user_id.is_empty():
			var por_usuario := str(Global.escolhas_por_user_id.get(user_id, ""))
			if not por_usuario.is_empty():
				return por_usuario
	return ""


func _personagem_local_pause() -> String:
	var personagem := _personagem_por_peer_pause(OnlineTransport.local_player_id())
	if personagem.is_empty():
		personagem = _personagem_por_peer_pause(Global.meu_peer_id)
	if personagem.is_empty() and not OnlineTransport.esta_em_sala():
		personagem = jogador_atual_id
	return personagem


func _peer_do_personagem_pause(personagem_id: String) -> int:
	if personagem_id.is_empty():
		return 0
	for chave_variant in Global.escolhas_da_mesa.keys():
		if str(Global.escolhas_da_mesa[chave_variant]) == personagem_id:
			return int(chave_variant)
	return 0


func _on_menu_pause_visibilidade_alterada(aberto: bool) -> void:
	_menu_pause_bloqueando_acoes = aberto
	if not _bots_jogadores.is_empty():
		definir_bots_pausados(aberto)
	arrastando_camera = false
	toques_ativos.clear()


func _nome_jogador_para_pausa(personagem_id: String) -> String:
	if dados_economia_jogadores.has(personagem_id):
		var dados: Dictionary = dados_economia_jogadores[personagem_id]
		var nome := str(dados.get("nome", "")).strip_edges()
		if not nome.is_empty():
			return nome
	if not personagem_id.is_empty():
		return personagem_id.capitalize()
	return "Jogador"


func _on_menu_pause_solicitar_pausa() -> void:
	if _partida_encerrada or _pausa_global_ativa:
		return

	if OnlineTransport.usando_photon():
		if not OnlineTransport.solicitar_estado_pausa_partida_ao_host(true):
			push_warning("[PAUSA ONLINE] Não foi possível enviar a solicitação ao host.")
		return

	var peer_solicitante: int = OnlineTransport.local_player_id()
	if OnlineTransport.is_host():
		_processar_solicitacao_estado_pausa(peer_solicitante, true)
	else:
		OnlineTransport.send_host(
			self,
			&"_solicitar_estado_pausa_servidor",
			[true],
			false
		)


func _on_menu_pause_solicitar_retomada() -> void:
	if _partida_encerrada or not _pausa_global_ativa:
		return

	if OnlineTransport.usando_photon():
		if not OnlineTransport.solicitar_estado_pausa_partida_ao_host(false):
			push_warning("[PAUSA ONLINE] Não foi possível solicitar a retomada ao host.")
		return

	var peer_solicitante: int = OnlineTransport.local_player_id()
	if OnlineTransport.is_host():
		_processar_solicitacao_estado_pausa(peer_solicitante, false)
	else:
		OnlineTransport.send_host(
			self,
			&"_solicitar_estado_pausa_servidor",
			[false],
			false
		)


func _on_solicitacao_estado_pausa_online(
	peer_solicitante: int,
	deseja_pausar: bool
) -> void:
	if not OnlineTransport.usando_photon() or not OnlineTransport.is_host():
		return
	_processar_solicitacao_estado_pausa(peer_solicitante, deseja_pausar)


func _on_estado_pausa_partida_online(
	ativo: bool,
	peer_iniciador: int,
	personagem_iniciador: String,
	nome_iniciador: String
) -> void:
	if not OnlineTransport.usando_photon() or not is_inside_tree():
		return
	_aplicar_estado_pausa_rede(
		ativo,
		peer_iniciador,
		personagem_iniciador,
		nome_iniciador
	)


@rpc("any_peer", "call_remote", "reliable")
func _solicitar_estado_pausa_servidor(deseja_pausar: bool) -> void:
	if not OnlineTransport.is_host() or _partida_encerrada:
		return
	var peer_solicitante := OnlineTransport.get_remote_sender_id()
	_processar_solicitacao_estado_pausa(peer_solicitante, deseja_pausar)


func _publicar_estado_pausa_host(
	ativo: bool,
	peer_iniciador: int,
	personagem_iniciador: String,
	nome_iniciador: String
) -> bool:
	if not OnlineTransport.is_host():
		return false
	if OnlineTransport.usando_photon():
		return OnlineTransport.publicar_estado_pausa_partida(
			ativo,
			peer_iniciador,
			personagem_iniciador,
			nome_iniciador
		)
	return OnlineTransport.send_all(
		self,
		&"_aplicar_estado_pausa_rede",
		[ativo, peer_iniciador, personagem_iniciador, nome_iniciador],
		true,
		true
	)


func _processar_solicitacao_estado_pausa(
	peer_solicitante: int,
	deseja_pausar: bool,
	forcar: bool = false
) -> bool:
	if not OnlineTransport.is_host() or _partida_encerrada:
		return false

	if deseja_pausar:
		if _pausa_global_ativa:
			return false
		var personagem_id := _personagem_por_peer_pause(peer_solicitante)
		if personagem_id.is_empty() and not OnlineTransport.esta_em_sala():
			personagem_id = jogador_atual_id
		if personagem_id.is_empty():
			return false
		var nome_iniciador := _nome_jogador_para_pausa(personagem_id)
		return _publicar_estado_pausa_host(
			true,
			peer_solicitante,
			personagem_id,
			nome_iniciador
		)

	if not _pausa_global_ativa:
		return true
	if not forcar and peer_solicitante != _peer_iniciador_pausa:
		return false
	return _forcar_retomada_pausa_host()


func _forcar_retomada_pausa_host() -> bool:
	if not OnlineTransport.is_host():
		return false
	return _publicar_estado_pausa_host(
		false,
		_peer_iniciador_pausa,
		_personagem_iniciador_pausa,
		_nome_iniciador_pausa
	)


@rpc("authority", "call_local", "reliable")
func _aplicar_estado_pausa_rede(
	ativo: bool,
	peer_iniciador: int,
	personagem_iniciador: String,
	nome_iniciador: String
) -> void:
	var estado_ja_aplicado := (
		_pausa_global_ativa == ativo
		and (
			not ativo
			or (
				_peer_iniciador_pausa == peer_iniciador
				and _personagem_iniciador_pausa == personagem_iniciador
				and _nome_iniciador_pausa == nome_iniciador
			)
		)
	)
	if estado_ja_aplicado:
		return

	# Em rede nunca usamos SceneTree.paused: isso pode interromper o heartbeat
	# da extensão Photon e fazer os outros jogadores parecerem desconectados.
	# A cena de gameplay é desativada, mas o MenuPause e os autoloads continuam.
	var pausa_de_rede := OnlineTransport.esta_em_sala()
	if not ativo:
		get_tree().paused = false
		process_mode = Node.PROCESS_MODE_ALWAYS

	_pausa_global_ativa = ativo
	_peer_iniciador_pausa = peer_iniciador if ativo else 0
	_personagem_iniciador_pausa = personagem_iniciador if ativo else ""
	_nome_iniciador_pausa = nome_iniciador if ativo else ""
	_menu_pause_bloqueando_acoes = ativo
	arrastando_camera = false
	toques_ativos.clear()

	_aplicar_interface_estado_pausa_atual()

	if ativo:
		if pausa_de_rede:
			get_tree().paused = false
			process_mode = Node.PROCESS_MODE_DISABLED
		else:
			process_mode = Node.PROCESS_MODE_PAUSABLE
			get_tree().paused = true


func _aplicar_interface_estado_pausa_atual() -> void:
	if menu_pause == null or not menu_pause.has_method("aplicar_estado_sincronizado"):
		return
	var sou_iniciador := (
		_pausa_global_ativa
		and OnlineTransport.local_player_id() == _peer_iniciador_pausa
	)
	menu_pause.aplicar_estado_sincronizado(
		_pausa_global_ativa,
		sou_iniciador,
		_nome_iniciador_pausa
	)


func _on_menu_pause_solicitar_salvamento() -> void:
	_solicitar_salvamento_ao_host(false)


func _on_menu_pause_solicitar_salvar_e_sair() -> void:
	_solicitar_salvamento_ao_host(true)


func _solicitar_salvamento_ao_host(salvar_e_sair: bool) -> void:
	if _partida_encerrada or _partida_sendo_salva_e_encerrada:
		_notificar_resultado_salvamento_local(
			false,
			"A PARTIDA NÃO PODE MAIS SER SALVA",
			false
		)
		return

	var peer_solicitante: int = OnlineTransport.local_player_id()
	if OnlineTransport.is_host():
		_processar_solicitacao_salvamento(peer_solicitante, salvar_e_sair)
		return

	var enviado: bool = OnlineTransport.send_host(
		self,
		&"_solicitar_salvamento_servidor",
		[salvar_e_sair],
		false
	)
	if not enviado:
		_notificar_resultado_salvamento_local(
			false,
			"NÃO FOI POSSÍVEL CONTATAR O HOST",
			false
		)


@rpc("any_peer", "call_remote", "reliable")
func _solicitar_salvamento_servidor(salvar_e_sair: bool) -> void:
	if not OnlineTransport.is_host():
		return
	var peer_solicitante: int = OnlineTransport.get_remote_sender_id()
	_processar_solicitacao_salvamento(peer_solicitante, salvar_e_sair)


func _processar_solicitacao_salvamento(
	peer_solicitante: int,
	salvar_e_sair: bool
) -> void:
	if not OnlineTransport.is_host():
		return
	if (
		not _pausa_global_ativa
		or peer_solicitante <= 0
		or peer_solicitante != _peer_iniciador_pausa
	):
		_enviar_resultado_salvamento(
			peer_solicitante,
			false,
			"SOMENTE QUEM PAUSOU PODE SALVAR A PARTIDA",
			false
		)
		return

	var resultado: Dictionary = GerenciadorSalvamento.salvar_partida(
		self,
		"salvar_e_sair" if salvar_e_sair else "manual"
	)
	var sucesso: bool = bool(resultado.get("sucesso", false))
	var mensagem: String = str(resultado.get("mensagem", "FALHA AO SALVAR A PARTIDA"))
	_enviar_resultado_salvamento(
		peer_solicitante,
		sucesso,
		mensagem,
		salvar_e_sair and sucesso
	)
	if not sucesso or not salvar_e_sair:
		return

	_partida_sendo_salva_e_encerrada = true
	var enviado: bool = OnlineTransport.send_all(
		self,
		&"_finalizar_salvar_e_sair_rede",
		[],
		true,
		true
	)
	if not enviado:
		_partida_sendo_salva_e_encerrada = false
		_enviar_resultado_salvamento(
			peer_solicitante,
			false,
			"A PARTIDA FOI SALVA, MAS NÃO FOI POSSÍVEL ENCERRAR A SALA",
			false
		)


func _enviar_resultado_salvamento(
	peer_destino: int,
	sucesso: bool,
	mensagem: String,
	encerrando: bool
) -> void:
	if peer_destino <= 0:
		return
	OnlineTransport.send_player(
		peer_destino,
		self,
		&"_notificar_resultado_salvamento_rede",
		[sucesso, mensagem, encerrando],
		true,
		true
	)


@rpc("authority", "call_local", "reliable")
func _notificar_resultado_salvamento_rede(
	sucesso: bool,
	mensagem: String,
	encerrando: bool
) -> void:
	_notificar_resultado_salvamento_local(sucesso, mensagem, encerrando)


func _notificar_resultado_salvamento_local(
	sucesso: bool,
	mensagem: String,
	encerrando: bool
) -> void:
	if menu_pause != null and menu_pause.has_method("notificar_resultado_salvamento"):
		menu_pause.notificar_resultado_salvamento(sucesso, mensagem, encerrando)


@rpc("authority", "call_local", "reliable")
func _finalizar_salvar_e_sair_rede() -> void:
	if not is_inside_tree():
		return
	_partida_sendo_salva_e_encerrada = true
	_pausa_global_ativa = false
	_peer_iniciador_pausa = 0
	_personagem_iniciador_pausa = ""
	_nome_iniciador_pausa = ""
	_menu_pause_bloqueando_acoes = false
	get_tree().paused = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	if menu_pause != null and menu_pause.has_method("fechar_imediatamente"):
		menu_pause.fechar_imediatamente()

	# O host permanece na sala por alguns frames para o broadcast chegar a todos
	# antes de cada cliente encerrar sua conexão com a sala antiga.
	await get_tree().create_timer(0.45, true).timeout
	if OnlineTransport.usando_photon():
		PhotonManager.sair_sala()

	var limite_ms: int = Time.get_ticks_msec() + 2200
	while PhotonManager.esta_em_sala() and Time.get_ticks_msec() < limite_ms:
		await get_tree().create_timer(0.10, true).timeout

	Global.escolhas_da_mesa.clear()
	Global.user_ids_da_mesa.clear()
	Global.escolhas_por_user_id.clear()
	Global.modo_online = false
	Global.fase_online = "online_lobby"
	Global.cena_online_atual = OnlineTransport.CENA_ONLINE
	get_tree().change_scene_to_file(OnlineTransport.CENA_ONLINE)


func _on_menu_pause_solicitar_desistencia() -> void:
	if _partida_encerrada or _desistencia_local_pendente:
		return
	_desistencia_local_pendente = true

	if OnlineTransport.usando_photon():
		if not OnlineTransport.solicitar_desistencia_partida_ao_host():
			_desistencia_local_pendente = false
			if menu_pause != null and menu_pause.has_method("restaurar_apos_falha_desistencia"):
				menu_pause.restaurar_apos_falha_desistencia(
					"FALHA AO ENVIAR A DESISTÊNCIA"
				)
		return

	if OnlineTransport.is_host():
		if not _processar_solicitacao_desistencia(OnlineTransport.local_player_id()):
			_desistencia_local_pendente = false
			if menu_pause != null and menu_pause.has_method("restaurar_apos_falha_desistencia"):
				menu_pause.restaurar_apos_falha_desistencia(
					"NÃO FOI POSSÍVEL IDENTIFICAR O JOGADOR"
				)
	else:
		var enviado := OnlineTransport.send_host(
			self,
			&"_solicitar_desistencia_servidor",
			[],
			false
		)
		if not enviado:
			_desistencia_local_pendente = false
			if menu_pause != null and menu_pause.has_method("restaurar_apos_falha_desistencia"):
				menu_pause.restaurar_apos_falha_desistencia(
					"FALHA AO ENVIAR A DESISTÊNCIA"
				)


func _on_solicitacao_desistencia_partida_online(peer_solicitante: int) -> void:
	if not OnlineTransport.usando_photon() or not OnlineTransport.is_host():
		return
	if not _processar_solicitacao_desistencia(peer_solicitante):
		push_warning(
			"[DESISTÊNCIA PHOTON] Solicitação rejeitada para peer=%d"
			% peer_solicitante
		)


@rpc("any_peer", "call_remote", "reliable")
func _solicitar_desistencia_servidor() -> void:
	if not OnlineTransport.is_host() or _partida_encerrada:
		return
	var peer_solicitante := OnlineTransport.get_remote_sender_id()
	if not _processar_solicitacao_desistencia(peer_solicitante):
		OnlineTransport.send_player(
			peer_solicitante,
			self,
			&"_notificar_falha_desistencia_rede",
			["NÃO FOI POSSÍVEL PROCESSAR A DESISTÊNCIA"],
			true,
			true
		)


@rpc("authority", "call_local", "reliable")
func _notificar_falha_desistencia_rede(mensagem: String) -> void:
	_desistencia_local_pendente = false
	if menu_pause != null and menu_pause.has_method("restaurar_apos_falha_desistencia"):
		menu_pause.restaurar_apos_falha_desistencia(mensagem)


func _processar_solicitacao_desistencia(peer_id: int) -> bool:
	if not OnlineTransport.is_host() or _partida_encerrada:
		return false

	var jogador_id := _personagem_por_peer_pause(peer_id)
	# Fallback para testes locais sem sala configurada. Nesse caso, considera
	# que o jogador do turno atual é quem confirmou a desistência.
	if jogador_id.is_empty() and not OnlineTransport.esta_em_sala():
		jogador_id = jogador_atual_id
	if jogador_id.is_empty() or not dados_economia_jogadores.has(jogador_id):
		return false
	if bool(dados_economia_jogadores[jogador_id].get("falido", false)):
		return false

	# A confirmação da desistência encerra primeiro a pausa global. O pacote de
	# retomada é enviado pelo mesmo host antes dos pacotes de eliminação/vitória.
	if _pausa_global_ativa and not _forcar_retomada_pausa_host():
		return false

	var restantes: Array[String] = []
	for id_variant in lista_turnos:
		var id_jogador := str(id_variant)
		if id_jogador == jogador_id:
			continue
		if not dados_economia_jogadores.has(id_jogador):
			continue
		if bool(dados_economia_jogadores[id_jogador].get("falido", false)):
			continue
		restantes.append(id_jogador)

	var vencedor_id := restantes[0] if restantes.size() == 1 else ""
	print(
		"[DESISTÊNCIA] peer=%d jogador=%s restantes=%s vencedor=%s"
		% [peer_id, jogador_id, str(restantes), vencedor_id]
	)

	# Se o próprio host está desistindo, ele não pode encerrar a conexão antes
	# de o vencedor confirmar que recebeu e apresentou o resultado final.
	var host_local_desistindo := (
		peer_id == OnlineTransport.local_player_id()
		and OnlineTransport.is_host()
		and not vencedor_id.is_empty()
	)
	if host_local_desistindo:
		_aguardando_confirmacao_vitoria_desistencia = true
		_vitoria_desistencia_confirmada_no_vencedor = false
		_vencedor_desistencia_aguardado = vencedor_id

	if OnlineTransport.usando_photon():
		var token := OnlineTransport.publicar_resultado_desistencia_partida(
			jogador_id,
			vencedor_id
		)
		if token.is_empty():
			_aguardando_confirmacao_vitoria_desistencia = false
			_vitoria_desistencia_confirmada_no_vencedor = false
			_vencedor_desistencia_aguardado = ""
			return false
		_token_desistencia_online_atual = token
		return true

	var enviado := OnlineTransport.send_all(
		self,
		&"_resolver_desistencia_rede",
		[jogador_id, vencedor_id],
		true,
		true
	)
	if not enviado:
		_aguardando_confirmacao_vitoria_desistencia = false
		_vitoria_desistencia_confirmada_no_vencedor = false
		_vencedor_desistencia_aguardado = ""
		return false

	if not vencedor_id.is_empty():
		var peer_vencedor := _peer_do_personagem_pause(vencedor_id)
		if peer_vencedor > 0:
			OnlineTransport.send_player(
				peer_vencedor,
				self,
				&"_confirmar_vitoria_por_desistencia_rede",
				[vencedor_id, jogador_id],
				true,
				true
			)
	return true


func _on_resultado_desistencia_partida_online(
	token: String,
	jogador_desistente: String,
	vencedor: String
) -> void:
	if token.is_empty() or not OnlineTransport.usando_photon():
		return
	if _tokens_desistencia_processados.has(token):
		OnlineTransport.limpar_resultado_desistencia_pendente(token)
		return
	_tokens_desistencia_processados[token] = true
	_token_desistencia_online_atual = token
	# Resultado terminal sempre vence o estado de pausa. Mesmo que o pacote de
	# retomada tenha atrasado, a tela de vitória precisa processar imediatamente.
	_pausa_global_ativa = false
	_peer_iniciador_pausa = 0
	_personagem_iniciador_pausa = ""
	_nome_iniciador_pausa = ""
	_menu_pause_bloqueando_acoes = false
	get_tree().paused = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	if menu_pause != null and menu_pause.has_method("fechar_imediatamente"):
		menu_pause.fechar_imediatamente()
	print(
		"[DESISTÊNCIA] Aplicando token=%s local=%s desistente=%s vencedor=%s"
		% [token, _personagem_local_pause(), jogador_desistente, vencedor]
	)
	_resolver_desistencia_rede(jogador_desistente, vencedor)
	OnlineTransport.limpar_resultado_desistencia_pendente(token)

	if (
		not vencedor.is_empty()
		and _personagem_local_pause() == vencedor
	):
		call_deferred(
			"_confirmar_apresentacao_vitoria_desistencia_apos_delay",
			vencedor
		)


func _on_confirmacao_vitoria_desistencia_online(
	token: String,
	peer_confirmando: int,
	vencedor: String
) -> void:
	if not OnlineTransport.usando_photon() or not OnlineTransport.is_host():
		return
	if not _aguardando_confirmacao_vitoria_desistencia:
		return
	if token != _token_desistencia_online_atual:
		return
	if vencedor != _vencedor_desistencia_aguardado:
		return
	var peer_vencedor := _peer_do_personagem_pause(vencedor)
	if peer_vencedor > 0 and peer_confirmando != peer_vencedor:
		return
	_vitoria_desistencia_confirmada_no_vencedor = true


@rpc("authority", "call_local", "reliable")
func _confirmar_vitoria_por_desistencia_rede(
	vencedor_id: String,
	jogador_desistente_id: String
) -> void:
	# O pacote direcionado pode chegar antes do broadcast geral. Garante que o
	# desistente seja removido localmente antes de montar placar e tela final.
	if (
		dados_economia_jogadores.has(jogador_desistente_id)
		and not bool(dados_economia_jogadores[jogador_desistente_id].get("falido", false))
	):
		_resolver_desistencia_rede(jogador_desistente_id, "")
	_declarar_vencedor_rede(vencedor_id, jogador_desistente_id)

	# O vencedor confirma ao host somente depois de a animação principal da
	# tela final ter tido tempo de aparecer. Enquanto essa confirmação não
	# chega, o host desistente permanece na sala e não derruba a sessão.
	if _personagem_local_pause() == vencedor_id:
		call_deferred(
			"_confirmar_apresentacao_vitoria_desistencia_apos_delay",
			vencedor_id
		)


func _confirmar_apresentacao_vitoria_desistencia_apos_delay(vencedor_id: String) -> void:
	await get_tree().create_timer(
		ATRASO_CONFIRMACAO_TELA_VITORIA,
		true,
		false,
		true
	).timeout
	if not is_inside_tree():
		return
	if _personagem_local_pause() != vencedor_id:
		return
	if OnlineTransport.usando_photon():
		OnlineTransport.confirmar_vitoria_desistencia_ao_host(
			_token_desistencia_online_atual,
			vencedor_id
		)
		return
	OnlineTransport.send_host(
		self,
		&"_confirmar_apresentacao_vitoria_desistencia_servidor",
		[vencedor_id],
		false
	)


@rpc("any_peer", "call_remote", "reliable")
func _confirmar_apresentacao_vitoria_desistencia_servidor(vencedor_id: String) -> void:
	if not OnlineTransport.is_host():
		return
	if not _aguardando_confirmacao_vitoria_desistencia:
		return
	if vencedor_id != _vencedor_desistencia_aguardado:
		return

	var peer_confirmando := OnlineTransport.get_remote_sender_id()
	var peer_vencedor := _peer_do_personagem_pause(vencedor_id)
	if peer_vencedor > 0 and peer_confirmando != peer_vencedor:
		return
	_vitoria_desistencia_confirmada_no_vencedor = true


@rpc("authority", "call_local", "reliable")
func _resolver_desistencia_rede(jogador_id: String, vencedor_id: String = "") -> void:
	if not dados_economia_jogadores.has(jogador_id):
		return

	var dados: Dictionary = dados_economia_jogadores[jogador_id]
	if bool(dados.get("falido", false)):
		# Ainda permite finalizar a vitória se este pacote for uma repetição
		# posterior ao pacote direcionado ao vencedor.
		if not vencedor_id.is_empty() and not _partida_encerrada:
			var meu_jogador_repetido := _personagem_local_pause()
			if meu_jogador_repetido != jogador_id:
				_declarar_vencedor_rede(vencedor_id, jogador_id)
		return

	dados["falido"] = true
	dados["desistiu"] = true
	dados["dinheiro"] = maxi(0, int(dados.get("dinheiro", 0)))
	_limpar_obrigacoes_falencia(jogador_id)
	_cancelar_promessas_do_jogador(jogador_id)
	_registrar_acao(
		"falencia",
		str(dados.get("nome", jogador_id)) + " desistiu da partida.",
		jogador_id
	)

	# Enquanto o salvamento de partidas não está implementado, os bens do
	# desistente retornam diretamente ao banco.
	for casa_variant in registro_propriedades.keys().duplicate():
		var casa_id := int(casa_variant)
		if str(registro_propriedades.get(casa_id, "")) != jogador_id:
			continue
		registro_propriedades.erase(casa_id)
		if tabuleiro.has(casa_id):
			tabuleiro[casa_id]["nivel"] = 0
			tabuleiro[casa_id]["hipotecada"] = false
		_atualizar_visual_dono(casa_id)
		_atualizar_imagem_construcao(casa_id)
	dados["propriedades_compradas"] = 0
	dados["propriedades_lista"] = []

	var indice_desistente := lista_turnos.find(jogador_id)
	if indice_desistente >= 0:
		lista_turnos.remove_at(indice_desistente)
		if indice_desistente < indice_turno_atual:
			indice_turno_atual -= 1
	if indice_turno_atual >= lista_turnos.size():
		indice_turno_atual = 0
	if not lista_turnos.is_empty():
		jogador_atual_id = str(lista_turnos[indice_turno_atual])

	if pinos_jogadores.has(jogador_id):
		pinos_jogadores[jogador_id].modulate = Color(0.35, 0.35, 0.4, 0.55)

	_atualizar_hud_ciclo_turno()

	var meu_jogador := _personagem_local_pause()
	var sou_desistente_local := (
		_desistencia_local_pendente
		and (meu_jogador == jogador_id or meu_jogador.is_empty())
	)
	if sou_desistente_local:
		# Em uma partida de dois jogadores, o resultado já foi decidido. Impede
		# que timers ou fases do tabuleiro continuem avançando enquanto o host
		# aguarda a confirmação visual do vencedor.
		if not vencedor_id.is_empty():
			_partida_encerrada = true
		call_deferred("_sair_para_menu_apos_desistencia")

	if not vencedor_id.is_empty():
		# Quem desistiu sai silenciosamente; somente os demais clientes executam
		# apresentação de vitória/derrota. Isso evita animar nós que serão liberados.
		if not sou_desistente_local:
			_declarar_vencedor_rede(vencedor_id, jogador_id)
	elif OnlineTransport.is_host():
		_verificar_permissao_de_clique()


func _sair_para_menu_apos_desistencia() -> void:
	var era_host_online := OnlineTransport.is_host()

	if era_host_online and _aguardando_confirmacao_vitoria_desistencia:
		var inicio_espera_ms: int = Time.get_ticks_msec()
		var limite_espera_ms: int = int(
			TEMPO_MAXIMO_CONFIRMACAO_VITORIA_DESISTENCIA * 1000.0
		)
		while (
			not _vitoria_desistencia_confirmada_no_vencedor
			and Time.get_ticks_msec() - inicio_espera_ms < limite_espera_ms
		):
			await get_tree().create_timer(0.1, true, false, true).timeout
			if not is_inside_tree():
				return

		# Pequena margem para o último pacote confiável ser processado e para a
		# interface do vencedor concluir a entrada dos botões.
		await get_tree().create_timer(0.65, true, false, true).timeout
	else:
		await get_tree().create_timer(1.25, true, false, true).timeout

	if not is_inside_tree():
		return
	get_tree().paused = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	if menu_pause != null and menu_pause.has_method("fechar_imediatamente"):
		menu_pause.fechar_imediatamente()

	# No Photon, sair apenas da sala é suficiente e permite a migração do host.
	# Desconectar totalmente logo após um RPC final podia encerrar a sessão antes
	# de o outro jogador processar a tela de vitória.
	if OnlineTransport.usando_photon():
		PhotonManager.sair_sala()
	elif OnlineTransport.usando_lan():
		NetworkManager.desconectar("Você desistiu da partida.")

	_aguardando_confirmacao_vitoria_desistencia = false
	_vitoria_desistencia_confirmada_no_vencedor = false
	_vencedor_desistencia_aguardado = ""
	_token_desistencia_online_atual = ""
	_tokens_desistencia_processados.clear()
	Global.modo_online = false
	Global.fase_online = "online_lobby"
	Global.cena_online_atual = OnlineTransport.CENA_ONLINE
	Global.escolhas_da_mesa.clear()
	Global.user_ids_da_mesa.clear()
	Global.escolhas_por_user_id.clear()
	get_tree().change_scene_to_file("res://scenes/ui/tela_inicial/menu_principal.tscn")


# ============================================================================
# NOVO: SISTEMA DE FALÊNCIA E VITÓRIA
# ============================================================================
func _verificar_falencia(jogador_id: String, eliminador_id: String = ""):
								var dados = dados_economia_jogadores[jogador_id]
								if dados.get("falido", false):
																return
								# Falência só pode ser acionada por uma dívida que deixou o saldo
								# NEGATIVO. Saldo zero é um estado válido: o jogador continua ativo
								# e ainda pode receber aluguel, negociar ou passar pela Partida.
								if dados["dinheiro"] >= 0:
																_limpar_obrigacoes_falencia(jogador_id)
																return
								

								# --- CORREÇÃO CRÍTICA: Sincroniza propriedades_lista com registro_propriedades.
								#     Se o jogador tem propriedades em registro_propriedades mas propriedades_lista
								#     está vazia (inconsistência de estado), reconstrói a lista. Sem isso,
								#     o plano de salvamento não encontra propriedades para vender e declara
								#     falência direta — o bug 3 onde "o jogo deu falência sem vender as
								#     propriedades". Também remove da lista props que o jogador não possui
								#     mais (foram transferidas em negociação ou leilão). ---
								var props_registradas: Array = []
								for id_casa in registro_propriedades.keys():
																if registro_propriedades[id_casa] == jogador_id:
																										props_registradas.append(id_casa)
								var lista_atual = dados.get("propriedades_lista", [])
								var lista_sincronizada: Array = []
								for casa_id in lista_atual:
																if props_registradas.has(casa_id) and not lista_sincronizada.has(casa_id):
																										lista_sincronizada.append(casa_id)
								# Adiciona props que estão no registro mas não na lista
								for casa_id in props_registradas:
																if not lista_sincronizada.has(casa_id):
																										lista_sincronizada.append(casa_id)
								dados["propriedades_lista"] = lista_sincronizada
								dados["propriedades_compradas"] = lista_sincronizada.size()
								
								# ====================================================================
								# PLANO DE SALVAMENTO (segue a ordem do GDD e regras do usuário):
								# 1) VENDER CONSTRUÇÕES (casas/hotéis): vende do MAIS CARO para o
								#    mais barato — cada nível devolve 50% do custo da obra.
								#    (Custo da obra = preco * 0.5 * nível; devolve metade = preco * 0.25 * nível.)
								# 2) HIPOTECAR PROPRIEDADES: hipoteca do MAIS BARATO para o mais
								#    caro (conforme solicitado pelo usuário), recebendo 50% do preço.
								#    Propriedades com construção não podem ser hipotecadas (mas a
								#    etapa 1 já deveria ter vendido todas as construções).
								# 3) Se ainda está negativo → FALÊNCIA. As propriedades permanecem
								#    com o falido até _declarar_falencia_rede(), onde serão
								#    recolhidas para oferta do Igor e leilão.
								# ====================================================================

								# --- ETAPA 1: VENDER CONSTRUÇÕES (do mais caro para o mais barato) ---
								# Constrói lista de (casa_id, nível) ordenada por nível decrescente
								# (nível 5 = hotel vale mais; nível 1 = casa simples vale menos).
								# Continua vendendo até dinheiro >= 0 ou não houver mais construções.
								while dados["dinheiro"] < 0:
																var candidatas_venda_constr: Array = []
																for casa_id in dados.get("propriedades_lista", []):
																								if tabuleiro.has(casa_id) and tabuleiro[casa_id].get("nivel", 0) > 0 and not tabuleiro[casa_id].get("hipotecada", false):
																																candidatas_venda_constr.append({
																																				"id": casa_id,
																																				"nivel": tabuleiro[casa_id]["nivel"],
																																				"preco": tabuleiro[casa_id]["preco"],
																																				"valor_devolucao": tabuleiro[casa_id]["preco"] * 0.25 * tabuleiro[casa_id]["nivel"],
																																})
																if candidatas_venda_constr.is_empty():
																								break  # não há mais construções para vender
																# Encontra a de MAIOR valor de devolução (mais cara primeiro)
																var alvo_idx = 0
																for i in range(1, candidatas_venda_constr.size()):
																								if candidatas_venda_constr[i].valor_devolucao > candidatas_venda_constr[alvo_idx].valor_devolucao:
																																alvo_idx = i
																# Vende a escolhida
																var alvo = candidatas_venda_constr[alvo_idx]
																var nivel_alvo = alvo.nivel
																var devolucao = int(alvo.valor_devolucao)
																tabuleiro[alvo.id]["nivel"] = 0  # zera a construção
																_atualizar_imagem_construcao(alvo.id)
																dados["dinheiro"] += devolucao
																if pinos_jogadores.has(jogador_id):
																								pinos_jogadores[jogador_id].mostrar_texto_flutuante("VENDA OBRA N" + str(nivel_alvo) + " +$" + str(devolucao), Color(0.9, 0.6, 0.2))

								# Se já escapou, para por aqui
								if dados["dinheiro"] >= 0:
																_limpar_obrigacoes_falencia(jogador_id)
																_atualizar_hud_minha_casa()
																_atualizar_hud_ciclo_turno()
																return

								# --- ETAPA 2: HIPOTECAR PROPRIEDADES (do mais barato para o mais caro) ---
								# Conforme solicitado: sempre vende/hipoteca os imóveis mais baratos primeiro,
								# preservando os imóveis mais valiosos com o jogador.
								while dados["dinheiro"] < 0:
																var candidatas_hipoteca: Array = []
																for casa_id in dados.get("propriedades_lista", []):
																								if tabuleiro.has(casa_id) and not tabuleiro[casa_id].get("hipotecada", false):
																																candidatas_hipoteca.append({
																																				"id": casa_id,
																																				"preco": tabuleiro[casa_id]["preco"],
																																})
																if candidatas_hipoteca.is_empty():
																								break  # não há mais propriedades para hipotecar
																# Encontra a de MENOR preço (mais barata primeiro)
																var alvo_hip_idx = 0
																for i in range(1, candidatas_hipoteca.size()):
																								if candidatas_hipoteca[i].preco < candidatas_hipoteca[alvo_hip_idx].preco:
																																alvo_hip_idx = i
																# Hipoteca a escolhida
																var alvo_hip = candidatas_hipoteca[alvo_hip_idx]
																var valor_hip = int(alvo_hip.preco * 0.5)
																tabuleiro[alvo_hip.id]["hipotecada"] = true
																dados["dinheiro"] += valor_hip
																_atualizar_visual_dono(alvo_hip.id)
																if pinos_jogadores.has(jogador_id):
																								pinos_jogadores[jogador_id].mostrar_texto_flutuante("HIPOTECADA +$" + str(valor_hip), Color(0.95, 0.6, 0.2))

								# Se já escapou, para por aqui
								if dados["dinheiro"] >= 0:
																_limpar_obrigacoes_falencia(jogador_id)
																_atualizar_hud_minha_casa()
																_atualizar_hud_ciclo_turno()
																return

								# --- ETAPA 3: DECLARAR FALÊNCIA SEM VENDER PROPRIEDADES AO BANCO ---
								# GDD §9.1: o jogador declara falência quando não consegue pagar uma
								# dívida mesmo depois de hipotecar todas as propriedades. Ao falir, as
								# propriedades restantes NÃO voltam para o banco: elas são recolhidas
								# por _declarar_falencia_rede(), passam primeiro pela oferta do Igor e
								# depois entram na fila de leilões de falência.
								if dados["dinheiro"] < 0:
									if pinos_jogadores.has(jogador_id):
										pinos_jogadores[jogador_id].mostrar_texto_flutuante("FALÊNCIA", Color(0.95, 0.2, 0.2))
									# Só o server chama .rpc() para evitar execução múltipla em multiplayer.
									if OnlineTransport.is_host():
										OnlineTransport.send_all(self, &"_declarar_falencia_rede", [jogador_id, eliminador_id], false, true)
									return

								_atualizar_hud_minha_casa()
								_atualizar_hud_ciclo_turno()


# --- GDD §9.1 — Abutre do Mercado do Igor: abre uma decisão real antes do
#     leilão. Igor pode comprar exatamente UMA propriedade acessível pelo
#     valor de tabela ou recusar; todas as demais seguem para o leilão. ---
func _oferecer_abutre_igor(props_disponiveis: Array) -> Dictionary:
	var resultado := {"comprada": -1, "restantes": props_disponiveis.duplicate()}
	if not OnlineTransport.is_host() or props_disponiveis.is_empty():
		return resultado
	if not lista_turnos.has("igor") or not dados_economia_jogadores.has("igor"):
		return resultado
	var igor_dados: Dictionary = dados_economia_jogadores["igor"]
	if igor_dados.get("falido", false):
		return resultado

	var opcoes: Array = []
	for cid_variant in props_disponiveis:
		var cid = int(cid_variant)
		if not tabuleiro.has(cid):
			continue
		var preco = int(tabuleiro[cid].get("preco", 0))
		if preco <= 0 or int(igor_dados.get("dinheiro", 0)) < preco:
			continue
		var grupo = str(tabuleiro[cid].get("grupo", ""))
		opcoes.append({
			"id": str(cid),
			"nome": str(tabuleiro[cid].get("nome", "Propriedade")).replace("\n", " "),
			"detalhe": grupo + " • Valor de tabela: $" + str(preco) + " • Saldo após compra: $" + str(int(igor_dados.get("dinheiro", 0)) - preco),
			"habilitado": true
		})
	if opcoes.is_empty():
		return resultado
	opcoes.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))

	var prompts := {
		"igor": {
			"titulo": "ABUTRE DO MERCADO",
			"descricao": "Escolha UMA propriedade do jogador falido para comprar pelo valor de tabela antes do leilão. Você também pode recusar.",
			"opcoes": opcoes,
			"min": 1,
			"max": 1,
			"texto_confirmar": "COMPRAR AGORA",
			"texto_recusar": "ENVIAR TUDO AO LEILÃO",
			"permitir_recusar": true,
			"cor": Color(1.0, 0.60, 0.05)
		}
	}
	var respostas = await _executar_sessao_decisoes(
		prompts,
		EVENTO_DECISAO_DURACAO_SEGUNDOS,
		"PRIMEIRA OFERTA DO IGOR",
		"Igor está escolhendo um ativo antes do leilão.",
		Color(1.0, 0.60, 0.05)
	)
	var resposta: Dictionary = respostas.get("igor", {})
	if str(resposta.get("acao", "")) != "confirmar":
		return resultado
	var selecionados: Array = resposta.get("selecionados", [])
	if selecionados.size() != 1:
		return resultado
	var escolhida = int(str(selecionados[0]))
	if not props_disponiveis.has(escolhida):
		return resultado
	var preco_escolhida = int(tabuleiro.get(escolhida, {}).get("preco", 0))
	if preco_escolhida <= 0 or int(igor_dados.get("dinheiro", 0)) < preco_escolhida:
		return resultado
	resultado["comprada"] = escolhida
	var restantes: Array = props_disponiveis.duplicate()
	restantes.erase(escolhida)
	resultado["restantes"] = restantes
	return resultado

func _enfileirar_resolucao_abutre(props_disponiveis: Array) -> void:
	if not OnlineTransport.is_host() or props_disponiveis.is_empty():
		return
	_fila_resolucoes_abutre.append(props_disponiveis.duplicate())
	OnlineTransport.send_all(self, &"_definir_bloqueio_abutre_rede", [true], true, true)
	if not _processando_resolucoes_abutre:
		_processar_fila_resolucoes_abutre.call_deferred()

func _processar_fila_resolucoes_abutre() -> void:
	if not OnlineTransport.is_host() or _processando_resolucoes_abutre:
		return
	_processando_resolucoes_abutre = true
	while not _fila_resolucoes_abutre.is_empty():
		var props: Array = _fila_resolucoes_abutre.pop_front()
		var resultado: Dictionary = await _oferecer_abutre_igor(props)
		OnlineTransport.send_all(self, &"_aplicar_resultado_abutre_rede", [int(resultado.get("comprada", -1)),
			resultado.get("restantes", props)], true, true)
		await get_tree().create_timer(0.25).timeout
	_processando_resolucoes_abutre = false
	OnlineTransport.send_all(self, &"_finalizar_resolucoes_abutre_rede", [], true, true)

@rpc("authority", "call_local")
func _definir_bloqueio_abutre_rede(ativo: bool) -> void:
	_abutre_bloqueando_acoes = ativo
	if ativo:
		if hud:
			hud.esconder_painel_dados()
	elif not _acoes_bloqueadas_por_evento() and not leilao_em_andamento:
		_verificar_permissao_de_clique()

@rpc("authority", "call_local")
func _aplicar_resultado_abutre_rede(casa_comprada: int, props_restantes: Array) -> void:
	if casa_comprada >= 0 and tabuleiro.has(casa_comprada) and dados_economia_jogadores.has("igor"):
		var igor_dados: Dictionary = dados_economia_jogadores["igor"]
		var preco = int(tabuleiro[casa_comprada].get("preco", 0))
		if not igor_dados.get("falido", false) and preco > 0 and int(igor_dados.get("dinheiro", 0)) >= preco:
			igor_dados["dinheiro"] -= preco
			igor_dados["propriedades_compradas"] = int(igor_dados.get("propriedades_compradas", 0)) + 1
			if not igor_dados.get("propriedades_lista", []).has(casa_comprada):
				igor_dados["propriedades_lista"].append(casa_comprada)
			registro_propriedades[casa_comprada] = "igor"
			_registrar_aquisicao_propriedade(casa_comprada, "igor")
			_atualizar_visual_dono(casa_comprada)
			_verificar_novos_monopolios_xp("igor")
			Animacoes.banner_cinematico(
				hud.get_node("Control"),
				"ABUTRE DO MERCADO!",
				"Igor comprou " + str(tabuleiro[casa_comprada].get("nome", "uma propriedade")).replace("\n", " ") + " por $" + str(preco) + ".",
				Color(1.0, 0.60, 0.05),
				2.8
			)
			if pinos_jogadores.has("igor"):
				pinos_jogadores["igor"].mostrar_texto_flutuante("PRIMEIRA OFERTA -$" + str(preco), Color(1.0, 0.60, 0.05))
				pinos_jogadores["igor"].celebrar()

	for cid_variant in props_restantes:
		var cid = int(cid_variant)
		if tabuleiro.has(cid) and not registro_propriedades.has(cid) and not _props_leilao_falencia.has(cid):
			_props_leilao_falencia.append(cid)
	if not _props_leilao_falencia.is_empty():
		_leilao_falencia_ativo = true
	_atualizar_hud_ciclo_turno()

@rpc("authority", "call_local")
func _finalizar_resolucoes_abutre_rede() -> void:
	_abutre_bloqueando_acoes = false
	if OnlineTransport.is_host():
		if _leilao_falencia_ativo and not leilao_em_andamento:
			_iniciar_leilao_falencia_agendado.call_deferred()
		elif _props_leilao_falencia.is_empty():
			_verificar_vitoria()
	if not _acoes_bloqueadas_por_evento() and not leilao_em_andamento and not _leilao_falencia_ativo:
		_verificar_permissao_de_clique()

func _distribuir_caixa_remanescente_falencia(jogador_id: String) -> void:
	if not dados_economia_jogadores.has(jogador_id):
		return
	var dados_devedor: Dictionary = dados_economia_jogadores[jogador_id]
	var obrigacoes: Dictionary = obrigacoes_falencia_pendentes.get(jogador_id, {})
	var credores: Array = []
	var total_devido: int = 0
	for credor_variant in obrigacoes.keys():
		var credor_id: String = str(credor_variant)
		var valor_devido: int = maxi(0, int(obrigacoes.get(credor_id, 0)))
		if valor_devido <= 0:
			continue
		credores.append(credor_id)
		total_devido += valor_devido
	credores.sort()

	if total_devido <= 0:
		dados_devedor["dinheiro"] = 0
		_limpar_obrigacoes_falencia(jogador_id)
		return

	# Os débitos já foram lançados integralmente. Somar o saldo negativo ao
	# total devido reconstrói o caixa que de fato restou após a liquidação.
	var saldo_final: int = int(dados_devedor.get("dinheiro", 0))
	var caixa_disponivel: int = clampi(total_devido + saldo_final, 0, total_devido)
	var pagamentos: Dictionary = {}
	var restos: Array = []
	var total_distribuido: int = 0
	for credor_variant in credores:
		var credor_id: String = str(credor_variant)
		var valor_devido: int = int(obrigacoes[credor_id])
		var numerador: int = caixa_disponivel * valor_devido
		var pagamento: int = floori(float(numerador) / float(total_devido))
		pagamentos[credor_id] = pagamento
		total_distribuido += pagamento
		restos.append({
			"credor": credor_id,
			"resto": numerador % total_devido
		})

	# Distribui centavos inteiros restantes pelos maiores restos; o id do credor
	# resolve empates e mantém todos os peers determinísticos.
	restos.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var resto_a: int = int(a["resto"])
		var resto_b: int = int(b["resto"])
		if resto_a == resto_b:
			return str(a["credor"]) < str(b["credor"])
		return resto_a > resto_b
	)
	var unidades_restantes: int = caixa_disponivel - total_distribuido
	for indice in range(unidades_restantes):
		var credor_id: String = str(restos[indice]["credor"])
		pagamentos[credor_id] = int(pagamentos[credor_id]) + 1

	var resumo_rateio: PackedStringArray = PackedStringArray()
	var credores_insolventes: Array = []
	for credor_variant in credores:
		var credor_id: String = str(credor_variant)
		var valor_devido: int = int(obrigacoes[credor_id])
		var valor_recebido: int = int(pagamentos.get(credor_id, 0))
		var valor_estornado: int = valor_devido - valor_recebido
		var nome_credor: String = "Banco"
		if credor_id != CREDOR_FALENCIA_BANCO and dados_economia_jogadores.has(credor_id):
			var dados_credor: Dictionary = dados_economia_jogadores[credor_id]
			nome_credor = str(dados_credor.get("nome", credor_id))
			dados_credor["dinheiro"] = int(dados_credor.get("dinheiro", 0)) - valor_estornado
			if pinos_jogadores.has(credor_id):
				pinos_jogadores[credor_id].mostrar_texto_flutuante(
					"RATEIO: $%d DE $%d" % [valor_recebido, valor_devido],
					Color(0.95, 0.75, 0.25)
				)
			if (
				int(dados_credor.get("dinheiro", 0)) < 0
				and not dados_credor.get("falido", false)
			):
				credores_insolventes.append(credor_id)
		resumo_rateio.append("%s $%d/$%d" % [nome_credor, valor_recebido, valor_devido])

	dados_devedor["dinheiro"] = 0
	_limpar_obrigacoes_falencia(jogador_id)
	_registrar_acao(
		"falencia",
		"Rateio proporcional de %s: %s." % [
			str(dados_devedor.get("nome", jogador_id)),
			", ".join(resumo_rateio)
		],
		jogador_id
	)
	_atualizar_hud_ciclo_turno()
	for credor_variant in credores_insolventes:
		_verificar_falencia.call_deferred(str(credor_variant))

@rpc("any_peer", "call_local")
func _declarar_falencia_rede(jogador_id: String, eliminador_id: String = ""):
								if not dados_economia_jogadores.has(jogador_id):
																return
								var dados: Dictionary = dados_economia_jogadores[jogador_id]
								if dados.get("falido", false):
																return
								_distribuir_caixa_remanescente_falencia(jogador_id)
								dados["falido"] = true
								var colocacao_falido := lista_turnos.size()
								if colocacao_falido == 2:
									_conceder_xp_partida(jogador_id, XP_SEGUNDO_LUGAR, "colocacao_2", "Terminou em 2º lugar")
								elif colocacao_falido == 3:
									_conceder_xp_partida(jogador_id, XP_TERCEIRO_LUGAR, "colocacao_3", "Terminou em 3º lugar")
								_creditar_eliminacao_xp(eliminador_id, jogador_id)
								_registrar_snapshot_final(jogador_id, colocacao_falido)
								_cancelar_promessas_do_jogador(jogador_id)
								var nome_falido_hist = dados.get("nome", jogador_id)
								_registrar_acao("falencia", nome_falido_hist + " declarou falência.", jogador_id)
				
								# --- CORREÇÃO CRÍTICA: Limpa TODOS os estados de habilidade do falido.
								#     Antes, as habilidades do falido continuavam ativas após a falência:
								#     - decreto_turnos do Breno continuava dobrando aluguéis de um grupo
								#     - especulacao_turnos do Igor continuava dobrando aluguel de uma casa
								#     - vazamento_ativo da Diana continuava anulando aluguéis
								#     Isso causava bug 3: Mira caía numa casa de Breno (já falido) e
								#     pagava aluguel DOBRADO pelo decreto que Breno ativou antes de falir.
								#     O aluguel inflado fazia Mira falir mesmo tendo propriedades para
								#     vender. Agora limpamos todos os estados para que o falido não
								#     afete mais o jogo. ---
								dados["decreto_turnos"] = 0
								dados.erase("decreto_grupo")
								dados["especulacao_turnos"] = 0
								dados.erase("especulacao_casa")
								dados["vazamento_ativo"] = false
								dados.erase("vazamento_turnos")
								dados["divida_ativa"] = 0
								dados["divida_original"] = 0
								dados["turnos_divida"] = 0
								dados["credor_divida"] = ""
								dados["mutirao_ativo"] = false
								dados["evento_imune_atual"] = ""
								dados["imunidades"] = []
								dados["aliancas"] = []
								
								# --- CORREÇÃO: Limpa imunidades e alianças de OUTROS jogadores que
								#     referenciam o falido. Sem isso, um jogador poderia ter imunidade
								#     contra um falido (inútil) ou aliança com um falido (inútil). ---
								for outro_id in dados_economia_jogadores.keys():
																if outro_id == jogador_id:
																										continue
																var dados_outro = dados_economia_jogadores[outro_id]
																# Limpa imunidades que referenciam o falido
																var imunidades_validas: Array = []
																for imun in dados_outro.get("imunidades", []):
																										if imun.get("de", "") != jogador_id:
																																				imunidades_validas.append(imun)
																dados_outro["imunidades"] = imunidades_validas
																# Limpa alianças que referenciam o falido
																var aliancas_validas: Array = []
																for alianca in dados_outro.get("aliancas", []):
																										if alianca.get("com", "") != jogador_id:
																																				aliancas_validas.append(alianca)
																dados_outro["aliancas"] = aliancas_validas
								
								# Kofi recebe 200 de redistribuição
								if dados_economia_jogadores.has("kofi") and not dados_economia_jogadores["kofi"].get("falido", false):
																dados_economia_jogadores["kofi"]["dinheiro"] += 200
																if pinos_jogadores.has("kofi"):
																								pinos_jogadores["kofi"].mostrar_texto_flutuante("SOLIDARIEDADE +$200", Color(0.9, 0.8, 0.2))
								# --- NOVO (GDD §9.1): Coleta todas as propriedades do falido
								#     para ir a LEILÃO entre os jogadores restantes.
								#     Antes, as props voltavam direto para o banco. ---
								var props_para_leilao: Array = []
								for id in tabuleiro.keys():
																if registro_propriedades.has(id) and registro_propriedades[id] == jogador_id:
																								# Reseta construções e hipotecas
																								tabuleiro[id]["nivel"] = 0
																								tabuleiro[id]["hipotecada"] = false
																								# Remove do registro (fica sem dono até o leilão)
																								registro_propriedades.erase(id)
																								props_para_leilao.append(id)
																								_atualizar_visual_dono(id)
																								_atualizar_imagem_construcao(id)
								dados["propriedades_compradas"] = 0
								dados["propriedades_lista"] = []

				# Abutre do Mercado é resolvido pelo servidor com uma escolha real de
				# UMA propriedade. O restante só entra na fila depois da decisão.
								# --- CORREÇÃO: Tela de falência SÓ aparece para o jogador que faliu.
								#     Os outros jogadores veem apenas um aviso flutuante. ---
								var meu_id_local_fal = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
								if meu_id_local_fal == jogador_id:
																hud.mostrar_tela_falencia(dados["nome"])
								else:
																# Outros jogadores veem um banner avisando
																Animacoes.banner_cinematico(hud.get_node("Control"), "JOGADOR ELIMINADO", dados["nome"] + " faliu!", Color(0.9, 0.3, 0.3), 2.5)
								# Remove o jogador da lista de turnos ativos
								# --- CORREÇÃO CRÍTICA: Antes de remover, captura o índice do falido
								#     para ajustar indice_turno_atual corretamente. Antes, se um jogador
								#     NÃO-atual falia (ex: por efeito de carta "rouba_todos"), o índice
								#     do jogador atual podia shiftar e apontar para o jogador errado.
								#     Isso causava bugs onde o turno pulava para outro jogador após
								#     uma falência indireta. ---
								var indice_falido = -1
								for i in range(lista_turnos.size()):
																if lista_turnos[i] == jogador_id:
																										indice_falido = i
																										break
								if jogador_id in lista_turnos:
																lista_turnos.erase(jogador_id)
								# Animação de "explosão" no pino
								if pinos_jogadores.has(jogador_id):
																pinos_jogadores[jogador_id].tremer(8.0, 0.8)
																pinos_jogadores[jogador_id].modulate = Color(0.4, 0.4, 0.4, 0.6)  # Cinza transparente
								# --- NOVO (GDD §9.1): Se há propriedades para leiloar, inicia o leilão.
								#     A verificação de vitória só acontece APÓS todos os leilões.
								#     CASO DE BORDA: se já estamos em um leilão de falência (ex: o
								#     vencedor de um leilão anterior faliu), as novas props são
								#     ADICIONADAS à fila existente em vez de sobrescrever. ---
								if props_para_leilao.size() > 0 and lista_turnos.size() >= 1:
																if OnlineTransport.is_host():
																								_enfileirar_resolucao_abutre(props_para_leilao)
								else:
																_verificar_vitoria()
								# --- CORREÇÃO CRÍTICA: Ajusta indice_turno_atual quando um jogador fali.
								#     - Se o falido estava ANTES do jogador atual (indice_falido < indice_turno_atual):
								#       decrementa indice_turno_atual para continuar apontando para o mesmo jogador.
								#     - Se o falido ERA o jogador atual (indice_falido == indice_turno_atual):
								#       após a remoção, indice_turno_atual aponta para o PRÓXIMO jogador (correto,
								#       pois o turno do falido é cancelado e passa ao próximo).
								#     - Se o falido estava DEPOIS do jogador atual (indice_falido > indice_turno_atual):
								#       não muda o índice (o jogador atual não foi afetado).
								#     Antes, o índice não era ajustado, fazendo o turno pular para o jogador
								#     errado quando um não-atual falia. ---
								if indice_falido >= 0 and indice_falido < indice_turno_atual:
																indice_turno_atual -= 1
								# Atualiza turno se necessário
								if indice_turno_atual >= lista_turnos.size():
																indice_turno_atual = 0
								if indice_turno_atual < 0:
																indice_turno_atual = 0
								if not lista_turnos.is_empty():
																jogador_atual_id = lista_turnos[indice_turno_atual]

# --- NOVO: Função separada para agendar o início do leilão de falência.
#     Usa call_deferred para não bloquear _declarar_falencia_rede com await. ---
func _iniciar_leilao_falencia_agendado():
								if not OnlineTransport.is_host():
																return
								if not _leilao_falencia_ativo:
																return
								await get_tree().create_timer(3.0).timeout
								if not _leilao_falencia_ativo or leilao_em_andamento or _abutre_bloqueando_acoes or _processando_resolucoes_abutre:
																return
								# Usa .rpc() para que TODOS os peers executem juntos
								OnlineTransport.send_all(self, &"_iniciar_proximo_leilao_falencia", [], true, true)

# --- NOVO (GDD §9.1): Inicia o próximo leilão da fila de falência.
#     Chamado pelo server após cada leilão terminar.
#     É um RPC para que TODOS os peers façam pop_front na fila juntos. ---
@rpc("authority", "call_local")
func _iniciar_proximo_leilao_falencia():
								if _props_leilao_falencia.is_empty():
																# Todos os leilões terminaram — limpa flag e verifica vitória
																_leilao_falencia_ativo = false
																_verificar_vitoria()
																# --- CORREÇÃO CRÍTICA: Se ainda há jogadores vivos (não acabou o jogo),
																#     precisa reativar os dados para o jogador atual. Antes, após
																#     o leilão de falência terminar, ninguém chamava _verificar_permissao_de_clique
																#     e o jogo ficava sem dados. ---
																if lista_turnos.size() > 1:
																								if indice_turno_atual >= lista_turnos.size():
																																indice_turno_atual = 0
																								if not lista_turnos.is_empty():
																																jogador_atual_id = lista_turnos[indice_turno_atual]
																								_verificar_permissao_de_clique()
																return
								# Pega a próxima propriedade da fila (TODOS os peers fazem isso)
								var proxima_casa = _props_leilao_falencia[0]
								_props_leilao_falencia.pop_front()
								# Inicia o leilão em todos os peers
								OnlineTransport.send_all(self, &"_iniciar_leilao_rede", [proxima_casa], false, true)

func _verificar_vitoria():
								# A decisão é autoritativa do servidor e só pode ocorrer uma vez.
								if not OnlineTransport.is_host() or _partida_encerrada:
																return

								# Conta todos os jogadores não falidos. Saldo e propriedades definem
								# se o último sobrevivente já pode vencer, mas não removem ninguém da
								# disputa. Assim, um jogador com $0 continua vivo.
								var jogadores_ativos: Array = []
								for p_id in lista_turnos.duplicate():
																if not dados_economia_jogadores.has(p_id):
																																continue
																if dados_economia_jogadores[p_id].get("falido", false):
																																continue
																jogadores_ativos.append(p_id)

								# Vitória comum: deve restar exatamente um jogador não falido. O
								# desempate por patrimônio é reservado para partidas com limite de
								# tempo e não pode encerrar uma partida normal no primeiro round.
								if jogadores_ativos.size() != 1:
																return

								var vencedor_id: String = jogadores_ativos[0]
								var dados_vencedor = dados_economia_jogadores[vencedor_id]
								if dados_vencedor.get("dinheiro", 0) <= 0:
																return
								if dados_vencedor.get("propriedades_compradas", 0) <= 0:
																return

								dados_vencedor["vencedor"] = true
								OnlineTransport.send_all(self, &"_declarar_vencedor_rede", [vencedor_id], false, true)

# --- NOVO: Verifica se um jogador tem monopólio de TODOS os grupos do tabuleiro.
#     Condição de vitória por domínio completo. ---
func _tem_monopolio_total(jogador_id: String) -> bool:
								var grupos_do_jogador: Dictionary = {}
								for casa_id in registro_propriedades.keys():
																if registro_propriedades[casa_id] == jogador_id:
																								var grupo = tabuleiro[casa_id].get("grupo", "")
																								if grupo not in ["Especial", "Utilidade", "Transporte", "Portal"]:
																																grupos_do_jogador[grupo] = true
								# Conta quantos grupos únicos existem no tabuleiro
								var grupos_existentes: Dictionary = {}
								for casa_id in tabuleiro.keys():
																var grupo = tabuleiro[casa_id].get("grupo", "")
																if grupo not in ["Especial", "Utilidade", "Transporte", "Portal"]:
																								grupos_existentes[grupo] = true
								return grupos_do_jogador.size() >= grupos_existentes.size() and grupos_existentes.size() > 0

# --- NOVO (GDD §9.2): Critérios de desempate para vitória.
#     1o: Maior patrimônio total (dinheiro + valor de propriedades)
#     2o: Maior número de propriedades
#     3o: Menor número de hipotecas ativas ---
func _aplicar_criterios_desempate(candidatos: Array) -> String:
								var melhor = candidatos[0]
								var melhor_patrimonio = _calcular_patrimonio(melhor)
								var melhor_props = dados_economia_jogadores[melhor]["propriedades_compradas"]
								var melhor_hipotecas = _contar_hipotecas_do_jogador(melhor)
								for i in range(1, candidatos.size()):
																var id = candidatos[i]
																var pat = _calcular_patrimonio(id)
																var props = dados_economia_jogadores[id]["propriedades_compradas"]
																var hips = _contar_hipotecas_do_jogador(id)
																# 1o critério: maior patrimônio
																if pat > melhor_patrimonio:
																								melhor = id
																								melhor_patrimonio = pat
																								melhor_props = props
																								melhor_hipotecas = hips
																elif pat == melhor_patrimonio:
																								# 2o critério: mais propriedades
																								if props > melhor_props:
																																melhor = id
																																melhor_patrimonio = pat
																																melhor_props = props
																																melhor_hipotecas = hips
																								elif props == melhor_props:
																																# 3o critério: menos hipotecas
																																if hips < melhor_hipotecas:
																																								melhor = id
																																								melhor_patrimonio = pat
																																								melhor_props = props
																																								melhor_hipotecas = hips
								return melhor

# --- NOVO: Calcula o patrimônio total de um jogador (dinheiro + valor de propriedades). ---
func _calcular_patrimonio(jogador_id: String) -> int:
								var total = dados_economia_jogadores[jogador_id].get("dinheiro", 0)
								for casa_id in dados_economia_jogadores[jogador_id].get("propriedades_lista", []):
																if tabuleiro.has(casa_id):
																								total += tabuleiro[casa_id].get("preco", 0)
																								# Adiciona valor das construções (nível * 50% do preço)
																								var nivel = tabuleiro[casa_id].get("nivel", 0)
																								if nivel > 0:
																																total += int(tabuleiro[casa_id]["preco"] * 0.5 * nivel)
								return total

@rpc("any_peer", "call_local")
func _declarar_vencedor_rede(
	vencedor_id: String,
	jogador_desistente_id: String = ""
) -> void:
	if _partida_encerrada:
		return
	if not dados_economia_jogadores.has(vencedor_id):
		push_error("Vencedor inválido recebido: %s" % vencedor_id)
		return

	_partida_encerrada = true
	if OnlineTransport.usando_photon() and OnlineTransport.is_host():
		GerenciadorSalvamento.marcar_partida_finalizada()
	_finalizar_rastreamento_evento_xp()
	var dados_vencedor: Dictionary = dados_economia_jogadores[vencedor_id]
	_conceder_xp_partida(vencedor_id, XP_VITORIA, "colocacao_1", "Venceu a partida")
	dados_vencedor["vencedor"] = true
	_registrar_snapshot_final(vencedor_id, 1)
	_registrar_acao(
		"vitoria",
		str(dados_vencedor.get("nome", vencedor_id)) + " venceu a partida.",
		vencedor_id
	)
	var placar_final := _montar_placar_final(vencedor_id)
	placar_final["progressao_local"] = _persistir_progressao_local(placar_final)

	var meu_id_local_vit := _personagem_local_pause()
	var sou_desistente := (
		not jogador_desistente_id.is_empty()
		and meu_id_local_vit == jogador_desistente_id
	)
	# O cliente que confirmou a desistência já está retornando ao menu. Não cria
	# banners, partículas ou telas que seriam liberados durante os awaits.
	if sou_desistente:
		return
	if hud == null or not is_instance_valid(hud):
		return

	if meu_id_local_vit == vencedor_id:
		if hud.has_method("mostrar_tela_vitoria"):
			hud.mostrar_tela_vitoria(str(dados_vencedor.get("nome", vencedor_id)))
	else:
		var hud_control := hud.get_node_or_null("Control")
		if hud_control != null:
			Animacoes.banner_cinematico(
				hud_control,
				"FIM DE JOGO",
				str(dados_vencedor.get("nome", vencedor_id)) + " venceu a partida!",
				Color(1.0, 0.85, 0.15),
				3.0
			)
		await get_tree().create_timer(3.5).timeout
		if not is_inside_tree() or hud == null or not is_instance_valid(hud):
			return
		var nome_perdedor := str(
			dados_economia_jogadores.get(meu_id_local_vit, {}).get(
				"nome",
				meu_id_local_vit
			)
		)
		if hud.has_method("mostrar_tela_derrota"):
			hud.mostrar_tela_derrota(
				nome_perdedor,
				str(dados_vencedor.get("nome", vencedor_id))
			)

	if pinos_jogadores.has(vencedor_id):
		pinos_jogadores[vencedor_id].celebrar()

	if camera != null and is_instance_valid(camera):
		var half_view_w: float = (VIEWPORT_LARGURA / float(camera.zoom.x)) / 2.0
		var half_view_h: float = (VIEWPORT_ALTURA / float(camera.zoom.y)) / 2.0
		for _i in range(20):
			var pos := Vector2(
				randf_range(-half_view_w, half_view_w),
				randf_range(-half_view_h, half_view_h)
			)
			Animacoes.explosao_particulas(
				self,
				camera.position + pos,
				Color(1, 0.85, 0.15),
				8,
				60
			)

	var hud_control_final := hud.get_node_or_null("Control")
	if hud_control_final != null:
		Animacoes.flash_de_tela(
			hud_control_final,
			Color(1.0, 0.85, 0.15, 0.6),
			1.0
		)
	await get_tree().create_timer(1.0).timeout
	if (
		is_inside_tree()
		and hud != null
		and is_instance_valid(hud)
		and hud.has_method("mostrar_placar_final_completo")
	):
		hud.mostrar_placar_final_completo(placar_final)

# ============================================================================
# NOVO: INICIALIZAÇÃO DE JOGADORES ATIVOS E CONEXÃO DE SINAIS
# ============================================================================
func _init_jogadores_ativos():
								jogadores_ativos = lista_turnos.duplicate()

# Conecta os novos sinais da HUD (chamado em _ready)
func _conectar_sinais_hud_novos():
								if hud.has_signal("solicitar_habilidade"):
																hud.solicitar_habilidade.connect(_on_hud_solicitar_habilidade)
								# --- NOVO (UI de seleção de alvo): conecta o signal que pede a lista
								#     de alvos válidos para a habilidade do personagem. ---
								if hud.has_signal("solicitar_opcoes_alvo"):
																hud.solicitar_opcoes_alvo.connect(_on_hud_solicitar_opcoes_alvo)
								if hud.has_signal("solicitar_hipoteca"):
																hud.solicitar_hipoteca.connect(_on_hud_solicitar_hipoteca)
								if hud.has_signal("solicitar_fianca_prisao"):
																hud.solicitar_fianca_prisao.connect(_on_hud_solicitar_fianca_prisao)
								# --- NOVO (Fase 1 — Negociação): conecta os 2 novos signals da HUD ---
								if hud.has_signal("solicitar_negociacao"):
																hud.solicitar_negociacao.connect(_on_hud_solicitar_negociacao)
								if hud.has_signal("responder_negociacao"):
																hud.responder_negociacao.connect(_on_hud_responder_negociacao)
								# --- NOVO (Fase 3 — Alianças): conecta signals de aliança ---
								if hud.has_signal("solicitar_alianca"):
																hud.solicitar_alianca.connect(_on_hud_solicitar_alianca)
								# responder_alianca não é necessário — usamos responder_negociacao
								# (o tipo da proposta diferencia aliança de troca)
								# --- NOVO (Fase 4 — Promessas): conecta signals de promessas ---
								if hud.has_signal("solicitar_criar_promessa"):
																hud.solicitar_criar_promessa.connect(_on_hud_solicitar_criar_promessa)
								if hud.has_signal("solicitar_quebrar_promessa"):
																hud.solicitar_quebrar_promessa.connect(_on_hud_solicitar_quebrar_promessa)
								# --- NOVO (Eleições Municipais): conecta signal de voto. ---
								if hud.has_signal("voto_eleicao_enviado"):
																hud.voto_eleicao_enviado.connect(_on_hud_voto_eleicao)

								# Eventos globais com decisão do jogador.
								if hud.has_signal("decisao_evento_enviada"):
																hud.decisao_evento_enviada.connect(_on_hud_decisao_evento)
# ============================================================================
# SISTEMA DE NEGOCIAÇÃO (Fase 1 — MVP: Troca de dinheiro + propriedades)
# ============================================================================
# Implementa 3 RPCs:
#   1. _enviar_proposta_negociacao_rede(proposta)   — A envia para todos; B mostra modal
#   2. _responder_proposta_negociacao_rede(id, ok, aceitador) — B responde; se aceitou, todos executam
#   3. _executar_negociacao_rede(proposta)          — todos aplicam a troca atomicamente
#
# Regras (Fase 1):
#   - Não toca em _calcular_aluguel nem em _pagar_aluguel_rede.
#   - Propriedades com hotéis (nível 5) e hipotecadas são transferíveis.
#   - Não pode negociar consigo mesmo nem com falidos.
#   - Limite de 3 propostas pendentes por receptor (anti-spam).
# ============================================================================

# Propostas pendentes por receptor. Estrutura: { "id_proposta": proposta_dict }
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
func fornecer_dados_para_negociacao() -> Dictionary:
				return {
								"dados_jogadores": dados_economia_jogadores,
								"tabuleiro_data": tabuleiro,
						"registro_props": registro_propriedades,
						"lista_turnos": lista_turnos,
						"promessas": _promessas_globais,
						"turno_global": _contador_turnos_globais,
				}

# --- Helper: converte personagem_id (ex.: "igor") em peer_id (ex.: 7) ---
# Itera Global.escolhas_da_mesa = { peer_id: personagem_id }.
# Retorna 1 se não encontrar (assume host/server local).
func _peer_id_do(personagem_id: String) -> int:
				for peer_id in Global.escolhas_da_mesa.keys():
								if Global.escolhas_da_mesa[peer_id] == personagem_id:
												return peer_id
				return 1  # fallback: host local

# --- Handler do signal "solicitar_negociacao" da HUD ---
# Recebe a proposta do proponente local e a encaminha para todos via RPC.
# Validações locais pesadas (saldo, posse de props) já foram feitas no painel;
# aqui fazemos apenas validação de sanidade final no servidor antes do broadcast.
func _on_hud_solicitar_negociacao(proposta: Dictionary):
				if _acao_bloqueada_por_eleicao(true):
								return
				# Não permite negociar durante leilão ativo (regra definida na análise)
				if leilao_em_andamento:
								if pinos_jogadores.has(proposta.get("de", "")):
												pinos_jogadores[proposta["de"]].mostrar_texto_flutuante("NEGOCIAR BLOQUEADO NO LEILÃO", Color(0.9, 0.3, 0.3))
								hud.atualizar_status_negociacao("❌ Negociações bloqueadas durante leilão.", Color(0.95, 0.3, 0.3))
								await get_tree().create_timer(1.5).timeout
								hud.fechar_painel_negociacao()
								return
				# Breno é imune especificamente ao Acordo de Silêncio. Bloqueios de
				# negociação causados por outros efeitos, como Apagão, ainda valem.
				var proponente_id: String = str(proposta.get("de", ""))
				var bloqueada_por_acordo: bool = _acordo_silencio_bloqueia(proponente_id)
				var bloqueada_por_efeito: bool = _negociacoes_bloqueadas_por_efeito(proponente_id)
				if bloqueada_por_acordo or bloqueada_por_efeito:
								var motivo_bloqueio: String = "ACORDO DE SILÊNCIO ATIVO" if bloqueada_por_acordo else "NEGOCIAÇÕES BLOQUEADAS"
								if pinos_jogadores.has(proponente_id):
																pinos_jogadores[proponente_id].mostrar_texto_flutuante(motivo_bloqueio, Color(0.9, 0.3, 0.3))
								var status_bloqueio: String = "❌ Negociações bloqueadas pelo Acordo de Silêncio neste turno." if bloqueada_por_acordo else "❌ Negociações bloqueadas por um efeito ativo."
								hud.atualizar_status_negociacao(status_bloqueio, Color(0.95, 0.3, 0.3))
								await get_tree().create_timer(1.5).timeout
								hud.fechar_painel_negociacao()
								return
				# Não permite negociar durante vitória/falência (lista_turnos vazia)
				if lista_turnos.size() < 2:
								hud.atualizar_status_negociacao("❌ Partida encerrada.", Color(0.95, 0.3, 0.3))
								await get_tree().create_timer(1.5).timeout
								hud.fechar_painel_negociacao()
								return
				# Encaminha para todos (cada peer decide se deve mostrar o modal)
				OnlineTransport.send_all(self, &"_enviar_proposta_negociacao_rede", [proposta], false, true)

# --- NOVO (Fase 3 — Alianças): handler do signal "solicitar_alianca" da HUD.
#     Mesma lógica de negociação: valida contexto (sem leilão, partida ativa)
#     e encaminha via _enviar_proposta_negociacao_rede (reaproveita o mesmo RPC,
#     pois a proposta carrega "tipo": "alianca" para diferenciação). ---
func _on_hud_solicitar_alianca(proposta: Dictionary):
				if _acao_bloqueada_por_eleicao(true):
								return
				if leilao_em_andamento:
								if pinos_jogadores.has(proposta.get("de", "")):
												pinos_jogadores[proposta["de"]].mostrar_texto_flutuante("ALIANÇA BLOQUEADA NO LEILÃO", Color(0.9, 0.3, 0.3))
								hud.atualizar_status_negociacao("❌ Alianças bloqueadas durante leilão.", Color(0.95, 0.3, 0.3))
								await get_tree().create_timer(1.5).timeout
								hud.fechar_painel_negociacao()
								return
				var proponente_id: String = str(proposta.get("de", ""))
				var bloqueada_por_acordo: bool = _acordo_silencio_bloqueia(proponente_id)
				var bloqueada_por_efeito: bool = _negociacoes_bloqueadas_por_efeito(proponente_id)
				if bloqueada_por_acordo or bloqueada_por_efeito:
								var motivo_bloqueio: String = "ACORDO DE SILÊNCIO ATIVO" if bloqueada_por_acordo else "ALIANÇAS BLOQUEADAS"
								if pinos_jogadores.has(proponente_id):
																pinos_jogadores[proponente_id].mostrar_texto_flutuante(motivo_bloqueio, Color(0.9, 0.3, 0.3))
								var status_bloqueio: String = "❌ Alianças bloqueadas pelo Acordo de Silêncio neste turno." if bloqueada_por_acordo else "❌ Alianças bloqueadas por um efeito ativo."
								hud.atualizar_status_negociacao(status_bloqueio, Color(0.95, 0.3, 0.3))
								await get_tree().create_timer(1.5).timeout
								hud.fechar_painel_negociacao()
								return
				if lista_turnos.size() < 2:
								hud.atualizar_status_negociacao("❌ Partida encerrada.", Color(0.95, 0.3, 0.3))
								await get_tree().create_timer(1.5).timeout
								hud.fechar_painel_negociacao()
								return
				# Encaminha para todos (reaproveita o RPC de negociação — a proposta
				# tem "tipo": "alianca" para o receptor saber que é aliança)
				OnlineTransport.send_all(self, &"_enviar_proposta_negociacao_rede", [proposta], false, true)

# ============================================================================
# RPC 1: PROPONENTE ENVIA A PROPOSTA — todos recebem, mas só o "para" mostra modal
# ============================================================================
@rpc("any_peer", "call_local")
func _enviar_proposta_negociacao_rede(proposta: Dictionary):
				if _acoes_bloqueadas_por_evento():
								return
				var de_id: String = str(proposta.get("de", ""))
				var para_id: String = str(proposta.get("para", ""))
				# Sanity: de e para devem existir
				if not dados_economia_jogadores.has(de_id) or not dados_economia_jogadores.has(para_id):
								return
				if _acordo_silencio_bloqueia(de_id) or _negociacoes_bloqueadas_por_efeito(de_id):
								return
				# Sanity: não pode ser consigo mesmo
				if de_id == para_id:
								return
				# Verifica limite anti-spam (3 propostas pendentes por receptor)
				var contador = 0
				for p in _propostas_negociacao_pendentes.values():
								if p.get("para", "") == para_id:
												contador += 1
				if contador >= 3:
								# Avisa o proponente que o alvo está saturado
								if pinos_jogadores.has(de_id):
												pinos_jogadores[de_id].mostrar_texto_flutuante("ALVO COM MUITAS PROPOSTAS PENDENTES", Color(0.9, 0.3, 0.3))
								# Se o proponente for o jogador local, fecha o painel com mensagem
								var meu_id_local = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
								if de_id == meu_id_local:
												hud.atualizar_status_negociacao("❌ Esse jogador já tem muitas propostas pendentes. Tente novamente mais tarde.", Color(0.95, 0.3, 0.3))
												await get_tree().create_timer(2.5).timeout
												hud.fechar_painel_negociacao()
								return
				# Registra a proposta como pendente
				# --- BUG FIX (HIGH #7): Adiciona timestamp para timeout. Se o receptor
				#     não responder em 60s, o server recusa automaticamente. ---
				proposta["timestamp"] = Time.get_ticks_msec()
				_propostas_negociacao_pendentes[proposta.get("id_proposta", "")] = proposta
				# Server agenda timeout para auto-recusar se não houver resposta
				if OnlineTransport.is_host():
								_agendar_timeout_proposta(proposta.get("id_proposta", ""))
				# Feedback visual no pino do proponente
				if pinos_jogadores.has(de_id):
								# --- NOVO (Fase 3): feedback diferente para aliança vs troca ---
								var tipo_msg = proposta.get("tipo", "troca")
								if tipo_msg == "alianca":
																pinos_jogadores[de_id].mostrar_texto_flutuante("ALIANÇA PROPOSTA → " + para_id.to_upper(), Color(0.95, 0.85, 0.15))
								else:
																pinos_jogadores[de_id].mostrar_texto_flutuante("PROPOSTA ENVIADA → " + para_id.to_upper(), Color(0.4, 0.8, 1.0))
				# Apenas o jogador local que É o "para" mostra o modal de resposta
				var meu_id = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
				if para_id == meu_id:
								# Mostra o modal em modo resposta
								hud.mostrar_proposta_recebida(proposta)
				# Jogadores controlados pela IA avaliam a mesma proposta sem abrir
				# uma interface local. A execução continua passando pelas validações
				# e pelo RPC normal, exatamente como em uma resposta humana.
				if _eh_jogador_bot(para_id):
								call_deferred(
									"_responder_negociacao_bot",
									str(proposta.get("id_proposta", ""))
								)


func _responder_negociacao_bot(id_proposta: String) -> void:
	if id_proposta.is_empty():
		return
	await get_tree().create_timer(0.85).timeout
	if not is_inside_tree() or not _propostas_negociacao_pendentes.has(id_proposta):
		return
	var proposta_variant: Variant = _propostas_negociacao_pendentes.get(
		id_proposta,
		{}
	)
	if not proposta_variant is Dictionary:
		return
	var proposta: Dictionary = proposta_variant
	var para_id: String = str(proposta.get("para", ""))
	if not _eh_jogador_bot(para_id):
		return
	var bot: Node = _bots_jogadores.get(para_id) as Node
	if bot == null or not is_instance_valid(bot):
		return

	var aceita: bool = false
	if str(proposta.get("tipo", "troca")) == "alianca":
		aceita = true
	elif bot.has_method("avaliar_negociacao"):
		var oferece_variant: Variant = proposta.get("oferece", {})
		var pede_variant: Variant = proposta.get("pede", {})
		var oferece: Dictionary = (
			oferece_variant if oferece_variant is Dictionary else {}
		)
		var pede: Dictionary = pede_variant if pede_variant is Dictionary else {}
		var valor_recebido: int = _valor_pacote_negociacao_bot(oferece)
		var valor_entregue: int = _valor_pacote_negociacao_bot(pede)
		aceita = bool(
			bot.call("avaliar_negociacao", valor_recebido, valor_entregue)
		)
	OnlineTransport.send_all(
		self,
		&"_responder_proposta_negociacao_rede",
		[id_proposta, aceita, para_id],
		false,
		true
	)


func _valor_pacote_negociacao_bot(pacote: Dictionary) -> int:
	var total: int = maxi(0, int(pacote.get("dinheiro", 0)))
	var propriedades_variant: Variant = pacote.get("propriedades", [])
	if propriedades_variant is Array:
		for casa_variant: Variant in propriedades_variant:
			var casa_id: int = int(casa_variant)
			if not tabuleiro.has(casa_id):
				continue
			var valor_propriedade: int = _calcular_valor_propriedade(casa_id)
			var nivel: int = int(tabuleiro[casa_id].get("nivel", 0))
			if bool(tabuleiro[casa_id].get("hipotecada", false)):
				valor_propriedade = int(valor_propriedade * 0.5)
			elif nivel > 0:
				valor_propriedade += int(valor_propriedade * 0.5 * nivel)
			total += valor_propriedade
	total += maxi(0, int(pacote.get("imunidade_visitas", 0))) * 100
	total += maxi(0, int(pacote.get("passes_transporte", 0))) * 75
	return total

# --- BUG FIX (HIGH #7): Agenda timeout de 60s para uma proposta. Se o
#     receptor não responder, o server recusa automaticamente.
#     Evita propostas pendentes eternamente se o receptor sair da partida
#     ou simplesmente ignorar. ---
func _agendar_timeout_proposta(id_proposta: String):
								# Só o server agenda timeouts
								if not OnlineTransport.is_host():
																return
								await get_tree().create_timer(60.0).timeout
								# Verifica se a proposta ainda está pendente (pode ter sido respondida)
								if _propostas_negociacao_pendentes.has(id_proposta):
																# Auto-recusa
																var proposta = _propostas_negociacao_pendentes[id_proposta]
																var para_id = proposta.get("para", "")
																# Emite a recusa como se viesse do receptor (mas é o server)
																OnlineTransport.send_all(self, &"_responder_proposta_negociacao_rede", [id_proposta, false, para_id], false, true)

# ============================================================================
# RPC 2: RECEPTOR RESPONDE — se aceitou, todos executam a troca
# ============================================================================
# Handler do signal "responder_negociacao" da HUD
func _on_hud_responder_negociacao(id_proposta: String, aceita: bool, aceitador: String):
				if _acao_bloqueada_por_eleicao(true):
								return
				OnlineTransport.send_all(self, &"_responder_proposta_negociacao_rede", [id_proposta, aceita, aceitador], false, true)

@rpc("any_peer", "call_local")
func _responder_proposta_negociacao_rede(id_proposta: String, aceita: bool, aceitador: String):
				if _acoes_bloqueadas_por_evento():
								return
				if not _propostas_negociacao_pendentes.has(id_proposta):
								# Proposta não existe mais (timeout? bug?) — apenas ignora
								return
				var proposta: Dictionary = _propostas_negociacao_pendentes[id_proposta]
				var de_id: String = str(proposta.get("de", ""))
				var para_id: String = str(proposta.get("para", ""))
				# Sanity: o aceitador deve ser o "para" da proposta
				if aceitador != para_id:
								return
				# Uma proposta antiga não pode contornar um bloqueio que começou
				# depois do envio. Propostas feitas por Breno continuam aceitando
				# resposta durante o Acordo de Silêncio, pois a imunidade é dele.
				var bloqueada_por_acordo: bool = _acordo_silencio_bloqueia(de_id)
				var bloqueada_por_efeito: bool = _negociacoes_bloqueadas_por_efeito(de_id)
				if aceita and (bloqueada_por_acordo or bloqueada_por_efeito):
								var meu_id_bloqueio: String = str(Global.escolhas_da_mesa.get(Global.meu_peer_id, ""))
								if meu_id_bloqueio == de_id or meu_id_bloqueio == para_id:
																var mensagem_bloqueio: String = "❌ Acordo de Silêncio ativo; a proposta ficará pendente." if bloqueada_por_acordo else "❌ Negociações bloqueadas por um efeito ativo."
																hud.atualizar_status_negociacao(mensagem_bloqueio, Color(0.95, 0.3, 0.3))
								return
				# Remove das pendentes
				_propostas_negociacao_pendentes.erase(id_proposta)
				# --- NOVO (Fase 3): detecta tipo da proposta ---
				var tipo_proposta = proposta.get("tipo", "troca")
				if aceita:
								if tipo_proposta == "alianca":
												# --- Proposta de ALIANÇA: validação simplificada (não há troca) ---
												var erros_alianca = _validar_alianca_para_execucao(proposta)
												if not erros_alianca.is_empty():
																var msg_erro_al = "❌ Aliança cancelada: " + erros_alianca[0]
																if pinos_jogadores.has(de_id):
																								pinos_jogadores[de_id].mostrar_texto_flutuante("ALIANÇA FALHOU", Color(0.9, 0.3, 0.3))
																if pinos_jogadores.has(para_id):
																								pinos_jogadores[para_id].mostrar_texto_flutuante("ALIANÇA FALHOU", Color(0.9, 0.3, 0.3))
																var meu_id_local_al = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
																if meu_id_local_al == de_id or meu_id_local_al == para_id:
																								hud.atualizar_status_negociacao(msg_erro_al, Color(0.95, 0.3, 0.3))
																								await get_tree().create_timer(2.5).timeout
																								hud.fechar_painel_negociacao()
																return
												# Tudo OK — executa aliança em todos os peers
												# --- CORREÇÃO: Só o server chama .rpc() para evitar execução dupla. ---
												if OnlineTransport.is_host():
																				OnlineTransport.send_all(self, &"_executar_alianca_rede", [proposta], false, true)
												return
								# --- Proposta de TROCA normal: validação completa ---
								var erros = _validar_proposta_para_execucao(proposta)
								if not erros.is_empty():
												# Mostra o erro para ambos os envolvidos
												var msg_erro = "❌ Negociação cancelada: " + erros[0]
												if pinos_jogadores.has(de_id):
																pinos_jogadores[de_id].mostrar_texto_flutuante("NEGOCIAÇÃO FALHOU", Color(0.9, 0.3, 0.3))
												if pinos_jogadores.has(para_id):
																pinos_jogadores[para_id].mostrar_texto_flutuante("NEGOCIAÇÃO FALHOU", Color(0.9, 0.3, 0.3))
												var meu_id_local = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
												if meu_id_local == de_id or meu_id_local == para_id:
																hud.atualizar_status_negociacao(msg_erro, Color(0.95, 0.3, 0.3))
																await get_tree().create_timer(2.5).timeout
																hud.fechar_painel_negociacao()
												return
								# Tudo OK — executa em todos os peers
								# --- CORREÇÃO CRÍTICA: Só o server chama _executar_negociacao_rede.rpc().
								#     Antes, TODOS os peers chamavam .rpc(), fazendo a transferência
								#     acontecer N vezes (N = número de peers). Com 2 peers, o dinheiro
								#     era transferido 2x — $1200 virava $2400, $400 virava $800. ---
								if OnlineTransport.is_host():
																OnlineTransport.send_all(self, &"_executar_negociacao_rede", [proposta], false, true)
				else:
								# Recusou: feedback visual para o proponente
								if pinos_jogadores.has(de_id):
												# --- NOVO (Fase 3): feedback diferente para aliança vs troca ---
												var tipo_recusa = proposta.get("tipo", "troca")
												if tipo_recusa == "alianca":
																pinos_jogadores[de_id].mostrar_texto_flutuante("ALIANÇA RECUSADA", Color(0.9, 0.3, 0.3))
												else:
																pinos_jogadores[de_id].mostrar_texto_flutuante("PROPOSTA RECUSADA", Color(0.9, 0.3, 0.3))
								# Se o proponente for o jogador local, mostra aviso breve e fecha
								var meu_id_local = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
								if meu_id_local == de_id:
												var tipo_msg_recusa = proposta.get("tipo", "troca")
												var msg_recusa = "Proposta recusada por " + dados_economia_jogadores[para_id]["nome"] + "."
												if tipo_msg_recusa == "alianca":
																msg_recusa = "Aliança recusada por " + dados_economia_jogadores[para_id]["nome"] + "."
												hud.atualizar_status_negociacao(msg_recusa, Color(0.95, 0.6, 0.2))
												await get_tree().create_timer(1.2).timeout
												hud.fechar_painel_negociacao()
								# Se o receptor for o jogador local, fecha o painel dele imediatamente
								if meu_id_local == para_id:
												hud.fechar_painel_negociacao()

# --- Re-validação crítica: chamada antes de _executar_negociacao_rede ---
# Verifica que o estado do jogo ainda permite a troca (pode ter mudado entre
# enviar e aceitar, especialmente se houve construção/hipoteca no meio).
func _validar_proposta_para_execucao(proposta: Dictionary) -> Array:
				var erros: Array = []
				var de_id = proposta.get("de", "")
				var para_id = proposta.get("para", "")
				if not dados_economia_jogadores.has(de_id) or not dados_economia_jogadores.has(para_id):
								erros.append("Jogador não existe mais.")
								return erros
				if dados_economia_jogadores[de_id].get("falido", false):
								erros.append("Proponente faliu.")
								return erros
				if dados_economia_jogadores[para_id].get("falido", false):
								erros.append("Receptor faliu.")
								return erros
				var oferece = proposta.get("oferece", {})
				var pede = proposta.get("pede", {})
				var dinheiro_of = int(oferece.get("dinheiro", 0))
				var dinheiro_pe = int(pede.get("dinheiro", 0))
				var saldo_de = dados_economia_jogadores[de_id].get("dinheiro", 0)
				var saldo_para = dados_economia_jogadores[para_id].get("dinheiro", 0)
				if dinheiro_of > saldo_de:
								erros.append("Proponente não tem mais $" + str(dinheiro_of) + ".")
								return erros
				if dinheiro_pe > saldo_para:
								erros.append("Receptor não tem mais $" + str(dinheiro_pe) + ".")
								return erros
				# Verifica posse de cada propriedade
				for casa_id in oferece.get("propriedades", []):
								if not registro_propriedades.has(casa_id) or registro_propriedades[casa_id] != de_id:
												erros.append("Propriedade do proponente mudou de dono.")
												return erros
				for casa_id in pede.get("propriedades", []):
								if not registro_propriedades.has(casa_id) or registro_propriedades[casa_id] != para_id:
												erros.append("Propriedade pedida mudou de dono.")
												return erros
				var passes_of = int(oferece.get("passes_transporte", 0))
				var passes_pe = int(pede.get("passes_transporte", 0))
				if passes_of < 0 or passes_pe < 0 or passes_of > 3 or passes_pe > 3:
								erros.append("Quantidade de passes inválida.")
								return erros
				if passes_of > 0 and _quantidade_linhas_metro(de_id) < 2:
								erros.append("O proponente não possui mais 2 Linhas de Metrô.")
								return erros
				if passes_pe > 0 and _quantidade_linhas_metro(para_id) < 2:
								erros.append("O receptor não possui mais 2 Linhas de Metrô.")
								return erros
				return erros

# ============================================================================
# RPC 3: EXECUTA A TROCA — todos os peers aplicam atomicamente
# ============================================================================
@rpc("any_peer", "call_local")
func _executar_negociacao_rede(proposta: Dictionary):
				var de_id = proposta.get("de", "")
				var para_id = proposta.get("para", "")
				var oferece = proposta.get("oferece", {})
				var pede = proposta.get("pede", {})
				var dinheiro_of = int(oferece.get("dinheiro", 0))
				var dinheiro_pe = int(pede.get("dinheiro", 0))
				var props_oferece: Array = oferece.get("propriedades", [])
				var props_pede: Array = pede.get("propriedades", [])

				# 1) Transfere dinheiro: de → para (líquido = dinheiro_pe - dinheiro_of)
				# Se dinheiro_of > dinheiro_pe: de paga a diferença para para.
				# Se dinheiro_pe > dinheiro_of: para paga a diferença para de.
				# --- NOVO (Fase 3 — Alianças): Taxa de -10% em negociações com terceiros.
				#     Regra do GDD: "aliança concede +10% de aluguel nas propriedades do
				#     aliado, mas ao custo de -10% na negociação com terceiros".
				#     Interpretação: quando um jogador aliado RECEBE dinheiro de um
				#     terceiro (não-aliado) em uma negociação, ele paga 10% de taxa
				#     (os 10% somem — vão para o banco, como subsídio inverso).
				#     Isso é o CUSTO de manter alianças: você ganha +10% aluguel do
				#     aliado (financiado pelo banco), mas perde 10% em negociações
				#     com outros jogadores. Trade-off equilibrado.
				#     IMPORTANTE: se A e B são aliados e A recebe de B, NÃO há taxa
				#     (são aliados diretos). A taxa só aplica em negociações com
				#     terceiros (não-aliados). ---
				var liquido_de_para = dinheiro_of - dinheiro_pe
				# --- CORREÇÃO: Limita a transferência ao saldo disponível do pagador.
				#     Previne saldo negativo se houver race condition entre validação
				#     e execução, ou se o saldo mudou entre criar e aceitar a proposta. ---
				if liquido_de_para > 0:
								# de paga para; para é o recebedor
								var recebedor_id = para_id
								var pagador_id = de_id
								var valor_recebido = liquido_de_para
								# Limita ao saldo do pagador
								var saldo_pagador = dados_economia_jogadores[de_id].get("dinheiro", 0)
								if valor_recebido > saldo_pagador:
																valor_recebido = saldo_pagador
								if valor_recebido <= 0:
																# Pagador não tem dinheiro — aborta transferência
																pass
								else:
																var taxa = _calcular_taxa_alianca(recebedor_id, pagador_id)
																if taxa > 0:
																								var valor_taxa = max(1, int(valor_recebido * taxa))  # CORREÇÃO: mínimo $1
																								var valor_liquido = valor_recebido - valor_taxa
																								dados_economia_jogadores[de_id]["dinheiro"] -= valor_recebido
																								dados_economia_jogadores[para_id]["dinheiro"] += valor_liquido
																								# 10% some (vai pro banco — subsídio inverso)
																								if pinos_jogadores.has(para_id):
																																pinos_jogadores[para_id].mostrar_texto_flutuante("CUSTO ALIANÇA -$" + str(valor_taxa), Color(0.9, 0.6, 0.2))
																else:
																								dados_economia_jogadores[de_id]["dinheiro"] -= valor_recebido
																								dados_economia_jogadores[para_id]["dinheiro"] += valor_recebido
				elif liquido_de_para < 0:
								# para paga para; de é o recebedor
								var recebedor_id2 = de_id
								var pagador_id2 = para_id
								var valor_recebido2 = -liquido_de_para
								# Limita ao saldo do pagador
								var saldo_pagador2 = dados_economia_jogadores[para_id].get("dinheiro", 0)
								if valor_recebido2 > saldo_pagador2:
																valor_recebido2 = saldo_pagador2
								if valor_recebido2 <= 0:
																# Pagador não tem dinheiro — aborta transferência
																pass
								else:
																var taxa2 = _calcular_taxa_alianca(recebedor_id2, pagador_id2)
																if taxa2 > 0:
																								var valor_taxa2 = max(1, int(valor_recebido2 * taxa2))  # CORREÇÃO: mínimo $1
																								var valor_liquido2 = valor_recebido2 - valor_taxa2
																								dados_economia_jogadores[para_id]["dinheiro"] -= valor_recebido2
																								dados_economia_jogadores[de_id]["dinheiro"] += valor_liquido2
																								if pinos_jogadores.has(de_id):
																																pinos_jogadores[de_id].mostrar_texto_flutuante("CUSTO ALIANÇA -$" + str(valor_taxa2), Color(0.9, 0.6, 0.2))
																else:
																								dados_economia_jogadores[para_id]["dinheiro"] -= valor_recebido2
																								dados_economia_jogadores[de_id]["dinheiro"] += valor_recebido2

				# 1.5) --- NOVO (Fase 2 — Imunidades): aplica imunidades temporárias.
				#       Cada lado pode conceder ao outro visitas sem pagar aluguel.
				#       Regra: turnos_restantes = visitas × 2 (1 visita ≈ 2 turnos).
				#       - Se "de" ofereceu N visitas de imunidade, o "para" recebe
				#         imunidade contra "de" por N visitas e 2N turnos.
				#       - Se "para" (via "pede") concedeu M visitas de imunidade,
				#         o "de" recebe imunidade contra "para" por M visitas e 2M turnos.
				#       A imunidade é armazenada no jogador que NÃO vai pagar aluguel
				#       (o pagador), referenciando o recebedor contra quem é imune. ---
				var visitas_of = int(oferece.get("imunidade_visitas", 0))
				var visitas_pe = int(pede.get("imunidade_visitas", 0))
				if visitas_of > 0:
								# "de" concede imunidade ao "para": para não paga aluguel para de
								dados_economia_jogadores[para_id]["imunidades"].append({
												"de": de_id,
												"visitas_restantes": visitas_of,
												"turnos_restantes": visitas_of * 2,
								})
								if pinos_jogadores.has(para_id):
												pinos_jogadores[para_id].mostrar_texto_flutuante("IMUNIDADE: " + str(visitas_of) + " visita(s) vs " + de_id.to_upper(), Color(0.4, 1.0, 0.8))
												# --- NOVO: animação de celebração no pino que recebeu imunidade ---
												pinos_jogadores[para_id].celebrar()
								# --- NOVO: banner cinemático + flash de tela informando a imunidade concedida ---
								var nome_de = dados_economia_jogadores[de_id]["nome"]
								var nome_para = dados_economia_jogadores[para_id]["nome"]
								Animacoes.banner_cinematico(hud.get_node("Control"), "🛡 IMUNIDADE CONCEDIDA", nome_de + " → " + nome_para + " (" + str(visitas_of) + " visitas)", Color(0.4, 1.0, 0.8), 2.0)
								Animacoes.flash_de_tela(hud.get_node("Control"), Color(0.4, 1.0, 0.8, 0.4), 0.5)
								# --- NOVO: partículas verde-água nos dois pinos envolvidos ---
								if pinos_jogadores.has(de_id):
												Animacoes.explosao_particulas(self, pinos_jogadores[de_id].position, Color(0.4, 1.0, 0.8), 12, 60)
								if pinos_jogadores.has(para_id):
												Animacoes.explosao_particulas(self, pinos_jogadores[para_id].position, Color(0.4, 1.0, 0.8), 12, 60)
				if visitas_pe > 0:
								# "para" concede imunidade ao "de": de não paga aluguel para para
								dados_economia_jogadores[de_id]["imunidades"].append({
												"de": para_id,
												"visitas_restantes": visitas_pe,
												"turnos_restantes": visitas_pe * 2,
								})
								if pinos_jogadores.has(de_id):
												pinos_jogadores[de_id].mostrar_texto_flutuante("IMUNIDADE: " + str(visitas_pe) + " visita(s) vs " + para_id.to_upper(), Color(0.4, 1.0, 0.8))
												# --- NOVO: animação de celebração no pino que recebeu imunidade ---
												pinos_jogadores[de_id].celebrar()
								# --- NOVO: banner cinemático + flash de tela (apenas se visitas_of == 0,
								#     para não duplicar o banner quando ambos concedem imunidade) ---
								if visitas_of == 0:
												var nome_de2 = dados_economia_jogadores[de_id]["nome"]
												var nome_para2 = dados_economia_jogadores[para_id]["nome"]
												Animacoes.banner_cinematico(hud.get_node("Control"), "🛡 IMUNIDADE CONCEDIDA", nome_para2 + " → " + nome_de2 + " (" + str(visitas_pe) + " visitas)", Color(0.4, 1.0, 0.8), 2.0)
												Animacoes.flash_de_tela(hud.get_node("Control"), Color(0.4, 1.0, 0.8, 0.4), 0.5)
								# --- NOVO: partículas verde-água (sempre, mesmo se visitas_of > 0) ---
								if pinos_jogadores.has(de_id):
												Animacoes.explosao_particulas(self, pinos_jogadores[de_id].position, Color(0.4, 1.0, 0.8), 12, 60)
								if pinos_jogadores.has(para_id):
												Animacoes.explosao_particulas(self, pinos_jogadores[para_id].position, Color(0.4, 1.0, 0.8), 12, 60)


				# 1.6) Passes de Transporte. Só podem ser concedidos por quem possui
				# pelo menos duas Linhas de Metrô; a validação é repetida no servidor.
				var passes_of = int(oferece.get("passes_transporte", 0))
				var passes_pe = int(pede.get("passes_transporte", 0))
				if passes_of > 0 and _quantidade_linhas_metro(de_id) >= 2:
								_conceder_passes_transporte(de_id, para_id, passes_of)
				if passes_pe > 0 and _quantidade_linhas_metro(para_id) >= 2:
								_conceder_passes_transporte(para_id, de_id, passes_pe)

				# 2) Transfere propriedades oferecidas (de → para)
				for casa_id in props_oferece:
								# Remove da lista do de
								if dados_economia_jogadores[de_id]["propriedades_lista"].has(casa_id):
												dados_economia_jogadores[de_id]["propriedades_lista"].erase(casa_id)
												dados_economia_jogadores[de_id]["propriedades_compradas"] -= 1
								# Adiciona à lista do para
								if not dados_economia_jogadores[para_id]["propriedades_lista"].has(casa_id):
												dados_economia_jogadores[para_id]["propriedades_lista"].append(casa_id)
												dados_economia_jogadores[para_id]["propriedades_compradas"] += 1
								# Atualiza registro central
								registro_propriedades[casa_id] = para_id
								_registrar_aquisicao_propriedade(casa_id, para_id)
								# Atualiza visual da faixa de dono
								_atualizar_visual_dono(casa_id)
								# --- BUG FIX (HIGH #2): Trata hipoteca na transferência. Em Monopoly
								#     clássico, quando uma propriedade hipotecada é transferida, o novo
								#     dono deve pagar 10% de juros ao banco imediatamente. ---
								if tabuleiro[casa_id].get("hipotecada", false):
												var juros = int(tabuleiro[casa_id]["preco"] * 0.5 * 0.1)
												if dados_economia_jogadores[para_id]["dinheiro"] >= juros:
																dados_economia_jogadores[para_id]["dinheiro"] -= juros
																if pinos_jogadores.has(para_id):
																				pinos_jogadores[para_id].mostrar_texto_flutuante("JUROS HIPOTECA -$" + str(juros), Color(0.9, 0.6, 0.2))

				# 3) Transfere propriedades pedidas (para → de)
				for casa_id in props_pede:
								if dados_economia_jogadores[para_id]["propriedades_lista"].has(casa_id):
												dados_economia_jogadores[para_id]["propriedades_lista"].erase(casa_id)
												dados_economia_jogadores[para_id]["propriedades_compradas"] -= 1
								if not dados_economia_jogadores[de_id]["propriedades_lista"].has(casa_id):
												dados_economia_jogadores[de_id]["propriedades_lista"].append(casa_id)
												dados_economia_jogadores[de_id]["propriedades_compradas"] += 1
								registro_propriedades[casa_id] = de_id
								_registrar_aquisicao_propriedade(casa_id, de_id)
								_atualizar_visual_dono(casa_id)
								# --- BUG FIX (HIGH #2): Mesmo tratamento de hipoteca para props_pede. ---
								if tabuleiro[casa_id].get("hipotecada", false):
												var juros2 = int(tabuleiro[casa_id]["preco"] * 0.5 * 0.1)
												if dados_economia_jogadores[de_id]["dinheiro"] >= juros2:
																dados_economia_jogadores[de_id]["dinheiro"] -= juros2
																if pinos_jogadores.has(de_id):
																				pinos_jogadores[de_id].mostrar_texto_flutuante("JUROS HIPOTECA -$" + str(juros2), Color(0.9, 0.6, 0.2))

				_verificar_novos_monopolios_xp(de_id)
				_verificar_novos_monopolios_xp(para_id)

				# 4) Feedback visual + animações
				var pos_de = pinos_jogadores[de_id].position if pinos_jogadores.has(de_id) else Vector2.ZERO
				var pos_para = pinos_jogadores[para_id].position if pinos_jogadores.has(para_id) else Vector2.ZERO
				if pinos_jogadores.has(de_id):
								var msg_de = "NEGOCIADO!"
								if liquido_de_para > 0:
												msg_de = "-$" + str(liquido_de_para) + " + " + str(props_pede.size()) + " prop(s)"
								elif liquido_de_para < 0:
												msg_de = "+$" + str(-liquido_de_para) + " - " + str(props_oferece.size()) + " prop(s)"
								else:
												msg_de = "TROCA: " + str(props_oferece.size()) + "↔" + str(props_pede.size()) + " props"
								pinos_jogadores[de_id].mostrar_texto_flutuante(msg_de, Color(0.4, 0.9, 1.0))
				if pinos_jogadores.has(para_id):
								var msg_para = "NEGOCIADO!"
								if liquido_de_para > 0:
												msg_para = "+$" + str(liquido_de_para) + " - " + str(props_pede.size()) + " prop(s)"
								elif liquido_de_para < 0:
												msg_para = "-$" + str(-liquido_de_para) + " + " + str(props_oferece.size()) + " prop(s)"
								else:
												msg_para = "TROCA: " + str(props_pede.size()) + "↔" + str(props_oferece.size()) + " props"
								pinos_jogadores[para_id].mostrar_texto_flutuante(msg_para, Color(0.4, 0.9, 1.0))

				# Animação de moedas voando entre os dois pinos
				if pinos_jogadores.has(de_id) and pinos_jogadores.has(para_id):
								if liquido_de_para != 0:
												var origem = pos_de if liquido_de_para > 0 else pos_para
												var destino = pos_para if liquido_de_para > 0 else pos_de
												Animacoes.transferencia_moedas(self, origem, destino, Color(1, 0.85, 0.15), 10)

				# Banner cinemático
				var nome_de = dados_economia_jogadores[de_id]["nome"]
				var nome_para = dados_economia_jogadores[para_id]["nome"]
				Animacoes.banner_cinematico(hud.get_node("Control"), "NEGOCIAÇÃO CONCLUÍDA", nome_de + " ↔ " + nome_para, Color(0.4, 0.9, 1.0), 2.0)
				Animacoes.flash_de_tela(hud.get_node("Control"), Color(0.4, 0.8, 1.0, 0.4), 0.5)
				_registrar_acao("negociacao", "%s e %s concluíram uma negociação." % [nome_de, nome_para], de_id)

				# 5) Atualiza HUD
				_atualizar_hud_minha_casa()
				_atualizar_hud_ciclo_turno()
				_atualizar_menu_construcao()

				# 5.5) --- CORREÇÃO: Verifica se a negociação completou um monopólio.
				#       Roda para ambos os envolvidos — qualquer um pode ter completado
				#       um grupo com a troca. Para cada propriedade recebida, checa se
				#       o novo dono agora possui todas as do grupo. Se sim, dispara o
				#       banner de MONOPÓLIO e a animação de celebração do pino.
				#       (Antes, só compras normais e leilões verificavam monopólio;
				#        negociações nunca disparavam o banner, mesmo quando o jogador
				#        ficava com o grupo completo.)
				_verificar_monopolio_apos_negociacao(de_id, props_pede)        # de recebeu as props pedidas
				_verificar_monopolio_apos_negociacao(para_id, props_oferece)   # para recebeu as props oferecidas
				_emitir_evento_tutorial(
								"negociacao_concluida",
								{
												"de": str(de_id),
												"para": str(para_id),
												"propriedades_oferecidas": props_oferece.duplicate(),
												"propriedades_recebidas": props_pede.duplicate(),
												"dinheiro_oferecido": dinheiro_of,
												"dinheiro_pedido": dinheiro_pe,
								}
				)

				# 6) Verifica falência (caso alguém tenha ficado negativo após a troca)
				_verificar_falencia(de_id)
				_verificar_falencia(para_id)

				# 7) Fecha o painel automaticamente após a execução.
				#    - Receptor (quem clicou ACEITAR): fecha IMEDIATAMENTE, pois a animação
				#      de sucesso (banner + moedas + flash) já dá feedback visual suficiente.
				#    - Proponente (quem enviou): mostra "✓ Proposta aceita!" por 0.6s para
				#      confirmar que o outro lado aceitou, depois fecha.
				var meu_id_local = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
				if meu_id_local == para_id:
								# Receptor: fecha na hora
								hud.fechar_painel_negociacao()
				elif meu_id_local == de_id:
								# Proponente: confirmação breve e fecha
								hud.atualizar_status_negociacao("✓ Proposta aceita!", Color(0.4, 1.0, 0.4))
								await get_tree().create_timer(0.6).timeout
								hud.fechar_painel_negociacao()


# --- Helper: verifica se alguma das propriedades recebidas em negociação
#     completou um monopólio para o receptor. Para cada prop recebida, checa
#     o grupo; se o jogador agora possui TODAS do grupo, dispara o banner.
#     Evita duplicar o banner se o mesmo grupo apareceu múltiplas vezes na
#     mesma negociação (raro, mas possível). ---
func _verificar_monopolio_apos_negociacao(jogador_id: String, props_recebidas: Array):
				var grupos_verificados := {}  # grupo -> true (para não repetir o banner)
				for casa_id in props_recebidas:
								if not tabuleiro.has(casa_id):
												continue
								var grupo = tabuleiro[casa_id].get("grupo", "")
								# Grupos especiais não contam como monopólio (regra do _tem_monopolio)
								if grupo in ["Especial", "Utilidade", "Transporte", "Portal"]:
												continue
								if grupos_verificados.has(grupo):
												continue  # já verificamos esse grupo nesta negociação
								grupos_verificados[grupo] = true
								if _tem_monopolio(jogador_id, grupo):
												hud.mostrar_monopolio(grupo)
												if pinos_jogadores.has(jogador_id):
																pinos_jogadores[jogador_id].celebrar()


# ============================================================================
# NOVO (Fase 3 — Alianças): SISTEMA DE ALIANÇAS FORMAIS
# ============================================================================
# Alianças são propostas do tipo "alianca" (em vez de "troca"). Quando aceitas:
#   - Ambos os jogadores recebem uma entrada em "aliancas": { "com": outro_id, "turnos_restantes": N }
#   - +10% no aluguel que um aliado paga ao outro (aplicado em _calcular_aluguel)
#   - -10% de taxa em negociações com terceiros (aplicado em _executar_negociacao_rede)
#   - Expira após N turnos (decrementado em _avancar_turno_rede)
# ============================================================================

# Validação simplificada para aliança (não há troca de dinheiro/props para validar).
# Apenas verifica que ambos os jogadores estão vivos e não são a mesma pessoa.
func _validar_alianca_para_execucao(proposta: Dictionary) -> Array:
				var erros: Array = []
				var de_id = proposta.get("de", "")
				var para_id = proposta.get("para", "")
				if not dados_economia_jogadores.has(de_id) or not dados_economia_jogadores.has(para_id):
								erros.append("Jogador não existe mais.")
								return erros
				if dados_economia_jogadores[de_id].get("falido", false):
								erros.append("Proponente faliu.")
								return erros
				if dados_economia_jogadores[para_id].get("falido", false):
								erros.append("Receptor faliu.")
								return erros
				if de_id == para_id:
								erros.append("Não pode formar aliança consigo mesmo.")
								return erros
				# Verifica se já são aliados (não permitir aliança duplicada)
				if _sao_aliados(de_id, para_id):
								erros.append("Já são aliados.")
								return erros
				return erros

# RPC: executa a formação de aliança em todos os peers (call_local).
# Adiciona a aliança nas listas de ambos os jogadores (bidirecional).
@rpc("any_peer", "call_local")
func _executar_alianca_rede(proposta: Dictionary):
				var de_id = proposta.get("de", "")
				var para_id = proposta.get("para", "")
				var duracao = int(proposta.get("duracao_turnos", 5))

				# Adiciona aliança bidirecional
				dados_economia_jogadores[de_id]["aliancas"].append({
								"com": para_id,
								"turnos_restantes": duracao,
				})
				dados_economia_jogadores[para_id]["aliancas"].append({
								"com": de_id,
								"turnos_restantes": duracao,
				})

				# Feedback visual rico
				var nome_de = dados_economia_jogadores[de_id]["nome"]
				var nome_para = dados_economia_jogadores[para_id]["nome"]
				if pinos_jogadores.has(de_id):
								pinos_jogadores[de_id].mostrar_texto_flutuante("ALIANÇA COM " + nome_para.to_upper(), Color(0.95, 0.85, 0.15))
								pinos_jogadores[de_id].celebrar()
				if pinos_jogadores.has(para_id):
								pinos_jogadores[para_id].mostrar_texto_flutuante("ALIANÇA COM " + nome_de.to_upper(), Color(0.95, 0.85, 0.15))
								pinos_jogadores[para_id].celebrar()

				# Banner cinemático + flash dourado + partículas
				Animacoes.banner_cinematico(hud.get_node("Control"), "🤝 ALIANÇA FORMADA", nome_de + " ↔ " + nome_para + " (" + str(duracao) + " turnos)", Color(0.95, 0.85, 0.15), 2.5)
				_registrar_acao("alianca", "%s e %s formaram aliança por %d turnos." % [nome_de, nome_para, duracao], de_id)
				Animacoes.flash_de_tela(hud.get_node("Control"), Color(0.95, 0.85, 0.15, 0.5), 0.6)
				if pinos_jogadores.has(de_id):
								Animacoes.explosao_particulas(self, pinos_jogadores[de_id].position, Color(0.95, 0.85, 0.15), 16, 80)
				if pinos_jogadores.has(para_id):
								Animacoes.explosao_particulas(self, pinos_jogadores[para_id].position, Color(0.95, 0.85, 0.15), 16, 80)

				# Atualiza HUD
				_atualizar_hud_minha_casa()
				_atualizar_hud_ciclo_turno()

				# --- CORREÇÃO: Fecha o painel de AMBOS os jogadores envolvidos.
				#     - Receptor (quem clicou ACEITAR): fecha IMEDIATAMENTE, pois a
				#       animação de sucesso (banner + partículas) já dá feedback visual.
				#     - Proponente (quem enviou): mostra "✓ Aliança aceita!" por 0.6s
				#       e fecha, para confirmar que o outro lado aceitou. ---
				var meu_id_local = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
				if meu_id_local == para_id:
								# Receptor: fecha na hora
								hud.fechar_painel_negociacao()
				elif meu_id_local == de_id:
								# Proponente: confirmação breve e fecha
								hud.atualizar_status_negociacao("✓ Aliança aceita!", Color(0.4, 1.0, 0.4))
								await get_tree().create_timer(0.6).timeout
								hud.fechar_painel_negociacao()

# --- NOVO (Fase 3 — Alianças): calcula a taxa de aliança aplicável.
#     Retorna 0.10 (10%) se o recebedor tem aliança ativa com um terceiro
#     que NÃO seja o pagador. Caso contrário, retorna 0.0 (sem taxa). ---
func _calcular_taxa_alianca(recebedor_id: String, pagador_id: String) -> float:
				if not dados_economia_jogadores.has(recebedor_id):
								return 0.0
				for alianca in dados_economia_jogadores[recebedor_id].get("aliancas", []):
								var terceiro = alianca.get("com", "")
								if terceiro != pagador_id and terceiro != recebedor_id and alianca.get("turnos_restantes", 0) > 0:
												return 0.10  # 10% de taxa
				return 0.0

# ============================================================================
# REPUTAÇÃO E PROMESSAS PÚBLICAS COM DURAÇÃO AUTOMÁTICA
# ============================================================================
# Uma promessa permanece ativa por 5 turnos globais. Se chegar ao fim sem ser
# reportada como quebrada, é cumprida automaticamente: +10 reputação e +80 XP.
# Quebrar reduz 20 pontos de reputação. A reputação influencia Eventos Globais:
# jogadores com 75+ recebem $40; jogadores com 25- pagam $40 no próximo evento.

func _on_hud_solicitar_criar_promessa(texto: String, autor_id: String):
	if _acao_bloqueada_por_eleicao(false):
		return
	var texto_limpo = texto.strip_edges().substr(0, 180)
	if texto_limpo == "":
		return
	var autor_local = str(Global.escolhas_da_mesa.get(Global.meu_peer_id, autor_id))
	if OnlineTransport.is_host():
		_servidor_criar_promessa(autor_local, texto_limpo)
	else:
		OnlineTransport.send_host(self, &"_solicitar_criar_promessa_servidor", [texto_limpo], false)

@rpc("any_peer", "call_remote", "reliable")
func _solicitar_criar_promessa_servidor(texto: String):
	if not OnlineTransport.is_host():
		return
	var autor_id = _personagem_do_peer(OnlineTransport.get_remote_sender_id())
	_servidor_criar_promessa(autor_id, texto.strip_edges().substr(0, 180))

func _servidor_criar_promessa(autor_id: String, texto: String) -> void:
	if texto == "" or not ordem_original_partida.has(autor_id):
		return
	if not dados_economia_jogadores.has(autor_id) or dados_economia_jogadores[autor_id].get("falido", false):
		return
	var ativas_autor = 0
	for promessa in _promessas_globais:
		if promessa.get("autor_id", "") == autor_id and promessa.get("status", "ativa") == "ativa":
			ativas_autor += 1
	if ativas_autor >= 3:
		return
	var id_unico = "prom_%d_%d_%d" % [OnlineTransport.local_player_id(), Time.get_ticks_msec(), randi() % 100000]
	OnlineTransport.send_all(self, &"_criar_promessa_rede", [id_unico, autor_id, texto, PROMESSA_DURACAO_PADRAO], true, true)

func _on_hud_solicitar_quebrar_promessa(id_promessa: String):
	if _acao_bloqueada_por_eleicao(false):
		return
	var reporter_local = str(Global.escolhas_da_mesa.get(Global.meu_peer_id, ""))
	if reporter_local == "":
		return
	if OnlineTransport.is_host():
		_servidor_reportar_quebra(id_promessa, reporter_local)
	else:
		OnlineTransport.send_host(self, &"_solicitar_quebrar_promessa_servidor", [id_promessa], false)

@rpc("any_peer", "call_remote", "reliable")
func _solicitar_quebrar_promessa_servidor(id_promessa: String):
	if not OnlineTransport.is_host():
		return
	var reporter_id = _personagem_do_peer(OnlineTransport.get_remote_sender_id())
	_servidor_reportar_quebra(id_promessa, reporter_id)

func _servidor_reportar_quebra(id_promessa: String, reporter_id: String) -> void:
	if reporter_id == "" or not ordem_original_partida.has(reporter_id):
		return
	for promessa in _promessas_globais:
		if promessa.get("id", "") != id_promessa:
			continue
		if promessa.get("status", "ativa") != "ativa":
			return
		var autor_id = str(promessa.get("autor_id", ""))
		# O autor pode admitir a quebra; qualquer outro jogador ativo pode reportá-la.
		if reporter_id != autor_id and dados_economia_jogadores.get(reporter_id, {}).get("falido", false):
			return
		OnlineTransport.send_all(self, &"_quebrar_promessa_rede", [id_promessa, reporter_id], true, true)
		return

@rpc("authority", "call_local", "reliable")
func _criar_promessa_rede(id_promessa: String, autor_id: String, texto: String, duracao_turnos: int = PROMESSA_DURACAO_PADRAO):
	for promessa_existente in _promessas_globais:
		if promessa_existente.get("id", "") == id_promessa:
			return
	var duracao = clampi(duracao_turnos, 1, 12)
	var promessa := {
		"id": id_promessa,
		"autor_id": autor_id,
		"texto": texto,
		"status": "ativa",
		"quebrada": false,
		"cumprida": false,
		"cancelada": false,
		"quebrada_por": "",
		"reportada_por": "",
		"turnos_totais": duracao,
		"turnos_restantes": duracao,
		"turno_criacao": _contador_turnos_globais,
	}
	_promessas_globais.append(promessa)
	if pinos_jogadores.has(autor_id):
		pinos_jogadores[autor_id].mostrar_texto_flutuante("PROMESSA: %d TURNOS" % duracao, Color(0.9, 0.8, 0.5))
	var nome_autor = dados_economia_jogadores.get(autor_id, {}).get("nome", autor_id)
	_registrar_acao("promessa", "%s firmou um acordo público por %d turnos." % [nome_autor, duracao], autor_id)
	_atualizar_hud_promessas()

@rpc("authority", "call_local", "reliable")
func _quebrar_promessa_rede(id_promessa: String, reportada_por: String):
	for promessa in _promessas_globais:
		if promessa.get("id", "") != id_promessa:
			continue
		if promessa.get("status", "ativa") != "ativa":
			return
		var autor_id = str(promessa.get("autor_id", ""))
		promessa["status"] = "quebrada"
		promessa["quebrada"] = true
		promessa["quebrada_por"] = autor_id
		promessa["reportada_por"] = reportada_por
		promessa["turnos_restantes"] = 0
		promessa["turno_quebra"] = _contador_turnos_globais
		_garantir_meta_jogador(autor_id)
		dados_economia_jogadores[autor_id]["promessas_quebradas"] = int(dados_economia_jogadores[autor_id].get("promessas_quebradas", 0)) + 1
		_alterar_reputacao(autor_id, -REPUTACAO_PENALIDADE_QUEBRA, "quebra de acordo")
		if pinos_jogadores.has(autor_id):
			pinos_jogadores[autor_id].mostrar_texto_flutuante("ACORDO QUEBRADO! REP -%d" % REPUTACAO_PENALIDADE_QUEBRA, Color(0.95, 0.4, 0.4))
		var autor_nome = dados_economia_jogadores.get(autor_id, {}).get("nome", autor_id)
		var reporter_nome = dados_economia_jogadores.get(reportada_por, {}).get("nome", reportada_por)
		Animacoes.banner_cinematico(hud.get_node("Control"), "ACORDO QUEBRADO", autor_nome + " perdeu reputação. Reportado por " + reporter_nome + ".", Color(0.95, 0.4, 0.4), 2.5)
		_registrar_acao("reputacao", "%s quebrou um acordo e perdeu %d de reputação." % [autor_nome, REPUTACAO_PENALIDADE_QUEBRA], autor_id)
		break
	_atualizar_hud_promessas()

func _processar_promessas_ao_avancar_turno() -> void:
	var houve_mudanca = false
	var conclusoes: Array = []
	for promessa in _promessas_globais:
		if promessa.get("status", "ativa") != "ativa":
			continue
		var autor_id = str(promessa.get("autor_id", ""))
		if not dados_economia_jogadores.has(autor_id) or dados_economia_jogadores[autor_id].get("falido", false):
			promessa["status"] = "cancelada"
			promessa["cancelada"] = true
			promessa["turnos_restantes"] = 0
			promessa["turno_cancelamento"] = _contador_turnos_globais
			houve_mudanca = true
			continue
		promessa["turnos_restantes"] = maxi(0, int(promessa.get("turnos_restantes", PROMESSA_DURACAO_PADRAO)) - 1)
		houve_mudanca = true
		if int(promessa["turnos_restantes"]) > 0:
			continue
		promessa["status"] = "cumprida"
		promessa["cumprida"] = true
		promessa["cumprida_por_expiracao"] = true
		promessa["turno_conclusao"] = _contador_turnos_globais
		_garantir_meta_jogador(autor_id)
		var dados_autor = dados_economia_jogadores[autor_id]
		dados_autor["promessas_cumpridas"] = int(dados_autor.get("promessas_cumpridas", 0)) + 1
		dados_autor["acordos_5_turnos"] = int(dados_autor.get("acordos_5_turnos", 0)) + 1
		_conceder_xp_partida(autor_id, XP_ACORDO_CINCO_TURNOS, "acordo_" + str(promessa.get("id", "")), "Manteve um acordo por 5 turnos")
		_alterar_reputacao(autor_id, REPUTACAO_BONUS_CUMPRIDA, "acordo cumprido")
		var nome_autor = str(dados_autor.get("nome", autor_id))
		conclusoes.append(nome_autor)
	if not conclusoes.is_empty():
		var resumo = ", ".join(conclusoes.slice(0, 3))
		if conclusoes.size() > 3:
			resumo += " e mais %d" % (conclusoes.size() - 3)
		Animacoes.banner_cinematico(hud.get_node("Control"), "ACORDO CUMPRIDO", resumo + " manteve a palavra: +80 XP por acordo.", Color(0.4, 1.0, 0.5), 2.4)
	if houve_mudanca:
		_atualizar_hud_promessas()

func _cancelar_promessas_do_jogador(jogador_id: String) -> void:
	var mudou = false
	for promessa in _promessas_globais:
		if promessa.get("autor_id", "") == jogador_id and promessa.get("status", "ativa") == "ativa":
			promessa["status"] = "cancelada"
			promessa["cancelada"] = true
			promessa["turnos_restantes"] = 0
			promessa["turno_cancelamento"] = _contador_turnos_globais
			mudou = true
	if mudou:
		_atualizar_hud_promessas()

func _atualizar_hud_promessas():
	if hud and hud.has_method("atualizar_painel_promessas"):
		hud.atualizar_painel_promessas(_promessas_globais)

# ============================================================================
# ELEIÇÕES MUNICIPAIS — VOTAÇÃO AUTORITATIVA E MODAL
# ============================================================================
func _jogadores_elegiveis_para_eleicao() -> Array:
	var elegiveis: Array = []
	for jogador_id in lista_turnos:
		if not dados_economia_jogadores.has(jogador_id):
			continue
		if dados_economia_jogadores[jogador_id].get("falido", false):
			continue
		elegiveis.append(jogador_id)
	return elegiveis

func _personagem_do_peer(peer_id: int) -> String:
	if peer_id <= 0:
		peer_id = OnlineTransport.local_player_id()
	var personagem = str(Global.escolhas_da_mesa.get(peer_id, ""))
	if personagem == "" and peer_id == OnlineTransport.local_player_id():
		personagem = str(Global.escolhas_da_mesa.get(Global.meu_peer_id, ""))
	# Fallback para execução local/debug sem tela de seleção sincronizada.
	if personagem == "" and peer_id == 1 and _eleicao_jogadores_elegiveis.has(jogador_atual_id):
		personagem = jogador_atual_id
	return personagem

func _on_hud_voto_eleicao(pacote: String):
	if not _votacao_eleicao_ativa or not _eleicao_bloqueando_acoes:
		return
	if not ELEICAO_PACOTES_VALIDOS.has(pacote):
		return
	OnlineTransport.send_host(self, &"_receber_voto_eleicao", [_eleicao_id_atual, pacote], false)

# O servidor resolve a identidade pelo peer remetente. O cliente não informa
# qual personagem está votando, impedindo votos em nome de outro jogador.
@rpc("any_peer", "call_local")
func _receber_voto_eleicao(votacao_id: int, pacote: String):
	if not OnlineTransport.is_host():
		return
	if not _votacao_eleicao_ativa or votacao_id != _eleicao_id_atual:
		return
	if not ELEICAO_PACOTES_VALIDOS.has(pacote):
		return

	var remetente = OnlineTransport.get_remote_sender_id()
	if remetente == 0:
		remetente = OnlineTransport.local_player_id()
	var jogador_id = _personagem_do_peer(remetente)
	if jogador_id == "" or not _eleicao_jogadores_elegiveis.has(jogador_id):
		return
	if _votos_eleicao.has(jogador_id):
		return  # exatamente um voto por jogador

	_votos_eleicao[jogador_id] = pacote
	OnlineTransport.send_all(self, &"_mostrar_voto_recebido_rede", [votacao_id, cor_por_jogador.get(jogador_id, Color.WHITE)], true, true)
	if _votos_eleicao.size() >= _eleicao_jogadores_elegiveis.size():
		_finalizar_votacao_eleicao(votacao_id)

@rpc("authority", "call_local")
func _mostrar_voto_recebido_rede(votacao_id: int, cor_jogador: Color):
	if votacao_id != _eleicao_id_atual:
		return
	if hud and hud.has_method("mostrar_voto_recebido"):
		hud.mostrar_voto_recebido(cor_jogador)

func _iniciar_votacao_eleicao():
	if not OnlineTransport.is_host() or _votacao_eleicao_ativa:
		return
	_eleicao_id_atual += 1
	_votos_eleicao.clear()
	_eleicao_falencias_pendentes.clear()
	_eleicao_jogadores_elegiveis = _jogadores_elegiveis_para_eleicao()
	_votacao_eleicao_ativa = true
	_eleicao_bloqueando_acoes = true
	OnlineTransport.send_all(self, &"_mostrar_painel_votacao_rede", [_eleicao_id_atual,
		ELEICAO_DURACAO_VOTACAO_SEGUNDOS,
		_eleicao_jogadores_elegiveis.size()], true, true)

	var id_iniciado = _eleicao_id_atual
	# Uma partida sem eleitores válidos não deve ficar bloqueada por 20 segundos.
	if _eleicao_jogadores_elegiveis.is_empty():
		_finalizar_votacao_eleicao(id_iniciado)
		return
	await get_tree().create_timer(float(ELEICAO_DURACAO_VOTACAO_SEGUNDOS)).timeout
	if _votacao_eleicao_ativa and id_iniciado == _eleicao_id_atual:
		_finalizar_votacao_eleicao(id_iniciado)

@rpc("authority", "call_local")
func _mostrar_painel_votacao_rede(votacao_id: int, duracao: int, total_eleitores: int):
	_eleicao_id_atual = votacao_id
	_votacao_eleicao_ativa = true
	_eleicao_bloqueando_acoes = true
	hud.esconder_painel_dados()
	var meu_id = str(Global.escolhas_da_mesa.get(Global.meu_peer_id, ""))
	var cor = cor_por_jogador.get(meu_id, Color.WHITE)
	if hud and hud.has_method("mostrar_painel_votacao"):
		hud.mostrar_painel_votacao(cor, total_eleitores)
	_iniciar_countdown_votacao(votacao_id, duracao)

func _iniciar_countdown_votacao(votacao_id: int, duracao: int):
	var segundos = duracao
	while segundos >= 0 and _votacao_eleicao_ativa and votacao_id == _eleicao_id_atual:
		if hud and hud.has_method("atualizar_timer_votacao"):
			hud.atualizar_timer_votacao(segundos)
		if segundos == 0:
			break
		await get_tree().create_timer(1.0).timeout
		segundos -= 1

func _finalizar_votacao_eleicao(votacao_id: int):
	if not OnlineTransport.is_host():
		return
	if not _votacao_eleicao_ativa or votacao_id != _eleicao_id_atual:
		return
	_votacao_eleicao_ativa = false

	var contagem := {"populista": 0, "liberal": 0, "conservador": 0}
	for pacote in _votos_eleicao.values():
		if contagem.has(pacote):
			contagem[pacote] += 1

	var maior_votacao = 0
	var empatados: Array = []
	for pacote in ELEICAO_PACOTES_VALIDOS:
		var quantidade = int(contagem[pacote])
		if quantidade > maior_votacao:
			maior_votacao = quantidade
			empatados = [pacote]
		elif quantidade == maior_votacao and quantidade > 0:
			empatados.append(pacote)

	var foi_empate = maior_votacao == 0 or empatados.size() != 1
	var vencedor = "paralisia" if foi_empate else str(empatados[0])
	_pacote_eleicao_vencedor = vencedor
	OnlineTransport.send_all(self, &"_anunciar_resultado_eleicao", [votacao_id, vencedor, foi_empate, contagem], true, true)
	_encerrar_eleicao_apos_resultado(votacao_id)

func _encerrar_eleicao_apos_resultado(votacao_id: int):
	await get_tree().create_timer(ELEICAO_DURACAO_RESULTADO_SEGUNDOS).timeout
	if OnlineTransport.is_host() and votacao_id == _eleicao_id_atual:
		OnlineTransport.send_all(self, &"_encerrar_eleicao_rede", [votacao_id], true, true)

@rpc("authority", "call_local")
func _anunciar_resultado_eleicao(votacao_id: int, vencedor: String, foi_empate: bool, contagem: Dictionary):
	if votacao_id != _eleicao_id_atual:
		return
	_votacao_eleicao_ativa = false
	_eleicao_bloqueando_acoes = true
	if hud and hud.has_method("mostrar_resultado_eleicao"):
		hud.mostrar_resultado_eleicao(vencedor, foi_empate, contagem)
	if _eleicao_resultado_aplicado_id == votacao_id:
		return
	_eleicao_resultado_aplicado_id = votacao_id
	_aplicar_pacote_eleicao(vencedor)

@rpc("authority", "call_local")
func _encerrar_eleicao_rede(votacao_id: int):
	if votacao_id != _eleicao_id_atual:
		return
	_votacao_eleicao_ativa = false
	if hud and hud.has_method("fechar_painel_votacao"):
		hud.fechar_painel_votacao()
	# Mantém o bloqueio durante o fade de saída para evitar ações por teclado
	# enquanto o modal ainda está visível.
	await get_tree().create_timer(0.24).timeout
	if votacao_id != _eleicao_id_atual:
		return
	_eleicao_bloqueando_acoes = false
	_eleicao_jogadores_elegiveis.clear()

	# Impostos do pacote Conservador podem causar insolvência. A liquidação é
	# processada somente depois que o modal fecha, evitando leilão atrás da votação.
	var falencias_para_processar = _eleicao_falencias_pendentes.duplicate()
	_eleicao_falencias_pendentes.clear()
	for jogador_id in falencias_para_processar:
		_verificar_falencia(str(jogador_id))
	if not _leilao_falencia_ativo:
		_verificar_permissao_de_clique()

func _media_preco_grupo(grupo: String) -> float:
	var soma = 0
	var quantidade = 0
	for casa_id in tabuleiro.keys():
		if str(tabuleiro[casa_id].get("grupo", "")) != grupo:
			continue
		if str(tabuleiro[casa_id].get("tipo", "")) != "propriedade":
			continue
		soma += int(tabuleiro[casa_id].get("preco", 0))
		quantidade += 1
	return float(soma) / float(quantidade) if quantidade > 0 else 0.0

func _grupos_residenciais_ordenados_por_preco() -> Array:
	var grupos: Array = []
	for grupo in cores_grupos.keys():
		if grupo in ["Especial", "Utilidade", "Transporte", "Portal", ""]:
			continue
		if _media_preco_grupo(str(grupo)) > 0.0:
			grupos.append(str(grupo))
	grupos.sort_custom(func(a, b): return _media_preco_grupo(a) < _media_preco_grupo(b))
	return grupos

func _aplicar_pacote_eleicao(pacote: String):
	match pacote:
		"populista":
			var grupos_ordenados = _grupos_residenciais_ordenados_por_preco()
			var grupos_pobres: Array = grupos_ordenados.slice(0, min(2, grupos_ordenados.size()))
			var inicio_premium = max(0, grupos_ordenados.size() - 2)
			var grupos_premium: Array = grupos_ordenados.slice(inicio_premium, grupos_ordenados.size())

			# Sem duração no GDD: a política permanece pelo resto da partida.
			_ativar_efeito_temporario("eleicao_populista_premium", "multiplicador_aluguel", -1, {
				"grupos": grupos_premium, "multiplicador": 0.80, "origem": "eleicao"
			})
			for casa_id in registro_propriedades.keys():
				if not grupos_pobres.has(str(tabuleiro[casa_id].get("grupo", ""))):
					continue
				if tabuleiro[casa_id].get("hipotecada", false):
					continue
				var nivel_atual = int(tabuleiro[casa_id].get("nivel", 0))
				tabuleiro[casa_id]["nivel"] = min(5, nivel_atual + 2)
				_atualizar_imagem_construcao(int(casa_id))

		"liberal":
			# O GDD define explicitamente duração de 2 turnos para a construção livre.
			_ativar_efeito_temporario("eleicao_liberal_construcao_livre", "regra_construcao_livre", 2, {
				"origem": "eleicao"
			})
			_ativar_efeito_temporario("eleicao_liberal_desconto", "multiplicador_custo_construcao", 2, {
				"multiplicador": 0.75, "origem": "eleicao"
			})

		"conservador":
			# Sem duração no GDD: o novo bônus da Partida permanece.
			_ativar_efeito_temporario("eleicao_conservadora_partida", "bonus_partida", -1, {
				"valor": 300, "origem": "eleicao"
			})
			for jogador_id in lista_turnos:
				if dados_economia_jogadores.get(jogador_id, {}).get("falido", false):
					continue
				var taxa_total = 0
				for casa_id in dados_economia_jogadores[jogador_id].get("propriedades_lista", []):
					if not tabuleiro.has(casa_id) or not tabuleiro[casa_id].get("hipotecada", false):
						continue
					var principal_hipoteca = int(ceil(_calcular_valor_propriedade(casa_id) * 0.5))
					taxa_total += int(ceil(principal_hipoteca * ELEICAO_IMPOSTO_HIPOTECA_PERCENTUAL))
				if taxa_total > 0:
					_aplicar_mudanca_dinheiro_rede(jogador_id, -taxa_total, "evento_global", true)
					if int(dados_economia_jogadores[jogador_id].get("dinheiro", 0)) <= 0 and not _eleicao_falencias_pendentes.has(jogador_id):
						_eleicao_falencias_pendentes.append(jogador_id)

		"paralisia":
			var valores: Dictionary = {}
			for casa_id in registro_propriedades.keys():
				valores[int(casa_id)] = _calcular_aluguel(int(casa_id), str(registro_propriedades[casa_id]))
			_ativar_efeito_temporario("eleicao_paralisia", "congelar_aluguel", 1, {
				"valores_por_casa": valores, "origem": "eleicao"
			})
	_atualizar_hud_ciclo_turno()
	_atualizar_menu_construcao()
