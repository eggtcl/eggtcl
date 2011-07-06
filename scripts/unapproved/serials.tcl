##
## serial list search v0.2 by HM2K (based on a script by [DrN])
##

## SETTINGS #####################################

# Which channels shall the commands work on?
set sz(chans) "#!serialz #serials #serialz";

# Set this to the maximum number of results to return
# This number can't be exceeded with the --l search switch.
set sz(maxsearch) 50;

# Set this to the default total number of results to return (default is 10)
set sz(totalresults) 1;

# [0/1] Set this to a 1 to highlight the first match in the line
set sz(highlight) 1;

# [0/1] Set this to 1 to show the line number in the output
set sz(showlinenumber) 1;

# Ignore any lookup requests when the queue list exceeds this number
# Set this to 0 to disable it.
set sz(maxqueue) 200;

# The full path to the location of your list files
set sz(path) "/home/serialz/public_html/serials/";

# Set this to the path/filename.ext of the file you wish to store data
# submitted to the script by the users. You can point this to the main
# serial datafile, but just in case they submit crap/flood it, it'd be
# easier to store them in a seperate file so you can verify them.
set sz(addserials) "$sz(path)!addserials.txt";

# Channel triggers for this script
set sz(serialcmd) "!serial";
set sz(addserialcmd) "!addserial";
set sz(helpcmd) "!help";
set sz(serialdcccmd) "serial";

###############################################################
## Do not edit below here unless you know what you are doing ##
###############################################################

set _szver "0.2";

bind msg - $sz(helpcmd) sz:msg_help;
bind pub - $sz(serialcmd) sz:pub_serialsearch;
bind msg - $sz(serialcmd) sz:msg_serialsearch;
bind msg - $sz(addserialcmd) sz:msg_addserial;
bind dcc - $sz(serialdcccmd) sz:dcc_serialsearch;

proc striphtml {html} {
  regsub -all -- {<[^>]*>} $html "" html;
  return $html;
}

proc chncheck {chan check} {
  foreach c $check {
    if {$chan == $c} {
      return 1;
    }
  }
  return 0;
}

proc sz:msg_help {nick uhost handle args} {
  global sz botnick;
  sz:privmsg $nick "Serial Search Usage: $sz(serialcmd) <search string> (eg: $sz(serialcmd) winrar)";
  sz:privmsg $nick "You can exclude words with a - (eg: $sz(serialcmd) adobe -photoshop)";
  sz:privmsg $nick "You can return more/less results using --l <num> (eg: $sz(serialcmd) --l 5 <search string>)";
  sz:privmsg $nick "To add an entry: /msg $botnick $sz(addserialcmd) Program Name : Registration Data";
  if {$sz(maxsearch) != 0} { sz:privmsg $nick "There is a limit of $sz(maxsearch) results in effect."; }
  return 1;
}

proc sz:dcc_serialsearch {hand idx args} {
  if {[lindex $args 0] != ""} {
      set a [lindex $args 0]
      doserialsearch $idx $a
  } else {
    putidx $idx "Usage: .$sz(serialdcccmd) <search string>"
  }
  return 1
}

proc sz:pub_serialsearch {nick uhost handle chan args} {
  global sz
  if {[chncheck $chan $sz(chans)]} {
    if {($sz(maxqueue) > 0) && ([queuesize help] > $sz(maxqueue))} {
      putserv "NOTICE $nick :Sorry, our queue is near full. Please wait a few minutes and make your request again."
      return 0
    }
    if {[lindex $args 0] != ""} {
      set a [lindex $args 0]
      doserialsearch $nick $a
    } else {
      puthelp "NOTICE $nick :Usage: $sz(serialcmd) <search string>"
    }
    return 1
  }
}

proc sz:msg_serialsearch {nick uhost handle args} {
  global sz botnick
  if {($sz(maxqueue) > 0) && ([queuesize help] > $sz(maxqueue))} {
   putserv "NOTICE $nick :Sorry, our queue is near full. Please wait a few minutes and make your request again."
   return 0
  }
  if {[lindex $args 0] != ""} {
    set a [lindex $args 0]
    doserialsearch $nick $a
  } else {
    puthelp "NOTICE $nick :Usage: /msg $botnick $sz(serialcmd) <search string>"
  }
  return 1
}

proc doserialsearch {nick data} {
  global sz botnick
  set maxsearch $sz(totalresults)

  set wpos [lsearch [string tolower $data] "--l"]
  if {$wpos >-1} {
    if {[isnum [lindex $data [expr $wpos +1]]]} {
      set data "[lrange $data 0 [expr $wpos -1]] [lrange $data [expr $wpos + 1] end]"
      set newmaxsearch [lindex $data $wpos]
      set data "[lrange $data 0 [expr $wpos -1]] [lrange $data [expr $wpos + 1] end]"
      while {[string index $data [expr [string length $data]-1]]==" "} {
        set data [string range $data 0 [expr [string length $data] - 2]]
      }
      if {$newmaxsearch > $sz(maxsearch)} {
        sz:privmsg $nick "You can not exceed $sz(maxsearch) search results."
        return 0
      } else { set maxsearch $newmaxsearch }
    }
  }
  #if {$sz(maxsearch) != 0} {sz:privmsg $nick "There is a limit of $maxsearch results in effect."}
  #sz:privmsg $nick "Searching for \"$data\""
  set data [string tolower $data]

  set serialfiles [serialfiles $sz(path)]

  if {$serialfiles == ""} {
    putlog "SZ: (error) Cannot gather list of files."
    return
  }

  set totfound 0
  set linenum 0

  foreach sdbfile $serialfiles {

    if {![file exists $sdbfile]} {
      putlog "SZ: (error) Cannot find '$sdbfile'."
      sz:notice $nick "Cannot find database file."
    } else {
      #searchserials $nick $maxsearch $sdbfile $data
    
      ##NOTICE: searchserials proc was moved into this proc to ensure limits work correctly across many files

      #start serialsearch
      set in [open $sdbfile r]
    
      while {![eof $in]} {
        set line [gets $in]
        incr linenum 1
        set found 0
        set matchline [string tolower $line]
        set tplus 0
        for {set l 0} {$l < [llength $data]} {incr l} {
          set w [lindex $data $l]
          if {[string index $w 0]=="-"} {
            set w [string range $w 1 end]
            if {[string match "*$w*" $matchline]} {set found [expr $found - 1]}
          } else {
            if {[string match "*$w*" $matchline]} {incr found}
            incr tplus
          }
        }
        if {$tplus == $found} {
          if {$sz(highlight)} {
            for {set l 0} {$l < [llength $data]} {incr l} {
              set w [lindex $data $l]
              if {[string index $w 0]!="-"} {
                set spos [string first $w [string tolower $line] 0]
                set fpos [expr $spos + [string length $w]]
                set line "[string range $line 0 [expr $spos - 1]]\002[string range $line $spos $fpos]\002[string range $line [expr $fpos + 1] end]"
              }
            }
          }
          #clean up those nasty serials 2000 lists
          set line [striphtml $line]
          set line [string map {"\x09" " "} $line]
          
          if {$sz(showlinenumber) == 1} {set line "($linenum) $line"}
    
          incr totfound
    
          if {$totfound == 1 && $wpos < 0} {
            sz:notice $nick "$line"
            return 1
          } else {
            sz:privmsg $nick "$line"
            if {$totfound >= $maxsearch} {
              sz:privmsg $nick "There is more than $maxsearch results. (for help issue $sz(helpcmd))"
              close $in
              return 0
            }
          }
        }
      }
      close $in
      #sz:notice $nick "There was a total of $totfound out of $linenum entries matching your query."
    
      ##end searchserial proc
    }
  }
}

proc serialfiles {dir} {
  if {[string range $dir end end] != "/"} {
    append dir "/"
  }
  set r ""
  #set l [glob -nocomplain $dir*]
  set l [lsort [eval glob -nocomplain $dir*]]
  foreach f $l {
    if {[file isdirectory $f]} {
      set r [concat $r [serialfiles $f]]
    } elseif {[file isfile $f]} {
        lappend r $f
    }
  }
  return $r
}

proc sz:msg_addserial {nick uhost hand text} {
	global sz
	
	if {![file exists $sz(addserials)]} {
    set out [open $sz(addserials) "w"]
    puts $out ""
    close $out
	}

  if {$text == ""} {sz:notice $nick "Usage: $sz(addserialcmd) Program name : Registration Data"
  	   return 0}
  set out [open $sz(addserials) "a+"]
  puts $out "[ctime [unixtime]] -$nick- $text"
  close $out
  sz:privmsg $nick "Entry submitted: $text"
}

proc sz:privmsg {nick text} {
	if {[isnum $nick]} {putidx $nick $text;} else {puthelp "PRIVMSG $nick :$text";}
}

proc sz:notice {nick text} {
	if {[isnum $nick]} {putidx $nick $text;} else {puthelp "NOTICE $nick :$text";}
}

# isnumber taken from alltools.tcl
proc isnum {string} {
  if {([string compare $string ""]) && (![regexp \[^0-9\] $string])} then {
    return 1;
  }
  return 0;
}

putlog "Loaded \002serial list search v$_szver\002 by HM2K"
