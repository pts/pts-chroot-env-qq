pts-chroot-env-qq: convenient chroot entry point
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
pts_chroot_env_qq.sh is script (containing shell and Perl code) which lets
the user conveniently enter a chroot environment on Unix systems. It's a
combination of sudo + chroot + su to regular user + cd + setting some the
environment variables.

Convenience functionality provided by pts_chroot_env_qq.sh:

* It works even if you are within a subdirectory of a chroot directory:
  it will find the top of the chroot, run the chroot command there, and take
  you back to your directory.
* It propagates all environment variables (overriding only a few of them)
  by default.
* It setuids back to the regular (non-root) user who called it. This way
  you can conveniently (and by default) run commands within a chroot
  environment as non-root. 
* It doesn't run sudo or su within the chroot, so your environment variables
  won't be clobbered.
* It doesn't run a shell if you specify a command, so your environment
  variables won't be clobbered by e.g. /etc/bash.bashrc.
* Even for the default interactive shell, it calls it with bash --norc, to
  keep the environment variables.
* It creates a symlink within the chroot, so host paths also work. For example,
  if /tmp/mychroot is the top of the chroot, then it creates the symlink `ln
  -s / /tmp/mychroot/tmp/mychroot', so pathanems like /tmp/mychroot/etc/motd
  work not only on the host system, but also within the chroot.
* It mounts /proc and /dev/pts (if not already mounted) within the chroot, so
  tools expecting these paths to exist will work.
* Adds a prefix `[qq=...] ' to $PS1 so the interactive shell will show a prompt
  indicating it's within a chroot environment.
* (It doesn't support running graphical applications within the chroot, so
  it unsets $DISPLAY and other GNOME, KDE and DBUX environment variables.)
* It unsets $LANG, $LANGUAGE and all other locale environemnt variables
  except for $LC_CTYPE, which it normalizes.
* It adds the current non-root user to /etc/passwd, /etc/shadow and
  /etc/group within the chroot, so commands like `id' will work and return
  the username. It also sets $HOME to the home directory within the chroot.
* It sets $PATH to a sane default (in /usr), and it also keeps existing host
  directories on the $PATH if they are visible from within the chroot
  environment (e.g. /tmp/mychroot/opt/myprogdir will be kept on $PATH,
  /var/myprog2dir will be removed).

Requirements on the host system:

* A Linux system (or any Unix system which can mount /proc and /dev/pts like
  Linux does it; the mount will be run within the chroot).
* The sudo command.
* The chroot command.
* A Bourne shell in /bin/sh: any of Bash, Zsh, Dash and Busybox sh will do.

Requirements in the chroot environment (guest system):

* (If you created the chroot with debootstrap or you are chrooting to a root
  file system of a Linux installation, you are set, no need to read
  further.)
* The /usr/bin/perl command running Perl 5 (5.004 or later).
* The /sbin/mount command for mounting /proc and /dev/pts.
* The /sbin/init command (won't be run, just the presence is detected).
* The /etc/issue file (just the presence is detected).
* Optionally (recommended), the /bin/bash (preferred) or /bin/sh command.

Installation:

* Download
  https://raw.githubusercontent.com/pts/pts-chroot-env-qq/master/pts_chroot_env_qq.sh
* Make pts_chroot_env_qq.sh executable.
* Create a symlink to pts_chroot_env_qq.sh on your $PATH with the name qq
  (recommended), e.g.:

    $ sudo ln -s /.../pts_chroot_env_qq.sh /usr/local/bin/qq

Usage:

* cd to anywhere within a chroot directory.
* Use qq as a regular user (non-root). pts_chroot_env_qq.sh runs sudo for you.
* Run qq to enter an interactive shell there. (You will have to type your
  password, because pts_chroot_env_qq.sh uses sudo.)
* Alternatively, run qq root to get an interactive root shell there.
* Alternatively, run qq <command> [<arg> ...] to run a command within the
  chroot.
* Alternatively, run qq root <command> [<arg> ...] to run a command to run a
  command as root within the chroot. For some commands (such as apt-get,
  dpkg and su), prepending root is not deeded, because pts_chroot_env_qq.sh
  recognizes them and runs them as root.
* Alternatively, run qq cd to see a writable directory name which works
  inside and outside the chroot. You can use this directory to transfer
  files even is a regular (non-root) user between the chroot and the host.
* To install packages to a Debian or Ubuntu chroot, first run
  `qq apt-get update', then run `qq apt-get install PACKAGENAME'.

__END__
