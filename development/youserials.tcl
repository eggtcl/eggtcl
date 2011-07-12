## youserials.tcl -- 0.22 *BETA*
#
#   Calls the youserials.com rss feed, gets the id for the serial, then,
#     calls the page with the correct id for that serial. Also has caching.
#
# Copyright (c) 2010 HM2K
#
# Name: YouSerials Lookup
# Author: HM2K <irc@hm2k.org>
# License: http://www.opensource.org/licenses/bsd-license.php BSD License
# Link: http://
# Labels: youserials, serialz, search
# Updated: 20-Dec-2010
#
###Revisions
# 0.22  - fixed http errors (eg: 504 Gateway Timeout)
# 0.21  - fixed redirect issue
# 0.2   - calls rss feed, instead of google
# 0.1   - beta release
###ToDo
# 0.3   - change to a cached based system with an indexer
#         downloaded serial will be cached and hashed
#         search term and hash will be added to index

### Settings
set ys(ver) "0.22 *BETA*"; #current version of this file
set ys(ua) "Mozilla/5.0 (Windows; U; Windows NT 5.1; en-GB; rv:1.9.2.6) Gecko/20100625 Firefox/3.6.6"; #user agent emulation
set ys(cmd) "!serial"; #public command trigger
set ys(dcccmd) "ys"; #dcc command trigger
set ys(usage) "Usage: %s <text>"; #usage string
set ys(url) "http://www.youserials.com.nyud.net:8090/jq_serial.php"; #url
set ys(gsearchurl) "http://www.google.com/xhtml"; #search engine
set ys(gsitesearch) "site:www.youserials.com/nasiel.php"; #site search string for search engine
#set ys(gmatch) "<div class=\"\[bdl\]\"><a href=\".+?(\[0-9\]{5,8})\""; # what to match
set ys(gmatch) "<a class=\"c\" href=\".+?(\[0-9\]{5,8})\""; # what to match
set ys(output) "\002%s\002 %s"; # output format
set ys(noresult) ""; # String for no result; empty means say nothing.
set ys(cachefile) "/home/freeshell/sz/public_html/serials/youserials.txt"; #location of cache file
set ys(cacheformat) "%s \002%s\002 %s"; # cache stored format
set ys(dateformat) "%Y-%m-%d"; # date format, used for cache output
set ys(debug) 1; # debug mode
set ys(tmpfile) "/home/freeshell/sz/public_html/http.html"; # a temp file used for debug
set ys(rssurl) "http://www.youserials.com/rss.php";
set ys(rssmatch) "<link>http://www.youserials.com/serial/.+?/(\[0-9\]{5,8})</link>";

### Package Definition
package require eggdrop 1.6;  #see http://geteggdrop.com/
package require Tcl 8.2.3;    #see http://tinyurl.com/6kvu2n
if {[catch {package require http 2.0} err]} {
  putlog "[info script] error: $err";
  putlog "[info script] error: http 2.0 or above is required, see http://wiki.tcl.tk/1475";
}
if {[catch {package require htmlparse} err]} {
  putlog "[info script] error: $err";
  putlog "[info script] error: Tcllib is required, see http://wiki.tcl.tk/12099";
}

### Binds
bind pub - $ys(cmd) ys:pub;
bind msg - $ys(cmd) ys:msg;
bind dcc -|- $ys(dcccmd) ys:dcc;

### Procedures
proc ys:cachesearch { text } {
  global ys;
  
  set text [string tolower $text];
  
  if {![file exists $ys(cachefile)]} { return; }
  
  set in [open $ys(cachefile) r];
  while {![eof $in]} {
    set line [gets $in];
    set found 0;
    set matchline [string tolower $line];
    set tplus 0;
    for {set l 0} {$l < [llength $text]} {incr l} {
      set w [lindex $text $l];
      if {[string index $w 0]=="-"} {
        set w [string range $w 1 end];
        if {[string match "*$w*" $matchline]} {set found [expr $found - 1];}
      } else {
        if {[string match "*$w*" $matchline]} {incr found;}
        incr tplus;
      }
    }
    if {$tplus == $found} {
      return $line;
    }
  }
  close $in;
}

proc ys:cacheadd { text } {
  global ys;

  if {$text == ""} {return;}

  set out [open $ys(cachefile) "a+"];
  puts $out $text;
  close $out;
}

proc ys:clearcache { } {
  global ys;

  set out [open $ys(cachefile) "w"];
  puts $out "";
  close $out;
  putlog "cache file was cleared.";
}

proc ys:lookup { text } {
  global ys;

  set text [ys:parseid $text];

  set text [ys:cleantext $text];

  #find cached result
  set result [ys:cachesearch $text];
  if {$result != ""} { return $result; }
  
  #get live result
  set data [ys:rsssearch $text];
  set id [ys:match $data $ys(rssmatch)];
  set result [ys:get $id];
  
  #add live result to cache
  if {$result != ""} { ys:cacheadd [format $ys(cacheformat) [clock format [clock seconds] -format $ys(dateformat)] $text $result]; }

  #no result
  if {$result == "" && $ys(noresult) == ""} { return; }
  
  if {$result == ""} { set result $ys(noresult); } 

  #return formatted result
  return [format $ys(output) $text $result];
}

proc ys:get { id } {
  global ys;
  if {$id <= 2} { return; }
  set query [::http::formatQuery id $id];
  set data [ys:httpget "$ys(url)?$query"];
  set data [string map {"\n" " "} $data];
  if {$data == ""} { return; }
  return "($id) $data";
}

proc ys:httpget { url } {
  global ys;
  if {$ys(debug)==1} { putlog "GET $url"; }
  set http [::http::config -useragent $ys(ua) -urlencoding "utf-8"];
  set http [::http::geturl $url];
  set data [::http::data $http];
  #Save http output
  if {$ys(debug)} {ys:httpsave $ys(tmpfile) $data;}
  #handling errors
  if {[::http::ncode $http] != 200} {
    ::http::cleanup $http;
    return;
  }
  #cleanup
  ::http::cleanup $http;
  return $data;
}

proc ys:httpsave { file data } {
  set out [open $file "w"];
  puts $out $data;
  close $out;
}

proc ys:cleantext { text } {
  set text [string map -nocase {"\"" ""} $text]; #remove quotes
  set text [string map -nocase {"*" " "} $text]; #* to space
  set text [string trim $text]; # trim spaces
  return $text;
}

proc ys:parseid { text } {
  global id;
  set id 0;
  #set wpos [lsearch [string tolower $text] "--l"];
  set wpos [lsearch -regex [string tolower $text] "(--l|-page)"];
  if {$wpos >-1 && [isnum [lindex $text [expr $wpos +1]]]} {
    set text "[lrange $text 0 [expr $wpos -1]] [lrange $text [expr $wpos + 1] end]";
    set id [lindex $text $wpos];
    set text "[lrange $text 0 [expr $wpos -1]] [lrange $text [expr $wpos + 1] end]";
  }
  return $text;
}

proc ys:gsearch { query args } {
  global ys;
  set query [::http::formatQuery hl "en" q "$ys(gsitesearch) $query"];
  set data [ys:httpget "$ys(gsearchurl)?$query"];
  return $data;
}

proc ys:rsssearch { query args } {
  global ys;
  set query [::http::formatQuery rss $query];
  set data [ys:httpget "$ys(rssurl)?$query"];
  return $data;
}

proc ys:match { data match } {
  set matched "";
  set result "";
  regexp -nocase $match $data matched result;
  return $result;
}

proc ys:pub { nick uhost handle chan arg } {
	global ys;
	if {[llength $arg]==0} { ys:out $nick [format $ys(usage) $ys(cmd)]; return; }
	set output [ys:lookup $arg];
	if {$output == ""} {return;}
  if {$ys(debug)} { putlog "> $nick $chan $ys(cmd):$output"; }
	ys:out $nick $output; 
}

proc ys:msg { nick uhost handle arg } {
	global ys;
	if {[llength $arg]==0} { ys:out $nick [format $ys(usage) $ys(cmd)]; return; }
	set output [ys:lookup $arg];
  if {$output == ""} {return;}
  if {$ys(debug)} { putlog "> $nick $ys(cmd):$output"; }
	ys:out $nick $output; 
}

proc ys:dcc {ha idx arg} {
  global ys;
	if {[llength $arg]==0} { ys:out $idx [format $ys(usage) ".$ys(dcccmd)"]; return; }
	if {$arg == "--clear"} {
    ys:clearcache;
  }	else { ys:out $idx [ys:lookup $arg]; } 
}

proc ys:out {nick text} {
  if {$text == ""} {return;}
	if {[isnum $nick]} {putidx $nick $text} else {puthelp "NOTICE $nick :$text"}
}

# isnumber taken from alltools.tcl
proc isnum {string} {
  if {([string compare $string ""]) && (![regexp \[^0-9\] $string])} then {
    return 1;
  }
  return 0;
}

### Loaded
putlog "youserials.tcl $ys(ver) loaded"

#EOF