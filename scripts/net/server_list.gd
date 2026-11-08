class_name ServerList
extends Node
## Client-side server browser data: LAN broadcast discovery, favourites and master server lists,
## with live info + ping from each server's query port.

signal servers_changed

const FAV_PATH := "user://favorites.cfg"
const LAN_PORTS := [27778, 27779, 27780, 27781, 27782]

var servers: Array = [] # dicts: name, host, port, map, mode, players, max_players, bots, ping_ms, source, password
var favorites: Array = [] # [[host, port], ...]
var _sock := PacketPeerUDP.new()
var _sent := {} # "ip:port" -> [send_time, source, host_label]
var _token := 0


func _ready() -> void:
	_sock.set_broadcast_enabled(true)
	_sock.bind(0)
	_load_favorites()


func _exit_tree() -> void:
	_sock.close()


func masters() -> Array:
	var raw := str(Cfg.settings.get("master_servers", ""))
	var out := []
	for m in raw.split(","):
		if m.strip_edges() != "":
			out.append(m.strip_edges())
	return out


func refresh() -> void:
	servers.clear()
	_sent.clear()
	_token += 1
	servers_changed.emit()
	# LAN broadcast
	for p in LAN_PORTS:
		_query("255.255.255.255", p, "lan")
	# Favourites
	for f in favorites:
		var ip := IP.resolve_hostname(str(f[0]), IP.TYPE_IPV4)
		if ip != "":
			_query(ip, int(f[1]) + 1, "favorite", str(f[0]))
	# Master servers
	for m in masters():
		var parts := str(m).split(":")
		var ip := IP.resolve_hostname(parts[0], IP.TYPE_IPV4)
		if ip == "":
			continue
		_sock.set_dest_address(ip, int(parts[1]) if parts.size() > 1 else MasterServer.DEFAULT_PORT)
		_sock.put_packet("BLL?".to_utf8_buffer())


func _query(ip: String, query_port: int, source: String, label := "") -> void:
	_sock.set_dest_address(ip, query_port)
	_sock.put_packet((ServerBeacon.MAGIC_QUERY + JSON.stringify({"t": _token})).to_utf8_buffer())
	if ip != "255.255.255.255":
		_sent["%s:%d" % [ip, query_port - 1]] = [Time.get_ticks_msec(), source, label if label != "" else ip]
	else:
		_sent["lan:%d" % query_port] = [Time.get_ticks_msec(), source, ""]


func _process(_delta: float) -> void:
	while _sock.get_available_packet_count() > 0:
		var pkt := _sock.get_packet()
		var ip := _sock.get_packet_ip()
		if pkt.size() < 4:
			continue
		var magic := pkt.slice(0, 4).get_string_from_ascii()
		var body = JSON.parse_string(pkt.slice(4).get_string_from_utf8())
		if magic == ServerBeacon.MAGIC_INFO and body is Dictionary:
			_on_info(ip, body)
		elif magic == "BLL!" and body is Dictionary:
			for e in body.get("servers", []):
				var key := "%s:%d" % [str(e[0]), int(e[1])]
				if not _sent.has(key):
					_query(str(e[0]), int(e[1]) + 1, "master")


func _on_info(ip: String, d: Dictionary) -> void:
	if int(d.get("t", -1)) != _token:
		return
	var port := int(d.get("port", Cfg.DEFAULT_PORT))
	var key := "%s:%d" % [ip, port]
	var sent: Array = _sent.get(key, _sent.get("lan:%d" % (port + 1), [Time.get_ticks_msec(), "lan", ""]))
	var entry := {
		"name": str(d.get("name", "BREACHLINE Server")), "host": ip, "port": port,
		"map": str(d.get("map", "?")), "mode": str(d.get("mode", "?")),
		"players": int(d.get("players", 0)), "max_players": int(d.get("max_players", Cfg.MAX_PLAYERS)),
		"bots": int(d.get("bots", 0)), "password": bool(d.get("password", false)),
		"ping_ms": Time.get_ticks_msec() - int(sent[0]), "source": str(sent[1]),
		"version": str(d.get("version", "")),
	}
	if str(sent[1]) == "favorite" and str(sent[2]) != "":
		entry["host"] = str(sent[2])
	for i in servers.size():
		if servers[i]["host"] == entry["host"] and int(servers[i]["port"]) == port:
			servers[i] = entry
			servers_changed.emit()
			return
	servers.append(entry)
	servers_changed.emit()


func add_favorite(host: String, port: int) -> void:
	for f in favorites:
		if f[0] == host and int(f[1]) == port:
			return
	favorites.append([host, port])
	_save_favorites()
	refresh()


func remove_favorite(host: String, port: int) -> void:
	for i in range(favorites.size() - 1, -1, -1):
		if favorites[i][0] == host and int(favorites[i][1]) == port:
			favorites.remove_at(i)
	_save_favorites()
	refresh()


func _load_favorites() -> void:
	var cf := ConfigFile.new()
	if cf.load(FAV_PATH) == OK:
		favorites = cf.get_value("favorites", "list", [])


func _save_favorites() -> void:
	var cf := ConfigFile.new()
	cf.set_value("favorites", "list", favorites)
	cf.save(FAV_PATH)
