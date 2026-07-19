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

# Configuração de partidas locais guiadas. Estes campos também servem de base
# para o futuro modo single-player: o Tabuleiro continua executando as regras
# normais e apenas delega os turnos indicados ao controlador de IA.
var modo_tutorial: bool = false
var jogadores_controlados_por_bot: Array[String] = []
var ordem_partida_local: Array[String] = []
var dados_tutorial_jogador: Array[Vector2i] = []
var dados_tutorial_bots: Dictionary = {}


func configurar_partida_tutorial() -> void:
	modo_online = false
	modo_tutorial = true
	meu_peer_id = 1
	escolhas_da_mesa = {1: "yasmin", 2: "igor"}
	user_ids_da_mesa.clear()
	escolhas_por_user_id.clear()
	jogadores_controlados_por_bot = ["igor"]
	ordem_partida_local = ["yasmin", "igor"]
	# Resultados controlados deixam o tutorial curto e reproduzível. A primeira
	# jogada leva Yasmin ao terreno Cinza; as seguintes passam por uma casa de
	# bônus e por um portal. Igor visita Transporte, terreno e Utilidade.
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
