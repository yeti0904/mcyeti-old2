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
import tickCounter;

struct Client {
	Socket  socket;
	ubyte[] inBuffer;
	string  username;
	bool    loadedInWorld;
	World   world;
	bool    authenticated;
	string  ip;
	uint    ticksAtLastBlockUpdate;
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
		running = true;
		
		config.ip           = "0.0.0.0";
		config.port         = 25565;
		config.heartbeatURL = "https://www.classicube.net/server/heartbeat";
		config.maxPlayers   = 50;
		config.publicServer = true;
		config.name         = "[MCYeti] Default";
		
		serverSet = new SocketSet();
		clientSet = new SocketSet();
	}

	~this() {
		socket.close();
		writeln("Exit");
	}

	void Init() {
		socket          = new Socket(AddressFamily.INET, SocketType.STREAM);
		socket.blocking = false; // this is a single threaded server so
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);

		version (Posix) {
			socket.setOption(SocketOptionLevel.SOCKET, cast(SocketOption)SO_REUSEPORT, 1);
		}

		socket.bind(new InternetAddress(config.ip, config.port));
		socket.listen(10);
		Util_Log("Running server on port %s", config.port);

		loadedWorlds ~= new World();
		loadedWorlds[0].Generate("main", 128, 128, 128);
		Util_Log("Generated world %s", loadedWorlds[0].name);
	}

	void LoadConfig() {
		string configPath = dirName(thisExePath()) ~ "/server.json";
		if (exists(configPath)) {
			config = CreateConfig(readText(configPath));
		}
		else {
			std.file.write(configPath, ConfigToJSON(&config));
		}
	}

	void SendMessageToClient(Client* client, string message) {
		client.socket.send(SToC_Message(message));
	}

	void SendGlobalMessage(string message) {
		foreach (ref client ; clients) {
			SendMessageToClient(&client, message);
		}
		Util_Log("%s", message);
	}

	void SendPlayerToWorld(Client* client, World world) {
		client.world = world;
		client.socket.send(SToC_SendWorld(world));

		if (world.AddPlayer(client, this)) {
			// send entities to the player
			for (size_t i = 0; i < clients.length; ++i) {
				if (
					(clients[i].authenticated) &&
					(clients[i].username != client.username) &&
					(clients[i].world.name == world.name)
				) {
					WorldEntity* entity = world.GetPlayer(clients[i].username);
					auto data = SToC_SpawnPlayer(
						entity.name, entity.id,
						entity.x, entity.y, entity.z,
						entity.yaw, entity.pitch
					);
					client.socket.send(data);
				}
			}
		
			SendGlobalMessage(client.username ~ " went to " ~ world.name);
		}
		else {
			SendMessageToClient(client, "&cWorld is full");
		}
	}

	void SendBlockUpdatesToWorld(string worldName, short x, short y, short z, byte block) {
		foreach (client ; clients) {
			if (client.world.name == worldName) {
				client.socket.send(SToC_SetBlock(x, y, z, block));
			}
		}
	}

	void KickPlayer(string name, string reason) {
		foreach (i, ref client ; clients) {
			if (client.authenticated && (client.username == name)) {
				client.socket.send(SToC_DisconnectPlayer(reason));

				SendGlobalMessage(
					"&e" ~ clients[i].username ~ " was kicked: " ~ reason
				);

				clients = clients.remove(i);
				return;
			}
		}
	}

	ulong GetConnectedIPs() {
		string[] ips;

		foreach (client ; clients) {
			if (!ips.canFind(client.ip)) {
				ips ~= client.ip;
			}
		}

		return ips.length;
	}

	ulong GetAmountOfThisIP(string ip) {
		ulong ret = 0;

		foreach (client ; clients) {
			if (client.ip == ip) {
				++ ret;
			}
		}

		return ret;
	}

	void KickDisconnectedClients() {
		for (size_t i = 0; i < clients.length; ++i) {
			if (
				clients[i].socket.send([cast(ubyte) SToCPacketID.Ping])
				== Socket.ERROR
			) {
				// client is no longer connected
				if (clients[i].authenticated) {
					SendGlobalMessage("&e" ~ clients[i].username ~ " left the game");
					for (size_t j = 0; j < clients.length; ++j) {
						if (
							(i == j) ||
							(clients[j].world.name != clients[i].world.name)
						) {
							continue;
						}

						clients[j].socket.send(
							SToC_DespawnPlayer(clients[i].world.GetPlayerID(
								clients[i].username)
							)
						);
					}
				}


				clients = clients.remove(i);
				Util_Log(
					"Now %d clients connected, and %d IPs connected",
					clients.length, GetConnectedIPs()
				);
			}
		}
	}

	void UpdateSockets() {
		serverSet.reset();
		clientSet.reset();

		serverSet.add(socket);
		if (clients) {
			foreach (client ; clients) {
				clientSet.add(client.socket);
			}
		}
		
		bool   success = true;
		Socket newClientSocket;
		try {
			newClientSocket = socket.accept();
		}
		catch (Throwable) {
			success = false;
		}

		if (success) {
			if (GetAmountOfThisIP(newClientSocket.remoteAddress.toAddrString()) > 5) {
				return;
			}

		
			newClientSocket.blocking = false;
			
			Client newClient;
			newClient.socket = newClientSocket;
			newClient.ip     = newClientSocket.remoteAddress.toAddrString();
			
			clients ~= newClient;
			clientSet.add(newClientSocket);
			Util_Log(
				"%s connected to the server, now %d clients connected and %d IPs connected",
				newClientSocket.remoteAddress.toAddrString(),
				clients.length, GetConnectedIPs()
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

	void UpdateClients() {
		foreach (i, ref client ; clients) {
			if (client.inBuffer.length == 0) {
				continue;
			}
			if (client.inBuffer.length > 256) {
				clients = clients.remove(i);
				return;
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

					client.socket.send(SToC_ServerIdentification(config));
					
					SendGlobalMessage("&e" ~ client.username ~ " joined the game");

					// send them to main world
					SendPlayerToWorld(&client, loadedWorlds[0]);

					client.inBuffer = client.inBuffer[size .. $];
					break;
				}
				case CToSPacketID.SetBlock: {
					const ulong size = CToSPacketSize.SetBlock;
					if (client.inBuffer.length < size) {
						continue;
					}

					if (GetTicks() - client.ticksAtLastBlockUpdate < 10) {
						KickPlayer(client.username, "Kicked by antigrief, slow down");
						return;
					}

					client.ticksAtLastBlockUpdate = GetTicks();

					auto packet = new CToS_SetBlock(client.inBuffer[0 .. size]);

					if (client.world.ValidBlock(packet.x, packet.y, packet.z)) {
						byte blockID = packet.mode == 0x00? 0 : packet.block;
						client.world.blocks[packet.z][packet.y][packet.x] = blockID;

						// send updates to other players
						SendBlockUpdatesToWorld(
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

					auto packet = new CToS_PositionOrientation(client.inBuffer[0 .. size]);
					auto clientEntity = client.world.GetPlayer(client.username);

					clientEntity.x     = cast(float) (packet.x) / 32;
					clientEntity.y     = cast(float) (packet.y) / 32;
					clientEntity.z     = cast(float) (packet.z) / 32;
					clientEntity.yaw   = packet.yaw;
					clientEntity.pitch = packet.pitch;

					if (client.world !is null) {
						foreach (ref entity ; client.world.entities) {
							if (entity.isPlayer) {
								entity.playerClient.socket.send(
									SToC_SetPositionOrientation(
										clientEntity.id,
										clientEntity.x,
										clientEntity.y,
										clientEntity.z,
										clientEntity.yaw,    clientEntity.pitch
									)
								);
							}
						}
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

					SendGlobalMessage(client.username ~ ": " ~ packet.message);

					client.inBuffer = client.inBuffer[size .. $];
					break;
				}
				default: {
					stderr.writefln(
						"[ERROR] %s sent invalid packet id %d",
						client.socket.localAddress.toAddrString(), client.inBuffer[0]
					);
					clients = clients.remove(i);
					return;
				}
			}
		}
	}
}
