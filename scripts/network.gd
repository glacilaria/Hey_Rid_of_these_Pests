extends Node
## Network (AUTOLOAD) – lobby, matchmaking, room codes, roster, bots, match start.
##
## Topology: one peer is the HOST (= authoritative server, peer id 1). Up to 3 players.
## Bots are roster entries with NEGATIVE ids (-1, -2) and {"bot": true}; the server
## drives them with BotBrain. Humans joining a bot-filled room replace a bot.
## Matchmaking is LAN-only (UDP broadcast). TODO(online): swap _find_room() for a backend.

signal roster_changed
signal status(text: String)
signal player_left(peer_id: int)
signal countdown(seconds: float)      # quick-match auto-start

const LOBBY_SCENE := "res://scenes/lobby_room.tscn"
const MATCH_SCENE := "res://scenes/match.tscn"
const GAME_PORT := 24565
const DISCOVERY_PORT := 24566
const SCAN_TIME := 1.5
const QUICK_START_DELAY := 6.0
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ"
const BOT_NAMES := ["Roomba", "Sponge", "Dustbunny", "Mop"]

var players := {}                  # peer_id -> {name, char_id, level, bot?}
var room_code := ""
var difficulty: int = GameData.Difficulty.NORMAL
var in_match := false
var local_profile := {"name": "Player%d" % (randi() % 900 + 100), "char_id": "nanay_tala", "level": 1}
var auto_start := -1.0

var _listener: PacketPeerUDP


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): status.emit("Connection failed"); leave())
	multiplayer.server_disconnected.connect(func(): status.emit("Host left the room"); leave())


# ------------------------------------------------------------------ helpers
func human_count() -> int:
	var n := 0
	for id in players:
		if id > 0:
			n += 1
	return n


func bot_count() -> int:
	return players.size() - human_count()


func in_room() -> bool:
	return room_code != ""


func is_host() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server() and in_room()


# ------------------------------------------------------------------ matchmaking
func host_room() -> void:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(GAME_PORT, GameData.MAX_PLAYERS)
	if err != OK:
		status.emit("Could not host: %s" % error_string(err))
		return
	multiplayer.multiplayer_peer = peer
	room_code = _make_code()
	players = {1: local_profile.duplicate()}
	_listener = PacketPeerUDP.new()
	_listener.bind(DISCOVERY_PORT)
	roster_changed.emit()
	status.emit("Room %s open – share the code. Waiting for players." % room_code)


## Private room: join by 4-letter code.
func join_by_code(code: String) -> void:
	code = code.strip_edges().to_upper()
	if code.length() < 4:
		status.emit("Enter a 4-letter room code")
		return
	status.emit("Looking for room %s..." % code)
	var info := await _find_room(code)
	if info.is_empty():
		status.emit("Room %s not found" % code)
		return
	_connect_to(info.ip, info.code)


## Public matchmaking: join an open room; if nobody is found, host one and add 2 bots.
func quick_match() -> void:
	status.emit("Searching for a match...")
	var info := await _find_room("*")
	if info.is_empty():
		host_room()
		if not in_room():
			return
		add_bot()
		add_bot()
		auto_start = QUICK_START_DELAY
		status.emit("No players found – quick match with 2 bots. Humans can still join!")
	else:
		_connect_to(info.ip, info.code)


## Host only.
func add_bot() -> void:
	if not is_host() or players.size() >= GameData.MAX_PLAYERS:
		return
	var id := -1
	while players.has(id):
		id -= 1
	var used: Array = []
	for pid in players:
		used.append(players[pid].char_id)
	var pool: Array = GameData.CHARACTERS.keys().filter(func(c): return not used.has(c))
	players[id] = {"name": "%s (bot)" % BOT_NAMES[(-id - 1) % BOT_NAMES.size()],
		"char_id": pool.pick_random(), "level": 1, "bot": true}
	rpc("cl_roster", players, room_code)


func remove_bots() -> void:
	if not is_host():
		return
	for id in players.keys():
		if id < 0:
			players.erase(id)
	auto_start = -1.0
	rpc("cl_roster", players, room_code)


func leave() -> void:
	if _listener:
		_listener.close()
		_listener = null
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	players.clear()
	room_code = ""
	in_match = false
	auto_start = -1.0
	roster_changed.emit()


func _connect_to(ip: String, code: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, GAME_PORT)
	if err != OK:
		status.emit("Connect error: %s" % error_string(err))
		return
	multiplayer.multiplayer_peer = peer
	room_code = code
	status.emit("Joining room %s..." % code)


func _make_code() -> String:
	var s := ""
	for i in 4:
		s += CODE_CHARS[randi() % CODE_CHARS.length()]
	return s


func _find_room(code: String) -> Dictionary:
	var scanner := PacketPeerUDP.new()
	scanner.set_broadcast_enabled(true)
	scanner.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	scanner.put_packet(("RIDPESTS?:%s" % code).to_utf8_buffer())
	var t := 0.0
	while t < SCAN_TIME:
		await get_tree().process_frame
		t += get_process_delta_time()
		if scanner.get_available_packet_count() > 0:
			var info = JSON.parse_string(scanner.get_packet().get_string_from_utf8())
			if info is Dictionary:
				info["ip"] = scanner.get_packet_ip()
				scanner.close()
				return info
	scanner.close()
	return {}


func _process(delta: float) -> void:
	# quick-match countdown (host)
	if auto_start > 0.0 and is_host() and not in_match:
		auto_start -= delta
		countdown.emit(maxf(auto_start, 0.0))
		if auto_start <= 0.0:
			auto_start = -1.0
			start_match(difficulty)
	# answer LAN discovery pings (host)
	if _listener == null:
		return
	while _listener.get_available_packet_count() > 0:
		var msg := _listener.get_packet().get_string_from_utf8()
		var ip := _listener.get_packet_ip()
		var port := _listener.get_packet_port()
		if not msg.begins_with("RIDPESTS?:"):
			continue
		var wanted := msg.get_slice(":", 1)
		var open := not in_match and human_count() < GameData.MAX_PLAYERS
		if open and (wanted == "*" or wanted == room_code):
			_listener.set_dest_address(ip, port)
			_listener.put_packet(JSON.stringify({"code": room_code, "players": players.size()}).to_utf8_buffer())


# ------------------------------------------------------------------ roster
func _on_connected() -> void:
	rpc_id(1, "srv_register", local_profile)


@rpc("any_peer", "reliable")
func srv_register(profile: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if in_match or human_count() >= GameData.MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	if players.size() >= GameData.MAX_PLAYERS:        # room full of bots -> kick one out
		for bid in players.keys():
			if bid < 0:
				players.erase(bid)
				break
	players[id] = profile
	if auto_start > 0.0:
		auto_start = QUICK_START_DELAY                # new human: restart the countdown
	rpc("cl_roster", players, room_code)
	status.emit("Room %s  (%d/%d)" % [room_code, players.size(), GameData.MAX_PLAYERS])


## Call after changing local_profile while inside a room.
func update_profile() -> void:
	if not multiplayer.has_multiplayer_peer() or not in_room():
		return
	if multiplayer.is_server():
		players[1] = local_profile.duplicate()
		rpc("cl_roster", players, room_code)
	else:
		rpc_id(1, "srv_update", local_profile)


@rpc("any_peer", "reliable")
func srv_update(profile: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and players.has(id):
		players[id] = profile
		rpc("cl_roster", players, room_code)


@rpc("authority", "call_local", "reliable")
func cl_roster(roster: Dictionary, code: String) -> void:
	players = roster
	room_code = code
	roster_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		players.erase(id)
		rpc("cl_roster", players, room_code)
		player_left.emit(id)


# ------------------------------------------------------------------ match flow
func start_match(diff: int) -> void:
	if not multiplayer.is_server() or in_match or players.is_empty():
		return
	in_match = true
	auto_start = -1.0
	rpc("cl_start", diff)


@rpc("authority", "call_local", "reliable")
func cl_start(diff: int) -> void:
	difficulty = diff
	in_match = true
	get_tree().change_scene_to_file(MATCH_SCENE)


func return_to_lobby() -> void:
	if multiplayer.is_server():
		rpc("cl_return")


@rpc("authority", "call_local", "reliable")
func cl_return() -> void:
	in_match = false
	get_tree().change_scene_to_file(LOBBY_SCENE)
