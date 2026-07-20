extends "res://scenes/gameplay/tabuleiro/modulos_tabuleiro/tabuleiro_base.gd"

# Módulo: tabuleiro_online.gd

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



func _peer_do_personagem_pause(personagem_id: String) -> int:
	if personagem_id.is_empty():
		return 0
	for chave_variant in Global.escolhas_da_mesa.keys():
		if str(Global.escolhas_da_mesa[chave_variant]) == personagem_id:
			return int(chave_variant)
	return 0



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



func _forcar_retomada_pausa_host() -> bool:
	if not OnlineTransport.is_host():
		return false
	return _publicar_estado_pausa_host(
		false,
		_peer_iniciador_pausa,
		_personagem_iniciador_pausa,
		_nome_iniciador_pausa
	)



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



func _on_solicitacao_desistencia_partida_online(peer_solicitante: int) -> void:
	if not OnlineTransport.usando_photon() or not OnlineTransport.is_host():
		return
	if not _processar_solicitacao_desistencia(peer_solicitante):
		push_warning(
			"[DESISTÊNCIA PHOTON] Solicitação rejeitada para peer=%d"
			% peer_solicitante
		)



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



func _peer_id_do(personagem_id: String) -> int:
				for peer_id in Global.escolhas_da_mesa.keys():
								if Global.escolhas_da_mesa[peer_id] == personagem_id:
												return peer_id
				return 1  # fallback: host local

# --- Handler do signal "solicitar_negociacao" da HUD ---
# Recebe a proposta do proponente local e a encaminha para todos via RPC.
# Validações locais pesadas (saldo, posse de props) já foram feitas no painel;
# aqui fazemos apenas validação de sanidade final no servidor antes do broadcast.

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
