# Create /usr/bin symlinks for compatibility with standard entrypoint scripts
# The entrypoint script expects tools like `id`, `find`, etc. at /usr/bin/
{ pkgs }:
pkgs.runCommand "usrbin-compat" { } ''
  mkdir -p $out/usr/bin

  # Core utilities needed by docker-entrypoint.sh
  ln -s /bin/id $out/usr/bin/id
  ln -s /bin/find $out/usr/bin/find
  ln -s /bin/install $out/usr/bin/install
  ln -s /bin/chown $out/usr/bin/chown
  ln -s /bin/chmod $out/usr/bin/chmod
  ln -s /bin/mkdir $out/usr/bin/mkdir
  ln -s /bin/rm $out/usr/bin/rm
  ln -s /bin/cat $out/usr/bin/cat
  ln -s /bin/ls $out/usr/bin/ls
  ln -s /bin/cp $out/usr/bin/cp
  ln -s /bin/mv $out/usr/bin/mv
  ln -s /bin/env $out/usr/bin/env
  ln -s /bin/basename $out/usr/bin/basename
  ln -s /bin/dirname $out/usr/bin/dirname
  ln -s /bin/head $out/usr/bin/head
  ln -s /bin/tail $out/usr/bin/tail
  ln -s /bin/sort $out/usr/bin/sort
  ln -s /bin/wc $out/usr/bin/wc
  ln -s /bin/tr $out/usr/bin/tr
  ln -s /bin/cut $out/usr/bin/cut
  ln -s /bin/tee $out/usr/bin/tee
  ln -s /bin/touch $out/usr/bin/touch
  ln -s /bin/stat $out/usr/bin/stat
  ln -s /bin/readlink $out/usr/bin/readlink
  ln -s /bin/realpath $out/usr/bin/realpath
  ln -s /bin/sleep $out/usr/bin/sleep
  ln -s /bin/date $out/usr/bin/date
  ln -s /bin/uname $out/usr/bin/uname
  ln -s /bin/whoami $out/usr/bin/whoami
  ln -s /bin/groups $out/usr/bin/groups
  ln -s /bin/xargs $out/usr/bin/xargs
  ln -s /bin/expr $out/usr/bin/expr
  ln -s /bin/test $out/usr/bin/test
  ln -s /bin/[ $out/usr/bin/[
  ln -s /bin/true $out/usr/bin/true
  ln -s /bin/false $out/usr/bin/false
  ln -s /bin/seq $out/usr/bin/seq
  ln -s /bin/printf $out/usr/bin/printf
  ln -s /bin/echo $out/usr/bin/echo

  # sed, awk, grep
  ln -s /bin/sed $out/usr/bin/sed
  ln -s /bin/awk $out/usr/bin/awk
  ln -s /bin/grep $out/usr/bin/grep
  ln -s /bin/egrep $out/usr/bin/egrep
  ln -s /bin/fgrep $out/usr/bin/fgrep
''
