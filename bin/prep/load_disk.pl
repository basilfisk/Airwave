#!/usr/bin/perl
# *********************************************************************************************
# *********************************************************************************************
#
# Copy all media files for a named site from the Content Repository to a new
# disk.  This is typically used for the initial data load of a server, or for
# recreating a disk in the event of a failure on site.  The list of films is
# built from all distribution manifests relating to the site.
#
# *********************************************************************************************
# *********************************************************************************************

# Declare modules
use strict;
use warnings;

# System modules
use Getopt::Long;

# Breato modules
use lib "$ENV{'AIRWAVE_ROOT'}";
use mods::API3 qw(apiData apiSelect apiStatus);
use mods::Common qw(formatDateTime logMsg logMsgPortal readConfig);

# Program information
our $PROGRAM = "load_disk.pl";
our $VERSION = "2.0";

# Check there are any arguments
if($#ARGV == -1) { usage(); }

# Read command line options
our $ACTION = 'empty';
our @DATA	= (0,0,0);
our $LOG	= 0;
our $SITE   = 'empty';
our $SOURCE = 'empty';
our $TARGET = 'empty';
our $TEST = 0;
GetOptions (
	'copy'			=> sub { $ACTION = 'copy'; },
	'show'			=> sub { $ACTION = 'show'; },
	'f|film'		=> sub { $DATA[0] = 1; },
	'm|meta'		=> sub { $DATA[2] = 1; },
	't|trailer'		=> sub { $DATA[1] = 1; },
	'log'			=> \$LOG,
	'site=s'		=> \$SITE,
	'src|source=s'	=> \$SOURCE,
	'tgt|target=s'	=> \$TARGET,
	'test'			=> sub { $TEST = 1; },
	'help'			=> sub { usage(); } );

# Read the configuration parameters
our %CONFIG  = readConfig("$ENV{'AIRWAVE_ROOT'}/etc/airwave.conf");

# Target file name with escaped spaces
our $TARGET_ESC;

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
	# Read argument and initialise local variables
	my($status,$msg,%error,%films);

	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");
	if($ACTION eq 'copy') {
		logMsg($LOG,$PROGRAM,"Load disk with films for '$SITE'");
	}
	else {
		logMsg($LOG,$PROGRAM,"Films allocated to '$SITE'");
	}

	# Check the validity of the 'action' argument
	if($ACTION ne 'show' && $ACTION ne 'copy') { usage(1); }

	# Check that site argument is present
	if($SITE eq 'empty') { usage(2); }

	# If 'action' is 'copy', check that the directories exist and at least 1 data type is selected
	if($ACTION eq 'copy') {
		# Must have at least 1 type of data to be copied
		if(($DATA[0]+$DATA[1]+$DATA[2]) == 0) { usage(3); }

		# If the 'source' argument has not been specified then use the default
		if($SOURCE eq 'empty') { $SOURCE = $CONFIG{CS_ROOT} }

		# Check that the 'target' argument is present
		if($TARGET eq 'empty') { usage(4); }

		# Check source directory exists
		if(!-d $SOURCE) { usage(5); }

		# Check target directory exists
		if(!-d $TARGET) { usage(6); }

		# Stop if the source directory has no marker file in the root
		if(!-f "$SOURCE/content-source-disk") { usage(7); }
	}

	# Escape spaces in the directory name
	$TARGET_ESC = $TARGET;
	$TARGET_ESC =~ s/ /\\ /g;

	# Return a hash of films at the site keyed by provider and film name
	($msg) = apiSelect('loadDisk',"site=$SITE");
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"SQL command 'loadDisk' did not return any records for site '$SITE' [$error{CODE}] $error{MESSAGE}");
		exit;
	}
	%films = apiData($msg);

	# Show list of films or load onto disk
	if($ACTION eq 'show') {
		list_films(%films);
	}
	else {
		copy_films(%films);
	}
}



# ---------------------------------------------------------------------------------------------
# Copy the list of films for the site
# Argument 1 : Hash of films
# ---------------------------------------------------------------------------------------------
sub copy_films {
	# Read argument and initialise local variables
	my(%films) = @_;
	my($msg,$dh,$status,@files,$file,$src,$tgt,$tgtesc,$cmd,$src_enc,$src_clr);
	my($provider,$certificate,$code,$title,$encserver);

	# Process each film record
	# Encryption details are the same for each film in the site
	foreach my $key (sort keys %films) {
		($provider,$certificate,$code,$title,$encserver) = @{$films{$key}};
		logMsg($LOG,$PROGRAM,"$title ($code)");

		# Create the directories on the target device
		$src = "$SOURCE/$provider/$code";
		$tgt = "$TARGET/$provider/$code";
		$tgtesc = "$TARGET_ESC/$provider/$code";

		# Create directory for assets
		if(!-d $tgt) { system("mkdir -p $tgtesc"); }

		# Check whether there is a source content directory for this film
		$status = 1;
		opendir($dh,"$src") or $status = 0;
		if($status) {
			# Copy meta-data and image files to target directory
			if($DATA[2]) {
				# Don't overwrite existing meta-data file
				$file = "$code.xml";
				if(-e "$tgt/$file") {
					logMsg($LOG,$PROGRAM," - Meta-data file already copied...");
				}
				else {
					logMsg($LOG,$PROGRAM," - Copying metadata...");
					copy_file("$src/$file",$tgt);
				}

				# Small image (if it exists)
				$file = "$code-small.jpg";
				if(-e "$src/$file") {
					logMsg($LOG,$PROGRAM," - Copying small image...");
					copy_file("$src/$file",$tgt);
				}

				# Large image (if it exists)
				$file = "$code-large.jpg";
				if(-e "$src/$file") {
					logMsg($LOG,$PROGRAM," - Copying large image...");
					copy_file("$src/$file",$tgt);
				}

				# Full image (if it exists)
				$file = "$code-full.jpg";
				if(-e "$src/$file") {
					logMsg($LOG,$PROGRAM," - Copying full image...");
					copy_file("$src/$file",$tgt);
				}
			}

			# Copy trailer to target directory
			if($DATA[1]) {
				$file = get_file_name("$CONFIG{CS_ROOT}/$provider",$code,'trailer');
				# Don't overwrite existing file
				if(-e "$tgt/$file") {
					logMsg($LOG,$PROGRAM," - Trailer file already copied...");
				}
				else {
					logMsg($LOG,$PROGRAM," - Copying trailer file...");
					copy_file("$src/$file","$tgt");
				}
			}

			# Copy film and supporting files to target directory
			if($DATA[0]) {
				$file = get_file_name("$CONFIG{CS_ROOT}/$provider",$code,'film');
				# Copy encrypted film to target directory
				if($encserver) {
					# Don't overwrite existing file
					if(-e "$tgt/$file.sm") {
						logMsg($LOG,$PROGRAM," - Film file already copied and encrypted by '$encserver'");
					}
					else {
						# If an encrypted version of film exists, use that, otherwise use unencrypted copy
						$encserver =~ s/ //g;
						$src_enc = "$src/$encserver/$file.sm";
						$src_clr = "$src/$file";
						if(-e $src_enc) {
							logMsg($LOG,$PROGRAM," - Copying encrypted film file");
							copy_file("$src_enc","$tgt");
							copy_file("$src_enc.mdm","$tgt");
							copy_file("$src_enc.sma","$tgt");
						}
						else {
							logMsg($LOG,$PROGRAM," - Copying clear film file");
							copy_file("$src_clr","$tgt");
						}
					}
				}
				# As no encryption is required, just copy file
				else {
					# Don't overwrite existing file
					if(-e "$tgt/$file") {
						logMsg($LOG,$PROGRAM," - Film file already copied...");
					}
					else {
						logMsg($LOG,$PROGRAM," - Copying clear film file...");
						copy_file("$src/$file","$tgt");
					}
				}
			}

			# Close the directory
			closedir($dh);
		}
		else {
			logMsgPortal($LOG,$PROGRAM,'W',"'$code' has no source content directory\n\t[$src]");
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Copy a single file from the Repository to the USB disk
#
# Argument 1 : Fully qualified name of the source file
# Argument 2 : Directory holding the target file
# ---------------------------------------------------------------------------------------------
sub copy_file {
	my($src,$tgt) = @_;

	# Only copy the file if it exists
	if(-e $src) {
		# Show the files to be copied
		if($TEST) {
			logMsg($LOG,$PROGRAM,"     Source: $src");
			logMsg($LOG,$PROGRAM,"     Target: $tgt");
		}
		# Copy the file
		else {
			system("cp",$src,$tgt);
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Find the file name of an asset from the XML metadata file
#
# Argument 1 : Repository directory of the film
# Argument 2 : Reference of film
# Argument 3 : Type of asset name to be returned (film/trailer)
#
# Return the asset file name
# ---------------------------------------------------------------------------------------------
sub get_file_name {
	my($repo,$film,$type) = @_;
	my($file,$psr,$doc,$xpc,@nodes);

	# Open and parse the XML metadata file
	$file = "$repo/$film/$film.xml";
	$psr = XML::LibXML->new();
	$doc = $psr->parse_file($file);
	$xpc = XML::LibXML::XPathContext->new($doc);

	# Read the film asset name
	@nodes = $xpc->findnodes("/metadata/assets/asset[\@class='$type']");

	# Return asset file name or undef
	if(@nodes) {
		return $nodes[0]->getAttribute("name");
	}
	else {
		logMsgPortal($LOG,$PROGRAM,'E',"Can't read file name from '$file'");
		exit;
	}
}



# ---------------------------------------------------------------------------------------------
# Display the list of films to be copied for the site
# Argument 1 : Hash of films
# ---------------------------------------------------------------------------------------------
sub list_films {
	my(%films) = @_;
	my($provider,$certificate,$code,$title,$encserver);

	# Show the header
	logMsg($LOG,$PROGRAM,sprintf("%-8s%-8s%-20s%s","Prov.","Cert.","Enc.Server","Title"));
	logMsg($LOG,$PROGRAM,sprintf("%-8s%-8s%-20s%s","=====","=====","==========","====="));

	# Process each film record
	foreach my $key (sort keys %films) {
		($provider,$certificate,$code,$title,$encserver) = @{$films{$key}};
		$encserver = ($encserver) ? $encserver : "-";
		logMsg($LOG,$PROGRAM,sprintf("%-8s%-8s%-20s%s (%s)",$provider,$certificate,$encserver,$title,$code));
	}
}



# ---------------------------------------------------------------------------------------------
# Program usage
# Argument 1 : Error number
# ---------------------------------------------------------------------------------------------
sub usage {
	my($err) = @_;
	$err = ($err) ? $err : 0;

	if($err == 1) {
		logMsgPortal($LOG,$PROGRAM,'E',"Argument 'action' must be 'show' or 'copy'");
	}
	elsif($err == 2) {
		logMsgPortal($LOG,$PROGRAM,'E',"The 'show' command requires the 'site' argument to be present");
	}
	elsif($err == 3) {
		logMsgPortal($LOG,$PROGRAM,'E',"At least 1 type of data must be copied. Use: -m -t -f options");
	}
	elsif($err == 4) {
		logMsgPortal($LOG,$PROGRAM,'E',"Target directory must be specified");
	}
	elsif($err == 5) {
		logMsgPortal($LOG,$PROGRAM,'E',"Source directory [$SOURCE] does not exist");
	}
	elsif($err == 6) {
		logMsgPortal($LOG,$PROGRAM,'E',"Target directory [$TARGET] does not exist");
	}
	elsif($err == 7) {
		logMsgPortal($LOG,$PROGRAM,'E',"Source directory [$SOURCE] is not a valid Airwave content repository");
	}
	else {
		printf("
Program : $PROGRAM
Version : v$VERSION
Author  : Basil Fisk (c)2013 Airwave Ltd

Summary :
  Copy all media files for a named site from the Content Repository to a new
  disk. This is typically used for the initial data load of a server, or for
  recreating a disk in the event of a failure on site. The list of films is
  built from all distribution manifests relating to the site.

Usage   : $PROGRAM --show --site=<siteref>
          $PROGRAM --copy --site=<siteref> -f -m -t --src=<path> --tgt=<path>

  MANDATORY
    --copy                 Copy the films that this site has from the content repository to
                           the target directory.
    --show                 Show the films assigned to this site.
    --site=<siteref>       Site reference.

  OPTIONAL
    --src|source=<path>    Path to the root of the content repository.
    --tgt|target=<path>    Path to the root of the target directory that the meta-data is to
                           be written to.
    --f|film               Copy the film file to the target directory.
    --m|meta               Copy the meta-data to the target directory.
    --t|trailer            Copy the trailer file to the target directory.
    --test                 Dry run without copying the films.
    --log                  If set, the results from the script will be written to the Airwave
                           log directory, otherwise the results will be written to the screen.
		\n");
	}

	# Stop in all cases
	exit;
}
