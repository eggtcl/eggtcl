# ucc.tcl -- 0.1.4
#
#   Converts an amount from one currency to another using the Yahoo Finance API
#
# Copyright (c) 2010 HM2K
#
# Name: Universal Currency Converter
# Author: HM2K <irc@hm2k.org>
# License: http://www.opensource.org/licenses/bsd-license.php BSD License
# Link: http://www.hm2k.com/posts/universal-currency-converter-tcl-for-eggdrop
# Labels: currency, converter, ucc, yahoo, finance
# Updated: 24-May-2010
#
###Usage
# > .ucc 1 usd gbp
# <Bot> 1 USD is 0.6913 GBP as of Fri May 21 17:54:00 2010
#
###Revisions
# 0.1.4 - better error checking and better file header
# 0.1.3 - added invalid datetime check
# 0.1.2 - added input check for amount (thanks BaS)
# 0.1.1 - custom date format and minor improvements
# 0.1   - first public release
#
###Todo
# 0.2 (feature) Add country currencies list for searching
#

### Settings
set ucc(ver) "0.1.4"; #current version of this file
set ucc(cmd) ".ucc"; #public command trigger
set ucc(dcccmd) "ucc"; #public command trigger
set ucc(usage) "Usage: $ucc(cmd) <amount> <from> <to>";
set ucc(prefix) "* UCC:"; #output prefix
set ucc(url) "http://download.finance.yahoo.com/d/"; #url
set ucc(ua) "MSIE 6.0"; #simulate a browser's user agent, ie: Mozilla
set ucc(output) "%s %s is %s %s as of %s"; #format for the output
set ucc(dateformat) "%a %b %d %H:%M:%S %Y"; #format for the output
set ucc(errorformat) "Error: %s"; #prefix all errors

### Package Definition
package require eggdrop 1.6;  #see http://geteggdrop.com/
package require Tcl 8.2.3;    #see http://tinyurl.com/6kvu2n
if {[catch {package require http 2.0} err]} {
  putlog "[info script] error: $err";
  putlog "http 2.0 package or above is required, see http://wiki.tcl.tk/1475";
}
if {[catch {package require htmlparse} err]} {
  putlog "[info script] error: $err";
  putlog "Tcllib package is required, see http://wiki.tcl.tk/12099";
}

### Binds
bind pub - $ucc(cmd) pub:ucc;
bind dcc -|- $ucc(dcccmd) dcc:ucc;

### Procedures
proc pub:ucc { nick uhost handle channel arg } {
	global ucc;
	set arg [split $arg];
	if {[llength $arg]!=3} { putserv "NOTICE $nick :$ucc(usage)"; return; }
	set result [ucc:get $arg];
	putserv "PRIVMSG $channel :$nick, $ucc(prefix) $result";
}

proc dcc:ucc {ha idx arg} {
  global ucc;
  set arg [split $arg];
	if {[llength $arg]!=3} { putdcc $idx $ucc(usage); return; }
	set result [ucc:get $arg];
  putdcc $idx $result; 
}

proc ucc:get { arg } {
  global ucc;

  set amount [lindex $arg 0];
  regsub -all -- {[^0-9\.]+} $amount "" amount;
  if {$amount eq ""} { set amount 1; }
  set from [string toupper [lindex $arg 1]];
  set to [string toupper [lindex $arg 2]];
  set query [::http::formatQuery f "sl1d1t1" s "$from$to=X"];
  
  set http [::http::config -useragent $ucc(ua)];
  set http [::http::geturl $ucc(url)?$query];
  set data [::http::data $http];
  set data [::htmlparse::mapEscapes $data];
  set data [string trim $data];
  set data [split $data ,];
  ::http::cleanup $http;
  
  set info(query) [lindex $data 0];
  set info(rate) [lindex $data 1];
  set info(date) [string trim [lindex $data 2] \"];
  set info(time) [string trim [lindex $data 3] \"];

  if {[catch {set info(timestamp) [clock scan "$info(date) $info(time)"]} error]} { 
	set info(datetime) "$info(date) $info(time)";
	#return [format $ucc(errorformat) $error];
  } else {
	 set info(datetime) [clock format $info(timestamp) -format $ucc(dateformat)];
  }
  if {[catch {set result [expr {$info(rate)*double($amount)}]} error]} {
    return [format $ucc(errorformat) $error];
  }
  return [format $ucc(output) $amount $from $result $to $info(datetime)];
}

### Loaded
putlog "ucc.tcl $ucc(ver) loaded";
#EOF