extends "res://scenes/gameplay/tabuleiro/modulos_tabuleiro/tabuleiro_turnos_movimento.gd"

# Módulo: tabuleiro_hud_interface.gd

func _mouse_sobre_hud(pos_tela: Vector2) -> bool:
								if not hud or not is_instance_valid(hud):
																return false
								var control = hud.get_node_or_null("Control")
								if not control:
																return false
								for child in _coletar_controls_ativos(control):
																if child is Control and child.is_visible_in_tree() and child.get_global_rect().has_point(pos_tela):
																								return true
								return false


func _input(event):
								if _menu_pause_bloqueando_acoes:
																arrastando_camera = false
																toques_ativos.clear()
																return
								if _acoes_bloqueadas_por_evento():
																# Não movimenta a câmera durante a votação, mas não marca o evento
																# como tratado: os cards modais ainda precisam receber clique/teclado.
																arrastando_camera = false
																toques_ativos.clear()
																return
								if cinematica_rodando: return

								# === TOUCH (mobile) ===
								if event is InputEventScreenTouch:
																if event.pressed:
																								toques_ativos[event.index] = event.position
																								# Verifica se o toque começou sobre a HUD (botão, painel, etc.)
																								if _mouse_sobre_hud(event.position):
																																arrastando_camera = false
																								elif toques_ativos.size() == 1:
																																arrastando_camera = true
																																posicao_mouse_anterior = event.position
																else:
																								toques_ativos.erase(event.index)
																								if toques_ativos.is_empty():
																																arrastando_camera = false
																																distancia_toque_anterior = 0.0
																																if modo_espectador_local:
																																	_atualizar_alvo_camera_espectador()
																return

								if event is InputEventScreenDrag:
																# Atualiza a posição atual do toque
																toques_ativos[event.index] = event.position
																# --- PINCH-TO-ZOOM (2 dedos) ---
																if toques_ativos.size() >= 2:
																								var touches = toques_ativos.values()
																								var dist_atual = touches[0].distance_to(touches[1])
																								if distancia_toque_anterior > 0.0:
																																var fator = dist_atual / distancia_toque_anterior
																																_aplicar_zoom(fator)
																								distancia_toque_anterior = dist_atual
																								return
																# --- ARRASTAR CÂMERA (1 dedo, não começou na HUD) ---
																if arrastando_camera:
																								var delta = event.position - posicao_mouse_anterior
																								if camera:
																																camera.position -= delta / camera.zoom.x
																																# --- NOVO: limita posição para não mostrar fundo preto ---
																																_limitar_posicao_camera()
																								posicao_mouse_anterior = event.position
																								seguindo_pino = false
																return

								# === MOUSE (PC) ===
								if event is InputEventMouseButton:
																if event.button_index == MOUSE_BUTTON_LEFT:
																								if _mouse_sobre_hud(event.position):
																																arrastando_camera = false
																																if not event.pressed and modo_espectador_local:
																																	_atualizar_alvo_camera_espectador()
																																return
																								arrastando_camera = event.pressed
																								posicao_mouse_anterior = event.position
																								if not event.pressed and modo_espectador_local:
																									_atualizar_alvo_camera_espectador()
																elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
																								if not _mouse_sobre_hud(event.position):
																																_aplicar_zoom(1.1)
																elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
																								if not _mouse_sobre_hud(event.position):
																																_aplicar_zoom(0.9)
								elif event is InputEventMouseMotion and arrastando_camera:
																var delta = event.position - posicao_mouse_anterior
																if camera:
																								camera.position -= delta / camera.zoom.x
																								# --- NOVO: limita posição para não mostrar fundo preto ---
																								_limitar_posicao_camera()
																posicao_mouse_anterior = event.position
																seguindo_pino = false


func _on_hud_solicitar_opcoes_alvo(id_personagem: String):
								if _acao_bloqueada_por_eleicao(true):
																return
								var meu_personagem_local = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
								# Segurança: só o jogador local pode pedir suas próprias opções
								# Verifica se é a vez do jogador
								if jogador_atual_id != meu_personagem_local:
												if hud and hud.has_method("mostrar_aviso_turno"):
																hud.mostrar_aviso_turno("Aguarde sua vez para usar habilidades!")
												return
								if dados_economia_jogadores[id_personagem].get("recarga_hab", 0) > 0:
																																if pinos_jogadores.has(id_personagem):
																																								pinos_jogadores[id_personagem].mostrar_texto_flutuante("HABILIDADE EM RECARGA", Color(0.9, 0.3, 0.3))
																																return
								# Apagão Digital desativa habilidades
								if _habilidades_bloqueadas_por_efeito(id_personagem):
																																if pinos_jogadores.has(id_personagem):
																																								pinos_jogadores[id_personagem].mostrar_texto_flutuante("APAGÃO DESATIVA HABILIDADES", Color(0.5, 0.5, 0.5))
																																return
								# Bloqueio extra para Kofi: eventos que bloqueiam construção
								if id_personagem == "kofi" and _opcoes_kofi(id_personagem).is_empty():
																																if pinos_jogadores.has(id_personagem):
																																								pinos_jogadores[id_personagem].mostrar_texto_flutuante("CONSTRUÇÃO BLOQUEADA POR EVENTO", Color(0.9, 0.3, 0.3))
																																return
								# Computa as opções de alvo
								var opcoes = _computar_opcoes_alvo_habilidade(id_personagem)
								# Mostra o overlay com a lista populada
								var nome_hab = NOMES_HABILIDADES.get(id_personagem, "Habilidade")
								var desc_hab = DESC_HABILIDADES_UI.get(id_personagem, DESC_HABILIDADES.get(id_personagem, ""))
								var cor_pers = cor_por_jogador.get(id_personagem, Color.WHITE)
								if hud and hud.has_method("mostrar_overlay_habilidade_com_alvos"):
																																hud.mostrar_overlay_habilidade_com_alvos(id_personagem, nome_hab, desc_hab, cor_pers, opcoes)

# --- NOVO (UI de seleção de alvo): computa a lista de opções de alvo válidas
#     para a habilidade do personagem. Cada opção é um Dictionary:
#       { "texto": str, "texto_curto": str, "alvo_id": str, "casa_id": int, "cor": Color }
#     Retorna Array vazio se não há alvos válidos (HUD mostra mensagem). ---

func _on_menu_pause_visibilidade_alterada(aberto: bool) -> void:
	_menu_pause_bloqueando_acoes = aberto
	if not _bots_jogadores.is_empty():
		definir_bots_pausados(aberto)
	arrastando_camera = false
	toques_ativos.clear()



func _conectar_sinais_hud_novos():
								if hud.has_signal("solicitar_habilidade"):
																hud.solicitar_habilidade.connect(_on_hud_solicitar_habilidade)
								# --- NOVO (UI de seleção de alvo): conecta o signal que pede a lista
								#     de alvos válidos para a habilidade do personagem. ---
								if hud.has_signal("solicitar_opcoes_alvo"):
																hud.solicitar_opcoes_alvo.connect(_on_hud_solicitar_opcoes_alvo)
								if hud.has_signal("solicitar_hipoteca"):
																hud.solicitar_hipoteca.connect(_on_hud_solicitar_hipoteca)
								if hud.has_signal("solicitar_fianca_prisao"):
																hud.solicitar_fianca_prisao.connect(_on_hud_solicitar_fianca_prisao)
								# --- NOVO (Fase 1 — Negociação): conecta os 2 novos signals da HUD ---
								if hud.has_signal("solicitar_negociacao"):
																hud.solicitar_negociacao.connect(_on_hud_solicitar_negociacao)
								if hud.has_signal("responder_negociacao"):
																hud.responder_negociacao.connect(_on_hud_responder_negociacao)
								# --- NOVO (Fase 3 — Alianças): conecta signals de aliança ---
								if hud.has_signal("solicitar_alianca"):
																hud.solicitar_alianca.connect(_on_hud_solicitar_alianca)
								# responder_alianca não é necessário — usamos responder_negociacao
								# (o tipo da proposta diferencia aliança de troca)
								# --- NOVO (Fase 4 — Promessas): conecta signals de promessas ---
								if hud.has_signal("solicitar_criar_promessa"):
																hud.solicitar_criar_promessa.connect(_on_hud_solicitar_criar_promessa)
								if hud.has_signal("solicitar_quebrar_promessa"):
																hud.solicitar_quebrar_promessa.connect(_on_hud_solicitar_quebrar_promessa)
								# --- NOVO (Eleições Municipais): conecta signal de voto. ---
								if hud.has_signal("voto_eleicao_enviado"):
																hud.voto_eleicao_enviado.connect(_on_hud_voto_eleicao)

								# Eventos globais com decisão do jogador.
								if hud.has_signal("decisao_evento_enviada"):
																hud.decisao_evento_enviada.connect(_on_hud_decisao_evento)
# ============================================================================
# SISTEMA DE NEGOCIAÇÃO (Fase 1 — MVP: Troca de dinheiro + propriedades)
# ============================================================================
# Implementa 3 RPCs:
#   1. _enviar_proposta_negociacao_rede(proposta)   — A envia para todos; B mostra modal
#   2. _responder_proposta_negociacao_rede(id, ok, aceitador) — B responde; se aceitou, todos executam
#   3. _executar_negociacao_rede(proposta)          — todos aplicam a troca atomicamente
#
# Regras (Fase 1):
#   - Não toca em _calcular_aluguel nem em _pagar_aluguel_rede.
#   - Propriedades com hotéis (nível 5) e hipotecadas são transferíveis.
#   - Não pode negociar consigo mesmo nem com falidos.
#   - Limite de 3 propostas pendentes por receptor (anti-spam).
# ============================================================================

# Propostas pendentes por receptor. Estrutura: { "id_proposta": proposta_dict }

func _on_hud_solicitar_alianca(proposta: Dictionary):
				if _acao_bloqueada_por_eleicao(true):
								return
				if leilao_em_andamento:
								if pinos_jogadores.has(proposta.get("de", "")):
												pinos_jogadores[proposta["de"]].mostrar_texto_flutuante("ALIANÇA BLOQUEADA NO LEILÃO", Color(0.9, 0.3, 0.3))
								hud.atualizar_status_negociacao("❌ Alianças bloqueadas durante leilão.", Color(0.95, 0.3, 0.3))
								await get_tree().create_timer(1.5).timeout
								hud.fechar_painel_negociacao()
								return
				var proponente_id: String = str(proposta.get("de", ""))
				var bloqueada_por_acordo: bool = _acordo_silencio_bloqueia(proponente_id)
				var bloqueada_por_efeito: bool = _negociacoes_bloqueadas_por_efeito(proponente_id)
				if bloqueada_por_acordo or bloqueada_por_efeito:
								var motivo_bloqueio: String = "ACORDO DE SILÊNCIO ATIVO" if bloqueada_por_acordo else "ALIANÇAS BLOQUEADAS"
								if pinos_jogadores.has(proponente_id):
																pinos_jogadores[proponente_id].mostrar_texto_flutuante(motivo_bloqueio, Color(0.9, 0.3, 0.3))
								var status_bloqueio: String = "❌ Alianças bloqueadas pelo Acordo de Silêncio neste turno." if bloqueada_por_acordo else "❌ Alianças bloqueadas por um efeito ativo."
								hud.atualizar_status_negociacao(status_bloqueio, Color(0.95, 0.3, 0.3))
								await get_tree().create_timer(1.5).timeout
								hud.fechar_painel_negociacao()
								return
				if lista_turnos.size() < 2:
								hud.atualizar_status_negociacao("❌ Partida encerrada.", Color(0.95, 0.3, 0.3))
								await get_tree().create_timer(1.5).timeout
								hud.fechar_painel_negociacao()
								return
				# Encaminha para todos (reaproveita o RPC de negociação — a proposta
				# tem "tipo": "alianca" para o receptor saber que é aliança)
				OnlineTransport.send_all(self, &"_enviar_proposta_negociacao_rede", [proposta], false, true)

# ============================================================================
# RPC 1: PROPONENTE ENVIA A PROPOSTA — todos recebem, mas só o "para" mostra modal
# ============================================================================

func _on_hud_solicitar_criar_promessa(texto: String, autor_id: String):
	if _acao_bloqueada_por_eleicao(false):
		return
	var texto_limpo = texto.strip_edges().substr(0, 180)
	if texto_limpo == "":
		return
	var autor_local = str(Global.escolhas_da_mesa.get(Global.meu_peer_id, autor_id))
	if OnlineTransport.is_host():
		_servidor_criar_promessa(autor_local, texto_limpo)
	else:
		OnlineTransport.send_host(self, &"_solicitar_criar_promessa_servidor", [texto_limpo], false)


func _on_hud_solicitar_quebrar_promessa(id_promessa: String):
	if _acao_bloqueada_por_eleicao(false):
		return
	var reporter_local = str(Global.escolhas_da_mesa.get(Global.meu_peer_id, ""))
	if reporter_local == "":
		return
	if OnlineTransport.is_host():
		_servidor_reportar_quebra(id_promessa, reporter_local)
	else:
		OnlineTransport.send_host(self, &"_solicitar_quebrar_promessa_servidor", [id_promessa], false)


func _atualizar_hud_promessas():
	if hud and hud.has_method("atualizar_painel_promessas"):
		hud.atualizar_painel_promessas(_promessas_globais)

# ============================================================================
# ELEIÇÕES MUNICIPAIS — VOTAÇÃO AUTORITATIVA E MODAL
# ============================================================================
