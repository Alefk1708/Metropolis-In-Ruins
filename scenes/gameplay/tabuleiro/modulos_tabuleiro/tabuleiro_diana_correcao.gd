extends "res://scenes/gameplay/tabuleiro/modulos_tabuleiro/tabuleiro_singleplayer_correcao.gd"

# ============================================================================
# DIANA — PASSIVA FONTE ANÔNIMA
# ============================================================================
#
# O módulo de eventos chama _sincronizar_proximo_evento_rede() depois de
# pré-sortear o próximo Evento Global, porém essa função deixou de existir
# durante a separação do antigo tabuleiro.gd em módulos.
#
# Sem o RPC:
# - proximo_evento_global nunca era atualizado;
# - proximo_evento_descricao permanecia vazia;
# - fonte_anonima_evento_previsto nunca era preenchido;
# - o dossiê da Diana não recebia a seção "FONTE ANÔNIMA".
#
# A passiva é contínua: sempre que um novo Evento Global é pré-sorteado,
# Diana recebe a previsão. O evento pré-sorteado continua sendo a fonte
# autoritativa usada pelo motor no próximo reveal.
# ============================================================================


# ============================================================================
# ANDROID — CACHE DAS INFORMAÇÕES DA CASA EM FOCO
# ============================================================================
#
# _atualizar_hud_minha_casa() é chamado por vários fluxos do tabuleiro.
# A implementação original duplica o dicionário da casa, recalcula aluguel,
# percorre propriedades e jogadores e remonta o texto completo mesmo quando
# nenhum dado visual mudou.
#
# Esta substituição cria uma assinatura barata do estado relevante e só chama
# a implementação original quando essa assinatura muda.
# ============================================================================


var _hud_casa_ultima_chave: String = ""


func _atualizar_hud_minha_casa():
	if hud == null or not is_instance_valid(hud):
		_hud_casa_ultima_chave = ""
		return

	var personagem_local: String = str(
		Global.escolhas_da_mesa.get(
			Global.meu_peer_id,
			""
		)
	)
	if (
		personagem_local.is_empty()
		or not pinos_jogadores.has(personagem_local)
	):
		_hud_casa_ultima_chave = ""
		return

	var pino_variant: Variant = pinos_jogadores.get(
		personagem_local
	)
	if (
		pino_variant == null
		or not is_instance_valid(pino_variant)
	):
		_hud_casa_ultima_chave = ""
		return

	var pino: Node = pino_variant as Node
	var casa_id: int = int(pino.get("casa_atual"))
	if not tabuleiro.has(casa_id):
		_hud_casa_ultima_chave = ""
		return

	var chave_atual: String = _hud_casa_criar_chave(
		personagem_local,
		casa_id,
		pino
	)
	if chave_atual == _hud_casa_ultima_chave:
		# O botão antigo foi movido para Gestão de Propriedades. Essa operação
		# é barata e continua sendo garantida mesmo quando o painel não muda.
		_hud_casa_esconder_botao_hipoteca()
		return

	# Executa a implementação original somente quando existe uma mudança real.
	super._atualizar_hud_minha_casa()
	_hud_casa_ultima_chave = chave_atual


func _hud_casa_criar_chave(
	personagem_local: String,
	casa_id: int,
	pino: Node
) -> String:
	var dados_casa: Dictionary = tabuleiro.get(
		casa_id,
		{}
	)
	var grupo: String = str(
		dados_casa.get("grupo", "")
	)
	var dono_id: String = str(
		registro_propriedades.get(
			casa_id,
			""
		)
	)
	var dono_nome: String = ""
	if (
		not dono_id.is_empty()
		and dados_economia_jogadores.has(dono_id)
	):
		dono_nome = str(
			dados_economia_jogadores[dono_id].get(
				"nome",
				dono_id
			)
		)

	var partes: PackedStringArray = PackedStringArray(
		[
			str(hud.get_instance_id()),
			personagem_local,
			str(pino.get_instance_id()),
			str(casa_id),
			dono_id,
			dono_nome,
			str(dados_casa),
			str(evento_ativo),
			str(multiplicador_inflacao_global),
			str(ultimo_dado1),
			str(ultimo_dado2),
			_hud_casa_assinatura_posse_grupo(grupo),
			_hud_casa_assinatura_habilidades(),
			_hud_casa_assinatura_efeitos_aluguel(),
		]
	)
	return "|".join(partes)


func _hud_casa_assinatura_posse_grupo(
	grupo: String
) -> String:
	# Monopólios, quantidade de transportes e quantidade de utilidades dependem
	# da posse das outras casas do mesmo grupo.
	var partes: PackedStringArray = PackedStringArray()
	var ids: Array = tabuleiro.keys()
	ids.sort()

	for id_variant: Variant in ids:
		var id_casa: int = int(id_variant)
		var dados_variant: Variant = tabuleiro.get(
			id_casa,
			{}
		)
		if not dados_variant is Dictionary:
			continue
		var dados: Dictionary = dados_variant
		if str(dados.get("grupo", "")) != grupo:
			continue
		partes.append(
			"%d:%s" % [
				id_casa,
				str(
					registro_propriedades.get(
						id_casa,
						""
					)
				),
			]
		)

	return ",".join(partes)


func _hud_casa_assinatura_habilidades() -> String:
	# O texto e o aluguel podem ser alterados pelo Decreto do Breno e pela
	# Especulação do Igor. Somente esses campos entram na chave.
	var partes: PackedStringArray = PackedStringArray()

	for jogador_variant: Variant in lista_turnos:
		var jogador_id: String = str(
			jogador_variant
		)
		var dados: Dictionary = (
			dados_economia_jogadores.get(
				jogador_id,
				{}
			)
		)
		partes.append(
			"%s:%d:%s:%d:%d" % [
				jogador_id,
				int(dados.get("decreto_turnos", 0)),
				str(dados.get("decreto_grupo", "")),
				int(dados.get("especulacao_turnos", 0)),
				int(dados.get("especulacao_casa", -1)),
			]
		)

	return ",".join(partes)


func _hud_casa_assinatura_efeitos_aluguel() -> String:
	# O motor central pode modificar o aluguel sem trocar evento_ativo. Por
	# exemplo: votação, congelamento, interdição ou carta com duração.
	var partes: PackedStringArray = PackedStringArray()

	for tipo_variant: Variant in [
		"congelar_aluguel",
		"aluguel_zero",
		"interdicao",
		"multiplicador_aluguel",
	]:
		var tipo: String = str(tipo_variant)
		partes.append(
			"%s:%s" % [
				tipo,
				str(_efeitos_ativos_por_tipo(tipo)),
			]
		)

	return ",".join(partes)


func _hud_casa_esconder_botao_hipoteca() -> void:
	if (
		hud != null
		and is_instance_valid(hud)
		and hud.has_method("esconder_botao_hipoteca")
	):
		hud.call("esconder_botao_hipoteca")


@rpc("authority", "call_local", "reliable")
func _sincronizar_proximo_evento_rede(
	nome_evento: String,
	descricao_evento: String
) -> void:
	# Todos os peers precisam conhecer a fila autoritativa, mesmo quando Diana
	# não participa da partida. _sortear_evento_global() usa este valor para
	# revelar exatamente o evento que foi pré-sorteado.
	proximo_evento_global = nome_evento
	proximo_evento_descricao = descricao_evento

	if not dados_economia_jogadores.has("diana"):
		return
	if not lista_turnos.has("diana"):
		return

	var dados_diana: Dictionary = dados_economia_jogadores["diana"]
	if bool(dados_diana.get("falido", false)):
		return

	# Remove a trava antiga das partidas salvas. A Fonte Anônima agora é uma
	# passiva contínua e não possui mais limite de uso por partida.
	if dados_diana.has("fonte_anonima_previsao_concedida"):
		dados_diana.erase(
			"fonte_anonima_previsao_concedida"
		)

	if nome_evento.is_empty():
		dados_diana[
			"fonte_anonima_evento_previsto"
		] = ""
		_limpar_fonte_anonima_diana_local()
		GerenciadorSalvamento.marcar_estado_alterado(self)
		return

	# Cada novo evento pré-sorteado substitui a previsão anterior. Como o motor
	# preserva proximo_evento_global até o reveal, Diana sempre vê exatamente o
	# evento que será aplicado.
	dados_diana[
		"fonte_anonima_evento_previsto"
	] = nome_evento

	_atualizar_fonte_anonima_diana_local(
		nome_evento
	)

	GerenciadorSalvamento.marcar_estado_alterado(self)


func _limpar_fonte_anonima_diana_local() -> void:
	var personagem_local: String = str(
		Global.escolhas_da_mesa.get(
			Global.meu_peer_id,
			""
		)
	)
	if personagem_local != "diana":
		return
	if hud == null or not is_instance_valid(hud):
		return
	if hud.has_method("limpar_previsao_evento"):
		hud.limpar_previsao_evento()


func _atualizar_fonte_anonima_diana_local(
	evento_previsto: String
) -> void:
	var personagem_local: String = str(
		Global.escolhas_da_mesa.get(
			Global.meu_peer_id,
			""
		)
	)
	if personagem_local != "diana":
		return
	if evento_previsto.is_empty():
		return
	if evento_previsto != proximo_evento_global:
		return
	if hud == null or not is_instance_valid(hud):
		return
	if not hud.has_method("alimentar_previsao_evento"):
		return

	# alimentar_previsao_evento() também abre o painel quando dossie_aberto é
	# false. A Fonte Anônima deve atualizar apenas o conteúdo, preservando a
	# decisão da jogadora de manter o dossiê fechado.
	var dossie_estava_aberto: bool = bool(
		hud.get("dossie_aberto")
	)
	if not dossie_estava_aberto:
		# O estado temporário impede somente o bloco de abertura automática.
		# Nenhum botão, painel ou animação é alterado.
		hud.set("dossie_aberto", true)

	hud.alimentar_previsao_evento(
		proximo_evento_global,
		proximo_evento_descricao
	)

	if not dossie_estava_aberto:
		hud.set("dossie_aberto", false)


# ============================================================================
# PRESERVAÇÃO DO EVENTO PREVISTO
# ============================================================================
#
# O fluxo de rodada chama _pre_sortear_proximo_evento() tanto depois de revelar
# um Evento Global quanto na rodada seguinte de Mercado Estável. Sem esta trava,
# o segundo chamado substituía o evento já mostrado à Diana antes do reveal.
# ============================================================================


func _pre_sortear_proximo_evento() -> void:
	if not OnlineTransport.is_host():
		return

	# Há um evento futuro válido aguardando reveal. Enquanto ele for diferente
	# do evento atualmente ativo, ele não pode ser substituído.
	if (
		not proximo_evento_global.is_empty()
		and proximo_evento_global != evento_ativo
	):
		# O evento já está no dossiê. Não reaplica a HUD aqui para não reabrir
		# o painel caso a jogadora tenha decidido fechá-lo.
		return

	# O campo está vazio ou contém o evento que acabou de ser revelado.
	# Nesse caso, o motor original pode escolher o próximo evento normalmente.
	super._pre_sortear_proximo_evento()


func aplicar_snapshot_online(snapshot: Dictionary) -> void:
	super.aplicar_snapshot_online(snapshot)

	# Em reconexões Photon, o snapshot restaura a previsão no estado antes de a
	# HUD do convidado terminar de montar. O deferred reaplica a informação no
	# dossiê quando a interface já está pronta.
	call_deferred(
		"_restaurar_fonte_anonima_diana_do_estado"
	)


func _ready() -> void:
	super._ready()

	# Também cobre partidas retomadas localmente ou por LAN, nas quais o estado
	# salvo pode já conter uma previsão válida quando a cena é aberta.
	call_deferred(
		"_restaurar_fonte_anonima_diana_do_estado"
	)


func _restaurar_fonte_anonima_diana_do_estado() -> void:
	await get_tree().process_frame

	if not is_inside_tree():
		return
	if not dados_economia_jogadores.has("diana"):
		return
	if not lista_turnos.has("diana"):
		return

	var evento_previsto: String = str(
		dados_economia_jogadores["diana"].get(
			"fonte_anonima_evento_previsto",
			""
		)
	)
	if evento_previsto.is_empty():
		return
	if evento_previsto != proximo_evento_global:
		return

	_atualizar_fonte_anonima_diana_local(
		evento_previsto
	)

