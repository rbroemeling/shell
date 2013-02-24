# ~/.profile: executed by the command interpreter for login shells.
# This file is not read by bash(1), if ~/.bash_profile or ~/.bash_login
# exists.
# see /usr/share/doc/bash/examples/startup-files for examples.
# the files are located in the bash-doc package.

# the default umask is set in /etc/profile; for setting the umask
# for ssh logins, install and configure the libpam-umask package.
#umask 022

# if running bash
if [ -n "$BASH_VERSION" ]; then
	# include .bashrc if it exists
	if [ -f "$HOME/.bashrc" ]; then
		. "$HOME/.bashrc"
	fi
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/bin" ]; then
	PATH="$HOME/bin:$PATH"
fi
if [ -d "$HOME/.bin" ]; then
	PATH="$HOME/.bin:$PATH"
fi

# configure our go language installation, if we have one
if [ -d "$HOME/.go" -a -d "$HOME/.go/current/bin" ];
  PATH="$PATH:$HOME/.go/current/bin"
  GOHOME="$HOME/.go/current"
fi

# if running interactively...
if [ "$PS1" ]; then
	# ... disable annoying ^S/^Q commands.
	stty -ixon -ixoff

	# ... and in a first-level shell ...
	if [ "$SHLVL" = 1 ]; then
		# ... show a quick snapshot of the system
		echo
		w
		echo
	fi
fi
