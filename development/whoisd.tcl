# whoisd.tcl -- 1.2
#
#   The whois command checks if a given domain is available or taken.
#   The tld command returns which country sponsors the given tld.
#   This script uses live servers so it is never outdated, unlike other scripts.
#
#   I have tried a lot of existing domain whois scripts, none of them did what I wanted.
#   So I decided to write my own, based on a similar script I wrote for mIRC.
#
#   It is purposely made to be simple so it did not require much maintenance.
#
# Copyright (c) 2010 HM2K
#
# Name: domain whois and tld country code lookup (!whois and !tld)
# Author: HM2K <irc@hm2k.org>
# License: http://www.opensource.org/licenses/bsd-license.php BSD License
# Link: http://www.hm2k.com/projects/eggtcl
# Labels: whois, lookup, domains, tld, country
# Updated: 29-Jul-2010
#
###Usage
# .whois is the default public channel trigger for the whois function
# .whoisd is the default dcc command trigger the whois function
# .tld is the default public channel trigger for the tld function
# .tld is the default dcc trigger for the tld function
#
###Example
# > .whois hm2k.com
# <Bot> whois: hm2k.com is taken!
# > .whois example-lame-domain.com
# <Bot> whois: example-lame-domain.com is available!
# > .tld uk
# <Bot> whois: Country for uk is United Kingdom
#
###Credits
# Thanks #eggtcl @ EFnet for some pointers
#
###Revisions
# 1.2   - better tld country detection and fixed default commands
# 1.1   - iana changed their whois response; the whole script was revamped
# 1.0.3 - better documentation; fixed trigger; fixed timeouts; fixed available match
# 1.0.2 - further imrovements were made
# 1.0.1 - first public release

### Settings
set whoisd(cmd_dcc_domain) "whoisd"; #the dcc command - eg: .whoisd <domain>
set whoisd(cmd_dcc_tld) "tld"; #the dcc tld command - eg: .tld <tld>
set whoisd(cmd_pub_domain) ".whois"; #the pub command - eg: .whois <domain>
set whoisd(cmd_pub_tld) ".tld"; #the pub tld command - eg: .tld <tld>
set whoisd(data_country) "";#place holder for country data
set whoisd(data_type) "domain"; #default data type
set whoisd(debug) 1; #turn debug on or off
set whoisd(error_connect) "Error: Connection to %s:%s failed."; #Connection failed
set whoisd(error_connect_lost) "Error: Connection to server has been lost.";
set whoisd(error_invalid) "Error: Invalid %s."; #Invalid domain/tld error
set whoisd(flag) "-|-"; #flag required to use the script
set whoisd(nomatch_domain) "No match|not found|Invalid query|does not exist|no data found|status:         avail|domain is available|(null)|no entries found|not registered|no objects found|domain name is not|Status:.*AVAILABLE"; #Replies from Whois Servers that match as "Available"... #TODO: split into new lines, join again later
set whoisd(nomatch_tld) "This query returned 0 objects."; #Error returned for invalid tld
set whoisd(notice_connect) "Connecting to... %s:%s (%s)"; #Connecting notice
set whoisd(output_country) "Country for %s is %s";
set whoisd(output_found) "%s is available!";
set whoisd(output_nomatch) "%s is taken!";
set whoisd(output_timeout) "Connection to %s:%s timed out within %s seconds.";
set whoisd(port) 43; #The default whois server port - should not change
set whoisd(prefix) "whois:"; #prefix on output
set whoisd(regex_country) {address.*?:\s*(.+)$};
set whoisd(regex_contact) {contact.*?:\s*(.+)$};
set whoisd(regex_server) {whois.*?:\s*(.+)$};
set whoisd(regex_valid_domain) {^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,6}$}; #Regular expression used for validating domains
set whoisd(regex_valid_tld) {^\.?[a-z]+$};
set whoisd(rplmode) 1; #reply mode (1:chan privmsg, 2:chan notice, 3:nick privmsg, 4:nick notice)
set whoisd(server) "whois.iana.org"; #The main whois server - should not change
set whoisd(timeout) 15; #server timeout in seconds - servers are quick, keep low 
set whoisd(usage) "Usage: %s <%s>"; #Usage
set whoisd(ver) "1.1"; # version

### Package Definition
package require eggdrop 1.6;  #see http://geteggdrop.com/
package require Tcl 8.2.3;    #see http://tinyurl.com/6kvu2n

### Binds
bind dcc $whoisd(flag) $whoisd(cmd_dcc_domain) whoisd:dcc_domain;
bind pub $whoisd(flag) $whoisd(cmd_pub_domain) whoisd:pub_domain;
bind dcc $whoisd(flag) $whoisd(cmd_dcc_tld) whoisd:dcc_tld;
bind pub $whoisd(flag) $whoisd(cmd_pub_tld) whoisd:pub_tld;

### Procedures
proc whoisd:validate {cmd word} {
	if {[string compare $word ""] == 0} {
    return [format $::whoisd(usage) $cmd $::whoisd(data_type)];    
  }
	if {![regexp $::whoisd(regex_valid) $word]} {
    return [format $::whoisd(error_invalid) $::whoisd(data_type)];
  }
  return;
}
proc whoisd:dcc_domain {hand idx text} {
  set ::whoisd(data_type) "domain";
  set ::whoisd(cmd_dcc) $::whoisd(cmd_dcc_domain);
  set ::whoisd(regex_valid) $::whoisd(regex_valid_domain);
	return [whoisd:dcc $hand $idx $text];
}
proc whoisd:pub_domain {nick uhost hand chan text} {
  set ::whoisd(data_type) "domain";
  set ::whoisd(cmd_pub) $::whoisd(cmd_pub_domain);
  set ::whoisd(regex_valid) $::whoisd(regex_valid_domain);
	return [whoisd:pub $nick $uhost $hand $chan $text];
}
proc whoisd:dcc_tld {hand idx text} {
  set ::whoisd(data_type) "tld";
  set ::whoisd(cmd_dcc) $::whoisd(cmd_dcc_tld);
  set ::whoisd(regex_valid) $::whoisd(regex_valid_tld);
	return [whoisd:dcc $hand $idx $text];
}
proc whoisd:pub_tld {nick uhost hand chan text} {
  set ::whoisd(data_type) "tld";
  set ::whoisd(cmd_pub) $::whoisd(cmd_pub_tld);
  set ::whoisd(regex_valid) $::whoisd(regex_valid_tld);
  return [whoisd:pub $nick $uhost $hand $chan $text];
}
proc whoisd:dcc {hand idx text} {
  set word [lrange [split $text] 0 0];
  if {[set invalid [whoisd:validate ".$::whoisd(cmd_dcc)" $word]] != ""} {
    whoisd:out 0 $idx {} $invalid;
    return;
  }
	whoisd:connect 0 $idx {} $::whoisd(server) $::whoisd(port) $word;
}
proc whoisd:pub {nick uhost hand chan text} {
  set word [lrange [split $text] 0 0];
  if {[set invalid [whoisd:validate $::whoisd(cmd_pub) $word]] != ""} {
    whoisd:out 4 {} $nick $invalid;
    return;
  }
	whoisd:connect $::whoisd(rplmode) $chan $nick $::whoisd(server) $::whoisd(port) $word;
}

proc whoisd:out {type dest nick text} {
	if {[string length [string trim $text]] < 1} { return; }
	switch -- $type {
	  "0" { putdcc $dest "$::whoisd(prefix) $text"; }
		"1" { putserv "PRIVMSG $dest :$::whoisd(prefix) $text"; }
		"2" { putserv "NOTICE $dest :$::whoisd(prefix) $text"; }
		"3" { putserv "PRIVMSG $nick :$::whoisd(prefix) $text"; }
		"4" { putserv "NOTICE $nick :$::whoisd(prefix) $text"; }
		"5" { putlog "$::whoisd(prefix) $text"; }
	}
}
proc whoisd:connect {type dest nick server port word} {
  set whoisd(data_country) "";
  putlog [format $::whoisd(notice_connect) $server $port $word];
	if {[catch {socket -async $server $port} sock]} {
    whoisd:out $type $dest $nick [format $::whoisd(error_connect) $server $port];
    return;
  }
	#TODO: too long; must be split
  fileevent $sock writable [list whoisd:write $type $dest $nick $word $sock $server $port [utimer $::whoisd(timeout) [list whoisd:timeout $type $dest $nick $server $port $sock $word]]];
}
proc whoisd:write {type dest nick word sock server port timerid} {
	if {[set error [fconfigure $sock -error]] != ""} {
		whoisd:out $type $dest $nick [format $::whoisd(error_connect) $server $port];
		whoisd:die $sock $timerid;
		return;
	}
  set word [string trim $word .];
	if {$server == $::whoisd(server)} {
    set lookup [lrange [split $word "."] end end];
  } else {
    set lookup $word;
  }
	puts $sock "$lookup\n";
	flush $sock;
	fconfigure $sock -blocking 0;
	fileevent $sock readable [list whoisd:read $type $dest $nick $word $sock $server $port $timerid];
	fileevent $sock writable {};
}
proc whoisd:read {type dest nick word sock server port timerid} {
	while {![set error [catch {gets $sock output} read]] && $read > 0} {
    if {!$type} { whoisd:out $type $dest $nick $output; }
		if {$server == $::whoisd(server)} {
			if {[regexp $::whoisd(nomatch_tld) $output]} {
				set output [format $::whoisd(error_invalid) "tld"];
				whoisd:out $type $dest $nick $output;
				whoisd:die $sock $timerid;
			}
			if {$::whoisd(data_type) == "tld"} {
				if {[regexp $::whoisd(regex_country) $output -> country]} {
          set ::whoisd(data_country) $country;
				}
				if {[regexp $::whoisd(regex_contact) $output -> contact]} {
          #set ::whoisd(data_contact) $contact;
          whoisd:timeout $type $dest $nick $server $port $sock $word;
  				whoisd:die $sock $timerid;
				}
			} elseif {[regexp -nocase -- $::whoisd(regex_server) $output -> server]} {
        whoisd:connect $type $dest $nick $server $port $word;
        whoisd:die $sock $timerid;
  		}
		} else {
			if {[regexp -nocase -- $::whoisd(nomatch_domain) $output]} { 
				set output [format $::whoisd(output_found) $word];
        whoisd:out $type $dest $nick $output;
				whoisd:die $sock $timerid;
			}
		}
	if {$error} {
		whoisd:out $type $dest $nick $::whoisd(error_connect_lost);
		whoisd:die $sock $timerid;
	}
 }
}
proc whoisd:die {sock timerid} {
  catch { killutimer $timerid }
	catch { close $sock }
}
proc whoisd:timeout {type dest nick server port sock word} {
	catch { close $sock }
	if {$server != $::whoisd(server)} {
    set output [format $::whoisd(output_nomatch) $word];
    whoisd:out $type $dest $nick $output;
    return;
  } elseif {$::whoisd(data_country) != ""} {
    set output [format $::whoisd(output_country) $word $::whoisd(data_country)];
  } else {
    set output [format $::whoisd(output_timeout) $server $port $::whoisd(timeout)];
  }
  whoisd:out $type $dest $nick $output;
}

### Loaded
putlog "whoisd.tcl $whoisd(ver) loaded";

#EOF