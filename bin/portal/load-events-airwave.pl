#!/usr/bin/perl
# *********************************************************************************************
# *********************************************************************************************
#
#  Load Airwave event data from files stored on server into Portal database
#
#  There is one XML file for each site
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
use XML::LibXML;

# Breato modules
use lib "$ROOT";
use mods::API qw(apiDML apiData apiStatus);
use mods::Common qw(formatDateTime logMsg logMsgPortal parseDocument readConfig);

# Program information
our $PROGRAM = "load-events-airwave.pl";
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
our %CONFIG  = readConfig("$ROOT/etc/airwave-portal.conf");

# Define date related variables
our $CCYY = "20".substr($YYMM,0,2);
our @MONTHS = ('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec');

# Directory in which events are created on the local server
our $EVENT_DIR = "$ROOT/../$CONFIG{PORTAL_STATS}/Airwave/$CCYY/$YYMM";

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
	my(@files,$file,$site,$err,$xpc,@nodes,@elem,$asset,$start,$charge,$curr,$d,$t,$y,$m,$h,$i);
	my($status,$msg,%error);

	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");
	logMsg($LOG,$PROGRAM,"Loading Events to the Portal for period '$YYMM'");

	# Stop if directory does not exist on server
	if(!-d $EVENT_DIR) {
#	      logMsgPortal($LOG,$PROGRAM,'E',"Invalid month requested. Directory does not exist");
		logMsg($LOG,$PROGRAM,"Invalid month requested. Directory does not exist");
		return;
	}

	# If all sites requested, read list of usage data files in directory
	if($SITECODE eq 'all') {
		@files = `ls $EVENT_DIR`;
	}
	# If one site requested, check file exists
	else {
		$file = "$SITECODE.xml";
		if(-f "$EVENT_DIR/$file") {
			push(@files,$file);
		}
		else {
#	      logMsgPortal($LOG,$PROGRAM,'E',"No data file for [$SITECODE] found");
			logMsg($LOG,$PROGRAM,"No data file for [$SITECODE] found");
			return;
		}
	}

	# For each site, process the event and asset records
	foreach $file (@files) {
		chomp $file;
		($site) = split(/\./,$file);
		logMsg($LOG,$PROGRAM,"Site: $site");

		# Read the site data
		($err,$xpc) = parseDocument('file',"$EVENT_DIR/$file");
		@nodes = $xpc->findnodes('/site/events/event');
		foreach my $node (@nodes) {
			@elem = $node->findnodes('item');
			$asset = $elem[0]->textContent;
			@elem = $node->findnodes('created');
			$start = $elem[0]->textContent;
			@elem = $node->findnodes('charge');
			$charge = $elem[0]->textContent;
			@elem = $node->findnodes('currency');
			$curr = $elem[0]->textContent;

			# Convert date from 'YYYY-MM-DD HH24:MI:SS' to 'DD Mon YYYY HH24:MI'
			($d,$t) = split(/ /,$start);
			($y,$m,$d) = split(/-/,$d);
			($h,$i) = split(/:/,$t);
			$start = "$d $MONTHS[$m-1] $y $h:$i";

			# Change Null charges to 0
			$charge = ($charge) ? $charge : 0;
			$charge = int($charge);

			# Clean up currency
			$curr =~ s/\s+//g;
			$curr =~ tr[A-Z][a-z];

			# Insert a record
			($msg) = apiDML('createEventAirwave',"site=$site","asset=$asset","start='$start'","charge=$charge","currency=$curr");
			($status,%error) = apiStatus($msg);
			if(!$status) {
#			       logMsgPortal($LOG,$PROGRAM,'E',"Event record not added: [$site][$asset][$start][$charge][$curr] [$error{CODE}] $error{MESSAGE}");
				logMsg($LOG,$PROGRAM,"Event record not added: [$site][$asset][$start][$charge][$curr] [$error{CODE}] $error{MESSAGE}");
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
  Load the event data from the files stored on the local server into the Portal database.
  There is one XML file for each site.

Usage :
  $PROGRAM --yymm=<YYMM> --site=<name>
  
  MANDATORY
  --site=<name>		The site code or 'all'.
  --yymm=<YYMM>		The reporting month in YYMM format (between 1101 and 1512 inclusive).
  
  OPTIONAL
  --log				If set, the results from the script will be written to the Airwave
					log directory, otherwise the results will be written to the screen.
		\n");
	}
	exit;
}
