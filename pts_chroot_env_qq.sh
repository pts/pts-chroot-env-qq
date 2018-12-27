#! /bin/sh
#
# pts_chroot_env_qq.sh: convenient chroot entry point
# by pts@fazekas.hu at Sat Jul 21 15:02:55 CEST 2018
#
# This shell script works with bash, zsh, dash and busybox sh.
#

__qq__() {
  local __QQD__="$PWD" __QQFOUND__
  test "${__QQD__#/}" = "$__QQD__" && __QQD__="$(pwd)"
  if test "${__QQD__#/}" = "$__QQD__"; then
    echo "qq: fatal: cannot find current directory: $__QQD__" >&2
    return 123
  fi
  while test "${__QQD__#//}" != "$__QQD__"; do
    __QQD__="${__QQD__#/}"  # Remove duplicate leading slashes.
  done
  while test "$__QQD__"; do
    __QQFOUND__=1
    if test -x "$__QQD__/usr/bin/perl"; then
      test -x "$__QQD__/sbin/init" && test -f "$__QQD__/etc/issue" && break
      test -f "$__QQD__/etc/qqsystem" && break
    fi
    __QQFOUND__=
    test "${__QQD__%/*}" = "$__QQD__" && break
    __QQD__="${__QQD__%/*}"
  done
  if test -z "$__QQFOUND__"; then
    echo "qq: fatal: system-in-chroot not found up from: $PWD" >&2
    return 124
  fi
  # TODO(pts): Set up /etc/hosts and /etc/resolve.conf automatically.
  # TODO(pts): As an alternative to `sudo -E chroot`, run the non-root mode in
  #            nsjail, so not even temporary root access is needed.
  # TODO(pts): Support qq1, qq2 (i.e. multiple execution environments). How
  #            can they see the same local directory?
  __QQIN__='
#! /usr/bin/perl -w
# qqin: Entry point for qq from `sudo -E chroot`.
#
# This Perl script can manage environment variables (and pass them to the
# command in @ARGV) precisely, because it does not invoke a shell, does not
# invoke su(1) or sudo(1).
#

BEGIN{ $^W = 1 }
use integer;
use strict;

#die "qqin: fatal: unexpected \$0: $0\n" if $0 ne "...";
die "qqin: fatal: must be run as root\n" if $> != 0;
$( = 0;
$) = "0 0";  # Also involves an empty setgroups.
$< = 0;  # setuid(0).

my $qqd = $ENV{__QQD__};
my $qqpath = $ENV{__QQPATH__};
my $pwd = $ENV{PWD};
my $home = $ENV{HOME};
die "qqin: fatal: empty \$ENV{__QQD__}\n" if !$qqd;
die "qqin: fatal: empty \$ENV{__QQPATH__}\n" if !$qqpath;
# Too late for a getpwnam or getpwuid after a chroot.
die "qqin: fatal: empty \$ENV{HOME}\n" if !$home;
die "qqin: fatal: bad QQD snytax: $qqd\n" if $qqd !~ m@\A(/[^/]+)+@;
die "qqin: fatal: bad PWD snytax: $pwd\n" if $pwd !~ m@\A(/[^/]+)+@;
die "qqin: fatal: QQD is not a prefix of PWD" if
    0 == length($pwd) or substr("$pwd/", 0, length($qqd) + 1) ne "$qqd/";
if ($ENV{__QQLCALL__}) {
  $ENV{LC_ALL} = $ENV{__QQLCALL__};
} else {
  delete $ENV{LC_ALL};
}
delete @ENV{"__QQD__", "__QQPATH__", "__QQLCALL__", "__QQIN__"};

# Removes setuid, setgid and sticky bits.
sub chmod_remove_high_bits($) {
  my $path = $_[0];
  my @stat = stat($path);
  die "qqin: fatal: stat $path: $!\n" if !@stat;
  die "qqin: fatal: chmod $path: $!\n" if !chmod($stat[2] & 0777, $path);
}

# Now create $qqd as a symlink to "/", to make filenames work.
my $link = readlink($qqd);
if (!$link) {
  my $qqdu = $qqd;
  $qqdu =~ s@/[^/]\Z(?!\n)@@;
  $link = symlink("/", $qqd);
  if (!$link and $qqdu =~ s@/[^/]+\Z(?!\n)@@ and $qqdu and !-d($qqdu)) {
    my @qqdl = ($qqdu);
    while ($qqdu =~ s@/[^/]+\Z(?!\n)@@ and $qqdu and !-d($qqdu)) {
      push @qqdl, $qqdu;
    }
    my $home =
        ($ENV{SUDO_USER} and $ENV{SUDO_UID} and $ENV{SUDO_GID}) ?
        "/home/$ENV{SUDO_USER}" : "-";
    while (@qqdl) {
      $qqdu = pop(@qqdl);
      # Owned by root. Good.
      die "qqin: fatal: mkdir $qqdu: $!\n" if !mkdir($qqdu, 0755);
      if (substr($qqdu, 0, length($home)) eq $home and
          (length($qqdu) == length($home) or
           substr($qqdu, length($home), 1) eq "/")) {
        die "qqin: fatal: chown $home: $!\n" if
            !chown($ENV{SUDO_UID}, $ENV{SUDO_GID}, $qqdu);
      }
      chmod_remove_high_bits($qqdu) if $qqdu eq $home;
    }
    $link = symlink("/", $qqd);
  }
  die "qqin: fatal: cannot create symlink: $qqd\n" if !$link;
}
die "qqin: fatal: chdir $pwd: $!\n" if !chdir($pwd);

sub is_mounted($) {
  my @stata = lstat("/");
  die "qqin: fatal: stat /: $!\n" if !@stata;
  my @statb = lstat($_[0]);
  return (@statb and $stata[0] != $statb[0]) ? 1 : 0;  # Different st_dev.
}

if (!is_mounted("/proc")) {
  die "qqin: fatal: mount /proc failed\n" if
      system("/bin/mount", "proc", "/proc", "-t", "proc");
}

if (!is_mounted("/dev/pts")) {
  die "qqin: fatal: mount /dev/pts failed\n" if
      system("/bin/mount", "devpts", "/dev/pts", "-t", "devpts");
}

delete @ENV{"UID", "EUID", "GID", "EGID"};  # Does not exist.
# Prevent noninteractive bash from executing bashrc.
# Does not affect noniteractive 2.05b.0(1)-release, it does not execute bashrc.
$ENV{SHLVL} = "1" if !defined($ENV{SHLVL});
# Prevent noninteractive bash from executing bashrc.
# Does not affect noniteractive 2.05b.0(1)-release, it does not execute bashrc.
#delete $ENV{SSH_CLIENT};
$ENV{PS1} = q~\u@\h:\w\$ ~ if !defined($ENV{PS1}) or
    $ENV{PS1} =~ m@%@;  # zsh prompt.
my $qqdlast = $qqd;
$qqdlast =~ s@\A.*/@@s;
$ENV{PS1} = "[qq=$qqdlast] $ENV{PS1}";
$ENV{SHELL} = -f("/bin/bash") ? "/bin/bash" : "/bin/sh";

# X11, Gnome
delete @ENV{qw(
    DISPLAY XAUTHORITY WINDOWID
    CLUTTER_IM_MODULE DBUS_SESSION_BUS_ADDRESS DEFAULTS_PATH DESKTOP_SESSION
    GDMSESSION GIO_LAUNCHED_DESKTOP_FILE GIO_LAUNCHED_DESKTOP_FILE_PID
    GNOME_DESKTOP_SESSION_ID GNOME_KEYRING_CONTROL GNOME_KEYRING_PID
    GTK_IM_MODULE GTK_MODULES IM_CONFIG_PHASE MANDATORY_PATH QT4_IM_MODULE
    QT_IM_MODULE QT_QPA_PLATFORMTHEME SESSION SESSIONTYPE SESSION_MANAGER
    SSH_AGENT_LAUNCHER TEXTDOMAIN TEXTDOMAINDIR UBUNTU_MENUPROXY UPSTART_SESSION
    XMODIFIERS XTERM_LOCALE XTERM_SHELL XTERM_VERSION
    XDG_CONFIG_DIRS XDG_CURRENT_DESKTOP XDG_DATA_DIRS XDG_GREETER_DATA_DIR
    XDG_MENU_PREFIX XDG_RUNTIME_DIR XDG_SEAT XDG_SEAT_PATH XDG_SESSION_ID
    XDG_SESSION_PATH XDG_VTNR
    )};

delete @ENV{qw(
    BASH_TO_ZSH GPG_AGENT_INFO HISTSIZE SELINUX_INIT SSH_AGENT_PID SSH_AUTH_SOCK
    _ SSH_CLIENT)};
# Keep: INSTANCE JOB LESSCHARSET EDITOR PAGER PTS_LOCAL_EOK TERM TEXCONFIG
# UA_NS OLDPWD.

my $lc_ctype = defined($ENV{LC_CTYPE}) ? $ENV{LC_CTYPE} : "";
delete @ENV{"LANG", "LANGUAGE", "LC_CTYPE", "LC_NUMERIC", "LC_TIME",
            "LC_COLLATE", "LC_MONETARY", "LC_MESSAGES", "LC_PAPER", "LC_NAME",
            "LC_ADDRESS", "LC_TELEPHONE", "LC_MEASUREMENT", "LC_IDENTIFICATION",
            "LC_ALL"};
if (-f("/usr/lib/locale/locale-archive")) {
  my $encoding = $lc_ctype =~ m@[.](.*)\Z(?!\n)@s ? $1 : "UTF-8";
  $encoding = "UTF-8" if $encoding =~ m@\Autf-?8@i;
  $ENV{LC_CTYPE} = "en_US.$encoding";
  delete $ENV{LC_CTYPE} if (readpipe("locale 2>&1") or "") =~
      /: Cannot set LC_CTYPE to default locale:/;
} else {
  delete $ENV{LC_CTYPE};
}

# Returns true iff entry was already there.
sub ensure_auth_line($$;$) {
  my($filename, $line, $is_check) = @_;
  $line =~ s@\n@@g;
  $line .= "\n";
  die "qqin: assert: bad auth line: $line" if $line !~ m@\A([^:\n]+:)@;
  my $prefix = $1;
  die "qqin: fatal: open $filename: $!\n" if !open(my($fh), "+<", $filename);
  my $fl;
  while (defined($fl = <$fh>)) {
    if (substr($fl, 0, length($prefix)) eq $prefix) {
      close($fh);
      return 1;
    }
  }
  if (!$is_check) {
    die "qqin: fatal: seek: $!\n" if !sysseek($fh, 0, 2);
    die "qqin: fatal: syswrite: $!\n" if !syswrite($fh, $line);
    die "qqin: fatal: close: $!\n" if !close($fh);
  }
  0;
}

$ENV{HOME} = "/root";
my $username = "root";
my @run_as_root = (
    "su", "sudo", "login", "passwd", "apt-get", "dpkg", "rpm", "yum");
my $is_root = 1;
my $is_root_cmd = 0;
if (@ARGV and $ARGV[0] eq "root") {
  $is_root_cmd = 1;
  shift @ARGV;
} elsif (@ARGV and grep({ $_ eq $ARGV[0] } @run_as_root)) {
} else {
  die "qqin: fatal: incomplete sudo environment: SUDO_UID, SUDO_GID, SUDO_USER\n" if
      !$ENV{SUDO_UID} or !$ENV{SUDO_GID} or !$ENV{SUDO_USER};
  if ($ENV{SUDO_USER} ne "root" and $ENV{SUDO_UID} != 0) {
    die "qqin: fatal: invalid username: $ENV{SUDO_USER}\n" if
        $ENV{SUDO_USER} !~ m@\A[-+.\w]+\Z(?!\n)@;
    if (!ensure_auth_line("/etc/passwd", "$ENV{SUDO_USER}:", 1)) {
      if (!-f("/etc/shadow")) {
        die "qqin: fatal: error creating /etc/shadow: $!\n" if
            !open(my($fh), ">>", "/etc/shadow");
        close($fh);
        die "qqin: fatal: error chmodding /etc/shadow: $!\n" if
            !chmod(0600, "/etc/shadow");
      }
      ensure_auth_line("/etc/shadow", "$ENV{SUDO_USER}:*:17633:0:99999:7:::\n");
      ensure_auth_line("/etc/group",  "$ENV{SUDO_USER}:x:$ENV{SUDO_GID}:\n");
      # Do it last, in case of errors with the above.
      ensure_auth_line("/etc/passwd", "$ENV{SUDO_USER}:x:$ENV{SUDO_UID}:$ENV{SUDO_GID}:qquser $ENV{SUDO_USER}:/home/$ENV{SUDO_USER}:$ENV{SHELL}");
    }
    # TODO(pts): Do we want to add the original $ENV{HOME} as a symlink?
    my $home = "/home/$ENV{SUDO_USER}";
    if (!-d($home)) {
      mkdir "/home", 0755;
      mkdir $home, 0755;
      die "qqin: fatal: could not create HOME: $home\n" if !-d($home);
      die "qqin: fatal: chown $home: $!\n" if
          !chown($ENV{SUDO_UID}, $ENV{SUDO_GID}, $home);
      chmod_remove_high_bits($home);
    }
    $ENV{HOME} = $home;
    ($(, $)) = ($ENV{SUDO_GID}, "$ENV{SUDO_GID} $ENV{SUDO_GID}");
    die "qqin: fatal: setgid failed\n" if
        $( != $ENV{SUDO_GID} or $) != $ENV{SUDO_GID};
    ($<, $>) = ($ENV{SUDO_UID}, $ENV{SUDO_UID});
    die "qqin: fatal: setuid failed\n" if
        $( != $ENV{SUDO_GID} or $) != $ENV{SUDO_GID};
    $is_root = 0;
  }
}
$ENV{LOGNAME} = $ENV{USER} = $ENV{USERNAME} = $username;
delete @ENV{"SUDO_COMMAND", "SUDO_GID", "SUDO_UID", "SUDO_USER"};
push @ARGV, ($ENV{SHELL} eq "/bin/bash") ?
    ("/bin/bash", "--norc") : ("/bin/sh") if !@ARGV;

# In $ENV{PATH} keep everything below $qqd and $ENV{HOME}, deduplicate those,
# and then add system path.
{
  my $homes = "$home/";
  my $qqds = "$qqd/";
  my %path;
  my @path_out;
  for my $dir (split(/:+/, ($qqpath or ""))) {
    # Don"t match $home (outside chroot) itself.
    if (!$is_root and substr($dir, 0, length($homes)) eq $homes) {
      $dir = "$ENV{HOME}/" . substr($dir, length($homes));
    } elsif ($dir eq $qqd or substr($dir, 0, length($qqds) eq $qqds)) {
    } else {
      next
    }
    if (!exists($path{$dir})) {
      $path{$dir} = 1;
      push @path_out, $dir;
    }
  }
  push @path_out, split(/:+/, "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin");
  $ENV{PATH} = join(":", @path_out);
}

if (@ARGV and $ARGV[0] eq "cd" and !$is_root_cmd) {
  # Print the name of the user-writable home directory, and exit.
  print "$qqd$ENV{HOME}\n";
  exit;
}

# TODO(pts): Run qqinbashrc now?
#            If it exists, then run @ARGV with bash (properly quote it first).

# exec(...) also prints a detailed error message.
die "qqin: fatal: exec $ARGV[0]: $!\n" if !exec(@ARGV);
' __QQD__="$__QQD__" __QQPATH__="$PATH" __QQLCALL__="$LC_ALL" PWD="$PWD" LC_ALL=C exec sudo -E chroot "$__QQD__" /usr/bin/perl -w -e 'eval $ENV{__QQIN__}; die $@ if $@' "$@"
  # Above setting LC_ALL=C instead of PERL_BADLANG=x, to prevent locale warnings.
}

__qq__ "$@"
