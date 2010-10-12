#!/bin/bash -e
#
# A simple script to install the environment files on a given host (or in a given location).
#

if [ -z "${1}" ]; then
	echo "Usage: ${0} DEST" >&2
	exit -1
fi

if [[ "${1}" =~ ":" ]]; then
	HOST="${1%%:*}"
else
	HOST=""
fi
LOCATION="${1#*:}"

if [ -n "${HOST}" ]; then
	rsync -rlptv --exclude=".svn" --rsh="ssh" . "${HOST}:${LOCATION}/.environment-install"
	echo "
		cd '${LOCATION}/.environment-install'
		./install.sh '${LOCATION}'
		cd '${LOCATION}'
		rm -rv '${LOCATION}/.environment-install'
	" | ssh "${HOST}" bash
else
	for F in .bash_logout .bashrc .emacs .hgrc .subversion/config .profile .vimrc; do
		install --backup --mode=0644 --preserve-timestamps --verbose "${F}" "${LOCATION}/${F}"
	done
fi
