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

# Declare modules
use strict;
use warnings;

# System modules
use Data::Dumper;
use Getopt::Long;
use XML::Writer;
use Image::ExifTool qw(:Public);
use IO::File;

# Breato modules
use lib "$ENV{'AIRWAVE_ROOT'}";
use mods::API3 qw(apiData apiStatus apiSelect);
use mods::Common qw(cleanNonUTF8 formatDateTime logMsg logMsgPortal readConfig);
use mods::PDF qw(pdfReport);

# Program information
our $PROGRAM = "showing-airtime.pl";
our $VERSION = "1.0";

# Check there are any arguments
if($#ARGV == -1) { usage(); }

# Read command line options
our $LOG		= 0;
our $LANGUAGE	= 'en';
GetOptions (
	'log'			=> \$LOG,
	'language=s'	=> sub { $LANGUAGE =~ tr/A-Z/a-z/; },
	'help'			=> sub { usage(); } );

# Read the configuration parameters
our %CONFIG  = readConfig("$ENV{'AIRWAVE_ROOT'}/etc/airwave.conf");

# AirTime logo and footer
our %IMAGES;
$IMAGES{header} = 'airtime_logo_thumbnail.jpg';
$IMAGES{footer} = 'airtime_app_logo_thumbnail.jpg';

# Location of report configuration file
our $TEMP = "$CONFIG{TEMP}";
our $CONFFILE = "$ENV{'AIRWAVE_ROOT'}/etc/showing-airtime.conf";
our $DATAFILE = "$ENV{'AIRWAVE_ROOT'}/showing-airtime.xml";

# Report definitions
our %REPORT = (
			current =>  {
					sql		=> 'airtimeCurrent',
					title	=> 'Current Titles',
					order	=> 'desc',
			}
);

# Start processing
main();





# ---------------------------------------------------------------------------------------------
# Start processing
# ---------------------------------------------------------------------------------------------
sub main {
	# Initialize local variables
	my($status,$msg,%error,%territories,$terrcode,%data,$terrname,$title);

	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");
	logMsg($LOG,$PROGRAM,"Generating the AirTime Marketing Sheets");

	# Return a hash of Airtime site
	($msg) = apiSelect('airtimeTerritories');
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"No territories returned from database [$error{CODE}] $error{MESSAGE}");
		exit;
	}
	%territories = apiData($msg);

	# Produce report for each territory
	for $terrcode (sort keys %territories) {
		$terrname = $territories{$terrcode}{name};
		$title = $REPORT{current}{title};

		# Retrieve the data
		($msg) = apiSelect($REPORT{current}{sql},"territory=$terrcode","language=$LANGUAGE");
		($status,%error) = apiStatus($msg);
		if(!$status) {
			logMsgPortal($LOG,$PROGRAM,'W',"There are no $title for territory '$terrcode' and language '$LANGUAGE'");
			exit;
		}

		# Print the report if there is any data
		logMsg($LOG,$PROGRAM,"===> $terrname: $title");
		%data = apiData($msg);
		if(%data) {
			film_page('current',$terrcode,$terrname,\%data);
		}
		else {
			logMsg($LOG,$PROGRAM,"No $title available for site $terrname");
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Create a smaller image from an existing image
#
# Argument 1 : Asset reference
# Argument 2 : Full name of image file
#
# Return the name of the new image
# ---------------------------------------------------------------------------------------------
sub film_image_resize {
	my($assetcode,$file) = @_;
	my($ref,@tags,$info,$value,%settings,$h,$w,$ratio,$wide,$size,$result);
	my $high = 200;
	my $image = "$assetcode-show.jpg";

	# Skip if file already processed or image not downloaded
	if(!-e "$TEMP/$image") {
		# Read ALL the image characteristics
		$ref = new Image::ExifTool;
		$ref->ImageInfo($file,\@tags);

		# Image characteristics to be saved
		@tags = ('MIMEType','XResolution','YResolution','ResolutionUnit','ImageWidth','ImageHeight','FileSize');

		# Read and assign characteristics into a hash
		foreach my $tag (@tags) {
			$info = $ref->GetInfo($tag);
			$value = $info->{$tag};
			$settings{$tag} = $value;
		}

		# Use the height and width to create a smaller image
		$h = $settings{ImageHeight};
		$w = $settings{ImageWidth};
		if(!($h && $w)) {
			logMsgPortal($LOG,$PROGRAM,'W',"Can't read image height or width for '$assetcode'");
		}
		# Resize the image
		else {
			$ratio = $h/$w;
			$wide = int($high/$ratio);
			$size = "$wide"."x$high";
			$result = `convert $file -resize $size $TEMP/$image`;
			if($result) {
				logMsgPortal($LOG,$PROGRAM,'W',"Can't resize image to '$size' for '$assetcode': $result");
			}
		}
	}

	# Return the name of the new image
	return $image;
}



# ---------------------------------------------------------------------------------------------
# Print the films (9/page)
#
# Argument 1 : Film package reference
# Argument 2 : Territory code
# Argument 3 : Territory name
# Argument 4 : Hash of film data keyed by film name
# ---------------------------------------------------------------------------------------------
sub film_page {
	my($pack,$terrcode,$terrname,$data_ref) = @_;
	my(@sorted,$fh,$xml);
	my($status,$msg,%error,%genre,$jacket,$image,$ok);
	my($pdffile,$provider,$film,$duration,$cert,$title,$short,$credits,$soundtracks,$genres);
	my %data = %$data_ref;

	# Force language code to upper case and form PDF file name
	$pdffile = $terrcode.'_'.$LANGUAGE.'_'.$REPORT{$pack}{title}.'.pdf';
	$pdffile =~ s/ /_/g;
	$pdffile =~ tr/A-Z/a-z/;

	# Sort order
	if($REPORT{$pack}{order} eq 'asc') {
		@sorted = sort keys %data;
	}
	else {
		@sorted = sort {$b cmp $a} keys %data;
	}

	# Create a new XML file, but only if existing file (from last run) is writeable
	open($fh,">$DATAFILE");

	# Open the XML document and create the container elements
	$xml = new XML::Writer(OUTPUT => $fh);
	$xml->startTag('data');

	# Generate the static XML data file which is used by the PDF printing module
	$xml->startTag('static');
	$xml->dataElement('page-title1',$REPORT{$pack}{title});
	$terrname =~ tr/a-z/A-Z/;
	$xml->dataElement('page-title2',$terrname);
	$xml->dataElement('airtime-header',"$ENV{'AIRWAVE_ROOT'}/../$CONFIG{IMAGE_TEMPLATE}/$IMAGES{header}");
	$xml->dataElement('airtime-footer',"$ENV{'AIRWAVE_ROOT'}/../$CONFIG{IMAGE_TEMPLATE}/$IMAGES{footer}");
	$xml->dataElement('timestamp',formatDateTime('zm/cczy'));
	$xml->endTag('static');

	# Generate the dynamic XML data file which is used by the PDF printing module
	$xml->startTag('dynamic');
	foreach my $key (@sorted) {
		$provider = $data{$key}{'provider'};
		$film = $data{$key}{'filmcode'};
		$duration = $data{$key}{'duration'};
		$cert = $data{$key}{'certificate'};
		$title = $data{$key}{'title'};
		$short = $data{$key}{'summary'};
		$credits = $data{$key}{'credits'};
		$soundtracks = $data{$key}{'languages'};
		$genres = $data{$key}{'genres'};

		# Assign values to undefined data
		$short = ($short) ? $short : ' ';

		# Restore special characters
		$title =~ s/&amp;/&/g;
		$short =~ s/&amp;/&/g;

		# Replace commas and delimiters with @nl@ for the PDF generator
		$genres =~ s/,/\@nl\@/g;
		$credits =~ s/#nl#/\@nl\@/g;
		$credits =~ s/\\n/\@nl\@/g;
		$credits =~ s/\n/\@nl\@/g;

		# If image exists, create a scaled copy in the temporary directory
		$jacket = "$ENV{'AIRWAVE_ROOT'}/../$CONFIG{IMAGE_JACKET}/$provider/$film.jpg";
		if(-e $jacket) {
			$image = film_image_resize($film,$jacket);
		}
		else {
			logMsgPortal($LOG,$PROGRAM,'W',"Can't find image '$CONFIG{IMAGE_JACKET}/$provider/$film.jpg' for $title");
		}

		# Clean up invalid characters in text fields
		($ok,$title) = cleanNonUTF8($title);
		if(!$ok) {
			logMsgPortal($LOG,$PROGRAM,'W',"$film: Invalid character in title: $title");
		}
		($ok,$short) = cleanNonUTF8($short);
		if(!$ok) {
			logMsgPortal($LOG,$PROGRAM,'W',"$film: Invalid character in summary: $short");
		}
		($ok,$credits) = cleanNonUTF8($credits);
		if(!$ok) {
			logMsgPortal($LOG,$PROGRAM,'W',"$film: Invalid character in cast list: $credits");
		}

		# Write the data record
		$xml->startTag('record','id'=>'data');
		$title =~ tr/a-z/A-Z/;
		$xml->dataElement('title',$title);
		$xml->dataElement('duration',$duration);
		$xml->dataElement('certificate',"$ENV{'AIRWAVE_ROOT'}/../$CONFIG{IMAGE_TEMPLATE}/BBFC_$cert.jpg");
		$xml->dataElement('summary',$short);
		$xml->dataElement('soundtracks',$soundtracks);
		$xml->dataElement('cast',$credits);
		$xml->dataElement('genre',$genres);
		if($image && -f "$TEMP/$image") {
			$xml->dataElement('image-small',"$TEMP/$image");
		}
		$xml->endTag('record');
	}
	$xml->endTag('dynamic');

	# Close the containers, then close the XML file
	$xml->endTag('data');
	$xml->end();
	$fh->close();

	# Create the PDF, but check if existing file (from previous run) is writeable
	if(!-w $TEMP) {
		logMsgPortal($LOG,$PROGRAM,'E',"Can't open directory [$TEMP] for writing");
		exit;
	}

	# Generate the PDF file
	pdfReport($CONFFILE,$DATAFILE,"$ENV{'AIRWAVE_ROOT'}/../$CONFIG{AIRTIME_OUTPUT}/$pdffile");
	logMsg($LOG,$PROGRAM,"Created report '$CONFIG{AIRTIME_OUTPUT}/$pdffile'");
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
#		logMsg($LOG,$PROGRAM,"The 'package' argument must be present");
	}
	else {
		printf("
Program : $PROGRAM
Version : v$VERSION
Author  : Basil Fisk (c)2016 Airwave Ltd

Summary :
  Generate the point of sales literature for all AirTime sites as PDF files.
  Each report is written to the Airwave Portal.

Usage :
  $PROGRAM --language=<code> --log

  MANDATORY
    None

  OPTIONAL
  --language=<code>		The language code for the film synopses.
						If this argument is not specified, English will be used.
  --log					If set, the results from the script will be written to the Airwave
						log directory, otherwise the results will be written to the screen.
		\n");
	}

	# Stop in all cases
	exit;
}
