#!/bin/bash -e
#
# Install a default set of useful packages and configure them reasonably.
# Note that these selections assume an already-existing basic (minimal,
# assuming only installation of standard system utilities) Debian install.
#
# To call directly from the git repository:
#   su
#   wget -q -O - https://raw.github.com/rbroemeling/shell/master/bootstrap/baseline.sh | bash
# Or:
#   wget -q -O - https://raw.github.com/rbroemeling/shell/master/bootstrap/baseline.sh | sudo bash
#

#
# Set flags about what type of system we are building on.
#
VMWARE="FALSE"
if dmesg | grep 'VMware Virtual' >/dev/null 2>&1; then
  VMWARE="TRUE"
fi

X11="FALSE"
if dpkg -l xinit >/dev/null 2>&1; then
  X11="TRUE"
fi

echo -n "Enter the unprivileged username to configure (blank for none): "
read UNPRIVILEGED_USER

#
# Install Postfix.
#
mkdir -p /etc/postfix
cat > /etc/postfix/main.cf <<'__EOF__'
# See /usr/share/postfix/main.cf.dist for a commented, more complete version

append_dot_mydomain = no
biff = no
inet_interfaces = loopback-only
mydestination = development, $myhostname, localhost.$mydomain, localhost
mynetworks_style = host
myorigin = /etc/mailname
readme_directory = no
#relayhost = A.B.C.D:smtp
recipient_delimiter = +
smtpd_banner = $myhostname ESMTP $mail_name (Debian/GNU)
__EOF__
aptitude install -y postfix

#
# Install utilities and applications.
#
aptitude install -y \
  curl libcurl4-openssl-dev \
  debconf-utils \
  dstat \
  fping \
  ifstat \
  iftop \
  iputils-ping \
  iputils-tracepath \
  mtr-tiny \
  nmap \
  openssh-server \
  pv \
  realpath \
  rsync \
  screen \
  strace \
  sudo \
  tcpdump \
  unzip \
  zip

#
# Install development tools and utilities.
#
aptitude install -y \
  git \
  subversion \
  autoconf \
  automake1.9 \
  bison \
  build-essential \
  debhelper \
  devscripts \
  dpatch \
  flex \
  gdb

#
# If we are on a 64-bit architecture, then install the 32-bit compatibility libraries.
#
if [ "$(uname -m)" = "x86_64" ]; then
  aptitude install -y ia32-libs ia32-libs-dev libc6-i386 libc6-dev-i386
fi

#
# Install a collection of text editors that should satisfy almost everyone.
#
if [ "${X11}" == "TRUE" ]; then
  aptitude install -y emacs23 vim-gtk
else
  aptitude install -y emacs23-nox vim
fi
aptitude install -y joe nano

#
# Install Stow
#
# We need to remove the /usr/local/man symlink and create a directory in it's place
# in order to prevent conflicts when stowing applications.
#
aptitude install -y stow
if [ -h /usr/local/man ]; then
  rm /usr/local/man
fi
mkdir -p /usr/local/man

#
# Install and enable/configure tmpreaper.
#
sed -ie 's/^TMPTIME=.*$/TMPTIME=7/' /etc/default/rcS
aptitude install -y tmpreaper
sed -ie 's/^SHOWWARNING/#SHOWWARNING/' /etc/tmpreaper.conf

#
# Install VMWare tools, if we are on a VMWare instance.
#
# Note that this requires the 'contrib' package repository.
#
if [ "${VMWARE}" == "TRUE" ]; then
  aptitude -y install open-vm-source
  module-assistant -i prepare open-vm
  module-assistant -i auto-install open-vm
  if [ "${X11}" == "TRUE" ]; then
    aptitude -u install open-vm-toolbox
  fi
fi

#
# Purge any 'removed' packages.
#
dpkg -l | awk '$1 == "rc" { print $2 }' | xargs -r aptitude -y purge

#
# Install some utility scripts, and our user environment if necessary.
#
cd /tmp
git clone git://github.com/rbroemeling/shell.git
install shell/bin/aliases_update.sh /etc/cron.daily/aliases
if [ -n "${UNPRIVILEGED_USER}" ]; then
  usermod -a -G adm "${UNPRIVILEGED_USER}"
  usermod -a -G staff "${UNPRIVILEGED_USER}"
  usermod -a -G sudo "${UNPRIVILEGED_USER}"
  usermod -a -G users "${UNPRIVILEGED_USER}"
  sed -ie 's/# $1 == "root".*/$1 == "root" { destination = "'"$UNPRIVILEGED_USER"'" }/' /etc/cron.daily/aliases
  cd shell/home
  sudo -u "${UNPRIVILEGED_USER}" ./install.sh "/home/${UNPRIVILEGED_USER}"
  cd ../..
  echo "Update /etc/cron.daily/aliases with the real e-mail address mapping for '${UNPRIVILEGED_USER}'." >&2
else
  echo "Update /etc/cron.daily/aliases with the real e-mail address mapping for 'root'." >&2
fi
rm -r /tmp/shell
