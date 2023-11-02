# Copyright (c) 2015 Jeff Smith 
#
# See the file "license.terms" of TclHttpd for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#
# I made a few modifications to the Websocket library to make it work with TclHttpd.
#
#       1. In the procedure ::websocket::takeover changed the following line from
#          fconfigure $sock -translation binary -blocking on
#          to
#          fconfigure $sock -translation binary -blocking off
#
#
#       2. In the procedure ::websocket::Receiver changed the following line from
#          binary scan $dta Iu mask
#          to
#          binary scan $dta I mask
#
#       Without this change the intial handshake with the VNC or Telnet Server
#       was intermittent ie. did not connect.
#
#	So make the above modifications and then save the following to 
#	WebSocketTCP-gateway.tcl and drop in the custom directory.
#

# Setup the AuthUserFile and copy the default webmaster credentials to the file
# outside the Starkit.

if {![file exists $Config(AuthUserFile)]} {
    set fd [open $Config(AuthUserFile) w]
    puts $fd "webmaster:$authdefault(user,webmaster)"
    close $fd
    unset fd
}


# If the user is Upgrading noVNC by creating a noVNC directory outside the Starkit,
# remap this new directory via Doc_AddRoot.
#
# The Config(starkitTop) array variable is defined in the main.tcl file of the
# Starkit and is used by the startup scripts of TclHttpd to define certain paths.

if {[file isdirectory [file join [file dirname $Config(starkitTop)] noVNC]]} {
    Doc_AddRoot /kanaka/noVNC [file join [file dirname $Config(starkitTop)] noVNC]
} else {
    Doc_AddRoot /kanaka/noVNC [file join $Config(starkitTop) kanaka-noVNC-b804b3e]
}


Url_AccessInstallPrepend ::websockit2me::AccessHook

Url_PrefixInstall /websockit2me [list ::websockit2me::Start /websockit2me]

	package require websocket

namespace eval ::websockit2me {
 	 # ensure ::websockit2me namespace exists
set ::Config(websockit2meVersion) 0.1.3
}

proc ::websockit2me::Start {prefix sock suffix} {
        upvar #0 Httpd$sock data
        variable Target

   set suffix [Url_PathCheck [string trimleft $suffix /]]
   if {![regexp {.*(/)$} $suffix _ slash]} {
     set slash ""
   }

if {[info exists ::Session:$suffix]} {
    return [::websockit2me::Session $sock $suffix]
} 


set noVNCpath {/kanaka/noVNC/vnc.html?path=websockit2me/$session}
set Telnetpath {/kanaka/wstelnet.tml?session=$session}

switch -- $suffix {
             "VNC" {
                     ::websockit2me::Dynamic $sock $noVNCpath
                   }
          "Telnet" {
                     ::websockit2me::Dynamic $sock $Telnetpath
                   }
          "Vtoken" {
                     ::websockit2me::Token $sock $noVNCpath VNC
                   }
          "Ttoken" {
                     ::websockit2me::Token $sock $Telnetpath Telnet
                   }
          default {
	           append pagehtml "<p>\n"
                   append pagehtml "Enter the VNC Server Host(or IP Address) and the Port you wish to connect too.\n<p>\n"
	           append pagehtml "<form action=$data(prefix)/VNC method=POST>\n"
	           append pagehtml "<input type=hidden name=session value=new>\n"
                   append pagehtml "<table>\n"
	           append pagehtml [::html::row "VNC Host" "<input type=text [html::formValue TCPhost]>"]\n 
	           append pagehtml [::html::row "VNC Port" "<input type=text [html::formValue TCPport]>"]\n
                   append pagehtml "</table>\n<p>\n<p>\n"
                   append pagehtml "<input type=submit>\n<p>\n</form>\n"
                   append pagehtml "<p>\n<b>OR</b>\n<p>\n"
                   append pagehtml "Enter the Telnet Server Host(or IP Address) and the Port you wish to connect too.\n<p>\n"
                   append pagehtml "<form action=$data(prefix)/Telnet method=POST>\n"
                   append pagehtml "<input type=hidden name=session value=new>\n"
                   append pagehtml "<table>\n<p>\n<p>\n"
                   append pagehtml [::html::row "Telnet Host" "<input type=text [html::formValue TCPhost]>"]\n
                   append pagehtml [::html::row "Telnet Port" "<input type=text [html::formValue TCPport]>"]\n
                   append pagehtml "</table>\n<p>\n<p>\n"
                   append pagehtml "<input type=submit>\n<p></form>\n"
                   append pagehtml "</body>\n</html>" 
	           Httpd_ReturnData $sock text/html "[::mypage::header "Select TCP/IP Hosts"] $pagehtml [mypage::footer]"
                  }
          }
}

# ::websockit2me::Session --
#       This procedure control access to the websocket to TCP gateway via a Session ID
#       via a Url query parameter. 

proc ::websockit2me::Session {sock session} {
	upvar #0 Httpd$sock data

# To get started register the socket as a websocket server.
 
	::websocket::server $sock

# The callback procedure when a message/data is present.

	::websocket::live $sock /websockit2me [list ::websockit2me::Gateway $session]

# Test the Http headers via data(headerlist) to see if it is a websocket request.

	set wstest [::websocket::test $sock $sock /websockit2me $data(headerlist) $data(query)]

# If ::websocket::test returns 1 it's a valid websocket request so suspend the Http request
# in TclHtppd. Let the websocket library return the correct Http headers via the
# ::websocket::upgrade and take control.

	if {$wstest == 1} { 
	    Httpd_Suspend $sock 0
	    ::websocket::upgrade $sock
        } else {
            Httpd_ReturnData $sock text/html "Not a valid Websocket connection!" 
        }
}

	
# ::websockit2me::Gateway --
#	This procedure is called when the server
#	can read data from the client
#
# Arguments: appended to the callback procedure by the Websocket library.
#	sock	The socket connection to the client
#	type	Type of message either:
#		request (initial connection generated by the websocket library.)
#		close
#		disconnect
#		binary
#		text
#	msg	message or data
#
	
proc ::websockit2me::Gateway {session sock type msg} {
         upvar #0 Session:$session state

# Uncomment the following line to view what's being sent from the client.

#puts "Gateway sock=$sock type=$type msg=$msg"


# In Tcl Websocket Library in tcllib there was a change in the type of connection label. In
# Version 1.3.1 the intial connection type was "request" in Version 1.4 it changed to "connect".
# Have kept both incase a different version is used. 

	  switch $type { 
		request {
                         set state(type) WsActive
                         return [::websockit2me::SocketTCP $sock $session $state(TCPhost) $state(TCPport)]
                        } 
                connect {
                         set state(type) WsActive
                         return [::websockit2me::SocketTCP $sock $session $state(TCPhost) $state(TCPport)]
                        }
		close { return } 
    		disconnect { 
                            close $state(TCPsock)
                            Session_Destroy $session
                            unset ::Httpd$sock
                            return
                           }   
    		binary { 
                        puts -nonewline $state(TCPsock) $msg
                        return
                       }
    		text { 
                      return
    		} 
	}
}

# ::websockit2me::SocketTCP --
#       This procedure connect via socket -async to the TCP host port.

proc ::websockit2me::SocketTCP {sock session TCPhost TCPport} {
      upvar #0 Session:$session state


         set state(TCPsock) [socket -async $TCPhost $TCPport]
         fconfigure $state(TCPsock) -translation binary -blocking off -buffering none
         fileevent $state(TCPsock) r [list ::websockit2me::ReceiveTCP $sock $session $state(TCPsock)]
}

# ::websockit2me::ReceiveTCP --
#       This procedure receives data on the TCP socket and then
#       resends it on the websocket via ::websocket::send

proc ::websockit2me::ReceiveTCP {sock session TCPsock} {
      upvar #0 Session:$session state

     set error [fconfigure $state(TCPsock) -error]

     if {$error ne ""} {
         ::websocket::close $sock
     } elseif {[eof $state(TCPsock)]} {
         ::websocket::close $sock
     } else {
         ::websocket::send $sock binary [read $state(TCPsock)] 
     }
}

# ::websockit2me::Auth --
#       This procedure is used in the callback of the .tclaccess
#       files.

proc ::websockit2me::Auth {sock realm user pass} {

     set file [file join $::Config(docRoot) websockit2me .tclaccess]
     set ::auth${file}(htaccessp,userfile) $::Config(AuthUserFile) 
     # now check the Basic credentials
     set crypt [AuthGetPass $sock $file $user]
     set salt [string range $crypt 0 1]
     set crypt2 [crypt $pass $salt]
     if {[string compare $crypt $crypt2] != 0} {
         return 0        ;# Not the right password
     } else {
         return 1
     }
}

# ::websockit2me::AccessHook --
#       This procedure is used via Url_AccessInstallPrepend to change
#       the default behaviour of the authentication. It check if the
#       the url starts with /websockit2me or /kanaka and allows access
#       based on what is set in the AuthTargetFile.txt file. 

proc ::websockit2me::AccessHook {sock url} {
    global Doc
    upvar #0 Httpd$sock data
    variable Target

    if {![string equal [file mtime $Target(VNCTargetFile,file)] $Target(VNCTargetFile,mtime)]} {
        ::websockit2me::VNCTarget 
    }
    if {![string equal [file mtime $Target(TelnetTargetFile,file)] $Target(TelnetTargetFile,mtime)]} {
        ::websockit2me::TelnetTarget
    }
    if {![string equal [file mtime $Target(AuthTargetFile,file)] $Target(AuthTargetFile,mtime)]} {
        ::websockit2me::AuthTarget
    }

    # Make sure the path doesn't sneak out via ..
    # This turns the URL suffix into a list of pathname components

    if {[catch {Url_PathCheck $data(suffix)} data(pathlist)]} {
        Doc_NotFound $sock
        return denied
    }

    # Figure out the directory corresponding to the domain, taking
    # into account other document roots.

    if {[regexp {^(/websockit2me|/kanaka|/favicon.ico)} $url]} {
        set directory [file join $Doc(root,/) websockit2me]

        set suffix [Url_PathCheck [string trimleft $data(suffix) /]]
        if {![regexp {.*(/)$} $suffix _ slash]} {
            set slash ""
        }
        if {$Target(AuthTargetFile,VNC) == 0} {
            if {[regexp {^(/websockit2me/Vtoken|/kanaka/noVNC/|/favicon.ico)} $url]} {
                return ok
            } elseif {[info exists ::Session:$suffix]} {
                return ok
            }

        }
        if {$Target(AuthTargetFile,Telnet) == 0} {
            if {[regexp {^(/websockit2me/Ttoken|/kanaka/wstelnet.tml|/kanaka/noVNC/|/kanaka/include/|/favicon.ico)} $url]} {
                return ok
            } elseif {[info exists ::Session:$suffix]} {
                return ok
            }    
        }

        # Look for .tclaccess file in websockit2me directory.
        # This controls access to websockit2me and kanaka
        # directories.
        set cookie [Auth_Check $sock $directory ""]

        # Finally, check access
        if {![Auth_Verify $sock $cookie]} {
            return denied
        } else {
            return skip
        }
     } elseif {[regexp {^(/debug|/status)} $url]} {
               return skip
     } elseif {[regexp {^(/)} $url]} {
           if {$Target(AuthTargetFile,Website) == 0} {
               return ok
           } else {
               return skip
           }
     } else {
        return skip
     }
}

# ::websockit2me::TelnetTarget --
#       This procedure sets up  the Telnet Target file and gets its contents
#       into an array. If the file doesn't exist it set a default of
#       "token1 127.0.0.1 23".

proc ::websockit2me::TelnetTarget {} {
     variable Target

     set Target(TelnetTargetFile,file) [file join [file dirname $::Config(starkitTop)] auth TelnetTarget.txt]

     if {![file exists $Target(TelnetTargetFile,file)]} {
         set fd [open $Target(TelnetTargetFile,file) w]
         puts $fd "token1 127.0.0.1 23"
         close $fd
         unset fd
         set Target(TelnetTargetFile,token1) "127.0.0.1 23"
         set Target(TelnetTargetFile,mtime) [file mtime $Target(TelnetTargetFile,file)]
     } else {
         set Target(TelnetTargetFile,mtime) [file mtime $Target(TelnetTargetFile,file)]
         set fd [open $Target(TelnetTargetFile,file) r]
         while {[gets $fd line] >= 0} {
                set Target(TelnetTargetFile,[lindex $line 0]) "[lrange $line 1 2]"
         }
         close $fd
         unset fd
     }
}

# ::websockit2me::VNCTarget --
#       This procedure sets up  the VNC Target file and gets its contents
#       into an array. If the file doesn't exist it set a default of
#       "token1 127.0.0.1 5900".

proc ::websockit2me::VNCTarget {} {
     variable Target

     set Target(VNCTargetFile,file) [file join [file dirname $::Config(starkitTop)] auth VNCTarget.txt]

     if {![file exists $Target(VNCTargetFile,file)]} {
         set fd [open $Target(VNCTargetFile,file) w]
         puts $fd "token1 127.0.0.1 5900"
         close $fd
         unset fd
         set Target(VNCTargetFile,token1) "127.0.0.1 5900"
         set Target(VNCTargetFile,mtime) [file mtime $Target(VNCTargetFile,file)]
     } else {
         set Target(VNCTargetFile,mtime) [file mtime $Target(VNCTargetFile,file)]
         set fd [open $Target(VNCTargetFile,file) r]
         while {[gets $fd line] >= 0} {
                set Target(VNCTargetFile,[lindex $line 0]) "[lrange $line 1 2]"
         }
         close $fd
         unset fd
     }
}

# ::websockit2me::AuthTarget --
#       This procedure sets up  the Auth Target file and gets its contents
#       into an array. If the file doesn't exist it sets some defaults.

proc ::websockit2me::AuthTarget {} {
     variable Target

     set Target(AuthTargetFile,file) [file join [file dirname $::Config(starkitTop)] auth AuthTarget.txt]

     if {![file exists $Target(AuthTargetFile,file)]} {
         set fd [open $Target(AuthTargetFile,file) w]
         puts $fd "VNC 0"
         puts $fd "Telnet 1"
         puts $fd "Website 0"
         close $fd
         unset fd
         set Target(AuthTargetFile,VNC) "0"
         set Target(AuthTargetFile,Telnet) "1"
         set Target(AuthTargetFile,Website) "0"
         set Target(AuthTargetFile,mtime) [file mtime $Target(AuthTargetFile,file)]
     } else {
         set Target(AuthTargetFile,mtime) [file mtime $Target(AuthTargetFile,file)]
         set fd [open $Target(AuthTargetFile,file) r]
         while {[gets $fd line] >= 0} {
                set Target(AuthTargetFile,[lindex $line 0]) "[lindex $line 1]"
         }
         close $fd
         unset fd
     }
}

# ::websockit2me::Dynamic ---
# This procedure is run when a Host and Port is configured in the form. It checks
# to make sure that the previous page was a referer page from the same server.
# It checks a valid Session ID is created and not a crafted Session ID.
# Tests the Host and Port are valid before establishing the WebSocket and
# the TCP connection.

proc ::websockit2me::Dynamic {sock urlRedirect} {
        upvar #0 Httpd$sock data


        set hostSelf [lindex $data(self) 0]://$data(mime,host)/websockit2me/
        if {[info exists data(mime,referer)]} {
            if {$hostSelf ne $data(mime,referer)} {
                Httpd_ReturnData $sock text/html "<br><h2><b>Error message = I hear you knocking but you can't come in!</b></h2>"
            } else {
                set session [Session_Match [Url_DecodeQuery $data(query)] WsInit {} 0]
                if {$session eq ""} {
                    Httpd_ReturnData $sock text/html "<br><h2><b>Error message = Not a valid Session ID</b></h2>"
                } else {
                    upvar #0 Session:$session state
                    Session_Reap 300 WsInit

                    # Check whether the connection is "https" or not.
                    # Sets state(encrypt) variable so it can be used in the wstelnet.tml page to
                    # determine if the Javascript Telnet Client should establish a ws:// or wss://
                    # WebSocket connection.

                    if {[string match -nocase [lindex $data(self) 0] "https"]} {
                        set state(encrypt) true
                    } else {
                        set state(encrypt) {}
                    }
                    foreach {name value} [Url_DecodeQuery $data(query)] {
                             if {[string match $name session] == 1 } {
                                 continue
                             } else {
                                 set state($name) $value
                             }
                    }
                    set sockinfo [catch {socket $state(TCPhost) $state(TCPport)} sockerr]
                    if {$sockinfo eq 0} {
                        catch {close $sockinfo}
                        Redirect_Self [subst $urlRedirect]
                    } else {
                        Httpd_ReturnData $sock text/html "<br><h2><b>Error message = $sockerr</b></h2>"
                        Session_Destroy $session
                    }
                }
            }
        } else {
          Httpd_ReturnData $sock text/html "<br><h2><b>Error message = I hear you knocking but you can't come in!</b></h2>"
        }
}

# ::websockit2me::Token ---
# Similar to ::websockit2me::Dynamic above. Check for valid
# Session ID and valid token from the Url query string.

proc ::websockit2me::Token {sock urlRedirect targetType} {
        upvar #0 Httpd$sock data
        variable Target 

        set session [Session_Match [Url_DecodeQuery $data(query)] WsInit {} 0]
        if {$session eq ""} {
            Httpd_ReturnData $sock text/html "<br><h2><b>Error message = Not a valid Session ID</b></h2>"
        } else {
            upvar #0 Session:$session state
            Session_Reap 300 WsInit

            # Check whether the connection is "https" or not.
            # Sets state(encrypt) variable so it can be used in the wstelnet.tml page to
            # determine if the Javascript Telnet Client should establish a ws:// or wss://
            # WebSocket connection.

            if {[string match -nocase [lindex $data(self) 0] "https"]} {
                set state(encrypt) true
            } else {
                set state(encrypt) {}
            }

            set iT 1
            set queryStringT {}
            foreach {name value} [Url_DecodeQuery $data(query)] {
                     if {[string match $name session] && $iT } {
                         incr iT
                         continue
                     } elseif {[string match $name token] && [string match $iT 2]} {
                         if {[info exists Target(${targetType}TargetFile,$value)]} {
                             set state(TCPhost) [lindex $Target(${targetType}TargetFile,$value) 0]
                             set state(TCPport) [lindex $Target(${targetType}TargetFile,$value) 1]
                             incr iT
                         } else {
                             Httpd_ReturnData $sock text/html "<br><h2><b>Error message = No Token defined for \"$value\"</b></h2>"
                             Session_Destroy $session
                         }
                     } else {
                         append queryStringT "&$name=$value"
                     }
            }
            set sockinfo [catch {socket $state(TCPhost) $state(TCPport)} sockerr]
            if {$sockinfo eq 0} {
                catch {close $sockinfo}
                Redirect_Self [subst $urlRedirect]$queryStringT
            } else {
                Httpd_ReturnData $sock text/html "<br><h2><b>Error message = $sockerr</b></h2>"
                Session_Destroy $session
            }
         }
}

# Generate the Auth, Telnet and VNC Target files.

::websockit2me::TelnetTarget
::websockit2me::VNCTarget
::websockit2me::AuthTarget

