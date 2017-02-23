#!/bin/bash
#
# A simple script to install the environment files on a given host (or in a given location).
#
set -euo pipefail

if [[ -z "${1}" ]]; then
  echo "Usage: ${0} HOME_DIR" >&2
  exit -1
fi

if [[ "${1}" =~ ":" ]]; then
  HOST="${1%%:*}"
else
  HOST=""
fi
LOCATION="${1#*:}"
LOCATION="${LOCATION%/}"

if [[ -n "${HOST}" ]]; then
  rsync -rlptv --rsh="ssh" . "${HOST}:${LOCATION}/.environment-install"
  echo "
    cd '${LOCATION}/.environment-install'
    ./install.sh '${LOCATION}'
    cd '${LOCATION}'
    rm -rv '${LOCATION}/.environment-install'
  " | ssh "${HOST}" bash
  exit
fi

for F in * .*; do
  [[ ! -f "${F}" ]] && continue
  [[ "${F}" == 'install.sh' ]] && continue
  if ! diff --brief --new-file "${LOCATION}/${F}" "${F}" >/dev/null 2>&1; then
    if [[ -e "${LOCATION}/${F}" ]]; then
      diff --unified "${LOCATION}/${F}" "${F}" || true
      read -N 1 -p 'Apply this change? [Y/n] ' -s
      echo
      if [[ ! "${REPLY}" =~ ^[Yy]{0,1}$ ]]; then
        continue
      fi
    fi
    install -D --backup --mode=0644 --preserve-timestamps --verbose "${F}" "${LOCATION}/${F}"
    if [[ -e "${LOCATION}/${F}~" ]]; then
      install -D --mode=0640 --preserve-timestamps --verbose "${LOCATION}/${F}~" "/tmp/${LOCATION////-}-${F}~"
    fi
  fi
done

if [[ ! -e "${LOCATION}/.bin" ]]; then
  mkdir "${LOCATION}/.bin"
fi
if [[ ! -e "${LOCATION}/.bin/ack" || "$("${LOCATION}/.bin/ack" --version | head --lines 1)" != "ack 2.14" ]]; then
  curl --location http://beyondgrep.com/ack-2.14-single-file >"${LOCATION}/.bin/ack"
  chmod 0755 "${LOCATION}/.bin/ack"
fi
