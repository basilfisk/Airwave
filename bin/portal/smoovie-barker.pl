#!/usr/bin/perl
# ***************************************************************************
# ***************************************************************************
#
#  Generate the background image for the barker channel for each Smoovie
#  hotel, showing the film's large image, cast list, certificate log, title,
#  duration and start times.
#
#  One file is generated for each channel/slot in PDF and JPG format.
#
# ***************************************************************************
# ***************************************************************************

# Set the root directory as the home directory of the user
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
use mods::PDF qw(pdfReport);

# Program information
our $PROGRAM = "smoovie-barker.pl";
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
our $CONFFILE = "$ROOT/etc/smoovie-barker.conf";
our $DATAFILE = "$ROOT/tmp/smoovie-barker.xml";

# Start processing
main();





# ---------------------------------------------------------------------------------------------
# Start processing
# ---------------------------------------------------------------------------------------------
sub main {
	my($status,$msg,%error,@cast,$actor,$image,$file_pdf,$file_jpg);
	my(%sites,$id,$sitecode,$sitename);
	my(%films,$provider,$channel,$slot,$schedule,$assetcode,$title,$short,$full,$cert,$release,$duration,$credits);

	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");
	logMsg($LOG,$PROGRAM,"Smoovie Barker Channel Background");

	# Return a hash keyed by site name
	($msg) = apiSelect('smoovieSites');
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"No sites returned from database: $msg");
		exit;
	}
	%sites = apiData($msg);

	# Process each site
	foreach my $key (sort keys %sites) {
		$id = $sites{$key}{site_id};
		$sitecode = $sites{$key}{site_code};
		$sitename = $sites{$key}{site};
		logMsg($LOG,$PROGRAM,"Site: $sitename ($sitecode)");

		# Return a hash keyed by film name
		($msg) = apiSelect('smoovieSiteFilms',"site=$id");
		($status,%error) = apiStatus($msg);
		if(!$status) {
			logMsgPortal($LOG,$PROGRAM,'W',"No films returned for site '$id': $msg");
		}
		%films = apiData($msg);

		# Read the films for the site and print 1 page for each film
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

			# Open the XML data file
			open_file();

			# Open a container for the summary data
			$XML->startTag('record','id'=>'data');

			# Film details
			$XML->dataElement('title',$title);
			$XML->dataElement('start',$schedule);
			$XML->dataElement('duration',$duration);
			$XML->dataElement('channel',$channel);

			# Cast list
			@cast = split(/\n/,$credits);
			for(my $i=0; $i<@cast || $i<4; $i++) {
				$actor = ($cast[$i]) ? $cast[$i] : ' ';
				$XML->dataElement("cast$i",$actor);
			}

			# Show the film image (drawn from bottom left)
			$XML->dataElement('jacket',"$ROOT/../$CONFIG{PORTAL_META}/$provider/$assetcode/$assetcode-large.jpg");

			# Read the Certificate logo from the portal into the temporary directory, then add to the document
			$XML->dataElement('certificate',"$ROOT/../$CONFIG{IMAGE_TEMPLATE}/BBFC_$cert.jpg");

			# Close the container for the summary data
			$XML->endTag('record');

			# Close the XML data file
			close_file();

			# Generate PDF file with current inventory of films
			$file_pdf = "$ROOT/../$CONFIG{PORTAL_INVENTORY}/$sitecode/Smoovie\ Barker\ Channel$channel\ Slot$slot.pdf";
			$file_jpg = "$ROOT/../$CONFIG{PORTAL_INVENTORY}/$sitecode/Smoovie\ Barker\ Channel$channel\ Slot$slot.jpg";
			pdfReport($CONFFILE,$DATAFILE,$file_pdf);

			# Convert PDF file to JPEG file
			system("convert '$file_pdf' '$file_jpg'");
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Close the data file and the XML document that holds the document definitions
# ---------------------------------------------------------------------------------------------
sub close_file {
	$XML->endTag('dynamic');
	$XML->endTag('data');
	$XML->end();
	$FILEHANDLE->close();
}



# ---------------------------------------------------------------------------------------------
# Open the data file and the XML document that holds the document definitions
# ---------------------------------------------------------------------------------------------
sub open_file {
	open($FILEHANDLE,">$DATAFILE");
	$XML = new XML::Writer(OUTPUT => $FILEHANDLE);
	$XML->startTag('data');
	$XML->startTag('dynamic');
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
  Generate the background image for the barker channel for each Smoovie
  hotel, showing the film's large image, cast list, certificate log, title,
  duration and start times.

  One file is generated for each channel/slot in PDF and JPG format.

Usage :
  $PROGRAM

  OPTIONAL
  --log		If set, the results from the script will be written to the Airwave
			log directory, otherwise the results will be written to the screen.
	\n");
	exit;
}
