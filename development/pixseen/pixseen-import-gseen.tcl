#! /bin/sh
# \
# Edit & comment out the line below to override the auto-detect. The \ at the end HAS TO BE THERE! \
#override=$HOME/local/bin/tclsh8.5 \
# \
# Nice little hack to find latest version of tclsh in PATH \
# Parts of this detection script is written by Tothwolf \
# \
# NOTE: backslash and semicolon placements are important! \
# \
# ToDo: Get rid of 'grep -o', 'find' \
# \
# Check if override is specified: \
if [ -n "$override" ]; \
then \
  echo "Auto-detect overridden. Using tclsh in $override"; \
  exec $override "$0" ${1+"$@"}; \
fi; \
# Check for working 'grep -E' before using 'egrep' \
if echo a | (grep -E '(a|b)') >/dev/null 2>&1; \
then \
  egrep="grep -E"; \
else \
  egrep=egrep; \
fi; \
# Search for tclsh[0-9].[0-9] in each valid dir in PATH and some other common paths \
for dir in `echo $PATH:$HOME/local/bin:$HOME/bin | sed 's/:/ /g'`; \
do \
  if test -d $dir; \
  then \
    files=`find $dir 2> /dev/null | $egrep '.*/tclsh[0-9]\.[0-9]$'`; \
    if test "$files" != ""; \
    then \
      versions="${versions:+$versions }`echo $files`"; \
    fi; \
  fi; \
done; \
# Loop over each version to find the latest version of tclsh \
for fullpath in $versions; \
do \
  ver=`echo $fullpath | grep -o '[0-9]\.[0-9]$'`; \
  tmpver=`echo $ver | sed 's/\.//g'`; \
  if test "$lasttmpver" != ""; \
  then \
    if test "$tmpver" -gt "$lasttmpver"; \
    then \
      lastver=$ver; \
      lasttmpver=$tmpver; \
      lastfullpath=$fullpath; \
    fi; \
    # Prefer installs in a users home dir if we find multiple copies of tclsh with the same version \
    if test "$tmpver" = "$lasttmpver"; \
    then \
      if test "`echo $fullpath |grep -o ^$HOME`" = "$HOME"; \
      then \
        lastver=$ver; \
        lasttmpver=$tmpver; \
        lastfullpath=$fullpath; \
      fi; \
    fi; \
  else \
    lastver=$ver; \
    lasttmpver=$tmpver; \
    lastfullpath=$fullpath; \
  fi; \
done; \
# Use the latest tclsh version found, otherwise fall back to 'tclsh' \
echo "Using tclsh auto-detected in $lastfullpath"; \
exec $lastfullpath "$0" ${1+"$@"}

# pixseen-import-gseen.tcl --
#
#       This shell script imports a gseen database to pixseen.tcl.
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
# v1.0 by Pixelz - April 5, 2010

package require Tcl 8.5
package require sqlite3

namespace eval ::pixseen {
	
	# path to the database file
	variable dbfile {pixseen.db}
	
	## END OF SETTINGS ##
	variable dbVersion 1
}

if {$argv eq {}} {
	puts "Usage: $argv0 <path/to/gseen.dat>"
	exit
}
if {![file exists $argv]} {
	puts "No such file: $argv"
	exit
}

# Check if we're being sourced from eggdrop.
if {[info exists ::version]} {
	putlog "ERROR! Detected pixseen-import-gseen.tcl being loaded from Eggdrop. This script is meant to be run as a shell script."
	die "PEBKAC detected"
}

## SQL functions
proc ::pixseen::rfccomp {a b} {
	string compare [string map [list \{ \[ \} \] ~ ^ | \\] [string toupper $a]] [string map [list \{ \[ \} \] ~ ^ | \\] [string toupper $b]]
}

proc ::pixseen::chan2id {chan} {
	if {[catch {seendb eval { INSERT OR IGNORE INTO chanTb VALUES(NULL, $chan); }} error]} {
		puts stdout "SQL error [seendb errorcode]; $error"
		exit
	}
	if {[catch {set retval [seendb eval { SELECT chanid FROM chanTb WHERE chan=$chan LIMIT 1 }]} error]} {
		puts stdout "SQL error [seendb errorcode]; $error"
		exit
	} else {
		return $retval
	}
}

##

# verifies table information, return 1 if it's valid, 0 if not
proc ::pixseen::ValidTable {table data} {
	switch -exact -- $table {
		{pixseen} {
			if {[join $data] eq {0 dbVersion INTEGER 1  0}} {
				return 1
			} else {
				return 0
			}
		}
		{seenTb} {
			if {[join $data] eq {0 event INTEGER 1  0 1 nick STRING 1  1 2 uhost STRING 1  0 3 time INTEGER 1  0 4 chanid INTEGER 0  0 5 reason STRING 0  0 6 othernick STRING 0  0}} {
				return 1
			} else {
				return 0
			}
		}
		{chanTb} {
			if {[join $data] eq {0 chanid INTEGER 1  1 1 chan STRING 1  0}} {
				return 1
			} else {
				return 0
			}
		}
		default {
			return 0
		}
	}
}

namespace eval ::pixseen {

	# initialize the db interface
	sqlite3 ::pixseen::seendb $dbfile
	
	seendb collate IRCRFC ::pixseen::rfccomp
	seendb function chan2id ::pixseen::chan2id
	if {[catch {set result [seendb eval {SELECT tbl_name FROM sqlite_master}]} error]} {
		puts stdout "SQL error [seendb errorcode]; $error"
		exit
	} elseif {$result eq {}} {
		# there's no tables defined, so we define some
		puts stdout "No existing database found, defining SQL schema."
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
			puts stdout "SQL error [seendb errorcode]; $error"
			exit
		}
	} else {
		# There's already data in this database, so we verify the schema
		# Verify the table names
		if {[catch { set result [seendb eval { SELECT tbl_name FROM sqlite_master WHERE type='table' ORDER BY tbl_name }] } error]} {
			puts stdout "SQL error [seendb errorcode]; $error"
			exit
		} elseif {[join $result] ne {chanTb pixseen seenTb}} {
			puts stdout "SQL database corrupt, exiting."
			exit
			
		# Verify the pixseen table
		} elseif {[catch { set result [seendb eval { PRAGMA table_info(pixseen) }] } error]} {
			puts stdout "SQL error [seendb errorcode]; $error"
			exit
		} elseif {![ValidTable {pixseen} $result]} {
			puts stdout "SQL database corrupt, exiting."
			exit
			
		# Verify the database version
		} elseif {[catch { set result [seendb eval { SELECT dbVersion FROM pixseen LIMIT 1  }] } error]} {
			puts stdout "SQL error [seendb errorcode]; $error"
			exit
		} elseif {$result != $dbVersion} {
			puts stdout "SQL database corrupt, exiting."
			exit
			
		# Verify the seenTb table
		} elseif {[catch { set result [seendb eval { PRAGMA table_info(seenTb) }] } error]} {
			puts stdout "SQL error [seendb errorcode]; $error"
			exit
		} elseif {![ValidTable {seenTb} $result]} {
			puts stdout "SQL database corrupt, exiting."
			exit
			
		# Verify the chanTb table
		} elseif {[catch { set result [seendb eval { PRAGMA table_info(chanTb) }] } error]} {
			puts stdout "SQL error [seendb errorcode]; $error"
			exit
		} elseif {![ValidTable {chanTb} $result]} {
			puts stdout "SQL database corrupt, exiting."
			exit
			
		# Everything is OK!
		}  else {
			puts stdout "Loaded an existing database."
		}
	}
	
	#define SEEN_JOIN 1
	#define SEEN_PART 2
	#define SEEN_SIGN 3
	#define SEEN_NICK 4
	#define SEEN_NCKF 5
	#define SEEN_KICK 6
	#define SEEN_SPLT 7
	#define SEEN_REJN 8
	#define SEEN_CHPT 9
	#define SEEN_CHJN 10
	
	#nick = newsplit(&s);
	#host = newsplit(&s);
	#chan = newsplit(&s);
	#iType = atoi(newsplit(&s));
	#when = (time_t) atoi(newsplit(&s));
	#spent = atoi(newsplit(&s));
	#msg = s;
	
	set fd [open $argv r]
	set events {}
	seendb eval { BEGIN TRANSACTION }
	while {![eof $fd]} {
		set line [gets $fd]
		if {[string index $line 0] ne {!}} { continue }
		lassign [set sline [split $line]] - nick uhost chan event timestamp spent
		set msg [lrange $sline  7 end]
		switch -exact -- $event {
			{1} {;# join
				if {[catch {seendb eval { INSERT OR REPLACE INTO seenTb VALUES(1, $nick, $uhost, $timestamp, chan2id($chan), NULL, NULL) }} error]} {
					puts stdout "SQL error: [seendb errorcode] $error"
					exit
				}
			}
			{2} {;# part
				if {[catch {seendb eval { INSERT OR REPLACE INTO seenTb VALUES(0, $nick, $uhost, $timestamp, chan2id($chan), $msg, NULL) }} error]} {
					puts stdout "SQL error: [seendb errorcode] $error"
					exit
				}
			}
			{3} {;# sign
				if {[catch {seendb eval { INSERT OR REPLACE INTO seenTb VALUES(4, $nick, $uhost, $timestamp, chan2id($chan), $msg, NULL) }} error]} {
					puts stdout "SQL error: [seendb errorcode] $error"
					exit
				}
			}
			{4} {;# nick
				if {[catch {seendb eval { INSERT OR REPLACE INTO seenTb VALUES(2, $nick, $uhost, $timestamp, chan2id($chan), NULL, $msg) }} error]} {
					puts stdout "SQL error: [seendb errorcode] $error"
					exit
				}
			}
			{5} {;# nckf
				if {[catch {seendb eval { INSERT OR REPLACE INTO seenTb VALUES(3, $nick, $uhost, $timestamp, chan2id($chan), NULL, $msg) }} error]} {
					puts stdout "SQL error: [seendb errorcode] $error"
					exit
				}
			}
			{6} {;# kick
				set aggressor [lindex $sline 7]
				set msg [lrange $sline 8 end]
				if {[catch {seendb eval { INSERT OR REPLACE INTO seenTb VALUES(7, $nick, $uhost, $timestamp, chan2id($chan), $msg, $aggressor) }} error]} {
					puts stdout "SQL error: [seendb errorcode] $error"
					exit
				}
			}
			{7} {;# splt
				if {[catch {seendb eval { INSERT OR REPLACE INTO seenTb VALUES(5, $nick, $uhost, $timestamp, chan2id($chan), NULL, NULL) }} error]} {
					puts stdout "SQL error: [seendb errorcode] $error"
					exit
				}
			}
			{8} {;# rejn
				if {[catch {seendb eval { INSERT OR REPLACE INTO seenTb VALUES(6, $nick, $uhost, $timestamp, chan2id($chan), NULL, NULL) }} error]} {
					puts stdout "SQL error: [seendb errorcode] $error"
					exit
				}
			}
			{9} {;# chpt
				if {[catch {seendb eval { INSERT OR REPLACE INTO seenTb VALUES(11, $nick, $uhost, $timestamp, chan2id($chan), NULL, $msg) }} error]} {
					puts stdout "SQL error: [seendb errorcode] $error"
					exit
				}
			}
			{10} {;# chjn
				if {[catch {seendb eval { INSERT OR REPLACE INTO seenTb VALUES(10, $nick, $uhost, $timestamp, chan2id($chan), NULL, $msg) }} error]} {
					puts stdout "SQL error: [seendb errorcode] $error"
					exit
				}
			}
			default {
				puts stdout "UNHANDLED EVENT: $event"
				exit
			}
		}
	}
	seendb eval { COMMIT }
	close $fd
	seendb close
}
