extends Node2D

class_name PinoPersonagem

# ============================================================================
# CONFIGURAÇÃO
# ============================================================================
var cor: Color = Color.WHITE
var id_jogador: String = ""
var casa_atual: int = 0
var esta_movendo: bool = false
var offset_local: Vector2 = Vector2.ZERO

# Pulo
const ALTURA_PULO = 60.0
const TEMPO_PULO = 0.25
const TEMPO_ESPERA_ENTRE_CASAS = 0.08

# --- NOVO: Estado de animação contínua ---
var tempo_idle: float = 0.0
var preso: bool = false  # Quando true, desenha barras de prisão sobre o pino
var barras_prisao: Node2D = null
var cor_tint: Color = Color(1, 1, 1, 0)  # Tint da habilidade ativa (fade in/out)
var overlay_tint: ColorRect = null

# Referências visuais
var sombra_chao: Panel
var visual_node: Node2D
var partes_cor: Array[Panel] = []
var label_nome: Label

signal movimento_finalizado(casa_atual: int)

# ============================================================================
# INICIALIZAÇÃO VISUAL (Um único bonequinho humanóide)
# ============================================================================
func _ready():
		z_index = 100  # Bem acima de tudo no tabuleiro
		
		# --- 1. SOMBRA NO CHÃO (Elipse) ---
		sombra_chao = Panel.new()
		sombra_chao.size = Vector2(36, 14)
		sombra_chao.position = Vector2(-18, -6)
		sombra_chao.add_theme_stylebox_override("panel", _criar_sb(Color(0, 0, 0, 0.45), 18))
		add_child(sombra_chao)
		
		# --- 2. NÓ VISUAL (Anima o boneco inteiro) ---
		visual_node = Node2D.new()
		add_child(visual_node)
		
		var cor_borda = Color(0.05, 0.05, 0.05)
		
		# --- 3. BORDAS PRETAS (A Silhueta de Fundo) ---
		_criar_parte(visual_node, Vector2(36, 14), Vector2(-18, -14), 6, cor_borda, false) # Base (Pés)
		_criar_parte(visual_node, Vector2(26, 32), Vector2(-13, -38), 8, cor_borda, false) # Corpo
		_criar_parte(visual_node, Vector2(28, 28), Vector2(-14, -62), 14, cor_borda, false)# Cabeça

		# --- 4. PREENCHIMENTO (Cor do Jogador) ---
		# Matemática exata: 8 pixels menor na largura/altura, 4 pixels de offset pra criar borda de 4px
		_criar_parte(visual_node, Vector2(28, 6), Vector2(-14, -10), 3, cor, true)         # [0] Base Cor
		_criar_parte(visual_node, Vector2(18, 24), Vector2(-9, -34), 4, cor, true)         # [1] Corpo Cor
		_criar_parte(visual_node, Vector2(20, 20), Vector2(-10, -58), 10, _cor_mais_escura(cor), true) # [2] Cabeça Cor
		
		# --- 5. LABEL COM INICIAIS ---
		label_nome = Label.new()
		label_nome.text = id_jogador.left(2).to_upper() if id_jogador.length() > 0 else "P"
		label_nome.position = Vector2(-20, -86) # Flutuando acima da cabeça
		label_nome.size = Vector2(40, 20)
		label_nome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label_nome.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label_nome.add_theme_color_override("font_color", _cor_contraste(cor))
		label_nome.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		label_nome.add_theme_constant_override("outline_size", 5)
		label_nome.add_theme_font_size_override("font_size", 16)
		visual_node.add_child(label_nome)

# Função auxiliar para criar as formas geométricas limpas
func _criar_parte(pai: Node, tamanho: Vector2, pos: Vector2, raio: int, c: Color, salvar_referencia: bool):
		var p = Panel.new()
		p.size = tamanho
		p.position = pos
		p.add_theme_stylebox_override("panel", _criar_sb(c, raio))
		pai.add_child(p)
		
		if salvar_referencia:
				partes_cor.append(p)

func _criar_sb(c: Color, r: int) -> StyleBoxFlat:
		var sb = StyleBoxFlat.new()
		sb.bg_color = c
		sb.corner_radius_top_left = r
		sb.corner_radius_top_right = r
		sb.corner_radius_bottom_right = r
		sb.corner_radius_bottom_left = r
		sb.anti_aliasing = true
		return sb

func _cor_mais_escura(c: Color) -> Color:
		return Color(max(c.r - 0.25, 0.0), max(c.g - 0.25, 0.0), max(c.b - 0.25, 0.0), 1.0)

func _cor_contraste(c: Color) -> Color:
		var luminancia = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
		return Color.BLACK if luminancia > 0.6 else Color.WHITE

func configurar(nova_cor: Color, novo_id: String):
		cor = nova_cor
		id_jogador = novo_id
		
		if partes_cor.size() == 3:
				(partes_cor[0].get_theme_stylebox("panel") as StyleBoxFlat).bg_color = cor
				(partes_cor[1].get_theme_stylebox("panel") as StyleBoxFlat).bg_color = cor
				(partes_cor[2].get_theme_stylebox("panel") as StyleBoxFlat).bg_color = _cor_mais_escura(cor)
				
		if label_nome:
				label_nome.text = id_jogador.left(2).to_upper() if id_jogador.length() > 0 else "P"
				label_nome.add_theme_color_override("font_color", _cor_contraste(cor))

# ============================================================================
# MOVIMENTAÇÃO 
# ============================================================================
func mover_casas(quantidade: int, tabuleiro: Dictionary, tabuleiro_node: Node2D):
		if esta_movendo or quantidade <= 0:
				return
		esta_movendo = true
		
		var casa_inicial = casa_atual
		var passou_volta = casa_inicial + quantidade >= 40
		
		tabuleiro_node._remover_pino_da_casa(self, casa_atual)
		
		if passou_volta:
				var casas_ate_39 = 39 - casa_inicial
				if casas_ate_39 > 0:
						await _pular_casas_sequencia(casas_ate_39, tabuleiro, 1)
				await _caminhar_volta_pelas_ruas(tabuleiro)
				var casas_restantes = (casa_inicial + quantidade) % 40
				if casas_restantes > 0:
						await _pular_casas_sequencia(casas_restantes, tabuleiro, 1)
		else:
				await _pular_casas_sequencia(quantidade, tabuleiro, 1)
		
		casa_atual = (casa_inicial + quantidade) % 40
		tabuleiro_node._adicionar_pino_na_casa(self, casa_atual)
		
		esta_movendo = false
		emit_signal("movimento_finalizado", casa_atual)

# --- NOVO (GDD §5.2): Move o pino para TRÁS (casas negativas).
#     Usado por cartas do tipo "move_tras". ---
func mover_casas_tras(quantidade: int, tabuleiro: Dictionary, tabuleiro_node: Node2D):
		if esta_movendo or quantidade <= 0:
				return
		esta_movendo = true
		var casa_inicial = casa_atual
		tabuleiro_node._remover_pino_da_casa(self, casa_atual)
		# Move para trás uma casa por vez
		for i in range(quantidade):
				var proxima_casa = casa_atual - 1
				if proxima_casa < 0:
						proxima_casa = 39
				await _pular_para_casa(proxima_casa, tabuleiro)
				casa_atual = proxima_casa
				if i < quantidade - 1:
						await get_tree().create_timer(TEMPO_ESPERA_ENTRE_CASAS).timeout
		tabuleiro_node._adicionar_pino_na_casa(self, casa_atual)
		esta_movendo = false
		emit_signal("movimento_finalizado", casa_atual)

func _pular_casas_sequencia(quantidade: int, tabuleiro: Dictionary, direcao: int):
		for i in range(quantidade):
				var proxima_casa = (casa_atual + direcao) % 40
				if proxima_casa < 0:
						proxima_casa += 40
				
				await _pular_para_casa(proxima_casa, tabuleiro)
				casa_atual = proxima_casa
				
				if i < quantidade - 1:
						await get_tree().create_timer(TEMPO_ESPERA_ENTRE_CASAS).timeout

func _pular_para_casa(id_casa: int, tabuleiro: Dictionary):
		if not tabuleiro.has(id_casa):
				return
		
		var pos_destino = tabuleiro[id_casa]["pos"] + offset_local
		var pos_inicial = position
		var meio = (pos_inicial + pos_destino) / 2.0
		
		var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		
		# Sobe (O bonequinho escala junto)
		tween.parallel().tween_property(self, "position", meio + Vector2(0, -ALTURA_PULO), TEMPO_PULO / 2.0)
		tween.parallel().tween_property(visual_node, "scale", Vector2(1.15, 1.15), TEMPO_PULO / 2.0)
		tween.parallel().tween_property(sombra_chao, "scale", Vector2(0.5, 0.5), TEMPO_PULO / 2.0)
		tween.parallel().tween_property(sombra_chao, "modulate", Color(1, 1, 1, 0.3), TEMPO_PULO / 2.0)
		
		# Desce
		tween.chain().tween_property(self, "position", pos_destino, TEMPO_PULO / 2.0)
		tween.parallel().tween_property(visual_node, "scale", Vector2(1.0, 1.0), TEMPO_PULO / 2.0)
		tween.parallel().tween_property(sombra_chao, "scale", Vector2(1.0, 1.0), TEMPO_PULO / 2.0)
		tween.parallel().tween_property(sombra_chao, "modulate", Color(1, 1, 1, 1.0), TEMPO_PULO / 2.0)
		
		await tween.finished
		
		# --- NOVO: IMPACTO DE POUSO (squash & stretch elástico) ---
		# O bonequinho amassa no chão e volta como uma mola
		var tween_impacto = create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tween_impacto.tween_property(visual_node, "scale", Vector2(1.25, 0.7), 0.12)
		tween_impacto.tween_property(visual_node, "scale", Vector2(1.0, 1.0), 0.25)

# ============================================================================
# CAMINHO DE VOLTA E UTILIDADES
# ============================================================================
func _caminhar_volta_pelas_ruas(tabuleiro: Dictionary):
		var caminho = _calcular_caminho_rua_39_para_0(tabuleiro)
		var distancia_total = 0.0
		for i in range(caminho.size() - 1):
				distancia_total += caminho[i].distance_to(caminho[i + 1])
		
		var velocidade = 800.0
		var duracao = distancia_total / velocidade
		
		var tween = create_tween().set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
		
		for i in range(caminho.size()):
				var duracao_ponto = duracao / caminho.size()
				if i == 0:
						tween.tween_property(self, "position", caminho[i] + offset_local, duracao_ponto)
				else:
						tween.chain().tween_property(self, "position", caminho[i] + offset_local, duracao_ponto)
		
		# Inclina o bonequinho para trás enquanto viaja pela rua do centro
		visual_node.rotation_degrees = -15
		var tween_rot = create_tween()
		tween_rot.tween_property(visual_node, "rotation_degrees", 0, duracao)
		
		await tween.finished
		casa_atual = 0

func _calcular_caminho_rua_39_para_0(tabuleiro: Dictionary) -> Array[Vector2]:
		var caminho: Array[Vector2] = []
		var pos_39 = tabuleiro[39]["pos"]
		var pos_0 = tabuleiro[0]["pos"]
		var tam_39 = _get_tamanho_casa(39, tabuleiro)
		var tam_0 = _get_tamanho_casa(0, tabuleiro)
		
		var dir = (pos_0 - pos_39).normalized()
		var ponto_saida = _get_ponto_borda(pos_39, dir, tam_39)
		var ponto_chegada = _get_ponto_borda(pos_0, -dir, tam_0)
		var ponto_meio = (ponto_saida + ponto_chegada) / 2.0
		
		caminho.append(ponto_saida)
		caminho.append(ponto_meio)
		caminho.append(ponto_chegada)
		return caminho

func aplicar_offset(novo_offset: Vector2, pos_casa: Vector2):
		offset_local = novo_offset
		var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "position", pos_casa + offset_local, 0.3)

# ============================================================================
# IDLE BOB — flutuação sutil quando parado (deixa o tabuleiro vivo)
# ============================================================================
func _process(delta: float) -> void:
		if not esta_movendo and visual_node:
				tempo_idle += delta
				# Oscilação sutil de ±2px no eixo Y, período 2s
				var bob = sin(tempo_idle * PI) * 1.5
				visual_node.position.y = bob
				# Leve rotação balanceando
				visual_node.rotation_degrees = sin(tempo_idle * PI * 0.5) * 1.0

func _get_tamanho_casa(id: int, tabuleiro: Dictionary) -> Vector2:
		var tipo = tabuleiro[id]["tipo"]
		var escala = tabuleiro[id].get("escala", 1.0)
		var base = Vector2(220, 280)
		if tipo in ["especial", "portal"]: 
				base = Vector2(240, 240)
		return base * escala

func _get_ponto_borda(pos: Vector2, dir: Vector2, tamanho: Vector2) -> Vector2:
		if abs(dir.x) > abs(dir.y):
				return pos + Vector2(tamanho.x / 2.0, 0) if dir.x > 0 else pos - Vector2(tamanho.x / 2.0, 0)
		else:
				return pos + Vector2(0, tamanho.y / 2.0) if dir.y > 0 else pos - Vector2(0, tamanho.y / 2.0)

func mover_para_casa(destino: int, tabuleiro: Dictionary, tabuleiro_node: Node2D):
		var diferenca = destino - casa_atual
		if diferenca < 0: diferenca += 40
		mover_casas(diferenca, tabuleiro, tabuleiro_node)

# ============================================================================
# EFEITOS VISUAIS
# ============================================================================
func mostrar_texto_flutuante(texto: String, cor: Color):
		var float_label = Label.new()
		float_label.text = texto
		float_label.add_theme_color_override("font_color", cor)
		float_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		float_label.add_theme_constant_override("outline_size", 6)
		float_label.add_theme_font_size_override("font_size", 28)
		
		# Centraliza o texto perfeitamente acima da cabeça do pino
		float_label.custom_minimum_size = Vector2(100, 30)
		float_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		float_label.position = Vector2(-50, -90)
		
		# Usa um z_index alto para garantir que apareça na frente dos prédios
		float_label.z_index = 200
		add_child(float_label)
		
		# Animação: Sobe 50 pixels e vai ficando transparente (Fade Out)
		var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(float_label, "position", float_label.position + Vector2(0, -50), 1.5)
		tween.parallel().tween_property(float_label, "modulate:a", 0.0, 1.5)
		
		# Deleta o nó quando a animação terminar
		tween.tween_callback(float_label.queue_free)

# ============================================================================
# NOVO: BARRAS DE PRISÃO — deslizam de cima quando o pino é preso
# ============================================================================
func ativar_barras_prisao():
		if barras_prisao:
				return  # Já ativadas
		preso = true
		barras_prisao = Node2D.new()
		barras_prisao.z_index = 150
		add_child(barras_prisao)
		
		# Cria 5 barras verticais pretas
		for i in range(5):
				var barra = Panel.new()
				barra.size = Vector2(6, 80)
				barra.position = Vector2(-22 + i * 11, -75)
				barra.modulate.a = 0.0
				var sb = StyleBoxFlat.new()
				sb.bg_color = Color(0.05, 0.05, 0.05, 0.95)
				barra.add_theme_stylebox_override("panel", sb)
				barras_prisao.add_child(barra)

				# Deslizam de cima para baixo com pequeno atraso entre cada
				# (Godot 4: usa tween_interval para criar o delay antes da animação)
				var tween = barra.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				tween.tween_interval(i * 0.05)
				tween.tween_property(barra, "modulate:a", 1.0, 0.2)
		
		# Escurece levemente o pino (visual de "preso")
		var t = visual_node.create_tween()
		t.tween_property(visual_node, "modulate", Color(0.6, 0.6, 0.6, 1.0), 0.4)

func desativar_barras_prisao():
		# O estado deve ser limpo mesmo se o nó das barras já tiver sido removido
		# ou não tiver sido criado neste peer. Isso evita um pino continuar
		# marcado visualmente como preso após a libertação em rede.
		preso = false
		if visual_node:
				var restaurar_cor = visual_node.create_tween()
				restaurar_cor.tween_property(visual_node, "modulate", Color(1, 1, 1, 1), 0.4)
		if not barras_prisao:
				return
		# --- BUG FIX (HIGH #23): Captura referência local para a closure.
		#     Antes, a closure capturava barras_prisao (variável de instância).
		#     Se ativar_barras_prisao fosse chamado de novo durante o fade out,
		#     barras_prisao apontaria para o novo node, e o callback faria
		#     queue_free() no NOVO node, deixando o antigo órfão.
		#     Agora capturamos a referência local no início da função. ---
		var barras_para_remover = barras_prisao
		# Fade out das barras
		var tween = barras_para_remover.create_tween().set_trans(Tween.TRANS_QUAD)
		tween.tween_property(barras_para_remover, "modulate:a", 0.0, 0.3)
		tween.tween_callback(func(): 
				if is_instance_valid(barras_para_remover):
						barras_para_remover.queue_free()
				# Só limpa barras_prisao se ainda aponta para o mesmo node
				if barras_prisao == barras_para_remover:
						barras_prisao = null
		)

# ============================================================================
# NOVO: TINT DE HABILIDADE ATIVA — overlay colorido durante o uso da habilidade
# ============================================================================
func ativar_tint_habilidade(cor_tint: Color, duracao: float = 1.5):
		# Adiciona um ColorRect sobre o pino que pulsa na cor do personagem
		var tint = ColorRect.new()
		tint.size = Vector2(50, 90)
		tint.position = Vector2(-25, -75)
		tint.color = cor_tint
		tint.modulate.a = 0.0
		tint.z_index = 140
		add_child(tint)
		
		# Aparece, pulsa, e some
		var tween = tint.create_tween().set_trans(Tween.TRANS_QUAD)
		tween.tween_property(tint, "modulate:a", 0.6, 0.2)
		tween.tween_property(tint, "modulate:a", 0.0, duracao)
		tween.tween_callback(tint.queue_free)
		
		# Escala o pino para "empolgar"
		var escala_original = visual_node.scale
		var t2 = visual_node.create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		t2.tween_property(visual_node, "scale", escala_original * 1.3, 0.3)
		t2.tween_property(visual_node, "scale", escala_original, 0.4)

# ============================================================================
# NOVO: TREMOR — pequeno shake do pino (uso em penalidades)
# ============================================================================
# --- BUG FIX (HIGH #22): Antes, tremer capturava pos_original = position e
#     restaurava no final. Mas o pino pode ter offset_local (definido por
#     _reposicionar_pinos_na_casa) que muda independentemente. Após o tremor,
#     o pino "voltava" para pos_original que podia estar desatualizado.
#     SOLUÇÃO: aplicar tremor em visual_node.position (nó visual interno) em
#     vez de self.position (posição lógica). O visual_node é animado
#     independentemente da posição lógica do pino. ---
func tremer(intensidade: float = 4.0, duracao: float = 0.3):
		var pos_original = visual_node.position
		var passos = int(duracao / 0.03)
		var tween = visual_node.create_tween()
		for i in range(passos):
				var decay = 1.0 - float(i) / float(passos)
				var offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * intensidade * decay
				tween.tween_property(visual_node, "position", pos_original + offset, 0.03)
		tween.tween_property(visual_node, "position", pos_original, 0.03)

# ============================================================================
# NOVO: CELEBRAÇÃO — pulo grande + rotação de vitória (em monopólio/vitória)
# ============================================================================
func celebrar():
		var escala_original = visual_node.scale
		var tween = create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(visual_node, "scale", escala_original * 1.6, 0.4)
		tween.parallel().tween_property(visual_node, "rotation_degrees", 360.0, 0.6)
		tween.tween_property(visual_node, "scale", escala_original, 0.3)
		tween.tween_property(visual_node, "rotation_degrees", 0.0, 0.0)
