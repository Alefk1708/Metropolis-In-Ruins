extends "res://scenes/gameplay/tabuleiro/modulos_tabuleiro/tabuleiro_pausa_salvamento.gd"

# Módulo: tabuleiro_tutorial_bots.gd

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


func _notificar_tabuleiro_pronto_tutorial() -> void:
	_emitir_evento_tutorial(
		"tabuleiro_pronto",
		{"jogador_id": jogador_atual_id, "rodada": rodada_atual}
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
