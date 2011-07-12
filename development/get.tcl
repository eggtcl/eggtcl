##
## get file v0.5 by HM2K (based on a script by mamaKIN)
##
### Requirements: ###############################
##
## You need to have the transfer module loaded for this to work
##
### Installation: ###############################
##
## 1) Put this file in your script directory
## 2) Add the line "source <scripts directory>/get.tcl" to your bots configuration
## 3) Rehash your bot if it is already running or start it up if it is not
##
### Usage: ######################################
##
## Channel Commands:
## !get <filename> - Sends the first matching file to you
## !search <wildcard> - Finds the closest match
## !send <nickname> <filename> - Sends the first matching file to the nickname
##
#################################################

## SETTINGS #####################################

# Where is your file directory?
set get(dir) "/home/serialz/public_html/cracks/"

# Which files/directories should I not search for/in?
set get(blocked) "incoming readme.txt upload.php index.html index.php"

# Which channels shall the commands work on?
set get(chans) "#!serialz #serials #serialz"

# Channel triggers for this script
set get(getcmd) "!get"
set get(searchcmd) "!search"
set get(sendcmd) "!send"

###############################################################
## Do not edit below here unless you know what you are doing ##
###############################################################

set _getver "0.5"

bind msg - $get(getcmd) GET:msg_get
bind pub - $get(getcmd) GET:pub_get
bind pub - $get(searchcmd) GET:pub_search
bind pub - $get(sendcmd) GET:pub_send

proc findfile {file dir} {
  set file [string tolower $file]
  return [findat $file $dir]
}

proc findat {file dir} {
  if {[string range $dir end end] != "/"} {
    append dir "/"
  }
  set r ""
  set l [glob -nocomplain $dir*]
  foreach f $l {
    if {[file isdirectory $f]} {
      set r [concat $r [findat $file $f]]
    } elseif {[file isfile $f]} {
      if {[string tolower [file tail $f]] == $file} {
        lappend r $f
      }
    }
  }
  return $r
}

proc searchfile {file dir} {
  set file [string tolower $file]
  set file [string map {" " *} $file]
  return [searchdata $file $dir]
}

proc searchdata {file dir} {
  if {[string range $dir end end] != "/"} {
    append dir "/"
  }
  set r ""
  set l [glob -nocomplain $dir*]
  foreach f $l {
    if {[file isdirectory $f]} {
      set r [concat $r [searchdata $file $f]]
    } elseif {[file isfile $f]} {
      if {[string match *$file* [string tolower [file tail $f]]]} {
        #lappend r $f
        return [file tail $f]
      }
    }
  }
  #return $r
}

proc chncheck {chan check} {
  foreach c $check {
    if {$chan == $c} {
      return 1
    }
  }
  return 0
}

proc GET:msg_get {nick host hand text} {
  global get
    #set file [lindex $text 0]
    set file $text
    if {![string match "*[string tolower $file]*" "[string tolower [lrange $get(blocked) 0 end]]"]} {
      set results [findfile $file $get(dir)]
    } {
      puthelp "NOTICE $nick :Sorry, file $file is blocked."
      return 1
    }
    if {[llength $results] == 0} {
      puthelp "NOTICE $nick :Sorry, file $file was not found."
    } {
      set sent [dccsend [lindex $results 0] $nick]
      if {$sent == 0} {
        puthelp "NOTICE $nick :Sending you $file"
      } elseif {$sent == 1} {
        puthelp "NOTICE $nick :DCC Tables are full. Try back in a few minutes."
      } elseif {$sent == 2} {
        puthelp "NOTICE $nick :For some strange reason the file does not exist."
      } elseif {$sent == 4} {
        puthelp "NOTICE $nick :Your file was queued for a later transfer."
      } else {
        puthelp "NOTICE $nick :An undefined error occurred during the transfer."
      }
    }
  return 1
}

proc GET:pub_get {nick host hand chan text} {
  global get botnick
  if {[chncheck $chan $get(chans)]} {
    #set file [lindex $text 0]
    set file $text
    if {$file == ""} {
        puthelp "NOTICE $nick :Please specify a filename."
        return 1    	
    }
	    if {![string match "*[string tolower $file]*" "[string tolower [lrange $get(blocked) 0 end]]"]} {
	      set results [findfile $file $get(dir)]
	    } {
	      puthelp "NOTICE $nick :Sorry, access to file $file is blocked."
	      return 1
	    }
	    if {[llength $results] == 0} {
	      puthelp "NOTICE $nick :Sorry, file $file was not found, try another bot."
	    } {
	      puthelp "NOTICE $nick :File $file was found, to recieve type: /msg $botnick $get(getcmd) $file"
	    }
  }
  return 1
}

proc GET:pub_search {nick host hand chan text} {
  global get botnick
  if {[chncheck $chan $get(chans)]} {
    #set file [lindex $text 0]
    #set file $text
    set file [string map {" " *} $text]
    if {$file == ""} {
        puthelp "NOTICE $nick :Please specify a filename."
        return 1    	
    }
	    if {![string match "*[string tolower $file]*" "[string tolower [lrange $get(blocked) 0 end]]"]} {
	      set results [searchfile $file $get(dir)]
	    } {
	      puthelp "NOTICE $nick :Sorry, that search is disabled."
	      return 1
	    }
	    #set results [searchfile $file $get(dir)]
	    if {[llength $results] == 0} {
	      puthelp "NOTICE $nick :Sorry, no match was not found."
	    } {
	      puthelp "NOTICE $nick :File $results was found as the closest match, to recieve type: /msg $botnick $get(getcmd) $results"
	    }
  }
  return 1
}

proc GET:pub_send {nick host hand chan text} {
  global get

  #check to make sure this is only to be used by voices or ops
  if {![isvoice $nick $chan] && ![isop $nick $chan]} {return 0}

  if {[chncheck $chan $get(chans)]} {
    set g2nick [lindex $text 0]
    set file [lindex $text 1]
    if {![string match "*[string tolower $file]*" "[string tolower [lrange $get(blocked) 0 end]]"]} {
      set results [findfile $file $get(dir)]
    } {
      puthelp "NOTICE $nick :Could not send you $file, because the file has been disabled."
      return 1
    }
    if {[llength $results] == 0} {
      puthelp "NOTICE $nick :Didn't find any results for $file"
    } else {
      set sent [dccsend [lindex $results 0] $g2nick]
      puthelp "NOTICE $g2nick :$nick requested for me to send you $file"
      if {$sent == 0} {
        puthelp "NOTICE $nick :Sending $g2nick $file"
        puthelp "NOTICE $g2nick :Sending you $file"
      } elseif {$sent == 1} {
        puthelp "NOTICE $g2nick :DCC Tables are full. You cannot receive the file."
        puthelp "NOTICE $nick :DCC Tables are full. Could not send $g2nick $file"
      } elseif {$sent == 2} {
        puthelp "NOTICE $g2nick :For some strange reason the file does not exist."
        putserv "NOTICE $nick :The file does not exist."
      } elseif {$sent == 3} {
        puthelp "NOTICE $nick :Had trouble connecting to $g2nick"
      } elseif {$sent == 4} {
        puthelp "NOTICE $g2nick :Your file was queued for a later transfer."
        puthelp "NOTICE $nick :$file was queued and will be transfered later."
      } else {
        puthelp "NOTICE $nick :An undefined error occurred during the transfer."
      }
    }
  }
  return 1
}

putlog "Loaded \002get file v$_getver\002 by HM2K"
