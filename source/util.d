import std.stdio;
import std.format;
import std.datetime;

void util_Log(Char, A...)(in Char[] fmt, A args) {
	TimeOfDay time = (cast(DateTime) Clock.currTime()).timeOfDay;
	writef("[%s:%s:%s] ", time.hour, time.minute, time.second);
	
	writefln(fmt, args);
}
