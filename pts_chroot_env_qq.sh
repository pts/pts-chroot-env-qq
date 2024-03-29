#! /bin/sh
#
# pts_chroot_env_qq.sh: convenient chroot entry point
# by pts@fazekas.hu at Sat Jul 21 15:02:55 CEST 2018
#
# This shell script works with bash, zsh, dash and busybox sh.
#
# This shell script is affected by the (optional) environment variable
# __QQPERL__ specifying which Perl interpreter to use.
#

# Initialize a chroot directory (e.g. /etc/passwd within) for the current
# user. This is useful so that next time the user can enter the chroot
# environment without sudo (e.g. unshare) on Linux.
__qq_init__() {
  (cd "$1" && __qq__ sh -c :)
}

__qq_pts_debootstrap__() {
  if test -z "$1" || test "$1" = --help || test $# -lt 2; then
    echo "Usage:   $0 pts-debootstrap [<flag>...] <debian-distro-name> <target-dir>" >&2
    echo "Example: $0 pts-debootstrap feisty feisty_dir"
    echo "Example: $0 pts-debootstrap --arch amd64 stretch stretch_dir"
    return 1
  fi
  local ARG DIR=
  for ARG in "$@"; do
    DIR="$ARG"
  done
  test "${DIR#/}" = "$DIR" && DIR="./$DIR"
  if test -d "$DIR"; then
    echo "qq: fatal: target directory already exists, not clobbering: $DIR" >&2
    return 100
  fi
  rm -rf "$DIR.pts-debootstrap"
  URL=https://raw.githubusercontent.com/pts/pts-debootstrap/master/pts-debootstrap
  if wget -qO "$DIR.pts-debootstrap" "$URL" &&
     test -s "$DIR.pts-debootstrap"; then
    :
  else
    echo "qq: fatal: error downloading URL: $URL" >&2
    return 103
  fi
  if ! chmod 755 "$DIR.pts-debootstrap"; then
    echo "qq: fatal: error chmodding: $DIR.pts-debootstrap" >&2
    return 104
  fi
  local SUDO=sudo
  test "$EUID" = 0 && SUDO=
  $SUDO "$DIR.pts-debootstrap" "$@"
  local STATUS="$?"
  rm -rf "$DIR.pts-debootstrap"
  if test "$STATUS" != 0; then
    rm  -rf "$DIR" 2>/dev/null
    test -d "$DIR" && $SUDO rm -rf "$DIR"
    return "$STATUS"
  fi
  __qq_init__ "$DIR"
}

__qq_get_alpine__() {
  local ARCH=
  if test "$1" = --arch && test $# -gt 1; then
    ARCH="$2"
    shift; shift
  fi
  if test -z "$1" || test "$1" = --help || test $# != 2; then
    echo "Usage:   $0 get-alpine [--arch=<arch>] {<version>|dir} <target-dir>" >&2
    echo "Example: $0 get-alpine latest-stable alpine_dir" >&2
    echo "Example: $0 get-alpine 3.8 alpine38_dir" >&2
    echo "Architectures (<arch>): i386 (x86), amd64 (x86_64), s390x, ppc64le, armhf, aarch64." >&2
    return 1
  fi
  if test -z "$ARCH"; then
    ARCH="$(uname -m)"
    case "$ARCH" in amd64 | x86_64 | x64) ARCH=i386; esac  # 32-bit default.
  fi
  case "$ARCH" in
   i[3456]86 | x86) ARCH=x86 ;;
   amd64 | x86_64 | x64) ARCH=x86_64 ;;
   ppc64el | ppc64le) ARCH=ppc64le ;;
  esac
  if test -z "$ARCH"; then
    echo "qq: fatal: bad architecture" >&2
    return 108
  fi

  # Works with version 3.5, 3.6, 3.7 and 3.8.
  local VERSION="$1"
  local DIR="$2"

  local SUDO=sudo
  test "$EUID" = 0 && SUDO=

  if test "$VERSION" = dir; then
    if ! (cd "$DIR" 2>/dev/null); then
      if ! $SUDO chown "$(id -u)" "$DIR"; then
        echo "qq: fatal: chown failed in: $DIR" >&2
        return 112
      fi
    fi
    if test -f "$DIR/etc/apk/repositories" && test -x "$DIR/sbin/apk" && test -f "$DIR/etc/issue" && (test -f "$DIR"/sbin/init || test -x "$DIR/sbin/init"); then
      :
    else
      echo "qq: fatal: Alpine Linux not found in directory: $DIR" >&2
      return 110
    fi
    return
  fi
  test "${DIR#/}" = "$DIR" && DIR="./$DIR"
  if test -d "$DIR"; then
    echo "qq: fatal: target directory already exists, not clobbering: $DIR" >&2
    return 100
  fi
  rm  -rf "$DIR.get" 2>/dev/null
  test -d "$DIR.get" && $SUDO rm -rf "$DIR.get"
  if ! mkdir -p "$DIR.get/alpine.dir"; then
    echo "qq: fatal: mkdir failed" >&2
    return 109
  fi
  if test "${VERSION#*.*.*}" != "$VERSION"; then
    VERSION="${VERSION#v}"
    local VERSION_SUFFIX="${VERSION#*.*.}"
    local VERSION_PREFIX="${VERSION%.$VERSION_SUFFIX}"  # 3.8 remains.
    local URL="http://dl-cdn.alpinelinux.org/alpine/v$VERSION_PREFIX/releases/$ARCH/alpine-minirootfs-$VERSION-$ARCH.tar.gz"
    VERSION="v$VERSION"
  else
    test "${VERSION#[0-9]}" = "$VERSION" || VERSION="v$VERSION"
    local URL="http://dl-cdn.alpinelinux.org/alpine/$VERSION/releases/$ARCH/"
    if wget -qO "$DIR.get/alpine.html" "$URL" && test -s "$DIR.get/alpine.html"; then
      :
    else
      echo "qq: fatal: error downloading URL: $URL" >&2
      rm -rf "$DIR.get"
      return 101
    fi
    local FILENAME="$(<"$DIR.get"/alpine.html awk -F'"' '$2~/^alpine-minirootfs-.*[.]tar[.]gz$/&&$2!~/[0-9]_rc[0-9]/{print$2}' | sort | tail -1)"  #'
    if test -z "$FILENAME"; then
      echo "qq: fatal: missing alpine-minirootfs-*.tar.gz in: $URL" >&2
      rm -rf "$DIR.get"
      return 102
    fi
    local URL="http://dl-cdn.alpinelinux.org/alpine/$VERSION/releases/$ARCH/$FILENAME"
  fi
  echo "qq: info: downloading: $URL" >&2
  if wget -qO "$DIR.get/alpine.tar.gz" "$URL" && test -s "$DIR.get/alpine.tar.gz"; then
    :
  else
    echo "qq: fatal: error downloading URL: $URL" >&2
    return 103
  fi
  # tar in Debian slink (1999-03) supports --numeric-owner, but busybox tar doesn't.
  if ! (cd "$DIR.get" &&
        (cd alpine.dir && $SUDO tar --numeric-owner -xzf ../alpine.tar.gz) &&
        $SUDO chmod 755 alpine.dir &&
        $SUDO mv alpine.dir/* ./ &&
        $SUDO rmdir alpine.dir &&
        rm -f alpine.tar.gz alpine.html); then
    echo "qq: fatal: error extracting $DIR.get/alpine.tar.gz" >&2
    rm  -rf "$DIR.get" 2>/dev/null
    test -d "$DIR.get" && $SUDO rm -rf "$DIR.get"
    return 104
  fi
  # TODO(pts): Use staticperl instead, it uses much less disk.
  if ! mv "$DIR".get "$DIR"; then
    echo "qq: fatal: rename failed from: $DIR.get" >&2
    exit 105
  fi
  echo "qq: info: Alpine Linux $VERSION installed to: $DIR" >&2
  __qq_init__ "$DIR"
}

__qq_get_cloud_image__() {
  local URL="$1" ARCH="$2" DISTRO="$3" DIR="$4"

  if test -z "$ARCH"; then
    ARCH="$(uname -m)"
    case "$ARCH" in amd64 | x86_64 | x64) ARCH=i386; esac  # 32-bit default.
  fi
  case "$ARCH" in
   i[3456]86 | x86) ARCH=i386 ;;
   amd64 | x86_64 | x64) ARCH=amd64 ;;
   ppc64el | ppc64le) ARCH=ppc64el ;;
  esac
  if test -z "$ARCH"; then
    echo "qq: fatal: bad architecture" >&2
    return 108
  fi

  local SUDO=sudo
  test "$EUID" = 0 && SUDO=

  test "${DIR#/}" = "$DIR" && DIR="./$DIR"
  if test -d "$DIR"; then
    echo "qq: fatal: target directory already exists, not clobbering: $DIR" >&2
    return 100
  fi
  rm  -rf "$DIR.get" 2>/dev/null
  test -d "$DIR.get" && $SUDO rm -rf "$DIR.get"
  if ! mkdir -p "$DIR.get/rootfs.dir"; then
    echo "qq: fatal: mkdir failed" >&2
    return 109
  fi
  local BASE_URL="${URL%%/streams/v1/*}/"

  echo "qq: info: downloading distro list: $URL" >&2
  # TODO(pts): Try downloading https:// everywhere first.
  if wget -qO "$DIR.get/images.json" "$URL" && test -s "$DIR.get/images.json"; then
    :
  else
    echo "qq: fatal: error downloading URL: $URL" >&2
    rm -rf "$DIR.get"
    return 101
  fi

  local TYPE_AND_URL="$(BASE_URL="$BASE_URL" ARCH="$ARCH" DISTRO="$DISTRO" exec "${__QQPERL__:-perl}" -w -e '
    BEGIN { $^W = 1 }
    use strict;
    use integer;
    $_=join("", <STDIN>);
    my %jsonstr = split(/,/, "b,\b,n,\n,r,\r,t,\t");
    # Poor man"s JSON-parser. Safe (resistant to injection attacks) even with eval below.
    s` ([{}\[\],\s]+) | (:) | "((?:[^\"\\]+|\\.)*)" | (null) | ([-+.\w]+) | (.) `
      if (defined($1)) { $1 }
      elsif (defined($2)) { "=>" }
      elsif (defined($3)) { my $s = $3; $s =~ s@\\(.)@$1@gs; $s=~s@([\\\x27])@\\$1@g; "\x27$s\x27" }  # TODO(pts): Support \uXXXX.
      elsif (defined($4)) { "undef" }
      elsif (defined($5)) { "\x27$5\x27" }  # Includes true and false.
      else { die "bad JSON syntax: $7\n" }
    `gexs; die $@ if $@;
    $_ = eval($_);
    die "bad json parse: $@\n" if $@;
    #use Data::Dumper; print Dumper($_);
    my %all_archs;
    my %all_distros;
    my $match_distro = $ENV{DISTRO};
    my $last_url;
    my $last_type;
    BEGIN { $^W = 0 }  # No warnings about undefined values.
    for (values(%{$_->{products}})) {
      $all_archs{$_->{arch}} = 1;
      my %distros;
      $distros{"\L$_->{os}/$_->{release}"} = 1 if $_->{release};
      $distros{"$_->{release}"} = 1 if $_->{release};
      $distros{"\L$_->{os}/$_->{release_title}"} = 1 if $_->{release_title};
      $distros{"$_->{release_title}"} = 1 if $_->{release_title};
      for my $alias (split(/[\s,]+/, $_->{aliases})) {
        $distros{"\L$_->{os}/$alias"} = 1;
        $distros{"\L$alias"} = 1;
      }
      for my $distro (keys(%distros)) { $all_distros{$distro} = 1 }
      next if $_->{arch} ne $ENV{ARCH} or !exists($distros{$match_distro});
      # Typical: version: "20181227_04:59", "20171031".
      for my $version (sort keys(%{$_->{versions}})) {
        my $item_dict = $_->{versions}{$version}{items};
        my ($type, $url);
        if ($item_dict->{"root.tar.xz"}{path}) {  # TODO(pts): Save type.
          $url = $item_dict->{"root.tar.xz"}{path};  # TODO(pts): Prefer .tar.xz if available and xz is not $PATH.
          $type = "root.tar.xz";
        } elsif ($item_dict->{"root.tar.gz"}{path}) {  # Do not look at "tar.gz", it contains a filesystem image (.img).
          $url = $item_dict->{"root.tar.gz"}{path};
          $type = "root.tar.gz";
        } elsif ($item_dict->{"root.squashfs"}{path}) {
          # Example: qq get-ubuntu zesty zesty_dir
          $url = $item_dict->{"root.squashfs"}{path};
          $type = "root.squashfs";
        } elsif ($item_dict->{"squashfs"}{path}) {
          $url = $item_dict->{"squashfs"}{path};
          $type = "root.squashfs";
        } elsif ($item_dict->{"tar.gz"}{path}) {
          # Example: qq get-ubuntu lucid lucid_dir
          # http://cloud-images.ubuntu.com/releases/server/releases/lucid/release-20150427/ubuntu-10.04-server-cloudimg-i386.tar.gz
          # ubuntu-10.04-server-cloudimg-i386.tar.gz contains:
          # -rw-r--r-- 1 root root       3657 Apr 27  2015 README.files
          # -rw-r--r-- 1 root root      91708 Apr 27  2015 lucid-server-cloudimg-i386-loader
          # -rw-r--r-- 1 root root    4215040 Apr 27  2015 lucid-server-cloudimg-i386-vmlinuz-virtual
          # -rw-r--r-- 1 root root 1476395008 Apr 27  2015 lucid-server-cloudimg-i386.img
          # The file lucid-server-cloudimg-i386.img is a 1.4 GiB ext3
          # filesystem image, we would need so much temporary disk space.
          $url = $item_dict->{"tar.gz"}{path};
          $type = "img.tar.gz";
        }
        if (defined($url)) {
          $url =~ s@\A/+@@;
          # Example $url: server/releases/zesty/release-20171121/ubuntu-17.04-server-cloudimg-armhf.tar.gz -> http://cloud-images.ubuntu.com/releases/server/releases/zesty/release-20171121/ubuntu-17.04-server-cloudimg-armhf.tar.gz
          $url = "$ENV{BASE_URL}$url" if $url !~ m@://@;
          #die $url;
          ($last_type, $last_url) = ($type, $url);  # Corresponding to the largest $version.
        }
      }
    }
    die "qq: fatal: root image of requested <distro>=$match_distro --arch=$ENV{ARCH} not found\n" .
        "qq: fatal: available <distro> values: @{[sort keys %all_distros]}\n" .
        "qq: fatal: --arch values: @{[sort keys %all_archs]}\n" if !defined($last_url);
    print "$last_type:$last_url"
  ' <"$DIR.get/images.json")"
  local TYPE="${TYPE_AND_URL%%:*}"
  URL="${TYPE_AND_URL#*:}"
  if test -z "$TYPE_AND_URL" || test "$TYPE" = "$TYPE_AND_URL"; then
    rm -rf "$DIR.get"
    return 102
  fi
  rm -f "$DIR.get/images.json"

  echo "qq: info: downloading root filesystem: $URL" >&2
  if test "$TYPE" = root.tar.gz; then
    # TODO(pts): Detect partial downloads.
    (wget -nv -O- "$URL" && : >"$DIR.get/download.ok") | (cd "$DIR.get/rootfs.dir" && $SUDO tar --numeric-owner -xz && : >"../extract.ok")
  elif test "$TYPE" = root.tar.xz; then
    (wget -nv -O- "$URL" && : >"$DIR.get/download.ok") | (cd "$DIR.get/rootfs.dir" && $SUDO tar --numeric-owner -xJ && : >"../extract.ok")
  elif test "$TYPE" = root.squashfs; then
    if wget -nv -O "$DIR.get/rootfs.squashfs" "$URL"; then
      # We need to support .squashfs, because .tar.gz and .tar.xz are missing for:
      # qq get-ubuntu zesty zesty_dir  # http://cloud-images.ubuntu.com/releases/server/releases/zesty/release-20171208/ubuntu-17.04-server-cloudimg-i386.squashfs
      echo "qq: info: extractiong root filesystem: $DIR.get/rootfs.squashfs" >&2
      if type -p unsquashfs >/dev/null 2>&1; then
        if $SUDO unsquashfs -n -f -d "$DIR.get/rootfs.dir" "$DIR.get/rootfs.squashfs"; then
          : >"$DIR.get/download.ok"
          : >"$DIR.get/extract.ok"
        else
          echo "qq: fatal: unsquashfs failed" >&2
        fi
      else
        if (cd "$DIR.get" &&
            mkdir rootfs.sqm &&
            $SUDO mount -t squashfs -o loop,ro,nodev,nosuid,noatime rootfs.squashfs rootfs.sqm &&
            # Better preserves hard links than `cp -a'.
            (cd rootfs.sqm && $SUDO tar --numeric-owner -c . && : >../download.ok) | (cd rootfs.dir && $SUDO tar --numeric-owner -x && : >../extract.ok) &&
            $SUDO umount rootfs.sqm &&
            rmdir rootfs.sqm); then
          : >"$DIR.get/extract.ok"
        else
          echo "qq: fatal: by-kernel extraction of squashfs failed" >&2
          test -e "$DIR.get/rootfs.sqm" && $SUDO umount "$DIR.get/rootfs.sqm" 2>/dev/null
          test -d "$DIR.get/rootfs.sqm" && rmdir rootfs.sqm
        fi
      fi
    fi
  elif test "$TYPE" = img.tar.gz; then
    # This is a bit tricy because we want to kill wget and tar (with SIGPIPE
    # by default) as soon as tar prints a filename ending with .img. Regular
    # shell pipelines don't give us this, so we implement it with Perl.
    local IMG_FILENAME="$(cd "$DIR.get" && URL="$URL" exec "${__QQPERL__:-perl}" -we '
        $SIG{PIPE} = "DEFAULT";
        die "qq fatal: open tar.out: $!\n" if !open(TARO, "> tar.out");
        close(TARO);
        die "qq: fatal: open wget: $!\n" if !open(WGET, "exec wget -qO- \"\$URL\"|");
        die "qq: fatal: open tar: $!\n" if !open(TART, "|exec tar --numeric-owner -tz >tar.out 2>/dev/null");
        sub maybe_finish() {
          if (-s("tar.out")) {
            die if !open(TARO, "< tar.out");
            for (<TARO>) {
              print($_),exit() if m@[.]img$@;
            }
            close(TARO);
          }
        }
        while (sysread(WGET, $_, 65536) > 0) {
          die "qq: fatal: syswrite to tar: $!\n" if syswrite(TART, $_, length($_)) != length($_);
          maybe_finish();
        }
        close(TART);
        maybe_finish()')"
    rm -f "$DIR.get/tar.out"
    if test -z "$IMG_FILENAME"; then
      echo "qq: fatal: .img file not found in: ${URL##*/}" >&2
    else
      echo "qq: info: downloading root filesystem image $IMG_FILENAME from: $URL" >&2
      (wget -nv -O- "$URL" && : >"$DIR.get/download.ok") | ($SUDO tar --numeric-owner -xzO "$IMAGE_FILENAME" >"$DIR.get/rootfs.img" && : >"$DIR.get/tar_extract.ok")
      if ! (test -f "$DIR.get/download.ok" && test -f "$DIR.get/tar_extract.ok"); then
        echo "qq: fatal: root filesystem image extraction failed: $IMG_FILENAME" >&2
      else
        if (cd "$DIR.get" &&
            mkdir rootfs.mounted &&
            # Typically an ext3 filesystem.
            $SUDO mount -o loop,ro,nodev,nosuid,noatime rootfs.img rootfs.mounted &&
            # Better preserves hard links than `cp -a'.
            (cd rootfs.mounted && $SUDO tar --numeric-owner -c . && : >../download.ok) | (cd rootfs.dir && $SUDO tar --numeric-owner -x && : >../extract.ok) &&
            $SUDO umount rootfs.mounted &&
            rmdir rootfs.mounted); then
          : >"$DIR.get/extract.ok"
        else
          echo "qq: fatal: by-kernel extraction of rootfs.img failed" >&2
          test -e "$DIR.get/rootfs.mounted" && $SUDO umount "$DIR.get/rootfs.mounted" 2>/dev/null
          test -d "$DIR.get/rootfs.mounted" && rmdir rootfs.mounted
        fi
      fi
    fi
  else
    echo "qq: fatal: unknown type $TYPE for file: ${URL##*/}" >&2
  fi
  if ! (test -f "$DIR.get/download.ok" && test -f "$DIR.get/extract.ok"); then
    echo "qq: fatal: error downloading root filesystem: $URL" >&2
    # TODO(pts): Do this cleanup on interrupt exit as well (with trap).
    rm  -rf "$DIR.get" 2>/dev/null
    test -d "$DIR.get" && $SUDO rm -rf "$DIR.get"
    return 103
  fi
  rm -f "$DIR.get/download.ok" "$DIR.get/extract.ok" "$DIR.get/tar_extract.ok" "$DIR.get/rootfs.squashfs" "$DIR.get/rootfs.img"
  if ! ( cd "$DIR.get" &&
         $SUDO chmod 755 rootfs.dir &&
         $SUDO mv rootfs.dir/* ./ &&
         $SUDO rm -rf rootfs.dir &&
         cd .. &&
         mv "$DIR".get "$DIR"); then
    echo "qq: fatal: rename failed from: $DIR.get" >&2
    rm  -rf "$DIR.get" 2>/dev/null
    test -d "$DIR.get" && $SUDO rm -rf "$DIR.get"
    return 104
  fi
  echo "qq: info: Linux distro $DISTRO installed to: $DIR" >&2
  __qq_init__ "$DIR"
}

# Download from http://images.linuxcontainers.org/
__qq_get_lxc__() {
  local ARCH=
  if test "$1" = --arch && test $# -gt 1; then
    ARCH="$2"
    shift; shift
  fi
  if test -z "$1" || test "$1" = --help || test $# != 2; then
    echo "Usage:   $0 get-lxc [--arch=<arch>] <distro> <target-dir>" >&2
    echo "Example: $0 get-lxc centos/6 centos6_dir" >&2
    echo "Architectures (<arch>): i386 (x86), amd64 (x86_64), s390x, ppc64el, armhf, aarch64." >&2
    return 1
  fi
  # Typically redirects to http://uk.images.linuxcontainers.org/...
  # http://uk.images.linuxcontainers.org/streams/v1/index.json
  __qq_get_cloud_image__ http://images.linuxcontainers.org/streams/v1/images.json "$ARCH" "$@"
}

# Download from http://cloud-images.ubuntu.com/
__qq_get_ubuntu__() {
  local ARCH=
  if test "$1" = --arch && test $# -gt 1; then
    ARCH="$2"
    shift; shift
  fi
  if test -z "$1" || test "$1" = --help || test $# != 2; then
    echo "Usage:   $0 get-ubuntu [--arch=<arch>] <distro> <target-dir>" >&2
    echo "Example: $0 get-ubuntu bionic bionic_dir" >&2
    echo "Architectures (<arch>): i386 (x86), amd64 (x86_64), s390x, ppc64el, armhf, aarch64." >&2
    return 1
  fi
  # http://cloud-images.ubuntu.com/releases/streams/v1/index.json
  __qq_get_cloud_image__ http://cloud-images.ubuntu.com/releases/streams/v1/com.ubuntu.cloud:released:download.json "$ARCH" "$@"
}

# Download from Docker Hub (https://hub.docker.com/).
__qq_get_docker__() {
  if test -z "$1" || test "$1" = --help || test $# != 2; then
    echo "Usage:   $0 get-docker <image> <target-dir>" >&2
    echo "Example: $0 get-docker busybox busybox_dir" >&2
    echo "Example: $0 get-docker alpine alpine_dir" >&2
    echo "Example: $0 get-docker bitnami/minideb:stretch stretch_dir" >&2
    return 1
  fi
  local IMAGE="$1" DIR="$2"

  local SUDO=sudo
  test "$EUID" = 0 && SUDO=

  test "${DIR#/}" = "$DIR" && DIR="./$DIR"
  if test -d "$DIR"; then
    echo "qq: fatal: target directory already exists, not clobbering: $DIR" >&2
    return 100
  fi
  rm  -rf "$DIR.get" 2>/dev/null
  test -d "$DIR.get" && $SUDO rm -rf "$DIR.get"
  if ! mkdir -p "$DIR.get"; then
    echo "qq: fatal: mkdir failed" >&2
    return 109
  fi

  if ! docker version >/dev/null 2>&1; then
    echo "qq: fatal: please install Docker first" >&2
    return 101
  fi

  local CONTAINER="qq_get_docker__$(echo "$IMAGE" | "${__QQPERL__:-perl}" -pe 's@[^-\w\n]+@__@g')"
  docker rm -f "$CONTAINER" >/dev/null 2>&1
  echo "qq: info: downloading Docker image: $IMAGE" >&2
  if ! docker create --name "$CONTAINER" "$IMAGE" >/dev/null; then
    echo "qq: fatal: error downloading Docker image: $IMAGE" >&2
    docker rm "$CONTAINER" >/dev/null
    return 102
  fi
  echo "qq: info: extracting  Docker image: $IMAGE" >&2
  if ! (docker export "$CONTAINER" | (cd "$DIR.get" && $SUDO tar --numeric-owner -x && $SUDO sh -c ': >>extract.ok')); then
    echo "qq: fatal: error extracting Docker image: $IMAGE" >&2
    docker rm "$CONTAINER" >/dev/null
    rm  -rf "$DIR.get" 2>/dev/null
    test -d "$DIR.get" && $SUDO rm -rf "$DIR.get"
    return 103
  fi
  if ! (test -f "$DIR.get/extract.ok" &&
        # /etc/qqsystem is needed by $IMAGE busybox, because it doesn't have /sbin/init and /etc/issue.
        $SUDO sh -c 'rm -f "$1/extract.ok" && mkdir -p "$1"/etc && : >>"$1/etc/qqsystem"' . "$DIR.get" &&
        docker rm "$CONTAINER" >/dev/null &&
        mv "$DIR".get "$DIR"); then
    echo "qq: fatal: error fixing Docker image: $IMAGE" >&2
    docker rm "$CONTAINER" >/dev/null
    rm  -rf "$DIR.get" 2>/dev/null
    test -d "$DIR.get" && $SUDO rm -rf "$DIR.get"
    return 103
  fi
  echo "qq: info: Docker image $IMAGE installed to: $DIR" >&2
  __qq_init__ "$DIR"
}

__qq__() {
  if test "$1" = pts-debootstrap; then shift; __qq_pts_debootstrap__ "$@"; return "$?"
  elif test "$1" = get-alpine; then shift; __qq_get_alpine__ "$@"; return "$?"
  elif test "$1" = get-lxc; then shift; __qq_get_lxc__ "$@"; return "$?"
  elif test "$1" = get-ubuntu; then shift; __qq_get_ubuntu__ "$@"; return "$?"
  elif test "$1" = get-docker; then shift; __qq_get_docker__ "$@"; return "$?"
  fi
  local __QQD__ __QQPWD__ __QQOLDPWD__ __QQFOUND__
  __QQOLDPWD__="$PWD"
  test "${__QQOLDPWD__#/}" = "$__QQOLWPWD__" && __QQOLDPWD__="$(pwd)"
  if test "${__QQOLDPWD__#/}" = "$__QQOLDPWD__"; then
    echo "qq: fatal: cannot find current directory: $__QQOLDPWD__" >&2
    return 123
  fi
  while test "${__QQOLDPWD__#//}" != "$__QQOLDPWD__"; do
    __QQOLDPWD__="${__QQOLDPWD__#/}"  # Remove duplicate leading slashes.
  done
  if test "$1" = use-workdir && test $# -gt 1; then
    __QQD__="$2"; shift; shift
    if ! test -d "$__QQD__"; then
      echo "qq: fatal: not a directory: $__QQD__" >&2
      return 122
    fi
    test "${__QQD__#/}" = "$__QQD__" && __QQD__="$(cd "$__QQD__" && pwd)"
    if test "${__QQD__#/}" = "$__QQD__"; then
      echo "qq: fatal: cannot find work directory: $__QQD__" >&2
      return 123
    fi
  else
    __QQD__="$__QQOLDPWD__"
    __QQOLDPWD__=
  fi
  while test "${__QQD__#//}" != "$__QQD__"; do
    __QQD__="${__QQD__#/}"  # Remove duplicate leading slashes.
  done
  __QQPWD__="$__QQD__"
  while test "$__QQD__"; do
    __QQFOUND__=1
    test -x "$__QQD__/sbin/init" && test -f "$__QQD__/etc/issue" && break
    test -h "$__QQD__/sbin/init" && test -f "$__QQD__/etc/issue" && break
    test -f "$__QQD__/etc/qqsystem" && break
    __QQFOUND__=
    test "${__QQD__%/*}" = "$__QQD__" && break
    __QQD__="${__QQD__%/*}"
  done
  if test -z "$__QQFOUND__"; then
    echo "qq: fatal: system-in-chroot not found up from: $__QQPWD__" >&2
    return 124
  fi
  local __QQLIB__='
BEGIN { $^W = 1 }
use integer;
use strict;

my $qqin = "qqin";  # Can be overwritten.

# Linux-specific constants.
sub CLONE_NEWUSER() { 0x10000000 }  # New user namespace.
sub CLONE_NEWNS() { 0x20000 }       # New mount namespace.
sub CLONE_NEWIPC() { 0x08000000 }   # New IPC namespace.
sub MS_RDONLY() { 0x1 }
sub MS_BIND() { 0x1000 }
sub MS_MOVE() { 0x2000 }
sub MS_REC() { 0x4000 }
sub MS_PRIVATE() { 0x40000 }
sub MS_SLAVE() { 0x80000 }
sub O_RDONLY { 0 }
sub O_DIRECTORY() { 00200000 }
sub MNT_DETACH() { 2 }

# Returns (undef, $SYS_mount, $SYS_unshare, $SYS_pivot_root, $SYS_fchdir, $SYS_umount2) or
# ($error, undef, undef, undef, undef).
sub detect_linux_syscalls() {
  return ("Linux operating system needed", undef, undef) if $^O ne "linux";
  # We figure out the architecture of the current process by opening the Perl
  # interpreter binary. Doing require POSIX; die((POSIX::uname())[4])
  # would not work, because it would return x86_64 for an i386 process running
  # on an amd64 kernel.
  my $perl_prog = $^X;
  if ($perl_prog !~ m@/@) {
    # Perl 5.004 does not have a path to "perl" in $^X, it just has "perl".
    # We look it up on $ENV{PATH}.
    my $perl_filename = $perl_prog;
    $perl_prog = undef;
    for my $dir (split(/:+/, $ENV{PATH})) {
      next if !length($dir);
      $perl_prog = "$dir/$perl_filename";
      last if -e $perl_prog;
      $perl_prog = undef;
    }
    return "Perl interpreter not found on \$ENV{PATH}: $perl_filename" if
        !defined($perl_prog);
  }
  local *FH;
  return ("open $^X: $!", undef, undef) if !open(FH, "< $perl_prog");
  my $got = sysread(FH, $_, 52);
  return ("read $^X: $!", undef, undef) if ($got or 0) < 52;
  return ("close $^X: $!", undef, undef) if !close(FH);
  my $arch = "unknown";
  my ($SYS_mount, $SYS_unshare);
  # All architectures supported by Debian 9 Stretch are here, plus some more.
  # https://en.wikipedia.org/wiki/Executable_and_Linkable_Format#File_header
  # System call numbers: https://fedora.juszkiewicz.com.pl/syscalls.html
  if (/\A\x7FELF\x02\x01\x01[\x00\x03]........[\x02\x03]\x00\x3E/s) {
    $arch = "amd64";  # x86_64, x64.
    return (undef, 165, 272, 155, 81, 166);
  } elsif (/\A\x7FELF\x02\x01\x01[\x00\x03]........[\x02\x03]\x00\xB7/s) {
    $arch = "aarch64";  # arm64.
    return (undef, 40, 97, 41, 50, 39);
  } elsif (/\A\x7FELF\x01\x01\x01[\x00\x03]........[\x02\x03]\x00\x03/s) {
    $arch = "i386";  # i486, i586, i686, x86.
    return (undef, 21, 310, 217, 133, 52);
  } elsif (/\A\x7FELF\x01\x01\x01[\x00\x03]........[\x02\x03]\x00\x28/s) {
    $arch = "arm";  # arm32, armel, armhf.
    return (undef, 21, 337, 218, 133, 52);
  } elsif (/\A\x7FELF\x02\x02\x01[\x00\x03]........\x00[\x02\x03]\x00/s) {
    $arch = "s390x";  # s390. s390x for Debian 9. Last byte is 0 (no architecture).
    return (undef, 21, 303, 217, 133, 52);
  } elsif (/\A\x7FELF\x01\x02\x01[\x00\x03]........\x00[\x02\x03][\x00\x08]/s) {
    $arch = "mips";  # mips for Debian 9. Last byte is 0 (no architecture).
    return (undef, 4021, 4303, 4216, 4133, 4052);
  } elsif (/\A\x7FELF\x02\x01\x01[\x00\x03]........[\x02\x03]\x00\x08/s) {
    $arch = "mips64el";
    return (undef, 5160, 5262, 5151, 5079, 5161);  # For mips64n32, SYS_unshare is 6266.
  } elsif (/\A\x7FELF\x01\x01\x01[\x00\x03]........[\x02\x03]\x00\x08/s) {
    $arch = "mipsel";  # Like mips, but LSB-first (little endiel).
    return (undef, 4021, 4303, 4216, 4133, 4052);
  } elsif (/\A\x7FELF\x02\x01\x01[\x00\x03]........[\x02\x03]\x00\x15/s) {
    $arch = "ppc64el";  # ppc64, powerpc64.
    return (undef, 21, 282, 203, 133, 52);
  } elsif (/\A\x7FELF\x01\x01\x01[\x00\x03]........[\x02\x03]\x00\x15/s) {
    $arch = "ppc32el";  # ppc32, powerpc32, powerpc.
    return (undef, 21, 282, 203, 133, 52);
  } else {
    return ("unknown architecture for the Perl process\n", undef, undef);
  }
}

# Returns true iff entry was already there.
sub ensure_auth_line($$;$) {
  my($filename, $line, $is_check) = @_;
  $line =~ s@\n@@g;
  $line .= "\n";
  die "$qqin: assert: bad auth line: $line" if $line !~ m@\A([^:\n]+:)@;
  my $prefix = $1;
  local *FH;  # my($fh) does not work in Perl 5.004.
  my $is_readonly = !open(FH, "+< $filename");
  die "$qqin: fatal: open $filename: $!\n" if
      $is_readonly and !open(FH, "< $filename");
  my $fl;
  while (defined($fl = <FH>)) {
    if (substr($fl, 0, length($prefix)) eq $prefix) {
      close(FH);
      return 1;
    }
  }
  if ($is_check) {
    close(FH);
    return 0;
  }
  if ($is_readonly) {
    die "$qqin: fatal: open-write $filename: $!\n" if !open(FH, "+< $filename");
  } else {
    die "$qqin: fatal: seek: $!\n" if !sysseek(FH, 0, 2);
  }
  die "$qqin: fatal: syswrite: $!\n" if
      length($line) != (syswrite(FH, $line, length($line)) or 0);
  die "$qqin: fatal: close: $!\n" if !close(FH);
  0
}

sub get_username() {
  my @pwd = getpwuid($>);
  @pwd = ($ENV{USER} or $ENV{LOGNAME}) if !@pwd;
  die "$qqin: fatal: cannot detect username\n" if !@pwd;
  $pwd[0]
}

sub is_owned_and_rwx($$) {
  my ($path, $uid) = @_;
  my @stat = stat($path);
  @stat and $stat[4] == $uid and ($stat[2] & 0700) == 0700;
}
'
  __QQPRESUDO__='
# qqpresudo: Entry point for qq before sudo or unshare.

'"$__QQLIB__"'

$qqin = "qqpresudo";
my $qqd = $ENV{__QQD__};
die "$qqin: fatal: empty \$ENV{__QQD__}\n" if !defined($qqd) or !length($qqd);
die "$qqin: fatal: \$ENV{__QQD__} does not start with /: $qqd" if
    substr($qqd, 0, 1) ne "/";

# Returns $syscall_error which is undef on no error, otherwise true.
sub try_unshare(;$) {
  my $do_ignore_dirs = $_[0];
  my ($unshare_error, $SYS_mount, $SYS_unshare) = detect_linux_syscalls();
  if (defined($unshare_error) or !defined($SYS_unshare)) {
    $unshare_error = "detect_linux_syscalls failed" if !defined($unshare_error);
  } elsif ($< != $>) {
    $unshare_error = "real and effective UID are different (running as setuid?)";
  } elsif ($( + 0 != $) + 0) {
    $unshare_error = "real and effective GID are different (running as setgid?)";
  } else {
    my $pid = fork();
    exit(!(!(syscall($SYS_unshare, CLONE_NEWUSER)))) if !$pid;  # Child.
    my $pid2 = waitpid($pid, 0);
    if (!($pid == $pid2 and $? == 0)) {
      $unshare_error = "unshare CLONE_NEWUSER failed";
    } else {  # Check that whatever qqin is doing to set up as root has been done.
      my $username = eval { get_username() };
      if (!defined($username)) {
        $unshare_error = "cannot detect username";
      } elsif (!stat("$qqd/proc") or !-d(_)) {
        # TODO(pts): Do not follow local symlinks above and elsewhere.
        #            Maybe use code like this: https://github.com/opencontainers/runc vendor/github.com/cyphar/filepath-securejoin/join.go
        $unshare_error = "not a directory: $qqd/proc";
      } elsif (!stat("$qqd/dev/pts") or !-d(_)) {
        # TODO(pts): Do not follow local symlinks above and elsewhere.
        $unshare_error = "not a directory: $qqd/dev/pts";
      } elsif (!$do_ignore_dirs and (readlink("$qqd$qqd") or 0) ne "/") {
        # TODO(pts): Do not follow local symlinks above and elsewhere.
        $unshare_error = "symlink does not point to /: $qqd$qqd";
      } elsif (!$do_ignore_dirs and !-d("$qqd/home/$username")) {
        # TODO(pts): Do not follow local symlinks above and elsewhere.
        $unshare_error = "home directory does not exist: $qqd/home/$username";
      } elsif (!$do_ignore_dirs and !is_owned_and_rwx("$qqd/home/$username", $>)) {
        # TODO(pts): Do not follow local symlinks above and elsewhere.
        $unshare_error = "home directory not owned by $username and rwx: $qqd/home/$username";
      } elsif (!$do_ignore_dirs and !ensure_auth_line("$qqd/etc/passwd", "$username:", 1)) {
        # TODO(pts): Do not follow local /etc symlinks above and elsewhere.
        # TODO(pts): Try to fix it if /etc/passwd, /etc/group and /etc/shadow are writable.
        # TODO(pts): Also check that the UID and GID are specified correctly.
        $unshare_error = "username $username missing from passwd (to fix, run \`qq root id\x27): $qqd/etc/passwd";
      } else {
        $unshare_error = undef;
      }
    }
  }
  $unshare_error
}

my @sudo = ("sudo", "-E");  # Preserve the environment.
$ENV{__QQUNSHARE__} = 0;
my @run_as_root = (
    "root", "su", "sudo", "login", "passwd", "apt-get", "apt", "dpkg", "rpm",
    "yum", "apk");
if (@ARGV and grep ({ $_ eq $ARGV[0] } @run_as_root)) {
  unshift @ARGV, "root" if $ARGV[0] ne "root";
} elsif (@ARGV and $ARGV[0] eq "use-sudo") {  # Override autodetection.
  shift @ARGV;
} elsif (@ARGV and ($ARGV[0] eq "use-unshare" or $ARGV[0] eq "use-rootless")) {  # Override autodetection.
  shift @ARGV;
  my $unshare_error = try_unshare(1);  # With $do_ignore_dirs=1, we will create those directories later.
  die "$qqin: fatal: use-unshare failed: $unshare_error\n" if
      $unshare_error;
  @sudo = ();
  $ENV{__QQUNSHARE__} = 1;  # Use unshare (rootless) instead of sudo + chroot.
} elsif (!$>) {  # Running as root (EUID 0), no need to run sudo manually.
  @sudo = ();
  unshift @ARGV, "root";  # Make sure qqin does not look for $ENV{SUDO_USER} etc.
} elsif (-f("$qqd/etc/qqforceroot")) {
} elsif (!try_unshare()) {
  @sudo = ();
  $ENV{__QQUNSHARE__} = 1;  # Use unshare (rootless) instead of sudo + chroot.
}
if ($ENV{__QQUNSHARE__}) {
  die "$qqin: fatal: real and effective UID are different (running as setuid?)\n" if $< != $>;
  die "$qqin: fatal: real and effective UID are different (running as setgid?)\n" if $( + 0 != $) + 0;
  $ENV{USER} = $ENV{LOGNAME} = $ENV{USERNAME} = get_username();
  ($ENV{SUDO_USER}, $ENV{SUDO_UID}, $ENV{SUDO_GID}) = ($ENV{USER}, $>, $) + 0);
} else {
  delete @ENV{"USER", "LOGNAME", "USERNAME", "SUDO_USER", "SUDO_UID", "SUDO_GID"};
}
die "$qqin: fatal: exec failed: $!\n" if
    !exec(@sudo, $^X, "-weeval\$ENV{__QQIN__};die\$\@if\$\@", "--", @ARGV);
' __QQIN__='
# qqin: Entry point for qq after sudo.
#
# This Perl script can manage environment variables (and pass them to the
# command in @ARGV) precisely, because it does not invoke a shell, does not
# invoke su(1) or sudo(1).
#
# TODO(pts): Set up /etc/hosts and /etc/resolve.conf automatically.
# TODO(pts): Support qq1, qq2 (i.e. multiple execution environments). How
#            can they see the same local directory?

'"$__QQLIB__"'

my $qqd = $ENV{__QQD__};
my $qqpath = $ENV{__QQPATH__};
my $qqpwd = $ENV{__QQPWD__};
my $qqoldpwd = $ENV{__QQOLDPWD__};
$qqoldpwd = undef if defined($qqoldpwd) and !length($qqoldpwd);
my $home = $ENV{__QQHOME__};
die "$qqin: fatal: empty \$ENV{__QQD__}\n" if !defined($qqd) and !length($qqd);
die "$qqin: fatal: empty \$ENV{__QQPATH__}\n" if !$qqpath;
# Too late for a getpwnam or getpwuid after a chroot.
die "$qqin: fatal: empty \$ENV{__QQHOME__}\n" if !$home;
die "$qqin: fatal: bad QQD snytax: $qqd\n" if $qqd !~ m@\A(/[^/]+)+@;
die "$qqin: fatal: bad QQPWD snytax: $qqpwd\n" if $qqpwd !~ m@\A(/[^/]+)+@;
die "$qqin: fatal: bad QQOLDPWD snytax: $qqoldpwd\n" if defined($qqoldpwd) and $qqoldpwd !~ m@\A(/[^/]+)+@;
die "$qqin: fatal: missing \$ENV{__QQUNSHARE__}" if !defined($ENV{__QQUNSHARE__});
my $do_unshare=!(!($ENV{__QQUNSHARE__}));
die "$qqin: fatal: QQD is not a prefix of QQPWD" if
    0 == length($qqpwd) or substr("$qqpwd/", 0, length($qqd) + 1) ne "$qqd/";
if ($ENV{__QQLCALL__}) {
  $ENV{LC_ALL} = $ENV{__QQLCALL__};
} else {
  delete $ENV{LC_ALL};
}
delete @ENV{"__QQD__", "__QQPWD__", "__QQOLDPWD__", "__QQPERL__", "__QQPATH__", "__QQHOME__", "__QQLCALL__", "__QQIN__", "__QQPRESUDO__", "__QQUNSHARE__"};
# We must call this before chroot(...), for the correct $^X value.
my ($syscall_error, $SYS_mount, $SYS_unshare, $SYS_pivot_root, $SYS_fchdir, $SYS_umount2) = detect_linux_syscalls();
umask(0022);

if ($do_unshare) {
  # $ENV{SUDO_USER}, $ENV{SUDO_UID} and $ENV{SUDO_GID} is already set up by qqpresudo.
  # Do the CLONE_NEWUSER + uid_map magic. Without this CLONE_NEWNS would
  # return EPERM.
  my $pid = $$;
  local (*HR, *PW, *PR, *HW);
  die "$qqin: fatal: pipe1: $!\n" if !pipe(HR, PW);
  die "$qqin: fatal: pipe2: $!\n" if !pipe(PR, HW);
  my $child_pid = fork();
  die "$qqin: fatal: fork: $!\n" if !defined($child_pid);
  if (!$child_pid) {  # Child process.
    close(PR); close(PW);
    # Wait for parent do CLONE_NEWUSER first.
    exit(-1) if !sysread(HR, $_, 1);
    local *FH;
    die "$qqin: fatal: child: open uid_map: $!\n" if !open(FH, "> /proc/$pid/uid_map");
    $_ = "$> $> 1\n";  # Unfortunately we are not able to map just any in-chroot UID to $>.
    die "$qqin: fatal: child: write uid_map: $!\n" if (syswrite(FH, $_, length($_)) or 0) != length($_);
    die "$qqin: fatal: child: close uid_map: $!\n" if !close(FH);
    die "$qqin: fatal: child: open setgroups: $!\n" if !open(FH, "> /proc/$pid/setgroups");
    # This disables the groups: groups=65534(nogroup),65534(nogroup),... .
    $_ = "deny\n";
    die "$qqin: fatal: child: write setgroups: $!\n" if (syswrite(FH, $_, length($_)) or 0) != length($_);
    die "$qqin: fatal: child: close setgroups: $!\n" if !close(FH);
    die "$qqin: fatal: child: open gid_map: $!\n" if !open(FH, "> /proc/$pid/gid_map");
    $_ = ($) + 0)." ".($) + 0)." 1\n";
    die "$qqin: fatal: child: write gid_map: $!\n" if (syswrite(FH, $_, length($_)) or 0) != length($_);
    die "$qqin: fatal: child: close gid_map: $!\n" if !close(FH);
    $_ = "B";
    die "$qqin: fatal: child: write helper: $!\n" if !syswrite(HW, $_, 1);
    exit(0);
  }
  close(HR); close(HW);
  # CLONE_NEWUSER needs Linux >=3.8 if run as non-root, otherwise EPERM.
  die "$qqin: fatal: CLONE_NEWUSER: $!\n" if syscall($SYS_unshare, CLONE_NEWUSER);
  $_ = "A";
  # Signal the child that it can start writing files in /proc.
  die "$qqin: fatal: child: write primary: $!\n" if !syswrite(PW, $_, 1);
  # Wait for the child to finish writing to /proc.
  die "$qqin: fatal: error in child\n" if !sysread(PR, $_, 1);
  close(PR); close(PW);
  my $child_pid2 = waitpid($child_pid, 0);
  die "$qqin: fatal: bad child_pid2\n" if $child_pid2 != $child_pid;
  die "$qqin: fatal: error in child: ".sprintf("0x%x")."$?\n" if $?;
} else {
  #die "$qqin: fatal: unexpected \$0: $0\n" if $0 ne "...";
  die "$qqin: fatal: must be run as root\n" if $> != 0;
  $( = 0;
  $) = "0 0";  # Also involves an empty setgroups.
  $< = 0;  # setuid(0).
}

if ($do_unshare) {
  die "$qqin: fatal: SYS_unshare not detected\n" if !defined($SYS_unshare);
  die "$qqin: fatal: unshare CLONE_NEWNS: $!\n" if
      syscall($SYS_unshare, CLONE_NEWNS);
  my @spec = ("none", "/", 0, MS_REC | MS_PRIVATE, 0);
  die "$qqin: fatal: mount /: $!\n" if syscall($SYS_mount, @spec);
} else {
  # We must call this on our root (/) before chroot to take effect.
  if (defined($SYS_unshare) and !syscall($SYS_unshare, CLONE_NEWNS)) {
    # Without this call CLONE_NEWS does not take effect when run as root.
    my @spec = ("none", "/", 0, MS_REC | MS_PRIVATE, 0);
    syscall($SYS_mount, @spec);
  }
}

# Follows symlinks. Good.
sub is_same_dir($$) {
  my @stata = stat($_[0]);
  die "$qqin: fatal: stat $_[0]: $!\n" if !@stata;
  return 0 if !-d(_);
  my @statb = stat($_[1]);
  die "$qqin: fatal: stat $_[1]: $!\n" if !@statb;
  ($stata[0] == $statb[0]) and ($stata[1] == $statb[1])  # st_dev and st_ino.
}

if (!-d("$qqd/proc")) {  # TODO(pts): Disallow symlinks in $qqd/proc.
  mkdir("$qqd/proc", 0755);
  die "$qqin: fatal: not a directory: $qqd/proc\n" if !-d("$qqd/proc");
}
if (!-d("$qqd/dev/pts")) {  # TODO(pts): Disallow symlinks.
  mkdir("$qqd/dev", 0755);
  mkdir("$qqd/dev/pts", 0755);
  die "$qqin: fatal: not a directory: $qqd/dev/pts\n" if !-d("$qqd/dev/pts");
}
if (!-e("$qqd/dev/ptmx")) {  # TODO(pts): Disallow symlinks.
  symlink("pts/ptmx", "$qqd/dev/ptmx");  # It is OK to fail here.
}
for my $node (qw(null zero full random urandom kmsg tty console)) {
  #if (!-c("$qqd/dev/$node")) {...}  # TODO(pts): Disallow symlinks.
  if (-f("$qqd/dev/$node")) {  # Already exists as a regular file. TODO(pts): Disallow symlinks.
    if (-c("/dev/$node")) {
      #if (!-e("$qqd/dev/$node")) {
      #  my $qqp = (substr($qqd, 0, 1) eq "/") ? "" : "./";
      #  close(FH) if open(FH, ">> $qqp$qqd/dev/$node");
      #}
      my @spec = ("/dev/$node", "$qqd/dev/$node", 0, MS_REC | MS_BIND, 0);
      # This bind mount works with use-rootless.
      die "$qqin: fatal: mount $qqd/dev/$node: $!\n" if syscall($SYS_mount, @spec);
    }
    die "$qqin: fatal: not a character device: $qqd/dev/$node\n" if !-c("$qqd/dev/$node");
  }
}
# Non-Linux systems will run mount(8) later.
if (defined($SYS_mount) and !is_same_dir($qqd, "/")) {
  my @spec = ("/proc", "$qqd/proc", 0, MS_REC | MS_BIND, 0);
  die "$qqin: fatal: mount $qqd/proc: $!\n" if syscall($SYS_mount, @spec);
  @spec = ("/dev/pts", "$qqd/dev/pts", 0, MS_REC | MS_BIND, 0);
  die "$qqin: fatal: mount $qqd/dev/pts: $!\n" if syscall($SYS_mount, @spec);
}
if (defined($qqoldpwd)) {  # `qq use-workdir $qqd` was run in directory $qqpwd.
  die "$qqin: fatal: missing work directory: $qqpwd\n" if !-d($qqpwd);
  die "$qqin: fatal: missing work source directory: $qqoldpwd\n" if !-d($qqoldpwd);
  my @spec = ($qqoldpwd, $qqpwd, 0, MS_REC | MS_BIND, 0);
  die "$qqin: fatal: mount $qqpwd: $!\n" if syscall($SYS_mount, @spec);
}

my $username;
if (@ARGV and $ARGV[0] eq "root") {
  shift @ARGV;
  $username = "root";
  $ENV{SUDO_UID} = $ENV{SUDO_GID} = "0";
} else {
  die "$qqin: fatal: incomplete sudo environment: SUDO_UID, SUDO_GID, SUDO_USER\n" if
      !$ENV{SUDO_UID} or !$ENV{SUDO_GID} or !$ENV{SUDO_USER};
  die "$qqin: fatal: inconsistent SUDO_USER and SUDO_UID for root\n" if
      ($ENV{SUDO_USER} eq "root") != ($ENV{SUDO_UID} == 0);
  $username = $ENV{SUDO_USER};
}
die "$qqin: fatal: invalid username: $username\n" if
    $username !~ m@\A[-+.\w]+\Z(?!\n)@;
$ENV{LOGNAME} = $ENV{USER} = $ENV{USERNAME} = $username;
delete @ENV{qw(SUDO_COMMAND SUDO_USER)};

if (defined($SYS_pivot_root) and $username eq "root") {
  # On Linux we use pivot_root(2) (and some other mount(2) and fchdir(2)
  # magic, see below) instead of chroot(2) to prevent the chdir("..") escape
  # technique (http://www.ouah.org/chroot-break.html), which would work as
  # root with chroot(2).
  #
  # This implementation with pivot_root(2) is based on
  # https://github.com/opencontainers/runc/blob/4769cdf607b0d1cbd73e5407d9655da7511fe193/libcontainer/rootfs_linux.go#L693
  # with the re-bind-bound below prepended. It also contains msMoveRoot
  # (MS_MOVE), but that works only if $qqd is a mount mount, and the
  # re-bind-mount rick below doesn not fix it.
  #
  # There is another implementation at
  # https://github.com/vincentbernat/jchroot/blob/3ad09cca4879c27f7eef657b7fa1dd8b4f6aa47b/jchroot.c#L122
  # , but that one creates a temporary directory within $qqd.
  #
  # https://github.com/opencontainers/runc/blob/master/libcontainer/SPEC.md
  # claims that pivot_root(2) is not supported in ramfs. It does work within
  # tmpfs though on Linux 3.13.
  local(*OLDROOT, *NEWROOT);
  # Without this bind-mount call, pivot_root would fail if $qqd was not a
  # mount point.
  # Without the MS_REC below, filesystems mounted within $qqd would not be
  # visible.
  my @spec = ($qqd, $qqd, 0, MS_REC | MS_BIND, 0);
  die "$qqin: fatal: re-bind-mount $qqd: $!\n" if syscall($SYS_mount, @spec);
  die "$qqin: fatal: chdir $qqd: $!\n" if !chdir($qqd);
  die "$qqin: fatal: open oldroot: $!\n" if
      !sysopen(OLDROOT, "/", O_RDONLY | O_DIRECTORY, 0);
  die "$qqin: fatal: open newroot: $!\n" if
      !sysopen(NEWROOT, $qqd, O_RDONLY | O_DIRECTORY, 0);
  # Not using chdir(NEWROOT), because it old versions of Perl (e.g.
  # 5.004_04) do not have it.
  die "$qqin: fatal: fchdir newroot: $!\n" if
      0 != syscall($SYS_fchdir, fileno(NEWROOT));
  die "$qqin: fatal: pivot_root . .: $!\n" if
      0 != syscall($SYS_pivot_root, @spec);
  die "$qqin: fatal: fchdir oldroot: $!\n" if
      0 != syscall($SYS_fchdir, fileno(OLDROOT));
  @spec = ("", ".", "", MS_REC | MS_SLAVE, 0);
  die "$qqin: fatal: mount . MS_REC: $!\n" if syscall($SYS_mount, @spec);
  @spec = (".", MNT_DETACH);
  die "$qqin: fatal: umount . MNT_DETACH: $!\n" if syscall($SYS_umount2, @spec);
  close(NEWROOT); close(OLDROOT);
} else {
  # For a non-root user chroot is secure enough. For root on non-Linux
  # systems the chdir("..") chroot escape technique
  # (http://www.ouah.org/chroot-break.html) can be used to break out, and we
  # don not have any protection against that here.
  #
  # On Linux 3.13 /proc/mounts remains very long in here (containing the
  # mounts of the host system). We cannot fix it. Linux 4.18 removes most of
  # those entries from mount.
  die "$qqin: fatal: chroot $qqd: $!\n" if !chroot($qqd);
}
die "$qqin: fatal: cd /: $!\n" if !chdir("/");  # Within $qqd.
#die if !opendir(D, "/"); die "qqd contents: (@{[readdir(D)]}).\n";
# TODO(pts): Close all file descriptors (/proc/self/fd) except for 0, 1 and 2?
# TODO(pts): Redirect /dev/null on file descriptors 0, 1 and 2 from outside to inside?
# TODO(pts): Populate /dev as https://github.com/opencontainers/runc/blob/master/libcontainer/SPEC.md does it.
# TODO(pts): Add unshare(CLONE_NEWPID) as optional.

# Removes setuid, setgid and sticky bits.
sub chmod_remove_high_bits($) {
  my $path = $_[0];
  my @stat = stat($path);
  die "$qqin: fatal: stat $path: $!\n" if !@stat;
  die "$qqin: fatal: chmod $path: $!\n" if !chmod($stat[2] & 0777, $path);
}

# Now create $qqd as a symlink to "/", to make filenames work.
my $link = defined($qqoldpwd) ? "/"  # Do not create rootdir symlink if use-workdir was specified.
    : readlink($qqd);
if (!defined($link) or $link ne "/") {
  die "$qqin: fatal: symlink is a directory (maybe chroot failed?): $qqd\n" if
      lstat($qqd) and -d(_);
  my $qqdu = $qqd;
  $qqdu =~ s@/[^/]\Z(?!\n)@@;
  $link = symlink("/", $qqd);
  if (!$link and $qqdu =~ s@/[^/]+\Z(?!\n)@@ and $qqdu and !-d($qqdu)) {
    my @qqdl = ($qqdu);
    while ($qqdu =~ s@/[^/]+\Z(?!\n)@@ and $qqdu and !-d($qqdu)) {
      push @qqdl, $qqdu;
    }
    my $home = $username ne "root" ? "/home/$username" : "-";
    while (@qqdl) {
      $qqdu = pop(@qqdl);
      # Owned by root. Good.
      die "$qqin: fatal: mkdir $qqdu: $!\n" if !mkdir($qqdu, 0755);
      if (substr($qqdu, 0, length($home)) eq $home and
          (length($qqdu) == length($home) or
           substr($qqdu, length($home), 1) eq "/")) {
        die "$qqin: assert: no SUDO_UID\n" if !defined($ENV{SUDO_UID});
        die "$qqin: fatal: chown $home: $!\n" if
            !chown($ENV{SUDO_UID}, $ENV{SUDO_GID}, $qqdu);
      }
      chmod_remove_high_bits($qqdu) if $qqdu eq $home;
    }
    $link = symlink("/", $qqd);
  }
  die "$qqin: fatal: cannot create symlink: $qqd: $!\n" if !$link;
}
if (defined($qqoldpwd)) {  # With use-workdir.
  # Convert chdir to relative, because we have not created to rootdir
  # symlink.
  $qqpwd = substr($qqpwd, length($qqd));
  $qqpwd = "." if !length($qqpwd);
}
if ($qqpwd ne "." and !chdir($qqpwd)) {
  # Some hardened Linux systems return Permission denied if root is trying
  # to follow a symlink which he does not own. Since lchown(2) is not
  # available in Perl, we recreate the symlink and retry.
  if (!$> and [lstat($qqd)]->[4] != 0) {
    unlink $qqd;
    die "$qqin: fatal: cannot recreate symlink: $qqd: $!\n" if
        !symlink("/", $qqd);
  }
  die "$qqin: fatal: chdir $qqpwd: $!\n" if !chdir($qqpwd);
}

sub is_mounted($) {
  return 1 if !-d($_[0]);
  my @stata = lstat("/");
  die "$qqin: fatal: stat /: $!\n" if !@stata;
  my @statb = lstat($_[0]);
  return (@statb and $stata[0] != $statb[0]) ? 1 : 0;  # Different st_dev.
}

if (!is_mounted("/proc")) {
  die "$qqin: fatal: mount /proc failed\n" if
      system("/bin/mount", "proc", "/proc", "-t", "proc");
}

if (!is_mounted("/dev/pts")) {
  die "$qqin: fatal: mount /dev/pts failed\n" if
      system("/bin/mount", "devpts", "/dev/pts", "-t", "devpts");
}

# Recent versions of bash (e.g. 4.x, but not 2.05b) executes etc/bash.bashrc
# and ~/.bashrc if they detect that they were invoked by rshd or sshd. We
# set $ENV{SHLVL} here to prevent this (so that bashrc would not mess up our
# carefully crafted $ENV{PS1}, $ENV{PATH} and $ENV{LC_CTYPE}). Alternatively,
# to prevent this, we could delete $ENV{SSH_CLIENT}.
#
# Our shell will not be a login shell, so it will not read /etc/profile,
# ~/.bash_profile, ~/.bash_login, ~/.profile or ~/.bash_logout.
#
# Our shell can be an interactive shell, and then it would read
# /etc/bash.bashrc and ~/.bashrc. To prevent this, we invoke it with --norc
# by default (see below). If the user wants bashrc read, he should run
# qq bash.
#
# If the user runs an interactive bash later within the chroot environment
# (e.g. qq; and then bash), then that bash will read /etc/bash.bashrc (exits
# early if $PS1 is set) and ~/.bashrc. The latter is missing by default (if
# qq has created $HOME for the user), but can be present (copied from
# /etc/skel/.bashrc) if $HOME was created by adduser within the chroot. In
# this case it may override $PS1 (and make it include $ENV{debian_chroot},
# so we set that below). There is no easy way for us to disable this
# subsequent execution of ~/.bashrc, so we do nothing.
#
# Some shells including bash may also read the file named by $ENV{ENV} or
# $ENV{BASH_ENV} at startup, so we delete those environment variables below.
$ENV{SHLVL} = "1" if !defined($ENV{SHLVL});
delete @ENV{qw(ENV BASH_ENV SHELLOPTS BASHOPTS CDPATH GLOBIGNORE)};
my $qqdlast = $qqd;
$qqdlast =~ s@\A.*/@@s;
$ENV{debian_chroot} = "qq=$qqdlast";

$ENV{PS1} = q~\u@\h:\w\$ ~ if !defined($ENV{PS1}) or
    $ENV{PS1} =~ m@%@;  # zsh prompt.
$ENV{SHELL} = -f("/bin/bash") ? "/bin/bash" : "/bin/sh";
my $shell_link =
    (@ARGV and ($ARGV[0] eq "dash" or $ARGV[0] eq "/bin/dash")) ? "dash" :
    readlink((@ARGV and $ARGV[0] eq "sh") ? "/bin/sh" : $ENV{SHELL});
if (defined($shell_link) and
    ($shell_link eq "dash" or $shell_link eq "/bin/dash")) {
  # dash does not expand $ENV{PS1};
  $ENV{PS1} = "[qq=$qqdlast] \$ ";
} else {
  # OK for bash, bash-as-sh, busybox sh.
  $ENV{PS1} = "[qq=$qqdlast] $ENV{PS1}";
}

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
    _ SSH_CLIENT HOME RANDOM UID EUID GID EGID)};
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

# If $SUDO_UID is 1000, and /etc/passwd already contains
# "ubuntu:x:1000:1000:Ubuntu,,,:/home/ubuntu:/bin/bash", remove it.
# Also remove "ubuntu:x:1000:" from /etc/group.
sub comment_out_wrong_username($$$) {
  my($filename, $good_username, $id) = @_;
  local *FH;
  return if !open(FH, "< $filename");
  my $fl;
  my $is_found = 0;
  while (defined($fl = <FH>)) {
    my @fx = split(/:/, $fl);
    if (@fx > 2 and $fx[2] eq $id and $fx[0] ne $username) {
      $is_found = 1; last
    }
  }
  close(FH);
  return if !$is_found;
  die "$qqin: fatal: open read-write $filename: $!\n" if
      !open(FH, "+< $filename");
  my $data = "";
  while (defined($fl = <FH>)) {
    my @fx = split(/:/, $fl);
    # Add a comment marker to the beginning of the line.
    $data .= "#" if @fx > 2 and $fx[2] eq $id and $fx[0] ne $username;
    $data .= $fl;
  }
  die "$qqin: fatal: fseek in $filename: $!\n" if !seek(FH, 0, 0);
  die "$qqin: fatal: rewrite $filename: $!\n" if !print(FH $data);
  die "$qqin: fatal: rewrite-flush $filename: $!\n" if !close(FH);
  die "$qqin: fatal: truncate $filename: $!\n" if
      !truncate($filename, length($data));
}

if (!-f("/etc/passwd")) {
  mkdir("/etc", 0755);
  local *FH;
  die "$qqin: fatal: error creating /etc/passwd: $!\n" if
      !open(FH, ">> /etc/passwd");
  close(FH);
}
if (!-f("/etc/shadow")) {
  local *FH;
  die "$qqin: fatal: error creating /etc/shadow: $!\n" if
      !open(FH, ">> /etc/shadow");
  close(FH);
  die "$qqin: fatal: error chmodding /etc/shadow: $!\n" if
      !chmod(0600, "/etc/shadow");
}
if (!-f("/etc/group")) {
  local *FH;
  die "$qqin: fatal: error creating /etc/group: $!\n" if
      !open(FH, ">> /etc/group");
  close(FH);
}
if (!ensure_auth_line("/etc/passwd", "$username:", 1)) {
  comment_out_wrong_username("/etc/passwd", $username, $ENV{SUDO_UID});
  comment_out_wrong_username("/etc/group", $username, $ENV{SUDO_GID});
  ensure_auth_line("/etc/shadow", "$username:*:17633:0:99999:7:::\n");
  ensure_auth_line("/etc/group",  "$username:x:$ENV{SUDO_GID}:\n");
  # Do it last, in case of errors with the above.
  ensure_auth_line("/etc/passwd", "$username:x:$ENV{SUDO_UID}:$ENV{SUDO_GID}:qquser $username:/home/$username:$ENV{SHELL}");
}
if ($username eq "root") {
  $ENV{HOME} = "/root";
} else {
  # TODO(pts): Do we want to add the original $ENV{HOME} as a symlink?
  my $home = "/home/$username";
  # chown below may be insecure for symlinks.
  die "$qqin: fatal: home is a symlink: $!\n" if -l($home);
  if (!-d($home)) {
    mkdir "/home", 0755;
    mkdir $home, 0755;
    die "$qqin: fatal: could not create HOME: $home\n" if !-d($home);
    die "$qqin: fatal: chown $home: $!\n" if
        !chown($ENV{SUDO_UID}, $ENV{SUDO_GID}, $home);
    chmod_remove_high_bits($home);
  } elsif (!is_owned_and_rwx($home, $ENV{SUDO_UID} + 0)) {
    chown($ENV{SUDO_UID}, $ENV{SUDO_GID}, $home) and
        chmod(0755, $home);
    die "$qqin: fatal: HOME not owned by $username and rwx: $home\n" if
        !is_owned_and_rwx($home, $ENV{SUDO_UID} + 0);
  }
  $ENV{HOME} = $home;
  ($(, $)) = ($ENV{SUDO_GID}, "$ENV{SUDO_GID} $ENV{SUDO_GID}");
  die "$qqin: fatal: setgid failed\n" if
      $( != $ENV{SUDO_GID} or $) != $ENV{SUDO_GID};
  # Some old versions on Perl (such as the one on Debian Potato) do not
  # support UID > 65535, and they set $< and $> to 0 instead.
  ($<, $>) = ($ENV{SUDO_UID}, $ENV{SUDO_UID});
  die "$qqin: fatal: setuid failed\n" if
      $( != $ENV{SUDO_GID} or $) != $ENV{SUDO_GID};
}
delete @ENV{"SUDO_GID", "SUDO_UID"};

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
    # Do not match $home (outside chroot) itself.
    if ($dir eq $qqd or substr($dir, 0, length($qqds) eq $qqds)) {
    } elsif ($username ne "root" and substr($dir, 0, length($homes)) eq $homes) {
      $dir = "$ENV{HOME}/" . substr($dir, length($homes));
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

if (@ARGV and $ARGV[0] eq "cd") {
  # Print the name of the user-writable home directory, and exit.
  print "$qqd$ENV{HOME}\n";
  exit;
}

# TODO(pts): Run qqinbashrc now?
#            If it exists, then run @ARGV with bash (properly quote it first).

# exec(...) also prints a detailed error message.
die "$qqin: fatal: exec $ARGV[0]: $!\n" if !exec(@ARGV);
' __QQD__="$__QQD__" __QQPWD__="$__QQPWD__" __QQOLDPWD__="$__QQOLDPWD__" __QQPATH__="$PATH" __QQHOME__="$HOME" __QQLCALL__="$LC_ALL" PWD="$PWD" LC_ALL=C exec "${__QQPERL__:-perl}" -we'eval$ENV{__QQPRESUDO__};die$@if$@' -- "$@"
  # TODO(pts): Add more CPU architectures.
  # TODO(pts): Try nesting use-unshare/use-unshare. Does the MS_PRIVATE mount work on /, and is it effective?
  # TODO(pts): Try nesting of qq with use-unshare/use-sudo and use-unshare/use-unshare. Give recommendations.
  # TODO(pts): Download and use staticperl if Perl not installed to the host.
  # TODO(pts): Try __QQIN__ and  with Perl 5.004 for maximum compatibility.
  # Above setting LC_ALL=C instead of PERL_BADLANG=x, to prevent locale warnings.
}

__qq__ "$@"
