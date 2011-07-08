# substitute.tcl -- 1.0
#
#     This script provides sed style text subsitution, with full regular
#     expression support. Use ".chanset #chan +substitute" to enable the
#     script in a channel.
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
###Tags
# Name: substitute
# Author: Pixelz <rutgren@gmail.com>
# License: http://www.opensource.org/licenses/ISC ISC license
# Labels: substitute, substitution, text, sed, regex
# Updated: 02-May-2010
# RCS: $Id$
#
###Usage
# Basic usage
# <nick> Hello, World!
# <nick> s/World/Everyone
# <bot> Nick meant: "Hello, Everyone!"
#
# With : instead of /
# <nick> Hello, World!
# <nick> s:World:Everyone
# <bot> Nick meant: "Hello, Everyone!"
#
# <nick> Hello, World!
# <nick> s/,/
# <bot> Nick meant: "Hello World!"
#
# Substitutions can be stacked indefinately
# <nick> Hello, World!
# <nick> s/l/w/s/o/u
# <bot> Nick meant: "Hewwu, Wurwd!"
#
# You can keep stacking over multiple messages
# <nick> Hello, World!
# <nick> s/World/Everyone
# <bot> Nick meant: "Hello, Everyone!"
# <nick> s/Everyone/Friday
# <bot> Nick meant: "Hello, Friday!"
#
# Regular expression
# <nick> Hello, World!
# <nick> s/[A-Z]/Y
# <bot> Nick meant: "Yello, Yorld!"
#
# More regular expression
# <nick> Hello, World!
# <nick> s/\S/x
# <bot> Nick meant: "xxxxxx xxxxxx"
#
# Metasyntax in action, turning on case insensitive matching:
# <nick> Aaa Bbb
# <nick> s/(?i)a/x/s/(?i)b/y
# <bot> Nick meant: "xxx yyy"
#
# Substitution guru:
# <nick> :p
# <nick> s/:/abc/s/p/defg/s/[ce]/^/s/d/o/s/a/\/s:g:/:s/b/(/s/f/)
# <bot> Nick meant: "\(^o^)/"
#
###Notes
# Flags (i.e. global, case-insensitive) aren't supported directly in the syntax,
# however Tcl metasyntax can still be used. Expressions default to global/all,
# case-sensitive. Note that it's not possible to turn on or off global matching
# via metasyntax, this is because of a limitation in Tcl.

package require Tcl 8.4
package require eggdrop 1.6

namespace eval ::substitute {
	# minimum time in seconds before spoken lines are allowed to expire
	variable dbExpire 600 ;# 10 minutes
	setudef flag {substitute}
	variable lastLine
}

proc ::substitute::pubm_substitute {nick uhost hand chan text} {
	variable lastLine
	if {![channel get $chan {substitute}]} {
		return
	} elseif {[string match {s[/:]*[/:]*} $text]} {
		if {[info exists lastLine([set lnick [string tolower $nick]],$chan)]} {
			set newLine [set last [lindex $lastLine($lnick,$chan) 1]]
			foreach {- a b c d} [regexp -all -inline -- {s(?:/([^/]+)/([^/]*)|:([^:]+):([^:]*))} $text] {
				if {$a ne {}} {
					catch {set newLine [regsub -all -- $a $newLine $b]}
				} else {
					catch {set newLine [regsub -all -- $c $newLine $d]}
				}
			}
			if {($newLine ne $last) && ([string length $newLine] <= 400)} {
				putserv "PRIVMSG $chan :$nick meant: \"$newLine\""
				set lastLine($lnick,$chan) [list [clock seconds] $newLine]
				return
			}
		}
	} else {
		set lastLine([string tolower $nick],$chan) [list [clock seconds] $text]
		return
	}
	return
}

proc ::substitute::dbCleanup {args} {
	variable lastLine; variable dbExpire
	foreach item [array names lastLine] {
		if {([clock seconds] - [lindex $lastLine($item) 0]) > $dbExpire} {
			unset lastLine($item)
		}
	}
	return
}

namespace eval ::substitute {
	bind pubm - "*" ::substitute::pubm_substitute
	bind time - "?0 * * * *" ::substitute::dbCleanup
	putlog "Loaded substitute.tcl v1.0 by Pixelz"
}
