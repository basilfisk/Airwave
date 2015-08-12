#!/usr/bin/perl
# *********************************************************************************************
# *********************************************************************************************
#
#  Check the film and trailer files in the specified batch (directory) and generate a
#  metadata file for the film containing film details read from the Portal and structural
#  information about the film and trailer files. The metadata file will be created in the
#  batch directory with the name of the film and a '.xml' file extension.  The image files
#  for the film will also be downloaded from the Portal so their details can be included
#  in the metadata file.
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
use Digest::MD5;
use Getopt::Long;
use IO::File;
use Image::ExifTool qw(:Public);
use XML::Writer;

# Breato modules
use lib "$ROOT";
use mods::API qw(apiData apiDML apiMessage apiSelect apiStatus);
use mods::Common qw(cleanNonUTF8 formatDateTime logMsg logMsgPortal md5Generate parseDocument portalDownload portalUpload readConfig);

# Program information
our $PROGRAM = "ingest_film.pl";
our $VERSION = "2.0";

# Check there are any arguments
if($#ARGV == -1) { usage(); }

# Read command line options
our $ACTION		= 'empty';
our $ASSET		= 'empty';
our $ASSETTYPE	= 'empty';
our $BATCH		= 'empty';
our $FILE		= 'empty';
our $QUALITY	= 'empty';
our $ALLFILMS	= 0;
our $LOG		= 0;
our $TEST		= 0;
if(!GetOptions(
	'action=s'		=> \$ACTION,		# ingest/refresh
	'asset=s'		=> \$ASSET,			# asset code
	'batch=s'		=> \$BATCH,			# name of WIP directory holding asset
	'file=s'		=> \$FILE,			# name of asset file
	'type=s'		=> \$ASSETTYPE,		# film/trailer
	'quality=s'		=> \$QUALITY,		# hd/sd
	'allfilms'		=> \$ALLFILMS,
	'log'			=> \$LOG,
	'test'			=> \$TEST,
	'help'			=> sub { usage(); } ))
	{ exit; }

# Read the configuration parameters and check that parameters have been read
our %CONFIG  = readConfig("$ROOT/etc/airwave.conf");

# Declare and initialise global variables
our($XML,$HANDLE,%AUDIO_PIDS,%SUB_PIDS,%VIDEO_PIDS,%LISTVALUES,%STREAMS,$ERROR,$REPO_DIR);
our %ASSETINFO = ();
our %ASSETSTREAMS = ();


# Files that will hold output from the tests
our $MPLAY_OUT = "$CONFIG{TEMP}/mplayer.txt";
our $MPLAY_ERR = "$CONFIG{TEMP}/mplayer.err";
our $MPGTX_OUT = "$CONFIG{TEMP}/mpgtx.txt";
our $MPGTX_ERR = "$CONFIG{TEMP}/mpgtx.err";

# Start processing
main();





# ---------------------------------------------------------------------------------------------
# Process a single asset or all assets for a content provider
# ---------------------------------------------------------------------------------------------
sub main {
	my($meta,$image,$cid,$aid,$provider,$status,$msg,%error,%assets);
	logMsg($LOG,$PROGRAM,"=================================================================================");
	
	# Check the arguments
	if($ACTION !~ m/^(ingest|refresh)$/) { error("ERROR: 'action' must be ingest or refresh"); };
	if($ASSET =~ m/empty/) { error("ERROR: 'asset' must have a value"); };
	if($ACTION eq 'ingest') {
		if($ASSETTYPE !~ m/^(film|trailer)$/) { error("ERROR: 'type' must be film or trailer"); };
		if($QUALITY !~ m/^(hd|sd)$/) { error("ERROR: 'quality' must be sd or hd"); };
		if($BATCH =~ m/empty/) { error("ERROR: 'batch' must have a value"); };
		if($FILE =~ m/empty/) { error("ERROR: 'file' must have a value"); };
	}
	
	# Load a set of hashes containing stream information, list values and stream data
	read_pids();
	read_listvalues();
	read_streams();
	
	# Ingest a single film
	if($ACTION eq 'ingest') {
		($cid,$aid,$provider,$meta,$image) = asset_id();
		ingest_asset($meta,$image,$cid,$aid,$provider);
	}
	# Recreate the metadata for a single film or all films for a content provider
	else {
		# Start processing a batch of assets if a content provider has been specified
		if($ALLFILMS) {
			# Read all active and delivered assets for selected provider
			($msg) = apiSelect('ingestFilmsProvider',"provider=$ASSET");
			($status,%error) = apiStatus($msg);
			if(!$status) {
				error("Error reading records for [$ASSET] from database: $error{MESSAGE}");
			}
			%assets = apiData($msg);
			
			# Process each asset in selected class
			foreach $ASSET (sort keys %assets) {
				($cid,$provider,$meta,$image) = film_id();
				generate_metadata($meta,$image,$cid);
			}
		}
		# Process a single asset
		else {
			($cid,$provider,$meta,$image) = film_id();
			generate_metadata($meta,$image,$cid);
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Retrieve asset details (film must be active and delivered)
#
# Return an array holding content ID, asset ID, provider code, metadata and image directories
# ---------------------------------------------------------------------------------------------
sub asset_id {
	my($status,$msg,%error,%film,$cid,$aid,$provider,$meta,$image);
	
	# Read the film and asset IDs from the Portal
	($msg) = apiSelect('ingestFilmAsset',"assetcode=$ASSET","assettype=$ASSETTYPE","quality=$QUALITY");
	($status,%error) = apiStatus($msg);
	if(!$status) {
		error("Error reading details for [$ASSET] from database: $error{MESSAGE}");
	}
	%film = apiData($msg);
	if(!%film) {
		# No film found on Portal
		error("No film matching [$ASSET] - film must be active and delivered");
	}
	($cid,$aid,$provider) = @{$film{$ASSET}};
	
	# Directories on Portal holding metadata and images are based on content provider of film
	$meta = "$CONFIG{PORTAL_META}/$provider";
	$image = "$CONFIG{IMAGE_JACKET}/$provider";
	
	# Check content provider's directory exists
	if(!-d "$CONFIG{CS_ROOT}/$provider") {
		error("No directory for content provider [$CONFIG{CS_ROOT}/$provider]");
	}
	
	# Setup the path to the asset in the repository
	$REPO_DIR = "$CONFIG{CS_ROOT}/$provider/$ASSET";
	
	# Return the asset details
	return ($cid,$aid,$provider,$meta,$image);
}



# ---------------------------------------------------------------------------------------------
# Error message for parameter checks
# ---------------------------------------------------------------------------------------------
sub error {
	my($msg) = @_;
	logMsg($LOG,$PROGRAM,$msg);
	exit;
}



# ---------------------------------------------------------------------------------------------
# Retrieve film details (film must be active and delivered)
#
# Return an array holding content ID, provider code, metadata and image directories
# ---------------------------------------------------------------------------------------------
sub film_id {
	my($status,$msg,%error,%film,$cid,$provider,$meta,$image);
	
	# Read the film ID from the Portal
	($msg) = apiSelect('ingestFilm',"assetcode=$ASSET");
	($status,%error) = apiStatus($msg);
	if(!$status) {
		error("Error reading details for [$ASSET] from database: $error{MESSAGE}");
	}
	%film = apiData($msg);
	if(!%film) {
		# No film found on Portal
		error("No film matching [$ASSET] - film must be active and delivered");
	}
	($cid,$provider) = @{$film{$ASSET}};
	
	# Directories on Portal holding metadata and images are based on content provider of film
	$meta = "$CONFIG{PORTAL_META}/$provider";
	$image = "$CONFIG{IMAGE_JACKET}/$provider";
	
	# Check content provider's directory exists
	if(!-d "$CONFIG{CS_ROOT}/$provider") {
		error("No directory for content provider [$CONFIG{CS_ROOT}/$provider]");
	}
	
	# Setup the path to the asset in the repository
	$REPO_DIR = "$CONFIG{CS_ROOT}/$provider/$ASSET";
	
	# Return the asset details
	return ($cid,$provider,$meta,$image);
}



# ---------------------------------------------------------------------------------------------
# Generate the metadata for the content
#
# Argument 1 : Directory on Portal holding metadata of the film
# Argument 2 : Directory on Portal holding images for the film
# Argument 3 : ID of the content
# ---------------------------------------------------------------------------------------------
sub generate_metadata {
	my($meta,$image,$cid) = @_;
	my($dir,$file,$rc);
	
	# Create in repository, unless running in test mode
	$dir = ($TEST) ? "$CONFIG{TEMP}" : $REPO_DIR;
	$file = "$dir/$ASSET.xml";
	logMsg($LOG,$PROGRAM,"Creating XML metadata file [$file]");
	
	# Create the metadata file for the film
	document_header($file);
	
	# Generate film details using data from the Portal
	film_details();
	film_images($meta,$image);
	film_clearances();
	film_genres();
	film_synopses();
	film_assets($cid);
	
	# Close the metadata file
	document_footer();
	
	# Validate the metadata file and stop if any errors found
	$rc = validate_xml_file($file);
	if($rc == 2) {
		error("Validation of XML metadata raised errors. Metadata file will not be uploaded to the Portal");
	}
	
	# Upload the metadata file
	upload_metadata($meta);
}



# ---------------------------------------------------------------------------------------------
# Ingest a single asset
#
# Argument 1 : Directory on Portal holding metadata of the film
# Argument 2 : Directory on Portal holding images for the film
# Argument 3 : ID of the content
# Argument 4 : ID of the asset
# Argument 5 : Provider of the content
# ---------------------------------------------------------------------------------------------
sub ingest_asset {
	my($meta,$image,$cid,$aid,$provider) = @_;
	my($new,$prefix,$msg,$type,$file,$dh,@dirfiles);
	my $filename = "$CONFIG{CS_DOWNLOAD}/$BATCH/$FILE";
	
	# 1 if new asset, 0 if existing asset
	$new = ($aid) ? 0 : 1;
	
	# Prefix for messages when run in test mode
	$prefix = ($TEST) ? 'TEST: ' : '';
	
	# Start up message for asset
	$msg = ($new) ? "Loading new" : "Updating";
	logMsg($LOG,$PROGRAM,$prefix."$msg $ASSETTYPE file for [$ASSET]");
	
	# Analyze film then update Portal
	$provider =~ tr[A-Z][a-z];
	asset_analyze($provider,$filename);
	update_portal($provider,$cid);
	
	# Create Content Repository directory to hold asset files (but not in test mode)
	if(!-d $REPO_DIR) {
		logMsg($LOG,$PROGRAM,$prefix."Creating asset directory [$REPO_DIR]");
		if(!$TEST) {
			system("mkdir -p $REPO_DIR");
		}
	}
	
	# If existing asset is being updated, move existing asset file to trash
	if(!$new) {
		if(!$TEST) {
			$type = ($QUALITY eq 'hd') ? 'mp4' : 'mpg';
			$file = ($ASSETTYPE eq 'film') ? "_ts" : "_ts_trailer";
			opendir($dh,$REPO_DIR);
			@dirfiles = readdir($dh);
			closedir($dh);
			@dirfiles = grep { /$file\.$type/ } @dirfiles;
			foreach my $filename (@dirfiles) {
				logMsg($LOG,$PROGRAM,"Moving $ASSETTYPE file [$REPO_DIR/$filename] to [$CONFIG{CS_TRASH}]");
				system("mv $REPO_DIR/$filename $CONFIG{CS_TRASH}");
			}
		}
	}
	
	# Move new asset file to film directory in Repository
	$file = "$CONFIG{CS_DOWNLOAD}/$BATCH/$FILE";
	logMsg($LOG,$PROGRAM,$prefix."New $ASSETTYPE file [$file] moved to [$REPO_DIR/$ASSETINFO{'FILE'}{'NAME'}]");
	if(!$TEST) {
		system("mv $file $REPO_DIR/$ASSETINFO{'FILE'}{'NAME'}");
	}
	
	# If empty, move download directory to 'trash' directory
	opendir($dh,"$CONFIG{CS_DOWNLOAD}/$BATCH");
	@dirfiles = readdir($dh);
	closedir($dh);
	@dirfiles = grep { !/^\./ } @dirfiles;
	if(!@dirfiles) {
		logMsg($LOG,$PROGRAM,$prefix."Moving download directory [$CONFIG{CS_DOWNLOAD}/$BATCH] to [$CONFIG{CS_TRASH}]");
		if(!$TEST) {
			system("mv $CONFIG{CS_DOWNLOAD}/$BATCH $CONFIG{CS_TRASH}");
		}
	}
	
	# Set ingest date on Portal, then generate metadata file and upload to Portal
	if(!$TEST) {
		update_ingest_date($cid);
		generate_metadata($meta,$image,$cid);
	}
}





# =============================================================================================
# =============================================================================================
#
# STREAM DATA EXTRACTION AND FORMATTING FUNCTIONS
#
# =============================================================================================
# =============================================================================================

# ---------------------------------------------------------------------------------------------
# Generate a standard Airwave file name
#
# Argument 1 : Name of file (without extension)
# Argument 2 : Hash of language PIDs
#
# Return the standard Airwave file name
# ---------------------------------------------------------------------------------------------
sub airwave_filename {
	my($filename,%langs) = @_;
	my $new_name = $ASSET;
	
	# Check that languages exist
	if(!%langs) {
		error("Error: At least 1 audio soundtrack must exist");
	}
	
	# Add languages to the file name
	foreach my $code (sort keys %langs) {
		$new_name .= "_$code";
	}
	
	# Add the suffix
	$new_name .= ($ASSETTYPE eq 'trailer') ? "_ts_trailer" : "_ts";
	$new_name .= ($ASSETINFO{'STREAM'}{'CODING'} eq 'mpeg2') ? ".mpg" : ".mp4";
	
	# Return the new name
	return $new_name;
}



# ---------------------------------------------------------------------------------------------
# Capture details of each file related to the asset and store in hashes
#
# Argument 1 : Provider of the content
# Argument 2 : Full file name and path of the file to be ingested
#
# The following values are loaded into the hashes
#
#	F1: $ASSETINFO{'FILE'}{'NAME'}				New file name, based on asset code and streams within the file (no path)
#	F2: $ASSETINFO{'FILE'}{'SIZE'}				Size of file in bytes
#	F3: $ASSETINFO{'FILE'}{'PROGNO'}			Programme number (not too sure what this is)
#	F4: $ASSETINFO{'FILE'}{'STREAMS'}			Number of streams in the file
#	F5: $ASSETINFO{'FILE'}{'MD5SUM'}			MD5 checksum for file
#
#	S1: $ASSETINFO{'STREAM'}{'CODING'}			Stream encoding mechanism (mpeg2,mpeg4)
#	S2: $ASSETINFO{'STREAM'}{'TYPE'}			Stream encoding type (transport)
#
#	V1: $ASSETINFO{'VIDEO'}{'FRAMESIZE'}		Frame size for ALL video streams
#	V2: $ASSETINFO{'VIDEO'}{'FRAMERATE'}		Frame rate for ALL video streams
#	V3: $ASSETINFO{'VIDEO'}{'ENCODERATE'}		Bit rate at which ALL video streams were encoded
#	V4: $ASSETINFO{'VIDEO'}{'ASPECTRATIO'}		Aspect ratio for ALL video streams
#	V5: $ASSETINFO{'VIDEO'}{'CODEC'}			Video stream codec (mpeg2/h264)
#
#	A1: $ASSETINFO{'AUDIO'}{'SAMPLERATE'}		Bit rate at which ALL audio streams were encoded
#	A2: $ASSETINFO{'AUDIO'}{'CHANNELS'}			Number of channels on ALL audio streams
#	A3: $ASSETINFO{'AUDIO'}{'ENCODERATE'}		Bit rate at which ALL audio streams were encoded
#	A4: $ASSETINFO{'AUDIO'}{'CODEC'}			Audio stream codec (mpeg1,aac)
#
#	P1: $ASSETSTREAMS{$pid}{'TYPE'}				Type of stream (audio/video/subtitle)
#	P2: $ASSETSTREAMS{$pid}{'CODEC'}			Stream codec (video=from V5, audio=from A4, stream=data)
#	P3: $ASSETSTREAMS{$pid}{'LANGUAGE'} 		(@{$AUDIO_PIDS{"$provider-$ASSETSTREAMS{$pid}{'CODEC'}-$pid"}})[3]
#												(@{$SUB_PIDS{"$provider-$ASSETSTREAMS{$pid}{'CODEC'}-$pid"}})[3]
#	P4: $ASSETSTREAMS{$pid}{'SAMPLERATE'}		From A1
#	P5: $ASSETSTREAMS{$pid}{'CHANNELS'}			From A2
#	P6: $ASSETSTREAMS{$pid}{'ENCODERATE'}		From A3
#	P7: $ASSETSTREAMS{$pid}{'FRAMESIZE'}		From V1
#	P8: $ASSETSTREAMS{$pid}{'FRAMERATE'}		From V2
#	P9: $ASSETSTREAMS{$pid}{'ENCODERATE'}		From V3
#	P0: $ASSETSTREAMS{$pid}{'ASPECTRATIO'}		From V4
# ---------------------------------------------------------------------------------------------
sub asset_analyze {
	my($provider,$filename) = @_;
	my($prefix,$fh,$line,@data,$item,$width,$height,$pid,%langs,$lang,$vpid,@apids);
	
	# Prefix for messages when run in test mode
	$prefix = ($TEST) ? 'TEST: ' : '';
	
	# Start processing
	logMsg($LOG,$PROGRAM,$prefix."Processing file [$filename]");
	
	# Size of file
	$ASSETINFO{'FILE'}{'SIZE'} = -s $filename;
	
	# Log file that is being processed
	logMsg($LOG,$PROGRAM,$prefix."Examining $ASSETTYPE file [$filename] : $ASSETINFO{'FILE'}{'SIZE'} Bytes");
	
	# Reset hash of discovered languages
	%langs = ();
	
	# ---------------------------------------
	# MPLAYER - Collect general information
	# ---------------------------------------
	# Run mplayer to extract details of active video and audio streams
	system("mplayer -identify -frames 0 -vo null -ao null $filename 2> $MPLAY_ERR > $MPLAY_OUT");
	
	# Only transport streams are valid
	@data = asset_read_array('TS file format detected',$MPLAY_OUT);
	if(scalar(@data) == 4) {
		$ASSETINFO{'STREAM'}{'TYPE'} = 'transport';
	}
	else {
		error("Only transport streams are supported");
	}
	
	# Read video stream codec (mpeg2,h264) - stop if neither of these
	@data = asset_read_array('PROGRAM N.',$MPLAY_OUT);
	($item) = split('\(',$data[1]);
	$item =~ tr[A-Z][a-z];
	if($item ne 'mpeg2' && $item ne 'h264') {
		error("Unsupported video codec '$item'");
	}
	$ASSETINFO{'VIDEO'}{'CODEC'} = $item;
	
	# Check video codec matches quality selected by user
	if(!(($item eq 'mpeg2' && $QUALITY eq 'sd') || ($item eq 'h264' && $QUALITY eq 'hd'))) {
		error("Video codec '$item' does not match quality selected by user '$QUALITY'");
	}
	
	# Set stream coding (mpeg2/4) based on video coded detected
	$ASSETINFO{'STREAM'}{'CODING'} = ($ASSETINFO{'VIDEO'}{'CODEC'} eq 'h264') ? 'mpeg4' : 'mpeg2';
	
	# Read audio stream codec (mpeg1,aac) - convert mpa to mpeg1
	@data = asset_read_array('PROGRAM N.',$MPLAY_OUT);
	($item) = split('\(',$data[3]);
	$item =~ tr[A-Z][a-z];
	$item = ($item eq 'mpa') ? 'mpeg1' : $item;
	if($item ne 'mpeg1' && $item ne 'aac') {
		error("Unsupported audio codec '$item'");
	}
	$ASSETINFO{'AUDIO'}{'CODEC'} = $item;
	
	# Read program number
	@data = asset_read_array('PROGRAM N.',$MPLAY_OUT);
	$ASSETINFO{'FILE'}{'PROGNO'} = pop(@data);
	
	# Video framesize
	$width = asset_read_value('ID_VIDEO_WIDTH',$MPLAY_OUT);
	$height = asset_read_value('ID_VIDEO_HEIGHT',$MPLAY_OUT);
	$ASSETINFO{'VIDEO'}{'FRAMESIZE'} = $width.'x'.$height;
	
	# Video aspect ratio
	if($ASSETINFO{'STREAM'}{'CODING'} eq 'mpeg2') {
		@data = asset_read_array('(aspect',$MPLAY_OUT);
		$item = $data[4];
		$item =~ s/\)//;
		if($item == 3) {
			$ASSETINFO{'VIDEO'}{'ASPECTRATIO'} = '16:9';
		}
		elsif($item == 2) {
			$ASSETINFO{'VIDEO'}{'ASPECTRATIO'} = '4:3';
		}
		elsif(int(100*$width/$height) == 177) {
			$ASSETINFO{'VIDEO'}{'ASPECTRATIO'} = '16:9';
		}
		else {
			$ASSETINFO{'VIDEO'}{'ASPECTRATIO'} = '16:9';
		}
	}
	else {
		if(int(100*$width/$height) == 177) {
			$ASSETINFO{'VIDEO'}{'ASPECTRATIO'} = '16:9';
		}
		else {
			$ASSETINFO{'VIDEO'}{'ASPECTRATIO'} = int(100*$width/$height)/100;
		}
	}
	
	# Video frame rate and encoding rate
	$item = asset_read_value('ID_VIDEO_FPS',$MPLAY_OUT);
	$ASSETINFO{'VIDEO'}{'FRAMERATE'} = int($item);
	$item = asset_read_value('ID_VIDEO_BITRATE',$MPLAY_OUT);
	$item = ($item) ? $item : '0';
	$ASSETINFO{'VIDEO'}{'ENCODERATE'} = int($item/1000);
	
	# Audio encoding information is taken from the header, and is assumed to be the same for all streams!
	$item = asset_read_value('ID_AUDIO_RATE',$MPLAY_OUT);
	$ASSETINFO{'AUDIO'}{'SAMPLERATE'} = int($item);
	$item = asset_read_value('ID_AUDIO_NCH',$MPLAY_OUT);
	$ASSETINFO{'AUDIO'}{'CHANNELS'} = int($item);
	$item = asset_read_value('ID_AUDIO_BITRATE',$MPLAY_OUT);
	$item = ($item) ? $item : '0';
	$ASSETINFO{'AUDIO'}{'ENCODERATE'} = int($item/1000);
	
	# Video PID
	$vpid = asset_read_value('ID_VIDEO_ID',$MPLAY_OUT);
	@apids = asset_read_value_array('ID_AUDIO_ID',$MPLAY_OUT);
	
	# ---------------------------------------
	# MPGTX - Collect stream information
	# ---------------------------------------
	# Read the stream information and put into a hash
	system("mpgtx -i \"$filename\" 2> $MPGTX_ERR > $MPGTX_OUT");
	if(!open($fh,"<$MPGTX_OUT")) {
		error("Cannot open file [$MPGTX_OUT]: $!");
	}
	close($fh);
	
	# Read transport stream details
	@data = asset_read_array('Program N',$MPGTX_OUT);
	$ASSETINFO{'FILE'}{'STREAMS'} = int($data[4]);
	
	# Read elementary stream details
	for(my $i=1; $i<=$ASSETINFO{'FILE'}{'STREAMS'}; $i++) {
		@data = asset_read_array("Stream $i",$MPGTX_OUT);
		
		# Stream PID
		$pid = pop(@data);
		$pid =~ s/\D//;
		
		# Stream number
		$ASSETSTREAMS{$pid}{'NUMBER'} = $i;
		
		# PID stream type is video if it matches video PID read earlier
		if($pid eq $vpid) {
			$ASSETSTREAMS{$pid}{'TYPE'} = 'video';
		}
		# PID stream type is audio if it matches one of the audio PIDs read earlier
		foreach my $a (@apids) {
			if($pid eq $a) {
				$ASSETSTREAMS{$pid}{'TYPE'} = 'audio';
			}
		}
		# If neither video or audio, it is assumed to be a subtitle stream
		if(!$ASSETSTREAMS{$pid}{'TYPE'}) {
			$ASSETSTREAMS{$pid}{'TYPE'} = 'subtitle';
		}
		
		# Reformat the information and store in a hash keyed by PID
		if($ASSETSTREAMS{$pid}{'TYPE'} eq 'video') {
			# Video stream data
			$ASSETSTREAMS{$pid}{'CODEC'} = $ASSETINFO{'VIDEO'}{'CODEC'};
			if($VIDEO_PIDS{"$provider-$ASSETSTREAMS{$pid}{'CODEC'}-$pid"}) {
				$ASSETSTREAMS{$pid}{'LANGUAGE'} = 'video';
				$ASSETSTREAMS{$pid}{'ASPECTRATIO'} = $ASSETINFO{'VIDEO'}{'ASPECTRATIO'};
				$ASSETSTREAMS{$pid}{'ENCODERATE'} = $ASSETINFO{'VIDEO'}{'ENCODERATE'};
				$ASSETSTREAMS{$pid}{'FRAMERATE'} = $ASSETINFO{'VIDEO'}{'FRAMERATE'};
				$ASSETSTREAMS{$pid}{'FRAMESIZE'} = $ASSETINFO{'VIDEO'}{'FRAMESIZE'};
			}
			else {
				logMsg($LOG,$PROGRAM,$prefix."Skipping: Invalid video PID found [$pid] for provider '$provider' and codec '$ASSETSTREAMS{$pid}{'CODEC'}'");
			}
		}
		elsif($ASSETSTREAMS{$pid}{'TYPE'} eq 'audio') {
			# Audio stream data
			$ASSETSTREAMS{$pid}{'CODEC'} = $ASSETINFO{'AUDIO'}{'CODEC'};
			if($AUDIO_PIDS{"$provider-$ASSETSTREAMS{$pid}{'CODEC'}-$pid"}) {
				$lang = (@{$AUDIO_PIDS{"$provider-$ASSETSTREAMS{$pid}{'CODEC'}-$pid"}})[3];
				$langs{$lang} = $lang;
				$ASSETSTREAMS{$pid}{'LANGUAGE'} = $lang;
				$ASSETSTREAMS{$pid}{'ENCODERATE'} = $ASSETINFO{'AUDIO'}{'ENCODERATE'};
				$ASSETSTREAMS{$pid}{'SAMPLERATE'} = $ASSETINFO{'AUDIO'}{'SAMPLERATE'};
				$ASSETSTREAMS{$pid}{'CHANNELS'} = $ASSETINFO{'AUDIO'}{'CHANNELS'};
			}
			else {
				logMsg($LOG,$PROGRAM,$prefix."Skipping: Invalid audio PID found [$pid] for provider '$provider' and codec '$ASSETSTREAMS{$pid}{'CODEC'}'");
			}
		}
		elsif($ASSETSTREAMS{$pid}{'TYPE'} eq 'subtitle') {
			# Sub-title stream data
			$ASSETSTREAMS{$pid}{'CODEC'} = "data";
			if($SUB_PIDS{"$provider-$ASSETSTREAMS{$pid}{'CODEC'}-$pid"}) {
				$lang = (@{$SUB_PIDS{"$provider-$ASSETSTREAMS{$pid}{'CODEC'}-$pid"}})[3];
				$langs{$lang.'s'} = $lang;
				$ASSETSTREAMS{$pid}{'LANGUAGE'} = $lang;
			}
			else {
				logMsg($LOG,$PROGRAM,$prefix."Skipping: Invalid subtitle PID found [$pid] for provider '$provider' and codec '$ASSETSTREAMS{$pid}{'CODEC'}'");
			}
		}
		else {
			# Shouldn't ever end up here
			error("Unrecognized stream type '$ASSETSTREAMS{$pid}{'TYPE'}'");
		}
	}
	
	# Create asset file name
	$ASSETINFO{'FILE'}{'NAME'} = airwave_filename($filename,%langs);
	
	# Generate the MD5 checksum for the file. Set to 'TEST MODE' if running in test mode
	if($TEST) {
		$ASSETINFO{'FILE'}{'MD5SUM'} = 'TEST MODE';
	}
	else {
		logMsg($LOG,$PROGRAM,$prefix."Generating an MD5 checksum");
		$ASSETINFO{'FILE'}{'MD5SUM'} = md5Generate("$CONFIG{CS_DOWNLOAD}/$BATCH/$FILE");
	}
}



# ---------------------------------------------------------------------------------------------
# Read all values in a row based on a search for a string in the file
# Only process first match found
#
# Argument 1 : Search string
# Argument 2 : File to be searched
#
# Return an array of values or undef if nothing found
# ---------------------------------------------------------------------------------------------
sub asset_read_array {
	my($string,$file) = @_;
	my(@rows,$row,@temp,@values);
	
	# Search for the string
	@rows = `grep '$string' $file 2>&1`;
	if(scalar(@rows) == 0) {
		logMsg($LOG,$PROGRAM,"No data found while searching for '$string' in [$file]");
		return;
	}
	
	# Process first match found
	$row = $rows[0];
	chomp $row;
	
	# Extract values and remove excess whitespace in the array
	@temp = split(' ',$row);
	foreach my $value (@temp) {
		if($value) { push(@values,$value); }
	}
	
	# Return the array of values
	return @values;
}



# ---------------------------------------------------------------------------------------------
# Read a single value in a row based on a search for a string in the file, assuming the
# structure of the item being searched for is 'string=value'
# Process all matches and return the first defined or non-zero value
#
# Argument 1 : Search string
# Argument 2 : File to be searched
#
# Return the value or undef if nothing found
# ---------------------------------------------------------------------------------------------
sub asset_read_value {
	my($string,$file) = @_;
	my(@rows,$value,$result);
	
	# Search for the string
	@rows = `grep '$string' $file 2>&1`;
	if(scalar(@rows) == 0) {
		logMsg($LOG,$PROGRAM,"No data found while searching for '$string' in [$file]");
		return;
	}
	
	# Process each row to find the first defined or non-zero value
	foreach my $row (@rows) {
		chomp $row;
		(undef,$value) = split('=',$row);
		if($value && $value ne '0' && !$result) {
			$result = $value;
		}
	}
	
	# Return the value
	return $result;
}



# ---------------------------------------------------------------------------------------------
# Read values from one or more rows based on a search for a string in the file, assuming the
# structure of the item being searched for is 'string=value'
# Process all matches and return all non-zero values
#
# Argument 1 : Search string
# Argument 2 : File to be searched
#
# Return an array of values or undef if nothing found
# ---------------------------------------------------------------------------------------------
sub asset_read_value_array {
	my($string,$file) = @_;
	my(@rows,$value,@result);
	
	# Search for the string
	@rows = `grep '$string' $file 2>&1`;
	if(scalar(@rows) == 0) {
		logMsg($LOG,$PROGRAM,"No data found while searching for '$string' in [$file]");
		return;
	}
	
	# Process each row to find non-zero value
	foreach my $row (@rows) {
		chomp $row;
		(undef,$value) = split('=',$row);
		if($value && $value ne '0') {
			push(@result,$value);
		}
	}
	
	# Return the values
	return @result;
}



# ---------------------------------------------------------------------------------------------
# Create or update the asset record on the Portal
#
# Argument 1 : Film ID
#
# Return asset ID
# ---------------------------------------------------------------------------------------------
sub load_asset {
	my($cid) = @_;
	my($status,$msg,%error,%data,$typ,$enc,$qty,$aid,$name,$size,$md5);
	
	# Skip if running in test mode
	if(!$TEST) {
		# Check whether an asset record exists
		($msg) = apiSelect('ingestAssetCheck',"contentid=$cid","type=$ASSETTYPE","encoding=$ASSETINFO{'STREAM'}{'CODING'}");
		($status,%error) = apiStatus($msg);
		if(!$status) {
			error("Can't read asset record for content '$ASSET': $error{MESSAGE}");
		}
		%data = apiData($msg);
		
		# Get list IDs from values 
		$typ = $LISTVALUES{'Asset Type'}{$ASSETTYPE};
		$enc = $LISTVALUES{'Asset Encoding'}{$ASSETINFO{'STREAM'}{'CODING'}};
		$qty = $LISTVALUES{'Content Quality'}{$QUALITY};
		
		# Asset details
		$name = $ASSETINFO{'FILE'}{'NAME'};
		$size = $ASSETINFO{'FILE'}{'SIZE'};
		$md5 = $ASSETINFO{'FILE'}{'MD5SUM'};
		
		# Update record if asset already exists
		if(%data) {
			$aid = shift [(keys %data)];
			($msg) = apiDML('ingestAssetUpdate',"id=$aid","contentid=$cid","type=$typ","encoding=$enc","quality=$qty","name=$name","size=$size","md5=$md5");
			($status,%error) = apiStatus($msg);
			if(!$status) {
				error("Could not update '$ASSETINFO{'STREAM'}{'CODING'}' asset record for $ASSETTYPE '$ASSET': $error{MESSAGE}");
			}
			else {
				logMsg($LOG,$PROGRAM,"Updated '$ASSETINFO{'STREAM'}{'CODING'}' asset record for $ASSETTYPE '$ASSET'");
			}
		}
		# If asset does not exist, create new asset record
		else {
			($msg) = apiDML('ingestAssetInsert',"contentid=$cid","type=$typ","encoding=$enc","quality=$qty","name=$name","size=$size","md5=$md5");
			($status,%error) = apiStatus($msg);
			if(!$status) {
				error("Could not insert asset record for $ASSETTYPE '$ASSET' encoded as '$ASSETINFO{'STREAM'}{'CODING'}': $error{MESSAGE}");
			}
			else {
				logMsg($LOG,$PROGRAM,"Created asset record for $ASSETTYPE '$ASSET' set to '$ASSETINFO{'STREAM'}{'CODING'}'");
			}
			
			# Find and return the ID of the asset that has just been created
			($msg) = apiSelect('ingestAssetCheck',"contentid=$cid","type=$ASSETTYPE","encoding=$ASSETINFO{'STREAM'}{'CODING'}");
			($status,%error) = apiStatus($msg);
			if(!$status) {
				error("Could not find ID of asset record for $ASSETTYPE '$ASSET' encoded as '$ASSETINFO{'STREAM'}{'CODING'}': $error{MESSAGE}");
			}
			%data = apiData($msg);
			$aid = shift [(keys %data)];
		}
		
		# Return asset ID
		return $aid;
	}
}



# ---------------------------------------------------------------------------------------------
# Create an asset stream record on the Portal. No updates.
#
# Argument 1 : Provider of the content
# Argument 2 : Asset ID
# Argument 3 : Stream PID
# ---------------------------------------------------------------------------------------------
sub load_stream {
	my($provider,$assetid,$pid) = @_;
	my($status,$msg,%error,%data,$key,$sid,$styp,$scod,$sno,$erate,$aspect,$frate,$fsize,$sample,$channel);
	
	# Skip if running in test mode
	if(!$TEST) {
		# Check whether an asset stream record exists
		($msg) = apiSelect('ingestAssetStreamCheck',"assetid=$assetid","stype=$ASSETSTREAMS{$pid}{'TYPE'}","codec=$ASSETSTREAMS{$pid}{'CODEC'}","lang=$ASSETSTREAMS{$pid}{'LANGUAGE'}");
		($status,%error) = apiStatus($msg);
		if(!$status) {
			error("Can't read asset stream record for content '$ASSET': $error{MESSAGE}");
		}
		%data = apiData($msg);
		
		# If asset stream already exists, don't update
		# If asset stream does not exist, create new asset stream record
		if(!%data) {
			# Get stream ID
			$key = ($ASSETSTREAMS{$pid}{'TYPE'} eq 'video') ? "$provider-$ASSETSTREAMS{$pid}{'TYPE'}-$ASSETSTREAMS{$pid}{'CODEC'}" : "$provider-$ASSETSTREAMS{$pid}{'TYPE'}-$ASSETSTREAMS{$pid}{'CODEC'}-$ASSETSTREAMS{$pid}{'LANGUAGE'}";
			$sid = $STREAMS{$key};
			
			# Get list IDs from values 
			$styp = $LISTVALUES{'Stream Type'}{$ASSETSTREAMS{$pid}{'TYPE'}};
			$scod = $LISTVALUES{'Codec'}{$ASSETSTREAMS{$pid}{'CODEC'}}; # Not currently updated as all asset streams would have to be reloaded
			
			# Stream number
			$sno = $ASSETSTREAMS{$pid}{'NUMBER'};
			
			if($ASSETSTREAMS{$pid}{'TYPE'} eq 'video') {
				$erate = $ASSETSTREAMS{$pid}{'ENCODERATE'};
				$aspect = $ASSETSTREAMS{$pid}{'ASPECTRATIO'};
				$frate = $ASSETSTREAMS{$pid}{'FRAMERATE'};
				$fsize = $ASSETSTREAMS{$pid}{'FRAMESIZE'};
				($msg) = apiDML('ingestAssetStreamInsertVideo',"assethasassetstream=$assetid","typehasassetstream=$sid","type=$styp","codec=$scod","encoderate=$erate","aspectratio=$aspect","framerate=$frate","framesize=$fsize");
			}
			elsif($ASSETSTREAMS{$pid}{'TYPE'} eq 'audio') {
				$erate = $ASSETSTREAMS{$pid}{'ENCODERATE'};
				$sample = $ASSETSTREAMS{$pid}{'SAMPLERATE'};
				$channel = $ASSETSTREAMS{$pid}{'CHANNELS'};
				($msg) = apiDML('ingestAssetStreamInsertAudio',"assethasassetstream=$assetid","typehasassetstream=$sid","type=$styp","codec=$scod","encoderate=$erate","samplerate=$sample","channels=$channel");
			}
			elsif($ASSETSTREAMS{$pid}{'TYPE'} eq 'subtitle') {
				($msg) = apiDML('ingestAssetStreamInsertSubtitle',"assethasassetstream=$assetid","typehasassetstream=$sid","type=$styp","codec=$scod");
			}
			
			($status,%error) = apiStatus($msg);
			if(!$status) {
				$msg = ($ASSETSTREAMS{$pid}{'TYPE'} eq 'video') ? $ASSETSTREAMS{$pid}{'TYPE'} : "$ASSETSTREAMS{$pid}{'TYPE'} ($ASSETSTREAMS{$pid}{'LANGUAGE'})";
				error("Could not insert $msg asset stream record for $ASSETTYPE '$ASSET': $error{MESSAGE}");
			}
			else {
				logMsg($LOG,$PROGRAM,"Inserted $ASSETSTREAMS{$pid}{'TYPE'} asset stream record for $ASSETTYPE '$ASSET'");
			}
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Close the metadata file
# ---------------------------------------------------------------------------------------------
sub document_footer {
	$XML->endTag('metadata');
	$XML->end();
	$HANDLE->close();
}



# ---------------------------------------------------------------------------------------------
# Create the metadata file and the XML writer object
#
# Argument 1 : Location of the new XML metadata file
# ---------------------------------------------------------------------------------------------
sub document_header {
	my($file) = @_;
	
	# Create the document file
	if(!open($HANDLE,">$file")) {
		error("Unable to create the metadata file [$file]");
	}
	
	# Create the document and write the header
	$XML = new XML::Writer(OUTPUT=>$HANDLE);
	$XML->xmlDecl("ISO-8859-1");
	
	# Create the contenter element
	$XML->startTag("metadata","id"=>$ASSET,"type"=>"video","creator"=>"Airwave","created"=>formatDateTime('zd/zm/ccyy zh24:mi:ss'));
}



# ---------------------------------------------------------------------------------------------
# Create assets section in the XML metadata file
#
# Argument 1 : ID of the content
# ---------------------------------------------------------------------------------------------
sub film_assets {
	my($cid) = @_;
	my($status,$msg,%error,%data,%assets);
	my($assetid,$aid,$file_name,$asset_type,$stream_coding,$stream_type,$quality,$file_size,$md5sum,$pid,$pid_type,$pid_codec,$samplerate,$channels,$language,$encoderate,$aspectratio,$framesize,$framerate,$num);
	my %no_streams = ();
	
	# Read the asset and asset stream details from the Portal
	($msg) = apiSelect('ingestFilmAssetDetails',"contentid=$cid");
	($status,%error) = apiStatus($msg);
	if(!$status) {
		error("Error reading asset and asset stream details for [$ASSET] from database: $error{MESSAGE}");
	}
	%data = apiData($msg);
	if(!%data) {
		# No asset and asset stream details found on Portal
		error("No asset and asset stream details for [$ASSET]");
	}
	
	# Extract the asset details for the outer container
	foreach my $key (sort keys %data) {
		($assetid,$file_name,$asset_type,$stream_coding,$stream_type,$quality,$file_size,$md5sum,$pid,$pid_type,$pid_codec,$samplerate,$channels,$language,$encoderate,$aspectratio,$framesize,$framerate) = @{$data{$key}};
		$assets{$assetid} = [($file_name,$asset_type,$stream_coding,$stream_type,$quality,$file_size,$md5sum)];
		$num = $no_streams{$assetid};
		$num++;
		$no_streams{$assetid} = $num;
	}
	
	# Create the 'assets' container
	$XML->startTag("assets");
	
	# Process each asset
	foreach my $assetid (sort keys %assets) {
		($file_name,$asset_type,$stream_coding,$stream_type,$quality,$file_size,$md5sum) = @{$assets{$assetid}};
		
		# Create the asset container in the metadata
		$XML->startTag("asset",
					   "name"		=> $file_name,
					   "class"		=> $asset_type,
					   "coding"		=> $stream_coding,
					   "type"		=> $stream_type,
					   "quality"	=> $quality,
					   "size"		=> $file_size,
					   "md5"		=> $md5sum,
					   "program"	=> 2,
					   "streams"	=> $no_streams{$assetid}
					   );
		
		# Create the stream container for the current asset
		foreach my $key (sort keys %data) {
			($aid,undef,undef,undef,undef,undef,undef,undef,$pid,$pid_type,$pid_codec,$samplerate,$channels,$language,$encoderate,$aspectratio,$framesize,$framerate) = @{$data{$key}};
			
			# If asset ID matches parent asset container
			if($assetid == $aid) {
				$XML->startTag("stream",
							   "pid"	=> $pid,
							   "coding"	=> $pid_codec,
							   "type"	=> $pid_type
							   );
				
				# Process audio stream
				if($pid_type eq 'audio') {
					$XML->dataElement("sample_rate",$samplerate);
					$XML->dataElement("channels",$channels);
					$XML->dataElement("encode_rate",$encoderate);
					$XML->dataElement("language",$language);
				}
				# Process sub-title stream
				elsif($pid_type eq 'subtitle') {
					$XML->dataElement("language",$language);
				}
				# Process video stream
				else {
					$XML->dataElement("frame_size",$framesize);
					$XML->dataElement("aspect_ratio",$aspectratio);
					$XML->dataElement("frame_rate",$framerate);
					$XML->dataElement("encode_rate",$encoderate);
				}
				$XML->endTag("stream");
			}
		}
		$XML->endTag("asset");
	}
	
	# Close the 'assets' container
	$XML->endTag("assets");
}



# ---------------------------------------------------------------------------------------------
# Print the film clearance dates
# ---------------------------------------------------------------------------------------------
sub film_clearances {
	my($status,$msg,%error,%clearances,$terrn,$encrypt,$clear);
	
	# Return a hash of clearance dates keyed by film name
	($msg) = apiSelect('ingestClearance',"assetcode=$ASSET");
	($status,%error) = apiStatus($msg);
	if(!$status) {
		error("No clearance dates returned for '$ASSET': $error{MESSAGE}");
	}
	%clearances = apiData($msg);
	
	# Print the clearance dates for each territory
	$XML->startTag("territories");
	foreach my $terrc (sort keys %clearances) {
		($terrn,$encrypt,$clear) = @{$clearances{$terrc}};
		$XML->startTag("territory","id"=>$terrc,"name"=>$terrn);
		$XML->dataElement("encrypted",$encrypt);
		$XML->dataElement("clear",$clear);
		$XML->endTag("territory");
	}
	$XML->endTag("territories");
}



# ---------------------------------------------------------------------------------------------
# Generate the film details
# ---------------------------------------------------------------------------------------------
sub film_details {
	my($status,$msg,%error,%details,$title,$reference,$provider);
	
	# Return a hash of film details keyed by film name
	($msg) = apiSelect('ingestFilmDetails',"assetcode=$ASSET");
	($status,%error) = apiStatus($msg);
	if(!$status) {
		error("Error: No film details returned for '$ASSET': $error{MESSAGE}");
	}
	%details = apiData($msg);
	
	# Stop if no details returned
	if(!%details) {
		error("Error: No film details returned for '$ASSET'");
	}
	
	# Read film details
	$title = (keys %details)[0];
	$reference = $details{$title}[4];
	$provider = $details{$title}[7];
	
	# Create the elements that are language independant
	$XML->dataElement("release",$details{$title}[1]);
	$XML->dataElement("year",$details{$title}[2]);
	$XML->dataElement("certificate",$details{$title}[6]);
	$XML->dataElement("duration",$details{$title}[3]);
	$XML->dataElement("imdb",$details{$title}[5]);
	$XML->startTag("provider");
	$XML->dataElement("name",$provider);
	$XML->dataElement("reference",$reference);
	$XML->endTag("provider");
}



# ---------------------------------------------------------------------------------------------
# Print the film genres
# ---------------------------------------------------------------------------------------------
sub film_genres {
	my($status,$msg,%error,%genres);
	
	# Return a hash of genres keyed by film name
	($msg) = apiSelect($CONFIG{PORTAL},'ingestGenres',"assetcode=$ASSET");
	($status,%error) = apiStatus($msg);
	if(!$status) {
		error("No genres returned for '$ASSET': $error{MESSAGE}");
	}
	%genres = apiData($msg);
	
	# Print the genres
	$XML->startTag("genres");
	foreach my $genre (sort keys %genres) {
		$XML->dataElement("genre",$genre);
	}
	$XML->endTag("genres");
}



# ---------------------------------------------------------------------------------------------
# Print the image details
#
# Argument 1 : Directory on the Portal where the metadata is held
# Argument 2 : Portal directory holding the full size image
# ---------------------------------------------------------------------------------------------
sub film_images {
	my($meta,$image) = @_;
	my($full);
	
	# Download full size image and return full name of temporary image file (or undef)
	$full = film_image_download($image);
	if(!$full) {
		logMsg($LOG,$PROGRAM,"There is no full size image for '$ASSET'");
		return;
	}
	
	# Create the different image sizes
	logMsg($LOG,$PROGRAM,"Creating image files for asset '$ASSET'");
	film_image_create($meta,$full,800,'full');
	film_image_create($meta,$full,400,'large');
	film_image_create($meta,$full,200,'small');
	
	# Create image container
	$XML->startTag("images");
	
	# Add details for different images
	film_image_details('full');
	film_image_details('large');
	film_image_details('small');
	
	# Close  image container
	$XML->endTag("images");
}



# ---------------------------------------------------------------------------------------------
# Create a smaller image from an existing image
#
# Argument 1 : Directory on the Portal where the metadata is held
# Argument 2 : Full name of temporary image file
# Argument 3 : Height of image (pixels)
# Argument 4 : Type of image being processes (full/large/small)
# ---------------------------------------------------------------------------------------------
sub film_image_create {
	my($portal,$file,$high,$type) = @_;
	my($ref,@tags,$info,$value,%settings,$h,$w,$ratio,$wide,$size,$dir,$result,$status,$msg);
	
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
	
	# Use the height and width to create standard size 'large' and 'small' images
	$h = $settings{ImageHeight};
	$w = $settings{ImageWidth};
	if(!($h && $w)) {
		logMsg($LOG,$PROGRAM,"Error reading image height or width");
		return;
	}
	$ratio = $h/$w;
	$wide = int($high/$ratio);
	$size = "$wide"."x$high";
	
	# Create in repository, unless running in test mode
	$dir = ($TEST) ? $CONFIG{TEMP} : $REPO_DIR;
	
	# Create the image
	$result = `convert $file -resize $size $dir/$ASSET-$type.jpg`;
	if($result) {
		logMsg($LOG,$PROGRAM,"Error resizing image to $size: $result");
		return;
	}
	
	# Upload the image to the Portal, unless running in test mode
	if($TEST) {
		logMsg($LOG,$PROGRAM,"TEST: Uploading [$REPO_DIR/$ASSET-$type.jpg] to [$portal/$ASSET]");
	}
	else {
		($status,$msg) = portalUpload("$ASSET-$type.jpg",$REPO_DIR,"$ASSET-$type.jpg","$portal/$ASSET");
		if(!$status) {
			logMsg($LOG,$PROGRAM,$msg);
			logMsg($LOG,$PROGRAM,"Cannot upload [$REPO_DIR/$ASSET-$type.jpg] to [$portal/$ASSET/$ASSET-$type.jpg]");
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Print the details of a single image
#
# Argument 1 : Type of image being processes (full/large/small)
# ---------------------------------------------------------------------------------------------
sub film_image_details {
	my($type) = @_;
	my($file,$ref,@tags,$info,$value,%settings,$high,$wide,$mime,@attr);
	
	# Add element if image downloaded
	$file = "$REPO_DIR/$ASSET-$type.jpg";
	if(-e $file) {
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
			logMsg($LOG,$PROGRAM,"Error reading image height, width or MIME type");
			return;
		}
		
		# Add to attribute list for XML
		push(@attr,('height',$high));
		push(@attr,('width',$wide));
		push(@attr,('mimetype',$mime));
		$XML->dataElement("image","$ASSET-$type.jpg","type",$type,@attr);
	}
}



# ---------------------------------------------------------------------------------------------
# Download the full size image from the Portal
#
# Argument 1 : Portal directory holding the full size image
#
# Return full name of temporary image file, or undef if no full size image was found
# ---------------------------------------------------------------------------------------------
sub film_image_download {
	my($image) = @_;
	my($status,$msg);
	
	# Delete the existing temporary image
	if(-e "$CONFIG{TEMP}/full-image.jpg") {
		system("rm $CONFIG{TEMP}/full-image.jpg");
	}
	
	# Download the image for the asset
	($status,$msg) = portalDownload("$ASSET.jpg",$image,"full-image.jpg","$CONFIG{TEMP}");
	if(!$status) {
		logMsg($LOG,$PROGRAM,$msg);
		logMsg($LOG,$PROGRAM,"Cannot download [$image/$ASSET.jpg] to [$CONFIG{TEMP}/full-image.jpg]");
	}
	
	# Return full name of temporary image file, or undef if no full size image was found
	if(-e "$CONFIG{TEMP}/full-image.jpg") {
		return "$CONFIG{TEMP}/full-image.jpg";
	}
	else {
		return;
	}
}



# ---------------------------------------------------------------------------------------------
# Print the film synopses
# ---------------------------------------------------------------------------------------------
sub film_synopses {
	my($status,$msg,%error,%synopses,$code,$ok,$title,$short,$full,$credits,@rows);
	
	# Return a hash of synopses keyed by film name
	($msg) = apiSelect('ingestSynopses',"assetcode=$ASSET");
	($status,%error) = apiStatus($msg);
	if(!$status) {
		error("No synopses returned for '$ASSET': $error{MESSAGE}");
	}
	%synopses = apiData($msg);
	
	# Print synopses (1/language)
	$XML->startTag("languages");
	foreach my $name (sort keys %synopses) {
		# Read synopsis information
		($code,$title,$short,$full,$credits) = @{$synopses{$name}};
		
		# Skip Russian as it is not in Western Europe encoding (needs ISO-8859-5)
		if($code ne 'ru') {
			# Create language container
			$XML->startTag("language","id"=>$code,"name"=>$name);
			
			# Full synopsis
			($ok,$title) = cleanNonUTF8($title);
			if(!$ok) {
				logMsgPortal($LOG,$PROGRAM,'W',"Invalid character found in film name: $title");
			}
			$XML->startTag("title");
			$XML->characters($title);
			$XML->endTag("title");
			
			# Tag line
			($ok,$short) = cleanNonUTF8($short);
			if(!$ok) {
				logMsgPortal($LOG,$PROGRAM,'W',"Invalid character found in summary: $short");
			}
			$XML->startTag("short");
			$XML->characters($short);
			$XML->endTag("short");
			
			# Full synopsis
			($ok,$full) = cleanNonUTF8($full);
			if(!$ok) {
				logMsgPortal($LOG,$PROGRAM,'W',"Invalid character found in synopsis: $full");
			}
			$XML->startTag("full");
			$XML->characters($full);
			$XML->endTag("full");
			
			# Credits - lines separated by '\n'
			$XML->startTag("credits");
			@rows = split(/#nl#/,$credits);
			foreach my $item (@rows) {
				($ok,$item) = cleanNonUTF8($item);
				if(!$ok) {
					logMsgPortal($LOG,$PROGRAM,'W',"Invalid character found in credits: $item");
				}
				$XML->startTag("item");
				$XML->characters($item);
				$XML->endTag("item");
			}
			$XML->endTag("credits");
			
			# Close language container
			$XML->endTag("language");
		}
	}
	$XML->endTag("languages");
}



# ---------------------------------------------------------------------------------------------
# Create a hash of hashes holding list values
# ---------------------------------------------------------------------------------------------
sub read_listvalues {
	my($status,$msg,%error,%data,$group,$item);
	
	# Read PIDs
	($msg) = apiSelect(,'ingestListValues');
	($status,%error) = apiStatus($msg);
	if(!$status) {
		error("No list values returned: $error{MESSAGE}");
	}
	%data = apiData($msg);
	
	# Create hash
	foreach my $id (keys %data) {
		($group,$item) = @{$data{$id}};
		$LISTVALUES{$group}{$item} = $id;
	}
}



# ---------------------------------------------------------------------------------------------
# Create a set of hashes keyed by Provider-PID, with the provider, PID and language codes
# in an array
# ---------------------------------------------------------------------------------------------
sub read_pids {
	my($status,$msg,%error,%data,%pids,$lang,$pid,$provider,$type,$codec);
	
	# Read PIDs
	($msg) = apiSelect('ingestPIDs');
	($status,%error) = apiStatus($msg);
	if(!$status) {
		error("No PIDs returned: $error{MESSAGE}");
	}
	%data = apiData($msg);
	
	# Load a hash for each type of stream
	foreach my $key (keys %data) {
		($lang,$pid,$provider,$type,$codec) = @{$data{$key}};
		if($type eq 'audio') {
			$AUDIO_PIDS{"$provider-$codec-$pid"} = [($provider,$codec,$pid,$lang)];
		}
		if($type eq 'video') {
			$VIDEO_PIDS{"$provider-$codec-$pid"} = [($provider,$codec,$pid,$lang)];
		}
		if($type eq 'subtitle') {
			$SUB_PIDS{"$provider-$codec-$pid"} = [($provider,$codec,$pid,$lang)];
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Create a hash holding stream values
# ---------------------------------------------------------------------------------------------
sub read_streams {
	my($status,$msg,%error,%data,$id);
	
	# Read PIDs
	($msg) = apiSelect('ingestStreams');
	($status,%error) = apiStatus($msg);
	if(!$status) {
		error("No stream data returned: $error{MESSAGE}");
		return;
	}
	%data = apiData($msg);
	
	# Create hash
	foreach my $key (keys %data) {
		($id) = @{$data{$key}};
		$STREAMS{$key} = $id;
	}
}



# ---------------------------------------------------------------------------------------------
# Update ingest date on Portal
#
# Argument 1 : Film ID
# ---------------------------------------------------------------------------------------------
sub update_ingest_date {
	my($id) = @_;
	my($status,$msg,%error);
	
	# Prefix for messages when run in test mode
	my $prefix = ($TEST) ? 'TEST: ' : '';
	logMsg($LOG,$PROGRAM,$prefix."Updating ingestion date for '$ASSET'");
	
	# Skip if running in test mode
	if(!$TEST) {
		# Update the new release flag
		($msg) = apiDML('ingestUpdateIngestDate',"id=$id","ingested=".formatDateTime('zd mon cczy'));
		($status,%error) = apiStatus($msg);
		if(!$status) {
			error("Could not update the ingestion date for '$ASSET': $error{MESSAGE}");
		}
		else {
			logMsg($LOG,$PROGRAM,"Ingestion date for '$ASSET' has been updated");
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Update the Portal with asset and stream data
#
# Argument 1 : Provider of the content
# Argument 2 : Film ID
# ---------------------------------------------------------------------------------------------
sub update_portal {
	my($provider,$cid) = @_;
	my($assetid);
	
	# Create the asset record on the Portal
	$assetid = load_asset($cid);
	
	# Process each stream for the asset
	foreach my $pid (sort keys %ASSETSTREAMS) {
		load_stream($provider,$assetid,$pid);
	}
}



# ---------------------------------------------------------------------------------------------
# Upload the metadata file to the Portal
#
# Argument 1 : Location of metadata directory on the Portal
# ---------------------------------------------------------------------------------------------
sub upload_metadata {
	my($portal) = @_;
	my($filename,$status,$msg);
	
	# Prefix for messages when run in test mode
	$filename = "$ASSET.xml";
	logMsg($LOG,$PROGRAM,"Uploading [$REPO_DIR/$filename] to [$portal/$ASSET]");
	
	# Upload metadata file to the Portal
	($status,$msg) = portalUpload($filename,$REPO_DIR,$filename,"$portal/$ASSET");
	if(!$status) {
		logMsg($LOG,$PROGRAM,$msg);
		logMsg($LOG,$PROGRAM,"Cannot upload [$REPO_DIR/$filename] to [$portal/$ASSET/$ASSET.xml]");
	}
	logMsg($LOG,$PROGRAM,"Uploaded [$REPO_DIR/$filename] to [$portal/$ASSET]");
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
Author  : Basil Fisk (c)2013 Airwave Ltd

Summary :
  Check the film and trailer files in the specified batch (directory) and generate a
  metadata file for the film containing film details read from the Portal and structural
  information about the film and trailer files. The metadata file will be created in the
  batch directory with the name of the film and a '.xml' file extension.  The image files
  for the film will also be downloaded from the Portal so their details can be included
  in the metadata file.
  
  NB: There may be multiple film files in a directory - the main film and the trailer.
  Trailers are distinguished as being less than 250MB in size.

Usage :
  $PROGRAM --asset=<code>
  $PROGRAM --asset=<provider>
  
  MANDATORY
  --asset=<code>        The reference of a single asset on the Portal.
  --asset=<provider>    The reference of a content provider, in which case the metadata for
                        all assets from the content provider will be refreshed.
                           bbc      : All BBC films
                           pbtv     : All Soft Adult films
                           uip      : All UIP films
  
  OPTIONAL
  --test                If set, the metadata file will be generated but not uploaded.
                        The MD5 checksum will not be generated (for speed of execution).
                        No updates will be applied to the Portal.
                        The download directory will not be moved to the 'trash' directory.
  --log                 If set, the results from the script will be written to the Airwave
                        log directory, otherwise the results will be written to the screen.
	\n");

	# Quit
	exit;
}





# =============================================================================================
# =============================================================================================
#
# VALIDATION FUNCTIONS
#
# =============================================================================================
# =============================================================================================

# ---------------------------------------------------------------------------------------------
# Validate the metadata file as follows:
#
# Assets
#  - Missing film and/or trailer
#  - Name does not reference all languages
#  - Name does not have correct type (ts)
#  - Name does not have '_trailer' if class is 'trailer'
#  - Name suffix is not 'mpg' or 'mp4'
#  - Class attribute is not 'film' or 'trailer'
#  - Coding attribute is not 'mpeg2' or 'mpeg4'
#  - Type attribute is not 'transport'
#
# Streams
#  - Stream coding is 'mpeg1', 'mpeg2' or 'data'
#  - Stream type is 'audio', 'video' or 'subtitle'
#  - Stream PID must be a valid number
#  - Video frame rate <> 25 (warning)
#  - Video encode rate <> 4000 for SD (warning) or NULL for HD
#  - Audio sample rate <> 48000 (warning)
#  - Number of audio channels <> 2 (warning)
#  - Audio encode rate <> 192 or 224 for SD (warning) or NULL for HD
#
# Argument 1 : Fully qualified name of XML metadata file
#
# Return the maximum error level encountered (0=OK, 1=Warning, 2=Error)
# ---------------------------------------------------------------------------------------------
sub validate_xml_file {
	my($file) = @_;
	my($err,$xpc,@temp,@nodes,$id,$class,$provider,$title,@tlr,@flm,@streams,$film,$trailer,$no_streams,@strlang,@attrs,@data,$value);
	logMsg($LOG,$PROGRAM,"Validating XML metadata file [$file]");
	
	# Open and parse the XML metadata file
	($err,$xpc) = parseDocument('file',$file);
	if(!$xpc) {
		logMsg($LOG,$PROGRAM,"Validating '$ASSET': Cannot open the XML file: $file");
		logMsg($LOG,$PROGRAM,$err);
		return 2;
	}
	
	# Clear out temporary variables
	@temp = @tlr = @flm = ();
	$id = $class = "";
	
	# Read the film provider
	@nodes = $xpc->findnodes("/metadata/provider/name");
	$provider = (@nodes) ? $nodes[0]->textContent : undef;
	
	# Read the film title
	@nodes = $xpc->findnodes("/metadata/languages/language[\@id='en']/title");
	$title = (@nodes) ? $nodes[0]->textContent : undef;
	
	# Set the asset found counters
	$film = 0;
	$trailer = 0;
	$ERROR = 0;
	
	# Process each asset element
	@nodes = $xpc->findnodes("/metadata/assets/asset");
	foreach my $node (@nodes) {
		$class = $node->getAttribute("class");
		@streams = $node->findnodes("stream");
		$no_streams = @streams;
		@strlang = $node->findnodes("stream/language");
		
		# Validate a trailer asset
		if($class && $class eq 'trailer') {
			$trailer++;
			# Read key attributes of trailer file, then add list of languages
			$tlr[0] = $node->getAttribute("name");
			$tlr[1] = $node->getAttribute("type");
			$tlr[2] = $node->getAttribute("coding");
			$tlr[3] = $node->getAttribute("streams");
			$tlr[4] = $no_streams;
			foreach my $lang (@strlang) {
				push(@tlr,$lang->textContent);
			}
			
			# Run checks on asset
			$ERROR = 0;
			logMsg($LOG,$PROGRAM,"Validating Trailer: ".$tlr[0]);
			validate_name_languages(@tlr);				# Check that languages are in name
			validate_mpg_extension($tlr[0]);			# Check name has 'mpg' or 'mp4' extension
			validate_coding($tlr[2]);					# Check coding is 'mpeg2' or 'mpeg4'
			validate_name_phrase($tlr[0],'_trailer');	# Check name has 'trailer' phrase
			if($tlr[1] eq 'transport') { validate_name_type('transport',$tlr[0],'_ts'); }
			
			# Read stream data, then run checks on streams within asset
			foreach my $stream (@streams) {
				@attrs = ();
				$attrs[0] = $stream->getAttribute("coding");
				$attrs[1] = $stream->getAttribute("type");
				$attrs[2] = $stream->getAttribute("pid");
				validate_asset_stream($provider,$stream,$tlr[1],@attrs);
			}
			
			# Finished checking the traile
			val_error_message('trailer');
		}
		
		# Validate a film asset
		if($class && $class eq 'film') {
			$film++;
			# Read key attributes of film file, then add list of languages
			$flm[0] = $node->getAttribute("name");
			$flm[1] = $node->getAttribute("type");
			$flm[2] = $node->getAttribute("coding");
			$flm[3] = $node->getAttribute("streams");
			$flm[4] = $no_streams;
			foreach my $lang (@strlang) {
				push(@flm,$lang->textContent);
			}
			
			# Run checks on asset
			$ERROR = 0;
			logMsg($LOG,$PROGRAM,"Validating Film: ".$flm[0]);
			validate_name_languages(@flm);				# Check that languages are in name
			validate_mpg_extension($flm[0]);			# Check name has 'mpg' or 'mp4' extension
			validate_coding($flm[2]);					# Check coding is 'mpeg2' or 'mpeg4'
			if($flm[1] eq 'transport') { validate_name_type('transport',$flm[0],'_ts'); }
			
			# Read stream data, then run checks on streams within asset
			foreach my $stream (@streams) {
				@attrs = ();
				$attrs[0] = $stream->getAttribute("coding");
				$attrs[1] = $stream->getAttribute("type");
				$attrs[2] = $stream->getAttribute("pid");
				validate_asset_stream($provider,$stream,$flm[1],@attrs);
			}
			
			# Finished checking film
			val_error_message('film');
		}
		
		# Missing 'class' attribute
		if(!$class) {
			logMsg($LOG,$PROGRAM,"Validating [$ASSET]: No 'class' attribute defined");
		}
	}
	
	# No trailer asset
	if($trailer == 0) {
		logMsg($LOG,$PROGRAM,"Validating [$ASSET]: No trailer files are referenced in the metadata file");
	}
	
	# No film asset
	if($film == 0) {
		logMsg($LOG,$PROGRAM,"Validating [$ASSET]: No film files are referenced in the metadata file");
	}
	
	# Return the maximum error level encountered (0=OK, 1=Warning 2=Error)
	return $ERROR;
}



# ---------------------------------------------------------------------------------------------
# Set the error level to 1 if a warning is raised or 2 if an error is raised
# Error levels can only go up : 0->1  0->2  1->2
#
# Argument 1 : Error level type (warning/error)
# Argument 2 : Error message
# ---------------------------------------------------------------------------------------------
sub val_error_level {
	my($level,$msg) = @_;
	if($level eq 'warning' && $ERROR == 0) {
		$ERROR = 1;
		logMsg($LOG,$PROGRAM,"Warning: $msg");
	}
	elsif($level eq 'error') {
		$ERROR = 2;
		logMsg($LOG,$PROGRAM,"Error: $msg");
	}
}



# ---------------------------------------------------------------------------------------------
# Write error message to the log file based on the current error level
#
# Argument 1 : Type of asset that has benn checked (film/trailer)
# ---------------------------------------------------------------------------------------------
sub val_error_message {
	my($asset) = @_;
	if($ERROR == 0) { logMsg($LOG,$PROGRAM,"Passed, $asset is valid"); }
	if($ERROR == 1) { logMsg($LOG,$PROGRAM,"Warnings raised during check of $asset"); }
	if($ERROR == 2) { logMsg($LOG,$PROGRAM,"Errors raised during check of $asset"); }
}



# ---------------------------------------------------------------------------------------------
# Run checks on streams within asset
# ---------------------------------------------------------------------------------------------
sub validate_asset_stream {
	my($provider,$stream,$method,$coding,$type,$pid) = @_;
	my(@data,$value);
	validate_stream_coding($coding);				# Stream coding is 'aac', 'h264', 'mpeg1', 'mpeg2' or 'data'
	validate_stream_type($type);					# Stream type is 'audio', 'video' or 'subtitle'
	if($method eq 'transport') {
		validate_stream_pid($provider,$type,$coding,$pid);	# Stream PID must be a valid number
	}
	# Check video data
	if($type eq 'video') {
		# Check the frame rate
		@data = $stream->findnodes("frame_rate");
		$value = $data[0]->textContent;
		if($value ne '25') {
			val_error_level('warning',"Video frame rate should be 25, not '$value'");
		}
		# Check the encoding rate
		@data = $stream->findnodes("encode_rate");
		$value = $data[0]->textContent;
		if($coding eq 'mpeg2' && $value ne '4000') {
			val_error_level('warning',"Video encode rate should be 4000, not '$value'");
		}
	}
	# Check audio data
	if($type eq 'audio') {
		# Check the sample rate
		@data = $stream->findnodes("sample_rate");
		$value = $data[0]->textContent;
		if($value ne '48000') {
			val_error_level('warning',"Audio sample rate should be 48000, not '$value'");
		}
		# Check the number of channels
		@data = $stream->findnodes("channels");
		$value = $data[0]->textContent;
		if($value ne '2') {
			val_error_level('warning',"Number of channels should be 2, not '$value'");
		}
		# Check the encoding rate
		@data = $stream->findnodes("encode_rate");
		$value = $data[0]->textContent;
		if($coding eq 'mpeg2' && ($value ne '192' && $value eq '224')) {
			val_error_level('warning',"Audio encode rate should be 192 or 224, not '$value'");
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Check coding is 'mpeg2' or 'mpeg4'
# ---------------------------------------------------------------------------------------------
sub validate_coding {
	my($value) = @_;
	if($value ne 'mpeg2' && $value ne 'mpeg4') {
		val_error_level('error',"Coding can only be 'mpeg2'");
	}
}



# ---------------------------------------------------------------------------------------------
# Check name has 'mpg' extension
# ---------------------------------------------------------------------------------------------
sub validate_mpg_extension {
	my($value) = @_;
	if(!($value =~ m/.mp[g4]/)) {
		val_error_level('error',"Name should have an '.mpg' or 'mp4' extension");
	}
}



# ---------------------------------------------------------------------------------------------
# Check that languages are in name
# ---------------------------------------------------------------------------------------------
sub validate_name_languages {
	my(@values) = @_;
	for(my $i=5; $i<@values; $i++) {
		if(!($values[0] =~ m/$values[$i]/)) {
			val_error_level('warning',"Language '".$values[$i]."' should be in name");
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Check name has 'trailer' suffix
# ---------------------------------------------------------------------------------------------
sub validate_name_phrase {
	my($value,$phrase) = @_;
	if(!($value =~ m/$phrase/)) {
		val_error_level('error',"Phrase '$phrase' should be in name");
	}
}



# ---------------------------------------------------------------------------------------------
# Check that extension matches type
# ---------------------------------------------------------------------------------------------
sub validate_name_type {
	my($value,$string,$phrase) = @_;
	if(!($string =~ m/$phrase/)) {
		val_error_level('error',"Asset is a '$value' stream, so name should have '$phrase' in it");
	}
}



# ---------------------------------------------------------------------------------------------
# Stream coding is 'aac', 'h264', 'mpeg1', 'mpeg2' or 'data'
# ---------------------------------------------------------------------------------------------
sub validate_stream_coding {
	my($value) = @_;
	if($value ne 'aac' && $value ne 'h264' && $value ne 'mpeg1' && $value ne 'mpeg2' && $value ne 'data') {
		val_error_level('error',"Stream coding is 'mpeg1', 'mpeg2', 'data' not '$value'");
	}
}



# ---------------------------------------------------------------------------------------------
# Streams does not match number of elements
# ---------------------------------------------------------------------------------------------
sub validate_stream_count {
	my($value1,$value2) = @_;
	my $arg1 = int($value1);
	my $arg2 = int($value2);
	if($arg1 != $arg2) {
		val_error_level('warning',"Attribute 'streams' [$arg1] does not match number of stream elements [$arg2]");
	}
}



# ---------------------------------------------------------------------------------------------
# Stream PID must be a valid number
#
# Argument 1 : Content provider
# Argument 2 : Type of stream (audio/video/subtitle)
# Argument 3 : Stream coding (mpeg1/mpeg2)
# Argument 4 : PID
# ---------------------------------------------------------------------------------------------
sub validate_stream_pid {
	my($provider,$type,$codec,$pid) = @_;
	
	# Validate the video PIDs
	if($type eq 'video') {
		if(!$VIDEO_PIDS{"$provider-$codec-$pid"}) {
			val_error_level('error',"Video PID '$pid' is invalid for provider '$provider' and codec '$codec'");
		}
	}
	
	# Validate the audio PIDs
	if($type eq 'audio') {
		if(!$AUDIO_PIDS{"$provider-$codec-$pid"}) {
			val_error_level('error',"Audio PID '$pid' is invalid for provider '$provider' and codec '$codec'");
		}
	}
	
	# Validate the sub-title PIDs
	if($type eq 'subtitle') {
		if(!$SUB_PIDS{"$provider-$codec-$pid"}) {
			val_error_level('error',"Sub-title PID '$pid' is invalid for provider '$provider' and codec '$codec'");
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Check that stream type is 'audio', 'video' or 'subtitle'
# ---------------------------------------------------------------------------------------------
sub validate_stream_type {
	my($value) = @_;
	if(!($value eq 'audio' || $value eq 'video' || $value eq 'subtitle')) {
		val_error_level('error',"Stream type is 'audio', 'video' or 'subtitle', not '$value'");
	}
}


