#!/usr/bin/perl -w
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

=head1 NAME

B<nexopia_watchdog.pl>

=head1 PURPOSE

This script is a fairly simple process watchdog.

It idles on a server and keeps a sharp eye out for "problematic" server
processess (what constitutes a "problematic" server process is completely up to
the user to code).

Upon finding a "problematic" server process it takes a pre-defined action (again,
the action is up to the user to code).  The expected action would be sending a
specific signal (TERM or KILL) to the process to bring it under control.

By default, the watchdog logs each action it takes to the 'unlimited_email'
log4perl configuration.

=cut

use Getopt::Long;
use Log::Log4perl;
use Pod::Usage;
use POSIX;
use strict;

sub stat_proc($);

my $debug = 0;
my $dry_run = 0;
my $help_requested = 0;
my $interval = 60;
my $once = 0;

=head1 SYNOPSIS

C<nexopia_watchdog.pl>

=head1 OPTIONS

=over

=item --debug

Puts the script into debug mode: all logging will flow to STDOUT, and copious
amounts of debug and trace information will be displayed.  Consider using
L</"--dry_run"> when L</"--debug"> is enabled.

=item --dry_run

Orders the script to perform B<only> read-only operations.  Guarantees that
no actions are undertaken (i.e. no processes are disturbed).
Most useful in combination with L</"--debug">.

=item --interval=INTERVAL

Controls the interval at which the script will check for problematic processes.
Checks will be performed every INTERVAL seconds.

=item --once

Disables the main program loop of the script; such that it will perform the
problematic process check once only and then exit.  Combining
L</"--interval=INTERVAL"> with L</"--once"> is non-sensical, though it will not
throw an error.

=back

=cut

GetOptions
(
	'debug' => \$debug,
	'dry_run' => \$dry_run,
	'help' => \$help_requested,
	'interval=i' => \$interval,
	'once' => \$once,
) or pod2usage( { -exitval => 2 } );
if ($help_requested)
{
	pod2usage( { -exitval => 1 } );
}

# Setup and configure our logging output.
Log::Log4perl::init('/etc/log4perl.conf');
my $syslog_logger = Log::Log4perl->get_logger('daemon');
my $email_logger = Log::Log4perl->get_logger('daemon.unlimited_email');
if ($debug)
{
	$syslog_logger = Log::Log4perl->get_logger('debug');
	$email_logger = Log::Log4perl->get_logger('debug');
}

while (1)
{
	if (opendir(PROC, '/proc'))
	{
		while (my $f = readdir(PROC))
		{
			next if ($f !~ /^\d+$/);
			next if (! -d '/proc/' . $f);
			my $s = stat_proc($f);

			# We couldn't find the process or had an error stat'ing it, skip it.
			next if (! defined $s->{'pid'});

			# If the process is not a ruby nexopia-child or queue-child, skip it.
			next if ($s->{'comm'} ne '(ruby)');
			if (($s->{'cmdline'} !~ /^nexopia-child \[\d+\] active/) && ($s->{'cmdline'} !~ /^queue-child \{\d+\}/))
			{
				next;
			}

			my @kill_reasons = ();

			# Deal with what appear to be infinitely-looping ruby children
			# (more than twenty minutes of CPU time).  Note that 'utime' is
			# measured in jiffies, which we assume to be 1/100 of a second.
			#if (($s->{'state'} eq 'R') && ($s->{'utime'} > (20 * 60 * 100)))
			#
			#	push(@kill_reasons, 'Running, CPU Time >= ' . ($s->{'utime'} / 100) . 's');
			#}

			# Deal with memory-hogging ruby children (more than 1.5GB of RAM used).
			if ($s->{'vsize'} >= (1536 * 1024 * 1024))
			{
				push(@kill_reasons, 'Memory Usage >= ' . ($s->{'vsize'} / (1024 * 1024)) . 'MB');
			}

			if (@kill_reasons)
			{
				my $kill_reason_str = '[' . join('], [', @kill_reasons) . ']';
				my $process_str = join(' ', $s->{'pid'}, $s->{'comm'}, $s->{'cmdline'});
				if ($dry_run)
				{
					$email_logger->warn('Problematic PID ' . $process_str . ' ' . $kill_reason_str . ' DRY RUN: taking no action');
				}
				else
				{
					if (! kill(POSIX::SIGKILL, $s->{'pid'}))
					{
						$email_logger->error('Problematic PID ' . $process_str . ' ' . $kill_reason_str . ' termination via SIGKILL unsuccessful, signal was not received');
					}
					else
					{
						$email_logger->warn('Problematic PID ' . $process_str . ' ' . $kill_reason_str . ' terminated via SIGKILL');
					}
				}
			}
		}
		closedir(PROC);
	}
	else
	{
		$syslog_logger->error('Could not open /proc: ' . $!);
	}
	last if ($once);
	sleep $interval;
}

=head1 Internal Methods

=head2 stat_proc($)

=head3 Arguments

=over

=item * $pid

The process ID (pid) of the process that we wish to retrieve information for.

=back

=head3 Return Value

A hash of information on the status of the process.

=head3 Description

Simple utility function to fetch information about the requested process
from the /proc filesystem and return it in a hash.

=cut

sub stat_proc($)
{
	my ($pid) = @_;
	my %data = ();

	if (open(STAT, '</proc/' . $pid . '/stat'))
	{
		$syslog_logger->debug('Retrieving status of PID ' . $pid);
		my
		(
			$pid,
			$comm,
			$state,
			$ppid,
			$pgrp,
			$session,
			$tty_nr,
			$tpgid,
			$flags,
			$minflt,
			$cminflt,
			$majflt,
			$cmajflt,
			$utime,
			$stime,
			$cutime,
			$cstime,
			$priority,
			$nice,
			$placeholder,
			$itrealvalue,
			$starttime,
			$vsize,
			$rss,
			$rlim,
			$startcode,
			$endcode,
			$startstack,
			$kstkesp,
			$kstkeip,
			$signal,
			$blocked,
			$sigignore,
			$sigcatch,
			$wchan,
			$nswap,
			$cnswap,
			$exit_signal,
			$processor,
			$rt_priority,
			$policy,
			$delayacct_blkio_ticks
		) = split(/ /, <STAT>);
		close(STAT);

		$data{'pid'} = $pid;
		$data{'comm'} = $comm;
		$data{'state'} = $state;
		$data{'ppid'} = $ppid;
		$data{'pgrp'} = $pgrp;
		$data{'session'} = $session;
		$data{'tty_nr'} = $tty_nr;
		$data{'tpgid'} = $tpgid;
		$data{'flags'} = $flags;
		$data{'minflt'} = $minflt;
		$data{'cminflt'} = $cminflt;
		$data{'majflt'} = $majflt;
		$data{'cmajflt'} = $cmajflt;
		$data{'utime'} = $utime;
		$data{'stime'} = $stime;
		$data{'cutime'} = $cutime;
		$data{'cstime'} = $cstime;
		$data{'priority'} = $priority;
		$data{'nice'} = $nice;
		$data{'itrealvalue'} = $itrealvalue;
		$data{'starttime'} = $starttime;
		$data{'vsize'} = $vsize;
		$data{'rss'} = $rss;
		$data{'rlim'} = $rlim;
		$data{'startcode'} = $startcode;
		$data{'endcode'} = $endcode;
		$data{'startstack'} = $startstack;
		$data{'kstkesp'} = $kstkesp;
		$data{'kstkeip'} = $kstkeip;
		$data{'signal'} = $signal;
		$data{'blocked'} = $blocked;
		$data{'sigignore'} = $sigignore;
		$data{'sigcatch'} = $sigcatch;
		$data{'wchan'} = $wchan;
		$data{'nswap'} = $nswap;
		$data{'cnswap'} = $cnswap;
		$data{'exit_signal'} = $exit_signal;
		$data{'processor'} = $processor;
		$data{'rt_priority'} = $rt_priority;
		$data{'policy'} = $policy;
		$data{'delayacct_blkio_ticks'} = $delayacct_blkio_ticks;

		if ($syslog_logger->is_trace())
		{
			my $trace_str = 'Status of PID ' . $pid . ' found:';
			foreach my $key (keys %data)
			{
				$trace_str .= ' ' . $key . ' = ' . $data{$key} . ',';
			}
			$trace_str = substr($trace_str, 0, -1);
			$syslog_logger->trace($trace_str);
		}
	}
	else
	{
		$syslog_logger->warn('Retrieving status of PID ' . $pid . ' failed: ' . $!);
		return {};
	}

	if (open(CMDLINE, '</proc/' . $pid . '/cmdline'))
	{
		$syslog_logger->debug('Retrieving cmdline of PID ' . $pid);
		$data{'cmdline'} = <CMDLINE>;
		close(CMDLINE);
		if (! defined $data{'cmdline'})
		{
			# This is either a permissions problem (i.e. our user doesn't have
			# read permission to the 'cmdline' file in /proc) or is simply
			# a process that doesn't have a 'cmdline' (i.e. kernel processes
			# like '(pdflush)' or '(rpciod/0)').  We report it at debug level
			# because it is a somewhat common occurrence.
			$syslog_logger->debug('Retrieving cmdline of PID ' . $pid . ' failed');
			return {};
		}
		else
		{
			# Clean up possible garbage on the end of the cmdline.
			$data{'cmdline'} =~ s/[\0\s]+$//;
			$syslog_logger->trace('cmdline of PID ' . $pid . ' found: ' . $data{'cmdline'});
		}
	}
	else
	{
		$syslog_logger->warn('Retrieving cmdline of PID ' . $pid . ' failed: ' . $!);
		return {};
	}

	return \%data;
}

=head1 REVISION

$Id: nexopia_watchdog.pl 17444 2010-02-23 16:21:56Z remi $

=cut
