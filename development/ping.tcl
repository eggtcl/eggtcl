#ping.tcl v1.2 - listens for ping requests in a chan or by msgs and responds accordingly
set pingver "1.2"

#Channel trigger words
set pingpubwords "!ping !pingme"

#List chans you don't want listen for here
set pingdisabled ""

foreach trigger [split $pingpubwords] { bind pub - $trigger pingnick }
bind ctcr - PING pingreply

proc pingnick {nick host hand chan {arg ""}} {
	global pingdisabled
	foreach chan [split $pingdisabled] {
		if {[string tolower $chan] == [string tolower $chan]} {
			return
		}
	}
	if {$arg == ""} { set arg $nick }
	if {[onchan $arg $chan]} { 
		putquick "PRIVMSG $arg :\001PING [clock clicks -milliseconds]\001"
	} else { 
		ping_exec $nick $host $hand $chan $arg
	}
	return 1
}
proc pingreply {nick host hand dest key arg} {
	global pingmethod server
	set pingnum [lindex $arg 0]
	set pingserver [lindex [split $server :] 0]
	if {![regexp -- {[^0-9]} $pingnum]} {
		puthelp "NOTICE $nick :Ping reply from $pingserver: [expr [expr [clock clicks -milliseconds] - $pingnum] / 1000.000] seconds"
		return 0
	}
}
proc ping_exec {nick host hand chan arg} {
set pinghost [lindex $arg 0]
if {[catch {exec ping $pinghost -c 1} ping]} { set ping 0 } 
if {[lindex $ping 0] == "0"} { putserv "PRIVMSG $chan :No responce from $pinghost"; return 0 }
if {[lindex $ping 0] != "0"} {
	if {[regexp {time=(.*) ms} $ping -> time]} {
		putserv "PRIVMSG $chan :Ping reply from $pinghost: $time ms"
		return 0
	}
 }
}

putlog "ping.tcl $pingver loaded"
