import std.stdio;
import core.atomic;
import core.thread;
import server;
import constants;
import util;
import heartbeat;
import tickCounter;

void main() {
	util_Log("Welcome to %s made by %s", appName, appAuthor);
	
	Server server = new Server();
	server.loadConfig();
	server.start();

	while (server.running) {
		server.updateSockets();
		server.updateClients();

		if (getTicks() % 1200 == 0) {
			doHeartbeat(server);
		}
		if (getTicks() % 20 == 0) {
			server.kickDisconnectedClients();
		}
		
		Thread.sleep(dur!("msecs")(50)); // 50ms delay
		incrementTicks();
	}
}
