#!/usr/bin/perl
# *********************************************************************************************
# *********************************************************************************************
#
# Ingest a single VTT sub-title file.  Load the name of the file and language contained 
# within the file onto the Portal, and save a copy of the original file named as
# {assetcode}_{language code}.vtt into the metadata directory.
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
use Getopt::Long;
use Data::Dumper;

# Breato modules
use lib "$ROOT";
use mods::API qw(apiData apiDML apiSelect apiStatus);
use mods::Common qw(formatDateTime logMsg logMsgPortal readConfig);

# Program information
our $PROGRAM = "ingest_vtt.pl";
our $VERSION = "1.0";

# Check there are any arguments
if($#ARGV == -1) { usage(); }

# Read command line options
our $ASSET		= 'empty';
our $DIRECTORY	= 'empty';
our $FILENAME	= 'empty';
our $LANGUAGE	= 'empty';
our $LOG		= 0;
if(!GetOptions(
	'asset=s'		=> \$ASSET,
	'directory=s'	=> \$DIRECTORY,
	'file=s'		=> \$FILENAME,
	'language=s'	=> \$LANGUAGE,
	'log'			=> \$LOG,
	'help'			=> sub { usage(); } ))
	{ exit; }

# Read the configuration parameters
our %CONFIG  = readConfig("$ROOT/etc/airwave-portal.conf");

# Declare and initialise global variables
our %LANGUAGES;

# Start processing
main();





# ---------------------------------------------------------------------------------------------
# Process a single film or all films for a content provider
# ---------------------------------------------------------------------------------------------
sub main {
	my($status,$msg,%error,%films,$cid,$provider,$source,$tfile,$tdir,$res);
	logMsg($LOG,$PROGRAM,"=================================================================================");
	
	# Load a hash containing language values
	if(!read_languages()) {
		return;
	}
	
	# Check that an asset has been selected
	if($ASSET =~ m/empty/) {
		logMsgPortal($LOG,$PROGRAM,'E',"ERROR: 'asset' argument must have a value");
		return;
	}
	
	# Check that a directory has been selected
	if($DIRECTORY =~ m/empty/) {
		logMsgPortal($LOG,$PROGRAM,'E',"ERROR: 'directory' argument must have a value");
		return;
	}
	
	# Check that a file has been selected
	if($FILENAME =~ m/empty/) {
		logMsgPortal($LOG,$PROGRAM,'E',"ERROR: 'file' argument must have a value");
		return;
	}
	
	# Check that a language has been selected
	if($LANGUAGE =~ m/empty/) {
		logMsgPortal($LOG,$PROGRAM,'E',"ERROR: 'language' argument must have a value");
		return;
	}
	
	# Check language code is valid
	if(!$LANGUAGES{$LANGUAGE}) {
		logMsgPortal($LOG,$PROGRAM,'E',"ERROR: Invalid language code '$LANGUAGE'");
		return;
	}
	
	# Read the film ID from the Portal
	($msg) = apiSelect('ingestFilm',"assetcode=$ASSET");
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"Error reading details for [$ASSET] from database: $error{MESSAGE}");
		return;
	}
	%films = apiData($msg);

	# Stop if no film found on Portal
	if(!%films) {
		logMsgPortal($LOG,$PROGRAM,'E',"No film matching [$ASSET] - film must be active and delivered");
		return;
	}
	$cid = $films{$ASSET}{'content_id'};
	$provider = $films{$ASSET}{'provider'};
	
	# Directories on Portal holding VTT files are based on provider of film
	$source = "$ROOT/../$CONFIG{VTT_FILES}/$provider/$DIRECTORY/$FILENAME";
	$tdir = "$ROOT/../$CONFIG{PORTAL_META}/$provider/$ASSET";
	$tfile = "$ASSET".'_'."$LANGUAGE.vtt";
	
	# Check VTT file exists
	if(!-f $source) {
		logMsgPortal($LOG,$PROGRAM,'E',"There is no VTT file '$FILENAME' in '$CONFIG{VTT_FILES}/$provider/$DIRECTORY'");
		return;
	}
	
	# Create the different image sizes
	$res = `cp $source $tdir/$tfile`;
	if($res) {
		logMsgPortal($LOG,$PROGRAM,'E',"Error copying VTT file '$FILENAME' to '$tdir': $res");
		return;
	}
	
	# Add VTT file details to the Portal
	portal_update($cid,$tfile);
}



# ---------------------------------------------------------------------------------------------
# Save the details of the VTT file to the Portal
#
# Argument 1 : ID of the film
# Argument 2 : Name of the ingested VTT file
# ---------------------------------------------------------------------------------------------
sub portal_update {
	my($cid,$name) = @_;
	my($langid,$msg,$status,%error,%data,$id);
	
	# Find ID of language
	$langid = $LANGUAGES{$LANGUAGE};
	
	# Does file already exist on Portal?
	($msg) = apiSelect('ingestVttSearch',"cid=$cid","language=$langid");
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"Error reading details of VTT file for '$ASSET': $error{MESSAGE}");
		return;
	}
	
	# Extract the ID if a match has been found
	%data = apiData($msg);
	if (%data) {
		$id = $data{$cid.'-'.$langid}{'id'};
	}
	
	# If new file, add the file attributes to the Portal
	if(!$id) {
		($msg) = apiDML('ingestVttInsert',"cid=$cid","name=$name","language=$langid");
		($status,%error) = apiStatus($msg);
		if(!$status) {
			logMsgPortal($LOG,$PROGRAM,'E',"$ASSET: Could not add details for the '$LANGUAGE' file: $error{MESSAGE}");
		}
		else {
			logMsg($LOG,$PROGRAM,"$ASSET: File for '$LANGUAGE' has been added");
		}
	}
	# If file already exists, update the file attributes on the Portal
	else {
		($msg) = apiDML('ingestVttUpdate',"id=$id","name=$name","language=$langid");
		($status,%error) = apiStatus($msg);
		if(!$status) {
			logMsgPortal($LOG,$PROGRAM,'E',"$ASSET: Could not update details for the '$LANGUAGE' file: $error{MESSAGE}");
		}
		else {
			logMsg($LOG,$PROGRAM,"$ASSET: File for '$LANGUAGE' has been updated");
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Create a hash of hashes holding language values
#
# Return 1 if data read successfully, 0 if error raised
# ---------------------------------------------------------------------------------------------
sub read_languages {
	my($status,$msg,%error,%data);
	
	# Read language IDs
	($msg) = apiSelect('ingestVttLanguages');
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"No list values returned: $error{MESSAGE}");
		return 0;
	}
	%data = apiData($msg);
	
	# Create hash
	foreach my $code (keys %data) {
		$LANGUAGES{$code} = $data{$code}{'id'};
	}

	return 1;
}



# ---------------------------------------------------------------------------------------------
# Program usage
#
# Argument 1 : Error number
# ---------------------------------------------------------------------------------------------
sub usage {
	my($err) = @_;
	$err = ($err) ? $err : 0;
	
	printf("
Program : $PROGRAM
Version : v$VERSION
Author  : Basil Fisk (c)2015 Airwave Ltd

Summary :
  Ingest a single VTT sub-title file.  Load the name of the file and language contained 
  within the file onto the Portal, and save a copy of the original file named as
  {assetcode}_{language code}.vtt into the metadata directory.

Usage :
  $PROGRAM --asset=<code> --directory=<name> --file=<name> --language=<code>
  
  MANDATORY
  --asset=<code>           The reference of a single film on the Portal.
  --directory=<code>       The name of the directory holding the VTT files on the Portal.
  --file=<code>            The name of the VTT file to be ingested.
  --language=<code>        The language of the VTT file to be ingested.
  
  OPTIONAL
  --log                 If set, the results from the script will be written to the Airwave
                        log directory, otherwise the results will be written to the screen.
	\n");

	# Quit
	exit;
}


