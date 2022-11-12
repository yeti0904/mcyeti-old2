import std.stdio;
import std.file;
import std.bitmanip;
import world;

World LoadWorld(string fileName) {
	File  file = File(fileName, "rb");
	World ret  = new World();

	// read level size
	short xSize = littleEndianToNative!short(file.rawRead(new ubyte[2])[0 .. 2]);
	short ySize = littleEndianToNative!short(file.rawRead(new ubyte[2])[0 .. 2]);
	short zSize = littleEndianToNative!short(file.rawRead(new ubyte[2])[0 .. 2]);

	ubyte[] levelData = file.rawRead(new ubyte[xSize * ySize * zSize]);

	writeln(levelData.length);

	ret.w = xSize;
	ret.h = ySize;
	ret.l = zSize;
	ret.FromBlocksArray(levelData);

	return ret;
}

void WriteWorld(string fileName, World world) {
	File file = File(fileName, "wb");

	file.rawWrite(nativeToLittleEndian!short(world.w));
	file.rawWrite(nativeToLittleEndian!short(world.h));
	file.rawWrite(nativeToLittleEndian!short(world.l));

	file.rawWrite(world.Serialise(false));
}
