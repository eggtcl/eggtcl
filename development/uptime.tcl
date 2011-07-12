putlog "Loading: uptime.tcl"

lappend useless_cmds "!uptime"

bind pub -|- "!uptime" useless:uptime

proc useless:uptime {nick idx hand chan args} {
	if {[kernow:user $nick $idx]==""} { return 0 }
	putquick "PRIVMSG $chan :[exec hostname -f] uptime: [exec uptime]"
}
