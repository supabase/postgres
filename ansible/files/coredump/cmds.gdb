# Based on orioledb/ci/cmds.gdb (OrioleDB's own CI crash-debugging script).
# debug-file-directory/file/core-file are set by the caller before this
# file is sourced (see process-orioledb-coredumps.sh).
#
# GDB aborts the rest of a sourced script on the first command error, so
# order matters here: commands that work without debug symbols run first.
# `set $end=argc` fails without postgres's debug symbols, and the
# myLockedPages dump fails without orioledb.so's. `info registers` also runs
# before `up 99999`, so it shows the crashing frame rather than main().
thread apply all bt full
info sharedlibrary
info registers
up 99999
set $i=0
set $end=argc
while ($i < $end)
p argv[$i++]
end
eval "p *((LWLockHandle (*) [%u]) held_lwlocks)", num_held_lwlocks
eval "p *((MyLockedPage (*) [%u]) myLockedPages)", numberOfMyLockedPages
quit
