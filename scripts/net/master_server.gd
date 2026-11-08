class_name MasterServer
extends Node
## Lightweight master server: game servers register with heartbeats, clients fetch the list.
## Run with:  BREACHLINE_Server.exe --master   (UDP port 27900 by default)

const DEFAULT_PORT := 27900
const EXPIRE := 95.0
const PER_PAGE := 40

var _sock := PacketPeerUDP.new()
var servers := {} # "ip:port" -> {ip, port, info, seen}


func start(port := DEFAULT_PORT) -> bool:
	var err := _sock.bind(port)
	if err != OK:
		printerr("Master server: cannot bind UDP port %d (%s)" % [port, error_string(err)])
		return false
	print("Master server listening on UDP %d" % port)
	return true


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	while _sock.get_available_packet_count() > 0:
		var pkt := _sock.get_packet()
		var ip := _sock.get_packet_ip()
		var port := _sock.get_packet_port()
		if pkt.size() < 4:
			continue
		var magic := pkt.slice(0, 4).get_string_from_ascii()
		if magic == ServerBeacon.MAGIC_HEARTBEAT:
			var d = JSON.parse_string(pkt.slice(4).get_string_from_utf8())
			if d is Dictionary:
				var gport := int(d.get("port", Cfg.DEFAULT_PORT))
				var key := "%s:%d" % [ip, gport]
				if not servers.has(key):
					print("Registered server %s (%s)" % [key, str(d.get("name", "?"))])
				servers[key] = {"ip": ip, "port": gport, "info": d, "seen": t}
		elif magic == "BLL?":
			var list := []
			for k in servers.keys():
				list.append([servers[k]["ip"], servers[k]["port"]])
			var pages := maxi(1, int(ceil(list.size() / float(PER_PAGE))))
			for p in pages:
				var chunk := list.slice(p * PER_PAGE, (p + 1) * PER_PAGE)
				_sock.set_dest_address(ip, port)
				_sock.put_packet(("BLL!" + JSON.stringify({"servers": chunk, "page": p, "pages": pages})).to_utf8_buffer())
	for k in servers.keys():
		if t - float(servers[k]["seen"]) > EXPIRE:
			print("Server %s timed out" % k)
			servers.erase(k)
