extends Control

# Dicionário contendo todos os dados
var banco_de_dados = {
		"yasmin": {
				"nome": "YASMIN KHALIL", "alcunha": "A Corretora",
				"lore": "\"O mercado nao tem moral. Mas eu tenho agenda.\"",
				"passiva": "[PASSIVA] Leilao Preferencial: Vence empates em leilao com 5% de desconto.",
				"passiva2": "[PASSIVA BÔNUS] Relatório de Mercado: Calcula as propriedades com maior chance real de tráfego nos próximos 2 turnos da mesa.",
				"ativa": "[ATIVA — Recarga: 5 turnos] Oferta Irrecusavel: Compra por 150% um terreno vazio de grupo compartilhado, sem desmontar monopolios; exige 2 rodadas de posse e cada rival so pode ser alvo uma vez.",
				"imagem": "res://assets/textures/retrato_yasmin.jpg"
		},
		"breno": {
				"nome": "BRENO VASQUEZ", "alcunha": "O Lobista",
				"lore": "\"Nao e corrupcao. E facilitacao.\"",
				"passiva": "[PASSIVA] Imunidade Politica: Uma vez por partida, Breno escolhe ignorar completamente um Evento Global negativo; contra Taxa Progressiva, cancela o evento para todos.",
				"passiva2": "[PASSIVA BÔNUS] Rede de Contatos: Recebe 50% a mais ao passar pela Casa de Partida ($300).",
				"ativa": "[ATIVA — Recarga: 5 turnos] Decreto Emergencial: Dobra alugueis de um bairro por 2 turnos.",
				"imagem": "res://assets/textures/retrato_breno.jpg"
		},
		"mira": {
				"nome": "MIRA SANTOS", "alcunha": "A Arquiteta Social",
				"lore": "\"Cada tijolo que voce coloca, alguem perde o teto. Eu sei disso. E coloco assim mesmo.\"",
				"passiva": "[PASSIVA] Construcao Acelerada: Constroi casas com 20% de desconto e antes do monopolio.",
				"passiva2": "[PASSIVA BÔNUS] Resistência Estrutural: Propriedades sofrem 50% menos dano em eventos destrutivos.",
				"ativa": "[ATIVA — Recarga: 4 turnos] Retrofit Urbano: Converte uma propriedade com exatamente 2 casas em 1 hotel instantaneamente.",
				"imagem": "res://assets/textures/retrato_mira.jpg"
		},
		"igor": {
				"nome": "IGOR VOLKOV", "alcunha": "O Especulador",
				"lore": "\"Nao compro imoveis. Compro o futuro deles.\"",
				"passiva": "[PASSIVA] Abutre do Mercado: Escolhe uma propriedade de um falido para comprar pelo valor de tabela antes do leilao.",
				"passiva2": "[PASSIVA BÔNUS] Hedge Fund: Nunca perde mais que 50% do saldo em aluguel. Excedente vira dívida.",
				"ativa": "[ATIVA — Recarga: 6 turnos] Especulacao Imobiliaria: Dobra aluguel base de terreno por 3 turnos.",
				"imagem": "res://assets/textures/retrato_igor.jpg"
		},
		"diana": {
				"nome": "DIANA FERRO", "alcunha": "A Infiltrada",
				"lore": "\"Informacao e o unico ativo que nao deprecia.\"",
				"passiva": "[PASSIVA] Dossie: Ve os valores exatos de dinheiro e casas de todos os jogadores.",
				"passiva2": "[PASSIVA BÔNUS] Fonte Anonima: Uma vez por partida, ve o proximo evento global antes do reveal.",
				"ativa": "[ATIVA — Recarga: 3 turnos] Vazamento Seletivo: Zera o proximo aluguel valido de um adversario e permanece ativo ate acontecer.",
				"imagem": "res://assets/textures/retrato_diana.jpg"
		},
		"kofi": {
				"nome": "KOFI MENSAH", "alcunha": "O Construtor de Comunidade",
				"lore": "\"Voce pode comprar o terreno. Mas nao compra o que foi construido nele.\"",
				"passiva": "[PASSIVA] Raizes: Propriedades nunca podem ser tomadas em eventos de confisco.",
				"passiva2": "[PASSIVA BÔNUS] Solidariedade: Recebe $200 quando outro jogador declara falência.",
				"ativa": "[ATIVA — Recarga: 4 turnos] Mutirao: Constroi uma casa simultaneamente pagando 60%.",
				"imagem": "res://assets/textures/retrato_kofi.jpg"
		}
}

# Variáveis de Controle Multiplayer
var ordem_personagens = ["yasmin", "breno", "mira", "igor", "diana", "kofi"]
var personagens_travados = []
var personagem_atual = ""
var minha_escolha_confirmada = false
var host_pronto_para_iniciar = false

# Referências aos nós da interface
@onready var retrato = $MargemPrincipal/LayoutHorizontal/LadoDireito_Detalhes/VBoxDetalhes/Cabecalho/RetratoGrande
@onready var label_nome = $MargemPrincipal/LayoutHorizontal/LadoDireito_Detalhes/VBoxDetalhes/Cabecalho/InfoTitulos/NomePersonagem
@onready var label_alcunha = $MargemPrincipal/LayoutHorizontal/LadoDireito_Detalhes/VBoxDetalhes/Cabecalho/InfoTitulos/AlcunhaPersonagem
@onready var label_lore = $MargemPrincipal/LayoutHorizontal/LadoDireito_Detalhes/VBoxDetalhes/LorePersonagem
@onready var label_passiva = $MargemPrincipal/LayoutHorizontal/LadoDireito_Detalhes/VBoxDetalhes/Habilidades/Passiva
@onready var label_passiva2 = $MargemPrincipal/LayoutHorizontal/LadoDireito_Detalhes/VBoxDetalhes/Habilidades/Passiva2
@onready var label_ativa = $MargemPrincipal/LayoutHorizontal/LadoDireito_Detalhes/VBoxDetalhes/Habilidades/Ativa
@onready var btn_confirmar = $MargemPrincipal/LayoutHorizontal/LadoDireito_Detalhes/VBoxDetalhes/BtnConfirmar

# Dicionário com a referência física dos botões para podermos desativá-los
@onready var botoes = {
		"yasmin": $MargemPrincipal/LayoutHorizontal/LadoEsquerdo_Lista/PainelGrade/GradePersonagens/BtnYasmin,
		"breno": $MargemPrincipal/LayoutHorizontal/LadoEsquerdo_Lista/PainelGrade/GradePersonagens/BtnBreno,
		"mira": $MargemPrincipal/LayoutHorizontal/LadoEsquerdo_Lista/PainelGrade/GradePersonagens/BtnMira,
		"igor": $MargemPrincipal/LayoutHorizontal/LadoEsquerdo_Lista/PainelGrade/GradePersonagens/BtnIgor,
		"diana": $MargemPrincipal/LayoutHorizontal/LadoEsquerdo_Lista/PainelGrade/GradePersonagens/BtnDiana,
		"kofi": $MargemPrincipal/LayoutHorizontal/LadoEsquerdo_Lista/PainelGrade/GradePersonagens/BtnKofi
}

func _ready() -> void:
	if not OnlineTransport.jogador_desconectado.is_connected(_on_peer_desconectado_selecao):
		OnlineTransport.jogador_desconectado.connect(_on_peer_desconectado_selecao)
	if not OnlineTransport.host_alterado.is_connected(_on_host_alterado_selecao):
		OnlineTransport.host_alterado.connect(_on_host_alterado_selecao)
	Global.meu_peer_id = OnlineTransport.local_player_id()
	if OnlineTransport.usando_photon():
		OnlineTransport.definir_fase_online("selecao", OnlineTransport.CENA_SELECAO)
	_reconstruir_escolhas_existentes()
	_selecionar_primeiro_disponivel()
	_avaliar_prontidao_da_sala()
	call_deferred("_animar_entrada_interface")


func _exit_tree() -> void:
	if OnlineTransport.jogador_desconectado.is_connected(_on_peer_desconectado_selecao):
		OnlineTransport.jogador_desconectado.disconnect(_on_peer_desconectado_selecao)
	if OnlineTransport.host_alterado.is_connected(_on_host_alterado_selecao):
		OnlineTransport.host_alterado.disconnect(_on_host_alterado_selecao)


func _reconstruir_escolhas_existentes() -> void:
	personagens_travados.clear()
	for peer_variant in Global.escolhas_da_mesa.keys():
		var peer_id := int(peer_variant)
		var id_personagem := str(Global.escolhas_da_mesa[peer_variant])
		if not banco_de_dados.has(id_personagem):
			continue
		if not personagens_travados.has(id_personagem):
			personagens_travados.append(id_personagem)
		if botoes.has(id_personagem):
			botoes[id_personagem].disabled = true
			botoes[id_personagem].text = "(INDISPONÍVEL)"
			botoes[id_personagem].modulate = Color(0.4, 0.4, 0.4)
		if peer_id == OnlineTransport.local_player_id():
			minha_escolha_confirmada = true
			personagem_atual = id_personagem

	if minha_escolha_confirmada:
		_aplicar_dados_personagem(personagem_atual)


func atualizar_painel(id_personagem: String) -> void:
	if minha_escolha_confirmada:
		return
	_aplicar_dados_personagem(id_personagem)


func _aplicar_dados_personagem(id_personagem: String) -> void:
	if not banco_de_dados.has(id_personagem):
		return

	personagem_atual = id_personagem
	_marcar_personagem_visual(id_personagem)
	var dados: Dictionary = banco_de_dados[id_personagem]
	label_nome.text = str(dados["nome"])
	label_alcunha.text = str(dados["alcunha"])
	label_lore.text = str(dados["lore"])
	label_passiva.text = str(dados["passiva"])
	if label_passiva2:
		label_passiva2.text = str(dados.get("passiva2", ""))
	label_ativa.text = str(dados["ativa"])
	if ResourceLoader.exists(str(dados["imagem"])):
		retrato.texture = load(str(dados["imagem"]))
	else:
		retrato.texture = null


func _marcar_personagem_visual(id_personagem: String) -> void:
	for id_botao in botoes.keys():
		var botao: Button = botoes[id_botao]
		botao.set_pressed_no_signal(str(id_botao) == id_personagem)

	if retrato == null:
		return
	retrato.modulate.a = 0.55
	var tween := create_tween()
	tween.tween_property(retrato, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _animar_entrada_interface() -> void:
	var lado_esquerdo: Control = $MargemPrincipal/LayoutHorizontal/LadoEsquerdo_Lista
	var lado_direito: Control = $MargemPrincipal/LayoutHorizontal/LadoDireito_Detalhes
	var logo: Control = $LogoMetropolis

	for controle in [logo, lado_esquerdo, lado_direito]:
		controle.pivot_offset = controle.size * 0.5
		controle.modulate.a = 0.0
		controle.scale = Vector2(0.97, 0.97)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(logo, "modulate:a", 1.0, 0.28)
	tween.tween_property(logo, "scale", Vector2.ONE, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(lado_esquerdo, "modulate:a", 1.0, 0.34).set_delay(0.08)
	tween.tween_property(lado_esquerdo, "scale", Vector2.ONE, 0.44).set_delay(0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(lado_direito, "modulate:a", 1.0, 0.34).set_delay(0.16)
	tween.tween_property(lado_direito, "scale", Vector2.ONE, 0.44).set_delay(0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	if not minha_escolha_confirmada and botoes.has(personagem_atual):
		botoes[personagem_atual].grab_focus()


func _selecionar_primeiro_disponivel() -> void:
	for personagem in ordem_personagens:
		if not personagens_travados.has(personagem):
			atualizar_painel(personagem)
			return
	label_nome.text = "PARTIDA CHEIA"
	label_alcunha.text = "Todos os personagens foram escolhidos"
	label_lore.text = "\"Aguarde o host iniciar a partida...\""
	label_passiva.text = "[AGUARDANDO]"
	if label_passiva2:
		label_passiva2.text = ""
	label_ativa.text = "[AGUARDANDO]"
	retrato.texture = null
	btn_confirmar.disabled = true
	btn_confirmar.text = "AGUARDANDO INÍCIO..."
	btn_confirmar.modulate = Color(0.5, 0.5, 0.5)


func _on_btn_yasmin_pressed() -> void: atualizar_painel("yasmin")
func _on_btn_breno_pressed() -> void: atualizar_painel("breno")
func _on_btn_mira_pressed() -> void: atualizar_painel("mira")
func _on_btn_igor_pressed() -> void: atualizar_painel("igor")
func _on_btn_diana_pressed() -> void: atualizar_painel("diana")
func _on_btn_kofi_pressed() -> void: atualizar_painel("kofi")


func _on_btn_voltar_pressed() -> void:
	if OnlineTransport.usando_photon():
		if OnlineTransport.is_host():
			OnlineTransport.mudar_cena_para_todos(OnlineTransport.CENA_ONLINE, true)
		else:
			PhotonManager.sair_sala()
			Global.modo_online = false
			get_tree().change_scene_to_file(OnlineTransport.CENA_ONLINE)
		return
	if NetworkManager.esta_hospedando():
		OnlineTransport.send_all(NetworkManager, &"_voltar_lobby_rede", [], true, true)
	else:
		NetworkManager.desconectar("Você saiu da seleção de personagens.")
		get_tree().change_scene_to_file("res://scenes/ui/lobby/lobby.tscn")


func _on_btn_confirmar_pressed() -> void:
	if host_pronto_para_iniciar and OnlineTransport.is_host():
		_iniciar_tabuleiro_para_todos()
		return
	if personagem_atual.is_empty() or personagens_travados.has(personagem_atual):
		_selecionar_primeiro_disponivel()
		return

	btn_confirmar.disabled = true
	btn_confirmar.text = "CONFIRMANDO..."
	if OnlineTransport.is_host():
		_processar_solicitacao_personagem(OnlineTransport.local_player_id(), personagem_atual)
	else:
		OnlineTransport.send_host(
			self,
			&"_solicitar_personagem_servidor",
			[personagem_atual],
			false
		)


@rpc("any_peer", "call_remote", "reliable")
func _solicitar_personagem_servidor(id_personagem: String) -> void:
	if not OnlineTransport.is_host():
		return
	var peer_solicitante := OnlineTransport.get_remote_sender_id()
	_processar_solicitacao_personagem(peer_solicitante, id_personagem)


func _processar_solicitacao_personagem(peer_id: int, id_personagem: String) -> void:
	if not OnlineTransport.is_host():
		return
	var ids_validos := OnlineTransport.get_peer_ids(true)
	ids_validos.append(OnlineTransport.local_player_id())
	if not ids_validos.has(peer_id):
		return
	if not banco_de_dados.has(id_personagem):
		_enviar_rejeicao_escolha(peer_id, "Personagem inválido.")
		return
	if Global.escolhas_da_mesa.has(peer_id):
		_enviar_rejeicao_escolha(peer_id, "Você já confirmou um personagem.")
		return
	if personagens_travados.has(id_personagem):
		_enviar_rejeicao_escolha(
			peer_id,
			"Esse personagem acabou de ser escolhido por outro jogador."
		)
		return

	var user_id := ""
	if OnlineTransport.usando_photon():
		user_id = PhotonManager.obter_user_id_jogador(peer_id)
	OnlineTransport.send_all(
		self,
		&"_confirmar_personagem_na_rede",
		[id_personagem, peer_id, user_id],
		true,
		true
	)


func _enviar_rejeicao_escolha(peer_id: int, mensagem: String) -> void:
	OnlineTransport.send_player(
		peer_id,
		self,
		&"_notificar_escolha_rejeitada",
		[mensagem],
		true,
		true
	)


@rpc("authority", "call_remote", "reliable")
func _notificar_escolha_rejeitada(mensagem: String) -> void:
	minha_escolha_confirmada = false
	btn_confirmar.disabled = false
	btn_confirmar.text = mensagem
	btn_confirmar.modulate = Color(1.0, 0.45, 0.35)
	_selecionar_primeiro_disponivel()


@rpc("authority", "call_local", "reliable")
func _confirmar_personagem_na_rede(id_p: String, peer_id: int, user_id: String = "") -> void:
	if Global.escolhas_da_mesa.has(peer_id):
		return
	if personagens_travados.has(id_p):
		return

	Global.escolhas_da_mesa[peer_id] = id_p
	if not user_id.is_empty():
		Global.user_ids_da_mesa[peer_id] = user_id
		Global.escolhas_por_user_id[user_id] = id_p
	personagens_travados.append(id_p)

	if botoes.has(id_p):
		botoes[id_p].disabled = true
		botoes[id_p].text = "(INDISPONÍVEL)"
		botoes[id_p].modulate = Color(0.4, 0.4, 0.4)

	if peer_id == OnlineTransport.local_player_id():
		minha_escolha_confirmada = true
		personagem_atual = id_p
		btn_confirmar.disabled = true
		btn_confirmar.text = "AGUARDANDO JOGADORES..."
		btn_confirmar.modulate = Color(0.5, 0.8, 0.5)
	elif personagem_atual == id_p and not minha_escolha_confirmada:
		_selecionar_primeiro_disponivel()
	_avaliar_prontidao_da_sala()


func _avaliar_prontidao_da_sala() -> void:
	var total_jogadores_na_sala := OnlineTransport.total_jogadores()
	host_pronto_para_iniciar = false

	if total_jogadores_na_sala < 2:
		btn_confirmar.disabled = true
		btn_confirmar.text = "AGUARDANDO +1 JOGADOR..."
		btn_confirmar.modulate = Color(0.8, 0.5, 0.3)
		return

	if personagens_travados.size() != total_jogadores_na_sala:
		if minha_escolha_confirmada:
			btn_confirmar.disabled = true
			btn_confirmar.text = "AGUARDANDO JOGADORES..."
			btn_confirmar.modulate = Color(0.5, 0.8, 0.5)
		return

	if OnlineTransport.is_host():
		host_pronto_para_iniciar = true
		btn_confirmar.disabled = false
		btn_confirmar.text = "INICIAR PARTIDA"
		btn_confirmar.modulate = Color(0.2, 0.6, 1.0)
	else:
		btn_confirmar.disabled = true
		btn_confirmar.text = "AGUARDANDO O HOST INICIAR..."


func _on_peer_desconectado_selecao(peer_id: int, inativo: bool = false) -> void:
	# O Photon preserva a vaga durante o TTL. Não solte o personagem enquanto
	# a desconexão for temporária, para permitir reentrada com a mesma conta.
	if inativo and OnlineTransport.usando_photon():
		_avaliar_prontidao_da_sala()
		return
	if not Global.escolhas_da_mesa.has(peer_id):
		_avaliar_prontidao_da_sala()
		return

	var personagem_id := str(Global.escolhas_da_mesa[peer_id])
	var user_id := str(Global.user_ids_da_mesa.get(peer_id, ""))
	Global.escolhas_da_mesa.erase(peer_id)
	Global.user_ids_da_mesa.erase(peer_id)
	if not user_id.is_empty():
		Global.escolhas_por_user_id.erase(user_id)
	personagens_travados.erase(personagem_id)
	if botoes.has(personagem_id):
		botoes[personagem_id].disabled = false
		botoes[personagem_id].text = personagem_id.to_upper()
		botoes[personagem_id].modulate = Color.WHITE
	if not minha_escolha_confirmada and personagem_atual.is_empty():
		_selecionar_primeiro_disponivel()
	_avaliar_prontidao_da_sala()


func _on_host_alterado_selecao(_eh_host: bool) -> void:
	_avaliar_prontidao_da_sala()


func _iniciar_tabuleiro_para_todos() -> void:
	if not OnlineTransport.is_host() or not host_pronto_para_iniciar:
		return
	Global.meu_peer_id = OnlineTransport.local_player_id()
	Global.modo_online = OnlineTransport.usando_photon()
	OnlineTransport.definir_fase_online("tabuleiro", OnlineTransport.CENA_TABULEIRO)
	OnlineTransport.mudar_cena_para_todos(OnlineTransport.CENA_TABULEIRO, false)
