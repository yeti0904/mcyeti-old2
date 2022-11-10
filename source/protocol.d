import std.stdio;
import std.string;
import std.bitmanip;
import std.algorithm;
import core.stdc.stdlib;
import world;
import serverConfig;

string stringFromBytes(char[64] bytes) {
	return cast(string) strip(bytes).idup();
}

char[64] bytesFromString(string str) {
	char[64] ret  = ' ';
	auto len      = min(64, str.length);
	ret[0 .. len] = str[0 .. len];

	return ret;
}

enum CToSPacketID {
	PlayerIdentification = 0x00,
	SetBlock             = 0x05,
	PositionOrientation  = 0x08,
	Message              = 0x0D
}

enum CToSPacketSize {
	PlayerIdentification = 131,
	SetBlock             = 9,
	PositionOrientation  = 10,
	Message              = 66
}

enum SToCPacketID {
	ServerIdentification   = 0x00,
	Ping                   = 0x01,
	LevelInitialise        = 0x02,
	LevelDataChunk         = 0x03,
	LevelFinalise          = 0x04,
	SetBlock               = 0x06,
	SpawnPlayer            = 0x07,
	SetPositionOrientation = 0x08,
	DespawnPlayer          = 0x0C,
	Message                = 0x0D,
	Disconnect             = 0x0E
}

enum SToCPacketSize {
	ServerIdentification   = 131,
	Ping                   = 1,
	LevelInitialise        = 1,
	LevelDataChunk         = 1028,
	LevelFinalise          = 7,
	SetBlock               = 8,
	SpawnPlayer            = 74,
	SetPositionOrientation = 10,
	DespawnPlayer          = 2,
	Message                = 66,
	DisconnectPlayer       = 65
}

class CToS_PlayerIdentification {
	ubyte  id, protocolVersion;
	string username, mppass;
	ubyte  unused;

	this(ubyte[] bytes) {
		if (bytes.length > CToSPacketSize.PlayerIdentification) {
			stderr.writefln("CToS_PlayerIdentification: Too many bytes (%d)", bytes.length);
			exit(1);
		}
		id              = bytes[0];
		protocolVersion = bytes[1];
		username        = stringFromBytes(cast(char[64]) bytes[2 .. 66]);
		mppass          = stringFromBytes(cast(char[64]) bytes[66 .. 130]);
		unused          = bytes[130];
	}
}

class CToS_SetBlock {
	byte  id;
	short x, y, z;
	byte  mode, block;

	this(ubyte[] bytes) {
		if (bytes.length > CToSPacketSize.SetBlock) {
			stderr.writefln("CToS_SetBlock: Too many bytes (%d)", bytes.length);
			exit(1);
		}

		id    = bytes[0];
		x     = bigEndianToNative!short(bytes[1 .. 3]);
		y     = bigEndianToNative!short(bytes[3 .. 5]);
		z     = bigEndianToNative!short(bytes[5 .. 7]);
		mode  = bytes[7];
		block = bytes[8];
	}
}

class CToS_Message {
	ubyte  id;
	byte   playerID;
	string message;

	this(ubyte[] bytes) {
		if (bytes.length > CToSPacketSize.Message) {
			stderr.writefln("CToS_Message: Too many bytes (%d)", bytes.length);
			exit(1);
		}
		id       = bytes[0];
		playerID = bytes[1];
		message  = stringFromBytes(cast(char[64]) bytes[2 .. 66]);
	}
}

byte[] stoc_ServerIdentification(ServerConfig config) {
	byte[] toSend;

	toSend ~= SToCPacketID.ServerIdentification;
	toSend ~= 0x07; // protocol version;
	toSend ~= bytesFromString(config.name); // server name
	toSend ~= bytesFromString("Welcome"); // motd
	toSend ~= 0x00; // user type (not op)

	assert(toSend.length == SToCPacketSize.ServerIdentification);

	return toSend;
}

byte[] stoc_SendWorld(World world) {
	byte[] toSend;

	// level initialise packet
	toSend ~= SToCPacketID.LevelInitialise;

	// send chunks of data
	ubyte[] data = world.serialize();
	bool    finished = false;
	size_t  bytesSent = 0;
	while (!finished) {
		ubyte[1024] chunk     = 0x00; // padding
		size_t      chunkLen  = min(data.length, 1024);
		bytesSent            += chunkLen;
		chunk[0 .. chunkLen]  = data[0 .. chunkLen];
		data                  = data[chunkLen .. $];
		if (data.length == 0) {
			finished = true;
		}

		// level data chunk packet
		toSend ~= SToCPacketID.LevelDataChunk;
		toSend ~= nativeToBigEndian(cast(short) chunkLen);
		toSend ~= chunk;
		toSend ~= cast(ubyte)
			((cast(float) bytesSent / cast(float) world.volume()) * 100); // %
	}

	// level finalise packet
	byte[] finalise;
	finalise ~= SToCPacketID.LevelFinalise;
	finalise ~= nativeToBigEndian(world.w);
	finalise ~= nativeToBigEndian(world.h);
	finalise ~= nativeToBigEndian(world.l);
	toSend   ~= finalise;

	return toSend;
}

byte[] stoc_SetBlock(short x, short y, short z, byte block) {
	byte[] data;

	data ~= SToCPacketID.SetBlock;
	data ~= nativeToBigEndian(x);
	data ~= nativeToBigEndian(y);
	data ~= nativeToBigEndian(z);
	data ~= block;

	assert(data.length == SToCPacketSize.SetBlock);

	return data;
}

byte[] stoc_SpawnPlayer(
	string name, byte playerID, short x, short y, short z, byte yaw, byte pitch
) {
	byte[] data;

	data ~= SToCPacketID.SpawnPlayer;
	data ~= playerID;
	data ~= bytesFromString(name);
	data ~= nativeToBigEndian(cast(short) (x * 32));
	data ~= nativeToBigEndian(cast(short) (y * 32));
	data ~= nativeToBigEndian(cast(short) (z * 32));
	data ~= yaw;
	data ~= pitch;

	assert(data.length == SToCPacketSize.SpawnPlayer);

	return data;
}

byte[] stoc_Message(string message) {
	byte[] ret;
	ret ~= SToCPacketID.Message;
	ret ~= 69;
	ret ~= bytesFromString(message);

	assert(ret.length == SToCPacketSize.Message);

	return ret;
}
