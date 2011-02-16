#
# The MIT License (http://www.opensource.org/licenses/mit-license.php)
#
# Copyright (c) 2010 Nexopia.com, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#

# shutil_lock(<lock file>, <attempts>)
#
# Create and claim <lock file>.  Attempt to claim <lock file> <attempts> times,
# sleeping in-between each attempt (see `man dotlockfile` for sleep time).  If
# <attempts> is less than zero, then attempts to claim <lock file> forever.  If
# <attempts> is not defined (or zero), then it defaults to '5'.  Returns
# success (zero) if the lock file has been claimed and failure (1) if it has not.
#
function shutil_lock()
{
	local LOCK_FILE="${1}"
	local ATTEMPTS="${2}"
	local INFINITE=""
	
	if [ -z "${ATTEMPTS}" ]; then
		ATTEMPTS="5"
	elif [ "${ATTEMPTS}" -eq "0" ]; then
		ATTEMPTS="5"
	fi
	if [ "${ATTEMPTS}" -lt "0" ]; then
		INFINITE="1"
		ATTEMPTS="1440" # each dotlockfile loop will last ~1 day.
	fi
	while ! dotlockfile -p -l -r "${ATTEMPTS}" "${LOCK_FILE}"; do
		if [ -z "${INFINITE}" ]; then
			return 1
		else
			sleep 60
		fi
	done
	return 0
}


# shutil_remote_source_install(<remote location>)
#
# A utility function to fetch a source archive from <remote location> using wget
# and then install it (via stow) on the localhost.
#
function shutil_remote_source_install
{
	local URL="${1}"
	local ARCHIVE="$(basename "${URL}")"
	
	cd "${HOME}"
	wget -O "${ARCHIVE}" "${URL}"
	if [ -t 0 ]; then
		# stdin is a terminal -- i.e. no custom configure/make/make install
		# process was passed in on stdin, and therefore we don't have
		# a custom process to send on to shutil_tarball_source_install.
		shutil_tarball_source_install "${HOME}/${ARCHIVE}"
	else
		# stdin is not a terminal, so we assume that it contains the
		# command sequence that should be used to configure/make/install
		# this package, and we therefore pass it on to shutil_tarball_source_install.
		cat '/dev/stdin' | shutil_tarball_source_install "${HOME}/${ARCHIVE}"
	fi
	rm -fv "${ARCHIVE}"
}


# shutil_tarball_source_install(<source archive file>)
#
# A utility function to install and stow a source archive by the
# default process of ./configure && make && make install && stow.
# It is possible to override this standard build process by passing in a
# a different command-sequence on stdin.
#
function shutil_tarball_source_install
{
	local SOURCE_ARCHIVE="${1}"
	local PACKAGE_NAME="$(basename "${SOURCE_ARCHIVE}")"
	local DECOMPRESSOR=""

	# Decompress the package archive into ${HOME}, the source is assumed
	# to end up in ${HOME}/${PACKAGE_NAME}
	case "${PACKAGE_NAME}" in
		*.tar )
			PACKAGE_NAME="$(basename "${PACKAGE_NAME}" ".tar")"
			DECOMPRESSOR="cat"
			;;
		*.tbz | *.tar.bz | *.tar.bz2 )
			PACKAGE_NAME="$(basename "${PACKAGE_NAME}" ".tbz")"
			PACKAGE_NAME="$(basename "${PACKAGE_NAME}" ".tar.bz")"
			PACKAGE_NAME="$(basename "${PACKAGE_NAME}" ".tar.bz2")"
			DECOMPRESSOR="bzcat"
			;;
		*.tgz | *.tar.gz )
			PACKAGE_NAME="$(basename "${PACKAGE_NAME}" ".tgz")"
			PACKAGE_NAME="$(basename "${PACKAGE_NAME}" ".tar.gz")"
			DECOMPRESSOR="zcat"
			;;
		* )
			echo "shutil_tarball_source_install() call error: ${SOURCE_ARCHIVE} is an unknown archive format."
			return -1
			;;
	esac
	"${DECOMPRESSOR}" "${SOURCE_ARCHIVE}" | tar --extract --verbose --directory "${HOME}"

	local STOW_DIR="/usr/local/stow/${PACKAGE_NAME}"
	mkdir -p "${STOW_DIR}"
	chown -R nobody "${STOW_DIR}"

	chown -R nobody "${HOME}/${PACKAGE_NAME}"
	cd "${HOME}/${PACKAGE_NAME}"

	if [ -t 0 ]; then
		# stdin is a terminal -- i.e. no custom configure/make/make install
		# process was passed in on stdin.  Use our default command sequence.
		[ -x ./configure ] && sudo -u nobody ./configure --prefix="${STOW_DIR}"
		sudo -u nobody make
		sudo -u nobody make install
	else
		# stdin is not a terminal, so we assume that it contains the
		# command sequence that should be used to configure/make/install
		# this package.
		export STOW_DIR
		cat '/dev/stdin' | bash
	fi
	
	# If our stow directory is still owned by 'nobody' (i.e. the code
	# executed above hasn't changed things), then chown it to 'root'.
	if [ "$(stat --format='%U' "${STOW_DIR}")" == "nobody" ]; then
		chown -R root "${STOW_DIR}"
	fi

	cd "${STOW_DIR}/.."
	stow -v "${PACKAGE_NAME}"
	cd "${HOME}"
	rm -rf "${PACKAGE_NAME}"
}


# shutil_unlock(<lock file>)
#
# Release <lock file>.  Returns success (zero) if the lock file has been
# released successfully and failure (1 or 2) if it has not.
#
function shutil_unlock()
{
	local LOCK_FILE="${1}"
	
	if [ ! -e "${LOCK_FILE}" -o ! -s "${LOCK_FILE}" ]; then
		# File doesn't exist or exists and is empty.
		return 1
	fi
	if [ "$(cat "${LOCK_FILE}")" -ne "${$}" ]; then
		# File contains a PID that is not us.
		return 2
	fi
	if dotlockfile -u "${LOCK_FILE}"; then
		return 0
	fi
	return 3
}
