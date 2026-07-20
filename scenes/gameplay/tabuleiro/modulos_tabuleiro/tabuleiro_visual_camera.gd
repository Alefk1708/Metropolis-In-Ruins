extends "res://scenes/gameplay/tabuleiro/modulos_tabuleiro/tabuleiro_tutorial_bots.gd"

# Módulo: tabuleiro_visual_camera.gd

func _cor_visual_personagem(personagem_id: String) -> Color:
	match personagem_id:
		"breno":
			return cores_grupos["Verde"]
		"mira":
			return cores_grupos["Azul-Escuro"]
		"igor":
			return cores_grupos["Laranja"]
		"diana":
			return cores_grupos["Vermelho"]
		"kofi":
			return cores_grupos["Amarelo"]
		_:
			return cores_grupos["Rosa"]



func _atualizar_alvo_camera_espectador() -> void:
	if not modo_espectador_local:
		return
	var alvo = jogador_atual_id if espectador_auto_seguir else espectador_alvo_id
	if alvo == "" or not pinos_jogadores.has(alvo) or dados_economia_jogadores.get(alvo, {}).get("falido", false):
		for candidato in lista_turnos:
			if pinos_jogadores.has(candidato):
				alvo = candidato
				break
	if alvo == "" or not pinos_jogadores.has(alvo):
		return
	espectador_alvo_id = alvo
	pino_seguido = pinos_jogadores[alvo]
	seguindo_pino = true
	focar_na_casa(pino_seguido.casa_atual)


func _aplicar_zoom(fator: float):
								if not camera: return
								var z = camera.zoom * fator
								# Zoom mínimo dinâmico: garante que a câmera nunca afaste tanto
								# a ponto de mostrar o fundo preto além dos limites da cidade.
								# Fórmula: zoom_min = viewport_pixels / cidade_size_world
								# (viewport em pixels dividido pelo tamanho da cidade em world units)
								var largura_cidade = CIDADE_LIMITE_X * 2.0
								var altura_cidade = CIDADE_LIMITE_Y * 2.0
								var zoom_min_visivel_x = VIEWPORT_LARGURA / largura_cidade
								var zoom_min_visivel_y = VIEWPORT_ALTURA / altura_cidade
								var zoom_min_visivel = max(zoom_min_visivel_x, zoom_min_visivel_y)
								# Usa o maior entre o ZOOM_MIN original e o visivel calculado
								var zoom_min_efetivo = max(ZOOM_MIN.x, zoom_min_visivel)
								z.x = clamp(z.x, zoom_min_efetivo, ZOOM_MAX.x)
								z.y = clamp(z.y, zoom_min_efetivo, ZOOM_MAX.y)
								camera.zoom = z
								# Após mudar o zoom, reposiciona a câmera para que continue
								# dentro dos limites válidos (o zoom pode ter expandido a área visível).
								_limitar_posicao_camera()

# --- NOVO: Claustro a posição da câmera dentro dos limites da cidade para
#     nunca revelar o fundo preto externo. Leva em conta o zoom atual: quanto
#     mais afastado (zoom menor), maior a área visível e menor a faixa onde
#     o centro da câmera pode ficar. ---

func _limitar_posicao_camera():
								if not camera: return
								# Tamanho da área visível em world units (depende do zoom)
								var half_view_w = (VIEWPORT_LARGURA / camera.zoom.x) / 2.0
								var half_view_h = (VIEWPORT_ALTURA / camera.zoom.y) / 2.0
								# Margem máxima que o centro da câmera pode se afastar da origem
								# sem revelar o vazio: limite_da_cidade - metade_do_viewport
								var max_x = CIDADE_LIMITE_X - half_view_w
								var max_y = CIDADE_LIMITE_Y - half_view_h
								# Se o viewport for maior que a cidade (zoom muito pequeno), o centro
								# fica preso na origem — usa max() com 0 para evitar limites negativos.
								max_x = max(max_x, 0.0)
								max_y = max(max_y, 0.0)
								var nova_pos = camera.position
								nova_pos.x = clamp(nova_pos.x, -max_x, max_x)
								nova_pos.y = clamp(nova_pos.y, -max_y, max_y)
								camera.position = nova_pos


func _posicionar_camera_inicio_cinematica() -> void:
	if camera == null:
		return
	camera.position = Vector2.ZERO
	var largura_cidade: float = CIDADE_LIMITE_X * 2.0
	var altura_cidade: float = CIDADE_LIMITE_Y * 2.0
	var zoom_min_visivel: float = max(
		VIEWPORT_LARGURA / largura_cidade,
		VIEWPORT_ALTURA / altura_cidade
	)
	var zoom_inicial: float = max(0.2, zoom_min_visivel)
	camera.zoom = Vector2(zoom_inicial, zoom_inicial)



func _iniciar_cinematica_abertura() -> void:
	if _cinematica_abertura_iniciada or not is_inside_tree():
		return
	_cinematica_abertura_iniciada = true
	_cinematica_abertura_concluida = false
	cinematica_rodando = true
	_posicionar_camera_inicio_cinematica()

	if is_instance_valid(_tween_cinematica_abertura):
		_tween_cinematica_abertura.kill()
	_tween_cinematica_abertura = create_tween()
	_tween_cinematica_abertura.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween_cinematica_abertura.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	_tween_cinematica_abertura.set_trans(Tween.TRANS_SINE)
	_tween_cinematica_abertura.set_ease(Tween.EASE_IN_OUT)
	_tween_cinematica_abertura.tween_interval(1.0)
	if camera != null and tabuleiro.has(0):
		_tween_cinematica_abertura.tween_property(camera, "position", tabuleiro[0]["pos"], 2.0)
		_tween_cinematica_abertura.parallel().tween_property(
			camera,
			"zoom",
			Vector2(1.2, 1.2),
			2.0
		)
	_tween_cinematica_abertura.tween_callback(_concluir_cinematica_abertura)

	# Segundo watchdog, curto e específico do Tween.
	_verificar_tween_cinematica.call_deferred()



func _verificar_tween_cinematica() -> void:
	await get_tree().create_timer(4.5).timeout
	if is_inside_tree() and not _cinematica_abertura_concluida:
		push_warning("[TABULEIRO] A cinemática não concluiu no prazo; finalizando com segurança.")
		_concluir_cinematica_abertura(true)



func _concluir_cinematica_abertura(forcar: bool = false) -> void:
	if _cinematica_abertura_concluida:
		return
	_cinematica_abertura_concluida = true
	cinematica_rodando = false

	if forcar and camera != null and tabuleiro.has(0):
		camera.position = Vector2(tabuleiro[0]["pos"])
		camera.zoom = Vector2(1.2, 1.2)

	var hud_control: Control = null
	if hud != null and is_instance_valid(hud):
		hud_control = hud.get_node_or_null("Control") as Control
	if hud_control == null:
		_notificar_tabuleiro_pronto_tutorial()
		_verificar_permissao_de_clique()
		return

	hud_control.visible = true
	if forcar:
		hud_control.modulate.a = 1.0
		_notificar_tabuleiro_pronto_tutorial()
		_verificar_permissao_de_clique()
		return

	var tween_hud: Tween = create_tween()
	tween_hud.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween_hud.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	tween_hud.set_trans(Tween.TRANS_QUAD)
	tween_hud.set_ease(Tween.EASE_OUT)
	tween_hud.tween_property(hud_control, "modulate:a", 1.0, 0.8)
	tween_hud.tween_callback(_notificar_tabuleiro_pronto_tutorial)
	tween_hud.tween_callback(_verificar_permissao_de_clique)



func _atualizar_visual_dono(casa_id: int):
								var nome_casa = "Casa_" + str(casa_id)
								var camada = get_node_or_null("Camada_02_Predios")
								if not camada or not camada.has_node(nome_casa):
																return
								var node_casa = camada.get_node(nome_casa)
								if not node_casa.has_node("FaixaDono"):
																return
								var faixa = node_casa.get_node("FaixaDono")
								# --- CORREÇÃO: Se a propriedade não tem dono (registro_propriedades
								#     não tem a casa), ESCONDE a faixa visual. Antes, a função
								#     retornava sem fazer nada — a faixa continuava visível com a
								#     cor do falido, fazendo parecer que a prop ainda era dele. ---
								if not registro_propriedades.has(casa_id):
																faixa.visible = false
																return
								var dono_id = registro_propriedades[casa_id]
								faixa.color = cor_por_jogador.get(dono_id, Color.WHITE)
								faixa.visible = true


func _validar_layout_tabuleiro() -> bool:
	for casa_id in range(40):
		if not tabuleiro.has(casa_id):
			return false
		var dados_variant: Variant = tabuleiro[casa_id]
		if not dados_variant is Dictionary:
			return false
		var dados_casa: Dictionary = dados_variant
		if not dados_casa.has("pos") or not dados_casa["pos"] is Vector2:
			return false
	return true



func _garantir_layout_tabuleiro() -> bool:
	if _layout_tabuleiro_pronto and _validar_layout_tabuleiro():
		return true

	# O snapshot pode chegar no mesmo instante em que a cena do convidado ainda
	# está concluindo sua inicialização. Recalcular o layout é determinístico e
	# restaura as chaves `pos`, `camada` e `escala` sem alterar o estado da partida.
	_calcular_espiral()
	_layout_tabuleiro_pronto = _validar_layout_tabuleiro()
	if not _layout_tabuleiro_pronto and not _aviso_layout_tabuleiro_emitido:
		_aviso_layout_tabuleiro_emitido = true
		push_error(
			"[TABULEIRO] Não foi possível reconstruir as posições das 40 casas."
		)
	return _layout_tabuleiro_pronto



func _gerar_cidade_de_fundo():
								const COR_FUNDO = Color(0.05, 0.06, 0.08)
								const COR_PRACA = Color(0.18, 0.40, 0.22)
								const COR_PRACA_DETALHE = Color(0.22, 0.48, 0.28)
								
								var tex_rua = null
								var tex_rua_bifurcacao = null
								var tex_rua_boeiro = null
								var tex_rua_pedestre = null
								var tex_praca_borda = null
								var tex_praca_canto = null
								var tex_praca_interior = null
								var tex_praca_fonte = null
								
								# O chão dos lotes é independente das futuras construções. As peças de
								# topo e canto são rotacionadas para que todas as calçadas se encaixem.
								var tex_base_lote_interior: Texture2D = null
								var tex_base_lote_topo: Texture2D = null
								var tex_base_lote_canto: Texture2D = null
								
								var caminho_rua = "res://assets/textures/fundo/rua.png"
								var caminho_rua_bifurcacao = "res://assets/textures/fundo/rua_bifurcacao.png"
								var caminho_rua_boeiro = "res://assets/textures/fundo/rua_boeiro.png"
								var caminho_rua_pedestre = "res://assets/textures/fundo/rua_pedestre.png"
								var caminho_praca_borda = "res://assets/textures/fundo/calcada_praca_topo.png"
								var caminho_praca_canto = "res://assets/textures/fundo/calcada_praca_canto.png"
								var caminho_praca_interior = "res://assets/textures/fundo/praca_interior.png"
								var caminho_praca_fonte = "res://assets/textures/fundo/praca_centro_fonte.png"
								
								if ResourceLoader.exists(caminho_rua): tex_rua = load(caminho_rua)
								if ResourceLoader.exists(caminho_rua_bifurcacao): tex_rua_bifurcacao = load(caminho_rua_bifurcacao)
								if ResourceLoader.exists(caminho_rua_boeiro): tex_rua_boeiro = load(caminho_rua_boeiro)
								if ResourceLoader.exists(caminho_rua_pedestre): tex_rua_pedestre = load(caminho_rua_pedestre)
								if ResourceLoader.exists(caminho_praca_borda): tex_praca_borda = load(caminho_praca_borda)
								if ResourceLoader.exists(caminho_praca_canto): tex_praca_canto = load(caminho_praca_canto)
								if ResourceLoader.exists(caminho_praca_interior): tex_praca_interior = load(caminho_praca_interior)
								if ResourceLoader.exists(caminho_praca_fonte): tex_praca_fonte = load(caminho_praca_fonte)
								
								if ResourceLoader.exists(CAMINHO_BASE_LOTE_INTERIOR):
																tex_base_lote_interior = load(CAMINHO_BASE_LOTE_INTERIOR) as Texture2D
								if ResourceLoader.exists(CAMINHO_BASE_LOTE_TOPO):
																tex_base_lote_topo = load(CAMINHO_BASE_LOTE_TOPO) as Texture2D
								if ResourceLoader.exists(CAMINHO_BASE_LOTE_CANTO):
																tex_base_lote_canto = load(CAMINHO_BASE_LOTE_CANTO) as Texture2D

								var texturas_base_lote: Dictionary = {
																"interior": tex_base_lote_interior,
																"topo": tex_base_lote_topo,
																"canto": tex_base_lote_canto,
								}
								var texturas_construcoes_cidade: Array[Texture2D] = []
								for caminho_construcao: String in CAMINHOS_CONSTRUCOES_CIDADE:
																if not ResourceLoader.exists(caminho_construcao):
																								continue
																var textura_construcao: Texture2D = load(caminho_construcao) as Texture2D
																if textura_construcao != null:
																								texturas_construcoes_cidade.append(textura_construcao)
								
								var fundo_node: Node2D = get_node_or_null("Camada_Fundo_Cidade") as Node2D
								if fundo_node != null:
																fundo_node.queue_free()
								
								fundo_node = Node2D.new()
								fundo_node.name = "Camada_Fundo_Cidade"
								fundo_node.z_index = -4
								add_child(fundo_node)
								
								var fundo_base: ColorRect = ColorRect.new()
								fundo_base.color = COR_FUNDO
								fundo_base.size = Vector2(15000, 15000)
								fundo_base.position = Vector2(-7500, -7500)
								fundo_base.z_index = -2
								fundo_node.add_child(fundo_base)

								# Os prédios usam a base do sprite como origem do Y-sort. Assim as
								# construções das linhas inferiores cobrem corretamente as que estão atrás.
								var camada_construcoes: Node2D = Node2D.new()
								camada_construcoes.name = "Camada_Construcoes_Cidade"
								camada_construcoes.z_index = 0
								camada_construcoes.y_sort_enabled = true
								fundo_node.add_child(camada_construcoes)
								
								var grid_radius: int = CIDADE_RAIO_GRID
								var tile_size: int = CIDADE_TILE_SIZE
								var mapa_logico: Dictionary = {}
								var rng: RandomNumberGenerator = RandomNumberGenerator.new()
								rng.seed = 12345
								
								var raio_praca: int = 4
								var raio_anel: int = raio_praca + 1
								
								# =========================================================================
								# 1. MAPEAMENTO LÓGICO DA CIDADE
								# =========================================================================
								for x in range(-grid_radius, grid_radius + 1):
																for y in range(-grid_radius, grid_radius + 1):
																								var pos_grid = Vector2i(x, y)
																								
																								if abs(x) <= raio_praca and abs(y) <= raio_praca:
																																mapa_logico[pos_grid] = "praca"
																																continue
																								
																								var is_anel = (abs(x) == raio_anel and abs(y) <= raio_anel) or (abs(y) == raio_anel and abs(x) <= raio_anel)
																								var is_arteria = (x == 0 or y == 0)
																								var is_grade = (x % 5 == 0) or (y % 5 == 0)
																								
																								if is_anel or is_arteria or is_grade:
																																mapa_logico[pos_grid] = "rua"
																								else:
																																mapa_logico[pos_grid] = "lote"
								
								# =========================================================================
								# 1.5 IDENTIFICA BIFURCAÇÕES, PEDESTRES E BOEIROS
								# =========================================================================
								# A textura rua_pedestre.png tem a faixa NO TOPO (rotação = 0).
								# Rotações dos tiles pedestre em relação à bifurcação adjacente:
								#   Tile ABAIXO  → faixa no topo    → 0
								#   Tile ACIMA   → faixa na base    → PI
								#   Tile ESQUERDA→ faixa na direita → PI/2
								#   Tile DIREITA → faixa na esquerda→ -PI/2

								var tiles_pedestre = {}     # Vector2i → float (rotação)
								var tiles_bifurcacao = {}   # Vector2i → info de conexões
								var tiles_boeiro = {}       # Vector2i → float (rotação)
								
								# Primeiro passo: identifica todas as bifurcações
								for pos in mapa_logico.keys():
																if mapa_logico[pos] != "rua": continue
																var conexoes = _contar_conexoes_rua(pos, mapa_logico)
																if conexoes.total >= 3:
																								tiles_bifurcacao[pos] = conexoes
								
								# Segundo passo: marca tiles de pedestre com rotação correta
								for bif_pos in tiles_bifurcacao.keys():
																var conexoes = tiles_bifurcacao[bif_pos]
																
																if conexoes.cima:
																								var pos_anterior = bif_pos + Vector2i(0, -1)
																								if mapa_logico.get(pos_anterior) == "rua" and not tiles_bifurcacao.has(pos_anterior):
																																tiles_pedestre[pos_anterior] = PI
																if conexoes.baixo:
																								var pos_anterior = bif_pos + Vector2i(0, 1)
																								if mapa_logico.get(pos_anterior) == "rua" and not tiles_bifurcacao.has(pos_anterior):
																																tiles_pedestre[pos_anterior] = 0.0
																if conexoes.esquerda:
																								var pos_anterior = bif_pos + Vector2i(-1, 0)
																								if mapa_logico.get(pos_anterior) == "rua" and not tiles_bifurcacao.has(pos_anterior):
																																tiles_pedestre[pos_anterior] = PI / 2.0
																if conexoes.direita:
																								var pos_anterior = bif_pos + Vector2i(1, 0)
																								if mapa_logico.get(pos_anterior) == "rua" and not tiles_bifurcacao.has(pos_anterior):
																																tiles_pedestre[pos_anterior] = -PI / 2.0
								
								# Terceiro passo: boeiros aleatórios em retas (~6% por tile)
								const CHANCE_BOEIRO = 0.1
								for pos in mapa_logico.keys():
																if mapa_logico[pos] != "rua": continue
																if tiles_bifurcacao.has(pos): continue
																if tiles_pedestre.has(pos): continue
																
																var conexoes = _contar_conexoes_rua(pos, mapa_logico)
																var eh_reta_v = conexoes.cima and conexoes.baixo and not conexoes.esquerda and not conexoes.direita
																var eh_reta_h = conexoes.esquerda and conexoes.direita and not conexoes.cima and not conexoes.baixo
																
																if (eh_reta_v or eh_reta_h) and rng.randf() < CHANCE_BOEIRO:
																								tiles_boeiro[pos] = PI / 2.0 if eh_reta_h else 0.0
								
								# =========================================================================
								# 2. RENDERIZAÇÃO DOS BLOCOS BASE
								# =========================================================================
								for pos in mapa_logico.keys():
																var tipo = mapa_logico[pos]
																var world_pos = Vector2(pos.x, pos.y) * tile_size
																var cor_base = COR_FUNDO
																
																match tipo:
																								"praca":
																																var abs_x: int = abs(pos.x)
																																var abs_y: int = abs(pos.y)
																																var eh_centro: bool = (pos.x == 0 and pos.y == 0)
																																var eh_borda: bool = (abs_x == raio_praca or abs_y == raio_praca)
																																var eh_canto: bool = (abs_x == raio_praca and abs_y == raio_praca)
																																
																																var tex_a_usar = null
																																var rotacao: float = 0.0
																																
																																if eh_centro and tex_praca_fonte:
																																								tex_a_usar = tex_praca_fonte
																																								rotacao = 0.0
																																elif eh_canto and tex_praca_canto:
																																								tex_a_usar = tex_praca_canto
																																								if pos.x > 0 and pos.y < 0: rotacao = 0.0
																																								elif pos.x > 0 and pos.y > 0: rotacao = PI / 2.0
																																								elif pos.x < 0 and pos.y > 0: rotacao = PI
																																								elif pos.x < 0 and pos.y < 0: rotacao = -PI / 2.0
																																elif eh_borda and tex_praca_borda:
																																								tex_a_usar = tex_praca_borda
																																								if pos.y == -raio_praca: rotacao = 0.0
																																								elif pos.x == raio_praca: rotacao = PI / 2.0
																																								elif pos.y == raio_praca: rotacao = PI
																																								elif pos.x == -raio_praca: rotacao = -PI / 2.0
																																elif tex_praca_interior:
																																								tex_a_usar = tex_praca_interior
																																								rotacao = 0.0
																																
																																if tex_a_usar:
																																								var sprite = Sprite2D.new()
																																								sprite.texture = tex_a_usar
																																								var escala = tile_size / float(tex_a_usar.get_width())
																																								sprite.scale = Vector2(escala, escala)
																																								sprite.position = world_pos
																																								sprite.rotation = rotacao
																																								sprite.z_index = -1
																																								fundo_node.add_child(sprite)
																																else:
																																								cor_base = COR_PRACA if rng.randf() > 0.3 else COR_PRACA_DETALHE
																																								_criar_bloco(fundo_node, world_pos, tile_size, cor_base, -4.0)
																																continue
																																
																								"rua":
																																var tex_a_usar = null
																																var rotacao: float = 0.0
																																
																																# Faixa de pedestre — rotação aponta para a bifurcação adjacente
																																if tiles_pedestre.has(pos):
																																								tex_a_usar = tex_rua_pedestre
																																								rotacao = tiles_pedestre[pos]
																																
																																# Bifurcação (T ou +)
																																elif tiles_bifurcacao.has(pos):
																																								tex_a_usar = tex_rua_bifurcacao
																																								rotacao = _calcular_rotacao_bifurcacao(tiles_bifurcacao[pos])
																																
																																# Boeiro aleatório em reta
																																elif tiles_boeiro.has(pos):
																																								tex_a_usar = tex_rua_boeiro
																																								rotacao = tiles_boeiro[pos]
																																
																																# Reta ou curva
																																else:
																																								var conexoes = _contar_conexoes_rua(pos, mapa_logico)
																																								
																																								if conexoes.total <= 1:
																																																tex_a_usar = tex_rua_boeiro
																																																if conexoes.esquerda or conexoes.direita:
																																																								rotacao = PI / 2.0
																																								elif conexoes.cima and conexoes.baixo and not conexoes.esquerda and not conexoes.direita:
																																																tex_a_usar = tex_rua
																																																rotacao = 0.0
																																								elif conexoes.esquerda and conexoes.direita and not conexoes.cima and not conexoes.baixo:
																																																tex_a_usar = tex_rua
																																																rotacao = PI / 2.0
																																								else:
																																																tex_a_usar = tex_rua
																																																if conexoes.cima and conexoes.direita: rotacao = 0.0
																																																elif conexoes.direita and conexoes.baixo: rotacao = PI / 2.0
																																																elif conexoes.baixo and conexoes.esquerda: rotacao = PI
																																																elif conexoes.esquerda and conexoes.cima: rotacao = -PI / 2.0
																																																else: rotacao = 0.0
																																
																																if tex_a_usar:
																																								var sprite = Sprite2D.new()
																																								sprite.texture = tex_a_usar
																																								var escala = tile_size / float(tex_a_usar.get_width())
																																								sprite.scale = Vector2(escala, escala)
																																								sprite.position = world_pos
																																								sprite.rotation = rotacao
																																								sprite.z_index = -1
																																								fundo_node.add_child(sprite)
																																else:
																																								_criar_bloco(fundo_node, world_pos, tile_size, Color(0.22, 0.23, 0.25), -1.0)
																																continue
																																
																								# Cada lote recebe primeiro a base rotacionada e sempre uma
																								# construção sem rotação, ancorada pela entrada na parte baixa do lote.
																								"lote":
																										var info_tile: Dictionary = _classificar_variante_base_cidade(pos, mapa_logico)
																										var variante: String = str(info_tile.get("variante", "interior"))
																										var rotacao_tile: float = float(info_tile.get("rotacao", 0.0))
																										var textura_variant: Variant = texturas_base_lote.get(variante)
																										if textura_variant is Texture2D:
																												var textura_base: Texture2D = textura_variant as Texture2D
																												var sprite_base: Sprite2D = Sprite2D.new()
																												sprite_base.texture = textura_base
																												var escala_base: float = tile_size / float(textura_base.get_width())
																												sprite_base.scale = Vector2(escala_base, escala_base)
																												sprite_base.position = world_pos
																												sprite_base.rotation = rotacao_tile
																												sprite_base.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
																												sprite_base.z_index = -1
																												fundo_node.add_child(sprite_base)
																										else:
																												_criar_bloco(fundo_node, world_pos, tile_size, Color(0.48, 0.49, 0.51), 0.0)

																										if not texturas_construcoes_cidade.is_empty():
																												var indice_construcao: int = _obter_indice_construcao_cidade(pos, texturas_construcoes_cidade.size())
																												if indice_construcao >= 0:
																														var textura_predio: Texture2D = texturas_construcoes_cidade[indice_construcao]
																														var largura_textura: float = float(textura_predio.get_width())
																														var altura_textura: float = float(textura_predio.get_height())
																														if largura_textura > 0.0 and altura_textura > 0.0:
																																var escala_largura: float = (float(tile_size) * LARGURA_RELATIVA_CONSTRUCAO_CIDADE) / largura_textura
																																var escala_altura: float = (float(tile_size) * ALTURA_MAXIMA_RELATIVA_CONSTRUCAO_CIDADE) / altura_textura
																																var escala_predio: float = minf(escala_largura, escala_altura)
																																var sprite_predio: Sprite2D = Sprite2D.new()
																																sprite_predio.texture = textura_predio
																																sprite_predio.scale = Vector2(escala_predio, escala_predio)
																																sprite_predio.offset = Vector2(0.0, -altura_textura / 2.0)
																																sprite_predio.rotation = 0.0
																																sprite_predio.position = world_pos + Vector2(0.0, roundf(float(tile_size) * OFFSET_BASE_RELATIVO_CONSTRUCAO_CIDADE))
																																sprite_predio.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
																																sprite_predio.z_index = 0
																																camada_construcoes.add_child(sprite_predio)


# Mantém a mesma ocupação e a mesma escolha de sprites em todas as máquinas,
# inclusive no modo online, sem depender da ordem interna de um Dictionary.

func _hash_posicao_construcao_cidade(pos: Vector2i, sal: int) -> int:
	var valor: int = pos.x * 92837111
	valor = valor ^ (pos.y * 689287499)
	valor = valor ^ (sal * 283923481)
	valor = valor ^ (valor >> 13)
	return valor * 127412617



func _modulo_positivo_cidade(valor: int, divisor: int) -> int:
	if divisor <= 0:
		return 0
	var resultado: int = valor % divisor
	if resultado < 0:
		resultado += divisor
	return resultado



func _obter_indice_construcao_cidade(pos: Vector2i, quantidade: int) -> int:
	if quantidade <= 0:
		return -1
	return _modulo_positivo_cidade(_hash_posicao_construcao_cidade(pos, 29), quantidade)


# ============================================================================
# FUNÇÕES DE ANÁLISE DE RUA
# ============================================================================

func _classificar_variante_base_cidade(pos: Vector2i, mapa: Dictionary) -> Dictionary:
								var tem_rua_cima: bool = _eh_rua_ou_praca(mapa.get(pos + Vector2i(0, -1)))
								var tem_rua_baixo: bool = _eh_rua_ou_praca(mapa.get(pos + Vector2i(0, 1)))
								var tem_rua_esquerda: bool = _eh_rua_ou_praca(mapa.get(pos + Vector2i(-1, 0)))
								var tem_rua_direita: bool = _eh_rua_ou_praca(mapa.get(pos + Vector2i(1, 0)))
								
								var variante: String = "interior"
								var rotacao: float = 0.0
								
								# Conta quantos lados tem rua/praca
								var lados_com_rua: int = 0
								if tem_rua_cima: lados_com_rua += 1
								if tem_rua_baixo: lados_com_rua += 1
								if tem_rua_esquerda: lados_com_rua += 1
								if tem_rua_direita: lados_com_rua += 1
								
								if lados_com_rua == 0:
																# Miolo da quadra: base sólida, sem calçada.
																variante = "interior"
																rotacao = 0.0
								elif lados_com_rua == 1:
																# Apenas 1 rua adjacente → variante TOPO
																variante = "topo"
																if tem_rua_cima:
																								rotacao = 0.0
																elif tem_rua_direita:
																								rotacao = PI / 2.0
																elif tem_rua_baixo:
																								rotacao = PI
																elif tem_rua_esquerda:
																								rotacao = -PI / 2.0
								else:
																# 2+ ruas adjacentes → variante CANTO
																# Procura por um par de ruas adjacentes (formando um canto).
																# Prioriza NE > SE > SW > NW para consistência visual.
																variante = "canto"
																if tem_rua_cima and tem_rua_direita:
																								rotacao = 0.0          # Canto NE
																elif tem_rua_direita and tem_rua_baixo:
																								rotacao = PI / 2.0      # Canto SE
																elif tem_rua_baixo and tem_rua_esquerda:
																								rotacao = PI            # Canto SW
																elif tem_rua_esquerda and tem_rua_cima:
																								rotacao = -PI / 2.0     # Canto NW
																else:
																								# Casos especiais: 2 lados opostos (passagem) ou 3+ lados.
																								# Para passagem (N+S ou E+W): usa TOPO voltado para o norte ou leste.
																								# Para 3+ lados: usa CANTO no primeiro par encontrado.
																								if tem_rua_cima and tem_rua_baixo and not tem_rua_esquerda and not tem_rua_direita:
																																variante = "topo"
																																rotacao = 0.0
																								elif tem_rua_esquerda and tem_rua_direita and not tem_rua_cima and not tem_rua_baixo:
																																variante = "topo"
																																rotacao = PI / 2.0
																								elif tem_rua_cima:
																																variante = "topo"
																																rotacao = 0.0
																								elif tem_rua_direita:
																																variante = "topo"
																																rotacao = PI / 2.0
																								elif tem_rua_baixo:
																																variante = "topo"
																																rotacao = PI
																								elif tem_rua_esquerda:
																																variante = "topo"
																																rotacao = -PI / 2.0
								
								return {"variante": variante, "rotacao": rotacao}


# Helper: verifica se um valor do mapa_logico representa uma área pública
# (rua ou praça) que exige calçada na borda do lote.
# Tiles fora do mapa (null) também são tratados como "rua" para que os
# lotes nas bordas externas da cidade tenham calçada voltada para fora.

func _atualizar_imagem_construcao(casa_id: int):
	if not tabuleiro.has(casa_id):
		return
	var dados = tabuleiro[casa_id]
	if dados.get("tipo", "") != "propriedade":
		return
	var nome_casa = "Casa_" + str(casa_id)
	var camada = get_node_or_null("Camada_02_Predios")
	if not camada or not camada.has_node(nome_casa):
		return
	var node_casa = camada.get_node(nome_casa)
	if not node_casa.has_node("ContainerConstrucao/SpriteConstrucao"):
		return
	var sprite_construcao = node_casa.get_node("ContainerConstrucao/SpriteConstrucao")
	var nivel = int(dados.get("nivel", 0))
	if nivel <= 0:
		sprite_construcao.visible = false
		sprite_construcao.texture = null
		return
	var caminho_imagem = CAMINHO_SPRITE_CONSTRUCAO_BASE + str(clamp(nivel, 1, 5)) + ".png"
	if ResourceLoader.exists(caminho_imagem):
		var tex = load(caminho_imagem)
		if tex:
			sprite_construcao.texture = tex
			sprite_construcao.visible = true
	else:
		sprite_construcao.visible = false
		sprite_construcao.texture = null
