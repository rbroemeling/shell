#!/bin/bash
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
set -euo pipefail
. /etc/os-release
CODENAME="${VERSION//[^a-z]/}"
export DEBIAN_FRONTEND=noninteractive

# Set flags about what type of system we are building on.
VMWARE="FALSE"
if dmesg | grep 'VMware Virtual' >/dev/null 2>&1; then
  VMWARE="TRUE"
fi

X11="FALSE"
if dpkg -l xinit >/dev/null 2>&1; then
  X11="TRUE"
fi

# Configure APT.
echo 'APT::Install-Recommends "false";' > /etc/apt/apt.conf.d/99recommends
echo 'APT::Install-Suggests "false";' > /etc/apt/apt.conf.d/99suggests
# cloud-init automatically configures APT sources (that we want to leave alone). If cloud-init is not present, configure
# our APT sources in a reasonable way.
if ! dpkg -l cloud-init >/dev/null 2>&1; then
  echo '# APT sources are kept in /etc/apt/sources.list.d/*.list' >/etc/apt/sources.list
  cat >/etc/apt/sources.list.d/debian.list <<EOF
# debian
deb http://httpredir.debian.org/debian ${CODENAME} main contrib non-free
deb-src http://httpredir.debian.org/debian ${CODENAME} main contrib non-free
EOF
  cat >/etc/apt/sources.list.d/debian-security.list <<EOF
# debian-security
deb http://security.debian.org/ ${CODENAME}/updates main contrib non-free
deb-src http://security.debian.org/ ${CODENAME}/updates main contrib non-free
EOF
  cat >/etc/apt/sources.list.d/debian-updates.list <<EOF
# debian-updates
deb http://httpredir.debian.org/debian ${CODENAME}-updates main contrib non-free
deb-src http://httpredir.debian.org/debian ${CODENAME}-updates main contrib non-free
EOF
  cat >/etc/apt/sources.list.d/debian-backports.list <<EOF
# debian-backports
deb http://httpredir.debian.org/debian ${CODENAME}-backports main contrib non-free
deb-src http://httpredir.debian.org/debian ${CODENAME}-backports main contrib non-free
EOF
fi
rm -f /etc/apt/sources.list~
apt-get update
apt-get upgrade -y

# Configure GRUB
sed -e '
  s/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/;
  s/#\?GRUB_GFXMODE=.*/GRUB_GFXMODE=1280x720x32/;
  /GRUB_GFXMODE=.*/ a GRUB_GFXPAYLOAD_LINUX=1280x720
' -i /etc/default/grub
update-grub

# Install/configure Postfix.
mkdir -p /etc/postfix
cat >/etc/postfix/main.cf <<__EOF__
# See /usr/share/postfix/main.cf.dist for a commented, more complete version
append_dot_mydomain = no
biff = no
inet_interfaces = loopback-only
mailbox_size_limit = 0
mynetworks_style = host
readme_directory = no
recipient_delimiter = +
#relayhost = A.B.C.D:smtp
smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache
smtpd_banner = \${myhostname} ESMTP \${mail_name} (Debian/GNU)
smtpd_tls_cert_file = /etc/ssl/certs/ssl-cert-snakeoil.pem
smtpd_tls_key_file = /etc/ssl/private/ssl-cert-snakeoil.key
smtpd_tls_session_cache_database = btree:\${data_directory}/smtpd_scache
smtpd_use_tls=yes
__EOF__
apt-get install -y postfix

# Install utilities and applications.
apt-get install -y \
  curl libcurl4-openssl-dev \
  debconf-utils \
  dstat \
  fping \
  ifstat \
  iftop \
  iptables-persistent \
  iputils-ping \
  iputils-tracepath \
  keychain \
  lrzsz \
  mtr-tiny \
  nano \
  nmap \
  ntp \
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
if [ "${X11}" == "TRUE" ]; then
  apt-get install -y emacs23 vim-gtk
else
  apt-get install -y emacs23-nox vim
fi

# Install development tools and utilities.
apt-get install -y \
  ack-grep \
  autoconf \
  automake \
  bison \
  build-essential \
  debhelper \
  devscripts \
  dpatch \
  flex \
  gdb \
  git \
  linux-headers-amd64 \
  subversion

# Install Stow
#
# We need to remove the /usr/local/man symlink and create a directory in it's place
# in order to prevent conflicts when stowing applications.
apt-get install -y stow
if [ -h /usr/local/man ]; then
  rm /usr/local/man
fi
install --directory --group=staff --mode=2775 --owner=root /usr/local/man

# Install and enable/configure tmpreaper.
sed -ie 's/^#TMPTIME=.*$/TMPTIME=7/' /etc/default/rcS
apt-get install -y tmpreaper
sed -ie 's/^SHOWWARNING/#SHOWWARNING/' /etc/tmpreaper.conf

# Install VMWare tools, if we are on a VMWare instance.
if [ "${VMWARE}" == "TRUE" ]; then
  apt-get install -y open-vm-dkms
  if [ "${X11}" == "TRUE" ]; then
    apt-get install -y open-vm-toolbox
  fi
fi

# Remove packages that generally we do not want nor need.
apt-get purge -y \
  nfs-common \
  rpcbind

# Install some utility scripts, and our user environment if necessary.
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
