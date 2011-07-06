#bitlbee.tcl - relay for bitlbee v0.1 by HM2K (updated: 01/02/07)
# based on linkchan

set debug 1
set debug_out 1
set shortcommands 1

bind pub o  `` bitlbee:sendmsg

bind dcc m bitlbee dcc:bitlbee
bind pub o .bitlbee pub:bitlbee

if {$shortcommands == 1} {bind dcc m bb dcc:bitlbee}

proc dcc:bitlbee {hand idx arg} {
 global botnick realname username chanbitlbee bitlbeeidx bitlbeeserv bitlbeenet bitlbeenick shortcommands bitlbeetrim bitlbeechan bitlbeepass
 set bitlbeenick $botnick
 set lchan [lindex $arg 0]
 set rchan [lindex $arg 1]
 set idpass [lindex $arg 2]
 set net [lindex $arg 3]
 set serv [lindex $arg 4]
 set port [lindex $arg 5]

  if {$serv == ""} {
   putdcc $idx "Specify a Server"
   putdcc $idx "usage: .bitlbee <localchan> <remotechan> <identpass> <network> <server> \[port\]"
  } else {
   if {[info exists bitlbeeidx]} {
    if {[valididx $bitlbeeidx]} {
     putdcc $bitlbeeidx "QUIT :Switching Servers"
     killdcc $bitlbeeidx
    }
   }
   if {$port == ""} { set port 6667 }
   set bitlbeeidx [connect $serv $port]

   set chanbitlbee $rchan
   set bitlbeechan $lchan
   set bitlbeeserv $serv
   set bitlbeenet $net
   set bitlbeepass $idpass
   control $bitlbeeidx bitlbee
   putbb "USER $username 0 0 :$realname"
   putbb "NICK :$bitlbeenick"
   set bitlbeetrim "abcdefghijklmnopqrstuvwxyzABCDEFGHIJGKLMNOPQRSTUVWXYZ1234567890 !@*.#~-_|\[\]\{\}`"
   #bind part - * part:bitlbee
   #bind pubm - * pubm:bitlbee
   #bind sign - * sign:bitlbee
   #bind ctcp - ACTION ctcp:bitlbee
   #bind join - * join:bitlbee
   #bind nick - * nick:bitlbee
   bind dcc m -bitlbee dcc:-bitlbee
   bind dcc m dumpbitlbee dcc:dumpbitlbee
   if {$shortcommands == 1} {
    bind dcc m -bb dcc:-bitlbee
    bind dcc m dumpbb dcc:dumpbitlbee
   }
   return 1
  }
}

proc pub:bitlbee {nick uhost hand chan arg} {
 global botnick realname username chanbitlbee bitlbeeidx bitlbeeserv bitlbeenet bitlbeenick bitlbeetrim bitlbeechan bitlbeepass
 set bitlbeenick $botnick
 set lchan [lindex $arg 0]
 set rchan [lindex $arg 1]
 set idpass [lindex $arg 2]
 set net [lindex $arg 3]
 set serv [lindex $arg 4]
 set port [lindex $arg 5]
  if {$serv == ""} {
   puthelp "PRIVMSG $chan :Specify a Server"
   puthelp "PRIVMSG $chan :usage: .bitlbee <localchan> <remotechan> <identpass> <network> <server> \[port\]"
  } else {
   if {[info exists bitlbeeidx]} {
    if {[valididx $bitlbeeidx]} {
     putdcc $bitlbeeidx "QUIT :Switching Servers"
     killdcc $bitlbeeidx
    }
   }
   if {$port == ""} { set port 6667 }
   set bitlbeeidx [connect $serv $port]

   set chanbitlbee $rchan
   set bitlbeechan $lchan
   set bitlbeeserv $serv
   set bitlbeenet $net
   set bitlbeepass $idpass
   control $bitlbeeidx bitlbee
   putbb "USER $username 0 0 :$realname"
   putbb "NICK :$bitlbeenick"
   set bitlbeetrim "abcdefghijklmnopqrstuvwxyzABCDEFGHIJGKLMNOPQRSTUVWXYZ1234567890 !@*.#~-_|\[\]\{\}`"
   return 1
  }
}

proc dcc:dumpbitlbee {hand idx arg} {
 putbb $arg
 return 1
}

proc dcc:-bitlbee {hand idx arg} {
 global bitlbeeidx chanbitlbee bitlbeeserv bitlbeenet bitlbeetrim shortcommands
 putbb "QUIT :Shutting Down Link"
 killdcc $bitlbeeidx
 bitlbee:shutdown
 return 1
}

proc bitlbee:shutdown {} {
 global bitlbeeidx chanbitlbee bitlbeeserv bitlbeenet bitlbeetrim shortcommands
 unset bitlbeeidx
 unset chanbitlbee
 unset bitlbeeserv
 unset bitlbeenet
 unset bitlbeetrim
 unbind part - * part:bitlbee
 unbind pubm - * pubm:bitlbee
  unbind sign - * sign:bitlbee
 unbind ctcp - ACTION ctcp:bitlbee
 unbind join - * join:bitlbee
 unbind nick - * nick:bitlbee
 unbind dcc m -bitlbee dcc:-bitlbee
 unbind dcc m dumpbitlbee dcc:dumpbitlbee
 clearqueue help
 if {$shortcommands == 1} {
  unbind dcc m -bb dcc:-bitlbee
  unbind dcc m dumpbb dcc:dumpbitlbee
 }
}

proc putbb {arg} {
 global bitlbeeidx debug_out
 if {$debug_out == 1} {putlog "bitlbee> $arg"}
 putdcc $bitlbeeidx $arg
}

proc bitlbee {idx arg} {
 global debug nick chanbitlbee bitlbeenet bitlbeenick username realname bitlbeetrim bitlbeepass
 if {$debug == 1} {putlog "bitlbee< $arg"}
 set arg2 [lindex $arg 0]
 switch $arg2 {
  PING {putbb "PONG [lindex $arg 1]"}
  ERROR {
   putserv "PRIVMSG $chanbitlbee :\0032ERROR: Closing Link"
   bitlbee:shutdown
  }
 }
 switch [lindex $arg 1] {
  001 {
   putbb "MODE $bitlbeenick :+i"
   putbb "JOIN $chanbitlbee"
   putbb "PRIVMSG $chanbitlbee :identify $bitlbeepass"
  }
  433 {
   set bitlbeenick $nick[rand 99]
   putdcc $idx "NICK :$bitlbeenick"
  }
  353 {puthelp "privmsg $chanbitlbee :$bitlbeenet NAMES list: [string trimleft [string trimleft [string trimleft $arg :] "abcdefghijklmnopqrstuvwxyzABCDEFGHIJGKLMNOPQRSTUVWXYZ1234567890 !@*.#~-_|\[\]\{\}`="] :]"}
  JOIN {puthelp "privmsg $chanbitlbee :\0033*** [lindex [split [lindex [split $arg2 !] 0] :] 1]@$bitlbeenet ([lindex [split $arg2 !] 1]) has joined $chanbitlbee"}
  KICK {bitlbee:kick $idx $arg}
  NICK {puthelp "privmsg $chanbitlbee :\0033*** [lindex [split [lindex [split $arg2 !] 0] :] 1]@$bitlbeenet in now known as [string trimleft [lindex $arg 2] :]@$bitlbeenet"}
  PART {puthelp "privmsg $chanbitlbee :\0033*** [lindex [split [lindex [split $arg2 !] 0] :] 1]@$bitlbeenet ([lindex [split $arg2 !] 1]) has left $chanbitlbee"}
  PRIVMSG {bitlbee:privmsg $idx $arg}
  QUIT {puthelp "privmsg $chanbitlbee :\0032*** [lindex [split [lindex [split $arg2 !] 0] :] 1]@$bitlbeenet ([lindex [split $arg2 !] 1]) Quit ([string trimleft [string trimleft [string trimleft $arg :] $bitlbeetrim] :])"}
 }
}

proc bitlbee:privmsg {idx arg} {
 global chanbitlbee bitlbeenet bitlbeetrim botnick network bitlbeechan
 set nick [lindex [split [lindex [split $arg !] 0] :] 1]
 if {$nick == $botnick} {
  putbb "QUIT :Yikes! Am I looking in a Mirror?"
  killdcc $idx
  bitlbee:shutdown
 } else {
  set text [string trimleft [string trimleft [string trimleft $arg :] $bitlbeetrim] :]
  if {[string tolower [lindex $arg 2]] == [string tolower $chanbitlbee]} {
   if {[string match \001*\001 $text]} {
    if {[string match \001ACTION*\001 $text]} {
     puthelp "privmsg $bitlbeechan :\0036 * $nick@$bitlbeenet[string trimright [string trimleft [string trimleft $text \001ACTION] ""] \001]"
    }
   } else {
    if {[string match -nocase [lindex $text 0] !names]} {
     putbb "PRIVMSG $chanbitlbee :$network NAMES list: [chanlist $chanbitlbee]"
    } else {
     puthelp "privmsg $bitlbeechan :<$nick@$bitlbeenet> $text"
    }
   }
  } else {
  	puthelp "privmsg $bitlbeechan :<$nick@$bitlbeenet> $text"
  }
 }
}

proc bitlbee:kick {idx arg} {
 global bitlbeenick chanbitlbee
 if {$bitlbeenick == [lindex $arg 3]} {putbb "JOIN $chanbitlbee"}
}

proc bitlbee:sendmsg {nick host hand chan text} {
 global chanbitlbee
 putbb "PRIVMSG $chanbitlbee :$text"
}

proc join:bitlbee {nick uhost hand chan args} {
 global network bitlbeeidx chanbitlbee
 if {[info exists bitlbeeidx] && [string match [string tolower $chan] [string tolower $chanbitlbee]]} {
  if {[valididx $bitlbeeidx]} {putbb "PRIVMSG $chan :\0033*** $nick@$network ($uhost) has joined $chan"}
 }
}

proc part:bitlbee {nick uhost hand chan msg} {
 global network bitlbeeidx chanbitlbee
 if {[info exists bitlbeeidx] && [string match [string tolower $chan] [string tolower $chanbitlbee]]} {
  if {$msg != ""} {set msg ($msg)}
  if {[valididx $bitlbeeidx]} {putbb "PRIVMSG $chan :\0033*** $nick@$network ($uhost) has left $chan $msg"}
 }
}

proc pubm:bitlbee {nick uhost hand chan text} {
 global network bitlbeeidx chanbitlbee bitlbeenick
 if {$nick == $bitlbeenick} {
  putbb "QUIT :Yikes! Am I looking in a Mirror?"
  killdcc $idx
  bitlbee:shutdown
 } else {
  if {[info exists bitlbeeidx] && [string match [string tolower $chan] [string tolower $chanbitlbee]]} {
   if {[valididx $bitlbeeidx]} {
    if {[string match -nocase [lindex $text 0] !names]} {
     putbb "NAMES $chan"
    } else {
     putbb "PRIVMSG $chan :<$nick@$network> $text"
    }
   }
  }
 }
}

proc sign:bitlbee {nick uhost hand chan reason} {
 global network bitlbeeidx chanbitlbee
 if {[info exists bitlbeeidx] && [string match [string tolower $chan] [string tolower $chanbitlbee]]} {
  if {[valididx $bitlbeeidx]} {putbb "PRIVMSG $chan :\0032*** $nick@$network ($uhost) Quit ($reason)"}
 }
}

proc ctcp:bitlbee {nick uhost hand dest keywork arg} {
 global network bitlbeeidx chanbitlbee
 if {[info exists bitlbeeidx]} {
  if {[valididx $bitlbeeidx] && [string match [string tolower $dest] [string tolower $chanbitlbee]]} {
   putbb "PRIVMSG $dest :\0036 * $nick@$network $arg"
  }
 }
}

proc nick:bitlbee {nick uhost hand chan newnick} {
 global network bitlbeeidx chanbitlbee
 if {[info exists bitlbeeidx] && [string match [string tolower $chan] [string tolower $chanbitlbee]]} {
  if {[valididx $bitlbeeidx]} {putbb "PRIVMSG $chan :\0033*** $nick@$network is now known as $newnick@$network"}
 }
}