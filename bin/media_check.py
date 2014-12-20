#!/usr/bin/python
# -*- coding: utf-8 -*-
#
# This is a general utility script to monitor a media library and ensure that the files within it
# are valid and remain that way.  It is designed specifically to detect when corrupt media files are
# added or when a previously correct media file is corrupted (by bad disk sectors, for example).
#
import argparse
import fnmatch
import logging
import os
import re
import sqlite3
import subprocess
import sys
import time

__version__ = "0.2.3"


def checksum(path):
	checksum = None
	proc = subprocess.Popen(["/usr/bin/cksfv", "-c", path], stderr=subprocess.STDOUT, stdin=open("/dev/null"), stdout=subprocess.PIPE, close_fds=True, cwd="/", env=dict())
	for line in proc.stdout:
		line = unicode(line, "utf-8", errors="ignore")
		if line[0:len(path)] == path:
			checksum = line[len(path)+1:len(line)]
	return checksum.rstrip()


def transcode(path):
	control_characters = "".join(map(unichr, range(0,32) + range(127, 160)))
	control_characters_re = re.compile("[%s]" % re.escape(control_characters))

	errors = 0
	warnings = 0
	proc = subprocess.Popen(["/usr/bin/ffmpeg", "-v", "verbose", "-i", path, "-f", "null", "-"], stderr=subprocess.STDOUT, stdin=open("/dev/null"), stdout=subprocess.PIPE, close_fds=True, cwd="/", env=dict())
	for line in proc.stdout:
		line = control_characters_re.sub("", line)
		line = unicode(line, "utf-8", errors="ignore")
		if line.find("error") != -1:
			logging.debug(u"ffmpeg error detected: {error_message}".format(error_message=line))
			errors += 1
		if line.find("warning") != -1:
			logging.debug(u"ffmpeg warning detected: {error_message}".format(error_message=line))
			warnings += 1
	return (errors + warnings)


def configure():
	parser = argparse.ArgumentParser(description="Check all media files under the given directory for validity.")
	parser.add_argument(
		"-c", "--checksum-every",
		default=14,
		help="how often (in days) to validate media file checksums (default: %(default)s, set to 0 to disable checksum validation)",
		metavar="DAYS",
		type=int,
	)
	parser.add_argument(
		"-d", "--database-path",
		default="{home}/.media_check.sqlite".format(home=os.environ["HOME"]),
		help="location of the SQLite database within which to store media state (default: %(default)s)",
		metavar="DBPATH"
	)
	parser.add_argument(
		"-m", "--media-glob",
		action="append",
		default=["*.avi", "*.mkv"],
		help="treat any file matching one of these shell glob patterns (argument can be given multiple times) as a media file (default: %(default)s)",
		metavar="GLOB"
	)
	parser.add_argument(
		"-n", "--maximum-media-verifications",
		default=None,
		help="the maximum number of media files to verify (default: verify all pending files)",
		metavar="NVERIFIES",
		type=int
	)
	parser.add_argument(
		"-p", "--prune",
		action="store_true",
		help="prune files that no longer exist out of the database (default: leave files that no longer exist in the database)"
	)
	parser.add_argument(
		"-r", "--report",
		default=None,
		help="display a full report of damaged media files (files that encountered more than NERR errors during transcoding)",
		metavar="NERR",
		type=int
	)
	parser.add_argument(
		"-t", "--maximum-run-time",
		default=None,
		help="run continually for at most SECS seconds (default: run until all pending files are verified)",
		metavar="SECS",
		type=int
	)
	parser.add_argument(
		"-v", "--verbose",
		action="count",
		help="increase the verbosity of the %(prog)s log output (argument can be given multiple times, to a maximum of -vv)"
	)
	parser.add_argument(
		"--version",
		action="version",
		help="display %(prog)s version",
		version="%(prog)s {version}".format(version=__version__)
	)
	parser.add_argument(
		"directories",
		help="one or more parent directories under which %(prog)s should search for media files",
		metavar="DIR",
		nargs="*"
	)
	arguments = parser.parse_args()
	arguments.checksum_every *= 24 * 3600

	loglevel = logging.WARNING
	if arguments.verbose >= 1:
		loglevel = logging.INFO
	if arguments.verbose >= 2:
		loglevel = logging.DEBUG
	logging.basicConfig(datefmt="%d %b %Y %H:%M:%S", format="%(asctime)s %(levelname)-8s %(message)s", level=loglevel)
	logging.debug("arguments: %s", str(arguments))

	return arguments


class MediaDB(object):
	def __init__(self, path):
		self.cnx = None
		self.path = path
		self.connect()
		if self.connected():
			self.ensure_schema()

	def commit(self):
		self.cnx.commit()

	def connect(self):
		if self.connected():
			self.disconnect()

		try:
			self.cnx = sqlite3.connect(self.path)
			self.cnx.row_factory = sqlite3.Row
		except sqlite3.Error, e:
			logging.error("sqlite error: {error}".format(error=e.args[0]))
			self.disconnect()

	def connected(self):
		if self.cnx is not None:
			return True
		else:
			return False

	def disconnect(self):
		if self.cnx is not None:
			self.cnx.close()
			self.cnx = None

	def ensure_row(self, path):
		cur = self.cnx.cursor()
		cur.execute("SELECT ROWID FROM media WHERE path = ?", (path,))
		row = cur.fetchone()
		if row is None:
			m = MediaRow(self)
			m.path = path
			m.save()

	def ensure_schema(self):
		self.cnx.execute("CREATE TABLE IF NOT EXISTS media (checksum character(8), checksum_timestamp int, transcode_errors int, transcode_timestamp int, path text, size int)")
		self.cnx.execute("CREATE UNIQUE INDEX IF NOT EXISTS media_path_idx ON media (path)")

	def fetch_pending(self, checksum_threshold):
		cur = self.cnx.cursor()
		cur.execute("SELECT ROWID, * FROM media WHERE size IS NULL LIMIT 1")
		row = cur.fetchone()

		if (row is None) and (checksum_threshold is not None):
			cur.execute("SELECT ROWID, * FROM media WHERE (checksum_timestamp IS NULL) OR (checksum_timestamp < ?) ORDER BY checksum_timestamp ASC LIMIT 1", (checksum_threshold,))
			row = cur.fetchone()

		cur.close()
		if row is None:
			return None
		else:
			return MediaRow(self, row)

	def iterate_all(self):
		for row in self.cnx.execute("SELECT ROWID, * FROM media ORDER BY path"):
			yield MediaRow(self, row)

	def iterate_errored(self, error_threshold):
		for row in self.cnx.execute("SELECT ROWID, * FROM media WHERE transcode_errors >= ? ORDER BY path", (error_threshold,)):
			yield MediaRow(self, row)


class MediaRow(object):
	def __init__(self, db, row=None):
		self.db = db
		self.cur = db.cnx.cursor()
		self.clear()
		if row is not None:
			self.load(row)

	def __str__(self):
		return unicode(self).encode("utf-8")

	def __unicode__(self):
		return u"< MediaRow #{self.id:d}   {self.size:>13,d} bytes   0x{self.checksum:8s}   {self.transcode_errors:>3d} err   {self.path} >".format(self=self)

	def clear(self):
		self.id = None
		self._checksum = None
		self.checksum_timestamp = None
		self.checksum_updated = False
		self._transcode_errors = None
		self.transcode_errors_updated = False
		self.transcode_timestamp = None
		self.path = None
		self._size = None
		self.size_updated = False

	@property
	def checksum(self):
		return self._checksum

	@checksum.setter
	def checksum(self, value):
		logging_level = logging.DEBUG
		original_checksum = self._checksum
		if self._checksum != value:
			if self._checksum is None:
				logging_level = logging.INFO
			else:
				logging_level = logging.ERROR
			self.checksum_updated = True
			self._checksum = value
		else:
			self.checksum_updated = False
		if self.checksum_updated and (original_checksum is not None):
			logging.log(logging_level, u"checksum({path}): {original_checksum} => {new_checksum}".format(new_checksum=self._checksum, original_checksum=original_checksum, path=self.path))

	@property
	def size(self):
		return self._size

	@size.setter
	def size(self, value):
		logging_level = logging.DEBUG
		original_size = self._size
		if self._size != value:
			if self._size is None:
				logging_level = logging.INFO
			else:
				logging_level = logging.ERROR
			self.size_updated = True
			self._size = value
		else:
			self.size_updated = False
		if self.size_updated and (original_size is not None):
			if original_size is not None:
				original_size = u"{original_size:,d}".format(original_size=original_size)
			new_size = self._size
			if new_size is not None:
				new_size = u"{new_size:,d}".format(new_size=new_size)
			logging.log(logging_level, u"size({path}): {original_size} => {new_size}".format(new_size=new_size, original_size=original_size, path=self.path))

	@property
	def transcode_errors(self):
		return self._transcode_errors

	@transcode_errors.setter
	def transcode_errors(self, value):
		logging_level = logging.DEBUG
		original_transcode_errors = self._transcode_errors
		if self._transcode_errors != value:
			self.transcode_errors_updated = True
			self._transcode_errors = value
			if self._transcode_errors > 0:
				logging_level = logging.ERROR
			else:
				logging_level = logging.INFO
		else:
			if self._transcode_errors > 0:
				logging_level = logging.WARNING
			self.transcode_errors_updated = False
		if self.transcode_errors_updated and (original_transcode_errors is not None):
			if original_transcode_errors is not None:
				original_transcode_errors = u"{original_transcode_errors:,d}".format(original_transcode_errors=original_transcode_errors)
			new_transcode_errors = self._transcode_errors
			if new_transcode_errors is not None:
				new_transcode_errors = u"{new_transcode_errors:,d}".format(new_transcode_errors=new_transcode_errors)
			logging.log(logging_level, u"transcode errors({path}): {original_transcode_errors} => {new_transcode_errors}".format(new_transcode_errors=new_transcode_errors, original_transcode_errors=original_transcode_errors, path=self.path))

	def load(self, row):
		(self.id, self.checksum, self.checksum_timestamp, self.transcode_errors, self.transcode_timestamp, self.path, self.size) = row

	def remove(self):
		logging.warning(u"exists({path}): True => False".format(path=self.path))
		self.cur.execute("DELETE FROM media WHERE ROWID = ?", (self.id,))
		self.db.commit()
		self.clear()

	def save(self):
		if self.id is None:
			self.cur.execute("INSERT INTO media (checksum, checksum_timestamp, transcode_errors, transcode_timestamp, path, size) VALUES (?, ?, ?, ?, ?, ?)", (self.checksum, self.checksum_timestamp, self.transcode_errors, self.transcode_timestamp, self.path, self.size))
			self.id = self.cur.lastrowid
			logging.debug(u"exists({path}): False => True".format(path=self.path))
		else:
			self.cur.execute("UPDATE media SET checksum=?, checksum_timestamp=?, transcode_errors=?, transcode_timestamp=?, path=?, size=? WHERE ROWID=?", (self.checksum, self.checksum_timestamp, self.transcode_errors, self.transcode_timestamp, self.path, self.size, self.id))
		self.db.commit()


if __name__ == "__main__":
	arguments = configure()
	db = MediaDB(arguments.database_path)
	if not db.connected():
		logging.error("no connection to database %s is available", arguments.database_path)
		sys.exit(7)

	# If we are just reporting the current state of the database, then print the requested
	# report and immediately exit.
	if arguments.report is not None:
		for m in db.iterate_errored(arguments.report):
			print u"{errors:>3d} {path}".format(errors=m.transcode_errors, path=m.path)
		sys.exit(0)

	# If a hard limit has been put on our execution time, calculate the time after which
	# we need to exit.
	if arguments.maximum_run_time is not None:
		run_time_threshold = time.time() + arguments.maximum_run_time
	else:
		run_time_threshold = None

	# Add all new files in the listed directories to the database.
	for root in arguments.directories:
		count = 0
		for root, directories, files in os.walk(root, topdown=False, followlinks=True):
			for glob in arguments.media_glob:
				for file in fnmatch.filter(files, glob):
					count += 1
					db.ensure_row(unicode(os.path.join(root, file), "utf-8"))
		logging.info("found {count:,d} media files within root: {root}".format(count=count, root=root))

	# If pruning is enabled, remove all rows from the database that don't exist on disk.
	if arguments.prune:
		for m in db.iterate_all():
			if not os.path.isfile(m.path):
				m.remove()

	# Loop over our 'pending' (i.e. ready to be verified) media files and verify them
	# until either:
	#   (1) there are no more pending media files.
	#   (2) we run out of time (as per --maximum-run-time).
	#   (3) we have verified --maximum-media-verifications media files.
	media_verification_count = 0
	while True:
		if (run_time_threshold is not None) and (time.time() > run_time_threshold):
			logging.info("maximum allowable run time ({maximum_run_time} seconds) has elapsed, exiting...".format(maximum_run_time=arguments.maximum_run_time))
			break;

		if (arguments.maximum_media_verifications is not None) and (media_verification_count >= arguments.maximum_media_verifications):
			logging.info("maximum allowable media verifications ({maximum_media_verifications}) have been executed, exiting...".format(maximum_media_verifications=arguments.maximum_media_verifications))
			break;

		if arguments.checksum_every > 0:
			checksum_threshold = time.time() - arguments.checksum_every
		else:
			checksum_threshold = None
		m = db.fetch_pending(checksum_threshold)
		if m is None:
			logging.info("no pending media verifications to execute, exiting...")
			break
		if not os.path.isfile(m.path):
			if arguments.prune:
				m.remove()
			else:
				logging.warning("skipping media verification (file does not exist): {path}".format(path=m.path))
		else:
			media_verification_count += 1
			logging.info("verifying media: {path}".format(path=m.path))
			m.size = os.stat(m.path).st_size
			if (checksum_threshold is not None) and (m.size_updated or (m.checksum_timestamp is None) or (m.checksum_timestamp < checksum_threshold)):
				m.checksum = checksum(m.path)
				m.checksum_timestamp = time.time()
				if (m.checksum_updated):
					m.transcode_errors = transcode(m.path)
					m.transcode_timestamp = time.time()
			m.save()