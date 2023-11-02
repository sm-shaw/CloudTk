
# Copyright (c) 2017 Jeff Smith
#
# See the file "license.terms" of TclHttpd for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#

package require bgexec

# Xdisplay_Start --
#
# The purpose of the below procedure is to manage the X display number used
# when an Xvnc server is launched. Once the X display is lauched the Tk
# application and a Window Manager(if needed) is started that use the same X display.
# It also does checks to make sure that it won't use an active X display 
# otherwise Xvnc won't start.
#
# Bgexec is used to launch the Xvnc server, Tk application and Window
# Manager as a background process.

proc Xdisplay_Start {{Xdisplay 1} session} {
     upvar #0 Session:$session state

     set Xincr 1
     while {$Xincr == 1} {
            if {[info exists ::X${Xdisplay}] || [file exists /tmp/.X${Xdisplay}-lock] || [file exists /tmp/.X11-unix/X$Xdisplay]} {
                incr Xdisplay
            } else {
                set ::X${Xdisplay}(Session) Session:$session
                set state(TCPhost) 127.0.0.1
                set state(TCPport) [expr {5900 + $Xdisplay}]
                set state(Xdisplay) $Xdisplay
                set ::X${Xdisplay}(Start) [clock seconds]
                set ::X${Xdisplay}(XvncClose) 0
                trace variable ::X${Xdisplay}(XvncClose) aw "Xdisplay_Close $Xdisplay Xvnc"
                set ::X${Xdisplay}(TkClose) 0
                trace variable ::X${Xdisplay}(TkClose) aw "Xdisplay_Close $Xdisplay Tk"
                set ::X${Xdisplay}(WmClose) 0
                trace variable ::X${Xdisplay}(WmClose) aw "Xdisplay_Close $Xdisplay Wm"
		set ::X${Xdisplay}(XvncPid) [bgexec ::X${Xdisplay}(XvncClose) -killsignal SIGTERM -linebuffered true -onerror "Xdisplay_XvncStart $Xdisplay $session" $state(Xvnc,exec) :$Xdisplay -geometry $state(Xvnc,geometry) -fp $state(Xvnc,fp) -localhost -desktop $state(Tk) SecurityTypes=$state(Xvnc,SecurityTypes) &]
                set Xincr 0
                
            }
     }
     Xdisplay_Reap
     Xdisplay_SessionReap 90 WsInit
     Xdisplay_SessionReap $state(InactiveTime) WsInactive
     Xdisplay_SessionReap $state(SessionAppTime) WsSessionApp
     Xdisplay_SessionReap 1 Crashout
     return $Xdisplay
}


# Xdisplay_Close --
#
# The purpose of the below procedure is to close all the processes associated
# with an X display. This is called once the process dies or we kill it
# and a trace variable is triggered. Setting the trace variable will kill
# the process under the control of bgexec.

proc Xdisplay_Close {Xdisplay type args} {
          upvar #0 X$Xdisplay Xstate

     switch $type {
                   Xvnc  {
                          set Xstate(TkClose) 1
                          set Xstate(WmClose) 1
                          set Xstate(XvncClose) 1
                   }
                   Tk {
                          set Xstate(WmClose) 1
                          set Xstate(XvncClose) 1                          
                   }
                   Wm {
                          set Xstate(TkClose) 1
                          set Xstate(XvncClose) 1  
                   }
     }
}


# Xdisplay_Reap --
#
# The purpose of the procedure below is to clean up any X display variable
# that still exist in TclHttpd but no longer have an active X display. This
# produre is called after a new X display is started in Xdisplay_Start

proc Xdisplay_Reap {} {

     foreach xd [info globals X*] {
         upvar #0 $xd Xstate

         if {[info exists Xstate(XvncClose)]} {
              if {[string equal 0 $Xstate(XvncClose)] || [string equal 1 $Xstate(XvncClose)]} {
#puts "[subst $xd](XvncClose)=$Xstate(XvncClose)"
              } else {
                   set Xstate(XvncClose) 1
                   set Xstate(WmClose) 1
                   set Xstate(TkClose) 1
               }
         } else {
              set Xstate(XvncClose) 1
              set Xstate(WmClose) 1
              set Xstate(TkClose) 1
         }
         if {[info exists Xstate(WmClose)]} {
              if {[string equal 0 $Xstate(WmClose)] || [string equal 1 $Xstate(WmClose)]} {
#puts "[subst $xd](WmClose)=$Xstate(WmClose)"
              } else {
                   set Xstate(XvncClose) 1
                   set Xstate(WmClose) 1
                   set Xstate(TkClose) 1
               }
         } else {
              set Xstate(XvncClose) 1
              set Xstate(WmClose) 1
              set Xstate(TkClose) 1
         }
         if {[info exists Xstate(TkClose)]} {
              if {[string equal 0 $Xstate(TkClose)] || [string equal 1 $Xstate(TkClose)]} {
#puts "[subst $xd](TkClose)=$Xstate(TkClose)"
              } else {
                   set Xstate(XvncClose) 1
                   set Xstate(WmClose) 1
                   set Xstate(TkClose) 1
               }
         } else {
              set Xstate(XvncClose) 1
              set Xstate(WmClose) 1
              set Xstate(TkClose) 1
         }
         if { !([string equal 0 $Xstate(TkClose)] && [string equal 0 $Xstate(WmClose)] && [string equal 0 $Xstate(XvncClose)]) } {
#puts "[subst $xd] Not=0and0and0"
              set Xstate(XvncClose) 1
              set Xstate(WmClose) 1
              set Xstate(TkClose) 1
         }
         if { [string equal 1 $Xstate(TkClose)] && [string equal 1 $Xstate(WmClose)] && [string equal 1 $Xstate(XvncClose)] } {
              Stderr "Reaping Xdisplay variable $xd"
#puts "Reaping Xdisplay variable $xd"
              unset Xstate
        }
     }
}


# Destroy all sessions older than a certain age (in seconds)
#    age:  time (in seconds) since the most recent access
#    type: a regexp to mach session types with (defaults to all)

proc Xdisplay_SessionReap {age {type .*}} {
    foreach id [info globals Session:*] {
        upvar #0 $id session
        set old [expr {[clock seconds] - $age}]
        if { [info exists session(type)] } {
             if {[regexp -- $type $session(type)] && $session(current) < $old} {
                 catch {interp delete $session(interp)}
                 Stderr "Reaping session $id"
                 if { [info exists session(Xdisplay)] } {
                      upvar #0 X$session(Xdisplay) Xstate
                      if { [info exists Xstate(Session)] } {
                           if { $Xstate(Session) == $id } {
                                Xdisplay_Close $session(Xdisplay) Xvnc
                           }
                      }
                 }
              unset session
              }
        } else {
           unset session
        }
    }
}



# The purpose of this procedure is to start the Window Manager and the Tk app after
# the Xvnc server is started. Otherwise there will not be an X display available therefore
# the Window Manager and Tk app will error and won't start.

proc Xdisplay_XvncStart {Xdisplay session data} {
	     upvar #0 Session:$session state	

# Wait until Xdisplay has started before loading Tk app and Window Manager
     if {[string match "*Listening for VNC connections on * port *" $data]} {
         if {$state(Xsetroot,ON)} {
             exec $state(Xsetroot,exec) -display :$Xdisplay -solid $state(Xsetroot,bgc) -cursor_name {*}$state(Xsetroot,cursor_name)
         }
         if {$state(Wm,ON)} {
             set ::X${Xdisplay}(WmPid) [bgexec ::X${Xdisplay}(WmClose) -killsignal SIGTERM /usr/bin/matchbox-window-manager -display :$Xdisplay -use_titlebar $state(Wm,use_titlebar) &]
         }
         set Tkarglist {}
         foreach {index value} [array get state] {
               if {[string match "TkArgs,*" $index]} {
                   set j [lindex [split $index ","] 1]
                   lappend Tkarglist -[string tolower $j] $value
               }
         }
         set ::X${Xdisplay}(TkPid) [bgexec ::X${Xdisplay}(TkClose)\
              -input ::Session:${session}(Bgexec,input)\
              -lastoutput ::Session:${session}(Bgexec,lastoutput)\
              -lasterror ::Session:${session}(Bgexec,lasterror)\
              -output ::Session:${session}(Bgexec,output)\
              -error ::Session:${session}(Bgexec,error)\
              -linebuffered true\
              -onoutput "::[set ::Session:${session}(Tk)]_LastOutput $session"\
              -onerror "::[set ::Session:${session}(Tk)]_LastError $session"\
              -killsignal SIGTERM [info nameofexecutable]\
              [file join [file dirname $::Config(starkitTop)] Tk $state(Tk) TkStartup.tcl]\
              -display :$Xdisplay {*}$Tkarglist &]
         set state(TkApp,TkPid) [set ::X${Xdisplay}(TkPid)] 
     }
}

# The purpose of this procedure is to monitor the idle time of a websocket
# connection and by default the idle time of the Tk app. Once the idle time
# is reached it will close the Tk app X display etc. A ping frame is sent
# when the websocket connection is idle to keep the TCP session alive
# and a binary frame is sent when there is activity. The first ping frame
# will set the start time and the next ping frame will set the current time.
# A binary frame will reset the time back to zero.

proc Xdisplay_IdleTime {Xdisplay IdleTime} {
             upvar #0 X$Xdisplay Xstate

     if {[string equal 0 $Xstate(IdleStart)]} {
         set Xstate(IdleStart) [clock seconds] 
     } else {
         set Xstate(IdleCurrent) [clock seconds]
         set IdleDiff [expr {$Xstate(IdleCurrent) - $Xstate(IdleStart)}]
             if {$IdleDiff > $IdleTime} {
                 Xdisplay_Close $Xdisplay Xvnc
             }
     }
}
