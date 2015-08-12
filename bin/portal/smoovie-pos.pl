#!/usr/bin/perl
# ***************************************************************************
# ***************************************************************************
# 
#  Generate point of sales literature for each Smoovie hotel as a PDF file
#  and create a schedule file for the Smoovie server in text format.
#
# ***************************************************************************
# ***************************************************************************

# Set the root directory as the home directory of the user
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
use IO::File;
use XML::Writer;

# Breato modules
use lib "$ROOT";
use mods::API qw(apiData apiStatus apiSelect);
use mods::Common qw(formatDateTime logMsg logMsgPortal readConfig);
use mods::PDF qw(pdfReport);

# Program information
our $PROGRAM = "smoovie-pos.pl";
our $VERSION = "2.0";

# Read command line options
our $LOG	= 0;
GetOptions (
	'log'	=> \$LOG,
	'help'	=> sub { usage(); } );

# Read the configuration parameters
our %CONFIG = readConfig("$ROOT/etc/airwave-portal.conf");

# Name of data file and configuration file
our($FILEHANDLE,$XML);
our $CONFFILE = "$ROOT/etc/smoovie-pos.conf";
our $DATAFILE = "$ROOT/tmp/smoovie-pos.xml";

# Start processing
main();





# ---------------------------------------------------------------------------------------------
# Start processing
# ---------------------------------------------------------------------------------------------
sub main {
	# Initialise local variables
	my($status,$msg,%error);
	my(%sites,$id,$sitecode,$sitename,%films);

	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");
	logMsg($LOG,$PROGRAM,"Smoovie In-Room Fliers");

	# Return a hash keyed by site name
	($msg) = apiSelect('smoovieSites');
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"No sites returned from database [$error{CODE}] $error{MESSAGE}");
		exit;
	}
	%sites = apiData($msg);

	# Process each site
	SITE: foreach my $key (sort keys %sites) {
		$id = $sites{$key}{site_id};
		$sitecode = $sites{$key}{site_code};
		$sitename = $sites{$key}{site};

		# Read a hash of films for the site keyed by film name
		($msg) = apiSelect('smoovieSiteFilms',"site=$id");
		($status,%error) = apiStatus($msg);
		if(!$status) {
			logMsgPortal($LOG,$PROGRAM,'W',"No films returned for site '$id' [$error{CODE}] $error{MESSAGE}");
		}
		%films = apiData($msg);

		# Skip site if no films returned for site
		if(!%films) {
			logMsgPortal($LOG,$PROGRAM,'W',"No films returned for '$sitename'");
			next SITE;
		}

		# Process the sheets for each site
		if($sitecode eq 'merton') {
			# Generate sheet with 7 UIP films
			logMsg($LOG,$PROGRAM,"Site: $sitename ($sitecode)");
			sheet_7_UIP($sitecode,$sitename,%films);
		}
		else {
			# Only Rogner at the moment and they have no UIP films
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Print a sheet with 7 UIP films (1 across top, then 3x2)
#
# Argument 1 : Site code
# Argument 2 : Site name
# Argument 3 : Hash of film data keyed by film name
# ---------------------------------------------------------------------------------------------
sub sheet_7_UIP {
	my($sitecode,$sitename,%films) = @_;
	my($fh,$xml,$file);
	my($provider,$channel,$slot,$schedule,$assetcode,$title,$short,$full,$cert,$release,$duration,$credits);
	my($status,$msg,%error,%genre,$genres,$cast_list,$lang);

	# Create a new XML file
	open($fh,">$DATAFILE");

	# Open XML document and create container elements
	$xml = new XML::Writer(OUTPUT => $fh);
	$xml->startTag('data');

	# Generate static section of document
	$xml->startTag('static');
	$xml->dataElement('title1',"Films Showing This Month");
	$xml->dataElement('title2','All Films are Free');
	$xml->dataElement('logo',"$ROOT/../$CONFIG{IMAGE_TEMPLATE}/$sitecode.gif");
	$xml->endTag('static');

	# Generate dynamic section of the document
	$xml->startTag('dynamic');
	foreach my $key (sort keys %films) {
		$provider = $films{$key}{provider};
		$channel = $films{$key}{channel};
		$slot = $films{$key}{slot};
		$schedule = $films{$key}{schedule};
		$assetcode = $films{$key}{asset_code};
		$title = $films{$key}{title};
		$short = $films{$key}{summary};
		$full = $films{$key}{synopsis};
		$cert = $films{$key}{certificate};
		$release = $films{$key}{release_date};
		$duration = $films{$key}{duration};
		$credits = $films{$key}{credits};

		# Read genres for film
		($msg) = apiSelect('smoovieGenres',"assetcode=$assetcode");
		($status,%error) = apiStatus($msg);
		if(!$status) {
			logMsgPortal($LOG,$PROGRAM,'E',"No genre defined for '$assetcode' [$error{CODE}] $error{MESSAGE}");
		}
		%genre = apiData($msg);

		# Build up genre list
		$genres = '';
		foreach my $genre (sort keys %genre) {
			$genres  .= $genre."\@nl\@";
		}
		$genres = substr($genres,0,-4);

		# Change '\n' newlines for '@nl@' newlines
		$cast_list = '';
		foreach my $cast (split(/\n/,$credits)) {
			$cast_list .= $cast."\@nl\@";
		}
		$cast_list = substr($cast_list,0,-4);

		# Write the data record
		$xml->startTag('record','id'=>'data');
		$xml->dataElement('title',$title);
		$xml->dataElement('duration',$duration);
		$xml->dataElement('poster',"$ROOT/../$CONFIG{PORTAL_META}/$provider/$assetcode/$assetcode-small.jpg");
		$xml->dataElement('certificate',"$ROOT/../$CONFIG{IMAGE_TEMPLATE}/BBFC_$cert.jpg");
		$xml->dataElement('summary',$short);
		$xml->dataElement('synopsis',$full);
		$xml->dataElement('cast',$cast_list);
		$xml->dataElement('genres',$genres);
		$xml->dataElement('channel',$channel);
		$xml->dataElement('schedule',$schedule);
		$xml->endTag('record');
	}
	$xml->endTag('dynamic');

	# Close the containers, then close the XML file
	$xml->endTag('data');
	$xml->end();
	$fh->close();

	# Generate the PDF file
	$file = "$ROOT/../$CONFIG{PORTAL_INVENTORY}/$sitecode/Smoovie\ POS.pdf";
	pdfReport($CONFFILE,$DATAFILE,$file);
	logMsg($LOG,$PROGRAM,"Created report '$file'");

	# Generate the schedule file
	$file = "$ROOT/../$CONFIG{PORTAL_INVENTORY}/$sitecode/Smoovie.txt";
	schedule_file($file,%films);
	logMsg($LOG,$PROGRAM,"Created schedule file '$file'");
}



# ---------------------------------------------------------------------------------------------
# Create the Smoovie schedule file
#
# Argument 1 : File name and path
# Argument 2 : Hash of film details
# ---------------------------------------------------------------------------------------------
sub schedule_file {
	my($file,%films) = @_;
	my($channel,$schedule,$assetcode);

	# Create header
	open(FILE,">$file") or die "Cannot create file [$file]: $!";
	print FILE "# <STREAM>,<FILE NAME>,<TIMES>\n";
	print FILE "NEW\n";

	# Add films
	foreach my $key (sort keys %films) {
		$channel = $films{$key}{channel};
		$schedule = $films{$key}{schedule};
		$assetcode = $films{$key}{asset_code};

		# Replace spaces between times with commas
		$schedule =~ s/ /,/g;

		# Change channel numbers to a sequence starting from 1
		$channel -= 902;

		# Print the record
		print FILE "$channel,$assetcode,$schedule\n";
	}

	# Close the file
	close(FILE);
}



# ---------------------------------------------------------------------------------------------
# Program usage
# ---------------------------------------------------------------------------------------------
sub usage {
	printf("
Program : $PROGRAM
Version : v$VERSION
Author  : Basil Fisk (c)2013 Airwave Ltd

Summary :
  Generate point of sales literature for each Smoovie hotel as a PDF file
  and create a schedule file for the Smoovie server in text format.

Usage :
  $PROGRAM

  OPTIONAL
  --log		If set, the results from the script will be written to the Airwave
			log directory, otherwise the results will be written to the screen.
	\n");
	exit;
}
