extends Node
## Connection management for online play (ENet listen server).
## Game-level replication lives in game.gd; this handles host/join/handshake.

signal joined(match_config: Dictionary)
signal join_failed(reason: String)
signal disconnected(reason: String)
signal peer_loaded(id: int, pname: String)
signal peer_gone(id: int)
signal upnp_done(ok: bool, external_ip: String)

var online := false
var peers := {} # id -> {"name": String, "loaded": bool}
var match_config := {}
var _upnp_thread: Thread
var _upnp: UPNP
var _upnp_port := 0
var _kick_reason := ""


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_server() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


func my_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 1
	return multiplayer.get_unique_id()


func start_offline(config: Dictionary) -> void:
	stop()
	match_config = config
	online = false


func host(port: int, config: Dictionary, use_upnp := true) -> Error:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, Cfg.MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	online = true
	match_config = config
	peers.clear()
	if use_upnp:
		_upnp_port = port
		_upnp_thread = Thread.new()
		_upnp_thread.start(_upnp_setup.bind(port))
	return OK


func join(ip: String, port: int) -> Error:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	online = true
	_kick_reason = ""
	return OK


func stop() -> void:
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	online = false
	peers.clear()
	if _upnp != null and _upnp_port > 0:
		var u := _upnp
		var p := _upnp_port
		_upnp = null
		_upnp_port = 0
		# Best-effort cleanup of the router mapping.
		var t := Thread.new()
		t.start(func(): u.delete_port_mapping(p, "UDP"))
		t.wait_to_finish()


func loaded_peers() -> Array:
	var out := []
	for id in peers:
		if peers[id]["loaded"]:
			out.append(id)
	return out


func peer_name(id: int) -> String:
	if peers.has(id):
		return peers[id]["name"]
	return "Player%d" % id


# --- UPnP --------------------------------------------------------------------
func _upnp_setup(port: int) -> void:
	var u := UPNP.new()
	var ok := false
	var ext := ""
	if u.discover(2000, 2, "InternetGatewayDevice") == UPNP.UPNP_RESULT_SUCCESS:
		var gw := u.get_gateway()
		if gw and gw.is_valid_gateway():
			if u.add_port_mapping(port, port, "BREACHLINE", "UDP", 0) == UPNP.UPNP_RESULT_SUCCESS:
				ok = true
				ext = u.query_external_address()
	if ok:
		_upnp = u
	call_deferred("_upnp_finished", ok, ext)


func _upnp_finished(ok: bool, ext: String) -> void:
	if _upnp_thread and _upnp_thread.is_started():
		_upnp_thread.wait_to_finish()
	upnp_done.emit(ok, ext)


# --- Connection events -----------------------------------------------------------
func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		peers[id] = {"name": "Player%d" % id, "loaded": false}


func _on_peer_disconnected(id: int) -> void:
	if peers.has(id):
		peers.erase(id)
	peer_gone.emit(id)


func _on_connected() -> void:
	_sv_hello.rpc_id(1, String(Cfg.settings["player_name"]), Cfg.VERSION)


func _on_connection_failed() -> void:
	stop()
	join_failed.emit("Could not connect to server.")


func _on_server_disconnected() -> void:
	var r := _kick_reason if _kick_reason != "" else "Lost connection to host."
	stop()
	disconnected.emit(r)


# --- Handshake RPCs -------------------------------------------------------------
@rpc("any_peer", "call_remote", "reliable")
func _sv_hello(pname: String, version: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if version != Cfg.VERSION:
		_cl_kick.rpc_id(id, "Version mismatch (host %s, you %s)." % [Cfg.VERSION, version])
		get_tree().create_timer(0.5).timeout.connect(func(): _drop_peer(id))
		return
	pname = pname.strip_edges().left(20)
	if pname == "":
		pname = "Player"
	# Ensure unique names
	var base := pname
	var n := 2
	var taken := [String(Cfg.settings["player_name"])]
	for p in peers.values():
		taken.append(p["name"])
	while pname in taken:
		pname = "%s(%d)" % [base, n]
		n += 1
	if not peers.has(id):
		peers[id] = {"name": pname, "loaded": false}
	peers[id]["name"] = pname
	_cl_welcome.rpc_id(id, match_config)


func _drop_peer(id: int) -> void:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id)


@rpc("authority", "call_remote", "reliable")
func _cl_welcome(config: Dictionary) -> void:
	match_config = config
	joined.emit(config)


@rpc("authority", "call_remote", "reliable")
func _cl_kick(reason: String) -> void:
	_kick_reason = reason


## Client tells the server its world is built and it can receive game RPCs.
func send_loaded() -> void:
	if multiplayer.is_server():
		return
	_sv_loaded.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _sv_loaded() -> void:
	var id := multiplayer.get_remote_sender_id()
	if not peers.has(id):
		return
	peers[id]["loaded"] = true
	peer_loaded.emit(id, peers[id]["name"])
