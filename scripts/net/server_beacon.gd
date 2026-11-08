class_name ServerBeacon
extends Node
## Runs next to a hosted game: answers UDP info queries (LAN browser, favourites, ping)
## on game_port + 1 and sends heartbeats to master servers so the server shows up in their lists.

const MAGIC_QUERY := "BLQ?"
const MAGIC_INFO := "BLI!"
const MAGIC_HEARTBEAT := "BLHB"
const HEARTBEAT_INTERVAL := 30.0

var game_port := Cfg.DEFAULT_PORT
var masters: Array = [] # ["host:port", ...]
var info_provider: Callable
var _sock := PacketPeerUDP.new()
var _hb_timer := 2.0
var _master_addrs := []


func start(p_game_port: int, p_masters: Array, provider: Callable) -> bool:
	game_port = p_game_port
	masters = p_masters
	info_provider = provider
	var err := _sock.bind(game_port + 1)
	if err != OK:
		push_warning("Query port %d unavailable (%s)" % [game_port + 1, error_string(err)])
		return false
	_master_addrs.clear()
	for m in masters:
		var parts := str(m).strip_edges().split(":")
		if parts.is_empty() or parts[0] == "":
			continue
		var ip := IP.resolve_hostname(parts[0], IP.TYPE_IPV4)
		if ip == "":
			push_warning("Cannot resolve master server %s" % parts[0])
			continue
		_master_addrs.append([ip, int(parts[1]) if parts.size() > 1 else MasterServer.DEFAULT_PORT])
	return true


func _exit_tree() -> void:
	_sock.close()


func info() -> Dictionary:
	var d: Dictionary = info_provider.call() if info_provider.is_valid() else {}
	d["port"] = game_port
	d["version"] = Cfg.VERSION
	return d


func _process(delta: float) -> void:
	if not _sock.is_bound():
		return
	while _sock.get_available_packet_count() > 0:
		var pkt := _sock.get_packet()
		var ip := _sock.get_packet_ip()
		var port := _sock.get_packet_port()
		if pkt.size() < 4:
			continue
		var magic := pkt.slice(0, 4).get_string_from_ascii()
		if magic == MAGIC_QUERY:
			var req = JSON.parse_string(pkt.slice(4).get_string_from_utf8())
			var d := info()
			if req is Dictionary:
				d["t"] = req.get("t", 0)
			_sock.set_dest_address(ip, port)
			_sock.put_packet((MAGIC_INFO + JSON.stringify(d)).to_utf8_buffer())
	_hb_timer -= delta
	if _hb_timer <= 0.0:
		_hb_timer = HEARTBEAT_INTERVAL
		var payload := (MAGIC_HEARTBEAT + JSON.stringify(info())).to_utf8_buffer()
		for m in _master_addrs:
			_sock.set_dest_address(m[0], int(m[1]))
			_sock.put_packet(payload)
