# ~/.bash_logout: executed by bash(1) when login shell exits.

# invalidate any existing sudo credentials
if [ -x /usr/bin/sudo ]; then
  /usr/bin/sudo -k
fi

# when leaving the console clear the screen to increase privacy
if [ "$SHLVL" = 1 ]; then
  if [ -x /usr/bin/clear_console ]; then
    # Debian/Ubuntu
    /usr/bin/clear_console -q
  elif [ -x /usr/bin/clear ]; then
    # CentOS
    /usr/bin/clear
  fi
fi
