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
	
	cd /tmp
	sudo -u nobody wget "${URL}"
	if [ -t 0 ]; then
		# stdin is a terminal -- i.e. no custom configure/make/make install
		# process was passed in on stdin, and therefore we don't have
		# a custom process to send on to shutil_tarball_source_install.
		shutil_tarball_source_install "/tmp/${ARCHIVE}"
	else
		# stdin is not a terminal, so we assume that it contains the
		# command sequence that should be used to configure/make/install
		# this package, and we therefore pass it on to shutil_tarball_source_install.
		cat '/dev/stdin' | shutil_tarball_source_install "/tmp/${ARCHIVE}"
	fi
	rm "${ARCHIVE}"
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

	# Decompress the package archive into /tmp, the source is assumed
	# to end up in /tmp/${PACKAGE_NAME}
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
	"${DECOMPRESSOR}" "${SOURCE_ARCHIVE}" | sudo -u nobody tar --extract --verbose --directory "/tmp/"

	local STOW_DIR="/usr/local/stow/${PACKAGE_NAME}"
	mkdir -p "${STOW_DIR}"
	chown -R nobody "${STOW_DIR}"
	cd "/tmp/${PACKAGE_NAME}"

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
	
	cd "${STOW_DIR}"
	# If our stow directory is still owned by 'nobody' (i.e. the code
	# executed above hasn't changed things), then chown it to 'root'.
	if [ "$(stat --format='%U' .)" == "nobody" ]; then
		chown -R root .
	fi
	cd ..
	stow -v "${PACKAGE_NAME}"
	cd "/tmp"
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
