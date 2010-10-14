#!/usr/bin/python
# -*- coding: utf-8 -*-
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

from __future__ import with_statement
import gzip
import logging
import optparse
import os
import re
import sys

__version__ = "$Rev: 17549 $"

def main(options):
	"""
	Read a mysqldump SQL file from stdin and split it out into multiple SQL
	files.  Each database creation is put in its own SQL file (named
	'<database>.sql'), and each table is also put in its own SQL file (named
	'<database>/<table>.sql').
	"""
	# Pre-compile our regular expressions for performance reasons.
	database_creation_re = re.compile('^CREATE DATABASE .* `(.*?)` .*;$')
	database_start_re = re.compile('^USE `(.*?)`;$')
	header_line_re = [
		re.compile('CHANGE MASTER TO'),
		re.compile('^/[*]!\d+ SET .* [*]/;$')
	]
	low_importance_re = [
		re.compile('^/[*]!\d+ SET .* [*]/;$'),
		re.compile('^SET (@saved_cs_client|character_set_client)\s+= ')
	]
	table_start_re = re.compile('^CREATE TABLE `(.*?)` [(]$')
	table_end_re = re.compile('^UNLOCK TABLES;$')
	worthless_re = re.compile('^(\s*|--.*)$')
	
	current_database = None # Whether we are currently within a database.
	current_table_fd = None # Whether we are currently within a table.

	# Keep an array of 'header' lines to prepend to each table definition.
	header = []

	lineno = 0
	for line in sys.stdin:
		lineno += 1

		# Collect any header lines into our 'header' array. We do this before
		# we drop comments and blank lines so that (if we want/need) some
		# comments can be saved for our header.  Note that we only check
		# for header lines as long as we aren't within a database or table.
		if current_database is None and current_table_fd is None:
			found = False
			for hl in header_line_re:
				if hl.search(line):
					logging.debug("[Line %d] [HEADER] %s", lineno, line.strip())
					header.append(line)
					found = True
					continue
			if found:
				continue

		# Skip worthless lines (i.e. comments and blank lines) from this point on.
		if worthless_re.search(line):
			continue

		# Handle CREATE DATABASE statements.
		match = database_creation_re.search(line)
		if match:
			logging.debug("[Line %d] [CREATE DATABASE] %s", lineno, line.strip())
			if not os.path.isdir("%s/%s" % (options.root, match.group(1))):
				os.mkdir("%s/%s" % (options.root, match.group(1)))
			if options.gzip:
				f = gzip.open('%s/%s.sql.gz' % (options.root, match.group(1)), 'w+')
			else:
				f = open('%s/%s.sql' % (options.root, match.group(1)), 'w+')
			try:
				f.write(line)
			finally:
				f.close()
			continue
	
		# Handle USE statements.
		match = database_start_re.search(line)
		if match:
			logging.debug("[Line %d] [USE] %s", lineno, line.strip())
			current_database = match.group(1)
			if current_table_fd:
				logging.error("[Line %d] database change encountered within table: %s", lineno, line.strip())
				current_table_fd.close()
				current_table_fd = None
			continue
	
		# Handle CREATE TABLE statements.
		match = table_start_re.search(line)
		if match:
			if current_table_fd:
				logging.error("[Line %d] table creation encountered within table: %s", lineno, line.strip())
				current_table_fd.close()
				current_table_fd = None
			logging.debug("[Line %d] [CREATE TABLE] %s", lineno, line.strip())
			if options.gzip:
				current_table_fd = gzip.open('%s/%s/%s.sql.gz' % (options.root, current_database, match.group(1)), 'w+')
			else:
				current_table_fd = open('%s/%s/%s.sql' % (options.root, current_database, match.group(1)), 'w+')
			for h in header:
				current_table_fd.write(h)

		# Otherwise, we have a plain SQL statement.
		if current_table_fd:
			current_table_fd.write(line)
		else:
			found = False
			for li in low_importance_re:
				if ((not found) and li.search(line)):
					found = True
					logging.debug("[Line %d] ignoring bare SQL outside of table: %s", lineno, line.strip())
			if (not found):
				logging.warning("[Line %d] ignoring bare SQL outside of table: %s", lineno, line.strip())

		# Handle UNLOCK TABLES statements.
		match = table_end_re.search(line)
		if match:
			logging.debug("[Line %d] [UNLOCK TABLES] %s", lineno, line.strip())
			if current_table_fd:
				current_table_fd.close()
				current_table_fd = None
			else:
				logging.error("[Line %d] unlock tables encountered outside of table: %s", lineno, line.strip())

def parse_arguments():
	"""
	Parse command-line arguments and setup an optparse object specifying
	the settings for this application to use.
	"""
	parser = optparse.OptionParser(
		usage="%prog [options]",
		version="%prog r" + re.sub("[^0-9]", "", __version__)
	)
	parser.add_option(
		"--debug",
		action="store_true",
		default=False,
		help="enable display of verbose debugging information"
	)
	parser.add_option(
		"--gzip",
		action="store_true",
		default=False,
		help="enable gzip compression of created SQL files"
	)
	parser.add_option(
		"--root",
		default=os.getcwd(),
		help="root directory to store resultant SQL files in"
	)
	
	(options, args) = parser.parse_args()

	if not os.path.isdir(options.root):
		os.mkdir(options.root)

	return options

if __name__ == "__main__":
	options = parse_arguments()
	
	# Initialize our logging layer.
	loglevel = logging.INFO
	if options.debug:
		loglevel = logging.DEBUG
	logging.basicConfig(datefmt = "%d %b %Y %H:%M:%S", format = "%(asctime)s %(levelname)-8s %(message)s", level = loglevel)
	del loglevel

	logging.debug("options: %s", str(options))

	main(options)
