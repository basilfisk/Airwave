#!/usr/bin/perl
# *********************************************************************************************
# *********************************************************************************************
#
#  Load event data from CSV files into Portal database
#
#  There is one file for each site.
#
# *********************************************************************************************
# *********************************************************************************************

# Establish the root directory
our $ROOT;
BEGIN {
	$ROOT = '/srv/visualsaas/instances/aa002/bin';
}

# Declare modules
use strict;
use warnings;

# System modules
use Data::Dumper;
use Getopt::Long;

# Breato modules
use lib "$ROOT";
use mods::API qw(apiDML apiData apiSelect apiStatus);
use mods::Common qw(formatDateTime logMsg logMsgPortal parseDocument readConfig);

# Program information
our $PROGRAM = "load_events_techlive.pl";
our $VERSION = "2.0";

# Check there are any arguments
if($#ARGV == -1) { usage(); }

# Read command line options
our $LOG		= 0;
our $LOAD		= 0;
our $SITECODE	='all';
our $YYMM		= 'empty';
GetOptions (
	'log'		=> \$LOG,
	'load'		=> \$LOAD,
	's|site=s'	=> \$SITECODE,
	'yymm=s'	=> \$YYMM,
	'help'		=> sub { usage(); } );

# Check that period argument is present and valid
if($YYMM eq 'empty') { usage(1); }

# Read the configuration parameters
our %CONFIG  = readConfig("$ROOT/etc/airwave-portal.conf");

# Define date related variables
our $CCYY = "20".substr($YYMM,0,2);
our @MONTHS = ('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec');

# Directory in which events are created on the local server
our $EVENT_DIR = "$ROOT/../$CONFIG{PORTAL_STATS}/Techlive/$CCYY/$YYMM";

# Open the database connection and start processing
main();





# =============================================================================================
# =============================================================================================
#
# PROCESSING FUNCTIONS
#
# =============================================================================================
# =============================================================================================
sub main {
	# Initialise local variables
	my(%films,%refunds,%alias,%currencies,@files,$file,$site,%data,$uid,$key,$filename,$fh,$siterefunds,$refunded,$line,@flds,$currency,$charge,$datetime,$date,$time,$d,$t,$y,$m,$h,$i,$techlive,$filmname,$filmcode,$id,$classic,%unknown,@keys);
	my($status,$msg,%error);
	
	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");
	logMsg($LOG,$PROGRAM,"Loading Events to the Portal for period '$YYMM'");
	
	# Stop if directory does not exist on server
	if(!-d $EVENT_DIR) {
		logMsgPortal($LOG,$PROGRAM,'E',"Invalid month requested. Directory does not exist");
		return;
	}

	# If all sites requested, read list of usage data files in directory
	if($SITECODE eq 'all') {
		@files = `ls $EVENT_DIR | grep events`;
	}
	# If one site requested, check file exists
	else {
		$file = $SITECODE.'_events.csv';
		if(-f "$EVENT_DIR/$file") {
			push(@files,$file);
		}
		else {
			logMsgPortal($LOG,$PROGRAM,'E',"No data file for [$SITECODE] found");
			return;
		}
	}

	# Read all films
	# Key: Techlive film ref
	# [0]: Film name
	# [1]: Film code
	# [2]: Film ID
	# [3]: Classic (y/n)
	($msg) = apiSelect('createEventTechliveFilms');
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"Error reading films from database");
		return;
	}
	%films = apiData($msg);
	
	# Read list of refunds
	($msg) = apiSelect('uipTechliveRefund',"month=$YYMM");
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"No Techlive refunds found on database for $YYMM");
	}
	%refunds = apiData($msg);
	
	# Read list of aliases
	# Key: Unrecognised ID
	# Value: Valid Techlive ID
	($msg) = apiSelect('uipTechliveAliases');
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"No Techlive aliases found on database");
	}
	%alias = apiData($msg);
	
	# Read valid currency codes
	($msg) = apiSelect('uipTechliveCurrency');
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"Error reading currency codes from database");
		return;
	}
	%currencies = apiData($msg);
	
	# For each site, process the event and asset records
	foreach my $file (@files) {
		chomp $file;
		($site) = split(/\./,$file);
		$site =~ s/_events//;
		%data = ();
		$key = 0;
		$uid = "$YYMM/$file";
		logMsg($LOG,$PROGRAM,"Site: $site");
		
		# Read the site data
		# {techlive film ref},{DD/MM/YYYY HH24:MI},{amount},{currency}
		$filename = "$EVENT_DIR/$file";
		open($fh,"<$filename") or die "Unable to open file [$filename]: $!";
		$siterefunds = ($refunds{$site}) ? $refunds{$site}{quantity} : 0;
		$refunded = 1;
		RECORD: while($line = readline($fh)) {
			chomp $line;
			@flds = split(',',$line);
			
			# Check the currency code is registered on the Portal
			if(@flds ne 4) {
				logMsgPortal($LOG,$PROGRAM,'E',"$uid: Record must have 4 fields {techlive film ref},{DD/MM/YYYY HH24:MI},{amount},{currency}");
				next RECORD;
			}
			
			# Extract currency, force to lower case, and convert STG to GBP
			$currency = pop(@flds);
			$currency =~ s/\s+//g;
			$currency =~ tr[A-Z][a-z];
			$currency = ($currency eq 'stg') ? 'gbp' : $currency;
			
			# Check the currency code is registered on the Portal
			if(!$currencies{$currency}) {
				logMsgPortal($LOG,$PROGRAM,'E',"$uid: Unrecognised currency [$currency]");
				next RECORD;
			}
			
			# Extract the charge, change null charges to 0, convert to pence/cents
			$charge = pop(@flds);
			$charge = ($charge) ? $charge : 0;
			$charge = int(100*$charge);
			
			# Extract the date/time and convert date from 'DD/MM/YYYY HH24:MI:SS' to 'DD Mon YYYY HH24:MI'
			$datetime = pop(@flds);
			($date,$time) = split(/ /,$datetime);
			if(!($date && $time)) {
				logMsgPortal($LOG,$PROGRAM,'E',"$uid: Date/time format should be 'DD/MM/YYYY HH24:MI' not [$datetime]");
				next RECORD;
			}
			
			# Extract day, month and year
			($d,$m,$y) = split(/\//,$date);
			if(!($d && $m && $y)) {
				logMsgPortal($LOG,$PROGRAM,'E',"$uid: Date format should be 'DD/MM/YYYY' not [$date]");
				next RECORD;
			}
			
			# Extract hour and minute
			($h,$i) = split(/:/,$time);
			if(!($h && $i)) {
				logMsgPortal($LOG,$PROGRAM,'E',"$uid: Time format should be 'HH24:MI' not [$time]");
				next RECORD;
			}
			$datetime = "$d $MONTHS[$m-1] $y $h:$i";
			
			# Remaining element is the Techlive film reference
			$techlive = pop(@flds);
			
			# Use the Techlive ID from the record to find the matching content details from the Portal
			if($films{$techlive}) {
				$filmname = $films{$techlive}{title};
				$filmcode = $films{$techlive}{asset_code};
				$id = $films{$techlive}{content_id};
				$classic = $films{$techlive}{classic};
			}
			# No direct match on Portal, so check the aliases
			elsif($alias{$techlive}) {
				$id = $alias{$techlive}{alias};
				if($films{$id}) {
					$filmname = $films{$techlive}{title};
					$filmcode = $films{$techlive}{asset_code};
					$id = $films{$techlive}{content_id};
				}
			}
			# Ignore films whose code is set to zero
			elsif($techlive eq '0' || !$filmcode || $filmcode eq '0') {
				$filmcode = undef;
			}
			# No matches at all, so file away for logging at end of script
			else {
				$filmcode = undef;
				$unknown{$techlive} = $techlive;
				logMsgPortal($LOG,$PROGRAM,'E',"$uid: Unrecognised film code [$techlive]");
				next RECORD;
			}
			
			# Add known films to hash for uploading
			if($filmcode) {
				# Skip first N non-classic films as they are allocated as refunds
				if($classic eq 'y' || $refunded > $siterefunds) {
					$key++;
					$data{substr('0000'.$key,-5,5)} = [($site,$filmcode,$datetime,$charge,$currency)];
				}
				else {
					logMsgPortal($LOG,$PROGRAM,'E',"$uid: Refund [$refunded] skipping film [$filmcode]");
					$refunded++;
				}
			}
		}
		
		# Load all films for the site
		if($LOAD) {
			foreach my $key (sort keys %data) {
				($site,$filmcode,$datetime,$charge,$currency) = @{$data{$key}};
				($msg) = apiDML('createEventTechlive',"site=$site","asset=$filmcode","start='$datetime'","charge=$charge","currency=$currency");
				($status,%error) = apiStatus($msg);
				if(!$status) {
					logMsgPortal($LOG,$PROGRAM,'E',"Event record not added: [$site][$filmcode][$datetime][$charge][$currency] [$error{CODE}] $error{MESSAGE}");
				}
			}
		}
	}
	
	# List unknown films
	@keys = sort keys %unknown;
	if(@keys) {
		logMsg($LOG,$PROGRAM,"List of Unknown Films");
		foreach my $key (@keys) {
			logMsg($LOG,$PROGRAM,"Techlive ID: $key");
		}
	}

	# Upload status message
	if($LOAD) {
		logMsg($LOG,$PROGRAM,"Data for '$YYMM' uploaded to Portal");
	}
	else {
		logMsg($LOG,$PROGRAM,"Data for '$YYMM' NOT uploaded to Portal");
	}
}



# ---------------------------------------------------------------------------------------------
# Program usage
#
# Argument 1 : Error number
# ---------------------------------------------------------------------------------------------
sub usage {
	my($err) = @_;
	$err = ($err) ? $err : 0;
	
	if($err == 1) {
		logMsgPortal($LOG,$PROGRAM,'E',"The 'yymm' argument must be present");
	}
	else {
		printf("
Program : $PROGRAM
Version : v$VERSION
Author  : Basil Fisk (c)2013 Airwave Ltd

Summary :
  Load the event data for Techlive sites from CSV files into the Portal database.
  There is one CSV file for each site.

Usage :
  $PROGRAM --yymm=<YYMM> --site=<name>
  
  MANDATORY
  --site=<name>		The site code or 'all'.
  --yymm=<YYMM>		The reporting month in YYMM format.
  
  OPTIONAL
  --load			If set, the usage files will be validated and the data will be
					uploaded to the Portal. If not set (default), the usage files will 
					be validated but the data will not be uploaded to the Portal.
  --log				If set, the results from the script will be written to the Airwave
					log directory, otherwise the results will be written to the screen.
		\n");
	}
	exit;
}

