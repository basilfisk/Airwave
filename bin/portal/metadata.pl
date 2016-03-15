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
	$ROOT = '/srv/visualsaas/instances/airwave/bin';
}

# Declare modules
use strict;
use warnings;

# System modeles
use Data::Dumper;
use Getopt::Long;
use JSON::XS;

# Breato modules
use lib "$ROOT";
use mods::API qw(apiData apiMetadata apiStatus);
use mods::Common qw(logMsg logMsgPortal readConfig writeFile);

# Program information
our $PROGRAM = "metadata.pl";
our $VERSION = "2.1";

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
	
	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");

	# Read the JSON metadata from the Portal and create a file
	$text = read_metadata('json');
	if(!$text) { return; }
	if(!write_metadata('json',$text)) { return; }
	
	# Read the XML metadata from the Portal and create a file
	$text = read_metadata('xml');
	if(!$text) { return; }
	if(!write_metadata('xml',$text)) { return; }
}



# ---------------------------------------------------------------------------------------------
# Convert a string in JSON format to a hash
#
# Argument 1 : String in JSON format
#
# Return (pointer,undef) to a hash of data if successful, or (undef,message) if errors
# ---------------------------------------------------------------------------------------------
sub json_data {
	my($string) = @_;
	my($hash_ref);

	# Parse the string and trap any errors
	eval { $hash_ref = JSON::XS->new->latin1->decode($string) or die "error" };
	if($@) {
		return (undef,$@);
	}
	return ($hash_ref,undef);
}



# ---------------------------------------------------------------------------------------------
# Read metadata from the Portal
#
# Argument 1 : Type of content (json|xml)
#
# Return metadata for success or undef for error
# ---------------------------------------------------------------------------------------------
sub read_metadata {
	my($type) = @_;
	my($msg,$status,%error,$ref,$msg,%meta);
	my $name = uc($type);
	logMsg($LOG,$PROGRAM,"Generating $name metadata for $FILM");
	
	$msg = apiMetadata('apMetadata',$FILM,$type);
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Could not read $name metadata from Portal [$error{CODE}] $error{MESSAGE}");
		return;
	}
	else {
		# Return metadata from response message
		%meta = apiData($msg);
		if ($type eq 'json') {
			return encode_json(\%meta);
		}
		else {
			$msg = $meta{'xml'};
			$msg =~ s/&quot;/"/g;
			return $msg
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Read metadata from the Portal
#
# Argument 1 : Type of content (json|xml)
# Argument 2 : Metadata text
#
# Return 1 for success or 0 for error
# ---------------------------------------------------------------------------------------------
sub write_metadata {
	my($type,$text) = @_;
	my $dir = "../$CONFIG{PORTAL_META}/$PROVIDER/$FILM";
	my $name = uc($type);
	logMsg($LOG,$PROGRAM,"Writing $name metadata to Portal for $FILM");
	
	if(writeFile("$ROOT/$dir/$FILM.$type",$text)) {
		logMsg($LOG,$PROGRAM,"$name metadata written to file: $dir/$FILM.$type");
		return 1;
	}
	else {
		logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Could not write $name metadata to file: $dir/$FILM.$type");
		return 0;
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


