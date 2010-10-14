#!/usr/bin/perl -w
# $Id: data_sanitizer.pl 16559 2009-09-09 14:58:28Z remi $
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

use Compress::Bzip2 qw(:constants :utilities);
use Config::IniFiles;
use Digest::MD5 qw(md5_hex);
use DBI;
use File::Basename;
use Getopt::Long;
use Log::Log4perl;
use Log::Log4perl::Layout;
use Log::Log4perl::Level;
use strict;


#
# Sanitization filter prototypes: declare each sanitization filter that is available
# here.
#
sub sanitize_email_address($);
sub sanitize_ip_address($);
sub sanitize_nullify($);
sub sanitize_paygcards_secret($);
sub sanitize_phone_number($);
sub sanitize_plaintext_ip_address($);
sub sanitize_plaintext_password($);
sub sanitize_string($);
sub sanitize_user_id($);
sub sanitize_user_password($);
sub sanitize_zero($);


#
# File-handling prototypes: operations to open/close SQL files and write SQL data.
#
sub sql_close($);
sub sql_open($);
sub sql_write($$);


#
# Sanitization filter configuration.  Assign general sanitization filters to column
# types and specific sanitization filters to column names.  These assignments control
# how data is mangled (or cleanly passed through) from the target database into the
# generated SQL files.
#
# Column Name Sanitizer Format: <database name>_<table name>_<column name>
# Column Type Sanitizer Format: <column type>
#
my %column_name_sanitizers = (
	articles_articles_author => 'pass-through',
	articles_articles_title => 'pass-through',
	articles_articles_text => 'pass-through',
	articles_cats_name => 'pass-through',
	articles_commentstext_msg => 'pass-through',
	articles_commentstext_nmsg => 'pass-through',
	banners_bannercampaigns_title => 'pass-through',
	banners_bannercampaigns_age => 'pass-through',
	banners_bannercampaigns_sex => 'pass-through',
	banners_bannercampaigns_loc => 'pass-through',
	banners_bannercampaigns_page => 'pass-through',
	banners_bannercampaigns_interests => 'pass-through',
	banners_bannercampaigns_allowedtimes => 'pass-through',
	banners_bannerclients_loginid => \&sanitize_plaintext_password,
	banners_bannerclients_loginpassword => \&sanitize_plaintext_password,
	banners_banners_age => 'pass-through',
	banners_banners_sex => 'pass-through',
	banners_banners_loc => 'pass-through',
	banners_banners_page => 'pass-through',
	banners_banners_interests => 'pass-through',
	banners_banners_allowedtimes => 'pass-through',
	banners_banners_title => 'pass-through',
	banners_banners_image => 'pass-through',
	banners_banners_link => 'pass-through',
	banners_banners_alt => 'pass-through',
	banners_bannertypestats_viewsdump => 'pass-through',
	banners_bannertypestats_clicksdump => 'pass-through',
	config_interests_name => 'pass-through',
	config_locs_name => 'pass-through',
	config_locs_slugline => 'pass-through',
	config_schools_name => 'pass-through',
	config_schools_slugline => 'pass-through',
	contest_contests_name => 'pass-through',
	contest_contests_content => 'pass-through',
	contest_contests_final => 'pass-through',
	contest_firstvote_ip => \&sanitize_ip_address,
	contest_quizentries_ipaddr => \&sanitize_ip_address,
	contest_quizentries_email => \&sanitize_email_address,
	contest_quizentries_data => \&sanitize_nullify,
	contest_quizfields_question => 'pass-through',
	contest_quizoptions_option => 'pass-through',
	contest_quizzes_title => 'pass-through',
	contest_quizzes_starttext => 'pass-through',
	contest_quizzes_endtext => 'pass-through',
	contest_secondvote_ip => \&sanitize_ip_address,
	contest_skins_filename => 'pass-through',
	contest_skins_siteskin => 'pass-through',
	fileupdates_fileservers_server => 'pass-through',
	fileupdates_fileupdates_file => 'pass-through',
	fileupdates_fileupdates_server => 'pass-through',
	forum_forumcats_name => 'pass-through',
	forum_forumranks_name => 'pass-through',
	forum_forumrankspending_forumrank => 'pass-through',
	forum_forums_name => 'pass-through',
	general_bannedusers_banned => \&sanitize_email_address,
	general_bannedwords_word => 'pass-through',
	general_blocks_funcname => 'pass-through',
	general_config_name => 'pass-through',
	general_config_value => 'pass-through',
	general_config_comments => 'pass-through',
	general_deletedusers_username => 'pass-through',
	general_deletedusers_ip => \&sanitize_ip_address,
	general_deletedusers_email => \&sanitize_email_address,
	general_email_optout_email => \&sanitize_email_address,
	general_faq_title => 'pass-through',
	general_faq_text => 'pass-through',
	general_faqcats_name => 'pass-through',
	general_files_location => 'pass-through',
	general_games_name => 'pass-through',
	general_games_description => 'pass-through',
	general_games_slugline => 'pass-through',
	general_games_thumb => 'pass-through',
	general_games_bans_slugline => 'pass-through',
	general_games_categories_slugline => 'pass-through',
	general_games_categories_name => 'pass-through',
	general_games_comments_comment => 'pass-through',
	general_invites_name => 'pass-through',
	general_invites_email => \&sanitize_email_address,
	general_keymap_phpkey => 'pass-through',
	general_keymap_rubykey => 'pass-through',
	general_mirrors_cookie => 'pass-through',
	general_mirrors_domain => 'pass-through',
	general_mirrors_status => 'pass-through',
	general_newestprofile_username => 'pass-through',
	general_newestusers_username => 'pass-through',
	general_news_title => 'pass-through',
	general_news_text => 'pass-through',
	general_news_ntext => 'pass-through',
	general_newusertasks_description => 'pass-through',
	general_police_dumpuserid => \&sanitize_user_id,
	general_police_email => \&sanitize_email_address,
	general_profileskins_name => 'pass-through',
	general_profileskins_data => 'pass-through',
	general_smilies_code => 'pass-through',
	general_smilies_pic => 'pass-through',
	general_staticpages_name => 'pass-through',
	general_staticpages_content => 'pass-through',
	general_todo_title => 'pass-through',
	general_todo_description => 'pass-through',
	general_typeid_typename => 'pass-through',
	master_metriclookup_description => 'pass-through',
	master_user_mobiles_number => \&sanitize_phone_number,
	master_useremails_email => \&sanitize_email_address,
	master_usernames_username => 'pass-through',
	mods_abuselogcomments_username => 'pass-through',
	mods_admin_title => 'pass-through',
	mods_adminlog_ip => \&sanitize_ip_address,
	mods_adminlog_page => 'pass-through',
	mods_adminlog_action => 'pass-through',
	mods_adminroles_rolename => 'pass-through',
	mods_adminroles_title => 'pass-through',
	mods_globalpicbans_md5 => 'pass-through',
	mods_privilegenames_name => 'pass-through',
	polls_pollans_answer => 'pass-through',
	polls_pollcommentstext_msg => 'pass-through',
	polls_pollcommentstext_nmsg => 'pass-through',
	polls_polls_question => 'pass-through',
	polls_pollvotes_ip => \&sanitize_ip_address,
	shop_billingpeople_action => 'pass-through',
	shop_billingpeople_maid => 'pass-through',
	shop_billingpeople_amount => 'pass-through',
	shop_billingpeople_customerid => 'pass-through',
	shop_billingpeople_date => 'pass-through',
	shop_billingpeople_time => 'pass-through',
	shop_billingpeople_mid => 'pass-through',
	shop_billingpeople_status => 'pass-through',
	shop_billingpeople_email => \&sanitize_email_address,
	shop_billingpeople_custom => 'pass-through',
	shop_billingpeople_ip => \&sanitize_plaintext_ip_address,
	shop_billingpeople_paymenttype => 'pass-through',
	shop_billingpeople_score => 'pass-through',
	shop_invoice_paymentcontact => 'pass-through',
	shop_invoiceitems_input => 'pass-through',
	shop_paygbatches_storeinvoiceid => 'pass-through',
	shop_paygcards_secret => \&sanitize_paygcards_secret,
	shop_productcats_name => 'pass-through',
	shop_products_name => 'pass-through',
	shop_products_inputname => 'pass-through',
	shop_products_validinput => 'pass-through',
	shop_products_callback => 'pass-through',
	shop_products_stock => 'pass-through',
	shop_producttext_summary => 'pass-through',
	shop_producttext_description => 'pass-through',
	shop_producttext_ndescription => 'pass-through',
	shop_shoppingcart_input => 'pass-through',
	streams_bandentries_name => 'pass-through',
	streams_bandentries_bio => 'pass-through',
	streams_bandentries_uri => 'pass-through',
	streams_bandentries_genre => 'pass-through',
	streams_musicchannelgroups_name => 'pass-through',
	streams_musicchannels_title => 'pass-through',
	streams_musicchannels_header => 'pass-through',
	streams_musicdisplaystreams_tagwords => 'pass-through',
	streams_musicdisplaystreams_title => 'pass-through',
	streams_musicfeatures_body => 'pass-through',
	streams_musicnews_title => 'pass-through',
	streams_musicnews_body => 'pass-through',
	streams_musicnews_brief => 'pass-through',
	streams_musicsidebarfeatures_content => 'pass-through',
	streams_musicsidebarfeatures_link => 'pass-through',
	streams_streamicons_thumbnail => 'pass-through',
	streams_streamicons_image => 'pass-through',
	streams_streamtags_tagname => 'pass-through',
	streams_streamtags_displaytitle => 'pass-through',
	userdb_archive_ip => \&sanitize_ip_address,
	userdb_emailinvites_email => \&sanitize_email_address,
	userdb_emailsearches_contacts => \&sanitize_nullify,
	userdb_gallerycomments_authorip => \&sanitize_ip_address,
	userdb_gallerypending_md5 => 'pass-through',
	userdb_gallerypics_md5 => 'pass-through',
	userdb_loginlog_ip => \&sanitize_ip_address,
	userdb_msgs_toname => 'pass-through',
	userdb_msgs_fromname => 'pass-through',
	userdb_msgs_sentip => \&sanitize_ip_address,
	userdb_picbans_md5 => 'pass-through',
	userdb_pics_description => 'pass-through',
	userdb_picspending_md5 => 'pass-through',
	userdb_profile_icq => \&sanitize_string,
	userdb_profile_yahoo => \&sanitize_email_address,
	userdb_profile_msn => \&sanitize_email_address,
	userdb_profile_aim => \&sanitize_email_address,
	userdb_profile_tagline => 'pass-through',
	userdb_profile_ntagline => 'pass-through',
	userdb_profile_signiture => 'pass-through',
	userdb_profile_nsigniture => 'pass-through',
	userdb_profile_profile => 'pass-through',
	userdb_profiledisplayblocks_path => 'pass-through',
	userdb_sessions_ip => \&sanitize_ip_address,
	userdb_sessions_sessionid => \&sanitize_nullify,
	userdb_shouts_shout => 'pass-through',
	userdb_useractivetime_ip => \&sanitize_ip_address,
	userdb_usercomments_authorip => \&sanitize_ip_address,
	userdb_userhitlog_ip => \&sanitize_ip_address,
	userdb_usernames_username => 'pass-through',
	userdb_userpasswords_password => \&sanitize_user_password,
	userdb_users_ip => \&sanitize_ip_address,
	userdb_users_forumrank => 'pass-through',
	userdb_users_school_id => \&sanitize_zero,
	userdb_users_skin => 'pass-through',
	userdb_userskins_name => 'pass-through',
	userdb_userskins_skindata => 'pass-through',
	wiki_wikipagedata_name => 'pass-through',
	wiki_wikipagedata_changedesc => 'pass-through',
	wiki_wikipagedata_content => 'pass-through',
	wiki_wikipagedata_comment => 'pass-through',
	wiki_wikipages_name => 'pass-through'
);
my %column_type_sanitizers = (
	bigint => 'pass-through',
	blob => \&sanitize_string,
	char => \&sanitize_string,
	date => 'pass-through',
	decimal => 'pass-through',
	double => 'pass-through',
	enum => 'pass-through',
	float => 'pass-through',
	int => 'pass-through',
	longblob => \&sanitize_string,
	longtext => \&sanitize_string,
	mediumint => 'pass-through',
	mediumblob => \&sanitize_string,
	mediumtext => \&sanitize_string,
	smallint => 'pass-through',
	text => \&sanitize_string,
	tinyint => 'pass-through',
	varchar => \&sanitize_string
);


#
# Ignore insertion error configuration.  Assigning a database/table combination a true
# value in this hash will cause each INSERT to that database/table combination to be an
# 'INSERT IGNORE'. This should be used when part of a unique key to that table is
# generated by this script, as the generated data may be symmetrical in two different
# rows and thus cause unique key conflicts on insert.
#
my %ignore_insertion_errors = (
	userdb_userhitlog => 1
);


my $compress = 0;
my @dbspecs = ();
my $help_requested = 0;
my $hostname = '127.0.0.1';
my $password = undef;
my $port = 3306;
my $username = undef;


#
# Seed $hostname, $username, $password and $port from ~/.my.cnf, if possible.
#
if (-e $ENV{'HOME'} . '/.my.cnf' && -f _ && -r _)
{
	my $cfg = new Config::IniFiles( -file => $ENV{'HOME'} . '/.my.cnf' );
	if ($cfg->val('mysql', 'host'))
	{
		$hostname = $cfg->val('mysql', 'host');
		$hostname =~ s/^\s+|\s+$//;
	}
	if ($cfg->val('mysql', 'password'))
	{
		$password = $cfg->val('mysql', 'password');
		$password =~ s/^\s+|\s+$//;
	}
	if ($cfg->val('mysql', 'port'))
	{
		$port = $cfg->val('mysql', 'port');
		$port =~ s/^\s+|\s+$//;
	}
	if ($cfg->val('mysql', 'user'))
	{
		$username = $cfg->val('mysql', 'user');
		$username =~ s/^\s+|\s+$//;
	}
}


#
# Deal with command-line arguments.
#
GetOptions
(
	'compress' => \$compress,
	'dbspec=s' => \@dbspecs,
	'help' => \$help_requested,
	'hostname=s' => \$hostname,
	'password=s' => \$password,
	'port=i' => \$port,
	'username=s' => \$username
) or $help_requested = -1;

if (($help_requested) or (! $hostname) or (! @dbspecs))
{
	print "Usage: $0 --hostname=HOST --dbspec=DATABASE\n";
	print "\n";
	print "Options:\n";
	print "\t--compress          Use bzip2 to compress the generated SQL files.\n";
	print "\t                    The default is to leave the generated SQL files uncompressed.\n";
	print "\t--dbspec=DATABASE   Fetch and sanitize all of the data from DATABASE.  This can also\n";
	print "\t                    be DATABASE.TABLE, in which case only data from the TABLE table of DATABASE\n";
	print "\t                    will be returned.\n";
	print "\t                    If the first character of DATABASE is '^', then only structure will be output\n";
	print "\t                    for items matching this dbspec, data will not be dumped.\n";
	print "\t                    Multiple 'dbspec' options are possible.\n";
	print "\t--hostname=HOSTNAME Use HOSTNAME as the host to connect to.\n";
	print "\t                    Read from ~/.my.cnf if possible, otherwise defaults to '127.0.0.1'.\n";
	print "\t--password=PASSWORD Use PASSWORD to connect to USERNAME on HOSTNAME.\n";
	print "\t                    Read from ~/.my.cnf if possible, otherwise defaults to no password.\n";
	print "\t--port=PORT         Port number to use when connecting to the host.\n";
	print "\t                    Read from ~/.my.cnf if possible, otherwise defaults to '3306'.\n";
	print "\t--username=USER     Use USER to connect to DATABASE on HOSTNAME.\n";
	print "\t                    Read from ~/.my.cnf if possible, otherwise defaults to no username.\n";
	exit 0 if ($help_requested > 0);
	exit -1;
}


#
# Setup and configure our logging output.
#
my $logger = Log::Log4perl->get_logger;
$logger->level($DEBUG);
{
	my $Screen_Layout = Log::Log4perl::Layout::PatternLayout->new('%d [%p] %F:%L %m%n');
	my $Syslog_Layout = Log::Log4perl::Layout::PatternLayout->new('[%L/%p] %m%n');

	my $Screen_Err = Log::Log4perl::Appender->new(
		'Log::Log4perl::Appender::Screen',
		name => 'Screen_Err',
		stderr => 1
	);
	$Screen_Err->layout($Screen_Layout);
	$Screen_Err->threshold($WARN);
	$logger->add_appender($Screen_Err);

	my $Syslog = Log::Log4perl::Appender->new(
		'Log::Dispatch::Syslog',
		facility => 'user',
		ident => basename($0),
		logopt => 'nofatal',
		name => 'Syslog'
	);
	$Syslog->layout($Syslog_Layout);
	$Syslog->threshold($INFO);
	$logger->add_appender($Syslog);
}


#
# Use @dbspecs list to generate a complete list of databases/tables to sanitize.  Save this complete list into
# the %dbspec hash.
#
my %dbspec = ();
foreach (@dbspecs)
{
	my $structure = 0;
	if (substr($_, 0, 1) eq '^')
	{
		$structure = 1;
		$_ = substr($_, 1);
	}
	my ($database, $table) = split(/[.]/);

	if (! $dbspec{$database})
	{
		$dbspec{$database} = {};
	}
	if ($table)
	{
		if ($structure)
		{
			if (! defined $dbspec{$database}->{$table})
			{
				$dbspec{$database}->{$table} = 'structure';
			}
		}
		else
		{
			$dbspec{$database}->{$table} = 'data';
		}
	}
	else
	{
		my $dbh = DBI->connect('dbi:mysql:' . join(':', $database, $hostname, $port), $username, $password, { PrintError => 0 });
		if (! $dbh)
		{
			$logger->error('Could not connect to ' . $hostname . ':' .$port . ' '. $DBI::errstr);
			die;
		}
		my $sth = $dbh->prepare('SHOW TABLE STATUS');
		if (! $sth)
		{
			$logger->error('Could not prepare statement: ' . $dbh->errstr);
			die;
		}
		if (! $sth->execute())
		{
			$logger->error('Could not execute statement: ' . $sth->errstr);
			die;
		}
		while (my $row = $sth->fetchrow_hashref())
		{
			if ($structure)
			{
				if (! defined $dbspec{$database}->{$row->{'Name'}})
				{
					$dbspec{$database}->{$row->{'Name'}} = 'structure';
				}
			}
			else
			{
				$dbspec{$database}->{$row->{'Name'}} = 'data';
			}
		}
		$sth->finish();
		$dbh->disconnect();
	}
}


foreach my $database (keys %dbspec)
{
	if (! -e $database)
	{
		if (! mkdir $database)
		{
			$logger->error('Could not create directory ' . $database . ': ' . $!);
			die;
		}
	}
	my $database_tag = $database;
	$database_tag =~ s/_beta$//;
	$database_tag = 'userdb' if ($database_tag =~ /^userdb\d+_\d+$/);
	$database_tag = 'userdb' if ($database_tag eq 'usersanon');
	$logger->debug('Mapped database ' . $database . ' to database tag ' . $database_tag . '.');

	my $dbh = DBI->connect('dbi:mysql:' . join(':', $database, $hostname, $port), $username, $password, { PrintError => 0 });
	if (! $dbh)
	{
		$logger->error('Could not connect to ' . $hostname . ':' . $port . ' ' . $DBI::errstr);
		die;
	}

	$dbh->{'mysql_auto_reconnect'} = 1;      # Allow auto-reconnection if the MySQL server goes away for some reason.
	$dbh->{'mysql_use_result'} = 1;          # Do _not_ buffer result sets.
	$dbh->{'LongReadLen'} = 4 * 1024 * 1024; # We assume that the largest "long"/"blob" object that we are going to see is 4MB.
	$dbh->{'LongTruncOk'} = 0;               # Truncating "long"/"blob" objects is not allowed.

	my $fh = sql_open($database);
	sql_write($fh, '-- Database dump of `' . $database . '`.' . "\n");
	sql_write($fh, 'CREATE DATABASE IF NOT EXISTS ' . $dbh->quote_identifier($database) . ";\n");
	sql_close($fh);

	foreach my $table (keys %{$dbspec{$database}})
	{
		$fh = sql_open($database . '/' . $table);
		sql_write($fh, '-- Table dump of `' . $database . '`.`' . $table . '`.' . "\n");
		sql_write($fh, 'USE ' . $dbh->quote_identifier($database) . ";\n\n");

		my $table_tag = $table;
		$table_tag = 'archive' if ($table_tag =~ /^archive\d{6}$/);
		$logger->debug('Mapped table ' . $table . ' to table tag ' . $table_tag . '.');

		#
		# Gather column names and types for the columns in the current $database.$table.
		#
		my @column_names = ();
		my @column_types = ();
		{
			my $sth = $dbh->prepare('DESCRIBE ' . $dbh->quote_identifier($table));
			if (! $sth)
			{
				$logger->error('Could not prepare statement: ' . $dbh->errstr);
				die;
			}
			if (! $sth->execute())
			{
				$logger->error('Could not execute statement: ' . $sth->errstr);
				die;
			}
			while (my $row = $sth->fetchrow_hashref())
			{
				$row->{'Type'} =~ s/\W.*//;
				push(@column_names, $row->{'Field'});
				push(@column_types, $row->{'Type'});
			}
			$sth->finish();
		}

		#
		# Fetch the CREATE statement for $database.$table and then write it out to our data stream.
		#
		{
			my $sth = $dbh->prepare('SHOW CREATE TABLE ' . $dbh->quote_identifier($table));
			if (! $sth)
			{
				$logger->error('Could not prepare statement: ' . $dbh->errstr);
				die;
			}
			if (! $sth->execute())
			{
				$logger->error('Could not execute statement: ' . $sth->errstr);
				die;
			}
			while (my $row = $sth->fetchrow_hashref())
			{
				sql_write($fh, $row->{'Create Table'} . ";\n\n");
			}
			$sth->finish();
		}

		#
		# Fetch all of the rows in $database.$table, sanitize them (if necessary), and then write out the necessary INSERT statements.
		#
		if ($dbspec{$database}->{$table} eq 'data')
		{
			my $sanitization_start_time = time();
			$logger->info('Beginning data sanitization of ' . $database . '.' . $table);

			my $insert_sql_stmt_prefix = undef;
			if ($ignore_insertion_errors{join('_', $database_tag, $table_tag)})
			{
				$insert_sql_stmt_prefix = 'INSERT IGNORE INTO ';
			}
			else
			{
				$insert_sql_stmt_prefix = 'INSERT INTO ';
			}

			my $sth = $dbh->prepare('SELECT * FROM ' . $dbh->quote_identifier($table));
			if (! $sth)
			{
				$logger->error('Could not prepare statement: ' . $dbh->errstr);
				die;
			}
			if (! $sth->execute())
			{
				$logger->error('Could not execute statement: ' . $sth->errstr);
				die;
			}
			sql_write($fh, 'ALTER TABLE ' . $dbh->quote_identifier($table) . " DISABLE KEYS;\n");
			my @row_sanitizers = ();
			my $row_count = 0;
			while (my $row = $sth->fetchrow_arrayref())
			{
				if (! @row_sanitizers)
				{
					# Build (and cache) an array of sanitizers to be used for this table.
					for (my $i = 0; $i <= $#{$row}; $i++)
					{
						my $j = join('_', $database_tag, $table_tag, $column_names[$i]);
						if ($column_name_sanitizers{$j} && (ref $column_name_sanitizers{$j}))
						{
							$logger->info('    Using column name sanitizer for column "' . $j . '"');
							push(@row_sanitizers, $column_name_sanitizers{$j});
						}
						elsif ($column_name_sanitizers{$j} && ($column_name_sanitizers{$j} eq 'pass-through'))
						{
							$logger->info('    Using pass-through for column name "' . $j . '"');
							push(@row_sanitizers, undef);
						}
						elsif ($column_type_sanitizers{$column_types[$i]} && (ref $column_type_sanitizers{$column_types[$i]}))
						{
							$logger->info('    Using column type sanitizer for column "' . $j . '"');
							push(@row_sanitizers, $column_type_sanitizers{$column_types[$i]});
						}
						elsif ($column_type_sanitizers{$column_types[$i]} && ($column_type_sanitizers{$column_types[$i]} eq 'pass-through'))
						{
							$logger->info('    Using pass-through for column type "' . $j . '"');
							push(@row_sanitizers, undef);
						}
						else
						{
							$logger->error('    Do not know how to sanitize field type ' . $column_types[$i] . ', nullifying.');
							push(@row_sanitizers, &sanitize_nullify);
						}
					}
				}
				for (my $i = 0; $i <= $#{$row}; $i++)
				{
					if (defined $row_sanitizers[$i])
					{
						$row->[$i] = $row_sanitizers[$i]->($row->[$i]);
					}
				}
				$row_count++;
				sql_write($fh, $insert_sql_stmt_prefix . $dbh->quote_identifier($table) . ' VALUES (' . join(', ', map { $dbh->quote($_); } @{$row}) . ");\n");
			}
			sql_write($fh, 'ALTER TABLE ' . $dbh->quote_identifier($table) . " ENABLE KEYS;\n");
			$sth->finish();

			$logger->info('Completed data sanitization of ' . $database . '.' . $table . ' (' . $row_count . ' rows) in ' . (time() - $sanitization_start_time) . ' seconds.');
		}
		else
		{
			sql_write($fh, "-- Table dump flagged as structure only.  No data dumped.\n\n");
		}
		sql_close($fh);
	}
	$dbh->disconnect();
}


#
# Replace the incoming data with dev-null+HASH@nexopia.com.
#
sub sanitize_email_address($)
{
	my $data = shift;
	if (! defined $data)
	{
		return $data;
	}
	return 'dev-null+' . md5_hex('data_sanitizer.pl salt:JshdU23klA1`@54sq', $data) . '@nexopia.com';
}


#
# Replace the incoming data with a random IP on the 127.x.x.x class A sub-net, unless it is '0', in which
# case we leave it alone.
#
sub sanitize_ip_address($)
{
	my $data = shift;
	if ((! defined $data) || ($data == 0))
	{
		return $data;
	}
	my $ip = 127 << 24;
	$ip = $ip | (int(rand(256)) << 16);
	$ip = $ip | (int(rand(256)) << 8);
	$ip = $ip | int(rand(256));
	return $ip;
}


#
# Replace the incoming data with an empty string.
#
sub sanitize_nullify($)
{
	my $data = shift;
	if (! defined $data)
	{
		return $data;
	}
	return '';
}


#
# Replace the incoming paygcards secret code with a randomly unique one.
#
BEGIN
{
	my $secret_character = 65;
	my @secret_numbers = (0, 0, 0);

	sub sanitize_paygcards_secret($)
	{
		my $data = shift;
		if (! defined $data)
		{
			return $data;
		}

		my $secret = sprintf
		(
			'%s%03d-%s%03d-%s%03d',
			chr($secret_character), $secret_numbers[0],
			chr($secret_character), $secret_numbers[1],
			chr($secret_character), $secret_numbers[2]
		);

		$secret_numbers[2]++;
		if ($secret_numbers[2] > 999)
		{
			$secret_numbers[2] = 0;
			$secret_numbers[1]++;
			if ($secret_numbers[1] > 999)
			{
				$secret_numbers[1] = 0;
				$secret_numbers[0]++;
				if ($secret_numbers[0] > 999)
				{
					$secret_numbers[0] = 0;
					$secret_character++;
				}
			}
		}
		return $secret;
	}
}


#
# Replace the incoming phone number with a randomly unique one.
#
BEGIN
{
	my $phone_number = 0;
	
	sub sanitize_phone_number($)
	{
		my $data = shift;
		if (! defined $data)
		{
			return $data;
		}
		
		$phone_number++;
		$data = sprintf('%10d', $phone_number);
		
		return $data;
	}
}


#
# Replace the incoming data with a random IP on the 127.x.x.x class A sub-net,
#
sub sanitize_plaintext_ip_address($)
{
	my $data = shift;
	if (! defined $data)
	{
		return $data;
	}

	my $ip = '127.';
	$ip .= int(rand(256)) . '.';
	$ip .= int(rand(256)) . '.';
	$ip .= int(rand(256));
	return $ip;
}


#
# Replace the incoming data with completely random alphanumeric data of the same length
# if the password is more than 8 characters in length, or of 8 characters in length if
# the password is shorter than that.
#
BEGIN
{
	my @character_set = ('a' .. 'z', 'A' .. 'Z', '0' .. '9');

	sub sanitize_plaintext_password($)
	{
		my $data = shift;
		if (! defined $data)
		{
			return $data;
		}
		my $len = length($data);
		if ($len < 8)
		{
			$len = 8;
		}

		my $generated_password = '';
		for (my $i = 0; $i < $len; $i++)
		{
			$generated_password .= $character_set[rand @character_set];
		}
		return $generated_password;
	}
}


#
# Replace the incoming data with 'similar' random data.
#
sub sanitize_string($)
{
	my $data = shift;
	if (! defined $data)
	{
		return $data;
	}
	my @chars = split(//, $data);
	for (my $i = 0; $i <= $#chars; $i++)
	{
		my $j = ord($chars[$i]);

		if (($j >= 123) && ($j <= 126))
		{
			$chars[$i] = chr(int(rand(126 - 123 + 1)) + 123);
		}
		elsif (($j >= 97) && ($j <= 122))
		{
			$chars[$i] = chr(int(rand(122 - 97 + 1)) + 97);
		}
		elsif (($j >= 91) && ($j <= 96))
		{
			$chars[$i] = chr(int(rand(96 - 91 + 1)) + 91);
		}
		elsif (($j >= 65) && ($j <= 90))
		{
			$chars[$i] = chr(int(rand(90 - 65 + 1)) + 65);
		}
		elsif (($j >= 58) && ($j <= 64))
		{
			$chars[$i] = chr(int(rand(64 - 58 + 1)) + 58);
		}
		elsif (($j >= 48) && ($j <= 57))
		{
			$chars[$i] = chr(int(rand(57 - 48 + 1)) + 48);
		}
		elsif (($j >= 33) && ($j <= 47))
		{
			$chars[$i] = chr(int(rand(47 - 33 + 1)) + 33);
		}
	}
	return join('', @chars);
}


#
# Replace any user id number with a random user id number.
#
sub sanitize_user_id($)
{
	my $maximum_uid = 3564778;
	my $uid = rand($maximum_uid) + 1;
	return $uid;
}


#
# Replace any user password with the hash for the password 'secret'.
#
sub sanitize_user_password($)
{
	my $data = shift;
	if (! defined $data)
	{
		return $data;
	}

	return '8f9db6f1dba404fbb3eb7a98c2d56fa0';
}


#
# Replace the incoming data with zero.
#
sub sanitize_zero($)
{
	my $data = shift;
	if (! defined $data)
	{
		return $data;
	}
	return 0;
}


#
# Close the file handle that is passed in.
#
sub sql_close($)
{
	my $fh = shift;

	sql_write($fh, '-- File closed ' . localtime(time()) . ".\n");
	if (! $compress)
	{
		if (close $fh)
		{
			return 1;
		}
		$logger->error('Error closing uncompressed SQL file: ' . $!);
		die;
	}
	my $rv = $fh->bzclose();
	if ($rv != BZ_OK)
	{
		$logger->error('Error closing compressed SQL file: ' . $bzerrno);
		die;
	}
	return 1;
}


#
# Open the file path that is passed in (after appending the proper extension, based
# on the $compress flag) and return it.
#
sub sql_open($)
{
	my $filename_root = shift;

	if (! $compress)
	{
		local *FH;
		if (open(FH, '>' . $filename_root . '.sql'))
		{
			sql_write(*FH, '-- File opened ' . localtime(time()) . ".\n");
			return *FH;
		}
		$logger->error('Error opening uncompressed SQL file: ' . $!);
		die;
	}
	my $bz = bzopen($filename_root . '.sql.bz2', 'wb');
	if ($bz)
	{
		sql_write($bz, '-- File opened ' . localtime(time()) . ".\n");
		return $bz;
	}
	$logger->error('Error opening compressed SQL file: ' . $bzerrno);
	die;
}


#
# Ensure that the given data is written successfully to the given filehandle,
# and honor the $compress flag correctly.
#
sub sql_write($$)
{
	my $fh = shift;
	my $data = shift;

	if (! $compress)
	{
		if (! print $fh $data)
		{
			$logger->error('Could not write to uncompressed SQL file: ' . $!);
			die;
		}
		return 1;
	}
	if ($fh->bzwrite($data) != length($data))
	{
		$logger->error('Could not write to compressed SQL file: ' . $fh->bzerror());
		die;
	}
	return 1;
}
