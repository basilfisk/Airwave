#!/usr/bin/perl
# *********************************************************************************************
# *********************************************************************************************
# 
#  Generate the point of sales literature for a specified content package as a PDF file.
#  The report shows 4 films on each page and lists the synopsis information for each film
#  in the package. One report is generated for each package in each territory, unless the
#  territory argument is used to specify the country code of a single territory.
#  Each report is written to the Airwave Portal.
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
use Getopt::Long;

# Breato modules
use lib "$ROOT";
use mods::API qw(apiData apiStatus apiSelect);
use mods::Common qw(logMsg logMsgPortal);

# Program information
our $PROGRAM = "showing.pl";
our $VERSION = "2.0";

# Check there are any arguments
if($#ARGV == -1) { usage(); }

# Read command line options
our $LOG		= 0;
our $LANGUAGE	= 'en';
our $PACKAGE	= 'empty';
our $SHOWLOGO	= 1;
our $TERRITORY	= 'all';
GetOptions (
	'log'			=> \$LOG,
	'language=s'	=> \$LANGUAGE,
	'nologo'		=> sub { $SHOWLOGO = 0 },
	'package=s'		=> \$PACKAGE,
	'territory=s'	=> \$TERRITORY,
	'help'			=> sub { usage(); } );

# Check that package argument is present
if($PACKAGE eq 'empty') { usage(1); }

# Check the validity of the 'package' argument
if(!($PACKAGE eq 'all' || 
	$PACKAGE eq 'bbc' || 
	$PACKAGE eq 'c18' || 
	$PACKAGE eq 'r18' || 
	$PACKAGE eq 'new' || 
	$PACKAGE eq 'current' || 
	$PACKAGE eq 'library')) { usage(2); }

# If 'all' has been specified for a territory, convert to a wild card
if($TERRITORY eq 'all') { $TERRITORY    = '*'; }

# Start processing
main();





# ---------------------------------------------------------------------------------------------
# Start processing
# ---------------------------------------------------------------------------------------------
sub main {
	# Initialise local variables
	my($status,$msg,%error,%territories,$ref);

	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");
	logMsg($LOG,$PROGRAM,"Generating the Film Marketing Sheets");

	# Return a hash of territories
	($msg) = apiSelect('showingTerritories',"territory=$TERRITORY");

	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"No territories returned from database [$error{CODE}] $error{MESSAGE}");
		exit;
	}
	%territories = apiData($msg);

	# Loop through the territories to be processed (default to all)
	foreach my $terr (sort keys %territories) {
		logMsg($LOG,$PROGRAM,"===> $terr");
		$ref = $territories{$terr}{code};

		if($PACKAGE eq 'all') {
			film_package($ref,$terr,'bbc');
			film_package($ref,$terr,'c18');
			film_package($ref,$terr,'r18');
			film_package($ref,$terr,'current');
			film_package($ref,$terr,'library');
			film_package($ref,$terr,'new');
		}
		else {
			film_package($ref,$terr,$PACKAGE);
		}

	}
}



# ---------------------------------------------------------------------------------------------
# Call the script that will generate a single file
#
# This is done in a child process because there is a memory leak issue with PDF::Create and 
# running all reports within 1 script causes memory full issues on the Portal server
#
# Argument 1 : Territory reference
# Argument 2 : Territory name
# Argument 3 : Package reference
# ---------------------------------------------------------------------------------------------
sub film_package {
	my($ref,$terr,$pack,$lang,$logo,$log) = @_;

	`$ROOT/showing-child.pl -code=$ref -name='$terr' -package=$pack -language=$LANGUAGE -logo=$SHOWLOGO -log=$LOG`;
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
		logMsg($LOG,$PROGRAM,"The 'package' argument must be present");
	}
	elsif($err == 2) {
		logMsg($LOG,$PROGRAM,"The 'package' argument must be one of: all/new/current/library");
	}
	else {
		printf("
Program : $PROGRAM
Version : v$VERSION
Author  : Basil Fisk (c)2013 Airwave Ltd

Summary :
  Generate the point of sales literature for a specified content package as a PDF file.
  The report shows 4 films on each page and lists the synopsis information for each film
  in the package. One report is generated for each package in each territory, unless the
  territory argument is used to specify the country code of a single territory.
  Each report is written to the Airwave Portal.

Usage :
  $PROGRAM --package=<type>
  $PROGRAM --package=<type> --territory=<code> --language=<code>
  
  MANDATORY
  --package=all			Generate the UIP New, Current and Library reports in 1 batch.
  --package=bbc			Report listing the films in the BBC package.
  --package=current		Report listing the films in the UIP 'Current' package.
  --package=library		Report listing the films in the UIP 'Library' package.
  --package=new			Report listing the UIP films that are 'Coming Soon'.
  --package=c18			Report listing the films in the PBTV 'Soft' package.
  --package=r18			Report listing the films in the PBTV 'Explicit' package.

  OPTIONAL
  --language=<code>		The language code for the film synopses.
						If this argument is not specified, English will be used.
  --territory=<code>	The country code of a single territory.
						If this argument is not specified, all territories will be used.
  --log					If set, the results from the script will be written to the Airwave
						log directory, otherwise the results will be written to the screen.
  --nologo				Don't put a logo at the top of the printed page.
  --noupload			Don't upload the files to the Portal.
		\n");
	}

	# Stop in all cases
	exit;
}
