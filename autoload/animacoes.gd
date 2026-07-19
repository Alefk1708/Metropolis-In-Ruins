extends Node

# ============================================================================
# METROPOLIS IN RUINS — BIBLIOTECA CENTRAL DE ANIMAÇÕES
# ============================================================================
# Singleton autoload (registrado em project.godot como "Animacoes").
# Centraliza todos os efeitos visuais reutilizáveis do jogo para que o
# tabuleiro, o pino e a HUD possam chamá-los sem duplicar código.
# ============================================================================

# Cache de fontes pixel-art usadas nos efeitos flutuantes
var _fonte_pixel: FontFile = null
var _fonte_grande: FontFile = null

func _ready() -> void:
				# Carrega fontes pixel uma única vez para reutilizar em todos os efeitos
				if ResourceLoader.exists("res://assets/fonts/PressStart2P.ttf"):
								_fonte_pixel = load("res://assets/fonts/PressStart2P.ttf")
				if ResourceLoader.exists("res://assets/fonts/m5x7.ttf"):
								_fonte_grande = load("res://assets/fonts/m5x7.ttf")

# ============================================================================
# 1. TEXTO FLUTUANTE — sobe e desaparece (em qualquer Node2D)
# ============================================================================
func texto_flutuante(no_pai: Node2D, pos: Vector2, texto: String, cor: Color, tamanho: int = 28, duracao: float = 1.5) -> void:
				var lbl = Label.new()
				lbl.text = texto
				lbl.add_theme_color_override("font_color", cor)
				lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
				lbl.add_theme_constant_override("outline_size", 6)
				lbl.add_theme_font_size_override("font_size", tamanho)
				if _fonte_pixel:
								lbl.add_theme_font_override("font", _fonte_pixel)
				lbl.custom_minimum_size = Vector2(200, 36)
				lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				lbl.position = pos - Vector2(100, 18)
				lbl.z_index = 200
				no_pai.add_child(lbl)
				
				var tween = no_pai.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				tween.tween_property(lbl, "position", lbl.position + Vector2(0, -60), duracao)
				tween.parallel().tween_property(lbl, "modulate:a", 0.0, duracao)
				tween.tween_callback(lbl.queue_free)

# ============================================================================
# 2. PULSO DE COR — pisca um Control com uma cor e volta ao normal
# ============================================================================
func pulso_de_cor(control: Control, cor: Color, vezes: int = 3, intervalo: float = 0.18) -> void:
				if not is_instance_valid(control):
								return
				var cor_original = control.modulate
				var tween = control.create_tween().set_loops(vezes)
				tween.tween_property(control, "modulate", cor, intervalo)
				tween.tween_property(control, "modulate", cor_original, intervalo)

# ============================================================================
# 3. TREMOR DE TELA — screen shake para a câmera 2D
# ============================================================================
# --- BUG FIX (CRITICAL #5): Antes, tremer_camera capturava pos_original =
#     camera.position e restaurava no final. Mas o _process do tabuleiro move
#     camera.position continuamente (seguindo o pino). Os dois sistemas
#     competiam: o tremor tentava colocar a câmera em posições aleatórias,
#     o _process puxava de volta. Resultado: tremor quase invisível durante
#     o movimento, e "salto" para posição desatualizada ao terminar.
#     SOLUÇÃO: usar camera.offset (propriedade nativa da Camera2D) em vez de
#     camera.position. O offset é ADICIONADO à posição final, sem competir
#     com o _process. Após o tremor, offset volta a Vector2.ZERO. ---
func tremer_camera(camera: Camera2D, intensidade: float = 6.0, duracao: float = 0.4) -> void:
				if not is_instance_valid(camera):
								return
				var offset_original = camera.offset
				var tween = camera.create_tween()
				var passos = int(duracao / 0.04)
				for i in range(passos):
								var decay = 1.0 - float(i) / float(passos)
								var shake_offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * intensidade * decay
								tween.tween_property(camera, "offset", offset_original + shake_offset, 0.04)
				tween.tween_property(camera, "offset", offset_original, 0.05)


# ============================================================================
# 4. FLASH DE TELA — overlay branco/colorido que aparece e some
# ============================================================================
func flash_de_tela(no_pai: Node, cor: Color, duracao: float = 0.4) -> void:
				var overlay = ColorRect.new()
				overlay.color = cor
				overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
				overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
				overlay.modulate.a = 0.0
				no_pai.add_child(overlay)
				
				var tween = overlay.create_tween().set_trans(Tween.TRANS_QUAD)
				tween.tween_property(overlay, "modulate:a", 0.75, duracao * 0.3)
				tween.tween_property(overlay, "modulate:a", 0.0, duracao * 0.7)
				tween.tween_callback(overlay.queue_free)

# ============================================================================
# 5. BANNER CINEMÁTICO — desliza de cima, fica, e desliza de volta
# Usado para eventos globais, falência, vitória, monopólio.
# ============================================================================
func banner_cinematico(no_pai: Node, titulo: String, subtitulo: String, cor_titulo: Color, duracao_exibicao: float = 2.5) -> void:
				# --- CORREÇÃO: Tamanho FIXO padronizado para todos os banners ---
				# Sempre o mesmo tamanho independente do conteúdo, garantindo centralização perfeita.
				var viewport_size: Vector2
				if no_pai is Control:
								viewport_size = (no_pai as Control).size
				elif no_pai is Node2D:
								viewport_size = no_pai.get_viewport_rect().size
				else:
								viewport_size = Vector2(1920, 1080)

				# Tamanho fixo padrão (não muda conforme o conteúdo)
				var largura_banner = min(900, viewport_size.x - 80)
				var altura_banner = 220
				# Centraliza horizontalmente
				var pos_x = (viewport_size.x - largura_banner) / 2.0
				var pos_y_inicial = -altura_banner - 20  # Começa acima da tela
				var pos_y_final = 60  # Posição final (topo)

				# --- Usa Panel (não PanelContainer) para ter tamanho FIXO que não expande ---
				var root = Panel.new()
				root.size = Vector2(largura_banner, altura_banner)
				root.custom_minimum_size = Vector2(largura_banner, altura_banner)
				root.position = Vector2(pos_x, pos_y_inicial)
				root.z_index = 500
				root.mouse_filter = Control.MOUSE_FILTER_IGNORE
				root.clip_contents = true  # Impede que o conteúdo extravase o tamanho fixo

				var sb = StyleBoxFlat.new()
				sb.bg_color = Color(0.04, 0.04, 0.06, 0.97)
				sb.border_width_left = 6
				sb.border_width_right = 6
				sb.border_width_top = 6
				sb.border_width_bottom = 6
				sb.border_color = cor_titulo
				sb.corner_radius_top_left = 12
				sb.corner_radius_top_right = 12
				sb.corner_radius_bottom_left = 12
				sb.corner_radius_bottom_right = 12
				sb.content_margin_left = 40
				sb.content_margin_right = 40
				sb.content_margin_top = 30
				sb.content_margin_bottom = 30
				root.add_theme_stylebox_override("panel", sb)

				# VBoxContainer que preenche TODO o Panel, com tamanho fixo
				var vbox = VBoxContainer.new()
				vbox.position = Vector2(40, 30)  # Margem interna
				vbox.size = Vector2(largura_banner - 80, altura_banner - 60)
				vbox.alignment = BoxContainer.ALIGNMENT_CENTER
				vbox.add_theme_constant_override("separation", 16)
				vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
				root.add_child(vbox)

				# --- Título com tamanho fixo e clip ---
				var lbl_titulo = Label.new()
				lbl_titulo.text = titulo
				lbl_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				lbl_titulo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				lbl_titulo.add_theme_color_override("font_color", cor_titulo)
				lbl_titulo.add_theme_color_override("font_outline_color", Color.BLACK)
				lbl_titulo.add_theme_constant_override("outline_size", 8)
				lbl_titulo.add_theme_font_size_override("font_size", 32)
				lbl_titulo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				lbl_titulo.custom_minimum_size = Vector2(largura_banner - 80, 60)
				lbl_titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				lbl_titulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
				if _fonte_pixel:
								lbl_titulo.add_theme_font_override("font", _fonte_pixel)
				vbox.add_child(lbl_titulo)

				# --- Subtítulo com tamanho fixo e clip ---
				var lbl_sub = Label.new()
				lbl_sub.text = subtitulo
				lbl_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				lbl_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				lbl_sub.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92))
				lbl_sub.add_theme_color_override("font_outline_color", Color.BLACK)
				lbl_sub.add_theme_constant_override("outline_size", 5)
				lbl_sub.add_theme_font_size_override("font_size", 16)
				lbl_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				lbl_sub.custom_minimum_size = Vector2(largura_banner - 80, 80)
				lbl_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				lbl_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
				if _fonte_pixel:
								lbl_sub.add_theme_font_override("font", _fonte_pixel)
				vbox.add_child(lbl_sub)

				no_pai.add_child(root)

				# Força o tamanho a permanecer fixo após adicionar à árvore
				root.size = Vector2(largura_banner, altura_banner)

				# Entra — desliza de cima para a posição final centralizada
				var tween_in = root.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tween_in.tween_property(root, "position", Vector2(pos_x, pos_y_final), 0.7)

				# Espera. A cena pode ser trocada enquanto o banner está visível
				# (por exemplo, ao desistir da partida), então guardamos a árvore
				# e validamos o nó novamente antes de iniciar a animação de saída.
				var arvore := no_pai.get_tree()
				if arvore == null:
					if is_instance_valid(root):
						root.queue_free()
					return
				await arvore.create_timer(duracao_exibicao).timeout

				if not is_instance_valid(root) or not root.is_inside_tree():
					return

				# Sai — desliza de volta para cima
				var tween_out = root.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				tween_out.tween_property(root, "position", Vector2(pos_x, pos_y_inicial), 0.5)
				tween_out.tween_callback(root.queue_free)

# ============================================================================
# 6. TRANSFERÊNCIA DE MOEDAS — partículas que voam do pagador ao receptor
# ============================================================================
func transferencia_moedas(no_pai: Node2D, origem: Vector2, destino: Vector2, cor: Color = Color(1, 0.85, 0.15), qtd: int = 8) -> void:
				for i in range(qtd):
								var moeda = Panel.new()
								moeda.size = Vector2(18, 18)
								moeda.position = origem - Vector2(9, 9)
								moeda.z_index = 250
								var sb = StyleBoxFlat.new()
								sb.bg_color = cor
								sb.corner_radius_top_left = 9
								sb.corner_radius_top_right = 9
								sb.corner_radius_bottom_left = 9
								sb.corner_radius_bottom_right = 9
								sb.border_width_left = 2
								sb.border_width_right = 2
								sb.border_width_top = 2
								sb.border_width_bottom = 2
								sb.border_color = Color(0.6, 0.45, 0.05)
								moeda.add_theme_stylebox_override("panel", sb)
								no_pai.add_child(moeda)
								
								# Arco com pequeno atraso entre cada moeda para parecer uma rajada
								var meio = (origem + destino) / 2.0 + Vector2(randf_range(-40, 40), -80)
								var tween = moeda.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
								# Delay inicial entre moedas (Godot 4: tween_interval, não set_delay)
								tween.tween_interval(i * 0.04)
								tween.tween_property(moeda, "position", meio - Vector2(9, 9), 0.25)
								tween.tween_property(moeda, "position", destino - Vector2(9, 9), 0.25)
								tween.tween_property(moeda, "scale", Vector2(0.1, 0.1), 0.15)
								tween.tween_callback(moeda.queue_free)

# ============================================================================
# 7. EXPLOSÃO DE PARTÍCULAS — burst circular de quadradinhos coloridos
# ============================================================================
func explosao_particulas(no_pai: Node2D, centro: Vector2, cor: Color, qtd: int = 14, raio: float = 80.0) -> void:
				for i in range(qtd):
								var p = Panel.new()
								p.size = Vector2(8, 8)
								p.position = centro - Vector2(4, 4)
								p.z_index = 240
								var sb = StyleBoxFlat.new()
								sb.bg_color = cor
								p.add_theme_stylebox_override("panel", sb)
								no_pai.add_child(p)
								
								var angulo = (float(i) / float(qtd)) * TAU
								var destino = centro + Vector2(cos(angulo), sin(angulo)) * raio
								var tween = p.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
								tween.tween_property(p, "position", destino - Vector2(4, 4), 0.5)
								tween.parallel().tween_property(p, "modulate:a", 0.0, 0.5)
								tween.tween_callback(p.queue_free)

# ============================================================================
# 8. EFEITO DE CONSTRUÇÃO — sobe do chão com poeira
# ============================================================================
func construcao_surge(no_pai: Node2D, alvo: Node2D) -> void:
				if not is_instance_valid(alvo):
								return
				var pos = alvo.position
				# Poeira
				for i in range(6):
								var poeira = Panel.new()
								poeira.size = Vector2(10, 10)
								poeira.position = pos + Vector2(randf_range(-20, 20), randf_range(-5, 5)) - Vector2(5, 5)
								poeira.z_index = 220
								poeira.modulate = Color(0.7, 0.6, 0.45, 0.8)
								no_pai.add_child(poeira)
								var tween = poeira.create_tween().set_trans(Tween.TRANS_QUAD)
								tween.tween_property(poeira, "position", poeira.position + Vector2(randf_range(-30, 30), -40), 0.6)
								tween.parallel().tween_property(poeira, "modulate:a", 0.0, 0.6)
								tween.tween_callback(poeira.queue_free)
				# Alvo escala
				var escala_original = alvo.scale
				alvo.scale = Vector2(0.1, 0.1)
				var t = alvo.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				t.tween_property(alvo, "scale", escala_original, 0.5)

# ============================================================================
# 8a. APARIÇÃO SUAVE DA CONSTRUÇÃO — executada após a obra terminar
# ============================================================================
func construcao_aparecer_suave(alvo: Node2D, duracao: float = 0.42) -> void:
	if not is_instance_valid(alvo):
		return

	var posicao_final = alvo.position
	var escala_final = alvo.scale
	var modulate_final = alvo.modulate

	# Entrada curta: sobe poucos pixels, cresce discretamente e ganha opacidade.
	alvo.position = posicao_final + Vector2(0, 12)
	alvo.scale = escala_final * 0.88
	alvo.modulate = Color(modulate_final.r, modulate_final.g, modulate_final.b, 0.0)

	var tween = alvo.create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(alvo, "position", posicao_final, duracao)
	tween.tween_property(alvo, "scale", escala_final, duracao).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(alvo, "modulate:a", modulate_final.a, duracao * 0.78)
	await tween.finished

	if is_instance_valid(alvo):
		alvo.position = posicao_final
		alvo.scale = escala_final
		alvo.modulate = modulate_final

# ============================================================================
# 8b. NOVO: ANIMAÇÃO DE CONSTRUÇÃO COMPLETA — andaimes + marteladas + barra de progresso
# ============================================================================
func animacao_construcao_completa(no_pai: Node2D, pos: Vector2, cor: Color, duracao: float = 1.5) -> void:
				# Container principal para tudo desaparecer de uma vez
				var container = Node2D.new()
				container.z_index = 230
				no_pai.add_child(container)

				# --- 1. ANDAIMES (estrutura de construction) ---
				# Cria 4 postes verticais (2 em cada lado) + 2 horizontais
				var andaimes: Array = []
				var largura_obra = 80
				var altura_obra = 100

				# Postes verticais (amarelos escuros, como madeira)
				for i in range(2):
								var poste = Panel.new()
								poste.size = Vector2(6, altura_obra)
								poste.position = pos + Vector2(-largura_obra/2 + i * (largura_obra - 6), -altura_obra)
								poste.modulate.a = 0.0
								var sb = StyleBoxFlat.new()
								sb.bg_color = Color(0.55, 0.4, 0.15)
								sb.border_width_left = 1
								sb.border_width_right = 1
								sb.border_color = Color(0.3, 0.2, 0.05)
								poste.add_theme_stylebox_override("panel", sb)
								container.add_child(poste)
								andaimes.append(poste)

				# Travessas horizontais
				for i in range(2):
								var trave = Panel.new()
								trave.size = Vector2(largura_obra, 5)
								trave.position = pos + Vector2(-largura_obra/2, -altura_obra + 20 + i * 40)
								trave.modulate.a = 0.0
								var sb2 = StyleBoxFlat.new()
								sb2.bg_color = Color(0.55, 0.4, 0.15)
								sb2.border_width_top = 1
								sb2.border_width_bottom = 1
								sb2.border_color = Color(0.3, 0.2, 0.05)
								trave.add_theme_stylebox_override("panel", sb2)
								container.add_child(trave)
								andaimes.append(trave)

				# Cruzeta de X (símbolo clássico de obra)
				var cruz = Panel.new()
				cruz.size = Vector2(largura_obra, 4)
				cruz.position = pos + Vector2(-largura_obra/2, -altura_obra/2)
				cruz.modulate.a = 0.0
				cruz.rotation_degrees = 30
				var sb_cruz = StyleBoxFlat.new()
				sb_cruz.bg_color = Color(0.95, 0.75, 0.1)
				cruz.add_theme_stylebox_override("panel", sb_cruz)
				container.add_child(cruz)
				andaimes.append(cruz)

				# Fade in dos andaimes
				for andaime in andaimes:
								var t_in = andaime.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
								t_in.tween_property(andaime, "modulate:a", 1.0, 0.2)

				# --- 2. BARRA DE PROGRESSO no topo ---
				var barra_fundo = Panel.new()
				barra_fundo.size = Vector2(100, 12)
				barra_fundo.position = pos + Vector2(-50, -altura_obra - 25)
				barra_fundo.modulate.a = 0.0
				var sb_bg = StyleBoxFlat.new()
				sb_bg.bg_color = Color(0.1, 0.1, 0.1, 0.9)
				sb_bg.border_width_left = 2
				sb_bg.border_width_right = 2
				sb_bg.border_width_top = 2
				sb_bg.border_width_bottom = 2
				sb_bg.border_color = Color(0.4, 0.4, 0.4)
				barra_fundo.add_theme_stylebox_override("panel", sb_bg)
				container.add_child(barra_fundo)

				var barra_preench = Panel.new()
				barra_preench.size = Vector2(0, 8)
				barra_preench.position = pos + Vector2(-48, -altura_obra - 23)
				var sb_fill = StyleBoxFlat.new()
				sb_fill.bg_color = cor
				barra_preench.add_theme_stylebox_override("panel", sb_fill)
				container.add_child(barra_preench)

				# Label "CONSTRUINDO..."
				var lbl_obra = Label.new()
				lbl_obra.text = "CONSTRUINDO"
				# --- BUG FIX (HIGH #27): Usar _fonte_pixel (pré-carregada com checagem)
				#     em vez de load() direto. Evita erro se o arquivo não existir. ---
				if _fonte_pixel:
								lbl_obra.add_theme_font_override("font", _fonte_pixel)
				lbl_obra.add_theme_font_size_override("font_size", 9)
				lbl_obra.add_theme_color_override("font_color", Color(0.95, 0.75, 0.1))
				lbl_obra.add_theme_color_override("font_outline_color", Color.BLACK)
				lbl_obra.add_theme_constant_override("outline_size", 4)
				lbl_obra.position = pos + Vector2(-50, -altura_obra - 50)
				lbl_obra.modulate.a = 0.0
				container.add_child(lbl_obra)

				# Anima os elementos de UI entrando
				var t_ui = barra_fundo.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				t_ui.tween_property(barra_fundo, "modulate:a", 1.0, 0.2)
				var t_lbl = lbl_obra.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				t_lbl.tween_property(lbl_obra, "modulate:a", 1.0, 0.2)

				# --- 3. MARTelADAS (pequenos blocos que sobem e descem) ---
				for i in range(4):
								var martelo = Panel.new()
								martelo.size = Vector2(8, 12)
								martelo.position = pos + Vector2(randf_range(-30, 30), -altura_obra - 15)
								var sb_m = StyleBoxFlat.new()
								sb_m.bg_color = Color(0.8, 0.7, 0.5)
								martelo.add_theme_stylebox_override("panel", sb_m)
								container.add_child(martelo)

								# Faz o martelo "bater" — sobe e desce em loop, com delay entre martelos
								var t_martelo = martelo.create_tween().set_loops(3)
								# Delay inicial antes das marteladas começarem (Godot 4: tween_interval)
								t_martelo.tween_interval(i * 0.1)
								t_martelo.tween_property(martelo, "position:y", martelo.position.y - 15, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
								t_martelo.tween_property(martelo, "position:y", martelo.position.y, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

				# --- 4. POEIRA contínua durante a obra ---
				for i in range(8):
								var poeira = Panel.new()
								poeira.size = Vector2(randf_range(8, 14), randf_range(8, 14))
								poeira.position = pos + Vector2(randf_range(-40, 40), randf_range(-10, 10)) - Vector2(5, 5)
								poeira.modulate = Color(0.7, 0.6, 0.45, 0.8)
								container.add_child(poeira)
								var t_poeira = poeira.create_tween().set_trans(Tween.TRANS_QUAD)
								# Delay entre cada nuvem de poeira (Godot 4: tween_interval)
								t_poeira.tween_interval(i * 0.15)
								t_poeira.tween_property(poeira, "position", poeira.position + Vector2(randf_range(-20, 20), -50), 0.8)
								t_poeira.parallel().tween_property(poeira, "modulate:a", 0.0, 0.8)
								t_poeira.tween_callback(poeira.queue_free)

				# --- 5. PREENCHE A BARRA DE PROGRESSO ---
				var t_barra = barra_preench.create_tween().set_trans(Tween.TRANS_LINEAR)
				t_barra.tween_property(barra_preench, "size:x", 96.0, duracao * 0.8)

				# --- 6. Quando a barra enche, remove os andaimes com fade out ---
				await no_pai.get_tree().create_timer(duracao * 0.85).timeout

				# Fade out dos andaimes
				for andaime in andaimes:
								if is_instance_valid(andaime):
												var t_out = andaime.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
												t_out.tween_property(andaime, "modulate:a", 0.0, 0.25)
				var t_bg_out = barra_fundo.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				t_bg_out.tween_property(barra_fundo, "modulate:a", 0.0, 0.25)
				var t_fill_out = barra_preench.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				t_fill_out.tween_property(barra_preench, "modulate:a", 0.0, 0.25)
				var t_lbl_out = lbl_obra.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				t_lbl_out.tween_property(lbl_obra, "modulate:a", 0.0, 0.25)

				# --- 7. BURST FINAL de poeira quando o prédio "sobe" ---
				await no_pai.get_tree().create_timer(0.3).timeout
				for i in range(10):
								var p = Panel.new()
								p.size = Vector2(randf_range(8, 16), randf_range(8, 16))
								p.position = pos + Vector2(randf_range(-30, 30), 0) - Vector2(5, 5)
								p.modulate = Color(0.8, 0.7, 0.5, 0.9)
								container.add_child(p)
								var angulo = randf_range(-PI, 0)  # Para cima
								var destino = p.position + Vector2(cos(angulo), sin(angulo)) * randf_range(40, 80)
								var t_p = p.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
								t_p.tween_property(p, "position", destino, 0.6)
								t_p.parallel().tween_property(p, "modulate:a", 0.0, 0.6)
								t_p.tween_callback(p.queue_free)

				# Remove o container inteiro
				await no_pai.get_tree().create_timer(0.7).timeout
				if is_instance_valid(container):
								container.queue_free()

# ============================================================================
# 9. TELA DE FIM DE JOGO — vitória ou falência
# ============================================================================
func _no_visual_animacao_valido(no: Node) -> bool:
	return no != null and is_instance_valid(no) and no.is_inside_tree()


func tela_fim_de_jogo(
	no_pai: Node,
	titulo: String,
	subtitulo: String,
	cor: Color,
	is_bankruptcy: bool = false,
	mostrar_continuar_assistindo: bool = true
) -> void:
	if not _no_visual_animacao_valido(no_pai):
		return

	var arvore: SceneTree = no_pai.get_tree()
	if arvore == null:
		return

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.0)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 999
	no_pai.add_child(overlay)

	var tween_fade := overlay.create_tween()
	tween_fade.tween_property(overlay, "color:a", 0.85, 0.8)

	var viewport_size := Vector2(1920, 1080)
	if no_pai is Control:
		viewport_size = (no_pai as Control).size

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(800, 400)
	vbox.size = Vector2(800, 400)
	vbox.position = Vector2(
		(viewport_size.x - 800.0) / 2.0,
		(viewport_size.y - 400.0) / 2.0
	)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 25)
	overlay.add_child(vbox)

	var lbl_titulo := Label.new()
	lbl_titulo.text = titulo
	lbl_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_titulo.add_theme_color_override("font_color", cor)
	lbl_titulo.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl_titulo.add_theme_constant_override("outline_size", 12)
	lbl_titulo.add_theme_font_size_override("font_size", 64)
	lbl_titulo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _fonte_pixel:
		lbl_titulo.add_theme_font_override("font", _fonte_pixel)
	lbl_titulo.modulate.a = 0.0
	vbox.add_child(lbl_titulo)

	var lbl_sub := Label.new()
	lbl_sub.text = subtitulo
	lbl_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_sub.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	lbl_sub.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl_sub.add_theme_constant_override("outline_size", 6)
	lbl_sub.add_theme_font_size_override("font_size", 18)
	lbl_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _fonte_pixel:
		lbl_sub.add_theme_font_override("font", _fonte_pixel)
	lbl_sub.modulate.a = 0.0
	vbox.add_child(lbl_sub)

	var hbox_botoes := HBoxContainer.new()
	hbox_botoes.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox_botoes.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox_botoes)

	var btn_nova := Button.new()
	btn_nova.text = "NOVA PARTIDA"
	btn_nova.custom_minimum_size = Vector2(240, 60)
	btn_nova.add_theme_font_size_override("font_size", 13)
	if _fonte_pixel:
		btn_nova.add_theme_font_override("font", _fonte_pixel)
	btn_nova.modulate.a = 0.0
	if OnlineTransport.is_host():
		hbox_botoes.add_child(btn_nova)
	btn_nova.pressed.connect(func() -> void:
		if not _no_visual_animacao_valido(no_pai):
			return
		if OnlineTransport.usando_photon():
			if OnlineTransport.is_host():
				OnlineTransport.mudar_cena_para_todos(OnlineTransport.CENA_ONLINE, true)
			return
		if OnlineTransport.is_host():
			OnlineTransport.send_all(NetworkManager, &"_voltar_lobby_rede", [], true, true)
		else:
			no_pai.get_tree().change_scene_to_file("res://scenes/ui/lobby/lobby.tscn")
	)

	var btn_menu := Button.new()
	btn_menu.text = "VOLTAR AO MENU"
	btn_menu.custom_minimum_size = Vector2(280, 60)
	btn_menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn_menu.add_theme_font_size_override("font_size", 14)
	if _fonte_pixel:
		btn_menu.add_theme_font_override("font", _fonte_pixel)
	btn_menu.modulate.a = 0.0
	btn_menu.pressed.connect(func() -> void:
		if not _no_visual_animacao_valido(no_pai):
			return
		if OnlineTransport.usando_photon():
			PhotonManager.sair_sala()
		elif NetworkManager.esta_em_sala():
			NetworkManager.desconectar("Você voltou ao menu principal.")
		no_pai.get_tree().change_scene_to_file(
			"res://scenes/ui/tela_inicial/menu_principal.tscn"
		)
	)
	hbox_botoes.add_child(btn_menu)

	if is_bankruptcy and mostrar_continuar_assistindo:
		var btn_assistir := Button.new()
		btn_assistir.text = "CONTINUAR ASSISTINDO"
		btn_assistir.custom_minimum_size = Vector2(300, 60)
		btn_assistir.add_theme_font_size_override("font_size", 13)
		if _fonte_pixel:
			btn_assistir.add_theme_font_override("font", _fonte_pixel)
		btn_assistir.modulate.a = 0.0
		btn_assistir.pressed.connect(func() -> void:
			if not _no_visual_animacao_valido(no_pai):
				return
			var ancestral: Node = no_pai
			while ancestral != null and is_instance_valid(ancestral):
				if ancestral.has_method("ativar_modo_espectador"):
					ancestral.ativar_modo_espectador()
					break
				ancestral = ancestral.get_parent()
			if _no_visual_animacao_valido(overlay):
				overlay.queue_free()
		)
		hbox_botoes.add_child(btn_assistir)

	await arvore.create_timer(1.0, true, false, true).timeout
	if not _no_visual_animacao_valido(overlay):
		return
	if not _no_visual_animacao_valido(lbl_titulo):
		return

	var tween_titulo := lbl_titulo.create_tween().set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	tween_titulo.tween_property(lbl_titulo, "modulate:a", 1.0, 0.6)

	await arvore.create_timer(0.6, true, false, true).timeout
	if not _no_visual_animacao_valido(overlay):
		return
	if not _no_visual_animacao_valido(lbl_sub):
		return

	var tween_subtitulo := lbl_sub.create_tween().set_trans(Tween.TRANS_QUAD)
	tween_subtitulo.tween_property(lbl_sub, "modulate:a", 1.0, 0.5)

	await arvore.create_timer(0.4, true, false, true).timeout
	if not _no_visual_animacao_valido(overlay):
		return
	if not _no_visual_animacao_valido(hbox_botoes):
		return

	if _no_visual_animacao_valido(btn_nova):
		var tween_nova := btn_nova.create_tween().set_trans(Tween.TRANS_QUAD)
		tween_nova.tween_property(btn_nova, "modulate:a", 1.0, 0.4)
	if _no_visual_animacao_valido(btn_menu):
		var tween_menu := btn_menu.create_tween().set_trans(Tween.TRANS_QUAD)
		tween_menu.tween_property(btn_menu, "modulate:a", 1.0, 0.4)

	for child_variant in hbox_botoes.get_children():
		if not child_variant is Button:
			continue
		var child := child_variant as Button
		if child.text != "CONTINUAR ASSISTINDO" or child.modulate.a >= 1.0:
			continue
		if not _no_visual_animacao_valido(child):
			continue
		var tween_assistir := child.create_tween().set_trans(Tween.TRANS_QUAD)
		tween_assistir.tween_property(child, "modulate:a", 1.0, 0.4)
