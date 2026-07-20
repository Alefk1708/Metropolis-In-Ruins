extends "res://scenes/gameplay/tabuleiro/modulos_tabuleiro/tabuleiro_hud_interface.gd"

# Módulo: tabuleiro_core.gd

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


func _disparar_inflacao_global():
								multiplicador_inflacao_global += 0.15
								OnlineTransport.send_all(self, &"_mostrar_alerta_meio_da_tela", ["INFLAÇÃO GALOPANTE!\nO Baralho reiniciou.\nTodos os aluguéis subiram +15% permanentemente!"], false, true)


func _grupo_bairro_vizinho_da_posicao(posicao: int) -> String:
	var propriedade = _propriedade_vizinha_da_posicao(posicao)
	if propriedade < 0:
		return ""
	return str(tabuleiro[propriedade].get("grupo", ""))


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


@rpc("any_peer", "call_local")
func _set_dupla_status_rede(jogador_id: String, is_dupla: bool, duplas_count: int):
								if jogador_id == jogador_atual_id:
																dados_economia_jogadores[jogador_id]["duplas_consecutivas"] = duplas_count
																_dupla_pendente = is_dupla


func _e_imune_a_confisco(jogador_id: String) -> bool:
								if jogador_id == "kofi":
																return true
								return false


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


func _calcular_bonus_partida(jogador_id: String) -> int:
	var bonus = 200
	for efeito in _efeitos_ativos_por_tipo("bonus_partida"):
		if efeito.get("jogadores_excecao", []).has(jogador_id):
			continue
		bonus = max(bonus, int(efeito.get("valor", bonus)))
	if jogador_id == "breno":
		bonus = int(round(bonus * 1.5))
	return bonus


func _acordo_silencio_bloqueia(jogador_id: String) -> bool:
	return acordo_silencio_ativo and jogador_id != "breno"


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


func _get_ponto_borda(pos: Vector2, dir: Vector2, tamanho: Vector2) -> Vector2:
								if abs(dir.x) > abs(dir.y):
																return pos + Vector2(tamanho.x / 2.0, 0) if dir.x > 0 else pos - Vector2(tamanho.x / 2.0, 0)
								else:
																return pos + Vector2(0, tamanho.y / 2.0) if dir.y > 0 else pos - Vector2(0, tamanho.y / 2.0)


func _gerar_tabuleiro():
								_desenhar_ruas()
								for id_casa in tabuleiro.keys():
																_desenhar_casa(id_casa)


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

func _preco_oferta_irrecusavel(casa_id: int) -> int:
	return int(ceil(float(tabuleiro.get(casa_id, {}).get("preco", 0)) * 1.50))


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

func _personagem_local_pause() -> String:
	var personagem := _personagem_por_peer_pause(OnlineTransport.local_player_id())
	if personagem.is_empty():
		personagem = _personagem_por_peer_pause(Global.meu_peer_id)
	if personagem.is_empty() and not OnlineTransport.esta_em_sala():
		personagem = jogador_atual_id
	return personagem



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
