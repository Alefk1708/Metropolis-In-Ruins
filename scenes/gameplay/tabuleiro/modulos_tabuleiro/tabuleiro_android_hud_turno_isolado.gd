extends "res://scenes/gameplay/tabuleiro/modulos_tabuleiro/tabuleiro_android_painel_propriedades.gd"

# ============================================================================
# GODOT 4.7 — HUD INCREMENTAL CONSOLIDADA
# ============================================================================
#
# Esta versão não herda mais de tabuleiro_android_hud_incremental.gd.
# Toda a lógica incremental necessária está neste arquivo, evitando que um erro
# ou arquivo intermediário ausente impeça o Godot de resolver a classe.
#
# Domínios:
# - turno: jogador atual, permissões e câmera de espectador;
# - básico: dinheiro, propriedades, reputação, XP, recarga e cartas;
# - social: imunidades, alianças e promessas globais;
# - construção: cards persistentes do módulo pai;
# - casa atual: somente quando a casa ou seus modificadores mudam;
# - Diana: dossiê dedicado;
# - Yasmin: relatório continua exclusivo do início da rodada.
# ============================================================================


var _android_hud_inicializada: bool = false
var _android_hud_personagem_local: String = ""
var _android_hud_processando_super: bool = false

var _android_hud_assinatura_turno: String = ""
var _android_hud_assinatura_basica: String = ""
var _android_hud_assinatura_social: String = ""
var _android_hud_assinatura_menu: String = ""
var _android_hud_assinatura_casa: String = ""
var _android_hud_assinatura_dossie: String = ""


func _atualizar_hud_ciclo_turno() -> void:
	if _android_hud_processando_super:
		return
	if hud == null or not is_instance_valid(hud):
		return

	var personagem_local: String = _android_hud_obter_personagem_local()
	if personagem_local.is_empty():
		return
	if not dados_economia_jogadores.has(personagem_local):
		return

	if (
		not _android_hud_inicializada
		or personagem_local != _android_hud_personagem_local
	):
		_android_hud_executar_atualizacao_inicial()
		_android_hud_capturar_assinaturas(personagem_local)
		_android_hud_inicializada = true
		_android_hud_personagem_local = personagem_local
		return

	var nova_turno: String = _android_hud_assinatura_do_turno()
	var nova_basica: String = _android_hud_assinatura_basica_atual(
		personagem_local
	)
	var nova_social: String = _android_hud_assinatura_social_atual(
		personagem_local
	)
	var nova_menu: String = _android_hud_assinatura_menu_atual(
		personagem_local
	)
	var nova_casa: String = _android_hud_assinatura_casa_atual(
		personagem_local
	)

	var algo_mudou: bool = false

	if nova_turno != _android_hud_assinatura_turno:
		_android_hud_atualizar_turno()
		_android_hud_assinatura_turno = nova_turno
		algo_mudou = true

	if nova_basica != _android_hud_assinatura_basica:
		_android_hud_atualizar_basico(personagem_local)
		_android_hud_assinatura_basica = nova_basica
		algo_mudou = true

	if nova_social != _android_hud_assinatura_social:
		_android_hud_atualizar_social(personagem_local)
		_android_hud_assinatura_social = nova_social
		algo_mudou = true

	if nova_menu != _android_hud_assinatura_menu:
		_atualizar_menu_construcao()
		_android_hud_assinatura_menu = nova_menu
		algo_mudou = true

	if nova_casa != _android_hud_assinatura_casa:
		_atualizar_hud_minha_casa()
		_android_hud_assinatura_casa = nova_casa
		algo_mudou = true

	if personagem_local == "diana":
		var nova_dossie: String = _android_hud_assinatura_dossie_atual()
		if nova_dossie != _android_hud_assinatura_dossie:
			_android_hud_atualizar_dossie_diana()
			_android_hud_assinatura_dossie = nova_dossie
			algo_mudou = true

	# Permissões são leves e também podem ser alteradas por modais ou eventos
	# sem que dinheiro, propriedade ou turno mudem.
	_android_hud_atualizar_permissoes()

	if algo_mudou:
		GerenciadorSalvamento.marcar_estado_alterado(self)


func _android_hud_executar_atualizacao_inicial() -> void:
	_android_hud_processando_super = true
	super._atualizar_hud_ciclo_turno()
	_android_hud_processando_super = false


func _android_hud_capturar_assinaturas(
	personagem_local: String
) -> void:
	_android_hud_assinatura_turno = _android_hud_assinatura_do_turno()
	_android_hud_assinatura_basica = (
		_android_hud_assinatura_basica_atual(personagem_local)
	)
	_android_hud_assinatura_social = (
		_android_hud_assinatura_social_atual(personagem_local)
	)
	_android_hud_assinatura_menu = (
		_android_hud_assinatura_menu_atual(personagem_local)
	)
	_android_hud_assinatura_casa = (
		_android_hud_assinatura_casa_atual(personagem_local)
	)
	if personagem_local == "diana":
		_android_hud_assinatura_dossie = (
			_android_hud_assinatura_dossie_atual()
		)
	else:
		_android_hud_assinatura_dossie = ""


func _android_hud_obter_personagem_local() -> String:
	return str(
		Global.escolhas_da_mesa.get(
			Global.meu_peer_id,
			""
		)
	)


func _android_hud_contar_propriedades(
	personagem_id: String
) -> int:
	var total: int = 0
	for dono_variant: Variant in registro_propriedades.values():
		if str(dono_variant) == personagem_id:
			total += 1
	return total


func _android_hud_assinatura_do_turno() -> String:
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


func _android_hud_assinatura_basica_atual(
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
				str(_android_hud_contar_propriedades(personagem_local)),
				str(int(dados.get("reputacao", 0))),
				str(int(dados.get("xp_partida", 0))),
				str(int(dados.get("recarga_hab", 0))),
				str(int(dados.get("cartas_construcao_gratis", 0))),
				str(int(dados.get("cartas_sair_prisao", 0))),
				str(bool(dados.get("falido", false))),
			]
		)
	)


func _android_hud_assinatura_social_atual(
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


func _android_hud_assinatura_menu_atual(
	personagem_local: String
) -> String:
	var dados_locais: Dictionary = dados_economia_jogadores.get(
		personagem_local,
		{}
	)
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


func _android_hud_assinatura_casa_atual(
	personagem_local: String
) -> String:
	var casa_id: int = int(
		posicoes_jogadores.get(
			personagem_local,
			0
		)
	)
	if pinos_jogadores.has(personagem_local):
		var pino_variant: Variant = pinos_jogadores[personagem_local]
		if pino_variant != null and is_instance_valid(pino_variant):
			casa_id = int(pino_variant.get("casa_atual"))

	var dados_casa: Dictionary = tabuleiro.get(casa_id, {})
	return "|".join(
		PackedStringArray(
			[
				personagem_local,
				str(casa_id),
				str(registro_propriedades.get(casa_id, "")),
				str(dados_casa.get("nivel", 0)),
				str(dados_casa.get("hipotecada", false)),
				str(dados_casa.get("grupo", "")),
				str(evento_ativo),
				str(multiplicador_inflacao_global),
			]
		)
	)


func _android_hud_assinatura_dossie_atual() -> String:
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
						str(_android_hud_contar_propriedades(jogador_id)),
						str(dados.get("imunidades", [])),
						str(dados.get("aliancas", [])),
						str(bool(dados.get("falido", false))),
						str(int(dados.get("reputacao", 0))),
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

	var propriedades_ordenadas: Array = registro_propriedades.keys()
	propriedades_ordenadas.sort()
	for casa_variant: Variant in propriedades_ordenadas:
		var casa_id: int = int(casa_variant)
		partes.append(
			"%d:%s" % [
				casa_id,
				str(registro_propriedades.get(casa_id, "")),
			]
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
	var propriedades: int = _android_hud_contar_propriedades(
		personagem_local
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
			int(dados.get("reputacao", 0)),
			int(dados.get("xp_partida", 0))
		)

	if hud.has_method("atualizar_habilidade"):
		hud.call(
			"atualizar_habilidade",
			_android_hud_nome_habilidade(personagem_local),
			int(dados.get("recarga_hab", 0))
		)

	if hud.has_method("atualizar_cartas_guardadas"):
		hud.call(
			"atualizar_cartas_guardadas",
			int(dados.get("cartas_construcao_gratis", 0)),
			int(dados.get("cartas_sair_prisao", 0))
		)


func _android_hud_nome_habilidade(
	personagem_local: String
) -> String:
	match personagem_local:
		"yasmin":
			return "Oferta Irrecusável"
		"breno":
			return "Decreto Emergencial"
		"mira":
			return "Retrofit Urbano"
		"igor":
			return "Especulação Imobiliária"
		"diana":
			return "Vazamento Seletivo"
		"kofi":
			return "Mutirão"
		_:
			return "Poder Especial"


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


func _android_hud_atualizar_turno() -> void:
	var nome_atual: String = jogador_atual_id.capitalize()
	if dados_economia_jogadores.has(jogador_atual_id):
		nome_atual = str(
			dados_economia_jogadores[jogador_atual_id].get(
				"nome",
				nome_atual
			)
		)

	for metodo_variant: Variant in [
		"atualizar_jogador_atual",
		"atualizar_nome_turno",
		"atualizar_turno",
	]:
		var metodo: String = str(metodo_variant)
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

	if modo_espectador_local:
		if has_method("_atualizar_alvo_camera_espectador"):
			call("_atualizar_alvo_camera_espectador")


func _android_hud_atualizar_dossie_diana() -> void:
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
				"props": _android_hud_contar_propriedades(jogador_id),
				"imunidades": _android_hud_formatar_imunidades(
					dados.get("imunidades", [])
				),
				"aliancas": _android_hud_formatar_aliancas(
					dados.get("aliancas", [])
				),
				"promessas": _android_hud_formatar_promessas(
					jogador_id
				),
				"reputacao": int(dados.get("reputacao", 0)),
				"xp_partida": int(dados.get("xp_partida", 0)),
			}
		)

	if hud.has_method("alimentar_dados_dossie"):
		hud.call(
			"alimentar_dados_dossie",
			payload
		)

	var container_variant: Variant = hud.get("container_dossie")
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


func _android_hud_formatar_imunidades(
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

	if partes.is_empty():
		return "nenhuma"
	return ", ".join(partes)


func _android_hud_formatar_aliancas(
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

	if partes.is_empty():
		return "nenhuma"
	return ", ".join(partes)


func _android_hud_formatar_promessas(
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


func _android_hud_como_array(
	valor: Variant
) -> Array:
	if valor is Array:
		return valor
	return []


func _android_hud_chamar_flexivel(
	metodo: String,
	argumentos_disponiveis: Array
) -> void:
	var quantidade_argumentos: int = -1

	for info_variant: Variant in hud.get_method_list():
		if not info_variant is Dictionary:
			continue

		var info: Dictionary = info_variant
		if str(info.get("name", "")) != metodo:
			continue

		var argumentos_variant: Variant = info.get("args", [])
		if argumentos_variant is Array:
			quantidade_argumentos = argumentos_variant.size()
		break

	if quantidade_argumentos < 0:
		return

	var argumentos: Array = []
	var limite: int = mini(
		quantidade_argumentos,
		argumentos_disponiveis.size()
	)
	for indice: int in range(limite):
		argumentos.append(
			argumentos_disponiveis[indice]
		)

	hud.callv(
		metodo,
		argumentos
	)


func _android_hud_atualizar_permissoes() -> void:
	if has_method("_verificar_permissao_de_clique"):
		call("_verificar_permissao_de_clique")

	if has_method("_atualizar_estado_hud_espectador"):
		call("_atualizar_estado_hud_espectador")
