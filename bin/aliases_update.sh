#!/bin/bash -e
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
# A simple script that regenerates /etc/aliases based on /etc/passwd.  Can be
# dropped into /etc/cron.daily in order to rebuild /etc/aliases once per day.
#

#
# Generate an /etc/aliases file based on the current state of /etc/passwd.
#
touch "/etc/aliases.${$}"
if [ -e "/etc/aliases" ]; then
	chown --reference="/etc/aliases" "/etc/aliases.${$}"
	chmod --reference="/etc/aliases" "/etc/aliases.${$}"
fi
{
	echo '# /etc/aliases'
	echo '#'
	echo "# Generation script: $(realpath "${0}")"
	echo "# Generation date:   $(date)"
	echo '#'
	echo '# Do not edit manually, changes will not be preserved.'
	echo '#'
	echo '# See `man 5 aliases` for format.'
	echo '#'
	echo
	cat /etc/passwd | awk -F":" '
		{ destination = "root" } # Set default destination of "root".
		$1 == "+" { next }       # Skip NIS dummy line if we encounter it ("+::::::").
		
		# Specific user rules - one per user, sets the e-mail address destination
		# for mails to that user.
		# $1 == "user" { destination = "user@example.com" }
		# $1 == "root" { destination = "root@example.com" }
		
		# Print our actual alias line, as long as we have determined a destination.
		destination != "" { print $1 ": " destination }
	'
} > "/etc/aliases.${$}"

#
# Check if the files are the same, if they are then leave the old file alone
# and exit.
#
if diff -uN -I '^#' "/etc/aliases" "/etc/aliases.${$}"; then
	rm "/etc/aliases.${$}"
	exit
fi

#
# Install our updated /etc/aliases file.
#
mv -f "/etc/aliases.${$}" "/etc/aliases"

#
# Update our aliases database and inform the mailserver of the changes.
#
newaliases
