# qchallengeauth.tcl --
#
#     This script authenticates to Q with challenge authentication, using
#     HMAC-SHA-256, HMAC-SHA-1 or HMAC-MD5.
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
# v0.1 by Pixelz (rutgren@gmail.com), October 19, 2010
#
# Features:
#	- Supports authentication using HMAC-SHA-256, HMAC-SHA-1 and HMAC-MD5.
#	- Prevents Eggdrop from joining any channels until authentication is complete.
#	- Changes to a random nick on connect and prevents Eggdrop to change back to it's main or alt nick until authentication is complete.
#	- Hides annoying Q replies from the the partyline and logs.
#	- Overrides the internal connect logic to some degree to speed it up.
#
# Maybe add:
#	- Join channels after a set time if we can't auth
#		- track Q joining a channel and auth if we're not authed
#	- Don't load all encryption packages at init, instead load others later if needed
#		- Rewrite self with a working hash package priority
#	- Rewrite self with hashed password/auth
#	- Better retry-auth logic, perhaps using ISON?

package require eggdrop 1.6.20
package require Tcl 8.5

namespace eval ::qchallengeauth {
	variable settings
	
	### SETTINGS ###
	
	# The bots Q auth name
	set settings(auth) {LamestBot}
	# The bots Q password
	set settings(pass) {LamestPass}
	# User modes to set on connect
	set settings(umodes) {+ix-w}
	
	# You probably don't need to change these:
	# Q's nick
	set settings(nick) {Q}
	# Q's ident@host
	set settings(uhost) {TheQBot@CServe.quakenet.org}
	# Q's host used to msg it
	set settings(msghost) {Q@CServe.quakenet.org}
	
	
	### END OF SETTINGS ###
}

proc ::qchallengeauth::rfclower {string} {
	return [string map [list \[ \{ \] \} ^ ~ \\ |] [string tolower $string]]
}

proc ::qchallengeauth::rfcequal {string1 string2} {
	if {[rfclower $string1] eq [rfclower $string2]} {
		return 1
	} else {
		return 0
	}
}

proc ::qchallengeauth::NOTC_CHALL {nick uhost hand text dest} {
	variable settings; variable haveSha256; variable haveSha1; variable haveMd5; variable timer
	if {![rfcequal $dest $::botnick]} {
		return
	} elseif {![rfcequal $nick $settings(nick)] || ![string equal -nocase $uhost $settings(uhost)]} {
		return
	} elseif {![regexp -- {CHALLENGE ([0-9a-f]{32}) (.+)} $text - challenge algoritms]} {
		return
	} else {
		# http://www.quakenet.org/development/challengeauth/
		# key = HASH("<username>:" + HASH("<password>"))
		# response = HMAC-HASH(data){key}
		if {[lsearch -exact [split $algoritms] {HMAC-SHA-256}] != -1 && $haveSha256} {
			putquick "PRIVMSG $settings(msghost) :CHALLENGEAUTH $settings(auth) [::sha2::hmac -hex -key [::sha2::sha256 -hex [rfclower $settings(auth)]:[::sha2::sha256 -hex [string range $settings(pass) 0 9]]] $challenge] HMAC-SHA-256"
			putlog "Authed to $settings(nick) using HMAC-SHA-256"
			return 1
		} elseif {[lsearch -exact [split $algoritms] {HMAC-SHA-1}] != -1 && $haveSha1} {
			putquick "PRIVMSG $settings(msghost) :CHALLENGEAUTH $settings(auth) [::sha1::hmac -hex -key [::sha1::sha1 -hex [rfclower $settings(auth)]:[::sha1::sha1 -hex [string range $settings(pass) 0 9]]] $challenge] HMAC-SHA-1"
			putlog "Authed to $settings(nick) using HMAC-SHA-1"
			return 1
		} elseif {[lsearch -exact [split $algoritms] {HMAC-MD5}] != -1 && $haveMd5} {
			putquick "PRIVMSG $settings(msghost) :CHALLENGEAUTH $settings(auth) [::md5::hmac -hex -key [::md5::md5 -hex [rfclower $settings(auth)]:[::md5::md5 -hex [string range $settings(pass) 0 9]]] $challenge] HMAC-SHA-MD5"
			putlog "Authed to $settings(nick) using HMAC-MD5"
			return 1
		} else {
			if {[info exists timer] && [lsearch -index 2 [timers] $timer]} { killtimer $timer }
			if {$haveSha256} { lappend supportedAlgoritms {HMAC-SHA-256} } else { lappend unSupportedAlgoritms {HMAC-SHA-256} }
			if {$haveSha1} { lappend supportedAlgoritms {HMAC-SHA-1} } else { lappend unSupportedAlgoritms {HMAC-SHA-1} }
			if {$haveMd5} { lappend supportedAlgoritms {HMAC-MD5} } else { lappend unSupportedAlgoritms {HMAC-MD5} }
			putlog "qchallengeauth.tcl: No usable hash algoritm recieved from $settings(qnick). It sent me: $algoritms."
			if {[info exists supportedAlgoritms]} { putlog "qchallengeauth.tcl: I currently have the nessesary packages loaded to support: [join $supportedAlgoritms {,}]" }
			if {[info exists unSupportedAlgoritms]} {
				putlog "qchallengeauth.tcl: I currently don't have the nessesary packages to support: [join $supportedAlgoritms {,}]"
				if {!$haveSha256 && [lsearch -exact [split $algoritms] {HMAC-SHA-256}] != -1} { putlog "qchallengeauth.tcl: If you installed version 1.0.2 or above of the sha256 package from tcllib I could support HMAC-SHA-256." }
				if {!$haveSha1 && [lsearch -exact [split $algoritms] {HMAC-SHA-1}] != -1} { putlog "qchallengeauth.tcl: If you installed version 2.0.3 or above of the sha1 package from tcllib I could support HMAC-SHA-1." }
				if {!$haveMd5 && [lsearch -exact [split $algoritms] {HMAC-MD5}] != -1} { putlog "qchallengeauth.tcl: If you installed version 2.0.7 or above of the md5 package from tcllib I could support HMAC-MD5." }
				if {[lsearch -exact [split $algoritms] {LEGACY-MD5}] != -1} { putlog "qchallengeauth.tcl: There is no support for LEGACY-MD5, because of its outdated nature." }
			}
			return
		}
	}
}

proc ::qchallengeauth::NOTC_TRACK {nick uhost hand text dest} {
	variable settings; variable authed
	if {![rfcequal $dest $::botnick]} {
		return
	} elseif {![rfcequal $nick $settings(nick)] || ![string equal -nocase $uhost $settings(uhost)]} {
		return
	} else {
		switch -glob -nocase -- $text {
			{You are now logged in as *.} -
			{CHALLENGE is not available once you have authed.} {
				set authed 1
				if {![rfcequal $::botnick $::nick]} {
					# Note: this has to be in the server queue, because eggdrop sends a WHOIS for itself using that queue.
					# If this is sent before that, the whois will fail, possibly causing Bad Things to happen
					putserv "NICK $::nick"
					foreach chan [channels] {
						if {![channel get $chan inactive]} {
							lappend chans $chan
						}
					}
					if {[info exists chans]} {
						putserv "JOIN [join $chans ,]"
					}
				}
				return 1
			}
			default { return 1 }
		}
	}
}

proc ::qchallengeauth::OUT {queue message status} {
	variable authed
	if {$authed} {
		return
	} elseif {$status ne {queued}} {
		return
	} elseif {[string equal -nocase [set cmd [lindex [split $message] 0]] {JOIN}]} {
		return 1
	} elseif {[string equal -nocase $cmd {NICK}] && $queue ne {noqueue}} {
		putnow "NICK [subst [string repeat {[format %c [expr {int(rand() * 26) + (int(rand() * 10) > 5 ? 97 : 65)}]]} 9]]"
		return 1
	}
}

proc ::qchallengeauth::EVNT {type} {
	variable authed; variable settings; variable timer
	switch -exact -- $type {
		connect-server - disconnect-server {
			set authed 0
			return
		}
		init-server {
			if {[info exists settings(umodes)] && $settings(umodes) ne {}} {
				putquick "MODE $::botnick $settings(umodes)"
			}
			putquick "PRIVMSG $settings(msghost) :CHALLENGE"
			set timer [timer 1 [list ::qchallengeauth::retryAuth]]
			return
		}
		default { return }
	}
}

proc ::qchallengeauth::nickInUse {from keyword text} {
	variable authed
	if {$keyword ne {433}} {
		return
	} elseif {[rfcequal [set currNick [lindex [split $text] 1]] $::nick]} {
		return
	} elseif {[rfcequal $currNick [regsub -all -- {[0-9]} $::altnick {?}]]} {
		return
	} else {
		set alt $::altnick
		while {[string first ? $alt] != -1} {
			regsub -- {\?} $alt [expr {int(rand() * 10)}] alt
		}
		putquick "NICK $alt"
	}
}

proc ::qchallengeauth::retryAuth {} {
	variable authed; variable settings; variable timer
	if {!$authed} {
		putquick "PRIVMSG $settings(msghost) :CHALLENGE"
		set timer [timer 1 [list ::qchallengeauth::retryAuth]]
	}
}

proc ::qchallengeauth::INIT {} {
	variable settings; variable haveSha256; variable haveSha1; variable haveMd5; variable authed
	
	# I thought about not loading all of these but I decided that memory is cheap so to hell with it.
	if {![catch {package require sha256 1.0.2}]} { set haveSha256 1 } else { set haveSha256 0 }
	if {![catch {package require sha1 2.0.3}]} { set haveSha1 1 } else { set haveSha1 0 }
	if {![catch {package require md5 2.0.7}]} { set haveMd5 1 } else { set haveMd5 0 }
	if {!$haveSha256 && !$haveSha1 && !$haveMd5} {
		putlog "qchallengeauth.tcl: Unable to find an HMAC capable hash package. Please install the latest version of tcllib."
		putlog "qchallengeauth.tcl was NOT loaded."
		namespace forget ::qchallengeauth
		return
	} else {
		if {![info exists authed]} {
			set authed 0
			if {${::server-online} > 0} {
				putquick "PRIVMSG $settings(msghost) :CHALLENGE"
			}
		}
	
		bind notc - {CHALLENGE *} ::qchallengeauth::NOTC_CHALL
		bind notc - {*} ::qchallengeauth::NOTC_TRACK
		bind out - {% queued} ::qchallengeauth::OUT
		bind evnt - {init-server} ::qchallengeauth::EVNT
		bind evnt - {connect-server} ::qchallengeauth::EVNT
		bind evnt - {disconnect-server} ::qchallengeauth::EVNT
		bind raw - 433 ::qchallengeauth::nickInUse
		
		putlog {Loaded qchallengeauth.tcl v0.1 by Pixelz}
	}
}

namespace eval ::qchallengeauth {
	INIT
}
