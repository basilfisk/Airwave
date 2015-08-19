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
use mods::API qw(apiData apiDML apiSelect apiStatus);
use mods::Common qw(cleanNonUTF8 formatDateTime logMsg logMsgPortal md5Generate parseDocument readConfig);

# Program information
our $PROGRAM = "ingest_film.pl";
our $VERSION = "2.0";

# Check there are any arguments
if($#ARGV == -1) { usage(); }

# Read command line options
our $ASSET		= 'empty';
our $ASSETTYPE	= 'empty';
our $BATCH		= 'empty';
our $FILE		= 'empty';
our $QUALITY	= 'empty';
our $LOG		= 0;
our $TEST		= 0;
if(!GetOptions(
	'asset=s'		=> \$ASSET,			# asset code
	'batch=s'		=> \$BATCH,			# name of WIP directory holding asset
	'file=s'		=> \$FILE,			# name of asset file
	'type=s'		=> \$ASSETTYPE,		# film/trailer
	'quality=s'		=> \$QUALITY,		# hd/sd
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
# Ingest the asset
# ---------------------------------------------------------------------------------------------
sub main {
	my($status,$msg,%error,%film,$cid,$aid,$provider,$filename,$assetid);
	my($new,$msg,$type,$file,$dh,@dirfiles);
	
	logMsg($LOG,$PROGRAM,"=================================================================================");
	
	# Check the arguments
	if($ASSET =~ m/empty/) { error("ERROR: 'asset' must have a value"); };
	if($ASSETTYPE !~ m/^(film|trailer)$/) { error("ERROR: 'type' must be film or trailer"); };
	if($QUALITY !~ m/^(hd|sd)$/) { error("ERROR: 'quality' must be sd or hd"); };
	if($BATCH =~ m/empty/) { error("ERROR: 'batch' must have a value"); };
	if($FILE =~ m/empty/) { error("ERROR: 'file' must have a value"); };
	
	# Load a set of hashes containing stream information, list values and stream data
	read_pids();
	read_listvalues();
	read_streams();
	
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
	
	# Check content provider's directory exists
	if(!-d "$CONFIG{CS_ROOT}/$provider") {
		error("No directory for content provider [$CONFIG{CS_ROOT}/$provider]");
	}
	
	# Setup the path to the asset in the repository
	$REPO_DIR = "$CONFIG{CS_ROOT}/$provider/$ASSET";
	
	# File name of the asset to be ingested
	$filename = "$CONFIG{CS_DOWNLOAD}/$BATCH/$FILE";
	
	# 1 if new asset, 0 if existing asset
	$new = ($aid) ? 0 : 1;
	
	# Start up message for asset
	$msg = ($new) ? "Loading new" : "Updating";
	if($TEST) {
		logMsg($LOG,$PROGRAM,"TEST: $msg $ASSETTYPE file for [$ASSET]");
	}
	else {
		logMsg($LOG,$PROGRAM,"$msg $ASSETTYPE file for [$ASSET]");
	}
	
	# Analyze film and load hash with data
	$provider =~ tr[A-Z][a-z];
	asset_analyze($provider,$filename);
	
	# Create the asset record on the Portal
	$assetid = update_asset($cid);
	
	# Process each stream for the asset
	foreach my $pid (sort keys %ASSETSTREAMS) {
		update_stream($provider,$assetid,$pid);
	}
	
	# Create Content Repository directory to hold asset files (but not in test mode)
	if(!-d $REPO_DIR) {
		if($TEST) {
			logMsg($LOG,$PROGRAM,"TEST: Creating asset directory [$REPO_DIR]");
		}
		else {
			logMsg($LOG,$PROGRAM,"Creating asset directory [$REPO_DIR]");
			system("mkdir -p $REPO_DIR");
		}
	}
	
	# If existing asset is being updated, move existing asset file to trash
	if(!$new) {
		# Work out which files to move to trash
		$type = ($QUALITY eq 'hd') ? 'mp4' : 'mpg';
		$file = ($ASSETTYPE eq 'film') ? "_ts" : "_ts_trailer";
		opendir($dh,$REPO_DIR);
		@dirfiles = readdir($dh);
		closedir($dh);
		@dirfiles = grep { /$file\.$type/ } @dirfiles;
		
		# Move each file
		foreach my $filename (@dirfiles) {
			if($TEST) {
				logMsg($LOG,$PROGRAM,"TEST: Moving $ASSETTYPE file [$REPO_DIR/$filename] to [$CONFIG{CS_TRASH}]");
			}
			else {
				logMsg($LOG,$PROGRAM,"Moving $ASSETTYPE file [$REPO_DIR/$filename] to [$CONFIG{CS_TRASH}]");
				system("mv $REPO_DIR/$filename $CONFIG{CS_TRASH}");
			}
		}
	}
	
	# Move new asset file to film directory in Repository
	$file = "$CONFIG{CS_DOWNLOAD}/$BATCH/$FILE";
	if($TEST) {
		logMsg($LOG,$PROGRAM,"TEST: New $ASSETTYPE file [$file] moved to [$REPO_DIR/$ASSETINFO{'FILE'}{'NAME'}]");
	}
	else {
		logMsg($LOG,$PROGRAM,"New $ASSETTYPE file [$file] moved to [$REPO_DIR/$ASSETINFO{'FILE'}{'NAME'}]");
		system("mv $file $REPO_DIR/$ASSETINFO{'FILE'}{'NAME'}");
	}
	
	# If empty, move download directory to 'trash' directory
	opendir($dh,"$CONFIG{CS_DOWNLOAD}/$BATCH");
	@dirfiles = readdir($dh);
	closedir($dh);
	@dirfiles = grep { !/^\./ } @dirfiles;
	if(!@dirfiles) {
		if($TEST) {
			logMsg($LOG,$PROGRAM,"TEST: Moving download directory [$CONFIG{CS_DOWNLOAD}/$BATCH] to [$CONFIG{CS_TRASH}]");
		}
		else {
			logMsg($LOG,$PROGRAM,"Moving download directory [$CONFIG{CS_DOWNLOAD}/$BATCH] to [$CONFIG{CS_TRASH}]");
			system("mv $CONFIG{CS_DOWNLOAD}/$BATCH $CONFIG{CS_TRASH}");
		}
	}
	
	# Set ingest date on Portal, then generate metadata file and upload to Portal
	if(!$TEST) {
		update_ingest_date($cid);
	}
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
	$ASSETINFO{'FILE'}{'NAME'} = asset_filename($filename,%langs);
	
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
# Generate a standard Airwave file name
#
# Argument 1 : Name of file (without extension)
# Argument 2 : Hash of language PIDs
#
# Return the standard Airwave file name
# ---------------------------------------------------------------------------------------------
sub asset_filename {
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
# Error message for parameter checks
# ---------------------------------------------------------------------------------------------
sub error {
	my($msg) = @_;
	logMsg($LOG,$PROGRAM,$msg);
	exit;
}



# ---------------------------------------------------------------------------------------------
# Create a hash of hashes holding list values
# ---------------------------------------------------------------------------------------------
sub read_listvalues {
	my($status,$msg,%error,%data,$group,$item);
	
	# Read PIDs
	($msg) = apiSelect('ingestListValues');
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
# Create or update the asset record on the Portal
#
# Argument 1 : Film ID
#
# Return asset ID
# ---------------------------------------------------------------------------------------------
sub update_asset {
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
# Update ingest date on Portal
#
# Argument 1 : Film ID
# ---------------------------------------------------------------------------------------------
sub update_ingest_date {
	my($id) = @_;
	my($status,$msg,%error);
	
	# Skip if running in test mode
	if($TEST) {
		logMsg($LOG,$PROGRAM,"TEST: Updating ingestion date for '$ASSET'");
	}
	else {
		# Update the new release flag
		logMsg($LOG,$PROGRAM,"Updating ingestion date for '$ASSET'");
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
# Create an asset stream record on the Portal. No updates.
#
# Argument 1 : Provider of the content
# Argument 2 : Asset ID
# Argument 3 : Stream PID
# ---------------------------------------------------------------------------------------------
sub update_stream {
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
  --asset=<code>        The reference of a single asset on the Portal
  --batch=<name>        The name of the directory holding the film to be ingested
  --file=<name>         The name of the file to be ingested
  --quality=<code>      The quality of the asset - sd|hd
  --type=<code>         The type of asset - film|trailer
  
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


