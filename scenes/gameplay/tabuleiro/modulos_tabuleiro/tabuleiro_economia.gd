extends "res://scenes/gameplay/tabuleiro/modulos_tabuleiro/tabuleiro_visual_camera.gd"

# Módulo: tabuleiro_economia.gd

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

func _on_leilao_timeout_local():
								_leilao_timeout = true
								# Se o jogador ainda não deu lance, marca como $0
								if _lance_local_leilao == -1:
																_lance_local_leilao = 0

# --- NOVO: Handler local do sinal de lance (captura o valor) ---

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



func _marcar_perda_construcao_evento_xp(jogador_id: String) -> void:
	if not _evento_xp_em_andamento or jogador_id == "":
		return
	if _evento_xp_perdas_construcao.has(jogador_id):
		_evento_xp_perdas_construcao[jogador_id] = true



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



func _contar_hipotecas_do_jogador(jogador_id: String) -> int:
								var count = 0
								for id in tabuleiro.keys():
																if registro_propriedades.has(id) and registro_propriedades[id] == jogador_id:
																								if tabuleiro[id].get("hipotecada", false):
																																count += 1
								return count


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

@rpc("authority", "call_remote", "reliable")
func _notificar_falha_fianca_local(mensagem: String):
	if hud and hud.has_method("resolver_solicitacao_fianca"):
		hud.resolver_solicitacao_fianca(false, mensagem)


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
