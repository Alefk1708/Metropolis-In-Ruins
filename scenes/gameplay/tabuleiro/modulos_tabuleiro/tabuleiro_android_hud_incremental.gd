extends "res://scenes/gameplay/tabuleiro/modulos_tabuleiro/tabuleiro_android_painel_propriedades.gd"

# ============================================================================
# ANDROID — HUD INCREMENTAL POR DOMÍNIO
# ============================================================================
#
# O método original _atualizar_hud_ciclo_turno() atualizava todos os painéis
# em conjunto. Esta camada separa o estado visual em domínios independentes:
#
# - básico: nome, dinheiro, quantidade de propriedades, habilidade e cartas;
# - social: imunidades, alianças e promessas do jogador local;
# - construção: cache de cards implementado no módulo anterior;
# - casa atual: atualizada somente quando posição/terreno/evento mudam;
# - dossiê da Diana: reconstruído somente quando os dados investigados mudam;
# - relatório da Yasmin: não é alimentado pelo ciclo genérico; o fluxo original
#   de início da rodada continua sendo a fonte da atualização.
#
# A primeira atualização ainda chama o método herdado para garantir que toda a
# HUD seja inicializada exatamente como antes. Depois disso, mudanças isoladas
# atualizam somente seu próprio domínio.
# ============================================================================


var _android_hud_inicializada: bool = false
var _android_hud_personagem_local: String = ""

var _android_hud_assinatura_basica: String = ""
var _android_hud_assinatura_social: String = ""
var _android_hud_assinatura_menu: String = ""
var _android_hud_assinatura_casa: String = ""
var _android_hud_assinatura_dossie: String = ""

var _android_hud_processando_super: bool = false


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

	# Primeira montagem, troca de personagem local ou reconstrução da cena:
	# usa o fluxo completo uma única vez e captura o estado resultante.
	if (
		not _android_hud_inicializada
		or personagem_local != _android_hud_personagem_local
	):
		_android_hud_executar_super_completo()
		_android_hud_capturar_assinaturas(personagem_local)
		_android_hud_inicializada = true
		_android_hud_personagem_local = personagem_local
		return

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

	# Diana observa dados de todos os jogadores. Somente quando esses dados
	# mudam executamos o construtor completo que já existe no jogo.
	if personagem_local == "diana":
		var assinatura_dossie: String = (
			_android_hud_criar_assinatura_dossie()
		)
		if assinatura_dossie != _android_hud_assinatura_dossie:
			_android_hud_executar_super_completo()
			_android_hud_capturar_assinaturas(personagem_local)
			return

	var algo_mudou: bool = false

	if assinatura_basica != _android_hud_assinatura_basica:
		_android_hud_atualizar_basico(personagem_local)
		_android_hud_assinatura_basica = assinatura_basica
		algo_mudou = true

	if assinatura_social != _android_hud_assinatura_social:
		_android_hud_atualizar_social(personagem_local)
		_android_hud_assinatura_social = assinatura_social
		algo_mudou = true

	if assinatura_menu != _android_hud_assinatura_menu:
		# Reutiliza os cards persistentes do módulo anterior.
		_atualizar_menu_construcao()
		_android_hud_assinatura_menu = assinatura_menu
		algo_mudou = true

	if assinatura_casa != _android_hud_assinatura_casa:
		_atualizar_hud_minha_casa()
		_android_hud_assinatura_casa = assinatura_casa
		algo_mudou = true

	# Permissões são leves e dependem do jogador atual. Mantê-las fora dos
	# painéis pesados evita que uma simples troca de turno reconstrua a HUD.
	_android_hud_atualizar_permissoes()

	# Preserva o comportamento do sistema de salvamento. O gerenciador apenas
	# marca o estado como alterado; a escrita continua sendo controlada por ele.
	if algo_mudou:
		GerenciadorSalvamento.marcar_estado_alterado(self)


func _android_hud_executar_super_completo() -> void:
	_android_hud_processando_super = true
	super._atualizar_hud_ciclo_turno()
	_android_hud_processando_super = false


func _android_hud_capturar_assinaturas(
	personagem_local: String
) -> void:
	_android_hud_assinatura_basica = (
		_android_hud_criar_assinatura_basica(personagem_local)
	)
	_android_hud_assinatura_social = (
		_android_hud_criar_assinatura_social(personagem_local)
	)
	_android_hud_assinatura_menu = (
		_android_hud_criar_assinatura_menu(personagem_local)
	)
	_android_hud_assinatura_casa = (
		_android_hud_criar_assinatura_casa(personagem_local)
	)
	_android_hud_assinatura_dossie = (
		_android_hud_criar_assinatura_dossie()
		if personagem_local == "diana"
		else ""
	)


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
				str(_android_hud_contar_propriedades(personagem_local)),
				str(int(dados.get("recarga_hab", 0))),
				str(int(dados.get("cartas_construcao_gratis", 0))),
				str(int(dados.get("cartas_sair_prisao", 0))),
				str(jogador_atual_id),
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
				str(dados.get("promessas", [])),
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
	var partes: PackedStringArray = PackedStringArray(
		[
			personagem_local,
			str(int(dados_locais.get("dinheiro", 0))),
			str(int(dados_locais.get("cartas_construcao_gratis", 0))),
			str(bool(dados_locais.get("mutirao_ativo", false))),
			str(jogador_atual_id),
			str(evento_ativo),
			str(_construcoes_visuais_em_andamento.size()),
		]
	)

	var ids: Array = registro_propriedades.keys()
	ids.sort()
	for id_variant: Variant in ids:
		var casa_id: int = int(id_variant)
		if str(registro_propriedades.get(casa_id, "")) != personagem_local:
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


func _android_hud_criar_assinatura_casa(
	personagem_local: String
) -> String:
	var posicao: int = int(
		posicoes_jogadores.get(
			personagem_local,
			0
		)
	)
	var dados_casa: Dictionary = tabuleiro.get(posicao, {})
	return "|".join(
		PackedStringArray(
			[
				personagem_local,
				str(posicao),
				str(registro_propriedades.get(posicao, "")),
				str(dados_casa),
				str(evento_ativo),
			]
		)
	)


func _android_hud_criar_assinatura_dossie() -> String:
	# Só é calculada quando o jogador local é Diana.
	# O dicionário econômico já contém dinheiro, falência, imunidades,
	# alianças e outros efeitos de cada personagem.
	return "|".join(
		PackedStringArray(
			[
				str(dados_economia_jogadores),
				str(registro_propriedades),
				str(evento_ativo),
			]
		)
	)


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
	var propriedades: int = (
		_android_hud_contar_propriedades(personagem_local)
	)

	var label_nome_variant: Variant = hud.get("label_nome")
	if label_nome_variant is Label:
		var label_nome_local: Label = label_nome_variant
		label_nome_local.text = nome.to_upper()

	var label_dinheiro_variant: Variant = hud.get("label_dinheiro")
	if label_dinheiro_variant is Label:
		var label_dinheiro_local: Label = label_dinheiro_variant
		label_dinheiro_local.text = "DINHEIRO: $%d" % dinheiro

	var label_props_variant: Variant = hud.get("label_propriedades")
	if label_props_variant is Label:
		var label_props_local: Label = label_props_variant
		label_props_local.text = "PROPRIEDADES: %d" % propriedades

	if hud.has_method("atualizar_habilidade"):
		hud.call(
			"atualizar_habilidade",
			str(
				NOMES_HABILIDADES.get(
					personagem_local,
					"Habilidade"
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
	var promessas: Array = _android_hud_como_array(
		dados.get("promessas", [])
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

	# Versões diferentes do painel de promessas usam assinaturas distintas.
	# A chamada flexível consulta a quantidade de argumentos antes de executar.
	if hud.has_method("atualizar_painel_promessas"):
		_android_hud_chamar_flexivel(
			"atualizar_painel_promessas",
			[
				promessas,
				personagem_local,
			]
		)


func _android_hud_como_array(valor: Variant) -> Array:
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
	for indice: int in range(
		mini(
			quantidade_argumentos,
			argumentos_disponiveis.size()
		)
	):
		argumentos.append(
			argumentos_disponiveis[indice]
		)
	hud.callv(metodo, argumentos)


func _android_hud_atualizar_permissoes() -> void:
	if has_method("_verificar_permissao_de_clique"):
		call("_verificar_permissao_de_clique")
	if has_method("_atualizar_estado_hud_espectador"):
		call("_atualizar_estado_hud_espectador")
