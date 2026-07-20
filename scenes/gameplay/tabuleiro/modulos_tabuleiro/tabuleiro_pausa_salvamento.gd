extends "res://scenes/gameplay/tabuleiro/modulos_tabuleiro/tabuleiro_online.gd"

# Módulo: tabuleiro_pausa_salvamento.gd

func definir_bots_pausados(pausados: bool) -> void:
	_bots_pausados = pausados
	for bot_variant: Variant in _bots_jogadores.values():
		var bot: Node = bot_variant as Node
		if bot != null and is_instance_valid(bot):
			bot.call("definir_pausado", pausados)



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



@rpc("any_peer", "call_remote", "reliable")
func _solicitar_estado_pausa_servidor(deseja_pausar: bool) -> void:
	if not OnlineTransport.is_host() or _partida_encerrada:
		return
	var peer_solicitante := OnlineTransport.get_remote_sender_id()
	_processar_solicitacao_estado_pausa(peer_solicitante, deseja_pausar)



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

func _encerrar_eleicao_apos_resultado(votacao_id: int):
	await get_tree().create_timer(ELEICAO_DURACAO_RESULTADO_SEGUNDOS).timeout
	if OnlineTransport.is_host() and votacao_id == _eleicao_id_atual:
		OnlineTransport.send_all(self, &"_encerrar_eleicao_rede", [votacao_id], true, true)


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
