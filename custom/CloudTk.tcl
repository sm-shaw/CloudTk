
# Copyright (c) 2017 Jeff Smith
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
#       So make the above modifications and then save the following to
#       WebSocketTCP-gateway.tcl and drop in the custom directory.
#

# source any <TkApp>_Crashout.tcl files first.

if {[file isdirectory [file join [file dirname $::Config(starkitTop)] Tk]/]} {
    foreach app [glob [file join [file dirname $::Config(starkitTop)] Tk]/*] {
            if {[file isdirectory $app]} { 
                set Crashout_File [file tail $app]_Crashout.tcl
                set Crashout_Path [file join $app $Crashout_File]
                if {[file exists $Crashout_Path]} {
                    source $Crashout_Path
                }
             }
    }
}

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
#    Doc_AddRoot /kanaka/noVNC [file join $Config(starkitTop) noVNC-1.3.0]
   file copy -force [file join $Config(starkitTop) noVNC-1.4.0] [file join [file dirname $Config(starkitTop)] noVNC]
   Doc_AddRoot /kanaka/noVNC [file join [file dirname $Config(starkitTop)] noVNC]  
}

# Add directory outside of starkit for html pages

if {![file isdirectory [file join [file dirname $Config(starkitTop)] htdocs]]} {
    file mkdir [file join [file dirname $Config(starkitTop)] htdocs]
} 

Mtype_Add .svg image/svg+xml

Url_AccessInstallPrepend ::cloudtk::AccessHook

Url_PrefixInstall /cloudtk [list ::cloudtk::Start /cloudtk]

Url_PrefixInstall / [list ::cloudtk::DocRoot $Doc(root)]

        package require websocket

namespace eval ::cloudtk {
         # ensure ::cloudtk namespace exists
set ::Config(cloudtkVersion) 1.4.0-51
}

proc ::cloudtk::Start {prefix sock suffix} {
        upvar #0 Httpd$sock data
        variable Target

#puts "prefix=$prefix sock=$sock suffix=$suffix"


   set suffix [Url_PathCheck [string trimleft $suffix /]]
   if {![regexp {.*(/)$} $suffix _ slash]} {
     set slash ""
   }

 set noVNCpath {/kanaka/noVNC/$state(noVNC,html)?path=cloudtk/$session&resize=$state(noVNC,resize)&autoconnect=$state(noVNC,autoconnect)&reconnect=$state(noVNC,reconnect)&reconnect_delay=$state(noVNC,reconnect_delay)&shared=$state(noVNC,shared)&view_only=$state(noVNC,view_only)&view_clip=$state(noVNC,view_clip)&quality=$state(noVNC,quality)&compression=$state(noVNC,compression)&show_dot=$state(noVNC,show_dot)&logging=$state(noVNC,logging)&bgc=$state(Xsetroot,bgc)$state(noVNClist)}


if {[info exists ::Session:$suffix]} {
         upvar #0 Session:$suffix state

    if { $state(type) == {WsActive} } {
         Redirect_Self /cloudtk/
    } elseif { $state(type) == {WsSessionApp} } {
         return [::cloudtk::Dynamic $sock $noVNCpath $suffix]
    } elseif { $state(type) == {Crashout} } {
         unset ::Session:$suffix
         Httpd_SockClose $sock 1 Close
    } else {
         return [::cloudtk::Session $sock $suffix]
    }
}


# set noVNCpath {/kanaka/noVNC/$state(noVNC,html)?path=cloudtk/$session&resize=remote&autoconnect=true}

switch -- $suffix {
             "VNC" {
                     ::cloudtk::Dynamic $sock $noVNCpath ""
                   }
          default {
                        append pagehtml "<p>\n"
                        append pagehtml "Launch HammerDB Application.\n<p>\n"
                        append pagehtml "<form action=$data(prefix)/VNC method=POST>\n"
                        append pagehtml "<input type=hidden name=session value=new>\n"
                        append pagehtml "<table>\n"
                        foreach d [lsort -dictionary [glob [file join [file dirname $::Config(starkitTop)] Tk]/*]] {
                                   if {[file isdirectory $d]} {
                                       set Tkapp [file tail $d]
                                       append pagehtml [::html::row $Tkapp "<input type=radio [html::radioValue Tk $Tkapp] checked>"]\n
                                   }
                       }
#                   append pagehtml [::html::row "VNC Host" "<input type=text [html::formValue TCPhost]>"]\n
#                   append pagehtml [::html::row "VNC Port" "<input type=text [html::formValue TCPport]>"]\n
                   append pagehtml "</table>\n<p>\n<p>\n"
                   append pagehtml "<input type=submit>\n<p>\n</form>\n"
                   append pagehtml "</body>\n</html>"
                   Httpd_ReturnData $sock text/html "[::mypage::header "Tk Application"] $pagehtml [mypage::footer]"
                   Httpd_SockClose $sock 1 Close
                  }
          }
}

# ::cloudtk::Session --
#       This procedure control access to the websocket to TCP gateway via a Session ID
#       via a Url query parameter.

proc ::cloudtk::Session {sock session} {
        upvar #0 Httpd$sock data

# To get started register the socket as a websocket server.

        ::websocket::server $sock

# The callback procedure when a message/data is present.

        ::websocket::live $sock /cloudtk [list ::cloudtk::Gateway $session]

# Test the Http headers via data(headerlist) to see if it is a websocket request.

        set wstest [::websocket::test $sock $sock /cloudtk $data(headerlist) $data(query)]

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


# ::cloudtk::Gateway --
#       This procedure is called when the server
#       can read data from the client
#
# Arguments: appended to the callback procedure by the Websocket library.
#       sock    The socket connection to the client
#       type    Type of message either:
#               request (initial connection generated by the websocket library.)
#               connect
#               close
#               disconnect
#               binary
#               text
#               ping
#               pong
#               timeout
#               error
#       msg     message or data
#

proc ::cloudtk::Gateway {session sock type msg} {
         upvar #0 Session:$session state

# Uncomment the following line to view what's being sent from the client.

#puts "Gateway sock=$sock type=$type msg=$msg"


# In Tcl Websocket Library in tcllib there was a change in the type of connection label. In
# Version 1.3.1 the intial connection type was "request" in Version 1.4 it changed to "connect".
# Have kept both incase a different version is used.

          switch $type {
                request {
                         set state(type) WsActive
                         return [::cloudtk::SocketTCP $sock $session $state(TCPhost) $state(TCPport)]
                        }
                connect {
                         set state(type) WsActive
                         return [::cloudtk::SocketTCP $sock $session $state(TCPhost) $state(TCPport)]
                        }
                close { 
                         # Set the state(type) WsInactive if the CloudTk server looses the websocket connection
                         # from the browser due to hitting the back button or reload button or there
                         # is a communication issue. This is a 1001 message. The Xdisplay session
                         # remains open and we re-establish the connection but using a different
                         # websocket.
                         #
                         # If the close is a normal closure due to the Tk app, Window Manager or Xvnc
                         # Server terminating a 1000 message is received. Set the state(type) WsSessionApp.
                         # Then upon hitting the noVNC Connect button or an automatic Reconnect
                         # we will connect to the same TkApp.

                                 if { [lindex $msg 0] == 1001 } {
                                      set state(type) WsInactive
                                      set state(current) [clock seconds]
                                 } elseif { [lindex $msg 0] == 1000 } {
                                      set state(type) WsSessionApp
                                      set state(current) [clock seconds]
                                 }
                        return 
                      }
                disconnect {
                                 if { $state(type) == {WsInactive}&& [string equal 1 $state(Inactive)] } {
                                      if { [file exists $state(TkApp,crashout)] } {
                                           $state(Tk)_Crashout $session
#                                           Xdisplay_Close $state(Xdisplay) Xvnc
                                           ::websocket::close $sock
                                           ::close $state(TCPsock)
#                                           Session_Destroy $session
                                           unset ::Httpd$sock
                                           unset ::websocket::Server_$sock                                           
                                      } else {
                                           ::websocket::close $sock
                                           ::close $state(TCPsock)
                                           unset ::Httpd$sock
                                           unset ::websocket::Server_$sock
                                      }
                                 } elseif { $state(type) == {WsSessionApp} && [string equal 1 $state(SessionApp)] } {
                                      Xdisplay_Close $state(Xdisplay) Xvnc
                                      ::close $state(TCPsock) 
                                      unset ::Httpd$sock
                                      unset ::websocket::Server_$sock   
                                 } else {
                                      Xdisplay_Close $state(Xdisplay) Xvnc
                                      ::close $state(TCPsock)
                                      Session_Destroy $session
                                      unset ::Httpd$sock
	                              unset ::websocket::Server_$sock 
                                 }
                            return
                           }
                binary {
                        set ::X${state(Xdisplay)}(IdleStart) 0
                        puts -nonewline $state(TCPsock) $msg
                        return
                       }
                text {
                      return
                     }
                ping {
                      Xdisplay_Reap
                      Xdisplay_SessionReap 90 WsInit
                      Xdisplay_SessionReap $state(InactiveTime) WsInactive
                      Xdisplay_SessionReap $state(SessionAppTime) WsSessionApp
                      Xdisplay_SessionReap 1 Crashout
                          if {$state(idletime) > 0} {
                              Xdisplay_IdleTime $state(Xdisplay) $state(idletime)
                          }
                      return
                     }
                pong {
                      Xdisplay_Reap
                      Xdisplay_SessionReap 90 WsInit
                      Xdisplay_SessionReap $state(InactiveTime) WsInactive
                      Xdisplay_SessionReap $state(SessionAppTime) WsSessionApp
                      Xdisplay_SessionReap 1 Crashout
                          if {$state(idletime) > 0} {
                              Xdisplay_IdleTime $state(Xdisplay) $state(idletime)
                          }
                      return
                     }
                timeout {
                         return
                        }
                error {
                       return 
               }
        }
}

# ::cloudtk::SocketTCP --
#       This procedure connect via socket -async to the TCP host port.

proc ::cloudtk::SocketTCP {sock session TCPhost TCPport} {
      upvar #0 Session:$session state

         set state(TCPsock) [socket -async $TCPhost $TCPport]

         set error [fconfigure $state(TCPsock) -error]

         # If the Xvnc server is not ready we get a "connection refused"
         # so wait 10ms and try again.
         while { $error == "connection refused" } {
                 close $state(TCPsock)
                 after 10
                 set state(TCPsock) [socket -async $TCPhost $TCPport]
                 set error [fconfigure $state(TCPsock) -error]
#puts TCPsockConnectionRefusedX=$error
         }

         fconfigure $state(TCPsock) -translation binary -blocking off -buffering none
         fileevent $state(TCPsock) r [list ::cloudtk::ReceiveTCP $sock $session $state(TCPsock)]

#puts TCPsock=$error
}

# ::cloudtk::ReceiveTCP --
#       This procedure receives data on the TCP socket and then
#       resends it on the websocket via ::websocket::send

proc ::cloudtk::ReceiveTCP {sock session TCPsock} {
      upvar #0 Session:$session state

#     set error [fconfigure $state(TCPsock) -error]

     if {[eof $state(TCPsock)]} {
         ::websocket::close $sock
     } else {
         ::websocket::send $sock binary [read $state(TCPsock)]
     }
}

# ::cloudtk::Dynamic ---
# This procedure is run when a Host and Port is configured in the form. It checks
# to make sure that the previous page was a referer page from same server or 
# source you configure.
# It checks a valid Session ID is created and not a crafted Session ID.
# Tests the Host and Port are valid before establishing the WebSocket and
# the TCP connection.

proc ::cloudtk::Dynamic {sock urlRedirect session} {
        upvar #0 Httpd$sock data

         if { [info exists ::Session:$session]} {
                upvar #0 Session:$session state

                    set state(Xdisplay) [Xdisplay_Start 50 $session]
                    set state(TCPhost) 127.0.0.1
                    set state(TCPport) [expr {5900 + $state(Xdisplay)}]
                    set state(type) WsInit
                    Httpd_AddHeaders $sock Cache-Control no-transform
                    return [::cloudtk::Session $sock $session]
        } else {

                set session [Session_Match [Url_DecodeQuery $data(query)] WsInit {} 0]

                if {$session eq ""} {
                    Httpd_ReturnData $sock text/html "<br><h2><b>Error message = Not a valid Session ID</b></h2>"
                    Httpd_SockClose $sock 1 Close
                } else {
                    upvar #0 Session:$session state
#                    Xdisplay_SessionReap 90 WsInit

                    foreach {name value} [Url_DecodeQuery $data(query)] {
                             if {[string match $name session] == 1 } {
                                 continue
                             } else {
                                 set state($name) $value
                             }
                    }

                    set state(TkApp,dir) [file join [file dirname $::Config(starkitTop)] Tk $state(Tk)]
                    if {![file isdirectory $state(TkApp,dir)]} {
                        Httpd_ReturnData $sock text/html "<br><h2><b>Error message = Not a valid Tk Applcation name</b></h2>"
                        Httpd_SockClose $sock 1 Close                     
                    } else {
                        set state(TkApp,config) [file join $state(TkApp,dir) $state(Tk).conf]
                        # Check if a per App config file exists else use CloudTk.conf
                        if {[file exists $state(TkApp,config)]} {
                            ::cloudtk::Init $state(TkApp,config) state $session
                        } else {
                            ::cloudtk::Init $::Config(cloudtk,config) state $session
                        }

                        set state(TkApp,crashout) [file join $state(TkApp,dir) $state(Tk)_Crashout.tcl]

                        if {[file exists [file join $state(TkApp,dir) $state(Tk)_vnc.html]]} {
                            file copy -force [file join $state(TkApp,dir) $state(Tk)_vnc.html] [file join [file dirname $::Config(starkitTop)] noVNC] 
                            set state(noVNC,html) $state(Tk)_vnc.html
                        }
                        set state(Xdisplay) [Xdisplay_Start 50 $session]
                        set state(TCPhost) 127.0.0.1
                        set state(TCPport) [expr {5900 + $state(Xdisplay)}]
                        Httpd_AddHeaders $sock Cache-Control no-transform
                        Redirect_Self [subst $urlRedirect]
                   }
                }
        }
}

# cloudtk::Init --
#
#       Get the list of resources from CloudTk.conf or <TkApp>.conf file.
#       This is inspired by the way TclHttpd processes the tclhttpd.rc file.
#
# Arguments:
#       config          The name of the configuration file (optional)
#       aname           Name of array containing default configuration
#                       values on input, and the new values after
#                       processing the config file. It won't overwrite
#                       any default configuration values even if the same
#                       variable with a different value is in the 
#                       configuration file.
#
# Side Effects:
#       It appends the config parameters to the Sessions state array
#       from the configuration file.

proc cloudtk::Init {config aname session} {
     upvar 1 $aname TheirConfig
     upvar #0 Session:$session state

    if {[catch {open $config} in]} {
        return -code error "Cannot read configuration file \"$config\"\nError: $in"
    }
    set X [read $in]
    close $in

    # Load the file into a safe interpreter that just creates state array

    set i [interp create -safe]
    if {$::tcl_version >= 8.5} {
      namespace ensemble create -command ::SafeFile -map {
        isdirectory {::file isdirectory}
        exists      {::file exists}
        join        {::file join}
        dirname     {::file dirname}
      }
      $i alias file SafeFile
    } else {
      interp expose $i file
    }
    $i alias fileutil::tempdir ::fileutil::tempdir

    # Create the slave's state array, then source the CloudTk/TkApp config script

    interp eval $i [list array set state [array get TheirConfig]]

    interp eval $i {
        proc state {name {value {}}} {
            global state
            if {![info exist state($name)]} {
                set state($name) $value
            } elseif {[string match *,exec $name] || [string match *,ON $name] } {
                set state($name) $value
            } else {
                set state($name)
            }
        }
    }
    if {[catch {interp eval $i $X} err]} {
        return -code error "Error in configuration file \"$config\"\n:Error: $err"
    }
    array set state [interp eval $i {array get state}]
    interp delete $i
    

    # Combine all the (noVNCargs,*) that are query parameters to the noVNClist variable
    # so this can be appended to the noVNCpath URL.

    set state(noVNClist) {}
    foreach {index value} [array get state] {
        if {[string match "noVNCargs,*" $index]} {
            set k [lindex [split $index ","] 1]
            append state(noVNClist) &${k}=$value
        }
    }
}

proc ::cloudtk::DocRoot {prefix sock suffix} {
        upvar #0 Httpd$sock data

     set htdocsOut [file join [file dirname $::Config(starkitTop)] htdocs]
     set htdocsIn [file join $::Config(home) ../htdocs]
     set indexTml [file join $htdocsOut index.tml]
     set indexHtml [file join $htdocsOut index.html]
     set indexHtm [file join $htdocsOut index.htm]

     if { $suffix == "" } {
          if { [file exists $indexTml] || [file exists $indexHtml] || [file exists $indexHtm] } {
               DocDomain $prefix $htdocsOut $sock $suffix
          } else {
               DocDomain $prefix $htdocsIn $sock $suffix
          }
     } elseif { [file exists [file join $htdocsOut $suffix]] } {
          DocDomain $prefix $htdocsOut $sock $suffix
     } else {
          DocDomain $prefix $htdocsIn $sock $suffix
     }
}

source [file join $::Config(home) ../custom CloudTk.Auth]
#source [file join $::Config(home) ../custom CloudTk.TkPool]

# Generate the Auth file.
::cloudtk::AuthTarget

# Generate TkPool
#::cloudtk::TkPool

# Location of CloudTk.conf outside of Starkit which can be customised.
set Config(cloudtk,config) [file join [file dirname $Config(starkitTop)] Tk CloudTk.conf]
#
# Location of default CloudTk.conf file which is copied out of the Starkit.
set Config(cloudtk,custom) [file join $::Config(home) ../custom]/CloudTk.conf

if {![file exists $Config(cloudtk,config)]} {
    file copy -force $Config(cloudtk,custom) $Config(cloudtk,config)
}

