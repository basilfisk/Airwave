#!/usr/bin/perl
# ***************************************************************************
# ***************************************************************************
# 
# This script is the interface between the distributions that are planned
# and scheduled on the Portal, and CDS which manages the distributions to
# each site.
#
# ***************************************************************************
# ***************************************************************************

# Establish the root directory
our $ROOT;
BEGIN {
	$ROOT = '/srv/visualsaas/instances/aa002/bin';
}

# Declare modules
use strict;
use warnings;

# System modeles
use Data::Dumper;
use Getopt::Long;

# Breato modules
use lib "$ROOT";
use mods::API qw(apiData apiMetadata apiStatus);
use mods::Common qw(logMsg logMsgPortal readConfig writeFile);

# Program information
our $PROGRAM = "metadata.pl";
our $VERSION = "1.0";

# Check there are any arguments
if($#ARGV == -1) { usage(); }

# Read command line options
our $FILM		= 'empty';
our $PROVIDER	= 'empty';
our $LOG		= 0;
if(!GetOptions(
	'film=s'		=> \$FILM,
	'provider=s'	=> \$PROVIDER,
	'log'			=> \$LOG,
	'help'			=> sub { usage(); } ))
	{ exit; }

# Check that film and provider arguments have been entered
if($FILM eq 'empty') { usage(1); }
if($PROVIDER eq 'empty') { usage(2); }

# Read the configuration parameters
our %CONFIG  = readConfig("$ROOT/etc/airwave-portal.conf");

# Start processing
main();





# ---------------------------------------------------------------------------------------------
# Process a single film or all films for a content provider
# ---------------------------------------------------------------------------------------------
sub main {
	my($text);
	my $dir = "../$CONFIG{PORTAL_META}/$PROVIDER/$FILM";
	
	# Read the JSON metadata from the Portal and create a file
	$text = apiMetadata('apMetadata',$FILM,'json');
	if(!$text) {
		logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Could not read metadata [$type] from Portal: [code] text");
		return;
	}
	writeFile("$dir/$FILM.json",$text);
	
	# Read the XML metadata from the Portal and create a file
	$text = apiMetadata('apMetadata',$FILM,'xml');
	if(!$text) {
		logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Could not read metadata [$type] from Portal: [code] text");
		return;
	}
	writeFile("$dir/$FILM.xml",$text);
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
		print "\nA single film must be specified\n\n";
	}
	elsif($err == 2) {
		print "\nThe content provider must be specified\n\n";
	}
	else {
		printf("
Program : $PROGRAM
Version : v$VERSION
Author  : Basil Fisk (c)2015 Airwave Ltd

Summary :
  Generate a JSON and an XML metadata file for the specified film.

Usage :
  $PROGRAM

  MANDATORY
    --f|film=<name>          Film to be processed.
    --p|provider=<name>      Content provider of the film.
  
  OPTIONAL
    --log		If set, the results from the script will be written to the Airwave
				log directory, otherwise the results will be written to the screen.
		\n");
	}

	# Stop in all cases
	exit;
}


