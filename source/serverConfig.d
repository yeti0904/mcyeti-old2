import std.stdio;
import std.json;
import std.format;
import core.stdc.stdlib;

struct ServerConfig {
	string ip;
	ushort port;
	string heartbeatURL;
	size_t maxPlayers;
	bool   publicServer;
	string name;
}

ServerConfig createConfig(string jsonConfig) {
	ServerConfig ret;
	JSONValue    config;
	
	try {
		config = parseJSON(jsonConfig);

		ret.ip           = config["ip"].str;
		ret.port         = cast(ushort) config["port"].integer;
		ret.heartbeatURL = config["heartbeatURL"].str;
		ret.maxPlayers   = config["maxPlayers"].integer;
		ret.publicServer = config["public"].boolean;
		ret.name         = config["name"].str;
	}
	catch (JSONException e) {
		stderr.writefln("Failed to load json: %s\n%s", e.msg, e.info);
		exit(1);
	}

	return ret;
}

string configToJSON(ServerConfig* config) {
	return format(
		`{
	"name": "%s",
	"ip": "%s",
	"port": %d,
	"heartbeatURL": "%s",
	"maxPlayers": %d,
	"public": %s
}`,
		config.name, config.ip, config.port, config.heartbeatURL, config.maxPlayers,
		config.publicServer? "true" : "false"
	);
}
