import std.uri;
import std.stdio;
import std.array;
import std.format;
import std.net.curl;
import server;
import util;

void DoHeartbeat(Server server) {
	static bool first = true;
	
	string url = format(
	    "%s?name=%s&port=%d&users=%d&max=%d&salt=blablabla&public=%s&server=MCYeti",
	    server.config.heartbeatURL,
	    encodeComponent(server.config.name),
	    server.config.port,
	    server.GetConnectedIPs(),
	    server.config.maxPlayers,
	    server.config.publicServer? "true" : "false"
	);

	string serverURL;
	try {
		serverURL = get(url).idup();
	}
	catch (Throwable e) {
		stderr.writefln("URL: %s", url);
		stderr.writeln(e);
	}
	
	if (first) {
	    Util_Log("Server URL: %s", serverURL);
	    first = false;
	}
}
