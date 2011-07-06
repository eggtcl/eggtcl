## totals v0.2 by HM2K
## total files and lines of text in all files in a directory
##

## SETTINGS #####################################

# Where is your file directory?
set total(filedir) "/home/serialz/public_html/cracks/"

# Where is your lists directory?
set total(linesdir) "/home/serialz/public_html/serials/"

# Channel trigger
set total(cmd) "!total"

# DCC command
set total(dcc) "total"

###############################################################
## Do not edit below here unless you know what you are doing ##
###############################################################

set _totalver "0.2"

bind pub o $total(cmd) pub_total
bind dcc o $total(dcc) dcc_total

proc pub_total {nick host hand chan text} {
  global total

  set total_files [total:files $total(filedir)]
  set total_lines [total:lines $total(linesdir)]
  if {[expr $total_files + $total_lines] != 0} { 
  	puthelp "PRIVMSG $chan :\001ACTION has a total of $total_lines lines and $total_files files.\001"
  } else { 
  	puthelp "NOTICE $nick :nothing found."
  }
  return 1
}

proc dcc_total {hand idx text} {
  global total

  set total_files [total:files $total(filedir)]
  set total_lines [total:lines $total(linesdir)]
  if {[expr $total_files + $total_lines] != 0} { 
  	putidx $idx "\001ACTION has a total of $total_lines lines and $total_files files.\001"
  } else { 
  	putidx $idx "nothing found."
  }
  return 1
}

proc total:files {dir} {
  if {[string range $dir end end] != "/"} {
    append dir "/"
  }
  set r 0
  set l [glob -nocomplain $dir*]
  foreach f $l {
    if {![file isdirectory $f]} {
    	incr r
    }
  }
  return $r
}

proc total:lines {dir} {
 set data [listfiles $dir]

 set lines 0
 foreach sdb $data {
	set fp [open $sdb "r"]
	set data [read -nonewline $fp]
	close $fp
	set lines [expr $lines + [llength [split $data "\n"]]]
 }
 return $lines
}

proc listfiles {dir} {
  if {[string range $dir end end] != "/"} {
    append dir "/"
  }
  set r ""
  set l [glob -nocomplain $dir*]
  foreach f $l {
    if {[file isdirectory $f]} {
      set r [concat $r [listfiles $f]]
    } elseif {[file isfile $f]} {
        lappend r $f
    }
  }
  return $r
}

putlog "Loaded \002total addon v$_totalver\002 by HM2K"
