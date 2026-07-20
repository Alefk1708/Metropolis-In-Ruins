extends "res://scenes/gameplay/tabuleiro/modulos_tabuleiro/tabuleiro_eventos_cartas.gd"

# Módulo: tabuleiro_turnos_movimento.gd

func _on_dados_rolados_recebidos(d1: int, d2: int):
								if _acoes_bloqueadas_por_evento():
																return
								# --- Guard: previne processamento duplo da mesma rolagem ---
								if _processando_dados:
																return
								_processando_dados = true
								_emitir_evento_tutorial(
																"dados_rolados",
																{
																								"jogador_id": jogador_atual_id,
																								"dado1": d1,
																								"dado2": d2,
																}
								)

								# Armazena últimos dados para a fórmula de utilidades
								ultimo_dado1 = d1
								ultimo_dado2 = d2

								var dados_jogador = dados_economia_jogadores[jogador_atual_id]

								# --- SISTEMA DE PRISÃO — Verifica se o jogador está preso ---
								if dados_jogador.get("preso", false):
																if d1 == d2:
																								# Tirou dupla: sai da prisão e move
																								# --- CORREÇÃO: Usa RPC para sincronizar a liberação em TODOS os peers.
																								#     Antes, só o peer que clicou em "Girar" removia as barras —
																								#     os outros viam as barras presas para sempre. ---
																								OnlineTransport.send_all(self, &"_sair_da_prisao_rede", [jogador_atual_id], false, true)
																								if pinos_jogadores.has(jogador_atual_id):
																																pinos_jogadores[jogador_atual_id].mostrar_texto_flutuante("DUPLA! LIVRE!", Color(0.4, 1.0, 0.4))
																								OnlineTransport.send_all(self, &"_sincronizar_movimento_na_rede", [jogador_atual_id, d1 + d2], false, true)
																else:
																								dados_jogador["turnos_preso"] += 1
																								if dados_jogador["turnos_preso"] >= 3:
																																# 3 tentativas sem dupla: paga $50 e sai
																																# --- CORREÇÃO: Usa RPC para sincronizar a liberação em TODOS os peers.
																																#     Antes, só o peer que clicou em "Girar" removia as barras —
																																#     os outros viam as barras presas para sempre. ---
																																OnlineTransport.send_all(self, &"_sair_da_prisao_rede", [jogador_atual_id], false, true)
																																# --- CORREÇÃO: Sincroniza a cobrança dos $50 via RPC.
																																#     Antes era só `dados_jogador["dinheiro"] -= 50` local,
																																#     que só diminuía no peer que clicou em girar. Os outros
																																#     peers não viam a cobrança — jogador saía "de graça"
																																#     na visão dos outros. ---
																																# --- BUG #7: fiança de prisão é "casa_especial" — Imunidade do Breno não dispara. ---
																																OnlineTransport.send_all(self, &"_aplicar_mudanca_dinheiro_rede", [jogador_atual_id, -50, "casa_especial"], false, true)
																																if pinos_jogadores.has(jogador_atual_id):
																																								pinos_jogadores[jogador_atual_id].mostrar_texto_flutuante("PAGOU $50", Color(0.9, 0.3, 0.3))
																																OnlineTransport.send_all(self, &"_sincronizar_movimento_na_rede", [jogador_atual_id, d1 + d2], false, true)
																								else:
																																# Continua preso
																																if pinos_jogadores.has(jogador_atual_id):
																																								pinos_jogadores[jogador_atual_id].mostrar_texto_flutuante("AINDA PRESO", Color(0.9, 0.3, 0.3))
																																# --- CORREÇÃO DO BUG DA PRISÃO EM MULTIPLAYER:
																																#     Antes havia `if OnlineTransport.is_host(): _finalizar_pouso_e_passar_turno()`.
																																#     O problema: _on_dados_rolados_recebidos roda LOCALMENTE no peer que
																																#     clicou em girar (não necessariamente o server). Se o jogador preso
																																#     estiver no peer 2 (client), is_server() retorna false e o turno
																																#     NUNCA passa — o painel de dados some e o jogo trava.
																																#     Solução: chamar _continuar_preso_passar_turno_rede.rpc() que é
																																#     call_local em todos os peers. Dentro dele, apenas o server
																																#     dispara _avancar_turno_rede (via _processar_passagem_de_turno). ---
																																OnlineTransport.send_all(self, &"_continuar_preso_passar_turno_rede", [], false, true)
																_processando_dados = false
																return

								# --- NOVO (GDD §5.2): Sistema de Duplas.
								#     - Tirar dupla (d1 == d2): jogador rola novamente após o movimento.
								#     - 3 duplas seguidas: vai preso.
								#     Implementação: antes de mover, verifica se é dupla.
								#     Se for, incrementa duplas_consecutivas e seta _dupla_pendente
								#     via RPC (para sincronizar com todos os peers). Se 3 duplas,
								#     envia para a prisão em vez de mover. ---
								var passos = d1 + d2
								var is_dupla = (d1 == d2)

								if is_dupla:
																var dados_jog = dados_economia_jogadores[jogador_atual_id]
																dados_jog["duplas_consecutivas"] = dados_jog.get("duplas_consecutivas", 0) + 1
																if dados_jog["duplas_consecutivas"] >= 3:
																								# 3 duplas = prisão! Não move, vai direto preso.
																								dados_jog["duplas_consecutivas"] = 0
																								_dupla_pendente = false
																								OnlineTransport.send_all(self, &"_set_dupla_status_rede", [jogador_atual_id, false, 0], false, true)
																								if pinos_jogadores.has(jogador_atual_id):
																																pinos_jogadores[jogador_atual_id].mostrar_texto_flutuante("3 DUPLAS! PRESO!", Color(0.9, 0.3, 0.3))
																								# Envia para a prisão (RPC para todos os peers)
																								# --- BUG FIX (CRITICAL #1): Padronizado — sempre espera 1s
																								#     antes de enviar para a prisão, independente de ser server
																								#     ou client. Antes, server esperava e client não, causando
																								#     timing inconsistente entre peers. ---
																								await get_tree().create_timer(1.0).timeout
																								OnlineTransport.send_all(self, &"_ir_para_prisao_rede", [jogador_atual_id], false, true)
																								_processando_dados = false
																								return
																# Menos de 3 duplas — seta flag para rolar novamente
																OnlineTransport.send_all(self, &"_set_dupla_status_rede", [jogador_atual_id, true, dados_jog["duplas_consecutivas"]], false, true)
								else:
																# Não é dupla — reseta contador
																dados_economia_jogadores[jogador_atual_id]["duplas_consecutivas"] = 0
																OnlineTransport.send_all(self, &"_set_dupla_status_rede", [jogador_atual_id, false, 0], false, true)

								# --- Texto flutuante mostrando os dados ANTES do movimento ---
								if pinos_jogadores.has(jogador_atual_id):
																pinos_jogadores[jogador_atual_id].mostrar_texto_flutuante(
																								"DADOS: " + str(d1) + "+" + str(d2) + " = " + str(passos),
																								Color(0.95, 0.85, 0.15)
																)

								OnlineTransport.send_all(self, &"_sincronizar_movimento_na_rede", [jogador_atual_id, passos], false, true)
								_processando_dados = false


func _avancar_turno():
								indice_turno_atual = (indice_turno_atual + 1) % lista_turnos.size()
								jogador_atual_id = lista_turnos[indice_turno_atual]
								
								_atualizar_hud_ciclo_turno()
								_verificar_permissao_de_clique()


func _atualizar_hud_ciclo_turno():
								var meu_personagem_local = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
								if meu_personagem_local == "" or not dados_economia_jogadores.has(meu_personagem_local): return
								
								var dados_locais = dados_economia_jogadores[meu_personagem_local]
								hud.atualizar_status_jogador(dados_locais["nome"], dados_locais["dinheiro"], dados_locais["propriedades_compradas"])
								if hud.has_method("atualizar_reputacao_jogador"):
									hud.atualizar_reputacao_jogador(int(dados_locais.get("reputacao", REPUTACAO_INICIAL)), int(dados_locais.get("xp_partida", 0)))
								# --- NOVO (Fase 2): atualiza o painel de imunidades abaixo do
								#     CantoSupEsq_Jogador com as imunidades ativas do jogador local. ---
								if hud.has_method("atualizar_painel_imunidades"):
																hud.atualizar_painel_imunidades(dados_locais.get("imunidades", []))
								# --- NOVO (Fase 3): atualiza o painel de alianças abaixo do
								#     painel de imunidades com as alianças ativas do jogador local. ---
								if hud.has_method("atualizar_painel_aliancas"):
																hud.atualizar_painel_aliancas(dados_locais.get("aliancas", []))
								# --- NOVO (Fase 4): atualiza o painel de promessas (lista global) ---
								if hud.has_method("atualizar_painel_promessas"):
																hud.atualizar_painel_promessas(_promessas_globais)
								if hud.has_method("atualizar_cartas_guardadas"):
									hud.atualizar_cartas_guardadas(
										int(dados_locais.get("cartas_construcao_gratis", 0)),
										int(dados_locais.get("cartas_sair_prisao", 0))
									)
								
								var nome_da_habilidade = "Poder Especial"
								match meu_personagem_local:
																"yasmin": nome_da_habilidade = "Oferta Irrecusável"
																"breno": nome_da_habilidade = "Decreto Emergencial"
																"mira": nome_da_habilidade = "Retrofit Urbano"
																"igor": nome_da_habilidade = "Especulação Imobiliária" 
																"diana": nome_da_habilidade = "Vazamento Seletivo"
																"kofi": nome_da_habilidade = "Mutirão" 
								
								hud.atualizar_habilidade(nome_da_habilidade, dados_locais["recarga_hab"])
								
								if meu_personagem_local == "diana":
																var payload_espionagem = []
																# --- CORREÇÃO: iterar sobre lista_turnos (jogadores ativos na partida)
																#     em vez de dados_economia_jogadores.keys() (que tem os 6 personagens
																#     fixos do dicionário base). Antes, o dossiê mostrava personagens que
																#     não estavam na partida. Agora só mostra quem está jogando.
																#     Também pula falidos (mesmo que ainda estejam em lista_turnos por
																#     algum motivo de sincronização, não devem aparecer no dossiê). ---
																for id in lista_turnos:
																								if id == "diana":
																																continue
																								if not dados_economia_jogadores.has(id):
																																continue
																								if dados_economia_jogadores[id].get("falido", false):
																																continue
																								# --- NOVO (Fase 2): inclui imunidades ativas de cada jogador
																								#     no dossiê da Diana, para que ela possa ver quem tem
																								#     imunidade contra quem e por quantas visitas/turnos. ---
																								var imunidades_txt = ""
																								var imunidades_lista = dados_economia_jogadores[id].get("imunidades", [])
																								if imunidades_lista.size() > 0:
																																var partes: Array = []
																																for imun in imunidades_lista:
																																								var de_id = imun.get("de", "")
																																								var de_nome_curto = dados_economia_jogadores.get(de_id, {}).get("nome", de_id)
																																								# Pega só o primeiro nome (ex.: "Yasmin Khalil" → "Yasmin")
																																								var primeiro_espaco = de_nome_curto.find(" ")
																																								if primeiro_espaco > 0:
																																																de_nome_curto = de_nome_curto.substr(0, primeiro_espaco)
																																								partes.append(de_nome_curto + "(" + str(imun.get("visitas_restantes", 0)) + "v/" + str(imun.get("turnos_restantes", 0)) + "T)")
																																								imunidades_txt = ", ".join(partes)
																								else:
																																imunidades_txt = "nenhuma"
																								# --- NOVO (Fase 3): inclui alianças ativas de cada jogador
																								#     no dossiê da Diana, para que ela possa ver quem é aliado
																								#     de quem e por quantos turnos. ---
																								var aliancas_txt = ""
																								var aliancas_lista = dados_economia_jogadores[id].get("aliancas", [])
																								if aliancas_lista.size() > 0:
																																var partes_al: Array = []
																																for alianca in aliancas_lista:
																																								var com_id = alianca.get("com", "")
																																								var com_nome_curto = dados_economia_jogadores.get(com_id, {}).get("nome", com_id)
																																								var espaco_al = com_nome_curto.find(" ")
																																								if espaco_al > 0:
																																																com_nome_curto = com_nome_curto.substr(0, espaco_al)
																																								partes_al.append(com_nome_curto + "(" + str(alianca.get("turnos_restantes", 0)) + "T)")
																																								aliancas_txt = ", ".join(partes_al)
																								else:
																																aliancas_txt = "nenhuma"
																								# --- NOVO (Fase 4): conta promessas feitas e quebradas ---
																								var promessas_feitas = 0
																								var promessas_quebradas = 0
																								for p in _promessas_globais:
																																if p.get("autor_id", "") == id:
																																								promessas_feitas += 1
																																								if p.get("quebrada", false):
																																																promessas_quebradas += 1
																								var promessas_txt = str(promessas_feitas) + " feitas"
																								if promessas_quebradas > 0:
																																promessas_txt += " (" + str(promessas_quebradas) + " quebradas!)"
																								payload_espionagem.append({
																																"nome": dados_economia_jogadores[id]["nome"],
																																"dinheiro": dados_economia_jogadores[id]["dinheiro"],
																																"props": dados_economia_jogadores[id]["propriedades_compradas"],
																																"imunidades": imunidades_txt,
																																"aliancas": aliancas_txt,
																													"promessas": promessas_txt,
																													"reputacao": int(dados_economia_jogadores[id].get("reputacao", REPUTACAO_INICIAL)),
																													"xp_partida": int(dados_economia_jogadores[id].get("xp_partida", 0))
																								})
																hud.alimentar_dados_dossie(payload_espionagem)
																hud.container_dossie.visible = true
								
								if meu_personagem_local == "yasmin":
																# --- BUG #4/#5 FIX: Usa tendências FIXAS geradas no início da rodada
																#     (em _avancar_turno_rede) em vez de sortear aleatoriamente a
																#     cada atualização da HUD. As tendências permanecem as mesmas
																#     por 2 rodadas, permitindo que Yasmin realmente use a info. ---
																if tendencias_fixas.is_empty():
																								# Fallback: gera agora se ainda não foram geradas
																								_gerar_tendencias_yasmin()
																hud.alimentar_dados_relatorio(tendencias_fixas.duplicate())
																hud.container_relatorio.visible = true
								
								# Fonte Anônima revela um único Evento Global por partida. A previsão
								# permanece no dossiê somente até o evento previsto ser revelado.
								if meu_personagem_local == "diana" and dados_economia_jogadores.has("diana"):
																var evento_previsto: String = str(dados_economia_jogadores["diana"].get("fonte_anonima_evento_previsto", ""))
																if evento_previsto != "" and evento_previsto == proximo_evento_global and hud.has_method("alimentar_previsao_evento"):
																								hud.alimentar_previsao_evento(proximo_evento_global, proximo_evento_descricao)

								_atualizar_hud_minha_casa()
								_atualizar_menu_construcao()
								GerenciadorSalvamento.marcar_estado_alterado(self)


func _atualizar_hud_minha_casa():
								var meu_personagem_local = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
								if meu_personagem_local == "" or not pinos_jogadores.has(meu_personagem_local):
																return
																
								var minha_casa_id = pinos_jogadores[meu_personagem_local].casa_atual
								var dados_casa = tabuleiro[minha_casa_id].duplicate() 
								var dono_nome = "Nenhum"
								var dono_id = ""
								
								if registro_propriedades.has(minha_casa_id):
																dono_id = registro_propriedades[minha_casa_id]
																dono_nome = dados_economia_jogadores[dono_id]["nome"]
																dados_casa["aluguel_atual"] = _calcular_aluguel(minha_casa_id, dono_id)
								else:
																dados_casa["aluguel_atual"] = _calcular_aluguel(minha_casa_id, "")
																
								var info = ""
								var grupo = dados_casa.get("grupo", "")

								if dados_casa["tipo"] == "propriedade":
																info += "🏢 Construção: Nível " + str(dados_casa.get("nivel", 0)) + "/5\n"
																if dono_id != "" and _tem_monopolio(dono_id, grupo):
																								info += "👑 MONOPÓLIO ATIVO: Aluguel Base Dobrado!\n"

								elif dados_casa["tipo"] == "transporte":
																var linhas_dono = 0
																if dono_id != "":
																								for id in tabuleiro.keys():
																																if tabuleiro[id].get("grupo") == "Transporte" and registro_propriedades.has(id) and registro_propriedades[id] == dono_id:
																																								linhas_dono += 1
																info += "🚆 Linhas do Dono: " + str(linhas_dono) + "/4\n(Aluguel: $25, $50, $100 ou $200)\n"

								elif dados_casa["tipo"] == "utilidade":
																info += "⚡ Serviços: Cobra um multiplicador dos dados.\n"

								if evento_ativo == "Bolha Imobiliária — Expansão":
																info += "📈 Mercado Aquecido: Aluguel +25%\n"
								elif evento_ativo == "Bolha Imobiliária — Estouro":
																info += "📉 Bolha Estourou: Aluguel -40%\n"
								elif evento_ativo == "Greve Geral" and grupo == "Transporte":
																info += "🛑 Greve Geral: Catraca Livre (Aluguel $0)\n"
								elif evento_ativo == "Onda de Calor Extremo" and grupo == "Utilidade":
																info += "🔥 Superaquecimento: Lucros Dobrados\n"
								elif evento_ativo == "Enchente da Bacia Norte":
																if grupo in ["Rosa", "Marrom"]:
																								info += "🌊 Bairro Alagado: Aluguel $0\n"
																elif grupo == "Laranja":
																								info += "📈 Procura por Área Seca: Aluguel +15%\n"
								elif evento_ativo == "Migração em Massa":
																if grupo in ["Rosa", "Marrom"]:
																								info += "📈 Superlotação: Aluguel x2\n"
																elif grupo in ["Verde", "Azul-Escuro"]:
																								info += "📉 Pânico da Elite: Aluguel -10%\n"
								elif evento_ativo == "Boom das Startups" and grupo in ["Verde", "Vermelho"]:
																info += "🚀 Especulação Tech: Aluguel x2\n"

								if multiplicador_inflacao_global > 1.0:
																var porc = int((multiplicador_inflacao_global - 1.0) * 100)
																info += "💸 Inflação Global: +" + str(porc) + "%\n"

								# --- NOVO: Mostra estado de hipoteca ---
								if dados_casa.get("hipotecada", false):
																info += "🔒 HIPOTECADA — Sem aluguel\n"

								# --- NOVO: Mostra modificadores de habilidade ativos ---
								for pid in lista_turnos:
																var dados_p = dados_economia_jogadores[pid]
																if dados_p.get("decreto_turnos", 0) > 0 and dados_p.get("decreto_grupo", "") == grupo:
																								info += "⚖️ DECRETO DO BRENO: 2x aluguel (" + str(dados_p["decreto_turnos"]) + "T)\n"
																if dados_p.get("especulacao_turnos", 0) > 0 and dados_p.get("especulacao_casa", -1) == minha_casa_id:
																								info += "📈 ESPECULAÇÃO DO IGOR: 2x aluguel (" + str(dados_p["especulacao_turnos"]) + "T)\n"

								dados_casa["info_extra"] = info
								hud.atualizar_info_casa(dados_casa, dono_nome)

								# --- CORREÇÃO: O botão flutuante de hipoteca foi movido para o painel
								#     de Gestão de Propriedades. Aqui apenas garantimos que ele fique escondido. ---
								hud.esconder_botao_hipoteca()


func _executar_casa_especial(casa_id: int):
								var dados = dados_economia_jogadores[jogador_atual_id]
								var mudanca_dinheiro = 0
								
								match casa_id:
																4:
																								# --- BUG FIX (LOW #13): Antes, patrimônio estimado usava
																								#     propriedades_compradas * 100 (valor arbitrário). Agora soma o
																								#     preço real de cada propriedade. ---
																								var patrimonio_estimado = dados["dinheiro"]
																								for cid in dados.get("propriedades_lista", []):
																																if tabuleiro.has(cid):
																																								patrimonio_estimado += tabuleiro[cid].get("preco", 0)
																								var dez_porcento = int(patrimonio_estimado * 0.1)
																								mudanca_dinheiro = -min(200, dez_porcento)
																								_mostrar_alerta_meio_da_tela("IMPOSTO DE RENDA\nO Leão pegou: $" + str(abs(mudanca_dinheiro)))
																7:
																								mudanca_dinheiro = 100
																								_mostrar_alerta_meio_da_tela("BÔNUS DE PRODUTIVIDADE\nRecebeu $" + str(mudanca_dinheiro))
																10:
																								_mostrar_alerta_meio_da_tela("PENITENCIÁRIA\nApenas de visita...")
																17:
																								mudanca_dinheiro = -50
																								turno_construcao_bloqueada = true
																								_mostrar_alerta_meio_da_tela("ZONA DE OBRAS\nTaxa de congestionamento: Pague $50\nConstruções bloqueadas até o fim do turno.")
																20:
																								_mostrar_alerta_meio_da_tela("PARQUE LIVRE\nRespire fundo... Nenhuma crise aqui.")
																22:
																								_mostrar_alerta_meio_da_tela("ACORDO DE SILÊNCIO\nAs negociações estão bloqueadas neste turno.\nBreno é imune.")
																								# --- BUG FIX (LOW #9): Implementa o bloqueio real de negociações.
																								#     Antes, o alerta dizia "bloqueadas" mas nada era bloqueado.
																								#     Agora seta a flag acordo_silencio_ativo, que é checada em
																								#     _on_hud_solicitar_negociacao e _on_hud_solicitar_alianca. ---
																								acordo_silencio_ativo = true
																30:
																								_mostrar_alerta_meio_da_tela("VÁ PARA A PRISÃO!\nVocê foi detido por investigação fiscal.")
																								if OnlineTransport.is_host():
																																await get_tree().create_timer(1.5).timeout
																																OnlineTransport.send_all(self, &"_ir_para_prisao_rede", [jogador_atual_id], false, true)
																								return
																33:
																								# --- BUG FIX (LOW #14): Antes, o alerta dizia "Uma de suas
																								#     casas será destruída" MESMO se o jogador não tinha
																								#     construções. Agora checa antes e mostra mensagem apropriada. ---
																								var tem_constr = false
																								for id_chk in dados.get("propriedades_lista", []):
																																if tabuleiro.has(id_chk) and tabuleiro[id_chk].get("nivel", 0) > 0:
																																								tem_constr = true
																																								break
																								if tem_constr:
																																_mostrar_alerta_meio_da_tela("COLAPSO ESTRUTURAL!\nUma de suas casas será destruída.")
																																_destruir_casa_aleatoria(jogador_atual_id)
																								else:
																																_mostrar_alerta_meio_da_tela("COLAPSO ESTRUTURAL!\nSorte sua: não havia construções para destruir.")
																38:
																								mudanca_dinheiro = -100
																								_mostrar_alerta_meio_da_tela("IMPOSTO DE LUXO\nPague $100 ao banco.")

								if mudanca_dinheiro != 0:
																# --- CORREÇÃO CRÍTICA: Só o server envia o RPC de mudança de dinheiro.
																#     Antes, TODOS os peers chamavam _aplicar_mudanca_dinheiro_rede.rpc(),
																#     fazendo a função rodar N vezes por peer, debitando N vezes o valor. ---
																# --- BUG #7: Passa origem="casa_especial" para que a Imunidade do Breno
																#     NÃO dispare em casas especiais (só dispara em cartas/eventos). ---
																if OnlineTransport.is_host():
																								OnlineTransport.send_all(self, &"_aplicar_mudanca_dinheiro_rede", [jogador_atual_id, mudanca_dinheiro, "casa_especial"], false, true)
								
								# --- CORREÇÃO CRÍTICA: _finalizar_pouso_e_passar_turno deve ser
								#     chamado em TODOS os peers, não só no server. Se o jogador
								#     tirou dupla, _finalizar_pouso_e_passar_turno precisa rodar
								#     em todos os peers para mostrar os dados novamente.
								#     Antes, só o server chamava — o client travava sem dados.
								#     O guard `if OnlineTransport.is_host()` dentro de _finalizar_pouso_e_passar_turno
								#     já garante que só o server passa o turno. ---
								await get_tree().create_timer(2.0).timeout
								_finalizar_pouso_e_passar_turno()


@rpc("any_peer", "call_local")
func _ir_para_prisao_rede(id_jogador: String):
	if not pinos_jogadores.has(id_jogador) or not dados_economia_jogadores.has(id_jogador):
		return
	var pino = pinos_jogadores[id_jogador]
	var dados_jogador: Dictionary = dados_economia_jogadores[id_jogador]

	_remover_pino_da_casa(pino, pino.casa_atual)
	pino.casa_atual = 10
	pino.position = tabuleiro[10]["pos"]
	_adicionar_pino_na_casa(pino, 10)

	# Ir para a prisão cancela qualquer nova rolagem por dupla.
	_dupla_pendente = false
	dados_jogador["duplas_consecutivas"] = 0
	dados_jogador["turnos_preso"] = 0

	# A carta é consumida automaticamente na próxima prisão. O jogador é
	# levado à casa 10, mas não fica preso e não paga fiança.
	var cartas_disponiveis: int = int(dados_jogador.get("cartas_sair_prisao", 0))
	if cartas_disponiveis > 0:
		dados_jogador["cartas_sair_prisao"] = cartas_disponiveis - 1
		dados_jogador["preso"] = false
		pino.desativar_barras_prisao()
		pino.mostrar_texto_flutuante("CARTA USADA! VOCÊ ESTÁ LIVRE!", Color(1.0, 0.84, 0.38))
		var nome_jogador: String = str(dados_jogador.get("nome", id_jogador))
		_registrar_acao(
			"prisao",
			"%s usou automaticamente uma carta e não ficou preso." % nome_jogador,
			id_jogador
		)
		_atualizar_hud_ciclo_turno()
		if OnlineTransport.is_host():
			_finalizar_pouso_e_passar_turno()
		return

	dados_jogador["preso"] = true
	pino.ativar_barras_prisao()
	pino.tremer(4.0, 0.4)
	_atualizar_hud_ciclo_turno()

	if OnlineTransport.is_host():
		_finalizar_pouso_e_passar_turno()

# --- CORREÇÃO CRÍTICA DO BUG DAS BARRAS DE PRISÃO EM MULTIPLAYER:
#     Quando um jogador é liberado da prisão por tirar DUPLA ou após 3 turnos
#     (pagando $50), a lógica de liberação estava dentro de _on_dados_rolados_recebidos
#     que roda APENAS no peer que clicou em "Girar". Os outros peers nunca recebiam
#     a chamada desativar_barras_prisao() — as barras ficavam presas na visão dos
#     outros jogadores mesmo depois do jogador ser liberado.
#     Este RPC roda em TODOS os peers (call_local), garantindo que:
#     1) O estado "preso" seja atualizado em todos os peers.
#     2) As barras visuais sejam removidas em todos os peers.
#     A fiança e a carta usam o fluxo autoritativo de
#     _aplicar_resultado_fianca_rede, que também sincroniza todos os peers. ---

@rpc("any_peer", "call_local")
func _continuar_preso_passar_turno_rede():
								if OnlineTransport.is_host():
																_resolucao_turno_em_andamento = true
																await get_tree().create_timer(1.5).timeout
																_processar_passagem_de_turno()


func _proximo_jogador_ativo(id_jogador: String) -> String:
	if lista_turnos.is_empty():
		return ""
	var inicio = lista_turnos.find(id_jogador)
	if inicio < 0:
		inicio = 0
	for deslocamento in range(1, lista_turnos.size() + 1):
		var candidato = lista_turnos[(inicio + deslocamento) % lista_turnos.size()]
		if candidato != id_jogador and not dados_economia_jogadores.get(candidato, {}).get("falido", false):
			return candidato
	return ""


func _finalizar_pouso_e_passar_turno():
								# --- NOVO (GDD §5.2): Se o jogador tirou dupla, não passa o turno.
								#     Em vez disso, permite que ele role novamente. ---
								if _dupla_pendente:
																_dupla_pendente = false
																_processando_dados = false
																_verificar_permissao_de_clique()
																if pinos_jogadores.has(jogador_atual_id):
																								pinos_jogadores[jogador_atual_id].mostrar_texto_flutuante("DUPLA! ROLE NOVAMENTE!", Color(0.4, 1.0, 0.4))
																return
								if OnlineTransport.is_host():
																_processar_passagem_de_turno()

# --- NOVO (GDD §5.2): RPC para sincronizar o status de dupla entre todos os peers.
#     _on_dados_rolados_recebidos roda localmente; este RPC propaga o status
#     para que _finalizar_pouso_e_passar_turno (que roda em todos os peers via
#     _sincronizar_movimento_na_rede) possa tomar a decisão correta. ---

func _executar_portal_atalho(casa_id: int):
								# --- NOVO (Cartas): Bloqueio de Tráfego — portais bloqueados ---
								if not _efeitos_ativos_por_tipo("bloqueio_portal").is_empty():
												if pinos_jogadores.has(jogador_atual_id):
																pinos_jogadores[jogador_atual_id].mostrar_texto_flutuante("TRÁFEGO BLOQUEADO!", Color(0.9, 0.5, 0.2))
												_finalizar_pouso_e_passar_turno()
												return
								var destino = 28 if casa_id == 12 else 12
								var pino = pinos_jogadores[jogador_atual_id]

								# --- CORREÇÃO: Teleporte INSTANTÂNEO em vez de pular 16 casas ---
								# Remove o pino da casa atual
								_remover_pino_da_casa(pino, pino.casa_atual)

								# Animação: pino "entra" no portal (encolhe e some)
								var tween_entra = pino.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
								tween_entra.parallel().tween_property(pino.visual_node, "scale", Vector2(0.1, 0.1), 0.3)
								tween_entra.parallel().tween_property(pino, "modulate:a", 0.0, 0.3)

								# Efeito visual no portal de origem
								var pos_origem = tabuleiro[casa_id].get("pos", Vector2.ZERO)
								Animacoes.explosao_particulas(self, pos_origem, Color(0.1, 0.8, 0.9), 12, 60)

								# Texto flutuante explicando o teleporte
								pino.mostrar_texto_flutuante("PORTAL! " + str(casa_id) + " → " + str(destino), Color(0.1, 0.8, 0.9))

								await tween_entra.finished

								# Teleporta instantaneamente para o destino
								pino.casa_atual = destino
								pino.position = tabuleiro[destino]["pos"]
								_adicionar_pino_na_casa(pino, destino)

								# Efeito visual no portal de destino
								var pos_destino = tabuleiro[destino].get("pos", Vector2.ZERO)
								Animacoes.explosao_particulas(self, pos_destino, Color(0.1, 0.8, 0.9), 12, 60)

								# Animação: pino "sai" do portal (expandir e aparecer)
								pino.visual_node.scale = Vector2(0.1, 0.1)
								pino.modulate.a = 0.0
								var tween_sai = pino.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
								tween_sai.parallel().tween_property(pino.visual_node, "scale", Vector2(1.0, 1.0), 0.4)
								tween_sai.parallel().tween_property(pino, "modulate:a", 1.0, 0.3)

								await tween_sai.finished

								var meu_personagem_local = Global.escolhas_da_mesa.get(Global.meu_peer_id, "")
								if jogador_atual_id == meu_personagem_local:
																await focar_na_casa(destino)

								_finalizar_pouso_e_passar_turno()

# ============================================================================
# LÓGICA MULTIPLAYER DE MOVIMENTO E TURNOS
# ============================================================================

func _processar_passagem_de_turno():
								if OnlineTransport.is_host():
																_resolucao_turno_em_andamento = true
								# A Fase de Evento precisa terminar antes que o turno avance.
								if _acoes_bloqueadas_por_evento():
																return
								# --- CORREÇÃO CRÍTICA: Se há leilão de falência em andamento (ou agendado),
								#     NÃO passa o turno. O leilão de falência chama _verificar_vitoria() ou
								#     _verificar_permissao_de_clique() quando termina.
								#     Antes, o turno era avançado durante o leilão de falência, fazendo:
								#     1) O índice do turno avançar 2x (uma pelo _pagar_aluguel_rede que
								#        disparou a falência, outra pelo próprio leilão) — pulando o
								#        próximo jogador.
								#     2) Os dados aparecerem para o jogador errado, ou em alguns casos
								#        travarem completamente (dados não aparecem mais para ninguém).
								#     Isso explica o bug onde, após um jogador falir, os dados sumiam
								#     para os jogadores restantes algumas rodadas depois. ---
								if _leilao_falencia_ativo:
																return
								await get_tree().create_timer(1.5).timeout
								# Checa novamente após o await (o leilão pode ter iniciado durante a espera)
								if _leilao_falencia_ativo:
																return
								OnlineTransport.send_all(self, &"_avancar_turno_rede", [], true, true)


@rpc("authority", "call_local")
func _avancar_turno_rede():
								# Segurança: nenhum RPC ou atalho pode avançar a rodada durante a votação.
								if _acoes_bloqueadas_por_evento():
																return
								indice_turno_atual = (indice_turno_atual + 1) % lista_turnos.size()
								jogador_atual_id = lista_turnos[indice_turno_atual]
								_contador_turnos_globais += 1
								_processar_promessas_ao_avancar_turno()
								_atualizar_alvo_camera_espectador()

								# Atualiza o relógio central antes de iniciar as ações do novo jogador.
								_decrementar_efeitos_temporarios()
								_processar_efeitos_periodicos_do_turno(jogador_atual_id)

								# --- BUG FIX (LOW #9): Reset do Acordo de Silêncio a cada novo turno.
								#     A flag acordo_silencio_ativo é setada quando alguém cai na casa 22
								#     e deve durar apenas aquele turno. Como _avancar_turno_rede é
								#     chamado quando o turno passa, resetamos aqui. ---
								acordo_silencio_ativo = false
								# Zona de Obras bloqueia somente o jogador que caiu nela, até esta troca.
								turno_construcao_bloqueada = false
								# --- NOVO (Ilha de Calor): Decrementa interdição ---
								if _ilha_calor_interditacao_turnos > 0:
												_ilha_calor_interditacao_turnos -= 1
												if _ilha_calor_interditacao_turnos <= 0:
																_ilha_calor_prop_interditada = -1
								# --- NOVO (Escândalo de Corrupção): Decrementa embargo ---
								if _corrupcao_embargo_turnos > 0:
												_corrupcao_embargo_turnos -= 1
												if _corrupcao_embargo_turnos <= 0:
																_corrupcao_props_embargadas.clear()
								# --- NOVO (Cartas): Decrementa efeitos temporários ---
								if _carta_valorizacao_turnos > 0:
												_carta_valorizacao_turnos -= 1
												if _carta_valorizacao_turnos <= 0:
																_carta_valorizacao_casa = -1
								if _carta_embargo_judicial_turnos > 0:
												_carta_embargo_judicial_turnos -= 1
												if _carta_embargo_judicial_turnos <= 0:
																_carta_embargo_judicial_casa = -1
								if _carta_parque_turnos > 0:
												_carta_parque_turnos -= 1
												if _carta_parque_turnos <= 0:
																_carta_parque_casa = -1
								if _carta_bloqueio_trafego:
												_carta_bloqueio_trafego = false
								if _carta_premio_turnos > 0:
												_carta_premio_turnos -= 1
												if _carta_premio_turnos <= 0:
																_carta_premio_casa = -1
								if _carta_acao_coletiva_ativa:
												_carta_acao_coletiva_ativa = false
								# --- NOVO (Protestos): Decrementa bloqueio de hotel ---
								if _protestos_bloqueio_turnos > 0:
												_protestos_bloqueio_turnos -= 1
												if _protestos_bloqueio_turnos <= 0:
																_protestos_bloqueio_hotel = false

								# --- NOVO (GDD §5.2): Reset duplas_consecutivas do novo jogador
								#     (cada turno começa com contador zerado — só acumula dentro
								#     do mesmo turno quando o jogador tira dupla e rola novamente). ---
								var dados_novo = dados_economia_jogadores.get(jogador_atual_id)
								if dados_novo:
																dados_novo["duplas_consecutivas"] = 0
								# --- BUG FIX (HIGH #19 + MED #27/#28):
								#     HIGH #19: Antes, a recarga de habilidade era decrementada
								#     APENAS para o novo jogador atual. Resultado: "recarga 4 turnos"
								#     significava 4 voltas completas do jogador (até 24 turnos reais
								#     em partida de 6). Agora decrementa a recarga de TODOS os
								#     jogadores a cada turno — "4 turnos" = 4 turnos reais.
								#     MED #27/#28: hud.habilidade_pronta_aviso() era chamado em
								#     TODOS os peers (porque _avancar_turno_rede é call_local).
								#     Agora só pulsa o botão no peer do jogador cuja habilidade
								#     ficou pronta. ---
								for jid_recarga in lista_turnos:
																var dados_rec = dados_economia_jogadores.get(jid_recarga)
																if dados_rec and dados_rec.get("recarga_hab", 0) > 0:
																								dados_rec["recarga_hab"] -= 1
																								if dados_rec["recarga_hab"] == 0:
																																if pinos_jogadores.has(jid_recarga):
																																								pinos_jogadores[jid_recarga].mostrar_texto_flutuante("HABILIDADE PRONTA!", Color(0.4, 1.0, 0.4))
																																# Só pulsa o botão de habilidade no peer do jogador local
																																if jid_recarga == Global.escolhas_da_mesa.get(Global.meu_peer_id, ""):
																																								hud.habilidade_pronta_aviso()
								# Decrementa Breno's Decreto Emergencial (do novo jogador atual)
								if dados_novo and dados_novo.get("decreto_turnos", 0) > 0:
																dados_novo["decreto_turnos"] -= 1
																if dados_novo["decreto_turnos"] == 0:
																								dados_novo.erase("decreto_grupo")
								# Decrementa Igor's Especulação (do novo jogador atual)
								if dados_novo and dados_novo.get("especulacao_turnos", 0) > 0:
																dados_novo["especulacao_turnos"] -= 1
																if dados_novo["especulacao_turnos"] == 0:
																								dados_novo.erase("especulacao_casa")

								# --- NOVO (Fase 2 — Imunidades): decrementa turnos_restantes de
								#     TODAS as imunidades de TODOS os jogadores. Isso garante que
								#     "imunidade expira por turnos" funcione independentemente de
								#     quem é o jogador atual. Após decrementar, remove imunidades
								#     expiradas (turnos_restantes == 0).
								#     OBS: visitas_restantes só é decrementado quando a imunidade
								#     é realmente usada em _pagar_aluguel_rede; aqui só cuidamos
								#     do prazo por turnos. ---
								for jid in lista_turnos:
																var imunidades = dados_economia_jogadores[jid].get("imunidades", [])
																if imunidades.is_empty():
																								continue
																# Decrementa turnos_restantes de cada imunidade
																for imun in imunidades:
																								if imun.get("turnos_restantes", 0) > 0:
																																imun["turnos_restantes"] = imun["turnos_restantes"] - 1
																# Remove as que expiraram por turnos (e também por visitas,
																# caso visitas_restantes tenha chegado a 0 em _pagar_aluguel_rede
																# mas a entrada ainda não foi removida — cenário raro)
																var imunidades_validas: Array = []
																for imun in imunidades:
																								if imun.get("turnos_restantes", 0) > 0 and imun.get("visitas_restantes", 0) > 0:
																																imunidades_validas.append(imun)
																								else:
																																# Feedback visual de expiração (só se o jogador afetado for o local)
																																if jid == Global.escolhas_da_mesa.get(Global.meu_peer_id, "") and pinos_jogadores.has(jid):
																																								pinos_jogadores[jid].mostrar_texto_flutuante("IMUNIDADE EXPIROU", Color(0.8, 0.6, 0.3))
																dados_economia_jogadores[jid]["imunidades"] = imunidades_validas

								# --- NOVO (Fase 3 — Alianças): decrementa turnos_restantes de
								#     TODAS as alianças de TODOS os jogadores. Mesma lógica das
								#     imunidades: roda para todos os jogadores independentemente
								#     de quem é o jogador atual, pois alianças expiram por turnos
								#     globais. Remove as que expiraram (turnos_restantes == 0). ---
								for jid_al in lista_turnos:
																var aliancas = dados_economia_jogadores[jid_al].get("aliancas", [])
																if aliancas.is_empty():
																								continue
																# Decrementa turnos_restantes de cada aliança
																for alianca in aliancas:
																								if alianca.get("turnos_restantes", 0) > 0:
																																alianca["turnos_restantes"] = alianca["turnos_restantes"] - 1
																# Remove as que expiraram
																var aliancas_validas: Array = []
																for alianca in aliancas:
																								if alianca.get("turnos_restantes", 0) > 0:
																																aliancas_validas.append(alianca)
																								else:
																																# Feedback visual de expiração (só se o jogador afetado for o local)
																																if jid_al == Global.escolhas_da_mesa.get(Global.meu_peer_id, "") and pinos_jogadores.has(jid_al):
																																								pinos_jogadores[jid_al].mostrar_texto_flutuante("ALIANÇA EXPIROU", Color(0.8, 0.6, 0.3))
																dados_economia_jogadores[jid_al]["aliancas"] = aliancas_validas

								var igor_dados = dados_economia_jogadores.get("igor")
								if jogador_atual_id == "igor" and igor_dados and igor_dados.get("turnos_divida", 0) > 0:
																# --- BUG #12 FIX: Hedge Fund paga 25% do excedente ORIGINAL por
																#     turno, por 2 turnos (50% total). O restante é PERDOADO.
																#     Antes, pagava excedente/2 por turno = 100% total. ---
																var divida_orig = int(igor_dados.get("divida_original", igor_dados["divida_ativa"]))
																var parcela = int(divida_orig * 0.25)
																# --- BUG FIX (MED #11): Antes, no último turno (turnos_divida == 1),
																#     pagava 50% da divida_ativa — que já havia sido reduzida pela
																#     parcela do turno anterior. Resultado: Igor pagava ~62% do
																#     excedente em vez de 50%. Agora SEMPRE paga 25% do divida_original
																#     (constante), e no último turno perdoa o restante. ---
																var credor = igor_dados["credor_divida"]

																_registrar_obrigacao_falencia("igor", str(credor), parcela)
																igor_dados["dinheiro"] -= parcela
																if dados_economia_jogadores.has(credor):
																								dados_economia_jogadores[credor]["dinheiro"] += parcela

																if pinos_jogadores.has("igor"): pinos_jogadores["igor"].mostrar_texto_flutuante("-$" + str(parcela) + " (Dívida Hedge)", Color(0.9, 0.5, 0.3))
																if pinos_jogadores.has(credor): pinos_jogadores[credor].mostrar_texto_flutuante("+$" + str(parcela) + " (Dívida Hedge)", Color(0.5, 0.9, 0.3))

																igor_dados["divida_ativa"] -= parcela
																igor_dados["turnos_divida"] -= 1
																# Quando os 2 turnos acabam, o restante da dívida é PERDOADO
																# (Hedge Fund perdoa 50% do excedente conforme GDD).
																if igor_dados["turnos_divida"] <= 0:
																								if igor_dados["divida_ativa"] > 0 and pinos_jogadores.has("igor"):
																																pinos_jogadores["igor"].mostrar_texto_flutuante("HEDGE: DÍVIDA RESTANTE PERDOADA", Color(0.3, 0.9, 0.3))
																								igor_dados["divida_ativa"] = 0
																								igor_dados["divida_original"] = 0
																								igor_dados["credor_divida"] = ""
																# --- CORREÇÃO: A parcela da dívida pode deixar o Igor
																#     negativo, disparando o sistema de salvamento/falência. ---
																_verificar_falencia("igor", str(credor))

								if indice_turno_atual == 0:
																rodada_atual += 1
																hud.atualizar_round_counter(rodada_atual)
																
																# GDD: no início de cada rodada, recalcula o tráfego previsto
																# usando as posições atuais e os próximos dois movimentos.
																_gerar_tendencias_yasmin()
																
																if OnlineTransport.is_host() and not Global.modo_tutorial:
																								if rodada_atual % 3 == 0:
																																_sortear_evento_global()
																																# --- NOVO (Fonte Anônima da Diana): pré-sortei o PRÓXIMO evento
																																#     global após revelar o atual. Diana pode ver essa info. ---
																																_pre_sortear_proximo_evento()
																								elif rodada_atual % 3 == 1:
																																OnlineTransport.send_all(self, &"_aplicar_evento_global", ["MERCADO ESTÁVEL", "estavel", "A cidade respira temporariamente.\n\nEFEITO:\nNenhuma crise ativa. Aluguéis operam com valores base normais."], true, true)
																																# Mesmo em rodada estável, pré-sortei o próximo evento
																																_pre_sortear_proximo_evento()

								# Reavalia a vitória também no fim de cada turno. Isso cobre o caso
								# em que o último sobrevivente só depois recupera saldo e compra sua
								# primeira propriedade.
								_verificar_vitoria()
								if _partida_encerrada:
																return
								_atualizar_hud_ciclo_turno()
								_emitir_evento_tutorial(
																"turno_iniciado",
																{"jogador_id": jogador_atual_id, "rodada": rodada_atual}
								)
								_verificar_permissao_de_clique()


@rpc("authority", "call_local")
func _mudar_turno_no_servidor():
								await get_tree().create_timer(1.0).timeout
								_avancar_turno()

# ============================================================================
# REGRAS DE MONOPÓLIO E CONSTRUÇÃO
# ============================================================================

# --- BUG #17 FIX: Função genérica que verifica se um jogador é imune a
#     confisco de propriedades. Atualmente, apenas o Kofi tem essa imunidade
#     (habilidade passiva Raízes). Centralizar em uma função permite estender
#     facilmente para outros personagens no futuro. ---

func _jogador_possui_grupo(jogador_id: String, grupos: Array) -> bool:
	for cid in registro_propriedades.keys():
		if registro_propriedades[cid] == jogador_id and grupos.has(tabuleiro[cid].get("grupo", "")):
			return true
	return false


func _jogador_possui_nome(jogador_id: String, trecho_nome: String) -> bool:
	for cid in registro_propriedades.keys():
		if registro_propriedades[cid] == jogador_id and str(tabuleiro[cid].get("nome", "")).find(trecho_nome) >= 0:
			return true
	return false


func _probabilidade_trafego_jogador_1_turno(posicao_inicial: int, casa_alvo: int) -> float:
	var probabilidade = 0.0
	for soma_variant in DISTRIBUICAO_2D6.keys():
		var soma = int(soma_variant)
		var destino = _posicao_final_para_relatorio(posicao_inicial + soma)
		if destino == casa_alvo:
			probabilidade += float(DISTRIBUICAO_2D6[soma_variant])
	return clampf(probabilidade, 0.0, 1.0)


func _proximos_jogadores_do_relatorio(quantidade: int = 2) -> Array:
	var resultado: Array = []
	if lista_turnos.is_empty() or quantidade <= 0:
		return resultado
	var inicio = clampi(indice_turno_atual, 0, lista_turnos.size() - 1)
	var limite = lista_turnos.size() * 2
	for deslocamento in range(limite):
		var indice = (inicio + deslocamento) % lista_turnos.size()
		var pid = str(lista_turnos[indice])
		if not dados_economia_jogadores.has(pid):
			continue
		if dados_economia_jogadores[pid].get("falido", false):
			continue
		resultado.append(pid)
		if resultado.size() >= quantidade:
			break
	return resultado


func _garantir_meta_jogador(jogador_id: String) -> void:
	if not dados_economia_jogadores.has(jogador_id):
		return
	var dados = dados_economia_jogadores[jogador_id]
	if not dados.has("reputacao"):
		dados["reputacao"] = REPUTACAO_INICIAL
	if not dados.has("xp_partida"):
		dados["xp_partida"] = 0
	if not dados.has("recompensas_xp"):
		dados["recompensas_xp"] = []
	if not dados.has("chaves_xp_recebidas"):
		dados["chaves_xp_recebidas"] = []
	if not dados.has("promessas_cumpridas"):
		dados["promessas_cumpridas"] = 0
	if not dados.has("promessas_quebradas"):
		dados["promessas_quebradas"] = 0
	if not dados.has("acordos_5_turnos"):
		dados["acordos_5_turnos"] = 0
	if not dados.has("habilidades_usadas"):
		dados["habilidades_usadas"] = 0
	if not dados.has("monopolios_premiados"):
		dados["monopolios_premiados"] = []
	if not dados.has("eventos_sem_perder_construcao"):
		dados["eventos_sem_perder_construcao"] = 0
	if not dados.has("bonus_eventos_seguros"):
		dados["bonus_eventos_seguros"] = 0
	if not dados.has("eliminacoes"):
		dados["eliminacoes"] = 0
	if not dados.has("eliminacoes_creditadas"):
		dados["eliminacoes_creditadas"] = []


func obter_dados_espectador() -> Dictionary:
	var previsao = _calcular_previsao_vitoria()
	var jogadores: Array = []
	for jogador_id in ordem_original_partida:
		var item: Dictionary
		if dados_economia_jogadores.get(jogador_id, {}).get("falido", false) and _snapshots_finais.has(jogador_id):
			item = _snapshots_finais[jogador_id].duplicate(true)
			item["falido"] = true
			item["snapshot_falencia"] = true
		else:
			item = _snapshot_atual_jogador(jogador_id)
		item["previsao_vitoria"] = float(previsao.get(jogador_id, 0.0))
		item["em_turno"] = jogador_id == jogador_atual_id
		jogadores.append(item)
	return {
		"jogadores": jogadores,
		"historico": _historico_acoes.duplicate(true),
		"eventos_ativos": _eventos_ativos_para_espectador(),
		"promessas": _promessas_globais.duplicate(true),
		"evento_atual": evento_ativo,
		"rodada": rodada_atual,
		"turno_global": _contador_turnos_globais,
		"jogador_atual_id": jogador_atual_id,
		"auto_seguir": espectador_auto_seguir,
		"alvo_seguido": espectador_alvo_id,
	}


func focar_na_casa(id_casa: int):
								if not camera: return
								var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
								tween.tween_property(camera, "position", tabuleiro[id_casa]["pos"], 0.8)
								tween.parallel().tween_property(camera, "zoom", Vector2(1.2, 1.2), 0.8)


func _get_tamanho_casa(id: int) -> Vector2:
								var escala = tabuleiro[id].get("escala", 1.0)
								return TAMANHO_UNICO * escala


func spawnar_pino(id_jogador: String, cor_do_grupo: Color):
								var instancia = pino_cena.instantiate()
								add_child(instancia)
								
								if not instancia.has_method("configurar"):
																var script_pino = load("res://scenes/gameplay/tabuleiro/pino_personagem.gd")
																instancia.set_script(script_pino)
																instancia._ready()
																
								instancia.configurar(cor_do_grupo, id_jogador)
								
								if tabuleiro.has(0):
																instancia.position = tabuleiro[0]["pos"]
																instancia.casa_atual = 0
																_adicionar_pino_na_casa(instancia, 0)
								
								pinos_jogadores[id_jogador] = instancia


func _desenhar_casa(id: int):
	var dados = tabuleiro[id]
	var escala = dados.get("escala", 1.0)
	var tamanho = _get_tamanho_casa(id)
	var eh_tile_construcao = dados.get("tipo", "") == "propriedade"
	var cor_bairro: Color = cores_grupos.get(str(dados.get("grupo", "")), Color(0.72, 0.69, 0.62))

	var node = Node2D.new()
	node.position = dados["pos"]
	node.name = "Casa_" + str(id)
	node.z_index = 10

	if eh_tile_construcao:
		var tile_base = TextureRect.new()
		tile_base.name = "TileBase"
		tile_base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tile_base.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tile_base.size = tamanho * ESCALA_TILE_CONSTRUCAO
		tile_base.position = Vector2(-tile_base.size.x / 2.0, -tile_base.size.y / 2.0)
		tile_base.z_index = 0
		if ResourceLoader.exists(CAMINHO_TILE_CONSTRUCAO):
			var tex_tile = load(CAMINHO_TILE_CONSTRUCAO)
			if tex_tile:
				tile_base.texture = tex_tile
		else:
			var fallback_bg = ColorRect.new()
			fallback_bg.size = tamanho + Vector2(16, 16)
			fallback_bg.position = Vector2(-fallback_bg.size.x / 2.0, -fallback_bg.size.y / 2.0)
			fallback_bg.color = cor_bairro
			node.add_child(fallback_bg)
		node.add_child(tile_base)

		# A moldura identifica visualmente o bairro sem substituir a arte do chão.
		var borda_grupo = ReferenceRect.new()
		borda_grupo.name = "BordaGrupo"
		borda_grupo.size = tamanho + Vector2(12, 12)
		borda_grupo.position = Vector2(-borda_grupo.size.x / 2.0, -borda_grupo.size.y / 2.0)
		borda_grupo.editor_only = false
		borda_grupo.border_color = cor_bairro
		borda_grupo.border_width = 10.0 * escala
		borda_grupo.z_index = 2
		node.add_child(borda_grupo)

		var sombra = ColorRect.new()
		sombra.name = "SombraConstrucao"
		sombra.size = Vector2(tamanho.x * 0.48, tamanho.y * 0.10)
		sombra.position = Vector2(-sombra.size.x / 2.0, tamanho.y * 0.08)
		sombra.color = Color(0.0, 0.0, 0.0, 0.18)
		sombra.z_index = 1
		node.add_child(sombra)

		var container_construcao = Node2D.new()
		container_construcao.name = "ContainerConstrucao"
		container_construcao.z_index = 5
		node.add_child(container_construcao)

		var sprite_construcao = TextureRect.new()
		sprite_construcao.name = "SpriteConstrucao"
		sprite_construcao.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite_construcao.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite_construcao.size = Vector2(
			tamanho.x * ESCALA_LARGURA_SPRITE_CONSTRUCAO,
			tamanho.y * ESCALA_ALTURA_SPRITE_CONSTRUCAO
		)
		sprite_construcao.position = Vector2(
			-sprite_construcao.size.x / 2.0,
			tamanho.y * ANCORA_BASE_Y_SPRITE_CONSTRUCAO - sprite_construcao.size.y
		)
		sprite_construcao.z_index = 0
		container_construcao.add_child(sprite_construcao)
	else:
		var bg = ColorRect.new()
		bg.size = tamanho + Vector2(16, 16)
		bg.position = Vector2(-bg.size.x / 2, -bg.size.y / 2)
		bg.color = cor_bairro
		node.add_child(bg)

		var caminho_imagem = ""
		var img_especial = dados.get("imagem", "default.png")
		caminho_imagem = "res://assets/textures/casas/" + img_especial
		if ResourceLoader.exists(caminho_imagem):
			var tex = load(caminho_imagem)
			if tex:
				var tex_rect = TextureRect.new()
				tex_rect.texture = tex
				tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tex_rect.size = tamanho
				tex_rect.position = Vector2(-tamanho.x / 2, -tamanho.y / 2)
				node.add_child(tex_rect)

		var borda = ReferenceRect.new()
		borda.size = tamanho
		borda.position = Vector2(-tamanho.x / 2, -tamanho.y / 2)
		borda.editor_only = false
		borda.border_color = Color(1, 1, 1, 0.4)
		borda.border_width = 5.0 * escala
		node.add_child(borda)

	var faixa_dono = ColorRect.new()
	faixa_dono.size = Vector2(tamanho.x, 25 * escala)
	faixa_dono.position = Vector2(-tamanho.x / 2, (tamanho.y / 2) - faixa_dono.size.y)
	faixa_dono.name = "FaixaDono"
	faixa_dono.visible = false
	faixa_dono.z_index = 18 if eh_tile_construcao else 2
	node.add_child(faixa_dono)

	var label = Label.new()
	label.text = dados["nome"]
	label.custom_minimum_size = Vector2(tamanho.x - 16, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	if fonte_pixel:
		label.add_theme_font_override("font", fonte_pixel)
	if eh_tile_construcao:
		label.size = Vector2(tamanho.x - 20.0, 54.0 * escala)
		label.position = Vector2(-label.size.x / 2.0, -tamanho.y / 2.0 - 8.0 * escala)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", int(28 * escala))
		label.add_theme_color_override("font_color", Color.WHITE)
		label.z_index = 25
	else:
		label.position = Vector2(-tamanho.x / 2 + 8, -tamanho.y / 2 + 12)
		label.add_theme_font_size_override("font_size", int(44 * escala))
	node.add_child(label)

	var camada = get_node_or_null("Camada_02_Predios")
	if not camada:
		camada = Node2D.new()
		camada.name = "Camada_02_Predios"
		camada.z_index = 10
		add_child(camada)
	camada.add_child(node)
	if eh_tile_construcao:
		_atualizar_imagem_construcao(id)


func _adicionar_pino_na_casa(pino: PinoPersonagem, casa_id: int) -> void:
	if pino == null or not is_instance_valid(pino):
		return
	var casa_segura: int = clampi(casa_id, 0, 39)
	if not pinos_por_casa.has(casa_segura):
		pinos_por_casa[casa_segura] = []
	var pinos_variant: Variant = pinos_por_casa[casa_segura]
	if not pinos_variant is Array:
		pinos_por_casa[casa_segura] = []
	var pinos_casa: Array = pinos_por_casa[casa_segura]
	if not pinos_casa.has(pino):
		pinos_casa.append(pino)
	_reposicionar_pinos_na_casa(casa_segura)



func _remover_pino_da_casa(pino: PinoPersonagem, casa_id: int) -> void:
	var casa_segura: int = clampi(casa_id, 0, 39)
	if not pinos_por_casa.has(casa_segura):
		return
	var pinos_variant: Variant = pinos_por_casa[casa_segura]
	if not pinos_variant is Array:
		pinos_por_casa.erase(casa_segura)
		return
	var pinos_casa: Array = pinos_variant
	pinos_casa.erase(pino)
	_reposicionar_pinos_na_casa(casa_segura)



func _obter_posicao_casa_segura(casa_id: int) -> Vector2:
	var casa_segura: int = clampi(casa_id, 0, 39)
	if _garantir_layout_tabuleiro():
		var dados_casa: Dictionary = tabuleiro[casa_segura]
		var pos_variant: Variant = dados_casa.get("pos", Vector2.ZERO)
		if pos_variant is Vector2:
			return pos_variant

	# Último recurso: usa a posição do nó visual já desenhado. Isso evita que
	# uma inconsistência transitória do dicionário interrompa a sincronização.
	var casa_node: Node2D = get_node_or_null(
		"Camada_02_Predios/Casa_%d" % casa_segura
	) as Node2D
	if casa_node != null:
		return casa_node.position
	return Vector2.ZERO



func _reposicionar_pinos_na_casa(casa_id: int) -> void:
	var casa_segura: int = clampi(casa_id, 0, 39)
	if not pinos_por_casa.has(casa_segura):
		return
	var pinos_variant: Variant = pinos_por_casa[casa_segura]
	if not pinos_variant is Array:
		pinos_por_casa.erase(casa_segura)
		return

	var pinos_validos: Array[PinoPersonagem] = []
	for pino_variant in pinos_variant:
		var pino: PinoPersonagem = pino_variant as PinoPersonagem
		if pino == null or not is_instance_valid(pino):
			continue
		pinos_validos.append(pino)
	pinos_por_casa[casa_segura] = pinos_validos

	var total: int = pinos_validos.size()
	if total == 0:
		return

	var pos_casa: Vector2 = _obter_posicao_casa_segura(casa_segura)
	var escala: float = 1.0
	if tabuleiro.has(casa_segura) and tabuleiro[casa_segura] is Dictionary:
		var dados_casa: Dictionary = tabuleiro[casa_segura]
		escala = float(dados_casa.get("escala", 1.0))
	var raio: float = 50.0 * escala

	if total == 1:
		pinos_validos[0].aplicar_offset(Vector2.ZERO, pos_casa)
		return

	for indice in range(total):
		var angulo: float = (2.0 * PI * float(indice)) / float(total)
		var offset: Vector2 = Vector2(cos(angulo), sin(angulo)) * raio
		pinos_validos[indice].aplicar_offset(offset, pos_casa)



func _grupo_zoneamento_permite_hotel_com_3_casas(grupo: String) -> bool:
	return _tem_efeito_temporario("zoneamento_" + grupo.to_lower().replace("-", "_"))


func _destruir_casa_aleatoria(jogador_id: String):
								# Encontra propriedades do jogador com nível > 0
								var candidatas = []
								for id in tabuleiro.keys():
																if registro_propriedades.has(id) and registro_propriedades[id] == jogador_id:
																								if tabuleiro[id].get("nivel", 0) > 0:
																																candidatas.append(id)
								if candidatas.is_empty():
																if pinos_jogadores.has(jogador_id):
																								pinos_jogadores[jogador_id].mostrar_texto_flutuante("SEM CASAS PARA DESTRUIR", Color(0.8, 0.6, 0.2))
																return
								var id_destruir = candidatas.pick_random()
								tabuleiro[id_destruir]["nivel"] -= 1
								_atualizar_imagem_construcao(id_destruir)
								if pinos_jogadores.has(jogador_id):
																pinos_jogadores[jogador_id].mostrar_texto_flutuante("CASA DESTRUÍDA!", Color(0.9, 0.3, 0.3))
																pinos_jogadores[jogador_id].tremer(5.0, 0.4)
								var pos_casa = tabuleiro[id_destruir].get("pos", Vector2.ZERO)
								Animacoes.explosao_particulas(self, pos_casa, Color(0.9, 0.3, 0.2), 14, 60)


func _contar_hoteis_do_jogador(jogador_id: String) -> int:
								var count = 0
								for id in tabuleiro.keys():
																if registro_propriedades.has(id) and registro_propriedades[id] == jogador_id:
																								if tabuleiro[id].get("nivel", 0) == 5:
																																count += 1
								return count


func _on_hud_solicitar_fianca_prisao():
	if _acao_bloqueada_por_eleicao(true) or _acoes_bloqueadas_por_evento():
		if hud and hud.has_method("resolver_solicitacao_fianca"):
			hud.resolver_solicitacao_fianca(false, "Aguarde o evento atual terminar.")
		return

	var meu_personagem_local = str(Global.escolhas_da_mesa.get(Global.meu_peer_id, ""))
	if meu_personagem_local == "" or not dados_economia_jogadores.has(meu_personagem_local):
		if hud and hud.has_method("resolver_solicitacao_fianca"):
			hud.resolver_solicitacao_fianca(false, "Não foi possível identificar o jogador local.")
		return
	if jogador_atual_id != meu_personagem_local:
		if hud and hud.has_method("resolver_solicitacao_fianca"):
			hud.resolver_solicitacao_fianca(false, "Aguarde sua vez para pagar a fiança.")
		return
	if not dados_economia_jogadores[meu_personagem_local].get("preso", false):
		if hud and hud.has_method("resolver_solicitacao_fianca"):
			hud.resolver_solicitacao_fianca(false, "Você já está livre.")
		_verificar_permissao_de_clique()
		return

	# A cobrança e a libertação são decididas somente pelo servidor. O cliente
	# não envia o personagem no RPC: o servidor o identifica pelo peer remoto,
	# evitando pagar a fiança em nome de outro jogador ou duplicar a cobrança.
	if OnlineTransport.is_host():
		_servidor_processar_fianca(meu_personagem_local)
	else:
		OnlineTransport.send_host(self, &"_solicitar_fianca_prisao_servidor", [], false)


@rpc("any_peer", "call_remote", "reliable")
func _solicitar_fianca_prisao_servidor():
	if not OnlineTransport.is_host():
		return
	var peer_remetente = OnlineTransport.get_remote_sender_id()
	var jogador_id = _personagem_do_peer(peer_remetente)
	if jogador_id == "":
		OnlineTransport.send_player(peer_remetente, self, &"_notificar_falha_fianca_local", ["Não foi possível identificar seu personagem no servidor."], false, true)
		return
	_servidor_processar_fianca(jogador_id)


func _init_jogadores_ativos():
								jogadores_ativos = lista_turnos.duplicate()

# Conecta os novos sinais da HUD (chamado em _ready)

func _processar_promessas_ao_avancar_turno() -> void:
	var houve_mudanca = false
	var conclusoes: Array = []
	for promessa in _promessas_globais:
		if promessa.get("status", "ativa") != "ativa":
			continue
		var autor_id = str(promessa.get("autor_id", ""))
		if not dados_economia_jogadores.has(autor_id) or dados_economia_jogadores[autor_id].get("falido", false):
			promessa["status"] = "cancelada"
			promessa["cancelada"] = true
			promessa["turnos_restantes"] = 0
			promessa["turno_cancelamento"] = _contador_turnos_globais
			houve_mudanca = true
			continue
		promessa["turnos_restantes"] = maxi(0, int(promessa.get("turnos_restantes", PROMESSA_DURACAO_PADRAO)) - 1)
		houve_mudanca = true
		if int(promessa["turnos_restantes"]) > 0:
			continue
		promessa["status"] = "cumprida"
		promessa["cumprida"] = true
		promessa["cumprida_por_expiracao"] = true
		promessa["turno_conclusao"] = _contador_turnos_globais
		_garantir_meta_jogador(autor_id)
		var dados_autor = dados_economia_jogadores[autor_id]
		dados_autor["promessas_cumpridas"] = int(dados_autor.get("promessas_cumpridas", 0)) + 1
		dados_autor["acordos_5_turnos"] = int(dados_autor.get("acordos_5_turnos", 0)) + 1
		_conceder_xp_partida(autor_id, XP_ACORDO_CINCO_TURNOS, "acordo_" + str(promessa.get("id", "")), "Manteve um acordo por 5 turnos")
		_alterar_reputacao(autor_id, REPUTACAO_BONUS_CUMPRIDA, "acordo cumprido")
		var nome_autor = str(dados_autor.get("nome", autor_id))
		conclusoes.append(nome_autor)
	if not conclusoes.is_empty():
		var resumo = ", ".join(conclusoes.slice(0, 3))
		if conclusoes.size() > 3:
			resumo += " e mais %d" % (conclusoes.size() - 3)
		Animacoes.banner_cinematico(hud.get_node("Control"), "ACORDO CUMPRIDO", resumo + " manteve a palavra: +80 XP por acordo.", Color(0.4, 1.0, 0.5), 2.4)
	if houve_mudanca:
		_atualizar_hud_promessas()


func _cancelar_promessas_do_jogador(jogador_id: String) -> void:
	var mudou = false
	for promessa in _promessas_globais:
		if promessa.get("autor_id", "") == jogador_id and promessa.get("status", "ativa") == "ativa":
			promessa["status"] = "cancelada"
			promessa["cancelada"] = true
			promessa["turnos_restantes"] = 0
			promessa["turno_cancelamento"] = _contador_turnos_globais
			mudou = true
	if mudou:
		_atualizar_hud_promessas()
