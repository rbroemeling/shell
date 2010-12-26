#!/usr/bin/env python
import base64
import json
import logging
import optparse
import os
import subprocess
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
		logging.info("found repository %s/%s: %s" % (repository["name"], repository["slug"], repository["description"]))
		if os.path.exists(repository["slug"]):
			logging.info("local directory '%s' already exists, pulling updates" % (repository["slug"]))
			os.chdir(repository["slug"])
			output  = subprocess.Popen(["hg", "pull"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT).communicate()[0]
			output += subprocess.Popen(["hg", "update"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT).communicate()[0]
			os.chdir("..")
		else:
			logging.info("local directory '%s' does not yet exist, cloning remote repository" % (repository["slug"]))
			output = subprocess.Popen(["hg", "clone", "ssh://hg@bitbucket.org/%s/%s" % (conf._username, repository["slug"])], stdout=subprocess.PIPE, stderr=subprocess.STDOUT).communicate()[0]
		for line in output.split("\n"):
			logging.debug(line)
	stale_timestamp = time.time() - (conf.stale_age * 3600 * 24)
	for repository in os.walk(".").next()[1]:
		logging.debug("checking age of local directory '%s': %d < %d?", repository, os.path.getmtime(repository), stale_timestamp)
		if os.path.getmtime(repository) < stale_timestamp:
			logging.warning("local directory '%s' is stale; it has not been updated in %d days" % (repository, conf.stale_age))

def parse_arguments():
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
		help="enable display of verbose debugging information"
	)
	parser.add_option(
		"--stale-age",
		default=2,
		dest="stale_age",
		help="the age (measured in days) at which a repository will be considered stale and trigger a warning",
		type="int"
	)

	(conf, args) = parser.parse_args()
        
	if len(args) < 2:
		parser.error("too few arguments given, missing either username or password")
	if len(args) > 2:
		parser.error("too many arguments given")
	if conf.stale_age < 0:
		parser.error("option --stale-age: must be larger than zero")

	conf._api_path = "https://api.bitbucket.org/1.0"
	conf._username = args[0]
	conf._password = args[1]
	conf._authorization = "Basic " + base64.encodestring("%s:%s" % (conf._username, conf._password)).rstrip()

	return conf

if __name__ == "__main__":
	conf = parse_arguments()

	# Initialize our logging layer.
	loglevel = logging.INFO
	if conf.debug:
		loglevel = logging.DEBUG
	logging.basicConfig(datefmt = "%d %b %Y %H:%M:%S", format = "%(asctime)s %(levelname)-8s %(message)s", level = loglevel)
	del loglevel

	logging.debug("configuration: %s", str(conf))

	main(conf)
