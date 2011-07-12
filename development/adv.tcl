## adv.tcl -- 1.5 *BETA*
#
#   Allows you to advertise across many channels, usually used in 
#     large channels or shell channels.
#
# Copyright (c) 2010 HM2K
#
# Name: Channel Advertisement
# Author: HM2K <irc@hm2k.org>
# License: http://www.opensource.org/licenses/bsd-license.php BSD License
# Link: http://
# Labels: advertise, channel
# Updated: 29-Dec-2010
#
###Revisions
# 1.5   - improved header, added binds, fixed write bug, improved syntax
# 1.4   - fixed a few syntax bugs
# 1.3   - load/edit/add/delete ads from a text file now
# 1.2   - minor changes
# 1.1   - minor changes
# 1.0   - innitial release
###ToDo
# 2.0   - ...
### Usage
#.+adv - \002Your Advert Here!\002 - An advert can be a great way for you to get people interested in your company/channel/website, we accept all types, if you would like to advertise please \002/MSG $owner for details\002
#.+adv \002My Company\002: Details about your company here!
#.-adv 1
#.advlist

### Settings
set adv(time) 60; # Time delay between advert messages. (in minutes)
set adv(chans) "#serials"; #Channels to advertise in
set adv(file) "adv.txt"; # Text file with lines of advert text

### Binds
bind dcc m +adv adv:dccadd;
bind dcc m -adv adv:dccdel;
bind dcc m advlist adv:dcclist;

### Variables
set adv(timer) 0;
set adv(text) "";
set adv(ver) "1.5";

### Procedures
proc adv:dccadd {ha idx arg} {
  global adv;
	if {[llength $arg]==0} { putidx $idx "Usage: .+adv <advert text>"; return; }
	set r [adv:add $arg];
  if {$r == 0} {
    putidx $idx "Advert add failed.";
  } else {
    putidx $idx "Advert added successfully.";
  }
}
proc adv:add {info} {
  global adv;
  lappend adv(text) $info;
  if {[catch {open $adv(file) a} advfile]} {
    putlog "Unable to open file '$adv(file)' for writing.";
    return 0;
  }
  puts $advfile $info;
	close $advfile;
	return 1;
}
proc adv:dccdel {ha idx arg} {
  global adv;
	if {[llength $arg]==0} { putidx $idx "Usage: .-adv <advert id>"; return; }
	set r [adv:del $arg];
  if {$r == 0} {
    putidx $idx "Advert delete failed.";
  } else {
    putidx $idx "Advert deleted successfully.";
  }
}
proc adv:del {id} {
  global adv;  
  set adv(text) [lreplace $adv(text) $id $id];
  return [adv:save];
}
proc adv:save {} {
  global adv;
  if {[catch {open $adv(file) w} advfile]} {
    putlog "Unable to open file '$adv(file)' for writing.";
    return 0;
  }
  foreach line $adv(text) {
    puts $advfile $line;
  }
	close $advfile;
	return 1;
}
proc adv:dcclist {ha idx arg} {
  global adv;
  set n 0;
  foreach line $adv(text) {
    putidx $idx "$n: $line";
    incr n;
  }
}
proc adv:print {} {
	global adv;
  set advmsg [lindex $adv(text) [rand [llength $adv(text)]]];
  foreach advchan $adv(chans) {
  	if {[info exists {advchan}] && [info exists {advmsg}]} {
      putserv "PRIVMSG $advchan :$advmsg";
    }
  }
  timer ${adv(time)} adv:print;
}
proc adv:init {} {
  global adv;
  if {$adv(timer) != 1} {
    set adv(timer) 1;
    timer ${adv(time)} adv:print;
  }
  if {[catch {set advfile [open $adv(file) r]} advfile]} {
    putlog "Unable to open file '$adv(file)' for reading.";
    return 0;
  }
  while {![eof $advfile]} {
    gets $advfile line;
    lappend adv(text) "$line";
  }
}

### Initialise
adv:init;

### Loaded
putlog "adv.tcl $adv(ver) loaded";

#EOF