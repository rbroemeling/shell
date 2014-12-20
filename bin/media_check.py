#!/usr/bin/python
# -*- coding: utf-8 -*-

import argparse
import fnmatch
import logging
import os
import re
import sqlite3
import subprocess
import sys
import time

__version__ = "0.1.2"


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
			errors += 1
		if line.find("warning") != -1:
			warnings += 1
	return (errors + warnings)


def configure():
	parser = argparse.ArgumentParser(description="Check all media files under the given directory for validity.")
	parser.add_argument(
		"--checksum-every",
		default=7,
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
		"--transcode-every",
		default=30,
		help="how often (in days) to validate media file transcode errors (default: %(default)s, set to 0 to disable transcode validation)",
		metavar="DAYS",
		type=int
	)
	parser.add_argument(
		"-r", "--report",
		default=None,
		help="display a full report of damaged media files (files that encountered more than NERR errors during transcoding)",
		metavar="NERR",
		type=int
	)
	parser.add_argument(
		"-t", "--run-time",
		default=None,
		help="run continually for at most SECS seconds (default: run until no more files have work pending)",
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
	arguments.transcode_every *= 24 * 3600

	loglevel = logging.WARNING
	if arguments.verbose >= 1:
		loglevel = logging.INFO
	if arguments.verbose >= 2:
		loglevel = logging.DEBUG
	logging.basicConfig(datefmt="%d %b %Y %H:%M:%S", format="%(asctime)s %(levelname)-8s %(message)s", level=loglevel)
	logging.debug("arguments: %s", str(arguments))

	return arguments


class MediaDB:
	def __init__(self, path):
		self.cnx = None
		self.path = path
		self.connect()
		if self.connected():
			self.schema_ensure()

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

	def schema_ensure(self):
		self.cnx.execute("CREATE TABLE IF NOT EXISTS media (checksum character(8), checksum_timestamp int, transcode_errors int, transcode_timestamp int, path text, size int)")
		self.cnx.execute("CREATE UNIQUE INDEX IF NOT EXISTS media_path_idx ON media (path)")


class MediaRow:
	@classmethod
	def report(self, db, errcnt):
		for row in db.cnx.execute("SELECT * FROM media WHERE transcode_errors >= ? ORDER BY path", (errcnt,)):
			print u"{errors:>3d} {path}".format(errors=row['transcode_errors'], path=row['path']).encode("utf-8")

	@classmethod
	def eldest(self, db, checksum_threshold, transcode_threshold):
		cur = db.cnx.cursor()
		row = None

		cur.execute("SELECT ROWID, * FROM media WHERE size is NULL LIMIT 1")
		row = cur.fetchone()

		if (row is None) and (checksum_threshold is not None):
			cur.execute("SELECT ROWID, * FROM media WHERE (checksum_timestamp IS NULL) OR (checksum_timestamp < ?) ORDER BY checksum_timestamp ASC LIMIT 1", (checksum_threshold,))
			row = cur.fetchone()

		if (row is None) and (transcode_threshold is not None):
			cur.execute("SELECT ROWID, * FROM media WHERE (transcode_timestamp IS NULL) OR (transcode_timestamp < ?) ORDER BY transcode_timestamp ASC LIMIT 1", (transcode_threshold,))
			row = cur.fetchone()

		cur.close()
		if row is None:
			return None
		return MediaRow(db, row)

	@classmethod
	def ensure(self, db, path):
		cur = db.cnx.cursor()
		cur.execute("SELECT ROWID FROM media WHERE path = ?", (path,))
		row = cur.fetchone()
		if row is None:
			m = MediaRow(db)
			m.path = path
			m.save()

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
		self.checksum = None
		self.checksum_timestamp = None
		self.transcode_errors = None
		self.transcode_timestamp = None
		self.path = None
		self.size = None

	def load(self, row):
		(self.id, self.checksum, self.checksum_timestamp, self.transcode_errors, self.transcode_timestamp, self.path, self.size) = row

	def remove(self):
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

	if arguments.report is not None:
		MediaRow.report(db, arguments.report)
		sys.exit(0)
	if arguments.run_time is not None:
		arguments.run_time = time.time() + arguments.run_time

	for root in arguments.directories:
		count = 0
		for root, directories, files in os.walk(root, topdown=False, followlinks=True):
			for glob in arguments.media_glob:
				for file in fnmatch.filter(files, glob):
					count += 1
					MediaRow.ensure(db, unicode(os.path.join(root, file), "utf-8"))
		logging.info("found {count:,d} media files within root: {root}".format(count=count, root=root))

	checksum_threshold = None
	transcode_threshold = None
	while ((arguments.run_time is None) or (time.time() < arguments.run_time)):
		if arguments.checksum_every > 0:
			checksum_threshold = time.time() - arguments.checksum_every
		if arguments.transcode_every > 0:
			transcode_threshold = time.time() - arguments.transcode_every

		m = MediaRow.eldest(db, checksum_threshold, transcode_threshold)
		if m is None:
			break
		if not os.path.isfile(m.path):
			logging.warning(u"exists({path}): True => False".format(path=m.path))
			m.remove()
		else:
			sz = os.stat(m.path).st_size
			lvl = logging.DEBUG
			if m.size is None:
				lvl = logging.INFO
			elif sz != m.size:
				lvl = logging.ERROR
			if m.size is None:
				logging.log(lvl, u"size({path}): None => {calculated:,d}".format(calculated=sz, path=m.path))
			else:
				logging.log(lvl, u"size({path}): {original:,d} => {calculated:,d}".format(calculated=sz, original=m.size, path=m.path))
			m.size = sz

			if (checksum_threshold is not None) and ((m.checksum_timestamp is None) or (m.checksum_timestamp < checksum_threshold)):
				cksum = checksum(m.path)
				lvl = logging.INFO
				if m.checksum is not None:
					if cksum != m.checksum:
						lvl = logging.ERROR
					else:
						lvl = logging.DEBUG
				logging.log(lvl, u"checksum({path}): {original} => {calculated}".format(calculated=cksum, original=m.checksum, path=m.path))
				m.checksum = cksum
				m.checksum_timestamp = time.time()

			if (transcode_threshold is not None) and ((m.transcode_timestamp is None) or (m.transcode_timestamp < transcode_threshold)):
				err = transcode(m.path)
				lvl = logging.DEBUG
				if m.transcode_errors == err:
					if err > 0:
						lvl = logging.WARNING
				else:
					if err == 0:
						lvl = logging.INFO
					else:
						lvl = logging.ERROR
				if m.transcode_errors is None:
					logging.log(lvl, u"transcode errors({path}): None => {calculated:,d}".format(calculated=err, path=m.path))
				else:
					logging.log(lvl, u"transcode errors({path}): {original:,d} => {calculated:,d}".format(calculated=err, original=m.transcode_errors, path=m.path))
				m.transcode_errors = err
				m.transcode_timestamp = time.time()

			m.save()
