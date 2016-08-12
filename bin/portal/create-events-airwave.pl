#!/usr/bin/perl
# *********************************************************************************************
# *********************************************************************************************
#
#  Create a set of artificial event data from the data held in the content distribution plan
#  for each active site. There will be 1 usage record for each play of a film. The number of
#  plays and the charges are randomly generated as follows:
#    - Smoovie servers: The charge is £0 and each film has 1 play
#    - Hospitals: The charge is £0 and the number of plays is random (more plays as free)
#    - For all other servers: The price is selected at random between 3 prices and the number
#      of plays is random (less plays as the films are not free)
#
# *********************************************************************************************
# *********************************************************************************************

# Establish the root directory
our $ROOT;
BEGIN {
	$ROOT = '/srv/visualsaas/instances/airwave/bin';
}

# Declare modules
use strict;
use warnings;

# System modules
use Data::Dumper;
use Getopt::Long;
use IO::File;
use XML::Writer;

# Breato modules
use lib "$ROOT";
use mods::API3Portal qw(apiData apiStatus apiSelect);
use mods::Common qw(formatDateTime logMsg logMsgPortal readConfig);

# Program information
our $PROGRAM = "create-events-airwave.pl";
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

# If site is 'all', convert to '*'
$SITECODE = ($SITECODE eq 'all') ? '*' : $SITECODE;

# Declare global variables
our($FILE,$XML);

# Read the configuration parameters
our %CONFIG  = readConfig("$ROOT/etc/airwave-portal.conf");

# Define date related variables
my @dpm = (31,28,31,30,31,30,31,31,30,31,30,31);
our $DAYS = $dpm[int(substr($YYMM,2,2))-1];
our $EOM = $DAYS."/".substr($YYMM,2,2)."/".substr($YYMM,0,2); # DD/MM/YY
our $CCYY = "20".substr($YYMM,0,2);

# Directory in which events are created on the server
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
	my($status,$msg,%error,%sites,$currency,$rooms,$sitetype,$site_file,%films,$created,@assets,$plays,$index,@price,@filmlist,$content,$charge,$day);

	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");
	logMsg($LOG,$PROGRAM,"Create Events for period '$YYMM'");

	# Create a directory for the usage data on the server
	if(!-d $EVENT_DIR) {
		`mkdir -p $EVENT_DIR`;
	}
	if(!-d $EVENT_DIR) {
		logMsgPortal($LOG,$PROGRAM,'E',"Cannot create directory '$EVENT_DIR'");
		return;
	}

	# Retrieve a list of sites to be processed
	($msg) = apiSelect('createEventAirwaveSites',"month=$YYMM".'01',"site=$SITECODE");
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"Can't read sites from database [$error{CODE}] $error{MESSAGE}");
		return;
	}
	%sites = apiData($msg);
	if(!%sites) {
		logMsgPortal($LOG,$PROGRAM,'W',"No sites returned from database for period $YYMM");
	}

	# For each site, process the event and asset records
	SITE: foreach my $site (sort keys %sites) {
		# Read the site data
		$currency = $sites{$site}{currency};
		$rooms = $sites{$site}{rooms};
		$sitetype = $sites{$site}{type};

		# Read the films for the site
		($msg) = apiSelect('createEventSiteFilms',"month=$YYMM".'01',"site=$site");
		($status,%error) = apiStatus($msg);
		if(!$status) {
			logMsgPortal($LOG,$PROGRAM,'E',"Site '$site': Error reading films from Portal [$error{CODE}] $error{MESSAGE}");
			next SITE;
		}
		%films = apiData($msg);

		# If films returned, create usage file
		if(%films) {
			logMsg($LOG,$PROGRAM,"Processing films for '$site'");

			# Create a new XML file for the site and month
			$site_file = "$site.xml";
			open($FILE,">$EVENT_DIR/$site_file");
			if(!$FILE) {
				logMsgPortal($LOG,$PROGRAM,'E',"Cannot open file $EVENT_DIR/$site_file: $!");
				exit;
			}

			# Open the document and create the container element
			$XML = new XML::Writer(OUTPUT => $FILE);
			$XML->startTag('site','id'=>$site,'viewing_areas'=>$rooms);

			# Create a container element for the events
			$XML->startTag('events');
			@assets = ();

			# Generate a random index to extract a price for Current/Library films for the site
			$index = int(rand(25));
			$price[0] = (325,350,375,395,400,425,450,475,495,500,525,550,575,595,600,660,699,700,750,799,800,875,900,975,1000)[$index];
			$price[1] = (150,175,195,200,225,245,250,275,299,300,325,350,375,400,425,450,475,499,500,525,550,575,599,600,625)[$index];

			# Read the films and create a set of usage records for each film
			@filmlist = sort keys %films;
			FILM:for(my $i=0; $i<@filmlist; $i++) {
				# Skip 1 in 3 films
				if((1+$i)/3 == int((1+$i)/3)) { next FILM; }

				# Read each film and add to the list of installed films
				$content = $filmlist[$i];
				push(@assets,$content);

				# Create a random number of plays and charges
				# Smoovie sites
				if($site eq 'merton' || $site eq 'rognerhotel') {
					# Smoovie servers: each film has only 1 play and charge is 0
					$plays = 1;
					$charge = 0;
				}
				# Free sites
				elsif($sitetype eq 'hospital' || $sitetype eq 'oilrig' || $sitetype eq 'school') {
					# Create a random number of plays (more plays as free)
					$plays = int(rand(8));
					$charge = 0;
				}
				# For all other types of site
				else {
					# Create a random number of plays (less plays as charged)
					$plays = int(rand(5));
					if($films{$content}{package} eq 'Current') {
						$charge = $price[0];
					}
					else {
						$charge = $price[1];
					}
				}

				# Create 1 usage record for each play
				for(my $p=1; $p<=$plays; $p++) {
					$XML->startTag('event');
					$XML->dataElement('item',$content);
					$day = 1+int(rand($DAYS));
					$created = "20".substr($EOM,6,2)."-".substr($EOM,3,2)."-$day 00:00:00"; # 2009-03-31 00:00:00
					$XML->dataElement('created',$created);
					$XML->dataElement('charge',$charge);
					$XML->dataElement('currency',$currency);
					$XML->endTag('event');
				}
			}
			# Close the container
			$XML->endTag('events');

			# Process each asset record
			$XML->startTag('assets');
			foreach my $asset (@assets) {
				$XML->dataElement('asset',$asset);
			}
			$XML->endTag('assets');

			# Close the outer container, then close the XML file
			$XML->endTag('site');
			$XML->end();
			$FILE->close();

			# If file not created
			if(!-f "$EVENT_DIR/$site_file") {
				logMsgPortal($LOG,$PROGRAM,'W',"Stats file NOT created $EVENT_DIR/$site_file");
			}
		}
		# If no films returned, don't create a usage file
		else {
			logMsgPortal($LOG,$PROGRAM,'W',"Site '$site': No films returned, so no usage data file created");
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Program usage
# Argument 1 : Error number
# ---------------------------------------------------------------------------------------------
sub usage {
	my($err) = @_;
	$err = ($err) ? $err : 0;

	if($err == 1) {
		logMsg($LOG,$PROGRAM,"The 'yymm' argument must be present");
	}
	else {
		printf("
Program : $PROGRAM
Version : v$VERSION
Author  : Basil Fisk (c)2013 Airwave Ltd

Summary :
  Create a set of artificial event data from the data held in the content distribution plan
  for each active site. There will be 1 usage record for each play of a film. The number of
  plays and the charges are randomly generated as follows:
    - Smoovie servers: The charge is £0 and each film has 1 play
    - Hospitals: The charge is £0 and the number of plays is random (more plays as free)
    - For all other servers: The price is selected at random between 3 prices and the number
      of plays is random (less plays as the films are not free)

Usage :
  $PROGRAM --yymm=<YYMM>

  MANDATORY
    --yymm=<YYMM>	 The reporting month in YYMM format.

  OPTIONAL
    --s|site=<name>	Site for which the events are to be created.  The default is all sites.
    --log			If set, the results from the script will be written to the Airwave
					log directory, otherwise the results will be written to the screen.
		\n");
	}
	exit;
}
