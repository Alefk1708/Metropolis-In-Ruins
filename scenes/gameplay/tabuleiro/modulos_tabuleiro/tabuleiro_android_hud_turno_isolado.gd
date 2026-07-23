extends "res://scenes/gameplay/tabuleiro/modulos_tabuleiro/tabuleiro_android_hud_incremental.gd"

# ============================================================================
# ANDROID — TURNO ISOLADO DOS PAINÉIS PESADOS
# ============================================================================
#
# Refinamento da HUD incremental:
#
# 1. jogador_atual_id não participa mais da assinatura de dinheiro.
# 2. jogador_atual_id não participa mais da assinatura do menu de construção.
# 3. turno possui assinatura própria e atualiza somente nome do jogador atual,
#    permissões e câmera do espectador.
# 4. promessas usam _promessas_globais, que é a fonte real do painel.
# 5. dossiê da Diana é reconstruído diretamente, sem chamar a atualização geral.
# 6. relatório da Yasmin continua exclusivo do início da rodada.
#
# Uma troca de turno comum não percorre cards, não refaz o dossiê, não reescreve
# dinheiro e não alimenta o relatório.
# ============================================================================


var _android_hud_assinatura_turno_isolado: String = ""


func _atualizar_hud_ciclo_turno() -> void:
	if _android_hud_processando_super:
		return
	if hud == null or not is_instance_valid(hud):
		return

	var personagem_local: String = _android_hud_obter_personagem_local()
	if (
		personagem_local.is_empty()
		or not dados_economia_jogadores.has(personagem_local)
	):
		return

	if (
		not _android_hud_inicializada
		or personagem_local != _android_hud_personagem_local
	):
		_android_hud_executar_super_completo()
		_android_hud_capturar_assinaturas(personagem_local)
		_android_hud_assinatura_turno_isolado = (
			_android_hud_criar_assinatura_turno()
		)
		_android_hud_inicializada = true
		_android_hud_personagem_local = personagem_local
		return

	var assinatura_turno: String = (
		_android_hud_criar_assinatura_turno()
	)
	var assinatura_basica: String = (
		_android_hud_criar_assinatura_basica(personagem_local)
	)
	var assinatura_social: String = (
		_android_hud_criar_assinatura_social(personagem_local)
	)
	var assinatura_menu: String = (
		_android_hud_criar_assinatura_menu(personagem_local)
	)
	var assinatura_casa: String = (
		_android_hud_criar_assinatura_casa(personagem_local)
	)

	var algo_mudou: bool = false

	if (
		assinatura_turno
		!= _android_hud_assinatura_turno_isolado
	):
		_android_hud_atualizar_turno_isolado()
		_android_hud_assinatura_turno_isolado = assinatura_turno
		algo_mudou = true

	if assinatura_basica != _android_hud_assinatura_basica:
		_android_hud_atualizar_basico(personagem_local)
		_android_hud_assinatura_basica = assinatura_basica
		algo_mudou = true

	if assinatura_social != _android_hud_assinatura_social:
		_android_hud_atualizar_social(personagem_local)
		_android_hud_assinatura_social = assinatura_social
		algo_mudou = true

	if assinatura_menu != _android_hud_assinatura_menu:
		# Cards persistentes. Mudanças de saldo apenas reavaliam botões; a troca
		# de turno, sozinha, não entra mais nesta assinatura.
		_atualizar_menu_construcao()
		_android_hud_assinatura_menu = assinatura_menu
		algo_mudou = true

	if assinatura_casa != _android_hud_assinatura_casa:
		_atualizar_hud_minha_casa()
		_android_hud_assinatura_casa = assinatura_casa
		algo_mudou = true

	if personagem_local == "diana":
		var assinatura_dossie: String = (
			_android_hud_criar_assinatura_dossie()
		)
		if assinatura_dossie != _android_hud_assinatura_dossie:
			_android_hud_atualizar_dossie_diana()
			_android_hud_assinatura_dossie = assinatura_dossie
			algo_mudou = true

	# Permissões são deliberadamente leves e também precisam reagir a bloqueios
	# de eventos que podem mudar sem alterar os outros domínios.
	_android_hud_atualizar_permissoes()

	if algo_mudou:
		GerenciadorSalvamento.marcar_estado_alterado(self)


func _android_hud_criar_assinatura_turno() -> String:
	return "|".join(
		PackedStringArray(
			[
				str(jogador_atual_id),
				str(indice_turno_atual),
				str(rodada_atual),
				str(modo_espectador_local),
			]
		)
	)


func _android_hud_criar_assinatura_basica(
	personagem_local: String
) -> String:
	var dados: Dictionary = dados_economia_jogadores.get(
		personagem_local,
		{}
	)
	return "|".join(
		PackedStringArray(
			[
				personagem_local,
				str(dados.get("nome", personagem_local)),
				str(int(dados.get("dinheiro", 0))),
				str(
					int(
						dados.get(
							"propriedades_compradas",
							_android_hud_contar_propriedades(
								personagem_local
							)
						)
					)
				),
				str(int(dados.get("reputacao", REPUTACAO_INICIAL))),
				str(int(dados.get("xp_partida", 0))),
				str(int(dados.get("recarga_hab", 0))),
				str(int(dados.get("cartas_construcao_gratis", 0))),
				str(int(dados.get("cartas_sair_prisao", 0))),
				str(bool(dados.get("falido", false))),
			]
		)
	)


func _android_hud_criar_assinatura_social(
	personagem_local: String
) -> String:
	var dados: Dictionary = dados_economia_jogadores.get(
		personagem_local,
		{}
	)
	return "|".join(
		PackedStringArray(
			[
				str(dados.get("imunidades", [])),
				str(dados.get("aliancas", [])),
				str(_promessas_globais),
			]
		)
	)


func _android_hud_criar_assinatura_menu(
	personagem_local: String
) -> String:
	var dados_locais: Dictionary = dados_economia_jogadores.get(
		personagem_local,
		{}
	)

	# O saldo permanece porque altera SEM DINHEIRO/RESGATAR, mas o turno não.
	# Isso atualiza apenas os botões dos cards persistentes.
	var partes: PackedStringArray = PackedStringArray(
		[
			personagem_local,
			str(int(dados_locais.get("dinheiro", 0))),
			str(int(dados_locais.get("cartas_construcao_gratis", 0))),
			str(bool(dados_locais.get("mutirao_ativo", false))),
			str(evento_ativo),
			str(turno_construcao_bloqueada),
			str(_construcoes_visuais_em_andamento.size()),
		]
	)

	var ids: Array = registro_propriedades.keys()
	ids.sort()
	for id_variant: Variant in ids:
		var casa_id: int = int(id_variant)
		if (
			str(registro_propriedades.get(casa_id, ""))
			!= personagem_local
		):
			continue
		var dados_casa: Dictionary = tabuleiro.get(casa_id, {})
		partes.append(
			"%d:%d:%s:%s" % [
				casa_id,
				int(dados_casa.get("nivel", 0)),
				str(bool(dados_casa.get("hipotecada", false))),
				str(dados_casa.get("grupo", "")),
			]
		)
	return "|".join(partes)


func _android_hud_criar_assinatura_dossie() -> String:
	var partes: PackedStringArray = PackedStringArray(
		[
			str(_promessas_globais),
			str(proximo_evento_global),
			str(proximo_evento_descricao),
		]
	)

	for id_variant: Variant in lista_turnos:
		var jogador_id: String = str(id_variant)
		if not dados_economia_jogadores.has(jogador_id):
			continue
		var dados: Dictionary = dados_economia_jogadores[jogador_id]
		partes.append(
			"|".join(
				PackedStringArray(
					[
						jogador_id,
						str(dados.get("nome", jogador_id)),
						str(int(dados.get("dinheiro", 0))),
						str(
							int(
								dados.get(
									"propriedades_compradas",
									0
								)
							)
						),
						str(dados.get("imunidades", [])),
						str(dados.get("aliancas", [])),
						str(bool(dados.get("falido", false))),
						str(
							int(
								dados.get(
									"reputacao",
									REPUTACAO_INICIAL
								)
							)
						),
						str(int(dados.get("xp_partida", 0))),
						str(
							dados.get(
								"fonte_anonima_evento_previsto",
								""
							)
						),
					]
				)
			)
		)
	return "\n".join(partes)


func _android_hud_atualizar_basico(
	personagem_local: String
) -> void:
	var dados: Dictionary = dados_economia_jogadores.get(
		personagem_local,
		{}
	)
	var nome: String = str(
		dados.get(
			"nome",
			personagem_local.capitalize()
		)
	)
	var dinheiro: int = int(dados.get("dinheiro", 0))
	var propriedades: int = int(
		dados.get(
			"propriedades_compradas",
			_android_hud_contar_propriedades(personagem_local)
		)
	)

	if hud.has_method("atualizar_status_jogador"):
		hud.call(
			"atualizar_status_jogador",
			nome,
			dinheiro,
			propriedades
		)

	if hud.has_method("atualizar_reputacao_jogador"):
		hud.call(
			"atualizar_reputacao_jogador",
			int(dados.get("reputacao", REPUTACAO_INICIAL)),
			int(dados.get("xp_partida", 0))
		)

	if hud.has_method("atualizar_habilidade"):
		hud.call(
			"atualizar_habilidade",
			str(
				NOMES_HABILIDADES.get(
					personagem_local,
					"Poder Especial"
				)
			),
			int(dados.get("recarga_hab", 0))
		)

	if hud.has_method("atualizar_cartas_guardadas"):
		hud.call(
			"atualizar_cartas_guardadas",
			int(dados.get("cartas_construcao_gratis", 0)),
			int(dados.get("cartas_sair_prisao", 0))
		)


func _android_hud_atualizar_social(
	personagem_local: String
) -> void:
	var dados: Dictionary = dados_economia_jogadores.get(
		personagem_local,
		{}
	)
	var imunidades: Array = _android_hud_como_array(
		dados.get("imunidades", [])
	)
	var aliancas: Array = _android_hud_como_array(
		dados.get("aliancas", [])
	)

	if hud.has_method("atualizar_painel_imunidades"):
		hud.call(
			"atualizar_painel_imunidades",
			imunidades
		)
	if hud.has_method("atualizar_painel_aliancas"):
		hud.call(
			"atualizar_painel_aliancas",
			aliancas
		)
	if hud.has_method("atualizar_painel_promessas"):
		_android_hud_chamar_flexivel(
			"atualizar_painel_promessas",
			[
				_promessas_globais,
				personagem_local,
			]
		)


func _android_hud_atualizar_turno_isolado() -> void:
	var nome_atual: String = jogador_atual_id.capitalize()
	if dados_economia_jogadores.has(jogador_atual_id):
		nome_atual = str(
			dados_economia_jogadores[jogador_atual_id].get(
				"nome",
				nome_atual
			)
		)

	# Compatibilidade com versões da HUD que possuam um indicador dedicado.
	for metodo: String in [
		"atualizar_jogador_atual",
		"atualizar_nome_turno",
		"atualizar_turno",
	]:
		if hud.has_method(metodo):
			_android_hud_chamar_flexivel(
				metodo,
				[
					nome_atual,
					jogador_atual_id,
				]
			)
			break

	_android_hud_atualizar_permissoes()

	# A câmera de espectador deve acompanhar a troca. Para jogadores normais,
	# o movimento do pino continua sendo a fonte da câmera e não é duplicado.
	if (
		modo_espectador_local
		and has_method("_atualizar_alvo_camera_espectador")
	):
		call("_atualizar_alvo_camera_espectador")


func _android_hud_atualizar_dossie_diana() -> void:
	if hud == null or not is_instance_valid(hud):
		return

	var payload: Array = []
	for id_variant: Variant in lista_turnos:
		var jogador_id: String = str(id_variant)
		if jogador_id == "diana":
			continue
		if not dados_economia_jogadores.has(jogador_id):
			continue

		var dados: Dictionary = dados_economia_jogadores[jogador_id]
		if bool(dados.get("falido", false)):
			continue

		payload.append(
			{
				"nome": str(dados.get("nome", jogador_id)),
				"dinheiro": int(dados.get("dinheiro", 0)),
				"props": int(
					dados.get(
						"propriedades_compradas",
						_android_hud_contar_propriedades(
							jogador_id
						)
					)
				),
				"imunidades": (
					_android_hud_formatar_imunidades_dossie(
						dados.get("imunidades", [])
					)
				),
				"aliancas": (
					_android_hud_formatar_aliancas_dossie(
						dados.get("aliancas", [])
					)
				),
				"promessas": (
					_android_hud_formatar_promessas_dossie(
						jogador_id
					)
				),
				"reputacao": int(
					dados.get(
						"reputacao",
						REPUTACAO_INICIAL
					)
				),
				"xp_partida": int(
					dados.get("xp_partida", 0)
				),
			}
		)

	if hud.has_method("alimentar_dados_dossie"):
		hud.call(
			"alimentar_dados_dossie",
			payload
		)

	var container_variant: Variant = hud.get(
		"container_dossie"
	)
	if container_variant is CanvasItem:
		var container: CanvasItem = container_variant
		container.visible = true

	var evento_previsto: String = str(
		dados_economia_jogadores.get(
			"diana",
			{}
		).get(
			"fonte_anonima_evento_previsto",
			""
		)
	)
	if (
		not evento_previsto.is_empty()
		and evento_previsto == proximo_evento_global
		and hud.has_method("alimentar_previsao_evento")
	):
		hud.call(
			"alimentar_previsao_evento",
			proximo_evento_global,
			proximo_evento_descricao
		)


func _android_hud_formatar_imunidades_dossie(
	valor: Variant
) -> String:
	if not valor is Array:
		return "nenhuma"
	var imunidades: Array = valor
	if imunidades.is_empty():
		return "nenhuma"

	var partes: PackedStringArray = PackedStringArray()
	for item_variant: Variant in imunidades:
		if not item_variant is Dictionary:
			continue
		var item: Dictionary = item_variant
		var de_id: String = str(item.get("de", ""))
		var nome: String = str(
			dados_economia_jogadores.get(
				de_id,
				{}
			).get(
				"nome",
				de_id
			)
		)
		var espaco: int = nome.find(" ")
		if espaco > 0:
			nome = nome.substr(0, espaco)
		partes.append(
			"%s(%dv/%dT)" % [
				nome,
				int(item.get("visitas_restantes", 0)),
				int(item.get("turnos_restantes", 0)),
			]
		)
	return ", ".join(partes) if not partes.is_empty() else "nenhuma"


func _android_hud_formatar_aliancas_dossie(
	valor: Variant
) -> String:
	if not valor is Array:
		return "nenhuma"
	var aliancas: Array = valor
	if aliancas.is_empty():
		return "nenhuma"

	var partes: PackedStringArray = PackedStringArray()
	for item_variant: Variant in aliancas:
		if not item_variant is Dictionary:
			continue
		var item: Dictionary = item_variant
		var com_id: String = str(item.get("com", ""))
		var nome: String = str(
			dados_economia_jogadores.get(
				com_id,
				{}
			).get(
				"nome",
				com_id
			)
		)
		var espaco: int = nome.find(" ")
		if espaco > 0:
			nome = nome.substr(0, espaco)
		partes.append(
			"%s(%dT)" % [
				nome,
				int(item.get("turnos_restantes", 0)),
			]
		)
	return ", ".join(partes) if not partes.is_empty() else "nenhuma"


func _android_hud_formatar_promessas_dossie(
	jogador_id: String
) -> String:
	var feitas: int = 0
	var quebradas: int = 0
	for promessa_variant: Variant in _promessas_globais:
		if not promessa_variant is Dictionary:
			continue
		var promessa: Dictionary = promessa_variant
		if str(promessa.get("autor_id", "")) != jogador_id:
			continue
		feitas += 1
		if bool(promessa.get("quebrada", false)):
			quebradas += 1

	var texto: String = "%d feitas" % feitas
	if quebradas > 0:
		texto += " (%d quebradas!)" % quebradas
	return texto
