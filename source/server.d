import std.file;
import std.path;
import std.stdio;
import std.array;
import std.socket;
import std.algorithm;
import util;
import protocol;
import world;
import serverConfig;
import types;

struct Client {
	Socket  socket;
	ubyte[] inBuffer;
	string  username;
	bool    loadedInWorld;
	World   world;
	bool    authenticated;
}

class Server {
	shared bool  running;
	ServerConfig config;
	Socket       socket;
	Client[]     clients;
	SocketSet    serverSet;
	SocketSet    clientSet;
	World[]      loadedWorlds;

	this() {
		running     = true;
		
		config.ip           = "localhost";
		config.port         = 25_565;
		config.heartbeatURL = "https://www.classicube.net/server/heartbeat";
		config.maxPlayers   = 50;
		config.publicServer = true;
		config.name         = "MCYeti dev";
		
		serverSet   = new SocketSet();
		clientSet   = new SocketSet();
	}

	~this() {
		socket.close();
		writeln("Exit");
	}

	void start() {
		socket          = new Socket(AddressFamily.INET, SocketType.STREAM);
		socket.blocking = false; // this is a single threaded server so
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);

		version (Posix) {
			socket.setOption(SocketOptionLevel.SOCKET, cast(SocketOption)SO_REUSEPORT, 1);
		}

		socket.bind(new InternetAddress(config.ip, config.port));
		socket.listen(10);
		util_Log("Running server on port %s", config.port);

		loadedWorlds ~= new World();
		loadedWorlds[0].generate("main", 128, 128, 128);
		util_Log("generated world %s", loadedWorlds[0].name);
	}

	void loadConfig() {
		string configPath = dirName(thisExePath()) ~ "/server.json";
		if (exists(configPath)) {
			config = createConfig(readText(configPath));
		}
		else {
			std.file.write(configPath, configToJSON(&config));
		}
	}

	void sendMessageToClient(Client* client, string message) {
		client.socket.send(stoc_Message(message));
	}

	void sendGlobalMessage(string message) {
		foreach (ref client ; clients) {
			sendMessageToClient(&client, message);
		}
		util_Log("%s", message);
	}

	void sendPlayerToWorld(Client* client, World world) {
		client.world = world;
		client.socket.send(stoc_SendWorld(world));

		if (world.addPlayer(client, this)) {
			sendGlobalMessage(client.username ~ " went to " ~ world.name);
		}
		else {
			sendMessageToClient(client, "&cWorld is full");
		}
	}

	void sendBlockUpdatesToWorld(string worldName, short x, short y, short z, byte block) {
		foreach (client ; clients) {
			if (client.world.name == worldName) {
				client.socket.send(stoc_SetBlock(x, y, z, block));
			}
		}
	}

	void kickDisconnectedClients() {
		for (size_t i = 0; i < clients.length; ++i) {
			if (
				clients[i].socket.send([cast(ubyte) SToCPacketID.Ping])
				== Socket.ERROR
			) {
				// client is no longer connected
				if (clients[i].authenticated) {
					sendGlobalMessage("&e" ~ clients[i].username ~ " left the game");
				}

				writeln(clients.length);
				clients.remove(i);
				writeln(clients.length);
			}
		}
	}

	void updateSockets() {
		serverSet.reset();
		clientSet.reset();

		serverSet.add(socket);
		if (clients) {
			foreach (client ; clients) {
				clientSet.add(client.socket);
			}
		}
		
		bool   success = true;
		Socket newClient;
		try {
			newClient = socket.accept();
		}
		catch (SocketAcceptException) {
			success = false;
		}

		if (success) {
			newClient.blocking  = false;
			clients            ~= Client(newClient, []);
			clientSet.add(newClient);
			util_Log(
				"%s connected to the server, now %d clients connected",
				newClient.localAddress.toAddrString(),
				clients.length
			);
		}

		foreach (ref client ; clients) {
			if (!clientSet.isSet(client.socket)) {
				continue;
			}

			ubyte[] incoming = new ubyte[1024];
			long    received = client.socket.receive(incoming);
			if (received == 0 || received == Socket.ERROR) {
				continue; // disconnected
				// TODO: delete this client
			}

			incoming         = incoming[0 .. received];
			client.inBuffer ~= incoming;
		}
	}

	void updateClients() {
		foreach (ref client ; clients) {
			if (client.inBuffer.length == 0) {
				continue;
			}
			switch (client.inBuffer[0]) {
				case CToSPacketID.PlayerIdentification: {
					const ulong size = CToSPacketSize.PlayerIdentification;
					if (client.inBuffer.length < size) {
						continue;
					}

					auto packet = new CToS_PlayerIdentification(
						client.inBuffer[0 .. size]
					);
					client.username      = packet.username;
					client.authenticated = true;

					client.socket.send(stoc_ServerIdentification(config));
					
					sendGlobalMessage("&e" ~ client.username ~ " joined the game");

					// send them to main world
					sendPlayerToWorld(&client, loadedWorlds[0]);

					client.inBuffer = client.inBuffer[size .. $];
					break;
				}
				case CToSPacketID.SetBlock: {
					const ulong size = CToSPacketSize.SetBlock;
					if (client.inBuffer.length < size) {
						continue;
					}

					auto packet = new CToS_SetBlock(client.inBuffer[0 .. size]);

					if (client.world.validBlock(packet.x, packet.y, packet.z)) {
						byte blockID = packet.mode == 0x00? 0 : packet.block;
						client.world.blocks[packet.z][packet.y][packet.x] = blockID;

						// send updates to other players
						sendBlockUpdatesToWorld(
							client.world.name, packet.x, packet.y, packet.z, blockID
						);
					}

					client.inBuffer = client.inBuffer[size .. $];
					break;
				}
				case CToSPacketID.PositionOrientation: {
					const ulong size = CToSPacketSize.PositionOrientation;
					if (client.inBuffer.length < size) {
						continue;
					}

					client.inBuffer = client.inBuffer[size .. $];
					break;
				}
				case CToSPacketID.Message: {
					const ulong size = CToSPacketSize.Message;
					if (client.inBuffer.length < size) {
						continue;
					}

					auto packet = new CToS_Message(client.inBuffer[0 .. size]);

					sendGlobalMessage(client.username ~ ": " ~ packet.message);

					client.inBuffer = client.inBuffer[size .. $];
					break;
				}
				default: {
					stderr.writefln(
						"[ERROR] %s sent invalid packet id %d",
						client.socket.localAddress.toAddrString(), client.inBuffer[0]
					);
				}
			}
		}
	}
}
