#!/usr/bin/perl
# *********************************************************************************************
# *********************************************************************************************
#
# Move files between the repository and archive directories depending on their status on the Portal.
#
# 1. Move an asset directory from repository to archive if:
#      - the asset is inactive on the Portal and
#      - the directory exists in the repository
#
# 2. Move an asset directory from archive to repository if:
#      - the asset is active on the Portal and
#      - the directory exists in the archive
#      - the repository directory does not exist
#
# 3. If there are multiple film files in the repository, move oldest to archive
#
# *********************************************************************************************
# *********************************************************************************************

# Establish the root directory
our $ROOT;
BEGIN {
	$ROOT = '/home/airwave/bin/Airwave';
}

# Declare modules
use strict;
use warnings;

# System modules
use Getopt::Long;

# Breato modules
use lib "$ROOT";
use mods::API3 qw(apiData apiSelect apiStatus);
use mods::Common qw(formatDateTime logMsg logMsgPortal readConfig);

# Program information
our $PROGRAM = "archive.pl";
our $VERSION = "2.0";

# Read command line options
our $LOG	= 0;
our $TEST	= 1;
GetOptions (
	'log'	=> \$LOG,
	'live'	=> sub { $TEST = 0; },
	'test'	=> sub { $TEST = 1; },
	'help'	=> sub { usage(); } );

# Read the configuration parameters
our %CONFIG  = readConfig("$ROOT/etc/airwave.conf");

# Start processing
main();





# =============================================================================================
# =============================================================================================
#
# PROCESSING FUNCTIONS
#
# =============================================================================================
# =============================================================================================

# ---------------------------------------------------------------------------------------------
# Main processing function
# ---------------------------------------------------------------------------------------------
sub main {
	my($status,$msg,%error,%films);
	my($assetcode,$active,$provider,$live,$archive,$dh,@files,$newest);

	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");

	# Return a hash of films, keyed with the asset code (directory name)
	($msg) = apiSelect('archiveFilms');
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"SQL command 'archiveFilms' did not return any records [$error{CODE}] $error{MESSAGE}");
		exit;
	}
	%films = apiData($msg);

	# Process each film record flagged as inactive
	foreach my $key (sort keys %films) {
		($provider,$assetcode,$active) = @{$films{$key}};

		# Determine the repository and archive directories
		$live = "$CONFIG{CS_ROOT}/$provider";
		$archive = "$CONFIG{CS_ARCH}/$provider";

		if(!$live) {
			logMsgPortal($LOG,$PROGRAM,'W',"Unknown content provider '$provider' for asset '$assetcode'");
			return;
		}

		# If asset is inactive and exists in repository, move from repository to archive
		if($active eq 'false' && -d $live) {
			move_dir('archive',"$live/$assetcode",$archive);
		}

		# If asset is active and exists in the archive directory but not the repository, move from archive to repository
		if($active eq 'true' && -d $archive && (!-d $live)) {
			move_dir('restore',"$archive/$assetcode",$live);
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Trap error when moving a file or directory
# ---------------------------------------------------------------------------------------------
sub error_move {
	my($res,$from,$to) = @_;
	if($res) {
		logMsgPortal($LOG,$PROGRAM,'E',"Error moving [$from] to '$to': $res");
	}
}



# ---------------------------------------------------------------------------------------------
# Move an asset directory
#
# Argument 1 : Action to be taken (archive/restore)
# Argument 2 : Source directory
# Argument 3 : Target directory
# ---------------------------------------------------------------------------------------------
sub move_dir {
	my($action,$source,$target) = @_;
	my($msg,$way,$res);

	# Text to be shown in log message
	if($action eq 'archive') {
		$msg = 'Archiving';
		$way = 'to';
	}
	else {
		$msg = 'Restoring';
		$way = 'from';
	}

	# Only move if source directory exists
	if(-d $source) {
		if($TEST) {
			logMsg($LOG,$PROGRAM,"TEST: $msg directory '$source' $way '$target'");
		}
		else {
			logMsg($LOG,$PROGRAM,"$msg directory '$source' $way '$target'");
			$res = `mv $source $target 2>&1`;
			error_move($res,$source,$target);
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Move an asset file
#
# Argument 1 : Source file
# Argument 2 : Archive directory
# ---------------------------------------------------------------------------------------------
sub move_file {
	my($source,$archive) = @_;
	my($res);

	# Create archive directory if it doesn't already exist
	if(!-d $archive) {
		if($TEST) {
			logMsg($LOG,$PROGRAM,"TEST: Creating archive directory '$archive'");
		}
		else {
			logMsg($LOG,$PROGRAM,"Creating archive directory '$archive'");
			$res = `mkdir -p $archive`;
			if($res) {
				logMsgPortal($LOG,$PROGRAM,'E',"Error creating directory [$archive]: $res");
			}
		}
	}

	# Move the file
	if($TEST) {
		logMsg($LOG,$PROGRAM,"TEST: Archiving file '$source' to '$archive'");
	}
	else {
		logMsg($LOG,$PROGRAM,"Archiving '$source' to '$archive'");
		$res = `mv $source $archive 2>&1`;
		error_move($res,$source,$archive);
	}
}



# ---------------------------------------------------------------------------------------------
# Program usage
#
# Argument 1 : Error number
# ---------------------------------------------------------------------------------------------
sub usage {
	my($err) = @_;

	printf("
Program : $PROGRAM
Version : v$VERSION
Author  : Basil Fisk (c)2015 Airwave Ltd

Summary :
  Move files between the repository and archive directories depending on their status on the Portal.

  1. Move an asset directory from repository to archive if:
       - the asset is inactive on the Portal and
       - the directory exists in the repository

  2. Move an asset directory from archive to repository if:
       - the asset is active on the Portal and
       - the directory exists in the archive
       - the repository directory does not exist

  3. If there are multiple film files in the repository, move oldest to archive

Usage   : $PROGRAM

  OPTIONAL
    --live                 Move the film directories.
    --test                 Dry run without moving film directories (default option).
    --log                  If set, the results from the script will be written to the Airwave
                           log directory, otherwise the results will be written to the screen.
	\n");

	# Stop in all cases
	exit;
}
