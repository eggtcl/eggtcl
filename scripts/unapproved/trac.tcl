# trac.tcl -- 0.1
#
#   This eggdrop script will allow you to return ticket information from Trac 
#     to an IRC channel.
#
# Copyright (c) 2010 HM2K
#
# Name: EggdropTicketInfoIntegration
# Author: HM2K <irc@hm2k.org>
# License: http://www.opensource.org/licenses/bsd-license.php BSD License
# Link: http://trac-hacks.org/wiki/EggdropTicketInfoIntegration
# Labels: trac, ticket, information
# Updated: 14-Dec-2010
#
###Install
# 1. Copy trac.tcl to your scripts directory.
# 2. Add "source scripts/trac.tcl" to your eggdrop.conf file.
#
###Usage
# > .trac 13
# <Bot> HM2K, * [assigned enhancement] #13 [major] Updates reported by hm2k
#                 http://example.com/trac/ticket/13
#
# Note: For each channel you want users to use .trac command,
#    Just type in partyline: .chanset #channel +trac
#
###Revisions
# 0.1   - almost a complete rewrite
#       - removed flood control, not needed
#       - removed curl support, outdated
#       - added dcc command
#       - improved header
#       - improved channel flag check
#       - fixed regex patterns
#       - fixed spelling errors
#       - added customisation settings
#       - improved package checking
#       - improved debugging
#       - added not found error
#       - added basic authorization support
#       - fixed syntax errors
# 0.0.1 - based on a script by mvanbaak
#
###Todo
# 0.2 - Upgrade cookie string replacement to use regsub
# 0.2 - Use RSS feed instead of HTML (see weather.tcl)
# 1.0 - Display updates from RSS feed (see adv.tcl & rss-synd.tcl)

### Settings
# version of this file
set trac(ver) "0.1";
# set trac auth - base64 package is required
set trac(auth) "user:password";
# set trac ticket url - no trailing slash
set trac(ticketurl) "http://example.com/trac/ticket";
# output format
set trac(output) "\[%status\] %ticketnum \002\[%priority\]\002 %summary reported by %reporter %url";
#http connection timeout (milliseconds)
set trac(timeout) 25000;
# results will be sent publicly to the channel (1) private message (0)
set trac(pub) 1;
#command for trac in public channel
set trac(pubcmd) ".trac";
#command for trac in dcc
set trac(cmd) "trac";
# syntax usage
set trac(usage) "\002Usage: $trac(pubcmd) <ticket number>\002";
# value for when nothing is returned
set trac(none) "N/A";
# user agent
set trac(ua) "MSIE 6.0";
# regex for ticketnum
set trac(regex_ticketnum) {<h1.*?>Ticket (.+?)<};
# regex for status
set trac(regex_status) {<span class="status">(.*?)</span>};
# regex for summary
set trac(regex_summary) {<h2 class="summary.*?">(.*?)</h2>};
# regex for priority
set trac(regex_priority) {<td headers="h_priority">.+?>(.*?)<.+?</td>};
# regex for reporter
set trac(regex_reporter) {<td headers="h_reporter".*?>.+?>(.*?)<.+?</td>};
# regex for message
set trac(regex_message) {<p class="message">(.+?)</p>};
# error message for url timeout
set trac(msg_timeout) "\002Error:\002 Connection timeout to %s.";
# error message not found
set trac(msg_notfound) "\002Error:\002 Not found.";
# disable/enable debugger (0/1)
set trac(debug) 1;

### Package Definition
package require eggdrop 1.6;  #see http://geteggdrop.com/
package require Tcl 8.4;      #see http://tinyurl.com/6kvu2n
if {[catch {package require http 2.0} err]} {
  putlog "[info script] error: $err";
  putlog "http 2.0 package or above is required, see http://wiki.tcl.tk/1475";
}
set trac(package_base64) [catch {package require base64}];
setudef flag trac;

### Binds
bind pub - $trac(pubcmd) trac_pub;
bind dcc -|- $trac(cmd) trac_dcc;

### Procedures
proc htmlcode {str} {
  set map {&#34; ' &#38; & &#91; ( &#92; / &#93; ) &#123; ( &#125; )
  &#163; £ &#168; ¨ &#169; © &#171; « &#173; ­ &#174; ® &#180; ´ &#183; ·
  &#185; ¹ &#187; » &#188; ¼ &#189; ½ &#190; ¾ &#192; À &#193; Á &#194; Â
  &#195; Ã &#196; Ä &#197; Å &#198; Æ &#199; Ç &#200; È &#201; É &#202; Ê
  &#203; Ë &#204; Ì &#205; Í &#206; Î &#207; Ï &#208; Ð &#209; Ñ &#210; Ò
  &#211; Ó &#212; Ô &#213; Õ &#214; Ö &#215; × &#216; Ø &#217; Ù &#218; Ú
  &#219; Û &#220; Ü &#221; Ý &#222; Þ &#223; ß &#224; à &#225; á &#226; â
  &#227; ã &#228; ä &#229; å &#230; æ &#231; ç &#232; è &#233; é &#234; ê
  &#235; ë &#236; ì &#237; í &#238; î &#239; ï &#240; ð &#241; ñ &#242; ò
  &#243; ó &#244; ô &#245; õ &#246; ö &#247; ÷ &#248; ø &#249; ù &#250; ú
  &#251; û &#252; ü &#253; ý &#254; þ &nbsp; "" &amp; "&"};
  return [string map $map $str];
}
proc replacevar {strin what withwhat} {
  set output $strin;
  set replacement $withwhat;
  set cutpos 0;
  while {[string first $what $output] != -1} {
    set cutstart [expr {[string first $what $output] - 1}];
    set cutstop  [expr {$cutstart + [string length $what] + 1}];
    set output [string range $output 0 $cutstart]$replacement[string range $output $cutstop end];
  }
  return $output;
}
proc trac_pub { nick uhost handle chan arg } {
  global trac;
  set arg [split $arg];  
  # check channel permission
  if {[channel get $chan trac]<1} { return; }
  # if no arg passed, show usage help
  if {[llength $arg]<1} { putserv "NOTICE $nick :$trac(usage)"; return; }  
  # public or private
  set toput [expr {$trac(pub)?"PRIVMSG $chan":"NOTICE $nick"}]; 
  trac_debug "toput: $toput";	
	# output
  set output [trac_proc $arg];
  foreach line [split $output "\n"] {
    puthelp "$toput :$line";
  }
}
proc trac_dcc {ha idx arg} {
  global trac;
  set arg [split $arg];
  # if no arg passed, show usage help
  if {[llength $arg]<1} { putdcc $idx $trac(usage); return; }
	set output [trac_proc $arg];
  foreach line [split $output "\n"] {
    putdcc $idx $line;
  }
}
proc trac_proc { arg } {
  global trac;

  # initial lookup
  set lookup [string map {\  %20 & %26 , %2C . %20} $arg];
  trac_debug "lookup: $lookup";
  #set auth and headers
  set headers [list];
  if {$trac(package_base64)<1} {
    set auth [::base64::encode $trac(auth)];
    lappend headers "Authorization" "Basic $auth";
  }
  #get page
  set url "$trac(ticketurl)/$lookup";
  trac_debug "geturl: $url";
  set page [::http::config -useragent $trac(ua)];
  set page [::http::geturl $url -timeout $trac(timeout) -headers $headers];
  if {[::http::status $page] eq "timeout"} {
    ::http::cleanup $page;
    return [format $trac(msg_timeout) $url];
  }
  set html [::http::data $page];
  ::http::cleanup $page;
  set output $trac(output);

  # get message
  set msg "";
  if {[regexp $trac(regex_message) $html - msg]} {
    trac_debug "message: $msg";
    if {$msg != ""} { return "Error: $msg"; }
  }
  
  # get ticketnum
  set ticketnum "";
  if {[regexp $trac(regex_ticketnum) $html - ticketnum]} {
    set pos [expr {[string last > $ticketnum] + 1}];
    set ticketnum [string range $ticketnum $pos end];
    set ticketnum [htmlcode $ticketnum];
  }
  if {$ticketnum eq ""} { return $trac(msg_notfound); }
  trac_debug "ticketnum: $ticketnum";

  # get status
  set status $trac(none);
  if {[regexp $trac(regex_status) $html - status]} {
    set pos [expr {[string last > $status] + 1}];
    set status [string range $status $pos end];
    set status [htmlcode $status];
    set status [string map {( ""} $status];
    set status [string map {) ""} $status];
  }
  trac_debug "status: $status";
  
  # get summary
  set summary $trac(none);
  if {[regexp $trac(regex_summary) $html - summary]} {
    set pos [expr {[string last > $summary] + 1}];
    set summary [string range $summary $pos end];
    set summary [htmlcode $summary];
  }
  trac_debug "summary: $summary";
  
  # get priority
  set priority $trac(none);
  if {[regexp $trac(regex_priority) $html - priority]} {
    set pos [expr {[string last > $priority] +1}];
    set priority [string range $priority $pos end];
    set priority [htmlcode $priority];
  }
  trac_debug "priority: $priority";

  # get reporter
  set reporter $trac(none);
  if {[regexp $trac(regex_reporter) $html - reporter]} {
    set pos [expr {[string last > $reporter] +1}];
    set reporter [string range $reporter $pos end];
    set reporter [htmlcode $reporter];
  }
  trac_debug "reporter: $reporter";
  
  # output results
  set output [replacevar $output "%ticketnum" $ticketnum];
  set output [replacevar $output "%status" $status];
  set output [replacevar $output "%summary" $summary];
  set output [replacevar $output "%priority" $priority];
  set output [replacevar $output "%reporter" $reporter];
  set output [replacevar $output "%url" $url];    
  return $output;
}
proc trac_debug {msg} {
  global trac;
  if {$trac(debug)>0} { putlog "trac(debug) $msg"; }
}

### Loaded
putlog "trac.tcl $trac(ver) loaded";

#EOF