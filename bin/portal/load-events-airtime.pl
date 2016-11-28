#!/usr/bin/perl
# *********************************************************************************************
# *********************************************************************************************
#
#  Load Airtimee event data from CSV files into Portal database
#
#  There is one XML file for each site
#
# *********************************************************************************************
# *********************************************************************************************

# Declare modules
use strict;
use warnings;

# System modules
use Data::Dumper;
use Getopt::Long;

# Breato modules
use lib "$ENV{'AIRWAVE_ROOT'}";
use mods::API3 qw(apiDML apiData apiStatus);
use mods::Common qw(formatDateTime logMsg logMsgPortal parseDocument readConfig);

# Program information
our $PROGRAM = "load-events-airtime.pl";
our $VERSION = "2.0";

# Check there are any arguments
if($#ARGV == -1) { usage(); }

# Read command line options
our $LOG		= 0;
our $SITECODE	='all';
our $YYMM		= 'empty';
GetOptions (
	'log'		=> \$LOG,
	's|site=s'	=> \$SITECODE,
	'yymm=s'	=> \$YYMM,
	'help'		=> sub { usage(); } );

# Check that period argument is present and valid
if($YYMM eq 'empty') { usage(1); }

# Read the configuration parameters
our %CONFIG  = readConfig("$ENV{'AIRWAVE_ROOT'}/etc/airwave.conf");

# Define date related variables
our $CCYY = "20".substr($YYMM,0,2);
our @MONTHS = ('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec');

# Directory in which events are created on the local server
our $EVENT_DIR = "$ENV{'AIRWAVE_ROOT'}/../$CONFIG{PORTAL_STATS}/Airtime/$CCYY/$YYMM";

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
	my(@files,$file,$site,$filename,$fh,$line,$asset,$start,$charge,$currency,$date,$time,$d,$m,$y,$h,$i);
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
		@files = `ls $EVENT_DIR`;
	}
	# If one site requested, check file exists
	else {
		$file = "$SITECODE.csv";
		if(-f "$EVENT_DIR/$file") {
			push(@files,$file);
		}
		else {
			logMsgPortal($LOG,$PROGRAM,'E',"No data file for [$SITECODE] found");
			return;
		}
	}

	# For each site, process the event and asset records
	foreach $file (@files) {
		chomp $file;
		($site) = split(/\./,$file);
		logMsg($LOG,$PROGRAM,"Site: $site");

		# Read the site data
		# {film code},{DD/MM/YYYY HH24:MI},{amount},{currency}
		$filename = "$EVENT_DIR/$file";
		open($fh,"<$filename") or die "Unable to open file [$filename]: $!";
		RECORD: while($line = readline($fh)) {
			chomp $line;
			($asset,$start,$charge,$currency) = split(',',$line);

			# Extract the date/time and convert date from 'DD/MM/YYYY HH24:MI:SS' to 'DD Mon YYYY HH24:MI'
#			($date,$time) = split(' ',$start);
			$date = substr($start, 0, 10);
			$time = substr($start, 11, 5);
			if(!($date && $time)) {
				logMsgPortal($LOG,$PROGRAM,'E',"$YYMM/$file: Date/time format should be 'DD/MM/YYYY HH24:MI' not [$start]");
				next RECORD;
			}

			# Extract day, month and year
			($d,$m,$y) = split(/\//,$date);
			if(!($d && $m && $y)) {
				logMsgPortal($LOG,$PROGRAM,'E',"$YYMM/$file: Date format should be 'DD/MM/YYYY' not [$date]");
				next RECORD;
			}

			# Extract hour and minute
			($h,$i) = split(/:/,$time);
			if(!($h && $i)) {
				logMsgPortal($LOG,$PROGRAM,'E',"$YYMM/$file: Time format should be 'HH24:MI' not [$time]");
				next RECORD;
			}
			$start = "$d $MONTHS[$m-1] $y $h:$i";

			# Change Null charges to 0
			$charge = ($charge) ? $charge : 0;
			$charge = int($charge);

			# Clean up currency and force to lower case
			$currency =~ s/\s+//g;
			$currency =~ tr[A-Z][a-z];

			# Insert a record
			($msg) = apiDML('createEventAirtime',"site=$site","asset=$asset","start=$start","charge=$charge","currency=$currency");
			($status,%error) = apiStatus($msg);
			if(!$status) {
				logMsgPortal($LOG,$PROGRAM,'E',"Event record not added: [$site][$asset][$start][$charge][$currency] [$error{CODE}] $error{MESSAGE}");
			}
		}
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
  Load the event data from XML files into the Portal database.
  There is one XML file for each site.

Usage :
  $PROGRAM --yymm=<YYMM> --site=<name>

  MANDATORY
  --site=<name>		The site code or 'all'.
  --yymm=<YYMM>		The reporting month in YYMM format.

  OPTIONAL
  --log				If set, the results from the script will be written to the Airwave
					log directory, otherwise the results will be written to the screen.
		\n");
	}
	exit;
}
