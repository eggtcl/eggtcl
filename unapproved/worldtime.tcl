# worldtime.tcl -- 2.4
#
#   Returns the current time for anywhere in the world.
#
# Copyright (c) 2011 HM2K
#
# Name: WorldTime Lookup
# Author: HM2K <irc@hm2k.org>
# License: http://www.opensource.org/licenses/bsd-license.php BSD License
# Link: http://www.hm2k.com/posts/worldtime-tcl
# Tags: time, world, lookup
# Updated: 10-Jul-2011
#
###Usage
# > .tz london
# <Bot> HM2K, The time in Westminster, London, UK is Fri Feb 13 23:31:30 2009
#       (GMT+1000)
#
###Revisions
# 2.4	- Uses namespace; init/deinit procs; settings file; better formatting
# 2.3.3 - improved header and formatting
# 2.3.2 - expanded GMT offset; added curly braces for expr
# 2.3.1 - fixed memory leaks; fixed unmatched results
# 2.3   - uses Google to retrieve geo and timezone information;
#         instead of the system zoneinfo database, which was unreliable.
#         more portable, works on any platform, including Windows.
# 2.2.3 - added timezone offset to output string
# 2.2.2 - added time offset, for a bizarre situation
# 2.2.1 - a few bug fixes, now finds correct zoneinfo dir
# 2.2   - replaced old TIME method with HTP method
# 2.1   - now uses the TIME protocol to get accurate unixtime
# 2.0   - new and improved, using system zoneinfo
# 1.3   - based on a script by Murf, using worldtimeserver.com

#
# Settings
#

# Namespace
namespace eval ::tz {
	variable version
	set version "2.4"; #current version of this script

	variable tz
	# Default settings
	set tz(cmd) ".tz"; # public command trigger
	set tz(dcccmd) "tz"; # dcc command trigger
	set tz(output) "The time in \002%s\002 is %s (%s)"; # format for the output
	set tz(dateformat) "%a %b %d %I:%M:%S %p %Y"; # format for the clock (wiki.tcl.tk/1810)
	set tz(usage) "Usage: $tz(cmd) <location>"; # usage result
	set tz(noresult) "Unable to find a match."; # no result result
	set tz(gettime) 1; # when on, will get time from time server, instead of system
	set tz(timeserver) "www.google.com"; # should be any good remote web server
	set tz(offset) 0; # seconds, eg: 3600 for plus 1 hour or -3600 for minus
	set tz(utc) "GMT"; # name given to UTC
	set tz(geourl) "http://maps.google.com/maps/api/geocode/xml"; # url for Google GeoCode lookup
	set tz(tzurl) "http://www.google.com/ig/timezone"; # url for Google's TimeZone lookup
	# Note: Copy the above "Default settings" section into "weather.settings.tcl"
	#	to customise your settings. Then they will be used instead.

	# Settings file
	if {[catch {source scripts/worldtime.settings.tcl} err]} {
	  putlog "Warning: 'worldtime.settings.tcl' was not loaded"
	}
}

#
# Procedures
#

# Initialization
proc ::tz::init {args} {
	variable tz
	variable version

	# Package Definition
	package require eggdrop 1.6;  #see http://geteggdrop.com/
	package require Tcl 8.2.3;    #see http://tinyurl.com/6kvu2n
	if {[catch {package require http 2.0} err]} {
	  putlog "[info script] error: $err"
	  putlog "http 2.0 package or above is required, see http://wiki.tcl.tk/1475"
	}
	if {[catch {package require htmlparse} err]} {
	  putlog "[info script] error: $err"
	  putlog "Tcllib is required, see http://wiki.tcl.tk/12099"
	}

	# User defined channel flag
	setudef flag worldtime

	# Binds
	bind pub - $tz(cmd) [namespace current]::pub
	bind dcc -|- $tz(dcccmd) [namespace current]::dcc
	bind evnt -|- prerehash [namespace current]::deinit

	# Loaded
	putlog "worldtime.tcl $version loaded"
}

# Deinitializaion
proc ::tz::deinit {args} {
	catch {unbind pub -|- {* *} [namespace current]::pub}
	catch {unbind dcc -|- {*} [namespace current]::dcc}
	catch {unbind evnt -|- prerehash [namespace current]::deinit}
	namespace delete [namespace current]
}

proc ::tz::pub { nick uhost hand chan arg } {
	variable tz
	# check channel permission
	if {[channel get $chan worldtime]<1} { return }
	if {[llength $arg]==0} {
		putserv "NOTICE $nick :$tz(usage)"
		return
	}
	set result [::tz::get $arg]
	if {[llength $result]==0} { set result $tz(noresult) }
	putserv "PRIVMSG $chan :$nick, $result"
}
proc ::tz::dcc {ha idx arg} {
	variable tz
	if {[llength $arg]==0} {
		putdcc $idx $tz(usage)
		return
	}
	set result [::tz::get $arg]
	if {[llength $result]==0} { set result $tz(noresult) }
	putdcc $idx $result
}
proc ::tz::get { arg } {
  variable tz
  #set the time
  set time ""
  if {$tz(gettime)} { set time [::tz::gethtp $tz(timeserver)] }
  if {$time eq ""} { set time [clock seconds] }
  #offset place holder
  set offset 0
  #set geo location info
  set geoinfo [::tz::getgeo $arg]
  #no results
  if {$geoinfo eq {}} { return }
  #set timezone name
  set arg [lrange $geoinfo 2 end]
  #set timezone info
  set tzinfo [::tz::gettz [lrange $geoinfo 0 1]]
  #no results
  if {$tzinfo eq {}} { return }
  #get gmt offset in seconds (including dst)
  set offset [expr {[lindex $tzinfo 0]+[lindex $tzinfo 1]}]
  #add timezone data to current gmt time (+offset)
  set time [expr {$time+$offset/1000+$tz(offset)}]
  #format the unixtime seconds to human readable time
  set time [clock format $time -format $tz(dateformat)]
  #make offset human readable
  set offset [expr {$offset/3600}]
  if {$offset == 0} { set offset "$tz(utc)"
  } elseif {$offset > 0} { set offset "$tz(utc)+$offset"
  } else { set offset "$tz(utc)$offset" }
  #format and return
  return [format $tz(output) $arg $time $offset]
}
proc ::tz::gethtp {args} { #?server? ?port?
  set server [expr ([llength $args]>0)?"[lindex $args 0]":"www.google.com"]
  set port [expr ([llength $args]>1)?"[lindex $args 1]":80]
  set s [socket $server $port]
  puts $s "HEAD / HTTP/1.0\n"
  flush $s
  while {[gets $s l] >= 0} {
    if {[regexp {Date: (.+?) GMT$} $l -> date]} {
      close $s
      return [clock scan $date]
    }
  }
}
proc ::tz::getdata { arg } {
  if {[string length $arg]<1} { return }
  set http [::http::geturl $arg]
  set data [::http::data $http]
  set data [::htmlparse::mapEscapes $data]
  set data [string trim $data]
  set data [join $data " "]
  ::http::cleanup $http
  return $data
}
proc ::tz::xmlparse { data arg } {
  if {[string length $arg]<1} { return }
  set arg [string tolower $arg]
  set matched ""
  set result ""
  regexp "<$arg>(.+?)</$arg>" $data matched result
  return $result
}
proc ::tz::jsonparse { data arg } {
  if {[string length $arg]<1} { return }
  set matched ""
  set result ""
  regexp "'$arg':(\[^,\}\]+)" $data matched result
  return $result
}
proc ::tz::getgeo { arg } {
  variable tz
  set arg [::http::formatQuery address $arg sensor "false"]
  set data [::tz::getdata $tz(geourl)?$arg]
  if {[regexp "<html>.+" $data]} { return }
  if {$data eq {}} { return }
  #parse info
  set info(lat) [::tz::xmlparse $data "lat"]
  set info(lng) [::tz::xmlparse $data "lng"]
  set info(addr) [::tz::xmlparse $data "formatted_address"]
  return "$info(lat) $info(lng) $info(addr)"
}
proc ::tz::gettz { arg } {
  variable tz
  if {[string length $arg]<1} { return }
  set arg [::http::formatQuery lat [lindex $arg 0] lng [lindex $arg 1]]
  set data [::tz::getdata $tz(tzurl)?$arg]
  if {[regexp "<html>.+" $data]} { return }
  if {$data eq {}} { return }
  set info(offset) [::tz::jsonparse $data "rawOffset"]
  set info(dst) [::tz::jsonparse $data "dstOffset"]
  return "$info(offset) $info(dst)"
}

::tz::init