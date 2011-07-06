#dns.tcl v0.13 - looks up a host/ip and resolves it accordingly on trigger
#based on a script by Vertex
set dnsver "v0.13"

if {[catch {exec which nslookup} lookpath]} {
  putlog "$host/IP Banner and dnslookup proc disabled, error:\n$lookpath"
  return 0
} else {
  proc dnslookup {host} {
    global lookpath
    set name "Unknown"; set ip "Unknown"; set errmsg "Unknown";
    set server_lines 0
    set $host [lindex [string tolower $host] 0]
    if {[catch {exec $lookpath [lindex $host 0]} buff]} {
      foreach line [split $buff \n] {
	if {[string first "${host}:" $line] != -1} {
	  set errmsg [string trim [lindex [split $line :] 1]]
	}
      }
      return "Error:$errmsg"
    }
    set buff [split $buff \n]
    set buff [lreplace $buff 0 1]
    if {[regexp {name = (.*)\.} $buff -> name]} { set ip $host }

    foreach data $buff {
      switch [lindex $data 0] {
	"Name:" {
	  set name [string trim [lindex [split $data :] 1]]
	}
	"Address:" {
	  set ip [string trim [lindex [split $data :] 1]]
	}
	"Addresses:" {
	  set ip [string trim [lindex [split $data :] 1]]
	}
      }
    }
    return "${name}:${ip}"
  }
}

proc lookup:do_lookup {ni uh ha chan text} {
  if {[llength $text] > 1} { return 0 }
  if {[onchan $text $chan]} {
    set host_ip [dnslookup [lindex [split [getchanhost $text $chan] @] 1]]
  } else {
  set host_ip [dnslookup $text]
  }
  set name [lindex [split $host_ip :] 0]
  set ip [lindex [split $host_ip :] 1]
  puthelp "privmsg $chan :DNS Lookup: $text ($name -> $ip)"
  return 1                                                 
}

bind pub - !dns lookup:do_lookup

putlog "dns.tcl $dnsver loaded"
