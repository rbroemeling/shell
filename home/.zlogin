if type -p keychain >/dev/null; then
  keychain --quiet ~/.ssh/id_?sa
  . "${HOME}/.keychain/${HOST}-sh"
else
  print -P "[ %F{yellow}WARNING%f ] 'keychain' not available, skipping ssh-agent initialization" >&2
fi

if [ -s "${HOME}/.zlogin.local" ]; then
  source "${HOME}/.zlogin.local"
fi
