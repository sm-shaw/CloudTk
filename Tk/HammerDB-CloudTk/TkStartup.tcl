global env
set ix [lsearch $argv -display]
if {$ix >= 0} {
    incr ix
    set env(DISPLAY) [lindex $argv $ix]
    set argc 0
    set argv {}
cd [ file join {*}[ lreplace [ file split [ pwd ]] end end ]]
set tempdir [ file join [ pwd ] TMP ]
if { ![file exists $tempdir] } { file mkdir $tempdir }
set ::env(TMP) $tempdir 
exec ./hammerdb
}
