# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# Source any global definitions that are present.
if [ -s "/etc/bashrc" ]; then
  source "/etc/bashrc"
fi

if [ -n "${PS1}" ]; then
  # We are running interactively, so build the necessary environment
  # for a user to work in.

  # don't put duplicate lines in the history.
  # don't put lines that begin with a space in the history.
  # See bash(1) for more options
  export HISTCONTROL=ignorespace:erasedups

  # don't put backgrounded, `ls`, `bg`, `fg`, `exit`, or `cd` commands in the history
  export HISTIGNORE="&:ls:[bf]g:exit:cd"

  # append to the history file, don't overwrite it
  shopt -s histappend

  # keep 5,000 commands in our command history
  export HISTSIZE=5000

  # keep 5,000 commands in our file-based command history
  export HISTFILESIZE=5000

  # check the window size after each command and, if necessary,
  # update the values of LINES and COLUMNS.
  shopt -s checkwinsize

  # make less more friendly for non-text input files, see lesspipe(1)
  [ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

  # 1) prefix the time (24-hour clock) in dark grey:
  PS1='[\[\033[37m\]\t\[\033[00m\]]'
  # 2) <chroot> <user>@<host>:<working directory>
  PS1="${PS1}"'[\[\033[01;35m\]${debian_chroot:+($debian_chroot)}\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]]'
  # 3) terminate with $, coloured red if the last command exited with a non-zero status.
  PS1="${PS1}\$([[ \$? != 0 ]] && echo \"\[\033[01;31m\]\")\\$\[\033[00m\] "

  # if this is an xterm set the title to user@host:dir
  case "$TERM" in
    xterm*|rxvt*)
      PS1="\[\e]0;\u@\h: \w\a\]$PS1"
      ;;
    *)
      ;;
  esac

  # add nice colors for ls/grep/fgrep/egrep.
  if type -P dircolors >/dev/null; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias egrep='egrep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias grep='grep --color=auto'
  fi

  # convenience aliases
  alias l='ls -CF'
  alias la='ls -A'
  alias ll='ls -l'
  alias lla='ls -la'

  # filesystem mark/jump functions, slightly modified from those by jeroen janssens at
  #  http://jeroenjanssens.com/2013/08/16/quickly-navigate-your-filesystem-from-the-command-line.html
  export MARK_ROOT="${HOME}/.marks"

  function jump
  {
    cd -P "${MARK_ROOT}/${1}" 2>/dev/null || echo "jump: ${1}: No such mark" >&2
  }

  function mark
  {
    mkdir --parents "${MARK_ROOT}"
    ln --symbolic --verbose "$(pwd)" "${MARK_ROOT}/${1}"
  }

  function marks
  {
    ls --color=always -l "${MARK_ROOT}" | sed 's/  / /g' | cut --delimiter=' ' --fields=9- | sed 's/ -/\t-/g' | tail --lines=+2
  }

  function unmark
  {
    rm --verbose "${MARK_ROOT}/${1}"
  }

  # enable programmable completion features (you don't need to enable
  # this, if it's already enabled in /etc/bash.bashrc and /etc/profile
  # sources /etc/bash.bashrc).
  #if ! shopt -oq posix; then
  #  if [ -f /usr/share/bash-completion/bash_completion ]; then
  #    . /usr/share/bash-completion/bash_completion
  #  elif [ -f /etc/bash_completion ]; then
  #    . /etc/bash_completion
  #  fi
  #fi

  # keychain (ssh-agent) setup
  if [ -n "${SSH_AGENT_PID}" ]; then
    echo -e "\033[32m[ INFO ]\033[0m inheriting SSH_AGENT_PID: ${SSH_AGENT_PID}" >&2
  elif [ -n "${SSH_AUTH_SOCK}" ]; then
    echo -e "\033[32m[ INFO ]\033[0m inheriting SSH_AUTH_SOCK: ${SSH_AUTH_SOCK}" >&2
  elif type -P keychain >/dev/null; then
    eval `keychain --eval --ignore-missing --quiet id_rsa id_dsa id_ecdsa`
  else
    echo -e "\033[31m[ WARNING ]\033[0m 'keychain' not available, skipping ssh-agent initialization" >&2
  fi
fi

# check for a 'local' bashrc file and include it if it exists.
if [ -s "${HOME}/.bashrc.local" ]; then
  source "${HOME}/.bashrc.local"
fi
