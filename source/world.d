import std.stdio;
import std.file;
import std.path;
import std.zlib;
import std.bitmanip;
import std.algorithm;
import server;
import types;
import protocol;
import worldFile;

struct WorldEntity {
	ubyte id;
	float x, y, z;
	byte  yaw, pitch;

	bool    isPlayer;
	Client* playerClient;
	string  name;
}

class World {
	string        name;
	ubyte[][][]   blocks;
	short         w, h, l;
	WorldEntity[] entities;
	Vec3          spawnPoint;

	bool PlayerIDExists(ubyte id) {
		return entities.filter!((a) => a.id == id).count > 0;
	}

	bool PlayerIsInWorld(string name) {
		foreach (entity ; entities) {
			if (entity.isPlayer && (entity.playerClient.username == name)) {
				return true;
			}
		}
		return false;
	}

	ubyte GetPlayerID(string name) {
		foreach (entity ; entities) {
			if (entity.isPlayer && (entity.playerClient.username == name)) {
				return entity.id;
			}
		}
		return 255;
	}

	WorldEntity* GetPlayer(string name) {
		foreach (ref entity ; entities) {
			if (entity.isPlayer && (entity.playerClient.username == name)) {
				return &entity;
			}
		}
		return null;
	}

	bool ValidBlock(short x, short y, short z) {
		return (
			(x > 0) && (y > 0) && (z > 0) &&
			(x < w) && (y < h) && (z < l)
		);
	}

	void RemovePlayer(string name) {
		WorldEntity dead;
		foreach (i, ref entity ; entities) {
			if (entity.isPlayer && (entity.name == name)) {
				dead = entity;
				entities = entities.remove(i);
			}
		}

		foreach (ref entity ; entities) {
			if (entity.isPlayer) {
				entity.playerClient.socket.send(SToC_DespawnPlayer(dead.id));
			}
		}
	}

	bool AddPlayer(Client* player, Server server) {
		// create an id for this player
		ubyte i;
		bool createdID = false;
		for (i = 0; i < 255; ++i) {
			bool res = PlayerIDExists(i);
			if (!res) {
				entities ~= WorldEntity(
					i, spawnPoint.x, spawnPoint.y, spawnPoint.y, 0, 0,
					true, player, player.username
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

			if (PlayerIsInWorld(client.username)) {
				client.socket.send(SToC_SpawnPlayer(
					player.username, id,
					spawnPoint.x, spawnPoint.y, spawnPoint.z, 0, 0
				));
			}
		}

		return true;
	}

	void Generate(const string pname, const short pw, const short ph, const short pl) {
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

	ubyte[] Serialise(bool forClient) {
		ubyte[] serialised;
		
		if (forClient) {
			serialised ~= nativeToBigEndian(cast(uint) (w * h * l));
		}
		
		for (short y = 0; y < h; ++y) {
			for (short z = 0; z < l; ++z) {
				for (short x = 0; x < w; ++x) {
					serialised ~= blocks[z][y][x];
				}
			}
		}

		if (forClient) {
			auto compressor  = new Compress(HeaderFormat.gzip);
			auto compressed  = compressor.compress(serialised);
			compressed      ~= compressor.flush();
			return cast(ubyte[]) compressed;
		}
		else {
			return serialised;
		}
	}

	bool FromBlocksArray(ubyte[] data) {
		if (data.length != w * h * l) {
			return false;
		}
		blocks     = new ubyte[][][](w, h, l);
		spawnPoint = Vec3(w / 2, (h / 2) + 1, l / 2);

		size_t i;
		for (short y = 0; y < h; ++y) {
			for (short z = 0; z < l; ++z) {
				for (short x = 0; x < w; ++x, ++i) {
					blocks[z][y][x] = data[i];
				}
			}
		}

		return true;
	}

	size_t Volume() {
		return w * h * l;
	}

	void Save() {
		string fname = dirName(thisExePath()) ~ "/worlds/" ~ name;

		WriteWorld(fname, this);
	}
}
