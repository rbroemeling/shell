#!/usr/bin/env python
import base64
import json
import logging
import logging.handlers
import optparse
import os
import subprocess
import sys
import time
import urllib2

__version__ = "0.1.1"

def main(conf):
	"""
	Request a list of bitbucket repositories and mirror them to our local current
	working directory.  Then iterate through our current working directory
	and verify that all repositories in it have been updated.
	"""
	pagerequest = urllib2.Request("%s/users/%s/" % (conf._api_path, conf._username), None, {"Authorization": conf._authorization})
	pagehandle = urllib2.urlopen(pagerequest)
	repositories = json.load(pagehandle)
	for repository in repositories["repositories"]:
		conf._logger.info("found repository %s/%s: %s" % (repository["name"], repository["slug"], repository["description"]))
		if os.path.exists(repository["slug"]):
			conf._logger.info("local directory '%s' already exists, pulling updates" % (repository["slug"]))
			os.chdir(repository["slug"])
			output  = subprocess.Popen(["hg", "pull"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT).communicate()[0]
			output += subprocess.Popen(["hg", "update"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT).communicate()[0]
			os.chdir("..")
		else:
			conf._logger.info("local directory '%s' does not yet exist, cloning remote repository" % (repository["slug"]))
			output = subprocess.Popen(["hg", "clone", "ssh://hg@bitbucket.org/%s/%s" % (conf._username, repository["slug"])], stdout=subprocess.PIPE, stderr=subprocess.STDOUT).communicate()[0]
		for line in output.split("\n"):
			conf._logger.debug(line)
	stale_timestamp = time.time() - (conf.stale_age * 3600 * 24)
	for repository in os.walk(".").next()[1]:
		conf._logger.debug("checking age of local directory '%s': %d < %d?", repository, os.path.getmtime(repository), stale_timestamp)
		if os.path.getmtime(repository) < stale_timestamp:
			conf._logger.warning("local directory '%s' is stale; it has not been updated in %d days" % (repository, conf.stale_age))

def parse_arguments(logger):
	"""
	Parse command-line arguments and setup an optparse object specifying
	the settings for this application to use.
	"""
	parser = optparse.OptionParser(
		usage="%prog [options] <username> <password>",
		version="%prog v" + __version__
	)
	parser.add_option(
		"--debug",
		action="store_true",
		default=False,
		help="enable logging of debugging information"
	)
	parser.add_option(
		"--stale-age",
		default=2,
		dest="stale_age",
		help="the age (measured in days) at which a repository will be considered stale and trigger a warning",
		type="int"
	)
	parser.add_option(
		"--verbose",
		action="store_true",
		default=False,
		help="send logging of level info and below to stdout (as well as the default of syslog)"
	)

	(conf, args) = parser.parse_args()

	if len(args) < 2:
		parser.error("too few arguments given, missing either username or password")
	if len(args) > 2:
		parser.error("too many arguments given")
	if conf.stale_age < 0:
		parser.error("option --stale-age: must be larger than zero")

	conf._logger = logger
	conf._api_path = "https://api.bitbucket.org/1.0"
	conf._username = args[0]
	conf._password = args[1]
	conf._authorization = "Basic " + base64.encodestring("%s:%s" % (conf._username, conf._password)).rstrip()

	# Update our logging configuration according to our arguments.
	if conf.debug:
		conf._logger.setLevel(logging.DEBUG)
	if conf.verbose:
		stdout_handler = logging.StreamHandler(sys.stdout) 
		stdout_handler.setLevel(logging.DEBUG)
		stdout_handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)-8s %(message)s", "%b %d %H:%M:%S"))
		conf._logger.addHandler(stdout_handler)
		del stdout_handler
		
	return conf

if __name__ == "__main__":
	# Initialize our logging layer.
	logger = logging.getLogger(os.path.basename(__file__))
	logger.setLevel(logging.INFO)

	# By default, log all messages to syslog.
	syslog_handler = logging.handlers.SysLogHandler(address='/dev/log')
	syslog_handler.setLevel(logging.DEBUG)
	syslog_handler.setFormatter(logging.Formatter("%(name)s [%(levelname)s] %(message)s"))
	logger.addHandler(syslog_handler)
	del syslog_handler
	
	# By default, log all messages at or above the WARNING level to stderr.
	stderr_handler = logging.StreamHandler(sys.stderr)
	stderr_handler.setLevel(logging.WARNING)
	stderr_handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)-8s %(message)s", "%b %d %H:%M:%S"))
	logger.addHandler(stderr_handler)
	del stderr_handler

	conf = parse_arguments(logger)
	del logger
	
	conf._logger.debug("configuration: %s", str(conf))

	main(conf)
