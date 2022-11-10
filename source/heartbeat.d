import std.uri;
import std.stdio;
import std.array;
import std.format;
import std.net.curl;
import server;
import util;

void doHeartbeat(Server server) {
	static bool first = true;
	
	string url = format(
	    "%s?name=%s&port=%d&users=%d&max=%d&salt=blablabla&public=%s",
	    server.config.heartbeatURL,
	    encodeComponent(server.config.name),
	    server.config.port,
	    server.clients.length,
	    server.config.maxPlayers,
	    server.config.publicServer? "true" : "false"
	);

	string serverURL;
	try {
		serverURL = get(url).idup();
	}
	catch (CurlException e) {
		stderr.writefln("URL: %s", url);
		stderr.writeln(e);
	}
	
	if (first) {
	    util_Log("Server URL: %s", serverURL);
	    first = false;
	}
}
