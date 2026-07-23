extends "res://scenes/gameplay/tabuleiro/modulos_tabuleiro/tabuleiro_singleplayer_correcao.gd"

# ============================================================================
# DIANA — PASSIVA FONTE ANÔNIMA
# ============================================================================
#
# O módulo de eventos chama _sincronizar_proximo_evento_rede() depois de
# pré-sortear o próximo Evento Global, porém essa função deixou de existir
# durante a separação do antigo tabuleiro.gd em módulos.
#
# Sem o RPC:
# - proximo_evento_global nunca era atualizado;
# - proximo_evento_descricao permanecia vazia;
# - fonte_anonima_evento_previsto nunca era preenchido;
# - o dossiê da Diana não recebia a seção "FONTE ANÔNIMA".
#
# A passiva concede UMA previsão por partida. O evento pré-sorteado continua
# sendo a fonte autoritativa usada pelo motor no próximo reveal.
# ============================================================================


@rpc("authority", "call_local", "reliable")
func _sincronizar_proximo_evento_rede(
	nome_evento: String,
	descricao_evento: String
) -> void:
	# Todos os peers precisam conhecer a fila autoritativa, mesmo quando Diana
	# não participa da partida. _sortear_evento_global() usa este valor para
	# revelar exatamente o evento que foi pré-sorteado.
	proximo_evento_global = nome_evento
	proximo_evento_descricao = descricao_evento

	if not dados_economia_jogadores.has("diana"):
		return
	if not lista_turnos.has("diana"):
		return

	var dados_diana: Dictionary = dados_economia_jogadores["diana"]
	if bool(dados_diana.get("falido", false)):
		return

	var evento_ja_registrado: String = str(
		dados_diana.get(
			"fonte_anonima_evento_previsto",
			""
		)
	)
	var previsao_ja_concedida: bool = bool(
		dados_diana.get(
			"fonte_anonima_previsao_concedida",
			false
		)
	)

	# Compatibilidade com partidas salvas por versões intermediárias: se já há
	# um evento previsto, considera a passiva concedida mesmo sem a nova flag.
	if not evento_ja_registrado.is_empty():
		previsao_ja_concedida = true
		dados_diana[
			"fonte_anonima_previsao_concedida"
		] = true

	# Fonte Anônima revela somente o primeiro próximo evento válido da partida.
	# A flag permanece true depois que o evento for revelado e o campo de evento
	# for limpo pelo fluxo atual, impedindo previsões infinitas.
	if (
		not previsao_ja_concedida
		and evento_ja_registrado.is_empty()
		and not nome_evento.is_empty()
	):
		dados_diana[
			"fonte_anonima_evento_previsto"
		] = nome_evento
		dados_diana[
			"fonte_anonima_previsao_concedida"
		] = true
		evento_ja_registrado = nome_evento

	_atualizar_fonte_anonima_diana_local(
		evento_ja_registrado
	)

	GerenciadorSalvamento.marcar_estado_alterado(self)


func _atualizar_fonte_anonima_diana_local(
	evento_previsto: String
) -> void:
	var personagem_local: String = str(
		Global.escolhas_da_mesa.get(
			Global.meu_peer_id,
			""
		)
	)
	if personagem_local != "diana":
		return
	if evento_previsto.is_empty():
		return
	if evento_previsto != proximo_evento_global:
		return
	if hud == null or not is_instance_valid(hud):
		return
	if not hud.has_method("alimentar_previsao_evento"):
		return

	hud.alimentar_previsao_evento(
		proximo_evento_global,
		proximo_evento_descricao
	)


# ============================================================================
# PRESERVAÇÃO DO EVENTO PREVISTO
# ============================================================================
#
# O fluxo de rodada chama _pre_sortear_proximo_evento() tanto depois de revelar
# um Evento Global quanto na rodada seguinte de Mercado Estável. Sem esta trava,
# o segundo chamado substituía o evento já mostrado à Diana antes do reveal.
# ============================================================================


func _pre_sortear_proximo_evento() -> void:
	if not OnlineTransport.is_host():
		return

	# Há um evento futuro válido aguardando reveal. Enquanto ele for diferente
	# do evento atualmente ativo, ele não pode ser substituído.
	if (
		not proximo_evento_global.is_empty()
		and proximo_evento_global != evento_ativo
	):
		_restaurar_fonte_anonima_diana_do_estado()
		return

	# O campo está vazio ou contém o evento que acabou de ser revelado.
	# Nesse caso, o motor original pode escolher o próximo evento normalmente.
	super._pre_sortear_proximo_evento()


func aplicar_snapshot_online(snapshot: Dictionary) -> void:
	super.aplicar_snapshot_online(snapshot)

	# Em reconexões Photon, o snapshot restaura a previsão no estado antes de a
	# HUD do convidado terminar de montar. O deferred reaplica a informação no
	# dossiê quando a interface já está pronta.
	call_deferred(
		"_restaurar_fonte_anonima_diana_do_estado"
	)


func _ready() -> void:
	super._ready()

	# Também cobre partidas retomadas localmente ou por LAN, nas quais o estado
	# salvo pode já conter uma previsão válida quando a cena é aberta.
	call_deferred(
		"_restaurar_fonte_anonima_diana_do_estado"
	)


func _restaurar_fonte_anonima_diana_do_estado() -> void:
	await get_tree().process_frame

	if not is_inside_tree():
		return
	if not dados_economia_jogadores.has("diana"):
		return
	if not lista_turnos.has("diana"):
		return

	var evento_previsto: String = str(
		dados_economia_jogadores["diana"].get(
			"fonte_anonima_evento_previsto",
			""
		)
	)
	if evento_previsto.is_empty():
		return
	if evento_previsto != proximo_evento_global:
		return

	_atualizar_fonte_anonima_diana_local(
		evento_previsto
	)

