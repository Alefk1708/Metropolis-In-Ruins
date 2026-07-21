extends "res://scenes/gameplay/tabuleiro/modulos_tabuleiro/tabuleiro_core.gd"

# ============================================================================
# CAMADA DE BALANCEAMENTO DAS HABILIDADES
# ============================================================================
#
# Esta camada fica separada do motor principal para reduzir o risco de
# regressões nos módulos de economia, eventos, HUD e multiplayer.
#
# Regras:
# - A recarga diminui apenas quando começa o turno do dono da habilidade.
# - Diana possui recarga de 4 turnos pessoais.
# - Diana pode manter apenas um Vazamento Seletivo pendente por vez.
# - O dossiê da Diana nunca abre sozinho durante atualizações da HUD.
# - O excedente protegido pelo Hedge Fund do Igor é pago integralmente
#   em quatro turnos pessoais, em vez de ter metade perdoada.
#
# Os valores exibidos na seleção continuam válidos:
# Yasmin 5, Breno 5, Mira 4, Igor 6, Diana 4 e Kofi 4 turnos pessoais.

var _alvo_vazamento_diana: String = ""
var _ultima_recarga_diana_observada: int = -1


@rpc("authority", "call_local")
func _avancar_turno_rede():
	# O código herdado reduz a recarga de todos os jogadores a cada turno
	# global. Antes de chamá-lo, adicionamos temporariamente 1 aos jogadores
	# que NÃO serão o próximo da rodada. Quando o pai descontar 1 de todos,
	# somente o dono do novo turno terá uma redução real.
	if _acoes_bloqueadas_por_evento() or lista_turnos.is_empty():
		super._avancar_turno_rede()
		return

	var proximo_indice: int = (indice_turno_atual + 1) % lista_turnos.size()
	var proximo_jogador: String = str(lista_turnos[proximo_indice])

	for jogador_variant: Variant in lista_turnos:
		var jogador_id: String = str(jogador_variant)
		if jogador_id == proximo_jogador:
			continue
		if not dados_economia_jogadores.has(jogador_id):
			continue

		var dados_jogador: Dictionary = dados_economia_jogadores[jogador_id]
		var recarga_atual: int = int(dados_jogador.get("recarga_hab", 0))
		if recarga_atual > 0:
			dados_jogador["recarga_hab"] = recarga_atual + 1

	super._avancar_turno_rede()
	_normalizar_vazamento_diana()


@rpc("any_peer", "call_local")
func _pagar_aluguel_rede(
	pagador: String,
	recebedor: String,
	valor: int,
	casa_id: int = -1
):
	super._pagar_aluguel_rede(pagador, recebedor, valor, casa_id)

	# Hedge Fund continua impedindo uma perda imediata superior a 50% do
	# saldo, mas o excedente não desaparece mais. O motor herdado cobra 25%
	# da dívida original por turno; quatro parcelas quitam o total.
	if (
		pagador == "igor"
		and dados_economia_jogadores.has("igor")
		and int(dados_economia_jogadores["igor"].get("divida_ativa", 0)) > 0
	):
		dados_economia_jogadores["igor"]["turnos_divida"] = 4

	_normalizar_vazamento_diana()


func _atualizar_hud_ciclo_turno():
	# Guarda o estado escolhido manualmente pelo jogador. A Fonte Anônima pode
	# atualizar o texto, mas não pode abrir o painel por conta própria.
	var dossie_estava_aberto: bool = false
	if hud != null and is_instance_valid(hud):
		dossie_estava_aberto = bool(hud.get("dossie_aberto"))

	# A habilidade da Diana é intencionalmente persistente, mas não deve
	# acumular marcações em vários adversários. Uma nova marca substitui a
	# anterior, mantendo a decisão estratégica sem permitir bloqueio em massa.
	_normalizar_vazamento_diana()
	_garantir_recarga_diana_quatro_turnos()
	super._atualizar_hud_ciclo_turno()
	_restaurar_dossie_fechado(dossie_estava_aberto)


func _garantir_recarga_diana_quatro_turnos() -> void:
	if not dados_economia_jogadores.has("diana"):
		_ultima_recarga_diana_observada = -1
		return

	var dados_diana: Dictionary = dados_economia_jogadores["diana"]
	var recarga_atual: int = int(dados_diana.get("recarga_hab", 0))

	# O motor base ainda registra 3 ao confirmar a habilidade. A transição
	# 0 -> 3 identifica uma nova utilização e converte a recarga para 4.
	# Uma redução normal de 4 -> 3 não é alterada.
	if recarga_atual == 3 and _ultima_recarga_diana_observada <= 0:
		recarga_atual = 4
		dados_diana["recarga_hab"] = recarga_atual

	_ultima_recarga_diana_observada = recarga_atual


func _restaurar_dossie_fechado(dossie_estava_aberto: bool) -> void:
	if dossie_estava_aberto:
		return
	if hud == null or not is_instance_valid(hud):
		return
	if not bool(hud.get("dossie_aberto")):
		return

	# O HUD atual possui um helper que cancela o Tween, invalida a animação
	# pendente e esconde o painel imediatamente.
	var painel_variant: Variant = hud.get("panel_dossie")
	if painel_variant is Control:
		var painel: Control = painel_variant as Control
		if hud.has_method("_ocultar_painel_imediato"):
			hud.call("_ocultar_painel_imediato", painel)
		else:
			painel.visible = false
			painel.modulate.a = 1.0
			painel.scale = Vector2.ONE

	hud.set("dossie_aberto", false)

	var botao_variant: Variant = hud.get("btn_dossie")
	if botao_variant is Button:
		var botao: Button = botao_variant as Button
		botao.text = "ABRIR DOSSIÊ"


func _normalizar_vazamento_diana() -> void:
	if dados_economia_jogadores.is_empty():
		_alvo_vazamento_diana = ""
		return

	var alvos_ativos: Array[String] = []
	for jogador_variant: Variant in lista_turnos:
		var jogador_id: String = str(jogador_variant)
		if jogador_id == "diana":
			continue
		if not dados_economia_jogadores.has(jogador_id):
			continue
		if dados_economia_jogadores[jogador_id].get("falido", false):
			continue
		if bool(dados_economia_jogadores[jogador_id].get("vazamento_ativo", false)):
			alvos_ativos.append(jogador_id)

	if alvos_ativos.is_empty():
		_alvo_vazamento_diana = ""
		return

	if alvos_ativos.size() == 1:
		_alvo_vazamento_diana = alvos_ativos[0]
		return

	# Se o alvo que já estava registrado continua ativo e apareceu outro,
	# o outro é a nova escolha da Diana e substitui a marca anterior.
	var alvo_mantido: String = ""
	if _alvo_vazamento_diana != "" and alvos_ativos.has(_alvo_vazamento_diana):
		for alvo_id: String in alvos_ativos:
			if alvo_id != _alvo_vazamento_diana:
				alvo_mantido = alvo_id
				break

	# Fallback determinístico para partidas antigas/salvamentos que já
	# contenham mais de uma marca antes desta correção.
	if alvo_mantido == "":
		alvos_ativos.sort()
		alvo_mantido = alvos_ativos[0]

	for alvo_id: String in alvos_ativos:
		if alvo_id == alvo_mantido:
			continue
		var dados_alvo: Dictionary = dados_economia_jogadores[alvo_id]
		dados_alvo["vazamento_ativo"] = false
		dados_alvo.erase("vazamento_turnos")

	_alvo_vazamento_diana = alvo_mantido
