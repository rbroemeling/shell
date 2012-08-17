if [ "$SHLVL" -eq "1" ]; then
  if [ -x /usr/bin/clear_console ]; then
    # Ubuntu
    /usr/bin/clear_console -q
  elif [ -x /usr/bin/clear ]; then
    # CentOS
    /usr/bin/clear
  fi
fi

if [ -s "${HOME}/.zlogout.local" ]; then
  source "${HOME}/.zlogout.local"
fi
