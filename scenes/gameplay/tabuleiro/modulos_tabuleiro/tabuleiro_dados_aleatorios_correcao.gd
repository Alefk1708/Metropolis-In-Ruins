extends "res://scenes/gameplay/tabuleiro/modulos_tabuleiro/tabuleiro_diana_correcao.gd"

# ============================================================================
# DADOS DOS BOTS — ALEATORIEDADE POR PARTIDA
# ============================================================================
#
# Antes, cada bot recebia id_jogador.hash() como semente. Como o ID do
# personagem não muda, Yasmin, Igor, Diana e os demais repetiam a mesma
# sequência pseudoaleatória sempre que uma nova partida era iniciada.
#
# Esta camada mantém o tutorial determinístico, mas cria sementes novas e
# independentes para os bots de cada partida singleplayer normal.
#
# A passiva Relatório de Mercado da Yasmin não participa deste sorteio:
# ela apenas lê posições e a distribuição matemática de 2d6.
# ============================================================================


var _rng_sementes_bots: RandomNumberGenerator = RandomNumberGenerator.new()
var _rng_sementes_bots_inicializado: bool = false


func _configurar_bots_locais() -> void:
	# Bots locais pertencem somente ao singleplayer e ao tutorial. Não cria nem
	# altera controladores durante partidas LAN ou Photon.
	if not _modo_permite_bots_locais():
		return

	_inicializar_rng_sementes_bots()

	for jogador_variant: Variant in Global.jogadores_controlados_por_bot:
		var id_jogador: String = str(jogador_variant)
		if id_jogador.is_empty() or not lista_turnos.has(id_jogador):
			continue
		if _bots_jogadores.has(id_jogador):
			continue

		var bot: Node = BOT_JOGADOR_SCRIPT.new()
		bot.name = "Bot_%s" % id_jogador.capitalize()
		add_child(bot)

		var semente_bot: int = _gerar_semente_bot(
			id_jogador,
			bot
		)
		bot.call(
			"configurar",
			self,
			id_jogador,
			semente_bot
		)

		# Resultados roteirizados são permitidos exclusivamente dentro do
		# tutorial. Uma fila antiga nunca pode vazar para uma partida normal.
		if Global.modo_tutorial:
			_aplicar_resultados_forcados_tutorial(
				bot,
				id_jogador
			)

		bot.call("definir_pausado", _bots_pausados)
		_bots_jogadores[id_jogador] = bot


func _modo_permite_bots_locais() -> bool:
	if Global.modo_online:
		return false
	if OnlineTransport.esta_em_sala():
		return false
	if OnlineTransport.usando_photon():
		return false
	return Global.modo_singleplayer or Global.modo_tutorial


func _inicializar_rng_sementes_bots() -> void:
	if _rng_sementes_bots_inicializado:
		return

	# randomize() usa entropia da execução atual. O gerador é criado uma única
	# vez por tabuleiro e fornece uma semente diferente para cada bot.
	_rng_sementes_bots.randomize()
	_rng_sementes_bots_inicializado = true


func _gerar_semente_bot(
	id_jogador: String,
	bot: Node
) -> int:
	# O tutorial mantém a sequência reproduzível depois que sua fila de dados
	# roteirizados terminar.
	if Global.modo_tutorial:
		var semente_tutorial: int = id_jogador.hash()
		return semente_tutorial if semente_tutorial != 0 else 1

	# Combina o gerador da partida com tempo de execução, personagem e instância.
	# Assim, bots criados no mesmo frame também recebem sequências distintas.
	var semente: int = (
		int(_rng_sementes_bots.randi())
		^ int(Time.get_ticks_usec())
		^ id_jogador.hash()
		^ int(bot.get_instance_id())
	)
	if semente == 0:
		semente = 1
	return semente


func _aplicar_resultados_forcados_tutorial(
	bot: Node,
	id_jogador: String
) -> void:
	var resultados: Array[Vector2i] = []
	var resultados_variant: Variant = (
		Global.dados_tutorial_bots.get(
			id_jogador,
			[]
		)
	)
	if resultados_variant is Array:
		for resultado_variant: Variant in resultados_variant:
			if resultado_variant is Vector2i:
				var resultado: Vector2i = resultado_variant
				if (
					resultado.x in range(1, 7)
					and resultado.y in range(1, 7)
				):
					resultados.append(resultado)

	if not resultados.is_empty():
		bot.call(
			"definir_resultados_forcados",
			resultados
		)
