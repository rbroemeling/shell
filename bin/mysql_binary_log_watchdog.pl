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

B<mysql_binary_log_watchdog.pl>

=head1 PURPOSE

When a MySQL master server runs out of space to store its binary logs it seizes up and
will not answer any more (write) queries until such time as space is cleared up.
Obviously we want to avoid that situation as much as possible.

This script is a fairly simple binary log watchdog whose purpose is to ensure
that the situation above occurs as rarely as possible.  It does this by helping
to ensure that the filesystem used to hold MySQL's binary logs does not run out
of space I<if at all possible>.  Note that this script prioritizes data consistency
over freeing up space; and thus "if at all possible" in the last sentence means
"if it can be done while ensuring data consistency".

To achieve that, the script monitors disk space utilization of the binary log
filesystem and removes the oldest binary log (assuming that all slaves are
past it) when space utilization grows beyond a certain threshold.  The script
tries to be quite careful to ensure that all slaves are past a binary log before
it is deleted -- no binary log will be deleted while there are still slave servers
that require it.  If there are no slaves running, this script will not delete
any binary logs.

Additionally, the script has the capability to trigger warnings (and send
warning e-mails via log4perl) when the age of the oldest binary log falls
below a certain threshold.  This is useful as a warning for when there is so
much write activity on a server that the binary logs are very 'young' (i.e.
not persisting for very long).

Finally, the script will trigger a warning if, even after all of the above checks,
the MySQL binary log filesystem is too full.

=cut

use DBI;
use File::Basename;
use File::Spec;
use Filesys::Df;
use Getopt::Long;
use Log::Log4perl;
use Pod::Usage;
use strict;

sub fetch_binary_logs();
sub fetch_slaves();
sub purge_binary_logs_to($);
sub safe_to_remove_binlog($);

my $age_threshold = 24;
my $alert_threshold = 90;
my $binlog_directory = undef;
my $debug = undef;
my $dry_run = 0;
my $help_requested = 0;
my $interval = 60;
my $mysqlbinlog = '/usr/local/mysql/bin/mysqlbinlog';
my $once = 0;
my $password = undef;
if ($ENV{MYSQL_BINARY_LOG_WATCHDOG_MYSQL_PASSWORD})
{
	$password = $ENV{MYSQL_BINARY_LOG_WATCHDOG_MYSQL_PASSWORD};
}
my $space_threshold = 80;
my $username = undef;
if ($ENV{MYSQL_BINARY_LOG_WATCHDOG_MYSQL_USERNAME})
{
	$username = $ENV{MYSQL_BINARY_LOG_WATCHDOG_MYSQL_USERNAME};
}

=head1 SYNOPSIS

C<mysql_binary_log_watchdog.pl --binlog_dir=DIR>

=head1 OPTIONS

=over

=item --age_threshold=AGE

Controls the threshold at which a warning will be sent about the binary
logs being too young (warning will be sent if the oldest binary log is
less than AGE hours old).

Defaults to 24 (24 hours).

=item --alert_threshold=%UTIL

Controls the threshold at which a warning will be sent about the binary log
filesystem space utilization (warning will be sent if the filesystem utilization
is more than %UTIL).

Defaults to 90 (90% utilization).

=item --binlog_dir=DIR

Controls which binary log directory location is being monitored.

There is no default, this is a required option.

=item --debug

Puts the script into debug mode: all logging will flow to STDOUT, and copious
amounts of debug and trace information will be displayed.  Consider using L</"--dry_run">
when L</"--debug"> is enabled.

=item --dry_run

Orders the script to perform B<only> read-only operations.  Guarantees that
no data is changed/deleted.  Most useful in combination with L</"--debug">.

=item --interval=INTERVAL

Controls the interval at which the script will perform the necessary checks.  Checks
will be performed every INTERVAL seconds.

Defaults to 60 (60 seconds).

=item --once

Disables the main program loop of the script; such that it will perform the necessary checks
once only and then exit.  Combining L</"--interval=INTERVAL"> with L</"--once"> is
non-sensical, though it will not throw an error.

=item --password=PASSWORD

Provides the password to use when connecting to all involved databases (the master on localhost
as well as each slave).

Can also be controlled by setting the environment variable MYSQL_BINARY_LOG_WATCHDOG_MYSQL_PASSWORD.

Defaults to no password.

=item --space_threshold=%UTIL

Controls the threshold at which disk space should be freed up by removal of the oldest binary
log file -- if removing the oldest binary log file is safe/possible.

Defaults to 80 (80% utilization).

=item --username=USERNAME

Provides the username to use when connecting to all involved databases (the master on localhost
as well as each slave).

Can also be controlled by setting the environment variable MYSQL_BINARY_LOG_WATCHDOG_MYSQL_USERNAME.

Defaults to no username.

=back

=cut

GetOptions
(
	'age_threshold=i' => \$age_threshold,
	'alert_threshold=i' => \$alert_threshold,
	'binlog_dir=s' => \$binlog_directory,
	'debug' => \$debug,
	'dry_run' => \$dry_run,
	'help' => \$help_requested,
	'interval=i' => \$interval,
	'once' => \$once,
	'password=s' => \$password,
	'space_threshold=i' => \$space_threshold,
	'username=s' => \$username
) or pod2usage( { -exitval => 2 } );
if ($help_requested)
{
	pod2usage( { -exitval => 1 } );
}
if (not defined $binlog_directory)
{
	pod2usage( { -exitval => 2, -message => "Required option missing: binlog_dir" } )
}

# Setup and configure our logging output.
Log::Log4perl::init('/etc/log4perl.conf');
my $logger = Log::Log4perl->get_logger('daemon.email');
if ($debug)
{
	$logger = Log::Log4perl->get_logger('debug');
}

while (1)
{
	# Fetch a list of the currently-existing binary logs.
	my $binary_logs = fetch_binary_logs();

	# Check available disk space.  Delete the oldest binary log if we are over our utilization threshold
	# and if it is safe to do so.  Send a notification if we are over our alert utilization threshold.
	my $df_ref = df($binlog_directory);
	if (defined $df_ref)
	{
		$logger->trace('Filesystem ' . $binlog_directory . ' is currently at ' . $df_ref->{per} . '% utilization');
		if ($df_ref->{per} >= $space_threshold)
		{
			if ($df_ref->{per} >= $alert_threshold)
			{
				$logger->warn('Filesystem ' . $binlog_directory . ' utilization of ' . $df_ref->{per} . '% is over threshold of ' . $space_threshold . '%');
			}
			else
			{
				$logger->info('Filesystem ' . $binlog_directory . ' utilization of ' . $df_ref->{per} . '% is over threshold of ' . $space_threshold . '%');
			}
			if (scalar @{$binary_logs} >= 2)
			{
				if (safe_to_remove_binlog($binary_logs->[0]->{Log_name}))
				{
					$logger->info('Purging binary log ' . $binary_logs->[0]->{Log_name} . ' to lower utilization of filesystem ' . $binlog_directory);
					purge_binary_logs_to($binary_logs->[1]->{Log_name});
				}
			}
		}
	}
	else
	{
		$logger->error('Could not read filesystem information for ' . $binlog_directory);
	}

	# Send a warning if we do not have binary log data back at least as far as $age_threshold
	# dictates.
	if (scalar @{$binary_logs})
	{
		if ($binary_logs->[0]->{Start_timestamp} > (time() - ($age_threshold * 3600)))
		{
			$logger->warn('Earliest binary log data available is from ' . POSIX::strftime('%H:%M on %A, %B %d, %Y', localtime($binary_logs->[0]->{Start_timestamp})) . ', which is less than ' . $age_threshold . ' hours ago');
		}
	}
	else
	{
		$logger->warn('No binary logs found in ' . $binlog_directory);
	}

	# Wait for $interval and then continue our loop, unless $once is set.
	last if ($once);
	sleep $interval;
}

=head1 Internal Methods

=head2 fetch_binary_logs()

=head3 Arguments

None.

=head3 Return Value

Reference to an array of hash references, each hash holding the information to describe a single binary log.
The array is sorted, from the oldest binary log (index 0) to the youngest binary log (index n).

=head3 Description

A simple method that reads through each file in $binlog_directory and assembles a complete list of
binary logs (names, paths, and file sizes) as well as the timestamps that each binary log covers.

=cut

sub fetch_binary_logs()
{
	my @binary_logs = ();

	if (! opendir(DIR, $binlog_directory))
	{
		$logger->error('Could not open directory ' . $binlog_directory . ' for read: ' . $!);
		return \@binary_logs;
	}
	while (my $entry = readdir(DIR))
	{
		my $entry_path = File::Spec->catfile($binlog_directory, $entry);
		my @status = stat($entry_path);
		if (! @status)
		{
			# We hide 'No such file or directory' warnings, as that is a simple
			# race-condition that we really don't need to receive warnings about.
			if ($! ne 'No such file or directory')
			{
				$logger->warn('Could not fetch status of directory entry ' . $entry_path . ': ' . $!);
			}
			next;
		}
		if (! -f _)
		{
			$logger->trace('Skipping directory entry ' . $entry_path . ': not a plain file');
			next;
		}
		if ($entry_path !~ /[.]\d{6,}$/)
		{
			$logger->trace('Skipping directory entry ' . $entry_path . ': filename does not conform to expected MySQL binary log filename format');
			next;
		}

		my $binary_log =
		{
			End_timestamp => $status[9],
			File_size => $status[7],
			Log_name => $entry,
			Log_path => $entry_path,
			Start_timestamp => undef
		};
		if (-x $mysqlbinlog)
		{
			if (open(MYSQLBINLOG, $mysqlbinlog . ' "' . $binary_log->{Log_path} . '" --stop-position=16384|'))
			{
				while (<MYSQLBINLOG>)
				{
					chomp;
					if (/^SET TIMESTAMP=(\d+)/)
					{
						$binary_log->{Start_timestamp} = $1;
						$logger->trace('Found start timestamp (' . $binary_log->{Start_timestamp} . ') on mysqlbinlog line "' . $_ . '"');
						last;
					}
					$logger->trace('Skipping mysqlbinlog line that starts with "' . substr($_, 0, 20) . '"');
				}
				close(MYSQLBINLOG);
			}
			else
			{
				$logger->warn('Could not open directory entry ' . $entry_path . ' with ' . $mysqlbinlog . ': ' . $!);
			}
		}
		else
		{
			$logger->error('Not able to search for start timestamp in directory entry ' . $entry_path . ': ' . $mysqlbinlog . ' does not exist, or is not executable.');
		}
		if ($logger->is_debug())
		{
			$logger->debug('Found Binary Log: ' . $binary_log->{Log_name});
			$logger->debug('       Full Path: ' . $binary_log->{Log_path});
			$logger->debug('       File Size: ' . $binary_log->{File_size});
			$logger->debug(' Start Timestamp: ' . $binary_log->{Start_timestamp} . ' (' . localtime($binary_log->{Start_timestamp}) . ')');
			$logger->debug('   End Timestamp: ' . $binary_log->{End_timestamp} . ' (' . localtime($binary_log->{End_timestamp}) . ')');
		}
		push(@binary_logs, $binary_log);
	}
	closedir(DIR);

	@binary_logs = sort { my @c = split(/[.]/, $a->{Log_name}); my @d = split(/[.]/, $b->{Log_name}); $c[$#c] <=> $d[$#d]; } @binary_logs;
	if ($logger->is_trace())
	{
		my $sorted_list = '';
		for (my $i = 0; $i <= $#binary_logs; $i++)
		{
			$sorted_list .= $binary_logs[$i]->{Log_name} . ', ';
		}
		$logger->trace('Sorted list of binary logs: ' . substr($sorted_list, 0, -2));
	}
	return \@binary_logs;
}

=head2 fetch_slaves()

=head3 Arguments

None.

=head3 Return Value

Reference to an array of hash references, each hash holding the information to describe a single MySQL slave server.

=head3 Description

A simple method that connects to the master database server (assumed to be on localhost) and assembles
a complete list of registered slave servers through the use of the C<SHOW SLAVE HOSTS> MySQL command.

=cut

sub fetch_slaves()
{
	my @slaves = ();

	my $dbh = DBI->connect('dbi:mysql::127.0.0.1:3306', $username, $password, { PrintError => 0 });
	if (! $dbh)
	{
		$logger->error('Could not connect to master database server 127.0.0.1: ' . $DBI::errstr);
		return \@slaves;
	}
	my $sth = $dbh->prepare('SHOW SLAVE HOSTS');
	if (! $sth)
	{
		$logger->error('Could not prepare statement: ' . $sth->errstr);
		return \@slaves;
	}
	if (! $sth->execute())
	{
		$logger->error('Could not execute statement: ' . $sth->errstr);
		return \@slaves;
	}
	while (my $row = $sth->fetchrow_hashref())
	{
		my $slave =
		{
			Host => $row->{Host},
			Master_id => $row->{Master_id},
			Port => $row->{Port},
			Server_id => $row->{Server_id}
		};
		$logger->debug('Found slave server: ' . $slave->{Host} . ':' . $slave->{Port});
		push(@slaves, $slave);
	}
	$sth->finish();
	$dbh->disconnect();
	return \@slaves;
}

=head2 safe_to_remove_binlog($)

=head3 Arguments

=over

=item * $target_binary_log

The name of the binary log that we wish to remove.

=back

=head3 Return Value

Boolean describing whether or not it is safe to remove the binary log $target_binary_log.

=head3 Description

Verifies that each slave server (as returned by L</"fetch_slaves()">) has completed executing
the binary log $target_binary_log and returns true if they have.  Returns false if no slaves
could be found, if it was not possible to communicate with one of the slaves, or if any
of the slaves have not yet completed executing the binary log $target_binary_log.

=cut

sub safe_to_remove_binlog($)
{
	my $target_binary_log = shift();
	my ($target_binary_log_idx) = $target_binary_log=~/[.](\d+)$/;
	my $target_binary_log_regex = $target_binary_log;
	$target_binary_log_regex =~ s/[.]\d{6,}$//;
	$target_binary_log_regex = '^' . $target_binary_log_regex . '[.]\d{6,}$';
	my $slaves = fetch_slaves();

	if (scalar @{$slaves} == 0)
	{
		$logger->warn('No slave MySQL servers could be found, disallowing any removal of binary logs');
		return 0;
	}
	$logger->trace('Checking (across ' . (scalar @{$slaves}) . ' slaves) whether it is safe to remove binary log ' . $target_binary_log . ', index ' . $target_binary_log_idx . ', regex ' . $target_binary_log_regex);
	for (my $i = 0; $i <= $#{$slaves}; $i++)
	{
		$logger->trace('Checking current binary log location of slave ' . $slaves->[$i]->{Host} . ':' . $slaves->[$i]->{Port});
		$slaves->[$i]->{Safe_to_Remove} = 0;
		my $dbh = DBI->connect('dbi:mysql:' . join(':', '', $slaves->[$i]->{Host}, $slaves->[$i]->{Port}), $username, $password, { PrintError => 0 });
		if (! $dbh)
		{
			$logger->error('Could not connect to slave database server ' . $slaves->[$i]->{Host} . ': ' . $DBI::errstr);
			return 0;
		}
		my $sth = $dbh->prepare('SHOW SLAVE STATUS');
		if (! $sth)
		{
			$logger->error('Could not prepare statement: ' . $sth->errstr);
			return 0;
		}
		if (! $sth->execute())
		{
			$logger->error('Could not execute statement: ' . $sth->errstr);
			return 0;
		}
		while (my $row = $sth->fetchrow_hashref())
		{
			if ($row->{Master_Log_File} !~ /$target_binary_log_regex/)
			{
				$logger->trace('Skipping master log file ' . $row->{Master_Log_File} . ', does not match target regex');
				next;
			}
			my ($slave_current_log_file_idx) = $row->{Master_Log_File}=~/[.](\d+)$/;
			$logger->trace('Found master log file ' . $row->{Master_Log_File} . ', index ' . $slave_current_log_file_idx);
			if ($slave_current_log_file_idx > $target_binary_log_idx)
			{
				$logger->debug('Marking slave ' . $slaves->[$i]->{Host} . ':' . $slaves->[$i]->{Port} . ' as safe, slave index ' . $slave_current_log_file_idx . ' > target index ' . $target_binary_log_idx);
				$slaves->[$i]->{Safe_to_Remove} = 1;
			}
			last;
		}
		$sth->finish();
		$dbh->disconnect();
	}
	for (my $i = 0; $i <= $#{$slaves}; $i++)
	{
		$logger->trace('Slave: ' . $slaves->[$i]->{Host} . ':' . $slaves->[$i]->{Port} . ', Safe_to_Remove = ' . $slaves->[$i]->{Safe_to_Remove});
		if (! $slaves->[$i]->{Safe_to_Remove})
		{
			return 0;
		}
	}
	return 1;
}

=head2 purge_binary_logs_to($)

=head3 Arguments

=over

=item * $new_oldest_binary_log

The name of the binary log that we want to execute the SQL C<PURGE BINARY LOGS TO ...> for.

=back

=head3 Return Value

Boolean describing whether or not we were successful in purging the binary logs before
$new_oldest_binary_log.

=head3 Description

Executes the SQL C<PURGE BINARY LOGS TO $new_oldest_binary_log>, such that all binary logs
B<before> $new_oldest_binary_log will be purged (deleted).  See http://dev.mysql.com/doc/refman/5.0/en/purge-binary-logs.html
for more information on what the database server will do when it receives this command.

=cut

sub purge_binary_logs_to($)
{
	my $dbh = DBI->connect('dbi:mysql::127.0.0.1:3306', $username, $password, { PrintError => 0 });
	if (! $dbh)
	{
		$logger->error('Could not connect to master database server 127.0.0.1: ' . $DBI::errstr);
		return 0;
	}
	my $sth = $dbh->prepare('PURGE BINARY LOGS TO ?');
	if (! $sth)
	{
		$logger->error('Could not prepare statement: ' . $sth->errstr);
		return 0;
	}
	if ($dry_run)
	{
		$logger->warn('DRY RUN: Execution of SQL (' . $sth->{Statement} . ') [' . shift() . '] statement skipped');
	}
	else
	{
		if (! $sth->execute(shift()))
		{
			$logger->error('Could not execute statement: ' . $sth->errstr);
			return 0;
		}
		$sth->finish();
	}
	$dbh->disconnect();
	return 1;
}

=head1 REVISION

$Id: mysql_binary_log_watchdog.pl 17064 2009-12-07 18:59:37Z remi $

=cut
