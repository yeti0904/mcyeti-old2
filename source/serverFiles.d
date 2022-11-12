import std.stdio;
import std.file;
import std.path;

void CreateServerDirectories() {
	string folder = dirName(thisExePath());

	if (!exists(folder ~ "/worlds")) {
		mkdir(folder ~ "/worlds");
	}
}
