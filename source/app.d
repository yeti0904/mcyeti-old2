import std.stdio;
import core.atomic;
import core.thread;
import server;
import constants;
import util;
import heartbeat;
import tickCounter;
import serverFiles;

void main() {
	Util_Log("Welcome to %s made by %s", appName, appAuthor);

	CreateServerDirectories();
	
	Server server = new Server();
	server.LoadConfig();
	server.Init();

	while (server.running) {
		server.UpdateSockets();
		server.UpdateClients();

		if (GetTicks() % 1200 == 0) {
			DoHeartbeat(server);
		}
		if (GetTicks() % 20 == 0) {
			server.KickDisconnectedClients();
		}
		if (GetTicks() % 120000 == 0) {
			server.AutoSaveWorlds();
		}
		
		Thread.sleep(dur!("msecs")(10)); // 100tps
		IncrementTicks();
	}
}
