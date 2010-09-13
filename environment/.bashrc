# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
[ -z "$PS1" ] && return

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

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "$debian_chroot" ] && [ -r /etc/debian_chroot ]; then
	debian_chroot=$(cat /etc/debian_chroot)
fi

# set a nice color prompt
PS1='[\[\033[01;30m\]\t\[\033[00m\]][${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]]\$ '

# if this is an xterm set the title to user@host:dir
case "$TERM" in
        xterm*|rxvt*)
                PROMPT_COMMAND='echo -ne "\033]0;${USER}@${HOSTNAME}: ${PWD}\007"'
                ;;
        *)
                ;;
esac

# add nice colors for ls/grep/fgrep/egrep.
if [ -x /usr/bin/dircolors ]; then
	test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
	alias ls='ls --color=auto'
	alias egrep='egrep --color=auto --exclude-dir=".svn"'
	alias fgrep='fgrep --color=auto --exclude-dir=".svn"'
	alias grep='grep --color=auto --exclude-dir=".svn"'
else
	alias grep='grep --exclude-dir=".svn"'
	alias fgrep='fgrep --exclude-dir=".svn"'
	alias egrep='egrep --exclude-dir=".svn"'
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
#	. /etc/bash_completion
#fi
