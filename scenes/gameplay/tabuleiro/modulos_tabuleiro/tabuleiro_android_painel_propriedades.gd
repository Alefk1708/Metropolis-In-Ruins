extends "res://scenes/gameplay/tabuleiro/modulos_tabuleiro/tabuleiro_dados_aleatorios_correcao.gd"

# ============================================================================
# ANDROID — CACHE DO PAINEL DE GESTÃO DE PROPRIEDADES
# ============================================================================
#
# O fluxo original chamava hud.popular_menu_construcao() em diversas mudanças
# de estado. A HUD apagava todos os filhos da lista e recriava cabeçalho, cards,
# barras, labels, StyleBoxFlat e botões para todas as propriedades.
#
# Esta camada substitui somente _atualizar_menu_construcao():
# - cria cada card uma única vez por casa_id;
# - atualiza somente os controles cujo estado mudou;
# - remove um card apenas quando a propriedade deixa de pertencer ao jogador;
# - preserva os mesmos sinais de construir e hipotecar;
# - não altera regras econômicas, LAN, Photon, bots ou salvamento.
# ============================================================================


const _ANDROID_PROPS_FONTE = preload(
	"res://assets/fonts/PressStart2P.ttf"
)

var _android_props_lista: VBoxContainer = null
var _android_props_cabecalho: Label = null
var _android_props_mensagem_vazia: Label = null
var _android_props_cards: Dictionary = {}


func _atualizar_menu_construcao() -> void:
	if hud == null or not is_instance_valid(hud):
		return

	var meu_personagem_local: String = str(
		Global.escolhas_da_mesa.get(
			Global.meu_peer_id,
			""
		)
	)
	if (
		meu_personagem_local.is_empty()
		or not dados_economia_jogadores.has(
			meu_personagem_local
		)
	):
		return

	var props_disponiveis: Array[Dictionary] = []
	var dados_locais: Dictionary = (
		dados_economia_jogadores[meu_personagem_local]
	)
	var meu_saldo: int = int(
		dados_locais.get("dinheiro", 0)
	)
	var tem_carta_gratis: bool = (
		int(
			dados_locais.get(
				"cartas_construcao_gratis",
				0
			)
		) > 0
	)

	for id_variant: Variant in tabuleiro.keys():
		var casa_id: int = int(id_variant)
		var dados: Dictionary = tabuleiro[casa_id]
		var tipo: String = str(
			dados.get("tipo", "")
		)
		if tipo not in [
			"propriedade",
			"transporte",
			"utilidade",
		]:
			continue
		if (
			not registro_propriedades.has(casa_id)
			or str(
				registro_propriedades[casa_id]
			) != meu_personagem_local
		):
			continue

		var grupo: String = str(
			dados.get("grupo", "")
		)
		var nivel: int = int(
			dados.get("nivel", 0)
		)
		var hipotecada: bool = bool(
			dados.get("hipotecada", false)
		)
		var propriedade_valida_para_obra: bool = (
			tipo == "propriedade"
			and _construcoes_visuais_em_andamento.is_empty()
			and not hipotecada
			and nivel < 5
			and not _construcao_bloqueada_por_efeito(
				meu_personagem_local,
				casa_id
			)
		)
		var pode_construir_pago: bool = (
			propriedade_valida_para_obra
			and (
				bool(
					dados_locais.get(
						"mutirao_ativo",
						false
					)
				)
				or _pode_construir(
					meu_personagem_local,
					grupo
				)
			)
		)
		var usar_carta_gratis: bool = (
			propriedade_valida_para_obra
			and tem_carta_gratis
		)
		var pode_construir: bool = (
			pode_construir_pago
			or usar_carta_gratis
		)
		var custo_casa: int = (
			_calcular_custo_construcao(
				meu_personagem_local,
				casa_id
			)
		)
		var aluguel_atual: int = _calcular_aluguel(
			casa_id,
			meu_personagem_local
		)
		var valor_hipoteca: int = int(
			_calcular_valor_propriedade(
				casa_id
			) * 0.5
		)
		var custo_resgate: int = (
			_calcular_custo_resgate_hipoteca(
				casa_id
			)
		)

		props_disponiveis.append(
			{
				"id": casa_id,
				"nome": str(
					dados.get(
						"nome",
						"Propriedade"
					)
				),
				"nivel": nivel,
				"custo": custo_casa,
				"saldo_jogador": meu_saldo,
				"cor": cores_grupos.get(
					grupo,
					Color.WHITE
				),
				"pode_construir": pode_construir,
				"usar_carta_gratis": usar_carta_gratis,
				"aluguel_atual": aluguel_atual,
				"hipotecada": hipotecada,
				"valor_hipoteca": valor_hipoteca,
				"valor_resgate": custo_resgate,
			}
		)

	_android_props_popular_menu(
		props_disponiveis
	)


func _android_props_popular_menu(
	propriedades: Array[Dictionary]
) -> void:
	if not _android_props_garantir_estrutura():
		return

	var ids_presentes: Dictionary = {}
	for prop: Dictionary in propriedades:
		ids_presentes[int(prop.get("id", -1))] = true

	# Destruição ocorre somente quando a propriedade realmente sai da lista.
	var ids_antigos: Array = _android_props_cards.keys()
	for id_variant: Variant in ids_antigos:
		var casa_id_antiga: int = int(id_variant)
		if ids_presentes.has(casa_id_antiga):
			continue
		var cache_antigo_variant: Variant = (
			_android_props_cards.get(
				casa_id_antiga,
				{}
			)
		)
		if cache_antigo_variant is Dictionary:
			var cache_antigo: Dictionary = (
				cache_antigo_variant
			)
			var card_antigo: Control = (
				cache_antigo.get("card") as Control
			)
			if (
				card_antigo != null
				and is_instance_valid(card_antigo)
			):
				var pai: Node = card_antigo.get_parent()
				if pai != null:
					pai.remove_child(card_antigo)
				card_antigo.queue_free()
		_android_props_cards.erase(
			casa_id_antiga
		)

	_android_props_mensagem_vazia.visible = (
		propriedades.is_empty()
	)

	var indice_visual: int = 2
	for prop: Dictionary in propriedades:
		var casa_id: int = int(
			prop.get("id", -1)
		)
		if casa_id < 0:
			continue

		var cache: Dictionary = {}
		var cache_variant: Variant = (
			_android_props_cards.get(
				casa_id,
				{}
			)
		)
		if cache_variant is Dictionary:
			cache = cache_variant

		var card_existente: Control = (
			cache.get("card") as Control
		)
		if (
			cache.is_empty()
			or card_existente == null
			or not is_instance_valid(
				card_existente
			)
		):
			cache = _android_props_criar_card(
				casa_id
			)
			_android_props_cards[casa_id] = (
				cache
			)

		var estado_novo: String = (
			_android_props_estado(prop)
		)
		if str(
			cache.get("estado", "")
		) != estado_novo:
			_android_props_atualizar_card(
				cache,
				prop
			)
			cache["estado"] = estado_novo
			_android_props_cards[casa_id] = (
				cache
			)

		var card: Control = cache.get(
			"card"
		) as Control
		if (
			card != null
			and is_instance_valid(card)
			and card.get_parent() == _android_props_lista
		):
			_android_props_lista.move_child(
				card,
				mini(
					indice_visual,
					_android_props_lista.get_child_count()
					- 1
				)
			)
			indice_visual += 1


func _android_props_garantir_estrutura() -> bool:
	if hud == null or not is_instance_valid(hud):
		return false

	var lista_variant: Variant = hud.get(
		"lista_construcao"
	)
	if not lista_variant is VBoxContainer:
		return false
	var lista_atual: VBoxContainer = lista_variant

	if (
		_android_props_lista == lista_atual
		and is_instance_valid(
			_android_props_lista
		)
		and _android_props_cabecalho != null
		and is_instance_valid(
			_android_props_cabecalho
		)
	):
		return true

	_android_props_lista = lista_atual
	_android_props_cards.clear()

	# Limpeza única para remover qualquer conteúdo criado pelo fluxo antigo.
	for filho: Node in _android_props_lista.get_children():
		_android_props_lista.remove_child(filho)
		filho.queue_free()

	_android_props_cabecalho = Label.new()
	_android_props_cabecalho.name = (
		"CabecalhoPropriedadesCache"
	)
	_android_props_cabecalho.text = (
		"=== SUAS PROPRIEDADES ==="
	)
	_android_props_cabecalho.add_theme_font_override(
		"font",
		_ANDROID_PROPS_FONTE
	)
	_android_props_cabecalho.add_theme_font_size_override(
		"font_size",
		16
	)
	_android_props_cabecalho.add_theme_color_override(
		"font_color",
		Color(0.95, 0.85, 0.15)
	)
	_android_props_cabecalho.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_android_props_lista.add_child(
		_android_props_cabecalho
	)

	_android_props_mensagem_vazia = Label.new()
	_android_props_mensagem_vazia.name = (
		"MensagemSemPropriedadesCache"
	)
	_android_props_mensagem_vazia.text = (
		"\nVOCÊ AINDA NÃO TEM\n"
		+ "PROPRIEDADES.\n\n"
		+ "COMPRE TERRENOS\n"
		+ "PARA COMEÇAR."
	)
	_android_props_mensagem_vazia.add_theme_font_override(
		"font",
		_ANDROID_PROPS_FONTE
	)
	_android_props_mensagem_vazia.add_theme_font_size_override(
		"font_size",
		14
	)
	_android_props_mensagem_vazia.add_theme_color_override(
		"font_color",
		Color(0.6, 0.6, 0.6)
	)
	_android_props_mensagem_vazia.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_android_props_mensagem_vazia.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)
	_android_props_mensagem_vazia.custom_minimum_size = (
		Vector2(0, 200)
	)
	_android_props_mensagem_vazia.visible = false
	_android_props_lista.add_child(
		_android_props_mensagem_vazia
	)
	return true


func _android_props_criar_card(
	casa_id: int
) -> Dictionary:
	var card: PanelContainer = PanelContainer.new()
	card.name = "CardPropriedade_%d" % casa_id
	card.custom_minimum_size = Vector2.ZERO

	var estilo: StyleBoxFlat = StyleBoxFlat.new()
	estilo.bg_color = Color(
		0.08,
		0.08,
		0.10,
		0.95
	)
	estilo.border_width_left = 4
	estilo.border_width_right = 4
	estilo.border_width_top = 4
	estilo.border_width_bottom = 4
	estilo.corner_radius_top_left = 6
	estilo.corner_radius_top_right = 6
	estilo.corner_radius_bottom_left = 6
	estilo.corner_radius_bottom_right = 6
	estilo.content_margin_left = 12
	estilo.content_margin_right = 12
	estilo.content_margin_top = 10
	estilo.content_margin_bottom = 10
	card.add_theme_stylebox_override(
		"panel",
		estilo
	)
	_android_props_lista.add_child(card)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override(
		"separation",
		6
	)
	card.add_child(vbox)

	var hbox_topo: HBoxContainer = HBoxContainer.new()
	hbox_topo.add_theme_constant_override(
		"separation",
		8
	)
	vbox.add_child(hbox_topo)

	var faixa: ColorRect = ColorRect.new()
	faixa.custom_minimum_size = Vector2(8, 28)
	faixa.size_flags_vertical = Control.SIZE_FILL
	hbox_topo.add_child(faixa)

	var lbl_nome: Label = Label.new()
	lbl_nome.add_theme_font_override(
		"font",
		_ANDROID_PROPS_FONTE
	)
	lbl_nome.add_theme_font_size_override(
		"font_size",
		14
	)
	lbl_nome.add_theme_color_override(
		"font_color",
		Color.WHITE
	)
	lbl_nome.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	lbl_nome.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)
	hbox_topo.add_child(lbl_nome)

	var hbox_nivel: HBoxContainer = HBoxContainer.new()
	hbox_nivel.add_theme_constant_override(
		"separation",
		4
	)
	vbox.add_child(hbox_nivel)

	var lbl_nivel_titulo: Label = Label.new()
	lbl_nivel_titulo.text = "NÍVEL:"
	lbl_nivel_titulo.add_theme_font_override(
		"font",
		_ANDROID_PROPS_FONTE
	)
	lbl_nivel_titulo.add_theme_font_size_override(
		"font_size",
		11
	)
	lbl_nivel_titulo.add_theme_color_override(
		"font_color",
		Color(0.65, 0.65, 0.65)
	)
	hbox_nivel.add_child(lbl_nivel_titulo)

	var barras: Array[ColorRect] = []
	for _indice: int in range(5):
		var barra: ColorRect = ColorRect.new()
		barra.custom_minimum_size = Vector2(
			20,
			14
		)
		barra.color = Color(
			0.2,
			0.2,
			0.2,
			0.5
		)
		hbox_nivel.add_child(barra)
		barras.append(barra)

	var lbl_nivel: Label = Label.new()
	lbl_nivel.add_theme_font_override(
		"font",
		_ANDROID_PROPS_FONTE
	)
	lbl_nivel.add_theme_font_size_override(
		"font_size",
		11
	)
	hbox_nivel.add_child(lbl_nivel)

	var hbox_info: HBoxContainer = HBoxContainer.new()
	hbox_info.add_theme_constant_override(
		"separation",
		12
	)
	vbox.add_child(hbox_info)

	var lbl_aluguel: Label = Label.new()
	lbl_aluguel.add_theme_font_override(
		"font",
		_ANDROID_PROPS_FONTE
	)
	lbl_aluguel.add_theme_font_size_override(
		"font_size",
		11
	)
	lbl_aluguel.add_theme_color_override(
		"font_color",
		Color(0.3, 0.9, 0.3)
	)
	lbl_aluguel.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	hbox_info.add_child(lbl_aluguel)

	# Criado uma única vez e apenas alternado entre visível/oculto.
	var lbl_hipoteca: Label = Label.new()
	lbl_hipoteca.text = (
		"HIPOTECADA — Sem aluguel"
	)
	lbl_hipoteca.add_theme_font_override(
		"font",
		_ANDROID_PROPS_FONTE
	)
	lbl_hipoteca.add_theme_font_size_override(
		"font_size",
		11
	)
	lbl_hipoteca.add_theme_color_override(
		"font_color",
		Color(0.95, 0.6, 0.2)
	)
	lbl_hipoteca.visible = false
	vbox.add_child(lbl_hipoteca)

	var hbox_botoes: HBoxContainer = HBoxContainer.new()
	hbox_botoes.add_theme_constant_override(
		"separation",
		8
	)
	vbox.add_child(hbox_botoes)

	var btn_construir: Button = Button.new()
	btn_construir.name = (
		"BtnConstruir_%d" % casa_id
	)
	btn_construir.custom_minimum_size = Vector2(
		0,
		56
	)
	btn_construir.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	btn_construir.add_theme_font_override(
		"font",
		_ANDROID_PROPS_FONTE
	)
	btn_construir.add_theme_font_size_override(
		"font_size",
		12
	)
	btn_construir.pressed.connect(
		_android_props_acionar_construcao.bind(
			casa_id
		)
	)
	hbox_botoes.add_child(btn_construir)

	var btn_hipoteca: Button = Button.new()
	btn_hipoteca.name = (
		"BtnHipoteca_%d" % casa_id
	)
	btn_hipoteca.custom_minimum_size = Vector2(
		160,
		56
	)
	btn_hipoteca.add_theme_font_override(
		"font",
		_ANDROID_PROPS_FONTE
	)
	btn_hipoteca.add_theme_font_size_override(
		"font_size",
		11
	)
	btn_hipoteca.pressed.connect(
		_android_props_acionar_hipoteca.bind(
			casa_id
		)
	)
	hbox_botoes.add_child(btn_hipoteca)

	return {
		"card": card,
		"estilo": estilo,
		"faixa": faixa,
		"nome": lbl_nome,
		"barras": barras,
		"nivel": lbl_nivel,
		"aluguel": lbl_aluguel,
		"hipoteca": lbl_hipoteca,
		"btn_construir": btn_construir,
		"btn_hipoteca": btn_hipoteca,
		"estado": "",
	}


func _android_props_atualizar_card(
	cache: Dictionary,
	prop: Dictionary
) -> void:
	var cor: Color = prop.get(
		"cor",
		Color.WHITE
	)
	var nivel: int = clampi(
		int(prop.get("nivel", 0)),
		0,
		5
	)
	var hipotecada: bool = bool(
		prop.get("hipotecada", false)
	)

	var estilo: StyleBoxFlat = cache.get(
		"estilo"
	) as StyleBoxFlat
	if estilo != null:
		estilo.border_color = cor

	var faixa: ColorRect = cache.get(
		"faixa"
	) as ColorRect
	if faixa != null:
		faixa.color = cor

	var lbl_nome: Label = cache.get(
		"nome"
	) as Label
	if lbl_nome != null:
		lbl_nome.text = str(
			prop.get("nome", "Propriedade")
		).replace("\n", " ").to_upper()

	var barras_variant: Variant = cache.get(
		"barras",
		[]
	)
	if barras_variant is Array:
		var barras: Array = barras_variant
		for indice: int in range(
			mini(5, barras.size())
		):
			var barra: ColorRect = (
				barras[indice] as ColorRect
			)
			if barra == null:
				continue
			if indice < nivel:
				barra.color = (
					Color(1.0, 0.85, 0.15)
					if nivel == 5
					else cor
				)
			else:
				barra.color = Color(
					0.2,
					0.2,
					0.2,
					0.5
				)

	var lbl_nivel: Label = cache.get(
		"nivel"
	) as Label
	if lbl_nivel != null:
		lbl_nivel.text = (
			"HOTEL"
			if nivel == 5
			else "%d/5" % nivel
		)
		lbl_nivel.add_theme_color_override(
			"font_color",
			(
				Color(1.0, 0.85, 0.15)
				if nivel == 5
				else Color(0.8, 0.8, 0.8)
			)
		)

	var lbl_aluguel: Label = cache.get(
		"aluguel"
	) as Label
	if lbl_aluguel != null:
		lbl_aluguel.text = (
			"ALUGUEL: $%d"
			% int(
				prop.get(
					"aluguel_atual",
					0
				)
			)
		)

	var lbl_hipoteca: Label = cache.get(
		"hipoteca"
	) as Label
	if lbl_hipoteca != null:
		lbl_hipoteca.visible = hipotecada

	var btn_construir: Button = cache.get(
		"btn_construir"
	) as Button
	if btn_construir != null:
		_android_props_configurar_construir(
			btn_construir,
			prop,
			nivel
		)

	var btn_hipoteca: Button = cache.get(
		"btn_hipoteca"
	) as Button
	if btn_hipoteca != null:
		_android_props_configurar_hipoteca(
			btn_hipoteca,
			prop
		)


func _android_props_configurar_construir(
	botao: Button,
	prop: Dictionary,
	nivel: int
) -> void:
	botao.disabled = false
	botao.modulate = Color.WHITE
	botao.tooltip_text = ""
	botao.remove_theme_color_override(
		"font_color"
	)
	botao.remove_theme_color_override(
		"font_hover_color"
	)

	if not bool(
		prop.get("pode_construir", false)
	):
		botao.text = "NÃO PODE\nCONSTRUIR"
		botao.disabled = true
		botao.modulate = Color(
			0.5,
			0.5,
			0.5
		)
	elif nivel >= 5:
		botao.text = "HOTEL MÁX."
		botao.disabled = true
		botao.modulate = Color(
			0.5,
			0.5,
			0.5
		)
	elif bool(
		prop.get("hipotecada", false)
	):
		botao.text = "HIPOTECADA"
		botao.disabled = true
		botao.modulate = Color(
			0.5,
			0.5,
			0.5
		)
	elif bool(
		prop.get(
			"usar_carta_gratis",
			false
		)
	):
		botao.text = "CONSTRUIR\nGRÁTIS"
		botao.add_theme_color_override(
			"font_color",
			Color(0.55, 1.0, 0.62)
		)
		botao.add_theme_color_override(
			"font_hover_color",
			Color(0.78, 1.0, 0.82)
		)
		botao.tooltip_text = (
			"Usará 1 carta de construção gratuita."
		)
	elif int(
		prop.get("custo", 0)
	) > int(
		prop.get("saldo_jogador", 0)
	):
		botao.text = (
			"SEM $ (%d)"
			% int(prop.get("custo", 0))
		)
		botao.disabled = true
		botao.modulate = Color(
			0.5,
			0.5,
			0.5
		)
	else:
		botao.text = (
			"CONSTRUIR ($%d)"
			% int(prop.get("custo", 0))
		)
		botao.add_theme_color_override(
			"font_color",
			Color(0.4, 0.9, 0.4)
		)


func _android_props_configurar_hipoteca(
	botao: Button,
	prop: Dictionary
) -> void:
	botao.disabled = false
	botao.modulate = Color.WHITE
	botao.remove_theme_color_override(
		"font_color"
	)

	if bool(
		prop.get("hipotecada", false)
	):
		var custo_resgate: int = int(
			prop.get("valor_resgate", 0)
		)
		botao.text = (
			"RESGATAR\n$%d"
			% custo_resgate
		)
		if custo_resgate > int(
			prop.get("saldo_jogador", 0)
		):
			botao.disabled = true
			botao.modulate = Color(
				0.5,
				0.5,
				0.5
			)
		else:
			botao.add_theme_color_override(
				"font_color",
				Color(0.4, 0.95, 0.4)
			)
	else:
		botao.text = (
			"HIPOTECAR\n+$%d"
			% int(
				prop.get(
					"valor_hipoteca",
					0
				)
			)
		)
		botao.add_theme_color_override(
			"font_color",
			Color(0.95, 0.6, 0.2)
		)


func _android_props_estado(
	prop: Dictionary
) -> String:
	var cor: Color = prop.get(
		"cor",
		Color.WHITE
	)
	return "|".join(
		PackedStringArray(
			[
				str(prop.get("nome", "")),
				str(int(prop.get("nivel", 0))),
				str(int(prop.get("custo", 0))),
				str(
					int(
						prop.get(
							"saldo_jogador",
							0
						)
					)
				),
				cor.to_html(true),
				str(
					bool(
						prop.get(
							"pode_construir",
							false
						)
					)
				),
				str(
					bool(
						prop.get(
							"usar_carta_gratis",
							false
						)
					)
				),
				str(
					int(
						prop.get(
							"aluguel_atual",
							0
						)
					)
				),
				str(
					bool(
						prop.get(
							"hipotecada",
							false
						)
					)
				),
				str(
					int(
						prop.get(
							"valor_hipoteca",
							0
						)
					)
				),
				str(
					int(
						prop.get(
							"valor_resgate",
							0
						)
					)
				),
			]
		)
	)


func _android_props_acionar_construcao(
	casa_id: int
) -> void:
	if (
		hud != null
		and is_instance_valid(hud)
		and hud.has_method("_avisar_construcao")
	):
		hud.call(
			"_avisar_construcao",
			casa_id
		)


func _android_props_acionar_hipoteca(
	casa_id: int
) -> void:
	if (
		hud != null
		and is_instance_valid(hud)
		and hud.has_method("_avisar_hipoteca")
	):
		hud.call(
			"_avisar_hipoteca",
			casa_id
		)
