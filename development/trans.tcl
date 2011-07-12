#trans.tcl v0.2 *BETA* by HM2K <irc@hm2k.org> (Updated: 24/03/10)
#@see

### Usage ###
#> .tr sacrebleu
#<Bot> HM2K, * transated: damn (fr) 

### Settings ###
set trans(ver) "0.2 *BETA*"; #current version of this file
set trans(cmd) ".tr"; #public command trigger
set trans(dcccmd) "tr"; #public command trigger
set trans(usage) "Usage: $trans(cmd) <sentance>";
set trans(prefix) "* transated:"; #output prefix
set trans(url) "http://translate.google.com/translate_a/t"; #url
set trans(lang) "en"; #default language
set trans(ua) "MSIE 6.0"; #simulate a browser's user agent, ie: Mozilla
set trans(output) "%s (%s)"; #format for the output

### Required Packages ###
package require http;
package require htmlparse;

### Requirements ###
if {![string match 1.6.* $version]} { putlog "\002WARNING:\002 This script is intended to run on eggdrop 1.6.x or later." }
if {[info tclversion] < 8.2} { putlog "\002WARNING:\002 This script is intended to run on Tcl Version 8.2 or later." }

### Code ###
bind pub - $trans(cmd) pub:trans;
bind dcc -|- $trans(dcccmd) dcc:trans;

proc pub:trans { nick uhost handle channel arg } {
	global trans;
	if {[llength $arg]<1} { putserv "NOTICE $nick :$trans(usage)"; return; }
	set result [trans:get $arg];
	putserv "PRIVMSG $channel :$nick, $trans(prefix) $result";
}

proc dcc:trans {ha idx arg} {
  global trans;
	if {[llength $arg]<1} { putdcc $idx $trans(usage); return; }
	set result [trans:get $arg];
  putdcc $idx $result; 
}

proc trans:get { arg } {
  global trans;

  #allows you to define the desired resulting language - still experimental  
  set lang [string range [lindex [split [lindex $arg 0] -] 1] 0 1];
  if {[llength $lang] > 0} {
    set trans(lang) $lang;
    set arg [lindex $arg 1 end];
  }

  set query [::http::formatQuery client "t" text $arg hl $trans(lang) sl "auto" tl $trans(lang) otf 2 pc 0];

  set http [::http::config -useragent $trans(ua)];
  set http [::http::geturl $trans(url)?$query];
  set data [::http::data $http];
  set data [::htmlparse::mapEscapes $data];
  set data [string trim $data];
  set data [split $data \"];
  set info(trans) [lindex $data 5];
  set info(orig) [lindex $data 9];
  set info(src) [lindex $data 17];

  return [format $trans(output) $info(trans) $info(src)];
}

putlog "trans.tcl $trans(ver) loaded";
