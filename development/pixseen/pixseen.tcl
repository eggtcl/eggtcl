# pixseen.tcl --
#
#       SQLite powered seen script. Keeps track of everyone, based on nickname.
#
# Copyright (c) 2010, Rickard Utgren <rutgren@gmail.com>
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#
# RCS: $Id$
#
# v1.1 by Pixelz - unreleased
#	- Fixed a problem with ValidTable always failing on some older SQLite versions
#	- Fixed a problem with the public trigger never showing the syntax help
#	- Minor fixes
#	- Fixed a problem with glob & regex matching where only the oldest matches would ever be returned
#	- Added a setting to change the maximum number of results returned from a query
#
# v1.0 by Pixelz - April 5, 2010
#	- Initial release

# ToDo:
# - add some kind of botnet synching
#		- auto-discover pixseen bots on link
#		- auto-assign a primary bot for each channel that will answer public requests
#		* Possible different routes for inter-bot information sharing:
#			* "Synch everything" route:
#				- synch databases on link
#				- keep synching across the net whenever there's a change.
#					- probably do this blindly, to account for IRCDs that doesn't show all joins/parts (ircu)
#					- perhaps add some logic to this, so bots dont push info to other bots that are in the same channel (and would see it anyway), at least on non-ircu, non-chanmode-D channels
#			* "Ask botnet" route:
#				- Don't synch databases
#				- Ask other bots for information on each seen request to the bot
#			* Considerations:
#				* For both of these methods, the clock probably has to fairly synched up, particularly for the "synch everything" route
#					- A simple solution: check TS delta on link, and complain loudly if it's too high, or compensate for it somehow
# - Add IRCU support ("hidden" users in +D channels) -> names -d #chan (who #chan cd)
#	- OR just tell quakenet users to use thommey's +D patch
# - add option to track every channel separately
# - track channel idle time, this would probably synergize well with the "track each channel separetly" option
# - find out if it's a good idea to [catch] each sql query (catch is slow, is there a better alternative?)
# - test the idx lookup stuff more, I suspect there's a bug in it somewhere
# - perhaps get rid of the daily unused-channels cleanup, and do it the same way as pixinfo.tcl.
#		- Make sure this isn't hugely resource intensive first.
# - Add a setting to set the default matching type? OR Apply better logic to it? perhaps assume glob if it contains asterisk, Most Users fail at regex anyway...


package require Tcl 8.5
package require msgcat 1.4.2
package require eggdrop 1.6
package require sqlite3 3.3.0;# order by desc was added in this version

namespace eval ::pixseen {
	# path to the database file
	variable dbfile {scripts/pixseen.db}
	
	# Output with NOTICE nick (0) or PRIVMSG #chan (1)
	variable outnotc 1
	
	# Language
	variable defaultLang "en"
	
	# Maximum number of results to display in public
	variable pubResults 3
	
	# Maximum number of results to display in private message
	variable msgResults 5
	
	# Maximum number of results to display in the partyline
	variable dccResults 10
	
	## end of settings ##
	
	# list of locales, if you translate the script, add your translation to this list
	variable locales [list "en" "en_us_bork"]
	
	namespace import ::msgcat::*
	# mcload fails to load _all_ .msg files, so we have to do it manually
	foreach f [glob -nocomplain -directory [file join [file dirname [info script]] pixseen-msgs] -type {b c f l} *.msg] {
		source -encoding {utf-8} $f
	}
	unset -nocomplain f
	
	mclocale $defaultLang
	setudef flag {seen}
	setudef str {seenlang}
	variable ::botnick
	variable ::botnet-nick
	variable ::nicklen
	variable seenFlood
	variable seenver {1.1}
	variable dbVersion 1
}

## utility procs

proc ::pixseen::validlang {lang} {
	variable locales
	if {[lsearch -exact -nocase $locales $lang] == -1} {
		return 0
	} else {
		return 1
	}
}

# msgcat compatible duration proc
proc ::pixseen::pixduration {seconds} {
	set map [list \
		{years} [mc {years}] \
		{year} [mc {year}] \
		{months} [mc {months}] \
		{month} [mc {month}] \
		{weeks} [mc {weeks}] \
		{week} [mc {week}] \
		{days} [mc {days}] \
		{day} [mc {day}] \
		{hours} [mc {hours}] \
		{hour} [mc {hour}] \
		{minutes} [mc {minutes}] \
		{minute} [mc {minute}] \
		{seconds} [mc {seconds}] \
		{second} [mc {second}] \
	]
	string map $map [duration $seconds]
}

# takes an idx and returns the user@host associated with it.
# ONLY to be called from finduhost. DON'T CALL THIS DIRECTLY!
proc ::pixseen::Idx2Uhost {idx} {
	# for some mind-boggling reason, eggdrop doesn't provide the uhost for a
	# lot of the partyline binds, so we extract it from dcclist
	foreach item [dcclist chat] {
		lassign $item i - u;
		if {$idx eq $i} {
			return $u
		}
	}
	# this should never happen?
	putlog [mc {%1$s error; %2$s was unable to extract uhost. PLEASE REPORT THIS BUG!} {pixseen.tcl} {::pixseen::Idx2Uhost}]
	return
}

# takes a handle and returns the user@host associated with it.
# ONLY to be called from finduhost. DON'T CALL THIS DIRECTLY!
proc ::pixseen::Hand2Uhost {botname hand {chan {*}}} {
	foreach item [whom $chan] {
		lassign $item Hand Botname Uhost Flags Idle Away Chan
		if {[string equal -nocase $botname $Botname] && [string equal -nocase $hand $Hand] && ($chan ne {*} && [string equal -nocase $chan $Chan])} {
			return $Uhost
		}
	}
	# this should never happen?
	putlog [mc {%1$s error; %2$s was unable to extract uhost. PLEASE REPORT THIS BUG!} {pixseen.tcl} {::pixseen::Hand2Uhost}]
	return
}

# figures out the uhost using different methods for different binds
# returns the uhost found, or "" if it can't find one.
proc ::pixseen::finduhost {bind args} {
	# chjn isn't listed because that bind actually calls the proc with the uhost
	# chon/chof is NOT triggered for remote users
	# away/chpt (and chjn) IS triggered for remote users
	switch -exact -- $bind {
		{chon} - {chof} {
			lassign $args idx
			return [Idx2Uhost $idx]
		}
		{chpt} {
			lassign $args idx botname hand chan
			if {[string equal -nocase $botname ${::botnet-nick}]} {
				# this is a local user, grab the uhost based on the idx
				return [Idx2Uhost $idx]
			} else {
				# this is a remote user, make an educated guess
				return [Hand2Uhost $botname $hand $chan]
			}
		}
		{away} {
			lassign $args idx botname
			if {[string equal -nocase $botname ${::botnet-nick}]} {
				# this is a local user, grab the uhost based on the idx
				return [Idx2Uhost $idx]
			} else {
				# this is a remote user. it is NOT POSSIBLE to get their uhost
				return
			}
		}
		default {
			return
		}
	}
}

# returns 1 if a module is loaded, 0 if not
proc ::pixseen::modloaded {module} {
	if {[lsearch -exact -index 0 [modules] $module] == -1} {
		return 0
	} else {
		return 1
	}
}

# returns the name of a partyline channel, or whatever was passed to it
# if there's no name set
proc ::pixseen::partychanname {chan} {
	if {(![modloaded assoc]) || ($chan == 0)} {
		return $chan
	} elseif {![catch {set name [assoc $chan]}]} {
		if {$name ne {}} {
			return $name
		} else {
			return $chan
		}
	} else {
		return $chan
	}
}

# returns 1 if the nick is valid on IRC, 0 if not
proc ::pixseen::validnick {nick} {
	if {([info exists ::nicklen]) && ($::nicklen > 32)} {
		set len $::nicklen
	} else {
		set len 32
	}
	if {[string length $nick] > $len} {
		return 0
	# FixMe: make sure these are all of the valid chars
	} elseif {![regexp -- {^[a-zA-Z\|\[\]`^\{\}][a-zA-Z0-9\-_\|\[\]`^\{\}\\]*$} $nick]} {
		return 0
	} else {
		return 1
	}
}

# returns 1 if a channel is set +secret, 0 if not
proc ::pixseen::issecret {chan} {
	if {[validchan $chan] && [channel get $chan secret]} {
		return 1
	} else {
		return 0
	}
}

proc ::pixseen::handseen {handle} {
	if {![validuser $handle]} {
		return
	} else {
		lassign [getuser $handle LASTON] timestamp location
		# the location can be fun things like "linked" or "@botnick" so let's not even go there...
		return [mc {%1$s was last seen %2$s ago.} $handle [pixduration [expr {[clock seconds] - $timestamp}]]]
	}
}

proc ::pixseen::lastspoke {nick chan} {
	if {[set idle [getchanidle $nick $chan]] == 0} {
		return
	} else {
		# whose great idea was it to return idle time in minutes? o_O
		return [pixduration [expr {$idle * 60}]]
	}
}

# returns the channel if the user is logged in to the partyline. if not, returns ""
proc ::pixseen::onpartyline {handle} {
	foreach item [whom *] {
		lassign $item nick bot uhost flags idle away chan
		if {[string equal -nocase $handle $nick]} { return [partychanname $chan] }
	}
	return
}

# checks the flood array and removes old timestamps.
# will eventually remove itself if we're not being flooded
proc ::pixseen::RemoveFlood {args} {
	variable seenFlood
	if {![array exists seenFlood]} { return }
	set time [clock seconds]
	foreach uhost [array names seenFlood] {
		foreach timestamp $seenFlood($uhost) {
			# don't append the timestamp if it's older than 60 seconds
			if {[expr {$time - 60}] <= $timestamp} {
				lappend stampList $timestamp
			}
		}
		if {[info exists stampList]} {
			set seenFlood($uhost) $stampList
		} else {
			array unset seenFlood $uhost
		}
	}
}

# returns 1 if we're flooded, 0 if not
proc ::pixseen::checkflood {uhost} {
	variable seenFlood
	RemoveFlood
	# case 1: uhost doesn't exist in the array, we're not being flooded
	if {![info exists seenFlood($uhost)]} {
		set seenFlood($uhost) [clock seconds]
		return 0
	# case 2: the list for this uhost is full, so we're being flooded with 6 lines over 60 seconds
	} elseif {[llength $seenFlood($uhost)] >= 6} {
		set seenFlood($uhost) [concat "[lrange [lsort -integer $seenFlood($uhost)] 1 end] [clock seconds]"]
		return 1
	# case 3: the list for this uhost isn't full, we're not being flooded
	} else {
		lappend seenFlood($uhost) [clock seconds]
		return 0
	}
}

# Formats seen events for output
proc ::pixseen::formatevent {event nick uhost time chan reason othernick} {
	set duration [pixduration [expr {[clock seconds] - $time}]]
	switch -exact -- $event {
		{0} {;# part
			if {$reason eq {}} {
				if {[issecret $chan]} {
					return [mc {%1$s (%2$s) was last seen parting a channel %3$s ago.} $nick $uhost $duration]
				} else {
					return [mc {%1$s (%2$s) was last seen parting %3$s %4$s ago.} $nick $uhost $chan $duration]
				}
			} else {
				if {[issecret $chan]} {
					return [mc {%1$s (%2$s) was last seen parting a channel %3$s ago, stating "%4$s"} $nick $uhost $duration $reason]
				} else {
					return [mc {%1$s (%2$s) was last seen parting %3$s %4$s ago, stating "%5$s"} $nick $uhost $chan $duration $reason]
				}
			}
		}
		{1} {;# join
			if {[issecret $chan]} {
				return [mc {%1$s (%2$s) was last seen joining a channel %3$s ago.} $nick $uhost $duration]
			} else {
				if {[onchan $nick $chan]} {
					return [mc {%1$s (%2$s) was last seen joining %3$s %4$s ago. %1$s is still on %3$s.} $nick $uhost $chan $duration]
				} else {
					return [mc {%1$s (%2$s) was last seen joining %3$s %4$s ago. I don't see %1$s on %3$s now, though.} $nick $uhost $chan $duration]
				}
			}
		}
		{2} {;# nick (old)
			if {[issecret $chan]} {
				return [mc {%1$s (%2$s) was last seen changing nicks to %4$s on a channel %3$s ago.} $nick $uhost $duration $othernick]
			} else {
				return [mc {%1$s (%2$s) was last seen changing nicks to %5$s on %3$s %4$s ago.} $nick $uhost $chan $duration $othernick]
			}
		}
		{3} {;# nick (new)
			if {[issecret $chan]} {
				return [mc {%1$s (%2$s) was last seen changing nicks from %4$s on a channel %3$s ago.} $nick $uhost $duration $othernick]
			} else {
				if {[onchan $nick $chan]} {
					return [mc {%1$s (%2$s) was last seen changing nicks from %5$s on %3$s %4$s ago. %1$s is still on %3$s.} $nick $uhost $chan $duration $othernick]
				} else {
					return [mc {%1$s (%2$s) was last seen changing nicks from %5$s on %3$s %4$s ago. I don't see %1$s on %3$s now, though.} $nick $uhost $chan $duration $othernick]
				}
			}
		}
		{4} {;# sign (quit)
			if {[issecret $chan]} {
				return [mc {%1$s (%2$s) was last seen quitting from a channel %3$s ago.} $nick $uhost $duration]
			} elseif {$reason eq {}} {
				return [mc {%1$s (%2$s) was last seen quitting from %3$s %4$s ago.} $nick $uhost $chan $duration]
			} else {
				return [mc {%1$s (%2$s) was last seen quitting from %3$s %4$s ago, stating "%5$s"} $nick $uhost $chan $duration $reason]
			}
		}
		{5} {;# splt (netsplit)
			if {[issecret $chan]} {
				return [mc {%1$s (%2$s) was last seen parting a channel due to a netsplit %3$s ago.} $nick $uhost $duration]
			} else {
				return [mc {%1$s (%2$s) was last seen parting %3$s due to a netsplit %4$s ago.} $nick $uhost $chan $duration]
			}
		}
		{6} {;# rejn (netsplit rejoin)
			if {[issecret $chan]} {
				return [mc {%1$s (%2$s) was last seen rejoining a channel from a netsplit %3$s ago.} $nick $uhost $duration]
			} else {
				if {[onchan $nick $chan]} {
					return [mc {%1$s (%2$s) was last seen rejoining %3$s from a netsplit %4$s ago. %1$s is still on %3$s.} $nick $uhost $chan $duration]
				} else {
					return [mc {%1$s (%2$s) was last seen rejoining %3$s from a netsplit %4$s ago. I don't see %1$s on %3$s now, though.} $nick $uhost $chan $duration]
				}
			}
		}
		{7} {;# kick
			if {[issecret $chan]} {
				return [mc {%1$s (%2$s) was last seen kicked from a channel %3$s ago.} $nick $uhost $duration]
			} else {
				return [mc {%1$s (%2$s) was last seen kicked from %3$s by %4$s %5$s ago, with the reason "%6$s"} $nick $uhost $chan $othernick $duration $reason]
			}
		}
		{8} {;# chon (enter partyline)
			if {[onpartyline $nick] ne {}} {
				return [mc {%1$s (%2$s) was last seen entering the partyline %3$s ago. %1$s is on the partyline right now.} $nick $uhost $duration]
			} else {
				return [mc {%1$s (%2$s) was last seen entering the partyline %3$s ago. I don't see %1$s on the partyline now, though.} $nick $uhost $duration]
			}
		}
		{9} {;# chof (leaves partyline)
			if {[set pchan [onpartyline $nick]] ne {}} {
				return [mc {%1$s (%2$s) was last seen leaving the partyline %3$s ago. %1$s is on the partyline channel %4$s still.} $nick $uhost $duration $pchan]
			} else {
				return [mc {%1$s (%2$s) was last seen leaving the partyline %3$s ago.} $nick $uhost $duration]
			}
		}
		{10} {;# chjn (joins partyline channel)
			if {[onpartyline $nick] ne {}} {
				return [mc {%1$s (%2$s) was last seen entering the partyline on %3$s %4$s ago. %1 is on the partyline right now.} $nick $uhost [partychanname $chan] $duration]
			} else {
				return [mc {%1$s (%2$s) was last seen entering the partyline on %3$s %4$s ago. I don't see %1$s on the partyline now, though.} $nick $uhost [partychanname $chan] $duration]
			}
		}
		{11} {;# chpt (parts partyline channel)
			if {[set pchan [onpartyline $nick]] ne {}} {
				return [mc {%1$s (%2$s) was last seen leaving the partyline from %3$s %4$s ago. %1$s is on the partyline channel %5$s still.} $nick $uhost [partychanname $chan] $duration $pchan]
			} else {
				return [mc {%1$s (%2$s) was last seen leaving the partyline from %3$s %4$s ago.} $nick $uhost [partychanname $chan] $duration]
			}
		}
		{12} {;# away (partyline away)
			if {[onpartyline $nick] ne {}} {
				return [mc {%1$s was last seen marked as away (%2$s) on the partyline %3$s ago. %1$s is on the partyline right now.} $nick $reason $duration]
			} else {
				return [mc {%1$s was last seen marked as away (%2$s) on the partyline %3$s ago. I don't see %1$s on the partyline now, though.} $nick $reason $duration]
			}
		}
		{13} {;# back (partyline back from away)
			if {[onpartyline $nick] ne {}} {
				return [mc {%1$s was last seen returning to the partyline %2$s ago. %1$s is on the partyline right now.} $nick $duration]
			} else {
				return [mc {%1$s was last seen returning to the partyline %2$s ago. I don't see %1$s on the partyline now, though.} $nick $duration]
			}
		}
		default {
			putlog [mc {%1$s error; Unhandled event in %2$s: %3$s} {pixseen.tcl} {formatevent} $event]
			return [mc {I don't remember seeing %s.} $nick]
		}
	}
}

## SQLite functions

# This is the SQLite collation function, if it's changed, the index has to be rebuilt with REINDEX or it'll cause Weird Behaviour
proc ::pixseen::rfccomp {a b} {
	string compare [string map [list \{ \[ \} \] ~ ^ | \\] [string toupper $a]] [string map [list \{ \[ \} \] ~ ^ | \\] [string toupper $b]]
}

proc ::pixseen::chan2id {chan} {
	if {[catch {seendb eval { INSERT OR IGNORE INTO chanTb VALUES(NULL, $chan); }} error]} {
		putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
	}
	if {[catch {set retval [seendb eval { SELECT chanid FROM chanTb WHERE chan=$chan LIMIT 1 }]} error]} {
		putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
		return -code error [mc {SQL error %1$s; %2$s} [seendb errorcode] $error]
	} else {
		return $retval
	}
}

# SQLite regexp function, squelches regex errors and turn on nocase
proc ::pixseen::pixregexp {args} {
	if {[catch {set result [regexp -nocase -- {*}$args]}]} {
		return 0
	} else {
		return $result
	}
}

##

proc ::pixseen::dbAdd {nick event timestamp uhost args} {
	switch -exact -- $event {
		{part} {;# 0
			lassign $args chan reason
			if {[catch {seendb eval { INSERT OR REPLACE INTO seenTb VALUES(0, $nick, $uhost, $timestamp, chan2id($chan), $reason, NULL) }} error]} {
				putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
			}
		}
		{join} {;# 1
			lassign $args chan
			if {[catch {seendb eval { INSERT OR REPLACE INTO seenTb VALUES(1, $nick, $uhost, $timestamp, chan2id($chan), NULL, NULL) }} error]} {
				putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
			}
		}
		{nick} {;# 2 & 3
			lassign $args chan newnick
			if {[catch {seendb eval {
				-- old nick;
				INSERT OR REPLACE INTO seenTb VALUES(2, $nick, $uhost, $timestamp, chan2id($chan), NULL, $newnick);
				-- new nick;
				INSERT OR REPLACE INTO seenTb VALUES(3, $newnick, $uhost, $timestamp, chan2id($chan), NULL, $nick);
			}} error]} {
				putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
			}
		}
		{sign} {;# 4 (quit)
			lassign $args chan reason
			if {[catch {seendb eval { INSERT OR REPLACE INTO seenTb VALUES(4, $nick, $uhost, $timestamp, chan2id($chan), $reason, NULL) }} error]} {
				putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
			}
		}
		{splt} {;# 5
			lassign $args chan
			if {[catch {seendb eval { INSERT OR REPLACE INTO seenTb VALUES(5, $nick, $uhost, $timestamp, chan2id($chan), NULL, NULL) }} error]} {
				putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
			}
		}
		{rejn} {;# 6
			lassign $args chan
			if {[catch {seendb eval { INSERT OR REPLACE INTO seenTb VALUES(6, $nick, $uhost, $timestamp, chan2id($chan), NULL, NULL) }} error]} {
				putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
			}
		}
		{kick} {;# 7
			lassign $args chan reason aggressor
			if {[catch {seendb eval { INSERT OR REPLACE INTO seenTb VALUES(7, $nick, $uhost, $timestamp, chan2id($chan), $reason, $aggressor) }} error]} {
				putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
			}
		}
		{chon} {;# 8 (enters partyline)
			if {[catch {seendb eval { INSERT OR REPLACE INTO seenTb VALUES(8, $nick, $uhost, $timestamp, NULL, NULL, NULL) }} error]} {
				putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
			}
		}
		{chof} {;# 9 (leaves partyline)
			if {[catch {seendb eval { INSERT OR REPLACE INTO seenTb VALUES(9, $nick, $uhost, $timestamp, NULL, NULL, NULL) }} error]} {
				putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
			}
		}
		{chjn} {;# 10 (joins partyline channel)
			lassign $args chan botname
			if {[catch {seendb eval { INSERT OR REPLACE INTO seenTb VALUES(10, $nick, $uhost, $timestamp, chan2id($chan), NULL, $botname) }} error]} {
				putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
			}
		}
		{chpt} {;# 11 (parts partyline channel)
			lassign $args chan botname
			if {[catch {seendb eval { INSERT OR REPLACE INTO seenTb VALUES(11, $nick, $uhost, $timestamp, chan2id($chan), NULL, $botname) }} error]} {
				putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
			}
		}
		{away} {;# 12 (partyline away)
			lassign $args botname reason
			if {[catch {seendb eval { INSERT OR REPLACE INTO seenTb VALUES(12, $nick, $uhost, $timestamp, NULL, $reason, $botname) }} error]} {
				putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
			}
		}
		{back} {;# 13 (partyline back from away)
			lassign $args botname
			if {[catch {seendb eval { INSERT OR REPLACE INTO seenTb VALUES(13, $nick, $uhost, $timestamp, NULL, NULL, $botname) }} error]} {
				putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
			}
		}
		default {
			putlog [mc {%1$s error; Unhandled event in %2$s: %3$s} {pixseen.tcl} {dbAdd} $event]
			return
		}
	}
	return
}

## event binds

proc ::pixseen::PART {nick uhost hand chan msg} {
	dbAdd $nick {part} [clock seconds] $uhost $chan $msg
	return
}

proc ::pixseen::JOIN {nick uhost hand chan} {
	dbAdd $nick {join} [clock seconds] $uhost $chan
	return
}

proc ::pixseen::NICK {nick uhost hand chan newnick} {
	dbAdd $nick {nick} [clock seconds] $uhost $chan $newnick
	return
}

proc ::pixseen::SIGN {nick uhost hand chan reason} {
	dbAdd $nick {sign} [clock seconds] $uhost $chan $reason
	return
}

proc ::pixseen::SPLT {nick uhost hand chan} {
	dbAdd $nick {splt} [clock seconds] $uhost $chan
	return
}

proc ::pixseen::REJN {nick uhost hand chan} {
	dbAdd $nick {rejn} [clock seconds] $uhost $chan
	return
}

proc ::pixseen::KICK {nick uhost hand chan target reason} {
	dbAdd $target {kick} [clock seconds] [getchanhost $target $chan] $chan $reason $nick
	return
}

proc ::pixseen::CHON {hand idx} {
	if {[set uhost [finduhost {chon} $idx]] ne {}} {
		dbAdd $hand {chon} [clock seconds] $uhost
	}
	return
}

proc ::pixseen::CHOF {hand idx} {
	if {[set uhost [finduhost {chof} $idx]] ne {}} {
		dbAdd $hand {chon} [clock seconds] $uhost
	}
	return
}

proc ::pixseen::CHJN {botname hand chan flag idx uhost} {
	dbAdd $hand {chon} [clock seconds] $uhost $chan $botname
	return
}

proc ::pixseen::CHPT {botname hand idx chan} {
	if {[set uhost [finduhost {chpt} $idx $botname $hand $chan]] ne {}} {
		dbAdd $hand {chon} [clock seconds] $uhost $chan $botname
	}
	return
}

proc ::pixseen::AWAY {botname idx text} {
	if {[string equal -nocase $botname ${::botnet-nick}]} {
		# this is a local away
		if {$text ne {}} {
			# user is away
			if {[set uhost [finduhost {away} $idx $botname]] ne {}} {
				dbAdd [idx2hand $idx] {away} [clock seconds] $uhost $botname $text
			}
		} else {
			# user has returned
			if {[set uhost [idx2uhost {away} $idx $botname]] ne {}} {
				dbAdd [idx2hand $idx] {back} [clock seconds] $uhost $botname
			}
		}
	} else {
		# this is a remote away. It's not possible to figure out the handle,
		# let alone the uhost, so we bail out.
		return
	}
	return
}

##

# returns a list of: id event nick uhost time chan reason othernick
proc ::pixseen::dbGetNick {target} {
	if {[catch {set result [seendb eval { SELECT event, nick, uhost, time, chanTb.chan, reason, othernick FROM seenTb, chanTb ON seenTb.chanid = chanTb.chanid WHERE nick=$target LIMIT 1 }]} error]} {
		putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
		return
	}
	return $result
}

# returns: a list of nicks matching the pattern
proc ::pixseen::dbSearchGlob {nick uhost chan} {
	# transform GLOB syntax into LIKE syntax:
	set nick [string map [list "\\" "\\\\" "%" "\%" "_" "\_" "*" "%" "?" "_"] $nick]
	set uhost [string map [list "\\" "\\\\" "%" "\%" "_" "\_" "*" "%" "?" "_"] $uhost]
	set chan [string map [list "\\" "\\\\" "%" "\%" "_" "\_" "*" "%" "?" "_"] $chan]
	if {$nick eq {}} { set nick "*"	}
	if {$uhost eq {}} { set uhost "*" }	                                       
	if {[catch { set result [seendb eval { SELECT nick FROM seenTb, chanTb ON seenTb.chanid = chanTb.chanid WHERE nick LIKE $nick ESCAPE '\' AND uhost LIKE $uhost ESCAPE '\' AND chanTb.chan LIKE $chan ESCAPE '\' ORDER BY seenTb.time DESC }] } error]} {
		putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
		return
	} else {
		return $result
	}
}

# returns: a list of nicks matching the pattern
proc ::pixseen::dbSearchRegex {nick uhost chan} {
if {[catch { set result [seendb eval { SELECT nick FROM seenTb, chanTb ON seenTb.chanid = chanTb.chanid WHERE nick REGEXP $nick AND uhost REGEXP $uhost AND chanTb.chan REGEXP $chan ORDER BY seenTb.time DESC }] } error]} {
		putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
		return
	} else {
		return $result
	}
}

# cleans out unused channels from the database
proc ::pixseen::dbCleanup {args} {
	putlog [mc {%s: performing database maintenance...} {pixseen.tcl}]
	if {[catch {set idList [seendb eval { SELECT chanid FROM chanTb WHERE chanid NOT IN (SELECT chanid FROM seenTb WHERE chanid = chanTb.chanid) }]} error]} {
		putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
	} elseif {$idList ne {}} {
		foreach id $idList {
			if {[catch {seendb eval { DELETE FROM chanTb WHERE chanid=$id }} error]} {
				putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
			}
		}
	}
	return
}

# Parses command arguments.
# Returns: a list of "nick uhost chan mode".
# Mode 0 = exact matching (the default)
# Mode 1 = glob matching
# Mode 2 = regex matching
proc ::pixseen::ParseArgs {text} {
	# !seen foobar
	# !seen foobar.com
	# !seen #foobar
	# !seen foobar foobar.com
	# !seen foobar #foobar
	# !seen foobar.com #foobar
	# !seen foobar.com foobar
	# !seen #foobar foobar
	# !seen #foobar foobar.com
	# !seen foobar foobar.com #foobar
	
	# default to exact mode
	set mode 0

	# grab the switches
	set i 0
	foreach item [set arg [split $text]] {
		if {$item eq {--}} {
			incr i
			break
		} elseif {[string index $item 0] eq {-}} {
			switch -glob -nocase -- $item {
				{-e*} { set mode 0 }
				{-g*} { set mode 1 }
				{-r*} { set mode 2 }
			}
			incr i
			continue
		} else {
			break
		}
	}

	if {([set arglen [llength [set arg [lrange $arg $i end]]]] < 1) || ($arglen > 3)} {
		return
	} elseif {$arglen == 3} {
		lassign $arg nick uhost chan
	} elseif {$mode == 2} {
		lassign $arg nick uhost chan
		if {$uhost eq {}} { set uhost {.*} }
		if {$chan eq {}} { set chan {.*} }
	} else {
		set nick {*}
		set uhost {*}
		set chan {*}
		
		set NickDone 0
		set ChanDone 0
		set UhostDone 0
		foreach item $arg {
			# nick
			if {!$NickDone && [regexp -- {^[^#&!+.][^.]*$} $item]} {
				set nick $item
				set NickDone 1
				continue
			# channel
			} elseif {!$ChanDone && [string match {[#&!+]*} $item]} {
				set chan $item
				set ChanDone 1
				continue
			# uhost
			} elseif {!$UhostDone && [string match {*.*} $item]} {
				set uhost $item
				set UhostDone 1
				continue
			}
		}
	}
	return [list $nick $uhost $chan $mode]
}


# output proc
proc ::pixseen::putseen {nick chan notcText {msgText {}}} {
	variable outnotc
	if {$outnotc == 0} {
		puthelp "NOTICE $nick :$notcText"
	} elseif {$msgText != {}} {
		puthelp "PRIVMSG $chan :$msgText"
	} else {
		puthelp "PRIVMSG $chan :$notcText"
	}
}

# Handle public !seen
# !seen [-exact/-glob/-regex] [--] <nick> [user@host] [channel]}
proc ::pixseen::pubm_seen {nick uhost hand chan text} {
	variable defaultLang; variable pubResults
	if {![info exists pubResults] || ![string is integer $pubResults]} { set pubResults {3} }
	if {![channel get $chan {seen}]} {
		return
	} elseif {![matchattr $hand f|f $chan]} {
		if {[checkflood $uhost] != 0} {
			return
		}
	}
	# Set the locale for this channel
	if {[validlang [channel get $chan seenlang]]} { mclocale [channel get $chan seenlang]  }
	if {[set arg [ParseArgs [join [lrange [split $text] 1 end]]]] eq {}} {
		putseen $nick $chan [mc {Usage: %s} {!seen [-exact/-glob/-regex] [--] <nick> [user@host] [channel]}] [mc {%1$s, Usage: %2$s} $nick {!seen [-exact/-glob/-regex] [--] <nick> [user@host] [channel]}]
		mclocale $defaultLang
		return
	} else {
		lassign $arg Nick Uhost Chan Mode
	}
	
	if {[string equal -nocase $nick $Nick]} {
		putseen $nick $chan [mc {Go look in a mirror.}] [mc {%s, go look in a mirror.} $nick]
		mclocale $defaultLang
		return
	} elseif {[string equal -nocase ${::botnick} $Nick]} {
		putseen $nick $chan [mc {You found me!}] [mc {You found me, %s!} $nick]
		mclocale $defaultLang
		return
	# Tcldrop supports glob matching for onchan, so check if Nick is valid first
	} elseif {[validnick $Nick] && [onchan $Nick $chan]} {
		if {[set lastspoke [lastspoke $Nick $chan]] eq {}} {
			putseen $nick $chan [mc {%s is on the channel right now!} $Nick]
		} else {
			putseen $nick $chan [mc {%1$s is on the channel right now! %1$s last spoke %2$s ago.} $Nick $lastspoke]
		}
		mclocale $defaultLang
		return
	}
	
	switch -exact -- $Mode {
		{0} {;# exact
			if {![validnick $Nick]} {
				putseen $nick $chan [mc {That is not a valid nickname.}] [mc {%s, that is not a valid nickname.} $nick]
				mclocale $defaultLang
				return
			} elseif {[set result [dbGetNick $Nick]] eq {}} {
				if {[set handseen [handseen $Nick]] ne {}} {
					putseen $nick $chan $handseen
					mclocale $defaultLang
					return 1
				} else {
					putseen $nick $chan [mc {I don't remember seeing %s.} $Nick]
					mclocale $defaultLang
					return
				}
			} else {
				putseen $nick $chan [formatevent {*}$result]
				mclocale $defaultLang
				return 1
			}
		}
		{1} {;# glob
			set result [dbSearchGlob $Nick $Uhost $Chan]
		}
		{2} {;# regex
			set result [dbSearchRegex $Nick $Uhost $Chan]
		}
	}
	if {$result eq {}} {
		if {[set handseen [handseen $Nick]] ne {}} {
			putseen $nick $chan $handseen
			mclocale $defaultLang
			return 1
		} else {
			putseen $nick $chan [mc {There were no matches to your query.}]
			mclocale $defaultLang
			return
		}
	} else {
		if {[set numMatches [llength $result]] > $pubResults} {
			putseen $nick $chan [mc {Displaying %1$s of %2$s results:} $pubResults $numMatches]
		} else {
			putseen $nick $chan [mc {Displaying %1$s of %2$s results:} $numMatches $numMatches]
		}
		foreach match [lrange $result 0 [expr {$pubResults - 1}]] {
			if {$match ne {}} {
				putseen $nick $chan [formatevent {*}[dbGetNick $match]]
			}
		}
		mclocale $defaultLang
		return 1
	}
	mclocale $defaultLang
	return
}

# Handle /msg botnick seen 
proc ::pixseen::msgm_seen {nick uhost hand text} {
	variable msgResults
	if {![info exists msgResults] || ![string is integer $msgResults]} { set msgResults {5} }
	if {![matchattr $hand f]} {
		if {[checkflood $uhost] != 0} {
			return
		}
	}
	if {[set arg [ParseArgs [join [lrange [split $text] 1 end]]]] eq {}} {
		puthelp "NOTICE $nick :[mc {Usage: %s} {seen [-exact/-glob/-regex] [--] <nick> [user@host] [channel]}]"
		return
	} else {
		lassign $arg Nick Uhost Chan Mode
	}
	if {[string equal -nocase $nick $Nick]} {
		puthelp "NOTICE $nick :[mc {Go look in a mirror.}]"
		return
	} elseif {[string equal -nocase ${::botnick} $Nick]} {
		puthelp "NOTICE $nick :[mc {You found me!}]"
		return
	}
	switch -exact -- $Mode {
		{0} {;# exact
			if {![validnick $Nick]} {
				puthelp "NOTICE $nick :[mc {That is not a valid nickname.}]"
				return
			} elseif {[set result [dbGetNick $Nick]] eq {}} {
				if {[set handseen [handseen $Nick]] ne {}} {
					puthelp "NOTICE $nick :$handseen"
					return 1
				} else {
					puthelp "NOTICE $nick :[mc {I don't remember seeing %s.} $Nick]"
					return
				}
			} else {
				puthelp "NOTICE $nick :[formatevent {*}$result]"
				return 1
			}
		}
		{1} {;# glob
			set result [dbSearchGlob $Nick $Uhost $Chan]
		}
		{2} {;# regex
			set result [dbSearchRegex $Nick $Uhost $Chan]
		}
	}
	if {$result eq {}} {
		if {[set handseen [handseen $Nick]] ne {}} {
			puthelp "NOTICE $nick :$handseen"
			return 1
		} else {
			puthelp "NOTICE $nick :[mc {There were no matches to your query.}]"
			return
		}
	} else {
		if {[set numMatches [llength $result]] > $msgResults} {
			puthelp "NOTICE $nick :[mc {Displaying %1$s of %2$s results:} $msgResults $numMatches]"
		} else {
			puthelp "NOTICE $nick :[mc {Displaying %1$s of %2$s results:} $numMatches $numMatches]"
		}
		foreach match [lrange $result 0 [expr {$msgResults - 1}]] {
			if {$match ne {}} {
				puthelp "NOTICE $nick :[formatevent {*}[dbGetNick $match]]"
			}
		}
		return 1
	}
	return
}

# Handle partyline .seen
proc ::pixseen::dcc_seen {hand idx text} {
	variable dccResults
	if {![info exists dccResults] || ![string is integer $dccResults]} { set dccResults {10} }
	if {[set arg [ParseArgs $text]] eq {}} {
		putdcc $idx [mc {Usage: %s} {.seen [-exact/-glob/-regex] [--] <nick> [user@host] [channel]}]
		return
	} else {
		lassign $arg Nick Uhost Chan Mode
	}
	if {[string equal -nocase $hand $Nick]} {
		putdcc $idx [mc {Go look in a mirror.}]
		return
	} elseif {[string equal -nocase ${::botnick} $Nick]} {
		putdcc $idx [mc {You found me!}]
		return
	}
	switch -exact -- $Mode {
		{0} {;# exact
			if {![validnick $Nick]} {
				putdcc $idx [mc {That is not a valid nickname.}]
				return
			} elseif {[set result [dbGetNick $Nick]] eq {}} {
				if {[set handseen [handseen $Nick]] ne {}} {
					putdcc $idx $handseen
					return 1
				} else {
					putdcc $idx [mc {I don't remember seeing %s.} $Nick]
					return
				}
			} else {
				putdcc $idx [formatevent {*}$result]
				return 1
			}
		}
		{1} {;# glob
			set result [dbSearchGlob $Nick $Uhost $Chan]
		}
		{2} {;# regex
			set result [dbSearchRegex $Nick $Uhost $Chan]
		}
	}
	if {$result eq {}} {
		if {[set handseen [handseen $Nick]] ne {}} {
			putdcc $idx $handseen
			return 1
		} else {
			putdcc $idx [mc {There were no matches to your query.}]
			return
		}
	} else {
		if {[set numMatches [llength $result]] > $dccResults} {
			putdcc $idx [mc {Displaying %1$s of %2$s results:} $dccResults $numMatches]
		} else {
			putdcc $idx [mc {Displaying %1$s of %2$s results:} $numMatches $numMatches]
		}
		foreach match [lrange $result 0 [expr {$dccResults - 1}]] {
			if {$match ne {}} {
				putdcc $idx [formatevent {*}[dbGetNick $match]]
			}
		}
		return 1
	}
	return
}

# verifies table information, return 1 if it's valid, 0 if not
proc ::pixseen::ValidTable {table data} {
	switch -exact -- $table {
		{pixseen} {
			# 0 dbVersion INTEGER 1 {} 0
			lassign $data id name type null default primaryKey
			if {$id != 0 || $name ne {dbVersion} || $type ne {INTEGER} || $null < 1 || $default ne {} || $primaryKey > 0} {
				return 0
			}
		}
		{seenTb} {
			foreach item $data {
				lassign $data id name type null default primaryKey
				switch -exact -- $id {
					{0} {
						# 0 event INTEGER 1 {} 0
						if {$name ne {event} || $type ne {INTEGER} || $null < 1 || $default ne {} || $primaryKey > 0} {
							return 0
						}
					}
					{1} {
						# 1 nick STRING 1 {} 1
						if {$name ne {nick} || $type ne {STRING} || $null < 1 || $default ne {} || $primaryKey < 1} {
							return 0
						}
					}
					{2} {
						# 2 uhost STRING 1 {} 0
						if {$name ne {uhost} || $type ne {STRING} || $null < 1 || $default ne {} || $primaryKey > 0} {
							return 0
						}
					}
					{3} {
						# 3 time INTEGER 1 {} 0
						if {$name ne {time} || $type ne {INTEGER} || $null < 1 || $default ne {} || $primaryKey > 0} {
							return 0
						}
					}
					{4} {
						# 4 chanid INTEGER 0 {} 0
						if {$name ne {chanid} || $type ne {INTEGER} || $null > 0 || $default ne {} || $primaryKey > 0} {
							return 0
						}
					}
					{5} {
						# 5 reason STRING 0 {} 0
						if {$name ne {reason} || $type ne {STRING} || $null > 0 || $default ne {} || $primaryKey > 0} {
							return 0
						}
					}
					{6} {
						# 6 othernick STRING 0 {} 0
						if {$name ne {othernick} || $type ne {STRING} || $null > 0 || $default ne {} || $primaryKey > 0} {
							return 0
						}
					}
					default {
						return 0
					}
				}
				
			}
		}
		{chanTb} {
			foreach item $data {
				lassign $data id name type null default primaryKey
				switch -exact -- $id {
					{0} {
						#0 chanid INTEGER 1 {} 1 
						if {$name ne {chanid} || $type ne {INTEGER} || $null < 1 || $default ne {} || $primaryKey < 1} {
							return 0
						}
					}
					{1} {
						#1 chan STRING 1 {} 0
						if {$name ne {chan} || $type ne {STRING} || $null < 1 || $default ne {} || $primaryKey > 0} {
							return 0
						}
					}
					default {
						return 0
					}
				}
			}
		}
		default {
			return 0
		}
	}
	return 1
}

# Prepare the database on load
proc ::pixseen::LOAD {args} {
	variable dbfile; variable dbVersion
	sqlite3 ::pixseen::seendb $dbfile
	seendb collate IRCRFC ::pixseen::rfccomp
	seendb function chan2id ::pixseen::chan2id
	seendb function regexp ::pixseen::pixregexp
	if {[catch {set result [seendb eval {SELECT tbl_name FROM sqlite_master}]} error]} {
		putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
	} elseif {$result eq {}} {
		# there's no tables defined, so we define some
		putlog [mc {%s: No existing database found, defining SQL schema.} {pixseen.tcl}]
		if {[catch {seendb eval {
			-- Create a table and populate it with a version integer in case we need to change the schema in the future.
			CREATE TABLE pixseen (
				dbVersion INTEGER UNIQUE NOT NULL
			);
			INSERT INTO pixseen VALUES(1);
			
			-- Create the table where all our seen data goes
			CREATE TABLE seenTb (
				event INTEGER NOT NULL,
				nick STRING PRIMARY KEY COLLATE IRCRFC UNIQUE NOT NULL,
				uhost STRING COLLATE NOCASE NOT NULL,
				time INTEGER NOT NULL,
				chanid INTEGER,
				reason STRING COLLATE NOCASE,
				othernick STRING COLLATE IRCRFC
			);
			
			-- Create the table that holds channel IDs and their real names
			CREATE TABLE chanTb (
				chanid INTEGER PRIMARY KEY UNIQUE NOT NULL,
				chan STRING UNIQUE NOT NULL COLLATE IRCRFC
			);
		}} error]} {
			putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
		}
	} else {
		# There's already data in this database, so we verify the schema
		# Verify the table names
		if {[catch { set result [seendb eval { SELECT tbl_name FROM sqlite_master WHERE type='table' ORDER BY tbl_name }] } error]} {
			putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
			die [mc {Fatal Error!}]
		} elseif {[join $result] ne {chanTb pixseen seenTb}} {
			putlog [mc {%1$s: FATAL ERROR; SQLite database corrupt, exiting.} {pixseen.tcl}]
			die [mc {Fatal Error!}]
			
		# Verify the pixseen table
		} elseif {[catch { set result [seendb eval { PRAGMA table_info(pixseen) }] } error]} {
			putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
			die [mc {Fatal Error!}]
		} elseif {![ValidTable {pixseen} $result]} {
			putlog [mc {%1$s: FATAL ERROR; SQLite database corrupt, exiting.} {pixseen.tcl}]
			die [mc {Fatal Error!}]
			
		# Verify the database version
		} elseif {[catch { set result [seendb eval { SELECT dbVersion FROM pixseen LIMIT 1  }] } error]} {
			putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
			die [mc {Fatal Error!}]
		} elseif {$result != $dbVersion} {
			putlog [mc {%1$s: FATAL ERROR; SQLite database corrupt, exiting.} {pixseen.tcl}]
			die [mc {Fatal Error!}]
			
		# Verify the seenTb table
		} elseif {[catch { set result [seendb eval { PRAGMA table_info(seenTb) }] } error]} {
			putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
			die [mc {Fatal Error!}]
		} elseif {![ValidTable {seenTb} $result]} {
			putlog [mc {%1$s: FATAL ERROR; SQLite database corrupt, exiting.} {pixseen.tcl}]
			die [mc {Fatal Error!}]
			
		# Verify the chanTb table
		} elseif {[catch { set result [seendb eval { PRAGMA table_info(chanTb) }] } error]} {
			putlog [mc {%1$s SQL error %2$s; %3$s} {pixseen.tcl} [seendb errorcode] $error]
			die [mc {Fatal Error!}]
		} elseif {![ValidTable {chanTb} $result]} {
			putlog [mc {%1$s: FATAL ERROR; SQLite database corrupt, exiting.} {pixseen.tcl}]
			die [mc {Fatal Error!}]
			
		# Everything is OK!
		}  else {
			# Do some database maintenance
			dbCleanup
			putlog [mc {%s: Loaded the seen database.} {pixseen.tcl}]
		}
	}
	return
}

proc ::pixseen::UNLOAD {args} {
	seendb close
	putlog [mc {%s: Unloaded the seen database.} {pixseen.tcl}]
	return
}

# We have to verify the password here to make sure that the die is successful
proc ::pixseen::msg_die {cmdString op} {
	set hand [lindex $cmdString 3]
	set pass [lindex $cmdString 4 0]
	if {[passwdok $hand $pass]} {
		UNLOAD
	}
	return
}

# chanset wrapper
# checks the language people set and complains if it's not supported.
proc ::pixseen::dcc_chanset {hand idx param} {
	set chan [lindex [set arg [split $param]] 0]
	if {![validchan $chan]} {
		*DCC:CHANSET $hand $idx $param
		return
	}
	set settings [lrange $arg 1 end]
	set found 0
	foreach setting $settings {
		if {$found} {
			set lang $setting
		} elseif {[string equal -nocase $setting {seenlang}]} {
			set found 1
		}
	}
	if {[info exists lang] && ![validlang $lang]} {
		putdcc $idx [mc {Error: Invalid seen language "%s".} $lang]
		return
	} else {
		*DCC:CHANSET $hand $idx $param
		return
	}
}

# This proc will be renamed to ::*dcc:chanset on load. We call out real
# wrapper from here so that it can stay in the correct namespace
proc ::pixseen::*dcc:chanset {hand idx param} {
	::pixseen::dcc_chanset $hand $idx $param
}

namespace eval ::pixseen {
	# trace die so that we can unload the database properly before the bot exist
	if {![info exists SetTraces]} {
		trace add execution die enter ::pixseen::UNLOAD
		# don't try to trace these on Tcldrop
		if {![info exists ::tcldrop]} {
			trace add execution *dcc:die enter ::pixseen::UNLOAD
			trace add execution *msg:die enter ::pixseen::msg_die
			# wrap chanset so we can validate the language people set
			# FixMe: add Tcldrop equivalent
			rename ::*dcc:chanset ::*DCC:CHANSET
			rename ::pixseen::*dcc:chanset ::*dcc:chanset
		}
		variable SetTraces 1
	}
	# load the database if it's not already loaded
	if {[info procs seendb] ne {seendb}} { ::pixseen::LOAD }
	# unload the database on rehash & restart
	bind evnt - {prerehash} ::pixseen::UNLOAD
	bind evnt - {prerestart} ::pixseen::UNLOAD
	# seen tracking events
	bind part - "*" ::pixseen::PART
	bind join - "*" ::pixseen::JOIN
	bind nick - "*" ::pixseen::NICK
	bind sign - "*" ::pixseen::SIGN
	bind splt - "*" ::pixseen::SPLT
	bind rejn - "*" ::pixseen::REJN
	bind kick - "*" ::pixseen::KICK
	bind chon - "*" ::pixseen::CHON
	bind chof - "*" ::pixseen::CHOF
	bind chjn - "*" ::pixseen::CHJN
	bind chpt - "*" ::pixseen::CHPT
	bind away - "*" ::pixseen::AWAY
	# triggers
	bind pubm - {% ?seen *} ::pixseen::pubm_seen
	bind pubm - {% seen *} ::pixseen::pubm_seen
	bind pubm - {% ?seen} ::pixseen::pubm_seen
	bind msgm - {seen *} ::pixseen::msgm_seen
	bind dcc - {seen} ::pixseen::dcc_seen
	# flood-array cleanup every 10 minutes
	bind time - "?0 * * * *" ::pixseen::RemoveFlood
	# do some database maintenance once daily
	bind evnt - {logfile} ::pixseen::dbCleanup
	putlog [mc {Loaded %1$s v%2$s by %3$s} {pixseen.tcl} $seenver {Pixelz}]
}
