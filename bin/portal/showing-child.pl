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
	$ROOT = '/srv/visualsaas/instances/airwave/bin';
}

# Declare modules
use strict;
use warnings;

# System modules
use Getopt::Long;
use XML::Writer;
use Image::ExifTool qw(:Public);
use IO::File;

# Breato modules
use lib "$ROOT";
use mods::API qw(apiData apiStatus apiSelect);
use mods::Common qw(cleanNonUTF8 formatDateTime logMsg logMsgPortal readConfig);
use mods::PDF qw(pdfReport);

# Program information
our $PROGRAM = "showing.pl";
our $VERSION = "2.0";

# Check there are any arguments
if($#ARGV == -1) { usage(); }

# Read command line options
our($LOG,$LANGUAGE,$SHOWLOGO,$PACKAGE,$TERRCODE,$TERRNAME);
GetOptions (
	'log=s'			=> \$LOG,
	'language=s'	=> \$LANGUAGE,
	'logo=s'		=> \$SHOWLOGO,
	'package=s'		=> \$PACKAGE,
	'code=s'		=> \$TERRCODE,
	'name=s'		=> \$TERRNAME);

# Read the configuration parameters
our %CONFIG  = readConfig("$ROOT/etc/airwave-portal.conf");

# Airwave logo
our $LOGO = 'Airwave_Logo.jpg';

# Location of report configuration file
our $TEMP = "$CONFIG{TEMP}";
our $CONFFILE = "$ROOT/etc/showing.conf";
our $DATAFILE = "$TEMP/showing.xml";

# Report definitions
our %REPORT = (
			bbc =>  {
					sql		=> 'showingBBC',
					title	=> 'BBC Worldwide',
					order	=> 'asc',
			},
			disney =>  {
					sql		=> 'showingDisney',
					title	=> 'Disney',
					order	=> 'asc',
			},
			c18 =>  {
					sql		=> 'showingPBTV',
					genre	=> 'C18',
					title	=> 'Adult Soft Films',
					order	=> 'desc',
			},
			r18 =>  {
					sql		=> 'showingPBTV',
					genre	=> 'R18',
					title	=> 'Adult Explicit Films',
					order	=> 'desc',
			},
			current =>  {
					sql		=> 'showingCurrent',
					title	=> 'Hollywood Current Films',
					order	=> 'desc',
			},
			library =>  {
					sql		=> 'showingLibrary',
					title	=> 'Hollywood Library Films',
					order	=> 'desc',
			},
			new =>  {
					sql		=> 'showingNew',
					title	=> 'Hollywood Coming Soon',
					order	=> 'asc',
			},
);

# Start processing
film_package($TERRCODE,$TERRNAME,$PACKAGE);





# ---------------------------------------------------------------------------------------------
# Create a smaller image from an existing image
#
# Argument 1 : Territory reference
# Argument 2 : Territory name
# Argument 3 : Package reference
# ---------------------------------------------------------------------------------------------
sub film_package {
	my($ref,$terr,$pack) = @_;
	my($cond,$status,$msg);
	my %error = ();
	my %data = ();

	# Last argument for SQL depends on the type of content
	if($pack eq 'c18' || $pack eq 'r18') {
		$cond = "genre=$REPORT{$pack}{genre}";
	}
	else {
		$cond = "language=$LANGUAGE";
	}

	# Retrieve the data
	($msg) = apiSelect($REPORT{$pack}{sql},"territory=$ref",$cond);
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'W',"There are no $REPORT{$pack}{title} for $terr");
		return;
	}

	# Print the package or stop if there is no data
	logMsg($LOG,$PROGRAM,"===> $terr: $REPORT{$pack}{title}");
	%data = apiData($msg);
	if(%data) {
		film_page($pack,$REPORT{$pack}{title},$terr,\%data);
	}
	else {
		logMsg($LOG,$PROGRAM,"No $REPORT{$pack}{title} available for territory [$terr]");
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
# Print the films (4/page)
#
# Argument 1 : Film package reference
# Argument 2 : Film package name
# Argument 3 : Territory name
# Argument 4 : Hash of film data keyed by film name
# ---------------------------------------------------------------------------------------------
sub film_page {
	my($pack,$packname,$territory,$data_ref) = @_;
	my(@sorted,$fh,$xml,$pdffile);
	my($status,$msg,%error,%genre,$jacket,$image,$lang,$ok);
	my($provider,$film,$release,$duration,$cert,$title,$short,$full,$credits,$soundtracks,$subtitles,$credits_lab,$genres_lab,$duration_lab,$hdlogo,$genres);
	my %data = %$data_ref;

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
	$xml->dataElement('page-title1',$packname);
	$xml->dataElement('page-title2',$territory);
	$xml->dataElement('airwave-logo',"$ROOT/../$CONFIG{IMAGE_TEMPLATE}/$LOGO");
	$xml->dataElement('timestamp',formatDateTime('zm/cczy'));
	$xml->endTag('static');

	# Generate the dynamic XML data file which is used by the PDF printing module
	$xml->startTag('dynamic');
	foreach my $key (@sorted) {
		$provider = $data{$key}{'provider'};
		$film = $data{$key}{'asset_code'};
		$release = $data{$key}{'release_date'};
		$duration = $data{$key}{'duration'};
		$cert = $data{$key}{'certificate'};
		$title = $data{$key}{'title'};
		$short = $data{$key}{'summary'};
		$full = $data{$key}{'synopsis'};
		$credits = $data{$key}{'credits'};
		$soundtracks = $data{$key}{'languages'};
		$subtitles = $data{$key}{'subtitles'};
		$credits_lab = $data{$key}{'credits_label'};
		$genres_lab = $data{$key}{'genres_label'};
		$duration_lab = $data{$key}{'duration_label'};
		$hdlogo = $data{$key}{'quality'};
		$genres = $data{$key}{'genres'};

		# Assign values to undefined data
		$hdlogo = ($hdlogo) ? $hdlogo : 'SD';
		$short = ($short) ? $short : ' ';

		# Restore special characters
		$title =~ s/&amp;/&/g;
		$short =~ s/&amp;/&/g;
		$full =~ s/&amp;/&/g;

		# Replace commas and delimiters with @nl@ for the PDF generator
		$genres =~ s/,/\@nl\@/g;
		$credits =~ s/#nl#/\@nl\@/g;
		$credits =~ s/\\n/\@nl\@/g;
		$credits =~ s/\n/\@nl\@/g;

		# If image exists, create a scaled copy in the temporary directory
		$jacket = "$ROOT/../$CONFIG{IMAGE_JACKET}/$provider/$film.jpg";
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
		($ok,$full) = cleanNonUTF8($full);
		if(!$ok) {
			logMsgPortal($LOG,$PROGRAM,'W',"$film: Invalid character in synopsis: $full");
		}
		($ok,$credits) = cleanNonUTF8($credits);
		if(!$ok) {
			logMsgPortal($LOG,$PROGRAM,'W',"$film: Invalid character in cast list: $credits");
		}

		# Write the data record
		$xml->startTag('record','id'=>'data');
		$xml->dataElement('title',$title);
		$xml->dataElement('duration',$duration);
		if($hdlogo eq 'HD') {
			$xml->dataElement('hdlogo',"$ROOT/../$CONFIG{IMAGE_TEMPLATE}/HD_Logo.jpg");
		}
		else {
			$xml->dataElement('hdlogo',"$ROOT/../$CONFIG{IMAGE_TEMPLATE}/Blank.jpg");
		}
		$xml->dataElement('certificate',"$ROOT/../$CONFIG{IMAGE_TEMPLATE}/BBFC_$cert.jpg");
		$xml->dataElement('summary',$short);
		$xml->dataElement('synopsis',$full);
		$xml->dataElement('soundtracks',$soundtracks);
		$xml->dataElement('subtitles',$subtitles);
		$xml->dataElement('cast-head',$credits_lab);
		$xml->dataElement('cast-list',$credits);
		$xml->dataElement('genre-head',$genres_lab);
		$xml->dataElement('genre-list',$genres);
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
	$lang = $LANGUAGE;
	$lang =~ tr/a-z/A-Z/;
	$pdffile = "$territory - $packname ($lang).pdf";
	if(!-w $TEMP) {
		logMsgPortal($LOG,$PROGRAM,'E',"Can't open directory [$TEMP] for writing");
		exit;
	}

	# Generate the PDF file
	pdfReport($CONFFILE,$DATAFILE,"$ROOT/../$CONFIG{PORTAL_FILMS}/$territory/$pdffile");
	logMsg($LOG,$PROGRAM,"Created report '$CONFIG{PORTAL_FILMS}/$territory/$pdffile'");
}
