extends Node

# ============================================================================
# METROPOLIS IN RUINS — GERENCIADOR CENTRAL DE ÁUDIO
# ============================================================================
# Trilhas automáticas:
# - Menu principal
# - Lobby LAN
# - Menu/sala Online
# - Partida no tabuleiro
#
# A seleção de personagens mantém a trilha do modo de rede ativo.
# Todos os BaseButton que emitem pressed usam ui_pop_01.wav.
# Volumes separados: Geral, Música, Efeitos e Botões.
# Preferências: user://configuracao_audio.cfg.
# ============================================================================

const CENA_MENU_PRINCIPAL: String = "res://scenes/ui/tela_inicial/menu_principal.tscn"
const CENA_LAN: String = "res://scenes/ui/lobby/lobby.tscn"
const CENA_ONLINE: String = "res://scenes/ui/online/online_menu.tscn"
const CENA_SELECAO: String = "res://scenes/ui/selecao_personagem/selecao_personagem.tscn"

# tabuleiro.tscn é somente a tela de carregamento.
# tabuleiro_jogo.tscn é o tabuleiro realmente executado por LAN, Online e local.
# tutorial_jogo.tscn contém uma instância do mesmo tabuleiro jogável.
const CENA_TABULEIRO_CARREGAMENTO: String = "res://scenes/gameplay/tabuleiro/tabuleiro.tscn"
const CENA_TABULEIRO_JOGO: String = "res://scenes/gameplay/tabuleiro/tabuleiro_jogo.tscn"
const CENA_TUTORIAL_JOGO: String = "res://scenes/ui/tutorial/tutorial_jogo.tscn"

const CAMINHO_CONFIGURACAO: String = "user://configuracao_audio.cfg"

const BUS_MUSICA: StringName = &"Musica"
const BUS_EFEITOS: StringName = &"Efeitos"
const BUS_BOTOES: StringName = &"Botoes"

const VOLUME_PADRAO_GERAL: float = 100.0
const VOLUME_PADRAO_MUSICA: float = 55.0
const VOLUME_PADRAO_EFEITOS: float = 70.0
const VOLUME_PADRAO_BOTOES: float = 75.0
const VOLUME_BASE_PLAYER_MUSICA_DB: float = -8.0
const OFFSET_LOOP_PARTIDA_SEGUNDOS: float = 12.0
const INTERVALO_VERIFICACAO_CENA: float = 0.35

const MUSICA_MENU: AudioStreamOggVorbis = preload(
	"res://assets/audio/music/tema_menu_metropolis_loop.ogg"
)
const MUSICA_LAN: AudioStreamOggVorbis = preload(
	"res://assets/audio/music/tema_lan_loop.ogg"
)
const MUSICA_ONLINE: AudioStreamOggVorbis = preload(
	"res://assets/audio/music/tema_online_loop.ogg"
)
const MUSICA_PARTIDA: AudioStreamOggVorbis = preload(
	"res://assets/audio/music/tema_partida_loop.ogg"
)
const SOM_BOTAO: AudioStreamWAV = preload(
	"res://assets/audio/ui/ui_pop_01.wav"
)
const SOM_DADOS_GIRANDO: AudioStreamWAV = preload(
	"res://assets/audio/sfx/dados_girando_simples.wav"
)
const CAMINHO_SOM_PULO_PINO: String = (
	"res://assets/audio/sfx/pulo_pino_ultra_simples.ogg"
)
const CAMINHO_SCRIPT_PINO: String = (
	"res://scenes/gameplay/tabuleiro/pino_personagem.gd"
)
const FONTE_UI: Font = preload("res://assets/fonts/m5x7.ttf")

enum TipoTrilha {
	NENHUMA,
	MENU,
	LAN,
	ONLINE,
	PARTIDA,
}

var _volume_geral: float = VOLUME_PADRAO_GERAL
var _volume_musica: float = VOLUME_PADRAO_MUSICA
var _volume_efeitos: float = VOLUME_PADRAO_EFEITOS
var _volume_botoes: float = VOLUME_PADRAO_BOTOES
var _musica_ativa: bool = true

var _player_musica: AudioStreamPlayer
var _player_dados: AudioStreamPlayer
var _player_pulo_pino: AudioStreamPlayer
var _players_botoes: Array[AudioStreamPlayer] = []
var _indice_player_botao: int = 0

# WeakRef evita manter pinos removidos vivos.
var _pinos_rastreados: Dictionary = {}
var _casa_anterior_pinos: Dictionary = {}
var _movimento_anterior_pinos: Dictionary = {}
var _tween_musica: Tween
var _timer_salvar: Timer

var _trilha_atual: int = TipoTrilha.NENHUMA
var _trilha_solicitada: int = TipoTrilha.NENHUMA
var _token_troca_musica: int = 0

# A tela de carregamento define current_scene manualmente depois de instanciar
# o destino, então também observamos diretamente a cena atual.
var _ultima_cena_observada: Node = null
var _tempo_verificacao_cena: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_garantir_barramentos()
	_carregar_configuracao()
	_aplicar_todos_os_volumes()
	_criar_players()
	_criar_timer_salvamento()

	var arvore := get_tree()
	if not arvore.node_added.is_connected(_ao_adicionar_no):
		arvore.node_added.connect(_ao_adicionar_no)
	if not arvore.scene_changed.is_connected(_ao_mudar_cena):
		arvore.scene_changed.connect(_ao_mudar_cena)

	set_process(true)
	call_deferred("_conectar_botoes_existentes")
	call_deferred("_registrar_pinos_existentes")
	call_deferred("_atualizar_cena_atual")
	call_deferred(
		"_integrar_check_musica_pausa",
		get_tree().current_scene
	)


func _process(delta: float) -> void:
	_verificar_pulos_pinos()

	var cena_atual: Node = get_tree().current_scene

	# Detecta inclusive atribuições manuais a SceneTree.current_scene.
	if cena_atual != _ultima_cena_observada:
		_ultima_cena_observada = cena_atual
		_atualizar_cena_atual()

	# Confirma periodicamente que a trilha esperada continua tocando.
	_tempo_verificacao_cena += delta
	if _tempo_verificacao_cena < INTERVALO_VERIFICACAO_CENA:
		return
	_tempo_verificacao_cena = 0.0

	var trilha_esperada: int = _determinar_trilha(cena_atual)
	if (
		trilha_esperada != TipoTrilha.NENHUMA
		and (
			trilha_esperada != _trilha_atual
			or _player_musica == null
			or not _player_musica.playing
		)
	):
		_solicitar_trilha(trilha_esperada)


# ============================================================================
# BARRAMENTOS E CONFIGURAÇÃO
# ============================================================================

func _garantir_barramentos() -> void:
	_garantir_barramento(BUS_MUSICA)
	_garantir_barramento(BUS_EFEITOS)
	_garantir_barramento(BUS_BOTOES)


func _garantir_barramento(nome: StringName) -> int:
	var indice := AudioServer.get_bus_index(nome)
	if indice >= 0:
		return indice

	AudioServer.add_bus()
	indice = AudioServer.bus_count - 1
	AudioServer.set_bus_name(indice, nome)
	AudioServer.set_bus_send(indice, &"Master")
	return indice


func _carregar_configuracao() -> void:
	var configuracao := ConfigFile.new()
	var erro := configuracao.load(CAMINHO_CONFIGURACAO)
	if erro != OK:
		return

	_volume_geral = clampf(float(
		configuracao.get_value("audio", "geral", VOLUME_PADRAO_GERAL)
	), 0.0, 100.0)
	_volume_musica = clampf(float(
		configuracao.get_value("audio", "musica", VOLUME_PADRAO_MUSICA)
	), 0.0, 100.0)
	_musica_ativa = bool(
		configuracao.get_value("audio", "musica_ativa", true)
	)
	_volume_efeitos = clampf(float(
		configuracao.get_value("audio", "efeitos", VOLUME_PADRAO_EFEITOS)
	), 0.0, 100.0)
	_volume_botoes = clampf(float(
		configuracao.get_value("audio", "botoes", VOLUME_PADRAO_BOTOES)
	), 0.0, 100.0)


func _criar_timer_salvamento() -> void:
	_timer_salvar = Timer.new()
	_timer_salvar.name = "TimerSalvarAudio"
	_timer_salvar.one_shot = true
	_timer_salvar.wait_time = 0.25
	_timer_salvar.process_callback = Timer.TIMER_PROCESS_IDLE
	_timer_salvar.process_mode = Node.PROCESS_MODE_ALWAYS
	_timer_salvar.timeout.connect(_salvar_configuracao)
	add_child(_timer_salvar)


func _agendar_salvamento() -> void:
	if _timer_salvar == null or not is_instance_valid(_timer_salvar):
		_salvar_configuracao()
		return
	_timer_salvar.start()


func _salvar_configuracao() -> void:
	var configuracao := ConfigFile.new()
	configuracao.set_value("audio", "geral", _volume_geral)
	configuracao.set_value("audio", "musica", _volume_musica)
	configuracao.set_value("audio", "musica_ativa", _musica_ativa)
	configuracao.set_value("audio", "efeitos", _volume_efeitos)
	configuracao.set_value("audio", "botoes", _volume_botoes)
	var erro := configuracao.save(CAMINHO_CONFIGURACAO)
	if erro != OK:
		push_warning(
			"Não foi possível salvar as configurações de áudio: %s"
			% error_string(erro)
		)


func _aplicar_todos_os_volumes() -> void:
	_aplicar_volume_barramento(&"Master", _volume_geral)
	_aplicar_volume_barramento(BUS_MUSICA, _volume_musica)
	_aplicar_estado_musica()
	_aplicar_volume_barramento(BUS_EFEITOS, _volume_efeitos)
	_aplicar_volume_barramento(BUS_BOTOES, _volume_botoes)


func _aplicar_volume_barramento(nome: StringName, valor: float) -> void:
	var indice := AudioServer.get_bus_index(nome)
	if indice < 0:
		return

	var limitado := clampf(valor, 0.0, 100.0)
	var linear := maxf(limitado / 100.0, 0.0001)
	AudioServer.set_bus_volume_db(indice, linear_to_db(linear))
	AudioServer.set_bus_mute(indice, limitado <= 0.0)


func _aplicar_estado_musica() -> void:
	var indice: int = AudioServer.get_bus_index(BUS_MUSICA)
	if indice < 0:
		return

	AudioServer.set_bus_mute(
		indice,
		not _musica_ativa or _volume_musica <= 0.0
	)


func definir_volume_geral(valor: float) -> void:
	_volume_geral = clampf(valor, 0.0, 100.0)
	_aplicar_volume_barramento(&"Master", _volume_geral)
	_agendar_salvamento()


func definir_volume_musica(valor: float) -> void:
	_volume_musica = clampf(valor, 0.0, 100.0)
	_aplicar_volume_barramento(BUS_MUSICA, _volume_musica)
	_aplicar_estado_musica()
	_agendar_salvamento()


func definir_musica_ativa(ativa: bool) -> void:
	_musica_ativa = ativa
	_aplicar_estado_musica()
	_agendar_salvamento()


func musica_esta_ativa() -> bool:
	return _musica_ativa


func definir_volume_efeitos(valor: float) -> void:
	_volume_efeitos = clampf(valor, 0.0, 100.0)
	_aplicar_volume_barramento(BUS_EFEITOS, _volume_efeitos)
	_agendar_salvamento()


func definir_volume_botoes(valor: float) -> void:
	_volume_botoes = clampf(valor, 0.0, 100.0)
	_aplicar_volume_barramento(BUS_BOTOES, _volume_botoes)
	_agendar_salvamento()


func obter_volume_geral() -> float:
	return _volume_geral


func obter_volume_musica() -> float:
	return _volume_musica


func obter_volume_efeitos() -> float:
	return _volume_efeitos


func obter_volume_botoes() -> float:
	return _volume_botoes


# ============================================================================
# PLAYERS E TROCA DE TRILHA
# ============================================================================

func _criar_players() -> void:
	_player_musica = AudioStreamPlayer.new()
	_player_musica.name = "PlayerMusicaGlobal"
	_player_musica.bus = BUS_MUSICA
	_player_musica.volume_db = VOLUME_BASE_PLAYER_MUSICA_DB
	_player_musica.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player_musica)

	_player_dados = AudioStreamPlayer.new()
	_player_dados.name = "SomDadosGirando"
	_player_dados.bus = BUS_EFEITOS
	_player_dados.stream = SOM_DADOS_GIRANDO
	_player_dados.volume_db = -3.0
	_player_dados.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player_dados)

	_player_pulo_pino = AudioStreamPlayer.new()
	_player_pulo_pino.name = "SomPuloPino"
	_player_pulo_pino.bus = BUS_EFEITOS
	_player_pulo_pino.volume_db = -8.0
	_player_pulo_pino.process_mode = Node.PROCESS_MODE_ALWAYS

	# Carregamento protegido: a ausência do arquivo não impede o projeto
	# inteiro de abrir. Com o OGG presente, o efeito funciona normalmente.
	if ResourceLoader.exists(CAMINHO_SOM_PULO_PINO):
		var stream_pulo: AudioStream = load(
			CAMINHO_SOM_PULO_PINO
		) as AudioStream
		_player_pulo_pino.stream = stream_pulo

	add_child(_player_pulo_pino)

	for indice in range(4):
		var player := AudioStreamPlayer.new()
		player.name = "SomBotao%02d" % (indice + 1)
		player.bus = BUS_BOTOES
		player.stream = SOM_BOTAO
		player.volume_db = -2.0
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_players_botoes.append(player)


func tocar_som_botao() -> void:
	if _players_botoes.is_empty():
		return

	var player: AudioStreamPlayer = _players_botoes[_indice_player_botao]
	_indice_player_botao = (_indice_player_botao + 1) % _players_botoes.size()
	player.pitch_scale = 1.0
	player.play()


func tocar_som_dados() -> void:
	if _player_dados == null or not is_instance_valid(_player_dados):
		return

	# Garante sincronização com o primeiro quadro da animação mesmo se uma
	# rolagem anterior tiver sido interrompida por troca de cena.
	_player_dados.stop()
	_player_dados.pitch_scale = 1.0
	_player_dados.play()


func tocar_som_pulo_pino() -> void:
	if (
		_player_pulo_pino == null
		or not is_instance_valid(_player_pulo_pino)
		or _player_pulo_pino.stream == null
	):
		return

	_player_pulo_pino.stop()
	_player_pulo_pino.pitch_scale = 1.0
	_player_pulo_pino.play()


func _solicitar_trilha(tipo: int) -> void:
	if _player_musica == null or not is_instance_valid(_player_musica):
		return

	var tween_ativo: bool = (
		_tween_musica != null
		and _tween_musica.is_valid()
	)

	# O watchdog e os sinais de cena podem solicitar a mesma faixa várias
	# vezes enquanto o fade ainda está em andamento. Não reinicia essa troca:
	# isso permite que o callback de _iniciar_trilha seja finalmente executado.
	if tipo == _trilha_solicitada:
		if tipo == _trilha_atual and _player_musica.playing:
			# Recupera uma faixa que tenha ficado silenciosa devido a uma
			# transição antiga interrompida antes desta correção.
			if (
				not tween_ativo
				and _player_musica.volume_db
				< VOLUME_BASE_PLAYER_MUSICA_DB - 0.1
			):
				_restaurar_volume_musica()
			return

		# A mesma troca ainda está sendo processada. Mantém o Tween existente.
		if tween_ativo:
			return

	_trilha_solicitada = tipo
	_token_troca_musica += 1
	var token: int = _token_troca_musica

	if tween_ativo:
		_tween_musica.kill()

	# A cena voltou para a faixa atual enquanto ela estava diminuindo.
	# Em vez de manter o player em -45 dB, restaura o volume suavemente.
	if tipo == _trilha_atual and _player_musica.playing:
		_restaurar_volume_musica()
		return

	if not _player_musica.playing:
		_iniciar_trilha(tipo, token)
		return

	_tween_musica = create_tween()
	_tween_musica.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween_musica.tween_property(
		_player_musica,
		"volume_db",
		-45.0,
		0.42
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween_musica.tween_callback(_iniciar_trilha.bind(tipo, token))


func _restaurar_volume_musica() -> void:
	if _player_musica == null or not is_instance_valid(_player_musica):
		return

	if _tween_musica != null and _tween_musica.is_valid():
		_tween_musica.kill()

	if not _player_musica.playing:
		_player_musica.volume_db = VOLUME_BASE_PLAYER_MUSICA_DB
		return

	if (
		absf(
			_player_musica.volume_db
			- VOLUME_BASE_PLAYER_MUSICA_DB
		) <= 0.1
	):
		_player_musica.volume_db = VOLUME_BASE_PLAYER_MUSICA_DB
		return

	_tween_musica = create_tween()
	_tween_musica.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween_musica.tween_property(
		_player_musica,
		"volume_db",
		VOLUME_BASE_PLAYER_MUSICA_DB,
		0.24
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _iniciar_trilha(tipo: int, token: int) -> void:
	if token != _token_troca_musica:
		return

	if tipo == TipoTrilha.NENHUMA:
		_player_musica.stop()
		_player_musica.stream = null
		_player_musica.volume_db = VOLUME_BASE_PLAYER_MUSICA_DB
		_trilha_atual = TipoTrilha.NENHUMA
		return

	var base := _obter_stream_trilha(tipo)
	if base == null:
		return

	var loop := base.duplicate() as AudioStreamOggVorbis
	if loop != null:
		loop.loop = true
		if tipo == TipoTrilha.PARTIDA:
			loop.loop_offset = OFFSET_LOOP_PARTIDA_SEGUNDOS
		else:
			loop.loop_offset = 0.0
		_player_musica.stream = loop
	else:
		_player_musica.stream = base

	_player_musica.volume_db = -45.0
	_player_musica.play()
	_trilha_atual = tipo

	_tween_musica = create_tween()
	_tween_musica.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween_musica.tween_property(
		_player_musica,
		"volume_db",
		VOLUME_BASE_PLAYER_MUSICA_DB,
		0.72
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _obter_stream_trilha(tipo: int) -> AudioStreamOggVorbis:
	match tipo:
		TipoTrilha.MENU:
			return MUSICA_MENU
		TipoTrilha.LAN:
			return MUSICA_LAN
		TipoTrilha.ONLINE:
			return MUSICA_ONLINE
		TipoTrilha.PARTIDA:
			return MUSICA_PARTIDA
	return null


# ============================================================================
# DETECÇÃO AUTOMÁTICA DAS CENAS
# ============================================================================

func _eh_pino_personagem(no: Node) -> bool:
	if no == null or not is_instance_valid(no):
		return false

	var script_pino: Script = no.get_script() as Script
	return (
		script_pino != null
		and script_pino.resource_path == CAMINHO_SCRIPT_PINO
	)


func _registrar_pino(pino: Node) -> void:
	if not _eh_pino_personagem(pino):
		return

	var identificador: int = pino.get_instance_id()
	_pinos_rastreados[identificador] = weakref(pino)
	_casa_anterior_pinos[identificador] = int(
		pino.get("casa_atual")
	)
	_movimento_anterior_pinos[identificador] = bool(
		pino.get("esta_movendo")
	)


func _registrar_pinos_existentes() -> void:
	_registrar_pinos_recursivamente(get_tree().root)


func _registrar_pinos_recursivamente(no: Node) -> void:
	if _eh_pino_personagem(no):
		_registrar_pino(no)

	for filho: Node in no.get_children():
		_registrar_pinos_recursivamente(filho)


func _remover_rastreamento_pino(
	identificador: int
) -> void:
	_pinos_rastreados.erase(identificador)
	_casa_anterior_pinos.erase(identificador)
	_movimento_anterior_pinos.erase(identificador)


func _verificar_pulos_pinos() -> void:
	for identificador_variant: Variant in (
		_pinos_rastreados.keys()
	):
		var identificador: int = int(
			identificador_variant
		)
		var referencia: WeakRef = (
			_pinos_rastreados.get(
				identificador
			) as WeakRef
		)
		if referencia == null:
			_remover_rastreamento_pino(identificador)
			continue

		var pino: Node = referencia.get_ref() as Node
		if pino == null or not is_instance_valid(pino):
			_remover_rastreamento_pino(identificador)
			continue

		var casa_atual: int = int(
			pino.get("casa_atual")
		)
		var casa_anterior: int = int(
			_casa_anterior_pinos.get(
				identificador,
				casa_atual
			)
		)
		var movendo_agora: bool = bool(
			pino.get("esta_movendo")
		)
		var movia_antes: bool = bool(
			_movimento_anterior_pinos.get(
				identificador,
				false
			)
		)

		if casa_atual != casa_anterior:
			_casa_anterior_pinos[identificador] = (
				casa_atual
			)
			# Somente movimentos animados produzem o tic.
			# O estado anterior captura também o último salto.
			if movendo_agora or movia_antes:
				tocar_som_pulo_pino()

		_movimento_anterior_pinos[identificador] = (
			movendo_agora
		)


func _ao_mudar_cena() -> void:
	call_deferred("_atualizar_cena_atual")


func _atualizar_cena_atual() -> void:
	var cena: Node = get_tree().current_scene
	_ultima_cena_observada = cena

	var trilha: int = _determinar_trilha(cena)
	_solicitar_trilha(trilha)

	if _eh_cena_menu(cena):
		call_deferred("_integrar_controles_opcoes", cena)

	call_deferred("_integrar_check_musica_pausa", cena)

	# Na seleção, a rede pode terminar de confirmar o estado alguns frames depois.
	if cena != null and cena.scene_file_path == CENA_SELECAO:
		_rever_trilha_selecao_depois()


func _rever_trilha_selecao_depois() -> void:
	await get_tree().create_timer(0.45, true, false, true).timeout
	var cena := get_tree().current_scene
	if cena != null and cena.scene_file_path == CENA_SELECAO:
		_solicitar_trilha(_determinar_trilha(cena))


func _determinar_trilha(cena: Node) -> int:
	if cena == null or not is_instance_valid(cena):
		return TipoTrilha.NENHUMA

	var caminho: String = cena.scene_file_path

	# O tutorial é instanciado atrás desta tela e current_scene só é alterada
	# depois. Assim a trilha da partida começa ainda durante o carregamento.
	if cena.name == &"CarregamentoTutorial":
		return TipoTrilha.PARTIDA

	# A música da partida depende somente de estar no fluxo do tabuleiro.
	# Não importa se a partida é tutorial, local, LAN ou Photon/Online.
	if (
		caminho == CENA_TABULEIRO_CARREGAMENTO
		or caminho == CENA_TABULEIRO_JOGO
		or caminho == CENA_TUTORIAL_JOGO
		or _cena_contem_tabuleiro_jogavel(cena)
	):
		return TipoTrilha.PARTIDA

	match caminho:
		CENA_MENU_PRINCIPAL:
			return TipoTrilha.MENU
		CENA_LAN:
			return TipoTrilha.LAN
		CENA_ONLINE:
			return TipoTrilha.ONLINE
		CENA_SELECAO:
			if OnlineTransport.usando_photon():
				return TipoTrilha.ONLINE
			if OnlineTransport.usando_lan():
				return TipoTrilha.LAN

	return TipoTrilha.NENHUMA


func _cena_contem_tabuleiro_jogavel(cena: Node) -> bool:
	if cena == null or not is_instance_valid(cena):
		return false

	# Cobre cenas que instanciem o tabuleiro internamente, como o tutorial.
	var candidato: Node = cena.find_child("Tabuleiro", true, false)
	if candidato != null and is_instance_valid(candidato):
		# Node.get_script() retorna Variant; a conversão explícita evita
		# o aviso de inferência quando warnings são tratados como erros.
		var script_candidato: Script = candidato.get_script() as Script
		if (
			script_candidato != null
			and script_candidato.resource_path
			== "res://scenes/gameplay/tabuleiro/tabuleiro.gd"
		):
			return true

	# Cobre uma eventual instância sem renomear a raiz original.
	var raiz_tabuleiro: Node = cena.find_child(
		"Tabuleiro_Metropolis",
		true,
		false
	)
	return raiz_tabuleiro != null and is_instance_valid(raiz_tabuleiro)


func _eh_cena_menu(cena: Node) -> bool:
	return (
		cena != null
		and is_instance_valid(cena)
		and cena.scene_file_path == CENA_MENU_PRINCIPAL
	)


# ============================================================================
# SOM AUTOMÁTICO EM TODOS OS BOTÕES
# ============================================================================

func _ao_adicionar_no(no: Node) -> void:
	if no is BaseButton:
		# O sinal node_added acontece assim que o botão entra na árvore.
		# Conectar imediatamente garante som também em botões dinâmicos.
		_conectar_botao(no)

	if _eh_pino_personagem(no):
		_registrar_pino(no)

	if (
		no.name == &"CheckTelaCheiaPause"
		or no.name == &"PainelOpcoesPause"
		or no.name == &"TelaOpcoesPause"
	):
		call_deferred(
			"_integrar_check_musica_pausa",
			get_tree().current_scene
		)

	# Se uma cena instanciar o tabuleiro depois do scene_changed,
	# a trilha é reavaliada assim que a raiz jogável entrar na árvore.
	if no.name == &"Tabuleiro" or no.name == &"Tabuleiro_Metropolis":
		call_deferred("_atualizar_cena_atual")


func _conectar_botoes_existentes() -> void:
	_conectar_botoes_recursivamente(get_tree().root)


func _conectar_botoes_recursivamente(no: Node) -> void:
	if no is BaseButton:
		_conectar_botao(no)
	for filho in no.get_children():
		_conectar_botoes_recursivamente(filho)


func _conectar_botao(no: Node) -> void:
	if no == null or not is_instance_valid(no) or not no is BaseButton:
		return

	var botao := no as BaseButton
	if botao.has_meta("gerenciador_audio_conectado"):
		return

	botao.set_meta("gerenciador_audio_conectado", true)
	botao.pressed.connect(_ao_botao_pressionado.bind(botao))


func _ao_botao_pressionado(botao: BaseButton) -> void:
	if botao == null or not is_instance_valid(botao):
		return

	# Esta função só é executada depois que o BaseButton realmente emite
	# pressed. Não verifica disabled aqui, pois muitos botões se desativam
	# dentro do próprio callback antes de o gerenciador receber o sinal.
	tocar_som_botao()

	# GIRAR DADOS recebe o mesmo pop dos demais botões e, no mesmo instante,
	# inicia o efeito sincronizado com a animação da rolagem.
	if botao.name == &"BotaoGirar":
		tocar_som_dados()


# ============================================================================
# CAIXA DE MÚSICA NAS OPÇÕES DO PAINEL DE PAUSA
# ============================================================================

func _integrar_check_musica_pausa(cena: Node) -> void:
	for _tentativa: int in range(8):
		if cena == null or not is_instance_valid(cena):
			return

		var check_tela_cheia: CheckButton = cena.find_child(
			"CheckTelaCheiaPause",
			true,
			false
		) as CheckButton

		if check_tela_cheia != null:
			var conteudo: VBoxContainer = (
				check_tela_cheia.get_parent() as VBoxContainer
			)
			if conteudo != null:
				_criar_ou_atualizar_check_musica_pausa(
					conteudo,
					check_tela_cheia
				)
				return

		await get_tree().process_frame


func _criar_ou_atualizar_check_musica_pausa(
	conteudo: VBoxContainer,
	check_tela_cheia: CheckButton
) -> void:
	var check_existente: CheckButton = conteudo.get_node_or_null(
		"CheckMusicaPause"
	) as CheckButton

	if check_existente != null:
		check_existente.set_pressed_no_signal(_musica_ativa)
		return

	var check_musica := CheckButton.new()
	check_musica.name = "CheckMusicaPause"
	check_musica.text = "MÚSICA DO JOGO"
	check_musica.tooltip_text = (
		"Desmarque para silenciar somente as músicas. "
		+ "Botões, dados e pulos continuam ativos."
	)
	check_musica.custom_minimum_size = Vector2(0.0, 64.0)
	check_musica.process_mode = Node.PROCESS_MODE_ALWAYS
	check_musica.set_pressed_no_signal(_musica_ativa)
	check_musica.add_theme_color_override(
		"font_color",
		Color.WHITE
	)
	check_musica.add_theme_color_override(
		"font_hover_color",
		Color(1.0, 0.78, 0.78)
	)
	_aplicar_fonte_ui(check_musica, 26, 3)
	check_musica.toggled.connect(
		_ao_check_musica_pausa_toggled
	)

	conteudo.add_child(check_musica)
	conteudo.move_child(
		check_musica,
		check_tela_cheia.get_index()
	)


func _ao_check_musica_pausa_toggled(ativada: bool) -> void:
	definir_musica_ativa(ativada)


# ============================================================================
# INTEGRAÇÃO COM O MODAL DE OPÇÕES EXISTENTE
# ============================================================================

func _integrar_controles_opcoes(cena: Node) -> void:
	for _tentativa in range(5):
		if not _eh_cena_menu(cena):
			return

		var modal := cena.find_child("ModalOpcoes", true, false)
		if modal != null:
			var vbox := _encontrar_vbox_opcoes(modal)
			if vbox != null:
				_configurar_vbox_opcoes(vbox, modal)
				return

		await get_tree().process_frame


func _encontrar_vbox_opcoes(no: Node) -> VBoxContainer:
	if no is VBoxContainer:
		for filho in no.get_children():
			if filho is Label and (filho as Label).text == "OPÇÕES":
				return no as VBoxContainer

	for filho in no.get_children():
		var encontrado := _encontrar_vbox_opcoes(filho)
		if encontrado != null:
			return encontrado
	return null


func _configurar_vbox_opcoes(vbox: VBoxContainer, modal: Node) -> void:
	if vbox.has_meta("controles_audio_separados_adicionados"):
		return
	vbox.set_meta("controles_audio_separados_adicionados", true)

	vbox.add_theme_constant_override("separation", 14)

	var painel := modal.find_child("PainelOpcoes", true, false) as PanelContainer
	if painel != null:
		painel.custom_minimum_size = Vector2(720.0, 820.0)

	var linha_volume_geral := _encontrar_linha_volume_geral(vbox)
	if linha_volume_geral == null:
		push_warning("Não foi possível localizar o controle de volume geral.")
		return

	var slider_geral := _encontrar_slider(linha_volume_geral)
	if slider_geral != null:
		slider_geral.value = _volume_geral
		slider_geral.value_changed.connect(_ao_alterar_volume_geral_menu)

	var indice_insercao := linha_volume_geral.get_index() + 1
	var controles_musica := _criar_controle_volume(
		"VOLUME DA MÚSICA",
		_volume_musica,
		_ao_alterar_volume_musica_menu
	)
	var rotulo_musica := controles_musica.get("rotulo") as Label
	var linha_musica := controles_musica.get("linha") as HBoxContainer
	if rotulo_musica == null or linha_musica == null:
		return
	vbox.add_child(rotulo_musica)
	vbox.move_child(rotulo_musica, indice_insercao)
	indice_insercao += 1
	vbox.add_child(linha_musica)
	vbox.move_child(linha_musica, indice_insercao)
	indice_insercao += 1

	var controles_efeitos := _criar_controle_volume(
		"VOLUME DOS EFEITOS",
		_volume_efeitos,
		_ao_alterar_volume_efeitos_menu
	)
	var rotulo_efeitos := controles_efeitos.get("rotulo") as Label
	var linha_efeitos := controles_efeitos.get("linha") as HBoxContainer
	if rotulo_efeitos == null or linha_efeitos == null:
		return
	vbox.add_child(rotulo_efeitos)
	vbox.move_child(rotulo_efeitos, indice_insercao)
	indice_insercao += 1
	vbox.add_child(linha_efeitos)
	vbox.move_child(linha_efeitos, indice_insercao)
	indice_insercao += 1

	var slider_efeitos := controles_efeitos.get("slider") as HSlider
	if slider_efeitos != null:
		slider_efeitos.drag_ended.connect(
			_ao_terminar_arraste_volume_efeitos
		)

	var controles_botoes := _criar_controle_volume(
		"VOLUME DOS BOTÕES",
		_volume_botoes,
		_ao_alterar_volume_botoes_menu
	)
	var rotulo_botoes := controles_botoes.get("rotulo") as Label
	var linha_botoes := controles_botoes.get("linha") as HBoxContainer
	if rotulo_botoes == null or linha_botoes == null:
		return
	vbox.add_child(rotulo_botoes)
	vbox.move_child(rotulo_botoes, indice_insercao)
	indice_insercao += 1
	vbox.add_child(linha_botoes)
	vbox.move_child(linha_botoes, indice_insercao)

	var slider_botoes := controles_botoes.get("slider") as HSlider
	if slider_botoes != null:
		slider_botoes.drag_ended.connect(_ao_terminar_arraste_volume_botoes)


func _encontrar_linha_volume_geral(vbox: VBoxContainer) -> HBoxContainer:
	for indice in range(vbox.get_child_count() - 1):
		var filho := vbox.get_child(indice)
		if filho is Label and (filho as Label).text == "VOLUME GERAL":
			var proximo := vbox.get_child(indice + 1)
			if proximo is HBoxContainer:
				return proximo as HBoxContainer
	return null


func _encontrar_slider(no: Node) -> HSlider:
	if no is HSlider:
		return no as HSlider
	for filho in no.get_children():
		var encontrado := _encontrar_slider(filho)
		if encontrado != null:
			return encontrado
	return null


func _criar_controle_volume(
	titulo: String,
	valor_inicial: float,
	acao_alteracao: Callable
) -> Dictionary:
	var rotulo := Label.new()
	rotulo.text = titulo
	rotulo.add_theme_color_override("font_color", Color.WHITE)
	_aplicar_fonte_ui(rotulo, 27, 3)

	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 18)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = clampf(valor_inicial, 0.0, 100.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0.0, 48.0)
	linha.add_child(slider)

	var percentual := Label.new()
	percentual.custom_minimum_size = Vector2(105.0, 48.0)
	percentual.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	percentual.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	percentual.add_theme_color_override(
		"font_color",
		Color(0.65, 0.88, 1.0)
	)
	_aplicar_fonte_ui(percentual, 27, 3)
	_atualizar_percentual(percentual, slider.value)
	linha.add_child(percentual)

	slider.value_changed.connect(acao_alteracao.bind(percentual))

	return {
		"rotulo": rotulo,
		"linha": linha,
		"slider": slider,
		"percentual": percentual,
	}


func _aplicar_fonte_ui(
	controle: Control,
	tamanho: int,
	contorno: int
) -> void:
	controle.add_theme_font_override("font", FONTE_UI)
	controle.add_theme_font_size_override("font_size", tamanho)
	controle.add_theme_color_override(
		"font_outline_color",
		Color(0.0, 0.0, 0.0, 0.95)
	)
	controle.add_theme_constant_override("outline_size", contorno)


func _ao_alterar_volume_geral_menu(valor: float) -> void:
	definir_volume_geral(valor)


func _ao_alterar_volume_musica_menu(
	valor: float,
	percentual: Label
) -> void:
	definir_volume_musica(valor)
	_atualizar_percentual(percentual, valor)


func _ao_alterar_volume_efeitos_menu(
	valor: float,
	percentual: Label
) -> void:
	definir_volume_efeitos(valor)
	_atualizar_percentual(percentual, valor)


func _ao_alterar_volume_botoes_menu(
	valor: float,
	percentual: Label
) -> void:
	definir_volume_botoes(valor)
	_atualizar_percentual(percentual, valor)


func _ao_terminar_arraste_volume_efeitos(
	valor_alterado: bool
) -> void:
	if valor_alterado:
		tocar_som_pulo_pino()


func _ao_terminar_arraste_volume_botoes(valor_alterado: bool) -> void:
	if valor_alterado:
		tocar_som_botao()


func _atualizar_percentual(rotulo: Label, valor: float) -> void:
	if rotulo != null and is_instance_valid(rotulo):
		rotulo.text = "%d%%" % int(round(valor))
