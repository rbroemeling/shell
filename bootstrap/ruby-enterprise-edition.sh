#!/bin/bash -e
#
# Install a Ruby Enterprise Edition into a nice, clean, compartmentalized, stowable directory.
#
# To call directly from the git repository:
#   wget -q -O - https://raw.github.com/rbroemeling/shell/master/bootstrap/ruby-enterprise-edition.sh | sudo bash
#

if ! grep '^rubybin:' /etc/group >/dev/null 2>&1; then
  groupadd -r rubybin
else
  echo 'Group rubybin already exists.'
fi
if ! grep '^rubybin:' /etc/passwd >/dev/null 2>&1; then
  useradd -M -r --comment 'ruby environment' --gid rubybin --home /dev/null --shell /usr/sbin/nologin rubybin
else
  echo 'User rubybin already exists.'
fi

if [ -e '/usr/local/lib/shell-utilities.inc.sh' ]; then
  source /usr/local/lib/shell-utilities.inc.sh
else
  wget -q -O "/tmp/shell-utilities.inc.sh.${$}" https://raw.github.com/rbroemeling/shell/master/lib/shell-utilities.inc.sh
  source "/tmp/shell-utilities.inc.sh.${$}"
  rm "/tmp/shell-utilities.inc.sh.${$}"
fi

shutil_remote_source_install "http://rubyenterpriseedition.googlecode.com/files/ruby-enterprise-1.8.7-2012.02.tar.gz" <<'__EOSHUTIL__'
#
# Change the owner of our ruby binaries to 'rubybin', so that it is easy to
# allow gems access to install into that directory without giving them full
# root access.
#
chown -R rubybin "${STOW_DIR}"

chown -R rubybin .
sudo -u rubybin "runtime/$(uname)-$(uname -m)/ruby" installer.rb --dont-install-useful-gems --auto "${STOW_DIR}"
__EOSHUTIL__

RUBY_ROOT="$(gem env gemdir)"
RUBY_ROOT="${RUBY_ROOT%/*/*/*/*}"
cp -a "${RUBY_ROOT}/bin/gem" "${RUBY_ROOT}/bin/gem.real"
cp -a "${RUBY_ROOT}/bin/gem" "${RUBY_ROOT}/bin/gem.wrapper"
cat >"${RUBY_ROOT}/bin/gem.wrapper" <<__EOWRAPPER__
#!/bin/bash -e

#
# Over-ride our 'gem' command to operate as the 'rubybin' user, so that we
# protect against insane gem installs screwing with anything that they aren't
# supposed to.  Running the 'gem' command as the 'rubybin' user allows it to
# change anything that is under our ruby environment root; but disallows it
# from changing anything else.
#

cd /tmp
sudo -u rubybin "\${0%/*}/gem.real" "\${@}"
if [ ! -L "${RUBY_ROOT}/bin/gem" ]; then
  sudo mv -f "${RUBY_ROOT}/bin/gem" "${RUBY_ROOT}/bin/gem.real"
  sudo ln -sfn gem.wrapper "${RUBY_ROOT}/bin/gem"
  sudo chown -h rubybin "${RUBY_ROOT}/bin/gem"
fi
cd "${RUBY_ROOT%/*}"
sudo stow "${RUBY_ROOT##*/}"
__EOWRAPPER__
ln -sfn gem.wrapper "${RUBY_ROOT}/bin/gem"
chown -h rubybin "${RUBY_ROOT}/bin/gem"

cd "${RUBY_ROOT%/*}"
stow "${RUBY_ROOT##*/}"
