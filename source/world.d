import std.stdio;
import std.zlib;
import std.bitmanip;
import std.algorithm;
import server;
import types;
import protocol;

struct WorldEntity {
	ubyte id;
	short x, y, z;
	byte  yaw, pitch;

	bool    isPlayer;
	Client* playerClient;
}

class World {
	string        name;
	ubyte[][][]   blocks;
	short         w, h, l;
	WorldEntity[] entities;
	Vec3          spawnPoint;

	bool playerIDExists(ubyte id) {
		return entities.filter!((a) => a.id == id).count > 0;
	}

	bool playerIsInWorld(string name) {
		foreach (entity ; entities) {
			if (entity.isPlayer && (entity.playerClient.username == name)) {
				return true;
			}
		}
		return false;
	}

	ubyte getPlayerID(string name) {
		foreach (entity ; entities) {
			if (entity.isPlayer && (entity.playerClient.username == name)) {
				return entity.id;
			}
		}
		return 0;
	}

	bool validBlock(short x, short y, short z) {
		return (
			(x > 0) && (y > 0) && (z > 0) &&
			(x < w) && (y < h) && (z < l)
		);
	}

	bool addPlayer(Client* player, Server server) {
		// create an id for this player
		ubyte i;
		bool createdID = false;
		for (i = 0; i < 255; ++i) {
			bool res = playerIDExists(i);
			if (!res) {
				entities ~= WorldEntity(
					i, spawnPoint.x, spawnPoint.y, spawnPoint.y, 0, 0,
					true, player
				);
				createdID = true;
				break;
			}
		}

		if (!createdID) {
			return false;
		}

		// send new entity to other players
		foreach (client ; server.clients) {
			ubyte id;
			if (client.username == player.username) {
				id = 255;
			}
			else {
				id = i;
			}

			if (playerIsInWorld(client.username)) {
				client.socket.send(stoc_SpawnPlayer(
					player.username, id,
					spawnPoint.x, spawnPoint.y, spawnPoint.z, 0, 0
				));
			}
		}

		return true;
	}

	void generate(const string pname, const short pw, const short ph, const short pl) {
		name   = pname;
		w      = pw;
		h      = ph;
		l      = pl;
		blocks = new ubyte[][][](pw, ph, pl);
		for (short x = 0; x < w; ++x) {
			for (short y = 0; y < h; ++y) {
				for (short z = 0; z < l; ++z) {
					blocks[z][y][x] = 0; // air
					if (y < h / 2) {
						blocks[z][y][x] = 1; // stone
					}
				}
			}
		}

		spawnPoint = Vec3(w / 2, (h / 2) + 1, l / 2);
	}

	ubyte[] serialize() {
		ubyte[] serialized;
		serialized ~= nativeToBigEndian(cast(uint) (w * h * l));
		for (short y = 0; y < h; ++y) {
			for (short z = 0; z < l; ++z) {
				for (short x = 0; x < w; ++x) {
					serialized ~= blocks[z][y][x];
				}
			}
		}

		auto compressor  = new Compress(HeaderFormat.gzip);
		auto compressed  = compressor.compress(serialized);
		compressed      ~= compressor.flush();
		return cast(ubyte[]) compressed;
	}

	size_t volume() {
		return w * h * l;
	}
}
