# weather.tcl -- 2.0.6
#
#   Returns the current weather for the city or postcode using the iGoogle
#    API for weather.
#
# Copyright (c) 2011 HM2K
#
# Name: Weather Lookup
# Author: HM2K <irc@hm2k.org>
# License: http://www.opensource.org/licenses/bsd-license.php BSD License
# Link: http://www.hm2k.com/posts/weather-tcl
# Labels: weather, lookup, google, api
# Updated: 07-Jan-2011
#
###Usage
# > .wz london
# <Bot> HM2K, * Weather: London, England: Mostly Cloudy, 8ºC Humidity: 87% Wind:
#        W at 9 mph
#
###Revisions
# 2.0.6 - added command check for ::htmlparse::mapEscapes proc
# 2.0.5 - added http timeout check; improvements to code syntax
# 2.0.4 - improved package defintion checks and added utf-8 support
# 2.0.3 - better requirement checking and better file header
# 2.0.2 - now returns temperature in C or F, depending on what you define.
# 2.0.1 - fixed weather.tcl $info(problem) -> $data(problem) (tnx Pixelz)
# 2.0   - a complete rewrite using google's api to gather the weather info
# 1.x   - based on a script by Ycarus
#
###Todo
# 2.1		- Add -c and -f to the syntax for returning the temperature
# 2.1		- Weather forecast
# 3.0   - Switch to Yahoo's Weather API
#
###Credits
# Web hosting by Phurix <www.phurix.co.uk>
# Shell hosting by Gallush <www.gallush.com>
#
# Please consider a donation. Thanks! http://tinyurl.com/hm2kpaypal

### Settings
set wz(ver) "2.0.6"; #current version of this file
set wz(lang) "en"; #language
set wz(cmd) ".wz"; #public command trigger
set wz(dcccmd) "wz"; #dcc command trigger
set wz(prefix) "* Weather:"; #output prefix
set wz(temp) "C"; # temperature scale [C/F]
set wz(output) "\002%s:\002 %s, %sº$wz(temp) %s %s"; #format for the output
set wz(problem) "Problem:";
set wz(errormsg) "Error: No information could be found for";
set wz(usage) "Usage: $wz(cmd) <city|postcode,country>";
set wz(ua) "MSIE 6.0"; #simulate a browser's user agent, ie: Mozilla
set wz(url) "http://www.google.com/ig/api"; #url
set wz(timeout) 25000;
set wz(timeoutmsg) "Error: Connection timed out";

### Package Definition
package require eggdrop 1.6;  #see http://geteggdrop.com/
package require Tcl 8.4;      #see http://tinyurl.com/6kvu2n
if {[catch {package require http 2.0} err]} {
  putlog "[info script] error: $err";
  putlog "http 2.0 package or above is required, see http://wiki.tcl.tk/1475";
}
if {[catch {package require htmlparse} err]} {
  putlog "[info script] error: $err";
  putlog "Tcllib is required, see http://wiki.tcl.tk/12099";
}

### Binds
bind pub - $wz(cmd) pub:wz;
bind dcc -|- $wz(dcccmd) dcc:wz;

### Procedures
proc pub:wz { nick uhost handle channel arg } {
	global wz;
	set arg [split $arg];
	if {[llength $arg]==0} { putserv "NOTICE $nick :$wz(usage)"; return; }
	set result [wz:get $arg];
	putserv "PRIVMSG $channel :$nick, $wz(prefix) $result";
}

proc dcc:wz {ha idx arg} {
  global wz;
  set arg [split $arg];
	if {[llength $arg]==0} { putdcc $idx $wz(usage); return; }
	set result [wz:get $arg];
  putdcc $idx $result; 
}

proc wz:get { arg } {
  global wz;

  set query [::http::formatQuery weather $arg hl $wz(lang)];
  #set url [format $wz(url) $arg $wz(lang)];
  
  set http [::http::config -useragent $wz(ua) -urlencoding "utf-8"];
  set http [::http::geturl $wz(url)?$query -timeout $wz(timeout)];
  if {[::http::status $http] eq "timeout"} {
    ::http::cleanup $http;
    return $wz(timeoutmsg);
  }
  set data [::http::data $http];
  set data [_mapEscapes $data];
  #set data [wz:parse $data "forecast_information"][wz:parse $data "current_conditions"];
  ::http::cleanup $http;

  set temp [expr {([string tolower $wz(temp)] == "f")?"temp_f":"temp_c"}];
  
  set info(city) [wz:parsedata $data city];
  set info(condition) [wz:parsedata $data condition];
  set info(temp) [wz:parsedata $data $temp];
  set info(humidity) [wz:parsedata $data humidity];
  set info(wind) [wz:parsedata $data wind_condition];
  set info(problem) [wz:parsedata $data problem_cause];
  
  if {([info exists info(problem)]) && ($info(problem) ne "")} {
    return "$wz(problem) $info(problem)";
  }
  if {([info exists info(city)]) && ($info(city) == "")} {
    return "$wz(errormsg) $arg";
  }

  return [format $wz(output) $info(city) $info(condition) $info(temp) $info(humidity) $info(wind)];
}

proc wz:parse { data arg } {
  set arg [string tolower $arg];
  set matched "";
  set result "";
  regexp "<$arg>(.+?)</$arg>" $data matched result;
  return $result;
}

proc wz:parsedata { data arg } {
  set arg [string tolower $arg];
  set matched "";
  set result "";
  regexp "<$arg data=\"(\[^\"\]+)\"/>" $data matched result;
  return $result;
}

proc _mapEscapes {data} {
	if {[info commands ::htmlparse::mapEscapes] == ""} {
		putlog "Invalid command name \"::htmlparse::mapEscapes\"";
    	putlog "Tcllib is required, see http://wiki.tcl.tk/12099";
	} else {
		return [::htmlparse::mapEscapes $data];
	}
}

### Loaded
putlog "weather.tcl $wz(ver) loaded";

#EOF