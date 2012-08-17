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
  rsync -rlptv --rsh="ssh" . "${HOST}:${LOCATION}/.environment-install"
  echo "
    cd '${LOCATION}/.environment-install'
    ./install.sh '${LOCATION}'
    cd '${LOCATION}'
    rm -rv '${LOCATION}/.environment-install'
  " | ssh "${HOST}" bash
else
  find . -type f | while read F; do
    F="${F:2}"
    [ "${F}" = "install.sh" ] && continue
    if ! diff -q -N "${F}" "${LOCATION}/${F}" >/dev/null 2>&1; then
      install -D --backup --mode=0644 --preserve-timestamps --verbose "${F}" "${LOCATION}/${F}"
    fi
  done
fi
