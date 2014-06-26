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
# To setup an unprivileged user at the same time:
#  wget -q -O - https://raw.github.com/rbroemeling/shell/master/bootstrap/baseline.sh | sudo env UNPRIVILEGED_USER=<username> bash
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

#
# Configure APT.
#
echo 'APT::Install-Recommends "false";' > /etc/apt/apt.conf.d/99recommends
echo 'APT::Install-Suggests "false";' > /etc/apt/apt.conf.d/99suggests
cat >/etc/apt/sources.list <<EOF
# debian
deb http://ftp.ca.debian.org/debian/ wheezy main contrib non-free
deb-src http://ftp.ca.debian.org/debian/ wheezy main contrib non-free

# debian-backports
deb http://ftp.ca.debian.org/debian/ wheezy-backports main contrib non-free
deb-src http://ftp.ca.debian.org/debian/ wheezy-backports main contrib non-free

# debian-updates
deb http://ftp.ca.debian.org/debian/ wheezy-updates main contrib non-free
deb-src http://ftp.ca.debian.org/debian/ wheezy-updates main contrib non-free

# debian-security
deb http://security.debian.org/ wheezy/updates main contrib non-free
deb-src http://security.debian.org/ wheezy/updates main contrib non-free
EOF
aptitude update
aptitude safe-upgrade -y

#
# Install Postfix.
#
hostname --fqdn >/etc/mailname
mkdir -p /etc/postfix
cat > /etc/postfix/main.cf <<__EOF__
# See /usr/share/postfix/main.cf.dist for a commented, more complete version

append_dot_mydomain = no
biff = no
inet_interfaces = loopback-only
mailbox_command = procmail -a "\$EXTENSION"
mailbox_size_limit = 0
mydestination = \$myhostname, localhost.\$mydomain, localhost
mydomain = $(hostname --domain)
mynetworks_style = host
myorigin = /etc/mailname
readme_directory = no
#relayhost = A.B.C.D:smtp
recipient_delimiter = +
smtpd_banner = \$myhostname ESMTP \$mail_name (Debian/GNU)
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
  keychain \
  lrzsz \
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
  automake \
  bison \
  build-essential \
  debhelper \
  devscripts \
  dpatch \
  flex \
  gdb

#
# Install a collection of text editors that should satisfy almost everyone.
#
aptitude install -y nano
if [ "${X11}" == "TRUE" ]; then
  aptitude install -y emacs23 vim-gtk
else
  aptitude install -y emacs23-nox vim
fi

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
install --directory --group=staff --mode=2775 --owner=root /usr/local/man

#
# Install and enable/configure tmpreaper.
#
sed -ie 's/^#TMPTIME=.*$/TMPTIME=7/' /etc/default/rcS
aptitude install -y tmpreaper
sed -ie 's/^SHOWWARNING/#SHOWWARNING/' /etc/tmpreaper.conf

#
# Install VMWare tools, if we are on a VMWare instance.
#
if [ "${VMWARE}" == "TRUE" ]; then
  aptitude -y install open-vm-dkms
  if [ "${X11}" == "TRUE" ]; then
    aptitude -y install open-vm-toolbox
  fi
fi

#
# Disable unnecessary/unused TTYs.
#
sed -ie 's/^\(.* tty[3456]\)$/#\1/g' /etc/inittab
/sbin/telinit q

#
# Remove pacakges that generally we do not want nor need.
#
aptitude remove -y \
  nfs-common \
  rpcbind

#
# Purge any 'removed' packages.
#
aptitude purge -y '~c'

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
