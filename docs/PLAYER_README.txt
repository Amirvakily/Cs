BREACHLINE  v1.0.0
==================
Round-based tactical shooter: Demolition (plant/defuse with an economy), Team Deathmatch and
Squad Hunt, with bots, a cover system, breaching and online play.

PLAY
  Double-click BREACHLINE.exe. Play Offline gives you a match against bots straight away.
  Needs a 64-bit Windows PC with a GPU that supports Vulkan or Direct3D 12 (falls back to
  OpenGL). Lower "Graphics quality" in Settings if it runs slowly.

CONTROLS
  WASD move        Mouse look       Left click fire       Right click aim / scope
  Space jump       Ctrl or C crouch Shift walk (quiet)    R reload
  E use (doors, plant/defuse, pick up)                    Q take cover (third person)
  1-5 weapons      4 grenades (press again to cycle)      Mouse wheel switch weapon
  X last weapon    G drop weapon    F flashlight          B buy menu
  Tab scoreboard   Y chat           U team chat           M change team    Esc menu

  Demolition: Red Viper plants the charge at site A or B (select it with 5 and hold fire, or
  hold E inside a site). Iron Guard defuses it by holding E next to it (a kit makes it faster).
  Cover: press Q facing a wall. Move along it with A/D, hold right click to peek and aim,
  click without aiming to blind-fire, press Q or move away to leave.
  Breach charges: buy in Gear, select with 5, click on a door or barricade.

PLAYING ONLINE
  Join: Server Browser lists servers on your network automatically. For internet servers,
  type IP:port and press Add Favorite (or Direct Connect).
  Host from the game: Host Online. Your friends join your IP on port 27777.

DEDICATED SERVER (run a server others can join)
  1. Edit server.cfg (name, port, password, map rotation, bots, difficulty...).
  2. Run "Start Dedicated Server.bat". The console shows the address to share.
  3. Players on your network see it in the Server Browser automatically.
     For internet players: the server tries to open the port with UPnP. If that fails,
     forward UDP ports 27777 and 27778 on your router to this PC.
  Console commands: status, say <text>, map <map> [mode], kick <name>, bots <n>, quit

MASTER SERVER (optional public server list)
  Run "Start Master Server.bat" on an always-on machine with UDP port 27900 open.
  Put its address in master_servers= in each server's server.cfg, and in each player's
  game settings file (master_servers in %APPDATA%\Godot\app_userdata\BREACHLINE\settings.cfg)
  so their Server Browser shows every registered server under Internet.

CREDITS
  Textures, skies and props: Poly Haven (polyhaven.com), CC0 public domain.
  Built with the Godot Engine (MIT license).
