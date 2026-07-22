extends "res://scenes/gameplay/tabuleiro/modulos_tabuleiro/tabuleiro_balanceamento.gd"

# ============================================================================
# CORREÇÃO DO SINGLEPLAYER APÓS PAUSAR
# ============================================================================
#
# O SceneTree local é congelado durante a pausa, mas o BotJogador também possui
# sua própria flag `_pausado`. A retomada agora libera explicitamente os dois
# estados e verifica se o turno atual ainda pertence a um bot.
# ============================================================================


@rpc("authority", "call_local", "reliable")
func _aplicar_estado_pausa_rede(
	ativo: bool,
	peer_iniciador: int,
	personagem_iniciador: String,
	nome_iniciador: String
) -> void:
	# O bot precisa receber a pausa antes de o SceneTree ser congelado.
	if ativo and Global.modo_singleplayer:
		definir_bots_pausados(true)

	super._aplicar_estado_pausa_rede(
		ativo,
		peer_iniciador,
		personagem_iniciador,
		nome_iniciador
	)

	if ativo or not Global.modo_singleplayer:
		return

	# Libera a espera interna presente em BotJogador._aguardar_liberacao().
	definir_bots_pausados(false)
	call_deferred("_garantir_retomada_turno_bot_singleplayer")


func _garantir_retomada_turno_bot_singleplayer() -> void:
	# Dois frames permitem que o MenuPause termine de ocultar a interface e que
	# timers pausados retomem antes do watchdog verificar o turno.
	await get_tree().process_frame
	await get_tree().process_frame

	if not is_inside_tree():
		return
	if not Global.modo_singleplayer:
		return
	if get_tree().paused:
		return
	if _pausa_global_ativa or _menu_pause_bloqueando_acoes:
		return
	if not _eh_jogador_bot(jogador_atual_id):
		return

	# BotJogador possui proteção contra execução duplicada. Portanto, esta chamada
	# apenas recupera um turno que ficou aguardando e não duplica uma jogada ativa.
	_solicitar_turno_bot(jogador_atual_id)


# ============================================================================
# BOTS EM VOTAÇÕES E DECISÕES DE EVENTOS
# ============================================================================
#
# Existem dois fluxos coletivos no motor:
# 1. Eleições Municipais, com os pacotes populista/liberal/conservador.
# 2. Sessões genéricas de decisão, usadas pela Crise Hídrica e pelos demais
#    Eventos Globais interativos.
#
# No singleplayer, os bots agora respondem diretamente no estado autoritativo
# local. O jogador humano continua usando normalmente os painéis da HUD.
# ============================================================================


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
	var id_sessao: int = _sessao_decisao_evento_id
	_sessao_decisao_evento_ativa = true
	_sessao_decisao_evento_prompts = prompts.duplicate(true)
	_sessao_decisao_evento_respostas.clear()

	var alvos: Array = prompts.keys()
	OnlineTransport.send_all(
		self,
		&"_mostrar_espera_decisao_evento_rede",
		[
			id_sessao,
			alvos,
			titulo_espera,
			descricao_espera,
			duracao,
			cor_espera,
		],
		true,
		true
	)

	for pid_variant: Variant in alvos:
		var pid: String = str(pid_variant)
		OnlineTransport.send_all(
			self,
			&"_mostrar_decisao_evento_rede",
			[pid, id_sessao, prompts[pid_variant], duracao],
			true,
			true
		)

	if Global.modo_singleplayer:
		call_deferred(
			"_responder_bots_sessao_evento_singleplayer",
			id_sessao,
			prompts.duplicate(true)
		)

	var tempo_passado: float = 0.0
	while (
		_sessao_decisao_evento_ativa
		and id_sessao == _sessao_decisao_evento_id
		and _sessao_decisao_evento_respostas.size() < prompts.size()
		and tempo_passado < float(duracao)
	):
		await get_tree().create_timer(0.1).timeout
		tempo_passado += 0.1

	for pid_variant: Variant in alvos:
		var pid: String = str(pid_variant)
		if not _sessao_decisao_evento_respostas.has(pid):
			_sessao_decisao_evento_respostas[pid] = {
				"acao": "tempo_esgotado",
				"selecionados": [],
			}

	var respostas: Dictionary = (
		_sessao_decisao_evento_respostas.duplicate(true)
	)
	_sessao_decisao_evento_ativa = false
	_sessao_decisao_evento_prompts.clear()
	_sessao_decisao_evento_respostas.clear()

	OnlineTransport.send_all(
		self,
		&"_fechar_decisao_evento_rede",
		[id_sessao],
		true,
		true
	)
	await get_tree().create_timer(0.22).timeout
	return respostas


func _responder_bots_sessao_evento_singleplayer(
	id_sessao: int,
	prompts: Dictionary
) -> void:
	# A pequena espera permite que os painéis apareçam antes dos votos dos bots.
	await get_tree().create_timer(0.48).timeout

	for bot_variant: Variant in Global.jogadores_controlados_por_bot:
		if not is_inside_tree():
			return
		if not Global.modo_singleplayer:
			return
		if (
			not _sessao_decisao_evento_ativa
			or id_sessao != _sessao_decisao_evento_id
		):
			return

		var bot_id: String = str(bot_variant)
		if bot_id.is_empty() or not prompts.has(bot_id):
			continue
		if bool(
			dados_economia_jogadores
			.get(bot_id, {})
			.get("falido", false)
		):
			continue
		if _sessao_decisao_evento_respostas.has(bot_id):
			continue

		var prompt_variant: Variant = prompts.get(bot_id, {})
		if not prompt_variant is Dictionary:
			continue

		var resposta: Dictionary = _escolher_resposta_evento_bot(
			bot_id,
			prompt_variant
		)
		_registrar_resposta_evento_bot(
			id_sessao,
			bot_id,
			prompt_variant,
			resposta
		)

		# Evita que todos os votos visuais aconteçam no mesmo frame.
		await get_tree().create_timer(0.16).timeout


func _registrar_resposta_evento_bot(
	id_sessao: int,
	bot_id: String,
	prompt: Dictionary,
	resposta: Dictionary
) -> void:
	if (
		not _sessao_decisao_evento_ativa
		or id_sessao != _sessao_decisao_evento_id
		or _sessao_decisao_evento_respostas.has(bot_id)
	):
		return

	var acao: String = str(
		resposta.get("acao", "tempo_esgotado")
	)
	if acao not in ["confirmar", "recusar", "tempo_esgotado"]:
		acao = "tempo_esgotado"

	if (
		acao == "recusar"
		and not bool(prompt.get("permitir_recusar", true))
	):
		acao = "tempo_esgotado"

	var permitidos: Array[String] = []
	for opcao_variant: Variant in prompt.get("opcoes", []):
		if not opcao_variant is Dictionary:
			continue
		var opcao: Dictionary = opcao_variant
		if not bool(opcao.get("habilitado", true)):
			continue
		var opcao_id: String = str(opcao.get("id", ""))
		if not opcao_id.is_empty():
			permitidos.append(opcao_id)

	var selecionados_limpos: Array[String] = []
	for selecionado_variant: Variant in resposta.get(
		"selecionados",
		[]
	):
		var selecionado: String = str(selecionado_variant)
		if (
			permitidos.has(selecionado)
			and not selecionados_limpos.has(selecionado)
		):
			selecionados_limpos.append(selecionado)

	if acao == "confirmar":
		var minimo: int = maxi(
			0,
			int(prompt.get("min", 0))
		)
		var maximo: int = maxi(
			minimo,
			int(prompt.get("max", 1))
		)
		if (
			selecionados_limpos.size() < minimo
			or selecionados_limpos.size() > maximo
		):
			acao = (
				"recusar"
				if bool(prompt.get("permitir_recusar", true))
				else "tempo_esgotado"
			)
			selecionados_limpos.clear()
	elif acao == "tempo_esgotado":
		selecionados_limpos.clear()

	_sessao_decisao_evento_respostas[bot_id] = {
		"acao": acao,
		"selecionados": selecionados_limpos,
	}


func _escolher_resposta_evento_bot(
	bot_id: String,
	prompt: Dictionary
) -> Dictionary:
	var opcoes_validas: Array[Dictionary] = []

	for opcao_variant: Variant in prompt.get("opcoes", []):
		if not opcao_variant is Dictionary:
			continue
		var opcao: Dictionary = opcao_variant
		if not bool(opcao.get("habilitado", true)):
			continue
		if str(opcao.get("id", "")).is_empty():
			continue
		opcoes_validas.append(opcao)

	var permitir_recusar: bool = bool(
		prompt.get("permitir_recusar", true)
	)
	if opcoes_validas.is_empty():
		return {
			"acao": (
				"recusar"
				if permitir_recusar
				else "tempo_esgotado"
			),
			"selecionados": [],
		}

	var titulo: String = str(
		prompt.get("titulo", "")
	).to_upper()
	var ids_validos: Array[String] = []
	for opcao: Dictionary in opcoes_validas:
		ids_validos.append(str(opcao.get("id", "")))

	# Votações binárias atuais e futuras.
	if ids_validos.has("sim") and ids_validos.has("nao"):
		return {
			"acao": "confirmar",
			"selecionados": [
				_escolher_voto_sim_nao_bot(bot_id, titulo)
			],
		}

	# A Imunidade Política é de uso único. Breno não deve gastá-la sempre.
	if titulo.contains("IMUNIDADE POLÍTICA"):
		if (
			ids_validos.has("usar_imunidade")
			and _bot_deve_usar_imunidade_politica(bot_id)
		):
			return {
				"acao": "confirmar",
				"selecionados": ["usar_imunidade"],
			}
		if permitir_recusar:
			return {
				"acao": "recusar",
				"selecionados": [],
			}

	# Ao escolher um grupo, o bot prioriza aquele em que já possui mais ativos.
	if titulo.contains("ZONEAMENTO"):
		var grupo_preferido: String = _grupo_preferido_bot(
			bot_id,
			opcoes_validas
		)
		if not grupo_preferido.is_empty():
			return {
				"acao": "confirmar",
				"selecionados": [grupo_preferido],
			}

	# Igor prioriza o ativo de maior valor disponível no Abutre do Mercado.
	if titulo.contains("ABUTRE DO MERCADO"):
		var propriedade_preferida: String = (
			_propriedade_mais_valiosa_das_opcoes(opcoes_validas)
		)
		if not propriedade_preferida.is_empty():
			return {
				"acao": "confirmar",
				"selecionados": [propriedade_preferida],
			}

	opcoes_validas.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (
				_pontuar_opcao_evento_bot(bot_id, titulo, a)
				>
				_pontuar_opcao_evento_bot(bot_id, titulo, b)
			)
	)

	var minimo: int = maxi(0, int(prompt.get("min", 0)))
	var maximo: int = maxi(
		minimo,
		int(prompt.get("max", 1))
	)
	var quantidade: int = mini(
		opcoes_validas.size(),
		maximo
	)
	if minimo > 0:
		quantidade = mini(
			opcoes_validas.size(),
			maxi(minimo, 1)
		)
	elif quantidade > 0:
		quantidade = 1

	var selecionados: Array[String] = []
	for indice: int in range(quantidade):
		selecionados.append(
			str(opcoes_validas[indice].get("id", ""))
		)

	if selecionados.size() < minimo:
		return {
			"acao": (
				"recusar"
				if permitir_recusar
				else "tempo_esgotado"
			),
			"selecionados": [],
		}

	return {
		"acao": "confirmar",
		"selecionados": selecionados,
	}


func _escolher_voto_sim_nao_bot(
	bot_id: String,
	titulo: String
) -> String:
	var dados: Dictionary = dados_economia_jogadores.get(
		bot_id,
		{}
	)
	var dinheiro: int = int(dados.get("dinheiro", 0))
	var niveis: int = _niveis_construcao_do_bot(bot_id)

	if titulo.contains("CRISE HÍDRICA"):
		# O dono da SAEM lucra com a duração maior e tende a votar NÃO.
		if _bot_possui_propriedade_com_nome(bot_id, "SAEM"):
			return "nao"

		# Mira e Kofi valorizam a liberação rápida das construções.
		if bot_id in ["mira", "kofi"] and dinheiro >= 350:
			return "sim"

		# Quem já investiu bastante em obras prefere reduzir o bloqueio.
		if niveis >= 3 and dinheiro >= 500:
			return "sim"

		# Bots com pouco caixa evitam o custo coletivo de $100.
		if dinheiro < 450:
			return "nao"

	# Fallback determinístico para qualquer votação binária futura.
	return (
		"sim"
		if posmod(hash(bot_id + titulo), 2) == 0
		else "nao"
	)


func _bot_deve_usar_imunidade_politica(
	bot_id: String
) -> bool:
	if bot_id != "breno":
		return false

	var dados: Dictionary = dados_economia_jogadores.get(
		bot_id,
		{}
	)
	if bool(dados.get("usou_imunidade", false)):
		return false

	var dinheiro: int = int(dados.get("dinheiro", 0))
	var propriedades: int = int(
		dados.get("propriedades_compradas", 0)
	)
	var niveis: int = _niveis_construcao_do_bot(bot_id)

	# Usa a proteção quando a posição econômica está vulnerável ou quando
	# há bastante patrimônio construído exposto ao evento.
	return dinheiro <= 700 or propriedades >= 4 or niveis >= 5


func _grupo_preferido_bot(
	bot_id: String,
	opcoes: Array[Dictionary]
) -> String:
	var melhor_grupo: String = ""
	var melhor_pontuacao: int = -1

	for opcao: Dictionary in opcoes:
		var grupo: String = str(opcao.get("id", ""))
		var pontuacao: int = (
			_quantidade_propriedades_grupo_bot(bot_id, grupo) * 1000
			+ posmod(hash(bot_id + grupo), 100)
		)
		if pontuacao > melhor_pontuacao:
			melhor_pontuacao = pontuacao
			melhor_grupo = grupo

	return melhor_grupo


func _propriedade_mais_valiosa_das_opcoes(
	opcoes: Array[Dictionary]
) -> String:
	var melhor_id: String = ""
	var melhor_valor: int = -1

	for opcao: Dictionary in opcoes:
		var id_texto: String = str(opcao.get("id", ""))
		if not id_texto.is_valid_int():
			continue

		var casa_id: int = int(id_texto)
		var valor: int = int(
			tabuleiro.get(casa_id, {}).get("preco", 0)
		)
		valor += int(
			tabuleiro.get(casa_id, {}).get("nivel", 0)
		) * 100

		if valor > melhor_valor:
			melhor_valor = valor
			melhor_id = id_texto

	return melhor_id


func _pontuar_opcao_evento_bot(
	bot_id: String,
	titulo: String,
	opcao: Dictionary
) -> int:
	var opcao_id: String = str(opcao.get("id", ""))
	var pontuacao: int = posmod(
		hash(bot_id + titulo + opcao_id),
		1000
	)

	if opcao_id.is_valid_int():
		var casa_id: int = int(opcao_id)
		if tabuleiro.has(casa_id):
			pontuacao += int(
				tabuleiro[casa_id].get("preco", 0)
			)
			pontuacao += int(
				tabuleiro[casa_id].get("nivel", 0)
			) * 120

			if str(
				registro_propriedades.get(casa_id, "")
			) == bot_id:
				pontuacao += 1800
	else:
		pontuacao += (
			_quantidade_propriedades_grupo_bot(
				bot_id,
				opcao_id
			)
			* 600
		)

	return pontuacao


func _quantidade_propriedades_grupo_bot(
	bot_id: String,
	grupo: String
) -> int:
	var total: int = 0

	for casa_variant: Variant in registro_propriedades.keys():
		var casa_id: int = int(casa_variant)
		if str(registro_propriedades[casa_variant]) != bot_id:
			continue
		if str(
			tabuleiro.get(casa_id, {}).get("grupo", "")
		) == grupo:
			total += 1

	return total


func _niveis_construcao_do_bot(bot_id: String) -> int:
	var total: int = 0

	for casa_variant: Variant in registro_propriedades.keys():
		var casa_id: int = int(casa_variant)
		if str(registro_propriedades[casa_variant]) != bot_id:
			continue
		total += int(
			tabuleiro.get(casa_id, {}).get("nivel", 0)
		)

	return total


func _bot_possui_propriedade_com_nome(
	bot_id: String,
	trecho_nome: String
) -> bool:
	for casa_variant: Variant in registro_propriedades.keys():
		var casa_id: int = int(casa_variant)
		if str(registro_propriedades[casa_variant]) != bot_id:
			continue
		if str(
			tabuleiro.get(casa_id, {}).get("nome", "")
		).contains(trecho_nome):
			return true

	return false


# ============================================================================
# ELEIÇÕES MUNICIPAIS
# ============================================================================


func _iniciar_votacao_eleicao() -> void:
	if not OnlineTransport.is_host() or _votacao_eleicao_ativa:
		return

	_eleicao_id_atual += 1
	_votos_eleicao.clear()
	_eleicao_falencias_pendentes.clear()
	_eleicao_jogadores_elegiveis = (
		_jogadores_elegiveis_para_eleicao()
	)
	_votacao_eleicao_ativa = true
	_eleicao_bloqueando_acoes = true

	OnlineTransport.send_all(
		self,
		&"_mostrar_painel_votacao_rede",
		[
			_eleicao_id_atual,
			ELEICAO_DURACAO_VOTACAO_SEGUNDOS,
			_eleicao_jogadores_elegiveis.size(),
		],
		true,
		true
	)

	var id_iniciado: int = _eleicao_id_atual

	if _eleicao_jogadores_elegiveis.is_empty():
		_finalizar_votacao_eleicao(id_iniciado)
		return

	if Global.modo_singleplayer:
		call_deferred(
			"_responder_eleicao_bots_singleplayer",
			id_iniciado
		)

	await get_tree().create_timer(
		float(ELEICAO_DURACAO_VOTACAO_SEGUNDOS)
	).timeout

	if (
		_votacao_eleicao_ativa
		and id_iniciado == _eleicao_id_atual
	):
		_finalizar_votacao_eleicao(id_iniciado)


func _responder_eleicao_bots_singleplayer(
	votacao_id: int
) -> void:
	await get_tree().create_timer(0.58).timeout

	for bot_variant: Variant in Global.jogadores_controlados_por_bot:
		if not is_inside_tree():
			return
		if not Global.modo_singleplayer:
			return
		if (
			not _votacao_eleicao_ativa
			or votacao_id != _eleicao_id_atual
		):
			return

		var bot_id: String = str(bot_variant)
		if (
			not _eleicao_jogadores_elegiveis.has(bot_id)
			or _votos_eleicao.has(bot_id)
		):
			continue
		if bool(
			dados_economia_jogadores
			.get(bot_id, {})
			.get("falido", false)
		):
			continue

		var pacote: String = _escolher_pacote_eleicao_bot(
			bot_id
		)
		if not ELEICAO_PACOTES_VALIDOS.has(pacote):
			pacote = "liberal"

		_votos_eleicao[bot_id] = pacote

		OnlineTransport.send_all(
			self,
			&"_mostrar_voto_recebido_rede",
			[
				votacao_id,
				cor_por_jogador.get(
					bot_id,
					Color.WHITE
				),
			],
			true,
			true
		)

		await get_tree().create_timer(0.18).timeout

	if (
		_votacao_eleicao_ativa
		and votacao_id == _eleicao_id_atual
		and _votos_eleicao.size()
		>= _eleicao_jogadores_elegiveis.size()
	):
		_finalizar_votacao_eleicao(votacao_id)


func _escolher_pacote_eleicao_bot(
	bot_id: String
) -> String:
	var dados: Dictionary = dados_economia_jogadores.get(
		bot_id,
		{}
	)
	var dinheiro: int = int(dados.get("dinheiro", 0))
	var propriedades: int = int(
		dados.get("propriedades_compradas", 0)
	)
	var hipotecas: int = 0
	var niveis: int = _niveis_construcao_do_bot(bot_id)

	var grupos_ordenados: Array = (
		_grupos_residenciais_ordenados_por_preco()
	)
	var grupos_pobres: Array = grupos_ordenados.slice(
		0,
		mini(2, grupos_ordenados.size())
	)
	var inicio_premium: int = maxi(
		0,
		grupos_ordenados.size() - 2
	)
	var grupos_premium: Array = grupos_ordenados.slice(
		inicio_premium,
		grupos_ordenados.size()
	)

	var propriedades_pobres: int = 0
	var propriedades_premium: int = 0

	for casa_variant: Variant in registro_propriedades.keys():
		var casa_id: int = int(casa_variant)
		if str(registro_propriedades[casa_variant]) != bot_id:
			continue

		var dados_casa: Dictionary = tabuleiro.get(
			casa_id,
			{}
		)
		var grupo: String = str(
			dados_casa.get("grupo", "")
		)
		if bool(dados_casa.get("hipotecada", false)):
			hipotecas += 1
		if grupos_pobres.has(grupo):
			propriedades_pobres += 1
		if grupos_premium.has(grupo):
			propriedades_premium += 1

	# Evita o pacote Conservador quando o próprio bot seria taxado por hipotecas.
	if hipotecas > 0:
		return "liberal"

	# Quem concentrou ativos baratos se beneficia diretamente do Populista.
	if (
		propriedades_pobres > propriedades_premium
		and propriedades_pobres > 0
	):
		return "populista"

	# Bots com caixa e portfólio desenvolvido priorizam construir com desconto.
	if (
		(propriedades >= 2 and dinheiro >= 550)
		or niveis >= 3
	):
		return "liberal"

	# Tendências estratégicas dos personagens evitam votos idênticos.
	var preferencia_personagem := {
		"yasmin": "liberal",
		"breno": "conservador",
		"mira": "liberal",
		"igor": "liberal",
		"diana": "populista",
		"kofi": "populista",
	}

	return str(
		preferencia_personagem.get(
			bot_id,
			ELEICAO_PACOTES_VALIDOS[
				posmod(hash(bot_id), ELEICAO_PACOTES_VALIDOS.size())
			]
		)
	)

