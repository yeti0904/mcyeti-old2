import std.stdio;
import core.atomic;
import core.thread;
import server;
import constants;
import util;
import heartbeat;
import tickCounter;

void main() {
	Util_Log("Welcome to %s made by %s", appName, appAuthor);
	
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
		
		Thread.sleep(dur!("msecs")(50)); // 50ms delay
		IncrementTicks();
	}
}
