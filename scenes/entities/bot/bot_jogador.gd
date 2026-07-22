extends Node
class_name BotJogador

## Controlador de decisões local e reutilizável.
##
## O bot não replica as regras do jogo. Ele escolhe uma ação e pede ao
## Tabuleiro para executá-la, mantendo compras, dinheiro, cartas e turnos sob a
## mesma autoridade usada por jogadores humanos.

signal acao_executada(tipo: String, dados: Dictionary)
signal pausa_alterada

@export_range(0.1, 3.0, 0.1) var atraso_antes_de_jogar: float = 0.85
@export_range(0, 1000, 25) var reserva_minima: int = 250

var jogador_id: String = ""
var _tabuleiro: Node = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _resultados_forcados: Array[Vector2i] = []
var _pausado: bool = false
var _executando_turno: bool = false
var _geracao_execucao_turno: int = 0


func configurar(tabuleiro: Node, id_jogador: String, semente: int = 0) -> void:
	_tabuleiro = tabuleiro
	jogador_id = id_jogador
	if semente == 0:
		_rng.randomize()
	else:
		_rng.seed = semente


func definir_resultados_forcados(resultados: Array[Vector2i]) -> void:
	_resultados_forcados = resultados.duplicate()


func definir_pausado(pausado: bool) -> void:
	if _pausado == pausado:
		return
	_pausado = pausado
	pausa_alterada.emit()


func esta_executando_turno() -> bool:
	return _executando_turno


func reiniciar_turno_seguro() -> void:
	# Invalida somente a corrotina que ficou presa antes/durante a pausa. Cada
	# await valida esta geração antes de rolar, portanto a rotina antiga nunca
	# consegue executar dados depois que a nova geração começa.
	_geracao_execucao_turno += 1
	_executando_turno = false
	if _pausado:
		_pausado = false
		pausa_alterada.emit()
	call_deferred("executar_turno")


func executar_turno() -> void:
	if (
		_executando_turno
		or _tabuleiro == null
		or not is_instance_valid(_tabuleiro)
	):
		return

	_executando_turno = true
	var geracao_local: int = _geracao_execucao_turno

	await _aguardar_liberacao()
	if not _execucao_turno_valida(geracao_local):
		_finalizar_execucao_se_atual(geracao_local)
		return

	await get_tree().create_timer(atraso_antes_de_jogar).timeout
	await _aguardar_liberacao()
	if not _execucao_turno_valida(geracao_local):
		_finalizar_execucao_se_atual(geracao_local)
		return

	var resultado: Vector2i = _sortear_dados()
	if not _execucao_turno_valida(geracao_local):
		_finalizar_execucao_se_atual(geracao_local)
		return

	acao_executada.emit(
		"rolar_dados",
		{
			"jogador_id": jogador_id,
			"dado1": resultado.x,
			"dado2": resultado.y,
		}
	)
	_tabuleiro.call(
		"executar_rolagem_bot",
		jogador_id,
		resultado.x,
		resultado.y
	)
	_finalizar_execucao_se_atual(geracao_local)


func decidir_compra(
	_casa_id: int,
	dados_casa: Dictionary,
	saldo: int,
	custo: int
) -> bool:
	await _aguardar_liberacao()
	await get_tree().create_timer(0.55).timeout
	await _aguardar_liberacao()
	if custo <= 0 or saldo < custo:
		return false

	var grupo: String = str(dados_casa.get("grupo", ""))
	var reserva: int = reserva_minima
	if grupo in ["Transporte", "Utilidade"]:
		reserva = maxi(150, reserva_minima - 100)
	var comprar: bool = saldo - custo >= reserva
	acao_executada.emit(
		"decisao_compra",
		{
			"jogador_id": jogador_id,
			"custo": custo,
			"comprar": comprar,
		}
	)
	return comprar


func decidir_lance(
	valor_atual: int,
	valor_propriedade: int,
	saldo: int
) -> int:
	var teto: int = mini(
		saldo - reserva_minima,
		int(valor_propriedade * 1.15)
	)
	if teto <= valor_atual:
		return 0
	return mini(
		teto,
		valor_atual + maxi(10, int(valor_propriedade * 0.08))
	)


func avaliar_negociacao(valor_recebido: int, valor_entregue: int) -> bool:
	return valor_recebido >= int(valor_entregue * 0.92)


func escolher_construcao(opcoes: Array[Dictionary], saldo: int) -> int:
	var melhor_id: int = -1
	var melhor_aluguel: int = -1
	for opcao: Dictionary in opcoes:
		var custo: int = int(opcao.get("custo", 0))
		if not bool(opcao.get("pode_construir", false)):
			continue
		if custo <= 0 or saldo - custo < reserva_minima:
			continue
		var aluguel: int = int(opcao.get("aluguel_atual", 0))
		if aluguel > melhor_aluguel:
			melhor_aluguel = aluguel
			melhor_id = int(opcao.get("id", -1))
	return melhor_id


func _sortear_dados() -> Vector2i:
	if not _resultados_forcados.is_empty():
		return _resultados_forcados.pop_front()
	return Vector2i(
		_rng.randi_range(1, 6),
		_rng.randi_range(1, 6)
	)


func _aguardar_liberacao() -> void:
	while _pausado and is_inside_tree():
		await pausa_alterada


func _execucao_turno_valida(geracao: int) -> bool:
	return (
		geracao == _geracao_execucao_turno
		and is_inside_tree()
		and _tabuleiro != null
		and is_instance_valid(_tabuleiro)
	)


func _finalizar_execucao_se_atual(geracao: int) -> void:
	# Uma corrotina invalidada não pode limpar a flag de uma geração mais nova.
	if geracao == _geracao_execucao_turno:
		_executando_turno = false
