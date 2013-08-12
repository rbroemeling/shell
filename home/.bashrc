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
  PS1='[\[\033[01;30m\]\t\[\033[00m\]]'
  # 2) <chroot> <user>@<host>:<working directory>
  PS1="${PS1}"'[\[\033[01;32m\]${debian_chroot:+($debian_chroot)}\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]]'
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

  # convenience function to compare a local file/directory (lhs) with a
  # remote file/directory (rhs)
  function remotediff()
  {
    LOCAL_FILE="${1}"
    shift
    REMOTE_HOST="$(echo "${1}" | awk -F: '{print $1}')"
    REMOTE_FILE="$(echo "${1}" | awk -F: '{print $2}')"
    shift

    if [ -z "${LOCAL_FILE}" -o -z "${REMOTE_HOST}" -o -z "${REMOTE_FILE}" ]; then
      echo "usage: remotediff LOCALPATH REMOTEPATH [... other args are passed to comparison call]"
      return -1
    fi
    if [ -d "${LOCAL_FILE}" ]; then
      # assume that we are dealing with a recursive diff of a directory
      rsync -rlptvzn --exclude=".svn" --del --rsh="ssh" "${@}" "${LOCAL_FILE}" "${REMOTE_HOST}:${REMOTE_FILE}"
    else
      # assume that we are dealing with a simple diff of a file
      ssh "${REMOTE_HOST}" -- gzip -c "${REMOTE_FILE}" | gunzip -c | diff "${@}" "${LOCAL_FILE}" -
    fi
  }

  # rsync convenience alias to ease synchronization of local <-> remote file(s).
  alias remotesync='rsync -rlptvz --exclude=".svn" --rsh="ssh"'

  # enable programmable completion features (you don't need to enable
  # this, if it's already enabled in /etc/bash.bashrc and /etc/profile
  # sources /etc/bash.bashrc).
  #if [ -f /etc/bash_completion ] && ! shopt -oq posix; then
  # . /etc/bash_completion
  #fi

  # keychain (ssh-agent) setup
  if type -P keychain >/dev/null; then
    keychain --quiet ~/.ssh/id_?sa
    . "${HOME}/.keychain/${HOSTNAME}-sh"
  else
    echo -e "[ \033[1;33;40m WARNING \033[0m ] 'keychain' not available, skipping ssh-agent initialization" >&2
  fi
fi

# check for a 'local' bashrc file and include it if it exists.
if [ -s "${HOME}/.bashrc.local" ]; then
  source "${HOME}/.bashrc.local"
fi
