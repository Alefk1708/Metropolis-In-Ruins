extends Node

# { peer_id: "personagem" }
var escolhas_da_mesa: Dictionary = {}

# Identidade persistente usada para reconectar um jogador Photon ao mesmo
# personagem mesmo quando o player_id numérico da sala mudar.
var user_ids_da_mesa: Dictionary = {} # { peer_id: user_id }
var escolhas_por_user_id: Dictionary = {} # { user_id: personagem }

# ID local usado pela HUD e pelo tabuleiro.
var meu_peer_id: int = 1

# Fluxo da sessão online. O modo LAN continua usando NetworkManager.
var modo_online: bool = false
var fase_online: String = "online_lobby"
var cena_online_atual: String = "res://scenes/ui/online/online_menu.tscn"

# Configuração de partidas locais guiadas.
var modo_tutorial: bool = false
var modo_singleplayer: bool = false
var jogadores_controlados_por_bot: Array[String] = []
var ordem_partida_local: Array[String] = []
var dados_tutorial_jogador: Array[Vector2i] = []
var dados_tutorial_bots: Dictionary = {}

# Preferências temporárias do modo singleplayer.
var personagem_singleplayer: String = ""
var quantidade_bots_singleplayer: int = 3

const PERSONAGENS_JOGAVEIS := [
	"yasmin",
	"breno",
	"mira",
	"igor",
	"diana",
	"kofi",
]


func configurar_partida_tutorial() -> void:
	modo_online = false
	modo_tutorial = true
	modo_singleplayer = false
	personagem_singleplayer = ""
	quantidade_bots_singleplayer = 3
	meu_peer_id = 1
	escolhas_da_mesa = {1: "yasmin", 2: "igor"}
	user_ids_da_mesa.clear()
	escolhas_por_user_id.clear()
	jogadores_controlados_por_bot = ["igor"]
	ordem_partida_local = ["yasmin", "igor"]

	# Resultados controlados deixam o tutorial curto e reproduzível.
	dados_tutorial_jogador = [
		Vector2i(1, 2),
		Vector2i(1, 3),
		Vector2i(1, 4),
	]
	dados_tutorial_bots = {
		"igor": [
			Vector2i(2, 3),
			Vector2i(2, 4),
			Vector2i(1, 2),
		]
	}


func limpar_partida_tutorial() -> void:
	modo_tutorial = false
	modo_singleplayer = false
	personagem_singleplayer = ""
	quantidade_bots_singleplayer = 3
	jogadores_controlados_por_bot.clear()
	ordem_partida_local.clear()
	dados_tutorial_jogador.clear()
	dados_tutorial_bots.clear()
	escolhas_da_mesa.clear()
	user_ids_da_mesa.clear()
	escolhas_por_user_id.clear()
	meu_peer_id = 1


func preparar_modo_singleplayer(
	quantidade_bots: int = 3
) -> void:
	modo_online = false
	modo_tutorial = false
	modo_singleplayer = true
	meu_peer_id = 1
	personagem_singleplayer = ""
	quantidade_bots_singleplayer = clampi(quantidade_bots, 1, 5)

	escolhas_da_mesa.clear()
	user_ids_da_mesa.clear()
	escolhas_por_user_id.clear()
	jogadores_controlados_por_bot.clear()
	ordem_partida_local.clear()
	dados_tutorial_jogador.clear()
	dados_tutorial_bots.clear()


func configurar_partida_singleplayer(
	personagem_jogador: String,
	quantidade_bots: int = 3
) -> bool:
	var personagem_limpo: String = personagem_jogador.strip_edges().to_lower()
	if not PERSONAGENS_JOGAVEIS.has(personagem_limpo):
		return false

	preparar_modo_singleplayer(quantidade_bots)
	personagem_singleplayer = personagem_limpo

	var candidatos: Array[String] = []
	for personagem_variant: Variant in PERSONAGENS_JOGAVEIS:
		var personagem_id: String = str(personagem_variant)
		if personagem_id != personagem_limpo:
			candidatos.append(personagem_id)

	candidatos.shuffle()
	var total_bots: int = mini(
		quantidade_bots_singleplayer,
		candidatos.size()
	)

	escolhas_da_mesa[1] = personagem_limpo
	jogadores_controlados_por_bot.clear()

	for indice: int in range(total_bots):
		var bot_id: String = candidatos[indice]
		var peer_bot: int = indice + 2
		escolhas_da_mesa[peer_bot] = bot_id
		jogadores_controlados_por_bot.append(bot_id)

	ordem_partida_local.clear()
	ordem_partida_local.append(personagem_limpo)
	for bot_id: String in jogadores_controlados_por_bot:
		ordem_partida_local.append(bot_id)

	# Embaralha a ordem para o jogador humano não começar sempre.
	ordem_partida_local.shuffle()
	return true


func limpar_partida_singleplayer() -> void:
	modo_online = false
	modo_tutorial = false
	modo_singleplayer = false
	personagem_singleplayer = ""
	quantidade_bots_singleplayer = 3
	jogadores_controlados_por_bot.clear()
	ordem_partida_local.clear()
	dados_tutorial_jogador.clear()
	dados_tutorial_bots.clear()
	escolhas_da_mesa.clear()
	user_ids_da_mesa.clear()
	escolhas_por_user_id.clear()
	meu_peer_id = 1


func consumir_dados_tutorial_jogador() -> Vector2i:
	if not modo_tutorial or dados_tutorial_jogador.is_empty():
		return Vector2i.ZERO
	return dados_tutorial_jogador.pop_front()
