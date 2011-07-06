# tinysong.tcl -- 0.1.3
#
#   Search for a track using tinysong.com and return the artist, title, album 
#    and url
#
# Copyright (c) 2010 HM2K
#
# Name: TinySong Search
# Author: HM2K <irc@hm2k.org>
# License: http://www.opensource.org/licenses/bsd-license.php BSD License
# Link: http://www.hm2k.com/posts/tinysong-tcl-script-for-eggdrop
# Labels: search, song, music
# Updated: 19-Apr-2011
#
###Usage
#> .song Midnight Juggernauts - Nine Lives
#<Bot> HM2K, * TinySong: Midnight Juggernauts - Nine Lives [Dystopia] 
# <http://tinysong.com/uAb8>
#
###Revisions
# 0.1.3 - added API key
# 0.1.2 - minor url update; argument split
# 0.1.1 - result error checking; better output and format
# 0.1   - first public release
#
###Credits
# Web hosting by Phurix <www.phurix.co.uk>
# Shell hosting by Gallush <www.gallush.com>
#
# Please consider a donation. Thanks! http://tinyurl.com/hm2kpaypal

### Settings
set tinysong(ver) "0.1.3"; #current version of this file
set tinysong(apikey) "b851de5f6f71c132c56e20bd3caea2c0"; # Your API key
set tinysong(cmd) ".song"; #public command trigger
set tinysong(dcccmd) "song"; #public command trigger
set tinysong(usage) "Usage: $tinysong(cmd) <song>";
set tinysong(prefix) "* TinySong:"; #output prefix
set tinysong(url) "http://tinysong.com/b/"; #url
set tinysong(ua) "MSIE 6.0"; #simulate a browser's user agent, ie: Mozilla
set tinysong(output) "%s - %s \[%s\] <%s>"; #format for the output
set tinysong(noresult) "No Result"; #string for no result

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
bind pub - $tinysong(cmd) pub:tinysong;
bind dcc -|- $tinysong(dcccmd) dcc:tinysong;

### Procedures
proc pub:tinysong { nick uhost handle channel arg } {
	global tinysong;
	set arg [split $arg];
	if {[llength $arg]<1} { putserv "NOTICE $nick :$tinysong(usage)"; return; }
	set result [tinysong:get $arg];
	putserv "PRIVMSG $channel :$nick, $tinysong(prefix) $result";
}

proc dcc:tinysong {ha idx arg} {
  global tinysong;
  set arg [split $arg];
	if {[llength $arg]<1} { putdcc $idx $tinysong(usage); return; }
	set result [tinysong:get $arg];
  putdcc $idx $result; 
}

proc tinysong:get { arg } {
  global tinysong;

  set query [::http::formatQuery $arg];

  set http [::http::config -useragent $tinysong(ua)];
  set http [::http::geturl $tinysong(url)$query?key=$tinysong(apikey)];
  set data [::http::data $http];
  set data [::htmlparse::mapEscapes $data];
  set data [string trim $data];
  if ([string length $data]==0) { return $tinysong(noresult); }
  set data [split $data ";"];
  set info(url) [string trim [lindex $data 0]];
  set info(artist) [string trim [lindex $data 4]];
  set info(title) [string trim [lindex $data 2]];
  set info(album) [string trim [lindex $data 6]];

  return [format $tinysong(output) $info(artist) $info(title) $info(album) $info(url)];
}
### Loaded
putlog "tinysong.tcl $tinysong(ver) loaded";
#EOF