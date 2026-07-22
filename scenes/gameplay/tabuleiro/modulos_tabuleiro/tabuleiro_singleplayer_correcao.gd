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
