#tinyurl expansion for rss-synd.tcl
#@see http://forum.egghelp.org/viewtopic.php?p=66327#66327
proc ::rss-synd::tinyurl {url} {
  #tinyurls are currently 26 chars at most
  if {[string length $url] <= 26} { return $url; } 
  set tinyurl "http://tinyurl.com/api-create.php";
  set query [::http::formatQuery "url" $url]; 
  # since this connection is synchronous and blocks
  #  the timeout should be relatively small. 
  set token [::http::geturl "$tinyurl?$query" -timeout 5000]; 
  set url [::http::data $token]; 
  ::http::cleanup $token; 
  return $url; 
}
#reddit shortlink expansion for rss-synd.tcl
#@see http://www.reddit.com/r/announcements/comments/eorhm/reddit_30_less_typing/c19v1hj?context=3
proc ::rss-synd::reddit {url} { 
	if {[string length $url] <= 22} { return $url; }
  set regex {http://www.reddit.com/r/\w+/comments/(\w+)/\w+/?};
  regsub -all $regex $url "http://redd.it/\\1" url;
  return $url;
}
#youtube shortlink expansion for rss-synd.tcl
proc ::rss-synd::youtube {url} {
	if {[string length $url] <= 27} { return $url; }
  set regex {http://www.youtube.com/watch?v=(\w+)};
  regsub -all $regex $url "http://youtu.be/\\1" url;
  return $url;
}
#shortlink expansion for rss-synd.tcl
#   using the above processes to form a short link
proc ::rss-synd::shortlink {url} { 
  set url [::rss-synd::reddit $url];
  set url [::rss-synd::youtube $url];
  set url [::rss-synd::tinyurl $url];
  return $url;
}
