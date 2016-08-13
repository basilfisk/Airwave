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
use mods::API3Portal qw(apiData apiMetadata apiSelect apiStatus);
use mods::Common qw(formatDateTime logMsg logMsgPortal metadataJsonToXML readConfig writeFile);

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
	my($msg,$status,%error,%data,$code);

	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");

	# Generate metadata for all provider's films
	if($FILM eq 'all') {
		$msg = apiSelect('metadataFilms',"provider=$PROVIDER");
		($status,%error) = apiStatus($msg);
		if(!$status) {
			logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Could not read film codes from Portal [$error{CODE}] $error{MESSAGE}");
			return;
		}
		else {
			# Run through all films, even if there are problems
			%data = apiData($msg);
			foreach $code (sort keys %data) {
				generate_meta($code);
			}
		}
	}
	else {
		generate_meta($FILM);
	}
}



# ---------------------------------------------------------------------------------------------
# Generate JSON and XML metadata for 1 film
#
# Argument 1 : Film code
# ---------------------------------------------------------------------------------------------
sub generate_meta {
	my($filmcode) = @_;
	my($text);

	# Read the JSON metadata from the Portal and create a file
	$text = read_metadata($filmcode,'json');
	if(!$text) { return; }
	if(!write_metadata($filmcode,'json',$text)) { return; }

	# Read the XML metadata from the Portal and create a file
	$text = read_metadata($filmcode,'xml');
	if(!$text) { return; }
	if(!write_metadata($filmcode,'xml',$text)) { return; }
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
# Argument 1 : Film code
# Argument 2 : Type of content (json|xml)
#
# If successful return metadata as a string, otherwise return undef
# ---------------------------------------------------------------------------------------------
sub read_metadata {
	my($filmcode,$type) = @_;
	my($msg,$status,%error,%meta,$xml,@arr,@arr2,%attr);
	my $name = uc($type);
	logMsg($LOG,$PROGRAM,"Generating $name metadata for $filmcode in $type format");

	$msg = apiMetadata($filmcode);
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Could not read $name metadata for $filmcode [$error{CODE}] $error{MESSAGE}");
		return;
	}
	else {
		# Return metadata from response message
		%meta = apiData($msg);
		if ($type eq 'json') {
			return encode_json(\%meta);
		}
		else {
			return metadataJsonToXML(%meta);
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Read metadata from the Portal
#
# Argument 1 : Film code
# Argument 2 : Type of content (json|xml)
# Argument 3 : Metadata text
#
# Return 1 for success or 0 for error
# ---------------------------------------------------------------------------------------------
sub write_metadata {
	my($filmcode,$type,$text) = @_;
	my $dir = "$ROOT/../$CONFIG{PORTAL_META}/$PROVIDER/$filmcode";
	my $name = uc($type);
	logMsg($LOG,$PROGRAM,"Writing $name metadata to Portal for $filmcode");

	# Check directory exists before writing
	if (!-d $dir) {
		logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Directory $dir does not exist");
		return 0;
	}
	else {
		if(writeFile("$dir/$filmcode.$type",$text)) {
			logMsg($LOG,$PROGRAM,"$name metadata written to file $dir/$filmcode.$type");
			return 1;
		}
		else {
			logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Could not write $name metadata to file $dir/$filmcode.$type");
			return 0;
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Create an opening XML element with attributes
#
# Argument 1 : Element name
# Argument 2 : Hash of attributes
#
# Return XML string
# ---------------------------------------------------------------------------------------------
sub xml_attribute {
	my($name,%attr) = @_;
	my($str);
	$str = '<'.$name;
	foreach my $id (keys %attr) {
		$str .= ' '.$id.'="'.$attr{$id}.'"';
	}
	$str .= '>';
	return $str;
}



# ---------------------------------------------------------------------------------------------
# Create an XML element with a data value
#
# Argument 1 : Element name
# Argument 2 : Element value
#
# Return XML string
# ---------------------------------------------------------------------------------------------
sub xml_element {
	my($name,$value) = @_;
	my $str = '';
	if($value) {
		$str .= '<'.$name.'>';
		$str .= $value;
		$str .='</'.$name.'>';
	}
	return $str;
}



# ---------------------------------------------------------------------------------------------
# Create an XML element with attributes and a data value
#
# Argument 1 : Element name
# Argument 2 : Element value
# Argument 3 : Hash of attributes
#
# Return XML string
# ---------------------------------------------------------------------------------------------
sub xml_element_attribute {
	my($name,$value,%attr) = @_;
	my($str);
	$str = '<'.$name;
	foreach my $id (keys %attr) {
		$str .= ' '.$id.'="'.$attr{$id}.'"';
	}
	$str .= '>';
	$str .= $value;
	$str .='</'.$name.'>';
	return $str;
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
    --f|film=all             Process all films for the content provider.
    --p|provider=<name>      Content provider of the film.

  OPTIONAL
    --log		If set, the results from the script will be written to the Airwave
				log directory, otherwise the results will be written to the screen.
		\n");
	}

	# Stop in all cases
	exit;
}
