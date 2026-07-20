extends "res://scenes/gameplay/tabuleiro/modulos_tabuleiro/tabuleiro_economia.gd"

# Módulo: tabuleiro_eventos_cartas.gd

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


func _indice_deterministico_carta(opcoes: Array, alvo_id: String, carta_nome: String) -> int:
	if opcoes.is_empty():
		return -1
	var base = rodada_atual + lista_turnos.find(alvo_id) + carta_nome.length()
	return posmod(base, opcoes.size())


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


func _habilidades_bloqueadas_por_efeito(jogador_id: String = "") -> bool:
	for efeito in _efeitos_ativos_por_tipo("bloqueio_habilidade"):
		if jogador_id != "" and efeito.get("jogadores_excecao", []).has(jogador_id):
			continue
		return true
	return false


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


func _registrar_uso_habilidade_xp(jogador_id: String) -> void:
	_garantir_meta_jogador(jogador_id)
	var dados = dados_economia_jogadores[jogador_id]
	dados["habilidades_usadas"] = int(dados.get("habilidades_usadas", 0)) + 1
	if int(dados["habilidades_usadas"]) >= 5:
		_conceder_xp_partida(jogador_id, XP_CINCO_HABILIDADES, "cinco_habilidades", "Usou a habilidade ativa 5 vezes")



func _iniciar_rastreamento_evento_xp(nome_evento: String) -> void:
	_finalizar_rastreamento_evento_xp()
	_evento_xp_em_andamento = true
	_evento_xp_nome = nome_evento
	_evento_xp_perdas_construcao.clear()
	for jogador_id in ordem_original_partida:
		if dados_economia_jogadores.has(jogador_id) and not dados_economia_jogadores[jogador_id].get("falido", false):
			_evento_xp_perdas_construcao[jogador_id] = false



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


func _jogadores_elegiveis_para_eleicao() -> Array:
	var elegiveis: Array = []
	for jogador_id in lista_turnos:
		if not dados_economia_jogadores.has(jogador_id):
			continue
		if dados_economia_jogadores[jogador_id].get("falido", false):
			continue
		elegiveis.append(jogador_id)
	return elegiveis


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
