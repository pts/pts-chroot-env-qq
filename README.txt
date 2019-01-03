pts-chroot-env-qq: convenient chroot creation and entering
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
pts_chroot_env_qq.sh is script (containing shell and Perl code) which lets
the user conveniently create chroot environments on Unix systems and enter
them either as a regular user or as root. sudo is used for the chroot
environment creation and entering, except that on Linux entering as a
regular user works in rootless mode (without sudo).

When entering a chroot environment, pts_chroot_env_qq.sh does roughly this:
walk up to find the chroot directory + sudo + chroot + (su to regular user) +
cd back to the directory + adding a line to /etc/passwd + creating an
in-chroot home directory + setting some the environment variables.

Advantages of pts_chroot_env_qq.sh:

* It can create a new chroot environment containing a vanilla Linux
  distribution or Docker image by running a single command. No need to
  download filesystem .iso or .squashfs images or .tar.gz dumps manually.
* It can be used conveniently as a regular user, no need to run any code
  within the chroot environment as root.
* Data files can be shared between the chroot and the host systems: the host
  system sees files within the chroot environment, even when working as a
  regular user (non-root). There is no need to copy, chown or chmod data files.
* The root directory of the chroot environment is autodetected, and the
  current directory is retained, so no need to run `cd' manually.
* It retains the environment variables by default, but modifies some of
  them so thet everything works conveniently.

Typical use case for compiling the same code with different compilers:

  $ qq get-ubuntu precise precise_dir
  $ mkdir precise_dir/tmp/myproject
  $ cd precise_dir/tmp/myproject
  $ echo '#include <stdio.h>' >hello.c
  $ echo 'int main() { return !printf("Hello, World!\n"); }' >>hello.c
  $ sudo apt-get update  # On the host system.
  $ sudo apt-get -y install gcc
  $ gcc -static -o hello.host hello.c
  $ qq apt-get update  # In the chroot.
  $ qq apt-get -y install gcc
  $ qq gcc -static -o hello.chroot hello.c
  $ qq ./hello.host  # Run host-compiled binary in the chroot environment.
  Hello, World!
  $ ./hello.chroot  # Run chroot-compiled binary on the host.
  Hello, World!

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
* On Linux it hides the /proc and /dev/pts mounts from the host system (using
  unshare(CLONE_NEWNS), equivalent to `unshare -m').
* On Linux 3.8 or later it operates in rootless mode (i.e. as the non-root
  user who has invoked it) by default (using unshare(CLONE_NEWUSER)): it
  doesn't even need sudo to root. (Limitations: sudo to root is needed for
  the creation of the chroot directory and its contents such as /dev/null, for
  the first non-root run of qq, and for all runs of qq root.)
* On Linux it automates the creation of chroot environments with
  Linux distributions Ubuntu, Debian and Alpine. (For this sudo to root is
  needed.)
* It removes X11, GUI desktop (e.g. D-Bus) and SSH environment variables.

Requirements on the host system:

* A Linux system (or any Unix system which can mount /proc and /dev/pts like
  Linux does it; the mount will be run within the chroot).
* The sudo command. (If it's already running as root (EUID 0), then sudo is
  not needed.)
* The perl command. Any Perl 5 from version 5.004 (released on 1997-10-15)
  will work.
* A Bourne shell in /bin/sh: any of Bash, Zsh, Dash and Busybox sh will do.

Requirements in the chroot environment (guest system):

* (If you created the chroot with debootstrap or you are chrooting to a root
  file system of a Linux installation, you are all set, no need to read
  further.)
* The /sbin/mount command for mounting /proc and /dev/pts. This is not
  needed on Linux systems, because pts_chroot_env_qq.sh can invoke the
  mount(2) system call directly.
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
* Start using it by creating a chroot environment (see below) and entering
  it (see below).

How to create a chroot environment:

* Skip this section if you already have a chroot environment created and
  extracted to a directly accessible directory.

* To install an initial chroot environment
  for Linux distribution Alpine, run `qq get-alpine VERSION TARGETDIR', e.g.

    $ qq get-alpine latest-stable alpine_dir
    $ cd alpine_dir
    $ qq busybox | head
    BusyBox v1.28.4 (2018-12-06 15:13:21 UTC) multi-call binary.

  Please note that the default `--arch i386' is used. To use a different
  architecture, specigy `--arch ARCH'.

* To install an initial chroot environment for a recent version of the
  Linux distribution Ubuntu using their cloud image repository, run
  `qq get-ubuntu DISTRO TARGETDIR', e.g. `qq get-ubuntu bionic bionic_dir'
  or `qq get-ubuntu zesty zesty_dir'. The oldest available Ubuntu from there
  is 10.04 (lucid), run `qq get-ubuntu lucid lucid_dir' to get it.

  To get a full list of Ubuntu releases available from there, run
  `qq get-ubuntu . get_dir'.

* To install an initial chroot environment for a recent version of a
  Linux distribution using the LXC (or LXD) cloud image repository, run
  `qq get-lxc DISTRO TARGETDIR', e.g. `qq get-lxc centos/6 centos_dir'.
  Alpine Linux is also available from this repository.

  To get a full list of Linux distributions available from there, run
  `qq get-lxc . get_dir'.

  On 2019-01-02, the repository contained the following Linux distributions:
  Debian (buster, jessie, sid, stetch, wheezy), Ubuntu Core, Ubuntu (bionic,
  cosmic, disco, trusty, xenial), Alpine (3.4 ... 3.8), Arch, CentOS (6 and
  7), Fedora (26, 27, 28, 29), Gentoo, openSUSE (15, 42), Oracle (6, 7),
  Plamo (5, 6, 7), Sabayon.

* To install an initial chroot environment based on a Docker image
  (typically for amd64 or i386 architecture), install
  Docker first, and then run `qq get-docker IMAGE TARGETDIR', e.g.
  `qq get-docker busybox busybox_dir' or
  `qq get-docker alpine alpine_dir' or
  `qq get-docker bitnami/minideb:stretch stretch_dir'.

  Use the chroot environment normally:

    $ qq get-docker busybox busybox_dir
    $ cd busybox_dir/tmp
    $ qq
    [qq=busybox_dir] USER@HOST:/tmp$ exit

  Recommended small Docker images: busybox, alpine, minideb,
  minideb:stretch, minideb:jessie, minideb:wheezy.

  More info about minideb (small Debian-based Docker image for amd64
  architecture):

  * https://github.com/bitnami/minideb
  * https://hub.docker.com/r/bitnami/minideb/tags/

* To install an initial chroot environment on Linux i386 or amd64 systems
  for Linux distributions Ubuntu and Debian using Debootstrap (more
  specifically, pts-debootstrap: https://github.com/pts/pts-debootstrap/),
  run `qq debootsrap DISTRO TARGETDIR', e.g.

    $ qq pts-debootstrap feisty feisty_dir
    $ cd feisty_dir
    $ bash --version | head -1  # Host system.
    GNU bash, version 4.4.12(1)-release (x86_64-pc-linux-gnu)
    $ qq bash --version | head -1  # Feisty in chroot.
    GNU bash, version 3.2.13(1)-release (i486-pc-linux-gnu)

  Please note that `qq pts-debootstrap' may take several minutes to finish,
  thus it is slower than `qq get-lxc', `qq get-ubuntu' and `qq get-docker'.
  The advantage of `qq pts-debootstrap' is that it supports very old Ubuntu
  and Debian releases: Debian slink (Debian 2.1, released on 1999-03-19) and
  Ubuntu feisty (Ubuntu 7.04, released 2007-04-19) both work.

* You can use any other method you already know to create the chroot
  environment. If it doesn't have /sbin/init and /etc/issue, then create a
  file named /etc/qqsystem there.

Usage:

* If you don't have a chroot environment yet, see below how to install one.
* cd to anywhere within a chroot environment.
* Use qq as a regular user (non-root). pts_chroot_env_qq.sh runs sudo for you
  if needed.
* (You can also use qq as root on the host system, but it's not recommended.
  Use qq root (see below) if you need root access in the chroot environment.)
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
* To force rootless mode, run qq use-rootless [...].
* To force sudo for the initial setup (rather than rooless mode), run qq
  use-sudo [...].

Compatibility with old Linux systems:

* The oldest Debian that is known to work with pts_chroot_env_qq.sh is
  slink (Debian 2.1, released on 1999-03-19, containing Perl 5.004).
  However, UIDs larger than 65535 are not supported, and you will get the
  UID truncated to 16 bits within the chroot instead.

  `qq pts-debootstrap slink slink_dir' also works, and `qq apt-get install'
  works within there.

  FYI In Debian potato (Debian 2.2), UIDs larger than 65535 are not
  supported either, and you will get root access within the chroot instead.

* The oldest Debian that is known to work with pts_chroot_env_qq.sh with
  UIDs larger than 65535 is woody (Debian 3.0, released on 2002-07-19,
  containing Perl 5.6.1). However, UIDs larger than 65535 are not supported,
  and you will get root access within the chroot instead.

  `qq pts-debootstrap woody woody_dir' also works, and `qq apt-get install'
  works within there.

* The oldest Ubuntu that is known to work with pts_chroot_env_qq.sh is
  feisty (Ubuntu 7.04, released on 2007-04-19). UIDs larger than 65535 also
  work.

  `qq pts-debootstrap feisty feisty_dir' also works, and `qq apt-get install'
  works within there.

Alternatives of pts_chroot_env_qq.sh:

* schroot (https://wiki.debian.org/Schroot) and its predecessor, dchroot are
  convenient and configurable tools for root and non-root users to enter a
  chroot environment. See more details on
  https://askubuntu.com/q/158847/3559 .

* uchroot (https://github.com/cheshirekow/uchroot): Python scripts providing
  chroot-like (`mount --bind') functionality with user namespaces. Doesn't
  need root access. An Ubuntu Trusty system can be set up within it:
  https://github.com/cheshirekow/uchroot/blob/master/uchroot/doc/multistrap_example.rst

* multistrap (https://wiki.debian.org/Multistrap) is a cross-architecture,
  manual (a bit hacky) version of debootstrap.

__END__
