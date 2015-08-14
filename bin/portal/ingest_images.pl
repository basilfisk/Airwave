#!/usr/bin/perl
# *********************************************************************************************
# *********************************************************************************************
#
# Ingest the image files by making 3 different standard sized images from the jacket cover
# image, and 2 copies of the landscape image for AirTime.  Add the image details to the
# Content Image table.
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
use IO::File;
use Image::ExifTool qw(:Public);
use Data::Dumper;

# Breato modules
use lib "$ROOT";
use mods::API qw(apiData apiDML apiSelect apiStatus);
use mods::Common qw(formatDateTime logMsg logMsgPortal readConfig);

# Program information
our $PROGRAM = "ingest_images.pl";
our $VERSION = "1.0";

# Check there are any arguments
if($#ARGV == -1) { usage(); }

# Read command line options
our $FILM		= 'empty';
our $LOG		= 0;
if(!GetOptions(
	'film=s'		=> \$FILM,
	'log'			=> \$LOG,
	'help'			=> sub { usage(); } ))
	{ exit; }

# Read the configuration parameters
our %CONFIG  = readConfig("$ROOT/etc/airwave-portal.conf");

# Declare and initialise global variables
our %LISTVALUES;

# Start processing
main();





# ---------------------------------------------------------------------------------------------
# Process a single film or all films for a content provider
# ---------------------------------------------------------------------------------------------
sub main {
	my($msg,$status,%error,%films);
	logMsg($LOG,$PROGRAM,"=================================================================================");
	
	# Check that a film has been selected
	if($FILM =~ m/empty/) {
		logMsgPortal($LOG,$PROGRAM,'E',"ERROR: 'film' argument must have a value");
		return;
	}
	
	# Load a hash containing list values
	if(!read_listvalues()) {
		return;
	}
	
	# Start processing all films if a content provider has been specified
	if($FILM eq 'bbc' || $FILM eq 'pbtv' || $FILM eq 'uip') {
		# Read all active and delivered assets for selected provider
		($msg) = apiSelect('ingestFilmsProvider',"provider=$FILM");
		($status,%error) = apiStatus($msg);
		if(!$status) {
			logMsgPortal($LOG,$PROGRAM,'E',"Error reading records for [$FILM] from database: $error{MESSAGE}");
			return;
		}
		%films = apiData($msg);
		
		# Process each asset in selected class
		foreach $FILM (sort keys %films) {
			film_details($FILM);
		}
	}
	# Process a single film
	else {
		film_details($FILM);
	}
}



# ---------------------------------------------------------------------------------------------
# Retrieve film details (film must be active and delivered)
#
# Argument 1 : Asset code of the film
#
# Return array of data if film found or undefined if not
# ---------------------------------------------------------------------------------------------
sub film_details {
	my($film) = @_;
	my($status,$msg,%error,%film,$cid,$provider,$meta,$jacket,$landscape);
	
	# Read the film ID from the Portal
	($msg) = apiSelect('ingestFilm',"assetcode=$film");
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"Error reading details for [$film] from database: $error{MESSAGE}");
		return;
	}
	%film = apiData($msg);
	if(!%film) {
		# No film found on Portal
		logMsgPortal($LOG,$PROGRAM,'E',"No film matching [$film] - film must be active and delivered");
		return;
	}
	$cid = $film{$film}{'film_id'};
	$provider = $film{$film}{'provider'};
	
	# If requested film was found
	if($cid) {
		# Directories on Portal holding metadata and images are based on film provider of film
		$meta = "$ROOT/../$CONFIG{PORTAL_META}/$provider/$film";
		$jacket = "$ROOT/../$CONFIG{IMAGE_JACKET}/$provider";
		$landscape = "$ROOT/../$CONFIG{IMAGE_LANDSCAPE}/$provider";
		
		# Create the small images from the jacket image
		jacket_images($cid,$film,$meta,$jacket);
		
		# Create the AirPlay images from the landscape image
		landscape_images($cid,$film,$meta,$landscape);
	}
}



# ---------------------------------------------------------------------------------------------
# Create the small images from the jacket image
#
# Argument 1 : ID of the film
# Argument 2 : Asset code of the film
# Argument 3 : Directory on the Portal where the metadata is held
# Argument 4 : Directory on the Portal holding the jacket images
# ---------------------------------------------------------------------------------------------
sub jacket_images {
	my($cid,$film,$meta,$jacket) = @_;
	my($name);
	
	# Check jacket image available for this film
	$name = "$jacket/$film.jpg";
	if(!-f $name) {
		logMsgPortal($LOG,$PROGRAM,'E',"There is no jacket image for '$film'");
		return;
	}
	
	# Create the different image sizes
	jacket_image_create($cid,$film,$meta,$name,800,'full');
	jacket_image_create($cid,$film,$meta,$name,400,'large');
	jacket_image_create($cid,$film,$meta,$name,200,'small');
}



# ---------------------------------------------------------------------------------------------
# Create a smaller image from an existing image
#
# Argument 1 : ID of the film
# Argument 2 : Asset code of the film
# Argument 3 : Directory on the Portal where the metadata is held
# Argument 4 : Full name of jacket image file
# Argument 5 : Height of image (pixels)
# Argument 6 : Type of image being processes (full/large/small)
# ---------------------------------------------------------------------------------------------
sub jacket_image_create {
	my($cid,$film,$meta,$jacket,$high,$type) = @_;
	my($ref,@tags,$info,$value,%settings,$h,$w,$ratio,$wide,$size,$name,$result);
	
	# Read ALL the image characteristics
	$ref = new Image::ExifTool;
	$ref->ImageInfo($jacket,\@tags);
	
	# Image characteristics to be saved
	@tags = ('MIMEType','XResolution','YResolution','ResolutionUnit','ImageWidth','ImageHeight','FileSize');
	
	# Read and assign characteristics into a hash
	foreach my $tag (@tags) {
		$info = $ref->GetInfo($tag);
		$value = $info->{$tag};
		$settings{$tag} = $value;
	}
	
	# Use the height and width to create standard size 'large' and 'small' images
	$h = $settings{ImageHeight};
	$w = $settings{ImageWidth};
	if(!($h && $w)) {
		logMsgPortal($LOG,$PROGRAM,'E',"Error reading image height or width");
		return;
	}
	$ratio = $h/$w;
	$wide = int($high/$ratio);
	$size = "$wide"."x$high";
	
	# Create the image
	$name = "$film-$type.jpg";
	$result = `convert $jacket -resize $size $meta/$name`;
	if($result) {
		logMsgPortal($LOG,$PROGRAM,'E',"Error resizing image to $size: $result");
		return;
	}
	
	# Add image details to the Portal
	image_save($cid,$type,$name,$meta);
}



# ---------------------------------------------------------------------------------------------
# Create the AirPlay images from the landscape image
#
# Argument 1 : ID of the film
# Argument 2 : Asset code of the film
# Argument 3 : Directory on the Portal where the metadata is held
# Argument 4 : Directory on the Portal holding the landscape images
# ---------------------------------------------------------------------------------------------
sub landscape_images {
	my($cid,$film,$meta,$landscape) = @_;
	my($name);
	
	# Check landscape image available for this film
	$name = "$landscape/$film.jpg";
	if(!-f $name) {
		logMsgPortal($LOG,$PROGRAM,'E',"There is no landscape image for '$film'");
		return;
	}
	
	# Create the different image sizes
	`cp $name $meta/$film-hero.jpg`;
	`cp $name $meta/$film-landscape.jpg`;
	
	# Add image details to the Portal
	image_save($cid,'hero',"$film-hero.jpg",$meta);
	image_save($cid,'landscape',"$film-landscape.jpg",$meta);
}



# ---------------------------------------------------------------------------------------------
# Save the details of an image to the Portal
#
# Argument 1 : ID of the film
# Argument 2 : Type of image (full/large/small)
# Argument 3 : Name of image
# Argument 4 : Directory on the Portal where the metadata is held
# ---------------------------------------------------------------------------------------------
sub image_save {
	my($cid,$type,$name,$meta) = @_;
	my($ref,@tags,$info,$value,%settings,$high,$wide,$mime,$typeid,$msg,$status,%error,%data,$id);
	my $file = "$meta/$name";
	
	# Read ALL the image characteristics
	$ref = new Image::ExifTool;
	$ref->ImageInfo($file,\@tags);
	
	# Image characteristics to be saved
	@tags = ('MIMEType','XResolution','YResolution','ResolutionUnit','ImageWidth','ImageHeight','FileSize');
	
	# Read characteristics and create attributes
	foreach my $tag (@tags) {
		$info = $ref->GetInfo($tag);
		$value = $info->{$tag};
		$settings{$tag} = $value;
	}
	
	# Use the height and width to create standard size 'large' and 'small' images
	$high = $settings{ImageHeight};
	$wide = $settings{ImageWidth};
	$mime = $settings{MIMEType};
	if(!($high && $wide && $mime)) {
		logMsgPortal($LOG,$PROGRAM,'E',"Error reading image height, width or MIME type");
		return;
	}
	
	# Find ID of image type
	$typeid = $LISTVALUES{'Image Size'}{$type};
	
	# Does image already exist on Portal?
	($msg) = apiDML('ingestImageSearch',"cid=$cid","type=$typeid");
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"Error reading details of '$type' image for '$name': $error{MESSAGE}");
		return;
	}
	
	# Extract the image ID if a match has been found
	%data = apiData($msg);
	if (%data) {
		$id = $data{$cid.'-'.$typeid}{'id'};
	}
	
	# If new image, add the image attributes to the Portal
	if(!$id) {
		($msg) = apiDML('ingestImageInsert',"cid=$cid","name=$name","type=$typeid","height=$high","width=$wide","mimetype=$mime");
		($status,%error) = apiStatus($msg);
		if(!$status) {
			logMsgPortal($LOG,$PROGRAM,'E',"Could not add the '$type' image: $error{MESSAGE}");
		}
		else {
			logMsg($LOG,$PROGRAM,"Image '$type' has been added");
		}
	}
	# If image already exists, update the image attributes on the Portal
	else {
		($msg) = apiDML('ingestImageUpdate',"id=$id","name=$name","type=$typeid","height=$high","width=$wide","mimetype=$mime");
		($status,%error) = apiStatus($msg);
		if(!$status) {
			logMsgPortal($LOG,$PROGRAM,'E',"Could not update the '$type' image: $error{MESSAGE}");
		}
		else {
			logMsg($LOG,$PROGRAM,"Image '$type' has been updated");
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Create a hash of hashes holding list values
#
# Return 1 if data read successfully, 0 if error raised
# ---------------------------------------------------------------------------------------------
sub read_listvalues {
	my($status,$msg,%error,%data,$group,$item);
	
	# Read PIDs
	($msg) = apiSelect('ingestListValues');
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"No list values returned: $error{MESSAGE}");
		return 0;
	}
	%data = apiData($msg);
	
	# Create hash
	foreach my $id (keys %data) {
		$LISTVALUES{$data{$id}{'type'}}{$data{$id}{'value'}} = $id;
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
  Ingest the image files by making 3 different standard sized images from the jacket cover
  image, and 2 copies of the landscape image for AirTime.  Add the image details to the
  Content Image table.

Usage :
  $PROGRAM --film=<code>
  
  MANDATORY
  --film=<code>        The reference of a single film on the Portal.
  
  OPTIONAL
  --log                 If set, the results from the script will be written to the Airwave
                        log directory, otherwise the results will be written to the screen.
	\n");

	# Quit
	exit;
}


