#!/usr/bin/perl
# ***************************************************************************
# ***************************************************************************
# 
# This script is the interface between the distributions that are planned
# and scheduled on the Portal, and CDS which manages the distributions to
# each site.
#
# ***************************************************************************
# ***************************************************************************

# Establish the root directory
our $ROOT;
BEGIN {
	$ROOT = '/home/airwave/bin';
}

# Declare modules
use strict;
use warnings;

# Assumes input files are in Windows CP1252 and converts to Perl's internal encoding (UTF-8) during read
#use open IN  => ':encoding(cp1252)';
# All output will be UTF-8
#use open OUT => ':utf8';

# System modules
use DBI;
use LWP 5.64;
use HTTP::Tiny;
use XML::LibXML;
use Getopt::Long;
use Data::Dumper;

# Don't verify host certificate. This only applies to my laptop, as I have
# had a problem since upgrading Perl as part of Ubuntu 11.10
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;

# Airwave modules
use lib "$ROOT";
use mods::API qw(apiData apiDML apiEmail apiFileDownload apiMetadata apiSelect apiStatus);
use mods::Common qw(cleanNonUTF8 formatDateTime logMsg logMsgPortal parseDocument readConfig writeFile);

# Program information
our $PROGRAM = "cds.pl";
our $VERSION = "2.0";

# Check there are any arguments
if($#ARGV == -1) { usage(); }

# Read command line options
our $ACTION		= 'empty';
our $LOG		= 0;
our $SERVER		= 'live';
our $TEST		= '';
GetOptions (
	'a|action=s'	=> \$ACTION,
	's|server=s'	=> \$SERVER,
	'test=s'		=> \$TEST,
	'l|log'			=> \$LOG,
	'help'			=> sub { usage(); } );

# Read the configuration parameters
our %CONFIG  = readConfig("$ROOT/etc/airwave.conf");

# Global variables
our($SESSION,$CDS_URL,$CDS_USER,$CDS_PASS,%PACKAGES);
our $CDS = LWP::UserAgent->new;

# Check that the action is recognized
if($ACTION ne 'catalogue' &&
   $ACTION ne 'complete' &&
   $ACTION ne 'content' &&
   $ACTION ne 'ended' &&
   $ACTION ne 'group' &&
   $ACTION ne 'log' &&
   $ACTION ne 'node' &&
   $ACTION ne 'node-status' &&
   $ACTION ne 'notify' &&
   $ACTION ne 'prepare' &&
   $ACTION ne 'running' &&
   $ACTION ne 'start' &&
   $ACTION ne 'status' &&
   $ACTION ne 'stop' &&
   $ACTION ne 'test') {
	   usage(1);
}

# Check that the server is recognized
if($SERVER ne 'live' && $SERVER ne 'test') { usage(2); }

# Set up the address of the requested CDS server
if($SERVER eq 'test') {
	$CDS_URL  = $CONFIG{CDS_URL_TEST};
	$CDS_USER = $CONFIG{CDS_USER_TEST};
	$CDS_PASS = $CONFIG{CDS_PASS_TEST};
}
else {
	# Use live server by default
	$CDS_URL  = $CONFIG{CDS_URL_LIVE};
	$CDS_USER = $CONFIG{CDS_USER_LIVE};
	$CDS_PASS = $CONFIG{CDS_PASS_LIVE};
}

# Set up a mapping of month number to names
our @MONTHS = ('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec');

# Start processing
main();





# ---------------------------------------------------------------------------------------------
# Main processing function
# ---------------------------------------------------------------------------------------------
sub main {
	my($response,$psr,$doc,$xpc,@nodes);

	# Display the last 100 lines of the log file
	if($ACTION eq 'log') {
		`tail -$CONFIG{LOGLINES} $CONFIG{LOGDIR}/cds.log`;
		exit;
	}
	
	# Login to the CDS node, stop if no session number returned by CDS
	login_user();
	if(!$SESSION) { exit; }

	# Prepare a distribution
	if($ACTION eq 'prepare') {
		dist_prepare();
	}
	# Catalogue the Distribution node on CDS
	elsif($ACTION eq 'catalogue') {
		dist_catalogue();
	}
	# Start a distribution
	elsif($ACTION eq 'start') {
		dist_start();
	}
	# Check the status of a distribution
	elsif($ACTION eq 'status') {
		dist_status();
	}
	# Stop a distribution
	elsif($ACTION eq 'stop') {
		dist_stop();
	}
	# Set the ended date of the batch on the Portal for completed distributions
	elsif($ACTION eq 'ended') {
		dist_ended();
	}
	# Update the Portal with the CDS node status
	elsif($ACTION eq 'node-status') {
		dist_node_status();
	}
	# Generate and send emails to each site listing the films distributed
	elsif($ACTION eq 'notify') {
		dist_notify();
	}
	# List completed distributions
	elsif($ACTION eq 'complete') {
		list_complete();
	}
	# List running distributions
	elsif($ACTION eq 'running') {
		list_running();
	}
	# List of catalogued content on the node
	elsif($ACTION eq 'content') {
		list_content();
	}
	# List groups
	elsif($ACTION eq 'group') {
		list_groups();
	}
	# List nodes
	elsif($ACTION eq 'node') {
		list_nodes();
	}
	# Test
	elsif($ACTION eq 'test') {
		test();
	}
	else {
		print "\nUnsupported action [$ACTION]\n\n";
	}

	# Log out from the CDS node
	#logout();
}



# ---------------------------------------------------------------------------------------------
# Catalogue the distribution node on the CDS server
# ---------------------------------------------------------------------------------------------
sub dist_catalogue {
	my($response);

	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");
	logMsg($LOG,$PROGRAM,"Catalogue the '$CONFIG{AIRWAVE_NODE_NAME}' node on the CDS server");
	
	# Run CDS command
	$response = cds_command('indexnode');
	if(!$response) {
		logMsgPortal($LOG,$PROGRAM,'E',"Catalogue: Unable to catalogue the [$CONFIG{AIRWAVE_NODE_NAME}] node on CDS");
		return;
	}
	logMsg($LOG,$PROGRAM,"Successfully catalogued the [$CONFIG{AIRWAVE_NODE_NAME}] node on CDS");
}



# ---------------------------------------------------------------------------------------------
# Set the end date for CDS batches that finished
# ---------------------------------------------------------------------------------------------
sub dist_ended {
	my($status,$msg,%error,%cms,$ok,$cdsref,%cds,$distname,$ended,$res,$distdir);
	my $count = 0;
	
	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");
	logMsg($LOG,$PROGRAM,"Set the end date for completed CDS batches");
	
	# Read the list of running batches from the Airwave Portal
	$msg = apiSelect('cdsStarted');
	($status,%error) = apiStatus($msg);
	
	# Stop if there were errors reading from the Airwave Portal
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"Ended: Unable to read list of current distributions from the Portal [$error{CODE}] $error{MESSAGE}");
		return;
	}
	%cms = apiData($msg);
	
	# Stop if there are no running batches on the Airwave Portal
	if(!%cms) {
		logMsg($LOG,$PROGRAM,"No active distributions on the Portal");
		return;
	}
	
	# Retrieve the list of running distributions
	($ok, $cdsref) = cds_sql_running();
	if(!$ok) {
		logMsg($LOG,$PROGRAM,"Could not read active distributions from the CDS Portal");
		return;
	}
	%cds = %$cdsref;
	
	# Loop through each batch from the Portal and check if still running on CDS
	DISTENDED: foreach my $cmsid (sort keys %cms) {
		$distname = $cms{$cmsid}{dist_name};
		
		# If batch names match, distribution is still running on CDS so skip to next CMS record
		foreach my $cdsid (keys %cds) {
			if($cds{$cdsid}{Bundle} eq $distname) {
				next DISTENDED;
			}
		}
		# Increment counter for number of distributions to be ended
		$count++;
		
		# Update ended date on distribution record
		# NB: This is not the end date as logged on CDS
		$ended = formatDateTime('zd Mon ccyy zh24:mi');
		$msg = apiDML('cdsUpdateEnded',"id=$cmsid","ended='$ended'");
		($status,%error) = apiStatus($msg);
		if(!$status) {
			logMsgPortal($LOG,$PROGRAM,'E',"Ended: End date NOT updated for distribution [$distname] [$error{CODE}] $error{MESSAGE}");
			next DISTENDED;
		}
		logMsg($LOG,$PROGRAM,"Ended date set to $ended for distribution [$distname]");
		
		# Remove the directory tree and all files for the distribution
		$distdir = "$CONFIG{DISTRIBUTION}/$distname";
		if(-d $distdir) {
			$res = `rm -r $distdir 2>&1`;
			if($res) {
				logMsgPortal($LOG,$PROGRAM,'E',"Ended: Unable to remove directory '$distdir': $res");
			}
			else {
				logMsg($LOG,$PROGRAM,"Ended: Removing directory [$distdir]");
			}
		}
	}
	
	# Warn that no distributions have been flagged as ended
	if(!$count) {
		logMsg($LOG,$PROGRAM,"No distributions have been flagged as ended");
	}
}



# ---------------------------------------------------------------------------------------------
# Update the Portal with the status of nodes
# ---------------------------------------------------------------------------------------------
sub dist_node_status {
	my($response,$err,$xpc,@nodes,$status,$msg,%error,%cms,$cmsname,$id,@child,$name);
	
	# Retrieve node details from CDS
	$response = cds_command('listnodes');
	if(!$response) {
		logMsgPortal($LOG,$PROGRAM,'W',"Node Status: Unable to retrieve the list of nodes on CDS");
		return;
	}
	
	# Read the list of nodes, stop if errors reading the response
	($err,$xpc) = parseDocument('string',$response);
	if(!$xpc) {
		logMsgPortal($LOG,$PROGRAM,'E',"Node Status: Unable to open the XML document: $response: $err");
		return;
	}
	@nodes = $xpc->findnodes("/cds:response/cds:nodelist/cds:node");
	if(!@nodes) {
		logMsgPortal($LOG,$PROGRAM,'E',"Node Status: Unable to extract nodes from response document");
		return;
	}
	
	# Read the list of CDS nodes from the Portal
	$msg = apiSelect('cdsNodes');
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"Node Status: Unable to read list of current distributions from the Portal [$error{CODE}] $error{MESSAGE}");
		return;
	}
	%cms = apiData($msg);
	
	# Stop if no CDS nodes were returned from the Portal
	if(!%cms) {
		logMsg($LOG,$PROGRAM,"No CDS nodes were returned from the Portal");
		return;
	}
	
	# Update the status of matching nodes on the Portal
	foreach my $id (keys %cms) {
		$cmsname = $cms{$id}{node};
		foreach my $node (@nodes) {
			# Read values from the CDS query
			$status = $node->getAttribute('status');
			@child = $node->findnodes("cds:name");
			$name = $child[0]->textContent;
			
			# If CDS and CMS names match, update the Portal
			if("$cmsname" eq "$name") {
				$status = ($status eq 'active') ? 'true' : 'false';
				$msg = apiDML('cdsUpdateNodeStatus',"id=$id","status=$status");
				($status,%error) = apiStatus($msg);
				if(!$status) {
					logMsgPortal($LOG,$PROGRAM,'E',"Node Status: Status NOT updated for node '$name' [$error{CODE}] $error{MESSAGE}");
				}
			}
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Generate and send emails for each node listing the films distributed
# ---------------------------------------------------------------------------------------------
sub dist_notify {
	my($status,$msg,%error,%data,$distid,$distname,$node,$notify,$provider,$site,$asset,$abort,%films);
	my @lastdist = (0,'','','','');
	
	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");
	logMsg($LOG,$PROGRAM,"Generate emails for completed distributions");
	
	# Return a hash keyed by distribution ID and content name, with distribition and film details
	$msg = apiSelect('cdsNotify');
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"Notify: No unnotified distributions found [$error{CODE}] $error{MESSAGE}");
		return;
	}
	%data = apiData($msg);
	
	# Stop if no notifications are needed
	if(!%data) {
		logMsg($LOG,$PROGRAM,"There are no unnotified distributions on the Portal");
		return;
	}
		
	# Process each combination of node and film
	# Build up a hash of film details for each site and send before next site is processed
	foreach my $key (sort keys %data) {
		$distid = $data{$key}{dist_id};
		$distname = $data{$key}{dist_name};
		$node = $data{$key}{node_name};
		$notify = $data{$key}{node_email};
		$provider = $data{$key}{provider};
		$site = $data{$key}{site};
		$asset = $data{$key}{content};
		$abort = $data{$key}{abort};
		
		# If same node, add next set of film details to hash
		if($lastdist[0] == $distid) {
			$films{"$provider:$site:$asset"} = [ ($provider,$site,$asset,$abort) ];
		}
		# Node has changed, so send email for the last node
		else {
			# Don't process email if this is the first iteration
			if($lastdist[0]) {
				dist_notify_email_send(@lastdist,%films);
			}
			
			# Save the current node details
			@lastdist = ($distid,$distname,$node,$notify,$abort);
			
			# Clear the hash and add the current film record
			%films = ();
			$films{"$provider:$site:$asset"} = [ ($provider,$site,$asset,$abort) ];
		}
	}
	
	# Send the email for the last node
	dist_notify_email_send(@lastdist,%films);
}



# ---------------------------------------------------------------------------------------------
# Return the body of the email
#
# Argument 1 : Name of the node
# Argument 2 : Name of the distribution
# Argument 3 : Hash of 4 element arrays (provider,site,title,abort)
#
# Return the formatted body of the email
# ---------------------------------------------------------------------------------------------
sub dist_notify_email_body {
	my($node,$distname,%films) = @_;
	my($provider,$site,$title,$genre,$abort,$status);
	my $lastprov = '';
	my $lastsite = '';
	my $newline = "<br>";
	my $body = '';
	
	# Content section of the email
	foreach my $key (sort keys %films) {
		# Read site and film related data
		$provider = @{$films{$key}}[0];
		$site = @{$films{$key}}[1];
		$title = @{$films{$key}}[2];
		$abort = @{$films{$key}}[3];
		
		# Genre heading
		if($lastprov ne $provider) {
			$lastprov = $provider;
			$genre = ($provider eq 'PBTV') ? "Adult" : "Hollywood";
			$status = ($abort eq 'true') ? "has <b>NOT</b> been" : "has been";
			$body .= "$newline";
			$body .= <<GENRE;
The following <b>$genre</b> content $status downloaded by CDS to node <b>$node</b> in batch <b>$distname</b>.$newline$newline
GENRE
		}
		
		# Site name
		if($lastsite ne $site) {
			$lastsite = $site;
			$body .= <<SITE;
<b>$site</b> $newline
SITE
		}
		
		# Print the film title
		$body .= <<FILM;
- $title $newline
FILM
	}
	
	# Closing section of the email
	$body .= <<END;
$newline
$newline
$CONFIG{DIST_EMAIL_NAME} $newline
$CONFIG{DIST_EMAIL_COMPANY} $newline
Phone: $CONFIG{DIST_EMAIL_PHONE} $newline
Email: $CONFIG{DIST_EMAIL_FROM} $newline
END
	
	# Return the body of the email
	return $body;
}



# ---------------------------------------------------------------------------------------------
# Send a notification email with the films delivered to the node
#
# Argument 1 : Distribution ID
# Argument 2 : Distribution name
# Argument 3 : CDS node name for the site
# Argument 4 : Email address of the site administrator
# Argument 5 : Has this distribution been aborted?
# Argument 6 : Hash of 4 element arrays (provider,site,title,abort)
# ---------------------------------------------------------------------------------------------
sub dist_notify_email_send {
	my($distid,$distname,$node,$to,$abort,%films) = @_;
	my($body,$status,$rc);
	
	# Generate the body of the email
	$body = dist_notify_email_body($node,$distname,%films);
	
	# Strip out all new lines
	$body =~ s/\n//g;
	
	# Send the email
	$status = ($abort eq 'true') ? 'aborted' : 'finished';
	$rc = email_send($status,$distname,$node,$to,$body);
	
	# If email sent without problems, update the notified date on the distribution
	if($rc) {
		dist_notify_update_notified($distid,$distname);
	}
}



# ---------------------------------------------------------------------------------------------
# Update the notified date for the batch on the Portal
#
# Argument 1 : ID of the distribution
# Argument 2 : Name of the distribution
# ---------------------------------------------------------------------------------------------
sub dist_notify_update_notified {
	my($distid,$distname) = @_;
	my($status,$msg,%error,$notified);
	
	# If batch not specified, don't update
	if(!$distid) {
		logMsgPortal($LOG,$PROGRAM,'W',"Notify: Unable to update the notified date as no distribution ID given");
		return;
	}
	
	# Update the notified date on the distribution
	$notified = formatDateTime('zd Mon ccyy zh24:mi');
	$msg = apiDML('cdsUpdateNotified',"id=$distid","notified='$notified'");
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"Notify: Notified date NOT updated for distribution '$distname' [$error{CODE}] $error{MESSAGE}");
	}
	else {
		logMsg($LOG,$PROGRAM,"Notified date set to $notified for distribution [$distname]");
	}
}



# ---------------------------------------------------------------------------------------------
# Prepare the files for a distribution on CDS
# This is done through links from the Content Repository
# ---------------------------------------------------------------------------------------------
sub dist_prepare {
	my($status,$msg,%error,%distros,$errorfound,$distdir,$res,$source,%subtitles,$file,%distribution,$pending,%meta);
	my($distid,$distname,$filmcode,$package,$provider);
	
	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");
	logMsg($LOG,$PROGRAM,"Prepare the files for a distribution on CDS");
	
	# Read package details from Portal
	dist_prepare_packages();
	
	# Read details of scheduled distributions
	$msg = apiSelect('cdsPrepare');
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Problem finding distributions for the preparation stage [$error{CODE}] $error{MESSAGE}");
		return;
	}
	%distros = apiData($msg);
	
	# Stop if there is nothing to process
	if(!%distros) {
		logMsg($LOG,$PROGRAM,"No distributions ready for the preparation stage");
		return;
	}
	
	# -----------------------------------------------------------------
	# Create links to files to be distributed
	# Key is distribution ID || film code
	# Process each record which is unique for a distribution and film
	# -----------------------------------------------------------------
	DISTRO: foreach my $key (sort keys %distros) {
		$distid = $distros{$key}{dist_id};
		$distname = $distros{$key}{dist_name};
		$filmcode = $distros{$key}{asset_code};
		$package = $distros{$key}{package};
		$provider = $distros{$key}{provider};
		logMsg($LOG,$PROGRAM,"Distribution [$distname]");
		logMsg($LOG,$PROGRAM,"Preparing [$filmcode] using package [$package]");
		
		# Clear the error flag
		$errorfound = 0;
		
		# Check the package for the distribution
		if (!$package) {
			$errorfound = 1;
			logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Invalid package for distribution [$distname]");
		}
		
		# ----------------------------------------------------------------------------
		# Determine location of the distribution directory
		# If sub-directory specified, add to root directory and substitute asset name
		# ----------------------------------------------------------------------------
		$distdir = "$CONFIG{DISTRIBUTION}/$distname";
		if($PACKAGES{$package}{distribution}{directory}) {
			$distdir .= "/$PACKAGES{$package}{distribution}{directory}";
			$distdir =~ s/\[asset\]/$filmcode/g;
		}
		
		# Create the distribution directory if needed
		if(!-d $distdir) {
			$res = `mkdir -p $distdir 2>&1`;
			if($res) {
				$errorfound = 1;
				logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Unable to create directory [$distdir]: $res");
			}
			else {
				logMsg($LOG,$PROGRAM,"Creating directory [$distdir]");
			}
		}
		
		# ----------------------------------------------------------------------------
		# Read the metadata from the Portal and create a file (JSON or XML)
		# ----------------------------------------------------------------------------
		foreach my $type (sort keys %{$PACKAGES{$package}{metadata}}) {
			if ($type eq 'json' || $type eq 'xml') {
				$msg = apiMetadata('apMetadata',$filmcode,$type);
				($status,%error) = apiStatus($msg);
				if(!$status) {
					$errorfound = 1;
					logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Could not read metadata [$type] from Portal [$error{CODE}] $error{MESSAGE}");
				}
				else {
					%meta = apiData($msg);
					if ($type eq 'json') {
						$msg = Dumper(\%meta);
					}
					else {
						$msg = $meta{xml};
						$msg =~ s/&quot;/"/g;
					}
					writeFile("$distdir/$filmcode.$type",$msg);
				}
				# 08/10/2015 BF TEMPORARY DEBUG : WRITE METADATA TO TEMP FILE IN ALL CASES
				writeFile("$CONFIG{DIST_META}/$filmcode.$type",$msg);
			}
			else {
				$errorfound = 1;
				logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Unrecognised type of metadata [$type]");
			}
		}
		
		# ----------------------------------------------------------------------------
		# Download the images from the Portal
		# ----------------------------------------------------------------------------
		foreach my $type (sort keys %{$PACKAGES{$package}{image}}) {
			if ($type eq 'small' || $type eq 'large' || $type eq 'full' || $type eq 'hero' || $type eq 'landscape') {
				$msg = apiFileDownload("$filmcode-$type.jpg","$CONFIG{PORTAL_IMAGES}/$provider/$filmcode","$filmcode-$type.jpg",$distdir);
				($status,%error) = apiStatus($msg);
				if(!$status) {
					$errorfound = 1;
					logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Could not download image [$type] from Portal [$error{CODE}] $error{MESSAGE}");
				}
			}
			else {
				$errorfound = 1;
				logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Unrecognised type of image [$type]");
			}
		}
		
		# ----------------------------------------------------------------------------
		# If specified in package, download VTT sub-title files from the Portal
		# ----------------------------------------------------------------------------
		if($PACKAGES{$package}{subtitle}) {
			# Read details of scheduled distributions
			$msg = apiSelect('cdsPrepareSubtitles',"assetcode=$filmcode");
			($status,%error) = apiStatus($msg);
			if(!$status) {
				$errorfound = 1;
				logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Problem reading list of sub-title files [$error{CODE}] $error{MESSAGE}");
			}
			else {
				%subtitles = apiData($msg);
				foreach my $subtitle (keys %subtitles) {
					$msg = apiFileDownload($subtitle,"$CONFIG{PORTAL_VTT}/$provider/$filmcode",$subtitle,$distdir);
					($status,%error) = apiStatus($msg);
					if(!$status) {
						$errorfound = 1;
						logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Could not download sub-title file [$subtitle] from Portal [$error{CODE}] $error{MESSAGE}");
					}
				}
			}
		}
		
		# ----------------------------------------------------------------------------
		# Prepare the film file
		# ----------------------------------------------------------------------------
		# Read film source directory, substitute asset name, then check it exists
		$source = "$PACKAGES{$package}{film}{source}";
		$source =~ s/\[asset\]/$filmcode/g;
		if(!-d $source) {
			logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Unable to read film directory '$source' for package '$package'");
			$errorfound = 1;
			# Skip remaining checks as they will all fail
			next DISTRO;
		}
		
		# Find the name of the most recent film file
		if($PACKAGES{$package}{film}{clear}) {
			$file = dist_prepare_file_name($source,$PACKAGES{$package}{film}{clear});
		}
		elsif($PACKAGES{$package}{film}{securemedia}) {
			$file = dist_prepare_file_name($source,$PACKAGES{$package}{film}{securemedia});
		}
		elsif($PACKAGES{$package}{film}{verimatrix}) {
			$file = dist_prepare_file_name($source,$PACKAGES{$package}{film}{verimatrix});
		}
		else {
			logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Film type for package '$package' can only be: clear, securemedia or verimatrix");
			$errorfound = 1;
			# Skip remaining checks as they will all fail
			next DISTRO;
		}
		
		# Check whether film file exists
		if(!-f "$source/$file") {
			logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Film file not found '$source/$file'");
			$errorfound = 1;
		}
		else {
			# Drop existing link to film file
			if(-l "$distdir/$file") {
				$res = `rm $distdir/$file 2>&1`;
				if($res) {
					logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Unable to delete existing link to film file '$distdir/$file': $res");
					$errorfound = 1;
				}
			}
			
			# Create link
			$res = `ln -s $source/$file $distdir/$file 2>&1`;
			if($res) {
				logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Unable to create link to film file '$source/$file': $res");
				$errorfound = 1;
			}
			else {
				logMsg($LOG,$PROGRAM,"Created link to film file '$source/$file'");
				# If link created successfully to securemedia file, link the SMA and MDM files as well
				# Don't need to check for errors as these files will exist if the main securemedia file exists
				if($PACKAGES{$package}{film}{securemedia}) {
					$res = `ln -s $source/$file.mdm $distdir/$file.mdm 2>&1`;
					$res = `ln -s $source/$file.sma $distdir/$file.sma 2>&1`;
				}
			}
		}
		
		# ----------------------------------------------------------------------------
		# Prepare the trailer file
		# ----------------------------------------------------------------------------
		# Read trailer source directory, substitute asset name, then check it exists
		if($PACKAGES{$package}{trailer}{source}) {
			$source = "$PACKAGES{$package}{trailer}{source}";
			$source =~ s/\[asset\]/$filmcode/g;
			if(!-d $source) {
				logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Unable to read trailer directory '$source' for package '$package'");
				$errorfound = 1;
				# Skip remaining checks as they will all fail
				next DISTRO;
			}
			
			# Substitute the asset name
			# TODO Does not cater for encrypted trailers
			$file = $PACKAGES{$package}{trailer}{clear};
			$file =~ s/\[asset\]/$filmcode/g;
			
			# Check whether trailer file exists (optional, as film may not have a trailer)
			if(-f "$source/$file") {
				# Delete link if it already already exists
				if(-l "$distdir/$file") {
					$res = `rm $distdir/$file 2>&1`;
					if($res) {
						logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Unable to delete existing link to trailer file '$distdir/$file': $res");
						$errorfound = 1;
					}
				}
				
				# Create link
				$res = `ln -s $source/$file $distdir/$file 2>&1`;
				if($res) {
					logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Unable to create link to trailer file '$source/$file': $res");
					$errorfound = 1;
				}
				else {
					logMsg($LOG,$PROGRAM,"Created link to trailer file '$source/$file'");
				}
			}
		}
		
		# ----------------------------------------------------------------------------
		# If the error count has already been initialised, add the current status,
		# otherwise initialise the error count with the current status
		# ----------------------------------------------------------------------------
		if(defined($distribution{$distid})) {
			$distribution{$distid} = [($distname,(@{$distribution{$distid}})[1]+$errorfound)];
		}
		else {
			$distribution{$distid} = [($distname,$errorfound)];
		}
	}
	
	# ------------------------------------------------------------------
	# Update each error free distribution record with pending date/time
	# ------------------------------------------------------------------
	foreach $distid (sort keys %distribution) {
		# Check whether any errors have been raised for films in the distribution
		($distname,$errorfound) = @{$distribution{$distid}};
		if($errorfound) {
			# Errors found, so back out gracefully
			logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Errors found while preparing distribution '$distname'");
			
			# Remove the directory tree and all files for the distribution
			$distdir = "$CONFIG{DISTRIBUTION}/$distname";
			if(-d $distdir) {
				$res = `rm -r $distdir 2>&1`;
				if($res) {
					logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Unable to remove directory '$distdir': $res");
				}
				else {
					logMsg($LOG,$PROGRAM,"Prepare: Removing directory [$distdir]");
				}
			}
		}
		else {
			# No errors found, so update the pending date on distribution record
			$pending = formatDateTime('zd Mon ccyy zh24:mi');
			$msg = apiDML('cdsUpdatePending',"id=$distid","pending='$pending'");
			($status,%error) = apiStatus($msg);
			if(!$status) {
				logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Unable to update distribution record '$distname' with pending date/time [$error{CODE}] $error{MESSAGE}");
			}
			else {
				logMsg($LOG,$PROGRAM,"Updated distribution record [$distname] with pending date/time");
			}
		}
	}
	
	# Catalogue the Airwave Distribution node to register the new distributions with CDS
	dist_catalogue();
}



# ---------------------------------------------------------------------------------------------
# Find the file name of an asset from the XML metadata file
#
# Argument 1 : Repository directory holding the film files
# Argument 2 : Film name pattern to be matched
#
# Return the asset file name, or undef if file can't be found or error in document
# ---------------------------------------------------------------------------------------------
sub dist_prepare_file_name {
	my($repodir,$pattern) = @_;
	my($dh,@files,$newest);
	
	# Read the list of files in the asset directory
	if(!opendir($dh,$repodir)) {
		# Problem reading the directory
		logMsgPortal($LOG,$PROGRAM,'W',"Prepare: Unable to read directory '$repodir'");
		return;
	}
	else {
		# Read the files then close the directory handle
		@files = grep { /$pattern/ } sort readdir($dh);
		closedir($dh);
		
		# Select the most recent film file
		# TEMPORARY - USES THE LENGTH OF THE FILE NAME
		$newest = '';
		foreach my $file (@files) {
			# If first file
			if(!$newest) { $newest = $file; }
			
			# Is next file more recent?
			if(length($file) > length($newest)) {
				$newest = $file;
			}
		}
		
		# Return the name of the newest film
		return $newest;
	}
}



# ---------------------------------------------------------------------------------------------
# Read package definitions from the Portal
# ---------------------------------------------------------------------------------------------
sub dist_prepare_packages {
	my($status,$msg,%error,%packs,$package,$class,$type,$value);
	
	# Read list of packages from Portal
	$msg = apiSelect('cdsPreparePackages');
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"Prepare: Problem reading list of packages [$error{CODE}] $error{MESSAGE}");
		exit;
	}
	%packs = apiData($msg);
	
	# Populate global hash of packages
	%PACKAGES = ();
	foreach my $id (sort keys %packs) {
		$package = $packs{$id}{package};
		$class = $packs{$id}{class};
		$type = $packs{$id}{type};
		$value = $packs{$id}{file};
		
		$value =~ s/~bslash/\\/g;
		$PACKAGES{$package}{$class}{$type} = $value;
	}
}



# ---------------------------------------------------------------------------------------------
# Check whether any new distributions can be started on CDS, and start if they can
# ---------------------------------------------------------------------------------------------
sub dist_start {
	my($ok,$cdsref,%cds,$running,@runningnodes,$new);
	
	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");
	logMsg($LOG,$PROGRAM,"Start distributions on CDS");
	
	# Retrieve the list of running distributions
	($ok, $cdsref) = cds_sql_running();
	if(!$ok) {
		logMsg($LOG,$PROGRAM,"Could not read active distributions from the CDS Portal");
		return;
	}
	%cds = %$cdsref;
	
	# Create a list of sites that have running distributions
	$running = keys(%cds);
	foreach my $key (keys %cds) {
		push(@runningnodes,$cds{$key}{Site});
	}
	
	# Check number of distributions currently running on CDS against max number of concurrent
	# processes allowed to see whether new distributions can be started
	if($running < $CONFIG{CDS_MAX_CONCURRENT}) {
		# Start new processes
		$new = $CONFIG{CDS_MAX_CONCURRENT} - $running;
		logMsg($LOG,$PROGRAM,"Starting distributions: $running running, $new can be started, ".$CONFIG{CDS_MAX_CONCURRENT}." maximum");
		dist_start_new($new,@runningnodes);
	}
	else {
		# Don't carry on as max number of processes running
		logMsg($LOG,$PROGRAM,"No new distributions started, as $running processes running");
		return;
	}
}



# ---------------------------------------------------------------------------------------------
# Start a set of distributions on CDS
#
# Argument 1 : Number of processes that can be started
# Argument 2 : Array of node names that have running distributions
# ---------------------------------------------------------------------------------------------
sub dist_start_new {
	my($new,@runningnodes) = @_;
	my(%sites,$site,$free,%freesite,%data,%content,@distlist,$seq,$response,$err,$xpc,@nodes,$cdsdistid,$ok,$cdsref,%cds,$start,%films);
	my($status,$msg,%error,%distros,$distname,$distid,$cdsnode,$notify,$contentid,$nodeid,$fs_node,$fs_free);
	my %to_be_distrib = ();
	
	# ---------------------------------------------------------
	# Retrieve list of nodes and catalogued content from CDS
	# ---------------------------------------------------------
	# Retrieve details of active sites from CDS
	%sites = cds_sql_sites();
	
	# Stop if no sites are found (i.e. can't connect to CDS)
	if(!%sites) {
		logMsg($LOG,$PROGRAM,"Can't connect to the CDS Portal");
		return;
	}
	
	# Only keep nodes on which no distributions are running (free)
	foreach my $id (keys %sites) {
		$free = 1;
		foreach my $running (@runningnodes) {
			if($sites{$id}{Site} eq $running) {
				$free = 0;
			}
		}
		if($free) {
			# Add a flag that will be unset when a distribution is sent to the site
			$freesite{$sites{$id}{Site}} = [($id,1)];
		}
	}
	
	# Retrieve catalogued content on CDS
	%data = cds_sql_content();
	
	# Stop if no catalogued content is found (or maybe unable to connect to CDS)
	if(!%data) {
		logMsg($LOG,$PROGRAM,"Can't read any catalogued content from the CDS Portal");
		return;
	}
	
	# Extract bundle IDs
	foreach my $id (keys %data) {
		$content{$data{$id}{Bundle}} = $id;
	}
	
	# -----------------------------------------------------------
	# Find pending distributions with catalogued content on CDS
	# -----------------------------------------------------------
	# Read all pending distributions from Portal
	$msg = apiSelect('cdsStart');
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"Start: Can't read list of pending distributions [$error{CODE}] $error{MESSAGE}");
		return;
	}
	%distros = apiData($msg);
	
	# Stop if there are no pending distributions
	if(!%distros) {
		logMsg($LOG,$PROGRAM,"There are no pending distributions on the Portal");
		return;
	}
	
	# Select only distributions that have catalogued content on CDS as only these can be started
	# Key is sequence in which to be run
	foreach my $seq (sort keys %distros) {
		$distname = $distros{$seq}{dist_name};
		$distid = $distros{$seq}{dist_id};
		$cdsnode = $distros{$seq}{node_name};
		$notify = $distros{$seq}{node_email};
		
		# Pending distribution record from Portal must match catalogued content on CDS
		foreach my $bundle (keys %content) {
			$contentid = $content{$bundle};
			
			# If distribution and catalogue names match, find CDS node ID
			if($bundle eq $distname) {
				# Loop through each CDS node
				$nodeid = 0;
				foreach my $site (keys %freesite) {
					($fs_node,$fs_free) = @{$freesite{$site}};
					# If CDS node name matches CDS node name on distribution record from Portal,
					# and a distribution has not been scheduled in this run, save ID
					if($site eq $cdsnode && $fs_free) {
						$nodeid = $fs_node;
						# Unset flag that marks when a distribution is sent to the site
						# This is to stop multiple distributions being sent to a CDS node
						$freesite{$site} = [($fs_node,0)];
					}
				}
				
				# Save distribution and node details, skip if node not found on CDS
				if($nodeid != 0) {
					$to_be_distrib{$seq} = [($distid,$distname,$contentid,$nodeid,$cdsnode,$notify)];
				}
			}
		}
	}
	
	# Stop if there is nothing to be distributed
	if(!%to_be_distrib) {
		logMsg($LOG,$PROGRAM,"No catalogued content found on CDS for distribution");
		return;
	}
	
	# ---------------------------------------------------------
	# Initiate a CDS start request for each distribution
	# ---------------------------------------------------------
	@distlist = sort keys %to_be_distrib;
	
	# Limit to miximum that can be started or total scheduled, whichever is less
	$new = ($new > @distlist) ? @distlist : $new;
	DISTSTART: for(my $i=0; $i<$new; $i++) {
		$seq = $distlist[$i];
		($distid,$distname,$contentid,$nodeid,$cdsnode,$notify) = @{$to_be_distrib{$seq}};
		
		# Build the CDS command to start the distribution
		$response = cds_command('sendcontent',$contentid,$nodeid);
		if(!$response) {
			logMsgPortal($LOG,$PROGRAM,'W',"Start: Unable to start distribution '$distname' on CDS");
			next DISTSTART;
		}
		logMsg($LOG,$PROGRAM,"Started distribution [$distname] on CDS");
		
		# Read the CDS distribution ID from the response document
		($err,$xpc) = parseDocument('string',$response);
		if(!$xpc) {
			logMsgPortal($LOG,$PROGRAM,'E',"Start: Unable to open the XML document: $response: $err");
			return;
		}
		@nodes = $xpc->findnodes("/cds:response/cds:distribution");
		if(!@nodes) {
			logMsgPortal($LOG,$PROGRAM,'E',"Start: Unable to extract the nodes from the response document");
			next DISTSTART;
		}
		$cdsdistid = $nodes[0]->getAttribute('id');
		
		# Retrieve the list of running distributions
		($ok, $cdsref) = cds_sql_running();
		if(!$ok) {
			logMsg($LOG,$PROGRAM,"Could not read active distributions from the CDS Portal");
			return;
		}
		%cds = %$cdsref;
		
		# Stop if no running distributions are found (or maybe unable to connect to CDS)
		if(!%cds) {
			logMsg($LOG,$PROGRAM,"No distributions running on the CDS Portal");
			return;
		}
		
		# Convert from CDS date to Portal date
		$start = convertCDSdate($cds{$cdsdistid}{Start});
		
		# Update started date on distribution record
		$msg = apiDML('cdsUpdateStarted',"id=$distid","started='$start'");
		($status,%error) = apiStatus($msg);
		if(!$status) {
			logMsgPortal($LOG,$PROGRAM,'E',"Start: Started date NOT updated [$error{CODE}] $error{MESSAGE}");
		}
		else {
			logMsg($LOG,$PROGRAM,"Updated distribution [$distname] with start date/time");
			
			# Build up a hash of film details for each site within the distribution
			$msg = apiSelect('cdsStartDistFilms',"id=$distid");
			($status,%error) = apiStatus($msg);
			if(!$status) {
				logMsgPortal($LOG,$PROGRAM,'E',"Start: No films returned for distribution '$distname' [$error{CODE}] $error{MESSAGE}");
				return;
			}
			%films = apiData($msg);
			
			# Send the email for the distribution node
			dist_start_email_send($distname,$cdsnode,$notify,%films);
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Send a notification email listing the films scheduled for delivery to the node
#
# Argument 1 : Distribution name
# Argument 2 : CDS node name for the site
# Argument 3 : Email address of the site administrator
# Argument 4 : Hash of 2 element arrays (provider,title)
# ---------------------------------------------------------------------------------------------
sub dist_start_email_send {
	my($distname,$node,$to,%films) = @_;
	my($provider,$title,$genre);
	my $lastprov = '';
	my $newline = "<br>";
	my $body = '';
	
	# Content section of the email
	foreach my $key (sort keys %films) {
		# Read site and film related data
		$provider = $films{$key}{provider};
		$title = $films{$key}{title};
		
		# Genre heading
		if($lastprov ne $provider) {
			$lastprov = $provider;
			$genre = ($provider eq 'PBTV') ? "Adult" : "Hollywood";
			$body .= "$newline";
			$body .= <<GENRE;
The following <b>$genre</b> content has been scheduled for download by CDS to node <b>$node</b> in batch <b>$distname</b>.$newline$newline
GENRE
		}
		
		# Print the film title
		$body .= <<FILM;
- $title $newline
FILM
	}
	
	# Closing section of the email
	$body .= <<END;
$newline
$newline
$CONFIG{DIST_EMAIL_NAME} $newline
$CONFIG{DIST_EMAIL_COMPANY} $newline
Phone $CONFIG{DIST_EMAIL_PHONE} $newline
Email $CONFIG{DIST_EMAIL_FROM} $newline
END
	
	# Strip out all new lines
	$body =~ s/\n//g;
	
	# Send the email
	email_send('started',$distname,$node,$to,$body);
}



# ---------------------------------------------------------------------------------------------
# Stop a distribution on CDS
# ---------------------------------------------------------------------------------------------
sub dist_stop {
	my($status,$msg,%error,%distros,$ok,$cdsref,%cds,$distname,$cdsid,$ended,$response,$distdir,$res);
	
	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");
	logMsg($LOG,$PROGRAM,"Abort requested distributions on CDS");
	
	# Read all pending distributions from the Portal
	$msg = apiSelect('cdsAbort');
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"Stop: No sites have distributions to be aborted [$error{CODE}] $error{MESSAGE}");
		return;
	}
	%distros = apiData($msg);
	
	# Stop if there are no pending distributions
	if(!%distros) {
		logMsg($LOG,$PROGRAM,"There are no distributions to be aborted on the Portal");
		return;
	}
	
	# Retrieve the list of running distributions
	($ok, $cdsref) = cds_sql_running();
	if(!$ok) {
		logMsg($LOG,$PROGRAM,"Could not read active distributions from the CDS Portal");
		return;
	}
	%cds = %$cdsref;
	
	# Stop if no running distributions are found (or maybe unable to connect to CDS)
	if(!%cds) {
		logMsg($LOG,$PROGRAM,"No distributions running on the CDS Portal");
		return;
	}
	
	# Abort each distribution
	foreach my $cmsid (keys %distros) {
		$distname = $distros{$cmsid}{distribution};
		logMsg($LOG,$PROGRAM,"Aborting distribution [$distname]");
		
		# Find the CDS distribution ID from the distribution name
		foreach my $id (keys %cds) {
			if($cds{$id}{Bundle} eq $distname) {
				$cdsid = $id;
			}
		}
		
		# Stop the distribution on CDS
		$response = cds_command('abortdistribution',$cdsid);
		if(!$response) {
			logMsgPortal($LOG,$PROGRAM,'E',"Stop: Unable to abort distribution '$distname' on CDS");
			return;
		}
		
		# Flag as ended on the Portal
		$ended = formatDateTime('zd Mon ccyy zh24:mi');
		$msg = apiDML('cdsUpdateEnded',"id=$cmsid","ended='$ended'");
		($status,%error) = apiStatus($msg);
		if(!$status) {
			logMsgPortal($LOG,$PROGRAM,'E',"Stop: Ended date for distribution '$distname' has not been set on Portal [$error{CODE}] $error{MESSAGE}");
		}
		
		# Remove the directory tree and all files for the distribution
		$distdir = "$CONFIG{DISTRIBUTION}/$distname";
		if(-d $distdir) {
			$res = `rm -r $distdir 2>&1`;
			if($res) {
				logMsgPortal($LOG,$PROGRAM,'E',"Stop: Unable to remove directory '$distdir': $res");
			}
			else {
				logMsg($LOG,$PROGRAM,"Stop: Removing directory [$distdir]");
			}
		}
		
		# All done
		logMsg($LOG,$PROGRAM,"Aborted distribution [$distname] on CDS");
	}
}



# ---------------------------------------------------------------------------------------------
# Update the status of a CDS distribution
# ---------------------------------------------------------------------------------------------
sub dist_status {
	my($ok,$cdsref,%cds,$status,$msg,%error,%cms,$batch,@sites,$nod,$pct,$err);
	
	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");
	logMsg($LOG,$PROGRAM,"Check the status of distributions running on CDS");
	
	# Retrieve the list of running distributions
	($ok, $cdsref) = cds_sql_running();
	if(!$ok) {
		logMsg($LOG,$PROGRAM,"Could not read active distributions from the CDS Portal");
		return;
	}
	%cds = %$cdsref;
	
	# Stop if no running distributions are found (or maybe unable to connect to CDS)
	if(!%cds) {
		logMsg($LOG,$PROGRAM,"No distributions running on the CDS Portal");
		return;
	}
	
	# Read the list of running batches from the Portal
	$msg = apiSelect('cdsStarted');
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsg($LOG,$PROGRAM,"Status: Could not read list of active distributions");
		return;
	}
	
	# Read list of running batches
	%cms = apiData($msg);
	if(!%cms) {
		logMsg($LOG,$PROGRAM,"Status: No sites have active distributions");
		return;
	}
	
	# List the running distributions
	logMsg($LOG,$PROGRAM,"STATUS OF ACTIVE DISTRIBUTIONS");
	foreach my $key (sort keys %cds) {
		$batch = $cds{$key}{Bundle};
		foreach my $cmsdistid (keys %cms) {
			# If Distribution and CDS refs match, update the completion and errors for the distribution
			if($cms{$cmsdistid}{dist_name} eq $batch) {
				$pct = $cds{$key}{Progress};
				$err = $cds{$key}{Errors};
				$msg = apiDML('cdsUpdateStatus',"id=$cmsdistid","completion=$pct","errors=$err");
				($status,%error) = apiStatus($msg);
				if(!$status) {
					logMsgPortal($LOG,$PROGRAM,'E',"Status: Status values NOT updated for batch '$batch' [$error{CODE}] $error{MESSAGE}");
				}
				else {
					logMsg($LOG,$PROGRAM,"$batch - $pct% ($err errors)");
				}
			}
		}
	}
}



# ---------------------------------------------------------------------------------------------
# List finished distributions on CDS
# ---------------------------------------------------------------------------------------------
sub list_complete {
	my($response,%cds,@sites,@files);
	my($to,$from) = months_offset(1);
	
	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");
	logMsg($LOG,$PROGRAM,"List finished distributions on CDS");
	
	# Run CDS command
	$response = cds_command('listaudit',$from,$to);
	if(!$response) {
		logMsg($LOG,$PROGRAM,"Unable to retrieve the list of completed distributions on CDS");
		return;
	}
	
	# Extract the distribution data from the CDS message
	%cds = extract_distribution_data($response);
	
	# List the completed distribution data
	logMsg($LOG,$PROGRAM,"DISTRIBUTIONS COMPLETED BETWEEN ".substr($from,0,10)." AND ".substr($to,0,10));
	foreach my $key (sort keys %cds) {
		logMsg($LOG,$PROGRAM,$cds{$key}{CONTENT_NAME});
		logMsg($LOG,$PROGRAM,"  Dist. ID  : $key");
		logMsg($LOG,$PROGRAM,"  Method    : ".$cds{$key}{DIST_MODE});
		logMsg($LOG,$PROGRAM,"  Encrypted : ".$cds{$key}{DIST_ENCRYPT});
		logMsg($LOG,$PROGRAM,"  Priority  : ".$cds{$key}{DIST_PRIORITY});
		logMsg($LOG,$PROGRAM,"  Started   : ".$cds{$key}{DIST_START});
		logMsg($LOG,$PROGRAM,"  Finished  : ".$cds{$key}{DIST_END});
		@sites = @{$cds{$key}{SITES}};
		logMsg($LOG,$PROGRAM,"  Sites:");
		foreach my $site (@sites) {
			logMsg($LOG,$PROGRAM,"    - ".(@$site)[1].' ('.(@$site)[3]." errors)");
		}
		@files = @{$cds{$key}{FILES}};
		logMsg($LOG,$PROGRAM,"  Files:");
		foreach my $file (@files) {
			logMsg($LOG,$PROGRAM,"    - ".(@$file)[1].' ('.(@$file)[2].")");
		}
	}
}



# ---------------------------------------------------------------------------------------------
# List active distributions on CDS
# ---------------------------------------------------------------------------------------------
sub list_running {
	my($response,%cds,@sites,@files);
	my($to,$from) = months_offset(1);
	
	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");
	logMsg($LOG,$PROGRAM,"List distributions running on CDS");
	
	# Run CDS command
	$response = cds_command('listdistributions',$from,$to);
	if(!$response) {
		logMsg($LOG,$PROGRAM,"Unable to retrieve the list of distributions running on CDS");
		return;
	}
	
	# Extract the data for running distributions from the CDS message
	%cds = extract_distribution_data($response);
	
	# List the running distributions
	logMsg($LOG,$PROGRAM,"ACTIVE DISTRIBUTIONS STARTED BETWEEN ".substr($from,0,10)." AND ".substr($to,0,10));
	foreach my $key (sort keys %cds) {
		logMsg($LOG,$PROGRAM,$cds{$key}{CONTENT_NAME});
		logMsg($LOG,$PROGRAM,"  Dist. ID : $key");
		logMsg($LOG,$PROGRAM,"  Method   : ".$cds{$key}{DIST_MODE});
		logMsg($LOG,$PROGRAM,"  Encrypted: ".$cds{$key}{DIST_ENCRYPT});
		logMsg($LOG,$PROGRAM,"  Priority : ".$cds{$key}{DIST_PRIORITY});
		logMsg($LOG,$PROGRAM,"  Started  : ".$cds{$key}{DIST_START});
		logMsg($LOG,$PROGRAM,"  Ended  : ".$cds{$key}{DIST_END});
		@sites = @{$cds{$key}{SITES}};
		logMsg($LOG,$PROGRAM,"  Sites:");
		foreach my $site (@sites) {
			logMsg($LOG,$PROGRAM,"    - ".(@$site)[1].' ('.(@$site)[3]." errors)");
		}
		@files = @{$cds{$key}{FILES}};
		logMsg($LOG,$PROGRAM,"\tFiles:");
		foreach my $file (@files) {
			logMsg($LOG,$PROGRAM,"    - ".(@$file)[1].' ('.(@$file)[2].")");
		}
	}
}



# ---------------------------------------------------------------------------------------------
# List the catalogued content on the CDS node
# ---------------------------------------------------------------------------------------------
sub list_content {
	my($response,$err,$xpc,@nodes,@child,$cid,$cname,$nid,$nname);
	
	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");
	logMsg($LOG,$PROGRAM,"List catalogued content on CDS");
	
	# Run CDS command
	$response = cds_command('listcontent');
	if(!$response) {
		logMsg($LOG,$PROGRAM,"Unable to retrieve the list of content packages on CDS");
		return;
	}
	
	# Extract the list of content
	($err,$xpc) = parseDocument('string',$response);
	if(!$xpc) {
		logMsg($LOG,$PROGRAM,"Unable to open the XML document: $response");
		logMsg($LOG,$PROGRAM,$err);
		return;
	}
	@nodes = $xpc->findnodes("/cds:response/cds:contentlist/cds:content");
	if(!@nodes) {
		logMsg($LOG,$PROGRAM,"Unable to extract the content element from the response document");
		return;
	}
	foreach my $node (@nodes) {
		$cid = $node->getAttribute('id');
		@child = $node->findnodes("cds:name");
		$cname = $child[0]->textContent;
		@child = $node->findnodes("cds:node");
		$nid = $child[0]->getAttribute('id');
		@child = $child[0]->findnodes("cds:name");
		$nname = $child[0]->textContent;
		
		# Print content
		logMsg($LOG,$PROGRAM,"  $cname [$cid]");
	}
}



# ---------------------------------------------------------------------------------------------
# List groups on a CDS node
# ---------------------------------------------------------------------------------------------
sub list_groups {
	my($response,$err,$xpc,@nodes,@child,$gid,$gname,%groups);
	
	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");
	logMsg($LOG,$PROGRAM,"List groups on CDS");
	
	# Run CDS command
	$response = cds_command('listgroups');
	if(!$response) {
		logMsg($LOG,$PROGRAM,"Unable to retrieve the list of groups on CDS");
		return;
	}
	
	# Extract the list of content
	($err,$xpc) = parseDocument('string',$response);
	if(!$xpc) {
		logMsg($LOG,$PROGRAM,"Unable to open the XML document: $response");
		logMsg($LOG,$PROGRAM,$err);
		return;
	}
	@nodes = $xpc->findnodes("/cds:response/cds:grouplist/cds:group");
	if(!@nodes) {
		logMsg($LOG,$PROGRAM,"Unable to extract the group element from the response document");
		return;
	}
	foreach my $node (@nodes) {
		$gid = $node->getAttribute('id');
		@child = $node->findnodes("cds:name");
		$gname = $child[0]->textContent;
		$groups{$gname} = $gid;
	}
	
	# Print the groups in alphabetic order
	foreach my $grp (sort keys %groups) { 
		logMsg($LOG,$PROGRAM,"  $grp [$groups{$grp}]");
	}
}



# ---------------------------------------------------------------------------------------------
# List nodes on CDS
# ---------------------------------------------------------------------------------------------
sub list_nodes {
	my($response,$err,$xpc,@nodes,@child,$id,$state,$name,%nodelist,@array);
	
	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");
	logMsg($LOG,$PROGRAM,"List nodes on CDS");
	
	# Run CDS command
	$response = cds_command('listnodes');
	if(!$response) {
		logMsg($LOG,$PROGRAM,"Unable to retrieve the list of nodes on CDS");
		return;
	}
	
	# Extract the list of content
	($err,$xpc) = parseDocument('string',$response);
	if(!$xpc) {
		logMsg($LOG,$PROGRAM,"Unable to open the XML document: $response");
		logMsg($LOG,$PROGRAM,$err);
		return;
	}
	@nodes = $xpc->findnodes("/cds:response/cds:nodelist/cds:node");
	if(!@nodes) {
		logMsg($LOG,$PROGRAM,"Unable to extract the node element from the response document");
		return;
	}
	foreach my $node (@nodes) {
		$id = $node->getAttribute('id');
		$state = $node->getAttribute('status');
		@child = $node->findnodes("cds:name");
		$name = $child[0]->textContent;
		$nodelist{$id} = [ ($name,$state) ];
	}
	
	# Print the active nodes in alphabetic order
	logMsg($LOG,$PROGRAM,"Active Nodes");
	foreach my $id (sort keys %nodelist) {
		if((@{$nodelist{$id}})[1] eq 'active') {
			push(@array,(@{$nodelist{$id}})[0]." [$id]");
		}
	}
	foreach my $elem (sort @array) {
		logMsg($LOG,$PROGRAM,"  $elem");
	}
	
	# Print the inactive nodes in alphabetic order
	@array = ();
	logMsg($LOG,$PROGRAM,"Offline Nodes");
	foreach my $id (sort keys %nodelist) {
		if((@{$nodelist{$id}})[1] ne 'active') {
			push(@array,(@{$nodelist{$id}})[0]." [$id]");
		}
	}
	foreach my $elem (sort @array) {
		logMsg($LOG,$PROGRAM,"  $elem");
	}
}



# ---------------------------------------------------------------------------------------------
# Run a test message using commands from the '-test' parameter
# ---------------------------------------------------------------------------------------------
sub test {
	my($cmd,$response,@args);
	my($status,$msg,%error,%data,$id,$key);
	my $bundle = 'aaa-bbb-ccc-ddd';
	my $bundleid = 2107;
	my $scheduled = '22 Sep 2011 13:00';
	my $pending = formatDateTime('zd Mon ccyy zh24:mi');
	my $xref = formatDateTime('ccyy-zm-zd-zh24-mi-ss');
}





# =============================================================================================
# =============================================================================================
#
# SUPPORT FUNCTIONS
#
# =============================================================================================
# =============================================================================================

# ---------------------------------------------------------------------------------------------
# Send a command to the CDS server and return the response
#
# Argument 1 : Function calling this one
# Argument 2 : CDS command in XML format
#
# Return the response from CDS if successful, or undef if CDS raised an error
# ---------------------------------------------------------------------------------------------
sub cds_call {
	my($function,$command) = @_;
	my($http,%headers,%options,$response,$content,$psr,$doc,$xpc,@nodes);
	
	# Clear out newlines, tabs and leading spaces
	$command =~ s/\n//g;
	$command =~ s/\t//g;
	$command =~ s/^\s+//;
	
	# Define the HTTP header and content
	$headers{'Content-Type'} = 'text/xml';
	$options{'content'} = $command;
	$options{'headers'} = \%headers;
	
	# Create a request obeject and make the call
	$http = HTTP::Tiny->new('Content-Type' => 'text/xml');
	$response = $http->request('GET', $CDS_URL, \%options);
	
	# Process the response
	if(!$response->{success}) {
		if($response->{status} == 599) {
			logMsgPortal($LOG,$PROGRAM,'E',"CDS Call '$function' timed out when connecting to CDS server at $CDS_URL");
		}
		else {
			logMsgPortal($LOG,$PROGRAM,'E',"CDS Call '$function': Unable to connect to CDS server at $CDS_URL [$response->{status}] $response->{reason}");
		}
		return undef;
	}
	$content = $response->{content};
	
	# Change reserved XML characters
	$content =~ s/&/&amp;/g;
	
	# There is a problem with the CDS API in that some commands append the HTML response code to the
	# end of the response message.  This code removes any characters after the </cds:response> tag
	$content =~ s/\n//g;
	$content =~ s/<\/cds:response>.*/<\/cds:response>/;
	
	# Return the response from CDS if successful, or undef if CDS raised an error
	$psr = XML::LibXML->new();
	eval { $doc = $psr->parse_string($content); };
	if($@) {
		logMsgPortal($LOG,$PROGRAM,'E',"CDS Call '$function': Unable to parse response from CDS (details in next message): $@");
		return undef;
	}
	$xpc = XML::LibXML::XPathContext->new($doc);
	@nodes = $xpc->findnodes("/cds:response/cds:error");
	if(@nodes) {
		logMsgPortal($LOG,$PROGRAM,'E',"CDS Call ($function): ".$nodes[0]->textContent);
		return undef;
	}
	return $content;
}



# ---------------------------------------------------------------------------------------------
# Run a CDS command
#
# Argument 1 : Name of command
# Argument 2 : Optional parameter (dependent on the command)
# Argument 3 : Optional parameter (dependent on the command)
#
# Return the response if successful, undef if error
# ---------------------------------------------------------------------------------------------
sub cds_command {
	my($cmd,$prm1,$prm2) = @_;
	my($xml,$response);
	
	# Find XML for command
	if($cmd eq 'abortdistribution') {
		# Abort a distribution
		$xml = <<COMMAND_ABORT;
<?xml version='1.0'?>
<cds:request xmlns:cds='cds' type='abortdistribution'>
	<cds:sessionid>$SESSION</cds:sessionid>
	<cds:distribution id='$prm1' />
</cds:request>
COMMAND_ABORT
	}
	elsif($cmd eq 'indexnode') {
		# Catalogue content
		$xml = <<COMMAND_INDEX;
<?xml version='1.0'?>
<cds:request xmlns:cds='cds' type='indexnode'>
	<cds:sessionid>$SESSION</cds:sessionid>
	<cds:nodelist>
		<cds:node id='$CONFIG{AIRWAVE_NODE_ID}' />
	</cds:nodelist>
</cds:request>
COMMAND_INDEX
	}
	elsif($cmd eq 'listaudit') {
		# Retrieve the list of completed distributions in the selected period
		$xml = <<COMMAND_AUDIT;
<?xml version='1.0'?>
<cds:request xmlns:cds='cds' type='listaudit'>
	<cds:sessionid>$SESSION</cds:sessionid>
	<cds:range type='date' start='$prm1' end='$prm2'></cds:range>
	<cds:nodelist id='repository'>
		<cds:node id='$CONFIG{AIRWAVE_NODE_ID}' />
	</cds:nodelist>
</cds:request>
COMMAND_AUDIT
	}
	elsif($cmd eq 'listcontent') {
		# Retrieve list of content packages
		$xml = <<COMMAND_CONTENT;
<?xml version='1.0'?>
<cds:request xmlns:cds='cds' type='listcontent'>
	<cds:sessionid>$SESSION</cds:sessionid>
	<cds:nodelist>
		<cds:node id='$CONFIG{AIRWAVE_NODE_ID}' />
	</cds:nodelist>
</cds:request>
COMMAND_CONTENT
	}
	elsif($cmd eq 'listdistributions') {
		# Retrieve list of distributions in selected period
		$xml = <<COMMAND_DIST;
<?xml version='1.0'?>
<cds:request xmlns:cds='cds' type='listdistributions'>
	<cds:sessionid>$SESSION</cds:sessionid>
	<cds:range type='date' start='$prm1' end='$prm2'></cds:range>
	<cds:nodelist>
		<cds:node id='$CONFIG{AIRWAVE_NODE_ID}' />
	</cds:nodelist>
</cds:request>
COMMAND_DIST
	}
	elsif($cmd eq 'listgroups') {
		# Retrieve list of groups
		$xml = <<COMMAND_GROUP;
<?xml version='1.0'?>
<cds:request xmlns:cds='cds' type='listgroups'>
	<cds:sessionid>$SESSION</cds:sessionid>
</cds:request>
COMMAND_GROUP
	}
	elsif($cmd eq 'listnodes') {
		# Retrieve list of nodes
		$xml = <<COMMAND_NODE;
<?xml version='1.0'?>
<cds:request xmlns:cds='cds' type='listnodes'>
	<cds:sessionid>$SESSION</cds:sessionid>
</cds:request>
COMMAND_NODE
	}
	elsif($cmd eq 'sendcontent') {
		# Start a distribution
		$xml = <<COMMAND_START;
<?xml version='1.0'?>
<cds:request xmlns:cds='cds' type='sendcontent'>
	<cds:sessionid>$SESSION</cds:sessionid>
	<cds:distribution id='0' encrypt='yes' priority='3' mode='direct' />
	<cds:content id='$prm1' />
	<cds:nodelist>
		<cds:node id='$prm2' />
	</cds:nodelist>
</cds:request>
COMMAND_START
	}
	# Unrecognised command
	else {
		logMsg($LOG,$PROGRAM,"Unable to find CDS command '$cmd'");
		return;
	}
	
	# Run command
	$response = cds_call($cmd,$xml);
	if(!$response) {
		logMsg($LOG,$PROGRAM,"Unable to run CDS command '$cmd'");
		return;
	}
	
	# Save the response to file
	dump_response_to_file("/tmp/cds_$cmd.xml",$response);
	
	# Return response
	return $response;
}



# ---------------------------------------------------------------------------------------------
# Connect to the Airwave database on the CDS Portal
#
# Return database handle or undef if any errors
# ---------------------------------------------------------------------------------------------
sub cds_db_connect {
	my($dsn,$dbh);
	
	$dsn = "DBI:mysql:database=$CONFIG{CDS_SQL_DATABASE};host=$CONFIG{CDS_SQL_HOST};mysql_connect_timeout=5";
	eval {
		$dbh = DBI->connect($dsn,$CONFIG{CDS_SQL_USERNAME},$CONFIG{CDS_SQL_PASSWORD},{RaiseError => 1});
	};
	
	# Error raised during connection
	if ($@) {
		logMsg($LOG,$PROGRAM,"Can't connect to CDS Portal: ".$@);
		return;
	}
	return $dbh;
}



# ---------------------------------------------------------------------------------------------
# Run a query to retrieve the list of catalogued content from the Airwave database on the CDS Portal
#
# Return results as a hash or undef if any errors
# ---------------------------------------------------------------------------------------------
sub cds_sql_content {
	my($sql,$dbh,$sth,$ref,$id,%data);
	
	# Running distributions
	$sql = <<SQL_CONTENT;
SELECT	ContentID,
		Name,
		(SELECT Name FROM Server WHERE ServerID=Content.RepositoryID) AS 'Server'
FROM	Content
WHERE	Status='active' 
AND		Type = 'managed_content' 
AND		(SELECT COUNT(*) 
		 FROM File 
		 WHERE ContentID=Content.ContentID 
		 AND Status='active') > 0 
AND		RepositoryID = 154
SQL_CONTENT
	
	# Connect to the database
	$dbh = cds_db_connect();
	if(!$dbh) { return; }
	
	# Run the query and load the data into a hash
	$sth = $dbh->prepare($sql);
	$sth->execute();
	while ($ref = $sth->fetchrow_hashref()) {
		foreach my $col (sort keys %$ref) {
			$id = $ref->{ContentID};
			$data{$id}{Bundle} = $ref->{Name};
			$data{$id}{Server} = $ref->{Server};
		}
	}
	$sth->finish();
	
	# Disconnect from the database
	$dbh->disconnect();
	
	# Return the data
	return %data;
}



# ---------------------------------------------------------------------------------------------
# Run a query to retrieve the running distributions from the Airwave database on the CDS Portal
#
# Return results as a [1,hashref] or [0,undef] if any errors
# ---------------------------------------------------------------------------------------------
sub cds_sql_running {
	my($sql,$dbh,$sth,$ref,$id,%data);
	
	# Running distributions
	$sql = <<SQL_RUNNING;
SELECT	d.DistributionID AS DistID,
		c.Name AS Bundle,
		d.Timestamp AS Start,
		(SELECT MAX(s.Name) FROM Action a,Server s WHERE a.DestServerID = s.ServerID AND a.DistributionID=d.DistributionID) AS Site,
		(SELECT COUNT(*) FROM Error e WHERE e.DistributionID=d.DistributionID) AS Errors,
		(SELECT SUM(f.Size*a.Progress)/SUM(f.Size) FROM Action a LEFT JOIN File f ON (a.ObjectID=f.FileID) WHERE a.DistributionID=d.DistributionID AND a.EventTypeID=(SELECT DISTINCT EventTypeID FROM EventType WHERE Name='transfer')) AS Progress 
FROM	Distribution d,
		Content c 
WHERE	d.ContentID = c.ContentID 
AND		0<(
			SELECT	COUNT(*) 
			FROM	Action a 
			WHERE	a.DistributionID=d.DistributionID 
			AND		a.Status='ready' 
			AND		a.EventTypeID IN (SELECT DISTINCT EventTypeID FROM EventType WHERE Name IN ('transfer','ingest'))
		)
SQL_RUNNING
	
	# Connect to the database
	$dbh = cds_db_connect();
	if(!$dbh) { return (0, undef); }
	
	# Run the query and load the data into a hash
	$sth = $dbh->prepare($sql);
	$sth->execute();
	while ($ref = $sth->fetchrow_hashref()) {
		foreach my $col (sort keys %$ref) {
			$id = $ref->{DistID};
			$data{$id}{Bundle} = $ref->{Bundle};
			$data{$id}{Start} = $ref->{Start};
			$data{$id}{Site} = $ref->{Site};
			$data{$id}{Errors} = $ref->{Errors};
			$data{$id}{Progress} = $ref->{Progress};
		}
	}
	$sth->finish();
	
	# Disconnect from the database
	$dbh->disconnect();
	
	# Return success and the data
	return (1, \%data);
}



# ---------------------------------------------------------------------------------------------
# Run a query to retrieve the active sites from the Airwave database on the CDS Portal
#
# Return results as a hash or undef if any errors
# ---------------------------------------------------------------------------------------------
sub cds_sql_sites {
	my($sql,$dbh,$sth,$ref,$id,%data);
	
	# Active sites (no users)
	$sql = <<SQL_SITES;
SELECT	u.UserID AS ID,
		c.Name AS Company,
		u.Name AS Site,
		s.Name AS Server 
FROM	User u, 
		Company c, 
		Server s 
WHERE	u.CompanyID = c.CompanyID 
AND		u.ServerID = s.ServerID 
AND		u.Type = 'site' 
AND		u.Status = 'active' 
SQL_SITES
	
	# Connect to the database
	$dbh = cds_db_connect();
	if(!$dbh) { return; }
	
	# Run the query and load the data into a hash
	$sth = $dbh->prepare($sql);
	$sth->execute();
	while ($ref = $sth->fetchrow_hashref()) {
		foreach my $col (sort keys %$ref) {
			$id = $ref->{ID};
			$data{$id}{Company} = $ref->{Company};
			$data{$id}{Site} = $ref->{Site};
			$data{$id}{Server} = $ref->{Server};
		}
	}
	$sth->finish();
	
	# Disconnect from the database
	$dbh->disconnect();
	
	# Return the data
	return %data;
}



# ---------------------------------------------------------------------------------------------
# Convert date in CDS format to Portal format
#
# Argument 1 : CDS date in 'yyyy-mm-dd hh24:mi:ss' format
#
# Return date in Portal format 'dd Mon ccyy hh24:mi'
# ---------------------------------------------------------------------------------------------
sub convertCDSdate {
	my($cds) = @_;
	return substr($cds,8,2).' '.$MONTHS[int(substr($cds,5,2))-1].' '.substr($cds,0,4).' '.substr($cds,11,2).':'.substr($cds,14,2);
}



# ---------------------------------------------------------------------------------------------
# Write the response message to a file
#
# Argument 1 : Full file name
# Argument 2 : response message from CDS command in XML format
# ---------------------------------------------------------------------------------------------
sub dump_response_to_file {
	my($filename,$response) = @_;
	my($fh);
	open($fh,">$filename") or die "Unable to open file [$filename]: $!";
	print $fh $response;
	close($fh);
}



# ---------------------------------------------------------------------------------------------
# Send a notification email with the films delivered to the node
#
# Argument 1 : Stage in cycle during which the email is being sent (started/finished/aborted)
# Argument 2 : Distribution name
# Argument 3 : CDS node name for the site
# Argument 4 : Email address of the site administrator
# Argument 5 : Body of the email
#
# Return 1 if the email was sent successfully, return 0 otherwise
# ---------------------------------------------------------------------------------------------
sub email_send {
	my($stage,$distname,$node,$to,$body) = @_;
	my($from,$ok,$subject,$cc,$status,$msg,%error);
	
	# Read email parameters from the configuration file
	$cc = $CONFIG{DIST_EMAIL_CC};
	$from = $CONFIG{DIST_EMAIL_FROM};
	
	# Build subject of email
	if($stage eq "aborted") {
		$subject = "Distribution of content to $node has been cancelled";
	}
	else {
		$subject = "Distribution of content to $node has $stage";
	}
	
	# Clean non UTF8 characters from subject and body
	($ok,$subject) = cleanNonUTF8($subject);
	if(!$ok) {
		logMsgPortal($LOG,$PROGRAM,'W',"Invalid character found in subject of email: $subject");
	}
	($ok,$body) = cleanNonUTF8($body);
	if(!$ok) {
		logMsgPortal($LOG,$PROGRAM,'W',"Invalid character found in body of email: $body");
	}
	
	# If TO address not set on Portal, send to default address and warn in subject
	if(!$to) {
		$to = $CONFIG{DIST_EMAIL_FROM};
		$subject = "USING DEFAULT 'TO' ADDRESS: $subject";
		logMsgPortal($LOG,$PROGRAM,'E',"Email: No [To] address for site assigned on Portal, using default email address");
	}
	
	# Clean the TO email addresses
	$to =~ s/\n/ /g;		# Replace new lines with spaces
	$to =~ s/;/ /g;			# Replace semi-colons with spaces
	$to =~ s/^\s+//;		# Remove leading whitespace
	$to =~ s/\s+$//;		# Remove trailing whitespace
	$to =~ s/\s+/ /g;		# Collapse internal whitespace to a single space
	
	# Replace semi-colon email address separators with spaces
	$from =~ s/;/ /g;
	$cc =~ s/;/ /g;
	
	# Send the email
	($msg) = apiEmail("to='$to'","from='$from'","subject='$subject'","body='$body'","cc='$cc'");
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"Email: Notification email NOT sent to '$to' for distribution '$distname' [$error{CODE}] $error{MESSAGE}");
		return 0;
	}
	else {
		logMsg($LOG,$PROGRAM,"Notification email sent to [$to] for distribution [$distname]");
		return 1;
	}
}



# ---------------------------------------------------------------------------------------------
# Extract the distribution data from the XML document into a hash of hashes
# Key is : Distribution ID
# Values : DIST_MODE
#          DIST_ENCRYPT
#          DIST_PRIORITY
#          DIST_START
#          DIST_END
#          CONTENT_ID
#          CONTENT_NAME
#          CONTENT_NODEID
#          CONTENT_NODENAME
#          FILES - array(id,name,size)
#          SITES - array(id,name,progress,errors)
#
# Argument 1 : XML response document from CDS
# ---------------------------------------------------------------------------------------------
sub extract_distribution_data {
	my($response) = @_;
	my($err,$xpc,@nodes,$key,@child,@nodelist,@files,@file,@sites,@site);
	my($status,$msg,%error);
	my %cds = ();
	
	# Read the response document
	($err,$xpc) = parseDocument('string',$response);
	if(!$xpc) {
		logMsgPortal($LOG,$PROGRAM,'E',"Unable to open the XML document: $response: $err");
		return;
	}
	@nodes = $xpc->findnodes("/cds:response/cds:distributionlist/cds:distribution");
	
	# Stop if no data returned from CDS
	if(!@nodes) {
		return;
	}
	
	# Loop through each distribution element
	foreach my $node (@nodes) {
		# Extract the distribution attributes
		$key = $node->getAttribute('id');
		$cds{$key}{DIST_MODE} = $node->getAttribute('mode');
		$cds{$key}{DIST_ENCRYPT} = $node->getAttribute('encrypt');
		$cds{$key}{DIST_PRIORITY} = $node->getAttribute('priority');
		
		# Read distribution start and end dates. If not defined, set to null
		@child = $node->findnodes("cds:date[\@type='start']");
		$cds{$key}{DIST_START} = (@child) ? $child[0]->textContent : '';
		@child = $node->findnodes("cds:date[\@type='finish']");
		$cds{$key}{DIST_END} = (@child) ? $child[0]->textContent : '';
		
		# Extract the source of the content
		@nodelist = $node->findnodes("cds:content");
		$cds{$key}{CONTENT_ID} = $nodelist[0]->getAttribute('id');
		@child = $nodelist[0]->findnodes("cds:name");
		$cds{$key}{CONTENT_NAME} = $child[0]->textContent;
		@child = $nodelist[0]->findnodes("cds:node");
		$cds{$key}{CONTENT_NODEID} = $child[0]->getAttribute('id');
		@child = $child[0]->findnodes("cds:name");
		$cds{$key}{CONTENT_NODENAME} = $child[0]->textContent;
		
		# Extract the list of files
		@files = ();
		@nodelist = $node->findnodes("cds:content/cds:filelist/cds:file");
		foreach my $item (@nodelist) {
			@file = ();
			$file[0] = $item->getAttribute('id');
			@child = $item->findnodes("cds:name");
			$file[1] = (@child) ? $child[0]->textContent : 'Unspecified';
			@child = $item->findnodes("cds:size");
			$file[2] = (@child) ? $child[0]->textContent : '-1';
			push(@files,[@file]);
		}
		$cds{$key}{FILES} = [@files];
		
		# Destination of content
		@sites = ();
		@nodelist = $node->findnodes("cds:nodelist/cds:node");
		foreach my $item (@nodelist) {
			@site = ();
			$site[0] = $item->getAttribute('id');
			@child = $item->findnodes("cds:name");
			$site[1] = (@child) ? $child[0]->textContent : '';
			@child = $item->findnodes("cds:progress");
			$site[2] = (@child) ? $child[0]->textContent : '';
			@child = $item->findnodes("cds:errors");
			$site[3] = (@child) ? $child[0]->textContent : '';
			push(@sites,[@site]);
		}
		$cds{$key}{SITES} = [@sites];;
	}
	return %cds;
}



# ---------------------------------------------------------------------------------------------
# Login request to a CDS node with a licence number
#
# Argument 1 : Licence number
# ---------------------------------------------------------------------------------------------
sub login_licence {
	my($licence) = @_;
	
	# CDS command to be issued
	my $cmd = <<COMMAND;
<?xml version='1.0'?>
<cds:request xmlns:cds='cds' type='login'>
	<cds:licence>$licence</cds:licence>
</cds:request>
COMMAND
	return cds_call('login_licence',$cmd);
}



# ---------------------------------------------------------------------------------------------
# Login request to a CDS node with user credentials
# ---------------------------------------------------------------------------------------------
sub login_user {
	my($cmd,$response,$err,$xpc,@nodes);
	
	# CDS command to be issued
	$cmd = <<COMMAND;
<?xml version='1.0'?>
<cds:request xmlns:cds='cds' type='login'>
	<cds:username>$CDS_USER</cds:username>
	<cds:password>$CDS_PASS</cds:password>
</cds:request>
COMMAND

	# Initiate the command and return undef if an error was encountered
	$response = cds_call('login_user',$cmd);
	if(!$response) {
		logMsgPortal($LOG,$PROGRAM,'E',"Login: Failed to login to the CDS Portal");
		return;
	}
	
	# Extract the session ID
	($err,$xpc) = parseDocument('string',$response);
	if(!$xpc) {
		logMsgPortal($LOG,$PROGRAM,'E',"Login: Unable to open the XML document: $response: $err");
		return;
	}
	@nodes = $xpc->findnodes("/cds:response/cds:sessionid");
	if(!@nodes) {
		logMsgPortal($LOG,$PROGRAM,'E',"Login: Session ID could not be read from the CDS response message");
		return;
	}
	
	# Save the session ID
	$SESSION = $nodes[0]->textContent;
}



# ---------------------------------------------------------------------------------------------
# Logout request from a CDS node
# ---------------------------------------------------------------------------------------------
sub logout {
	my($cmd,$response);
	
	# CDS command to be issued
	$cmd = <<COMMAND;
<?xml version='1.0'?>
<cds:request xmlns:cds='cds' type='logout'>
	<cds:sessionid>$SESSION</cds:sessionid>
</cds:request>
COMMAND

	# Initiate the command and report any errors
	$response = cds_call('logout',$cmd);
	if(!$response) {
		logMsgPortal($LOG,$PROGRAM,'E',"Logout: CDS session not closed properly");
	}
}



# ---------------------------------------------------------------------------------------------
# Take the current timestamp and subtract the specified number of months
#
# Argument 1 : Number of months
#
# Return the current timestamp and the adjusted timestamp in YYYY-MM-DD HH24:MI:SS format
# ---------------------------------------------------------------------------------------------
sub months_offset {
	my($interval) = @_;
	my($now,$adj,$time);
	my($sec,$min,$hour,$day,$mth,$year) = localtime();
	
	# Time (HH24:MI:SS)
	$time = substr("0".$hour,-2,2).':'.substr("0".$min,-2,2).':'.substr("0".$sec,-2,2);
	
	# Adjust month and year
	$mth++;
	$year += 1900;
	
	# TO date
	$now = $year.'-'.substr("0".$mth,-2,2).'-'.substr("0".$day,-2,2).' '.$time;
	
	# FROM date
	$mth -= $interval;
	$year = ($mth <= 0) ? ($year-1) : $year;
	$mth = ($mth <= 0) ? $mth+12 : $mth;
	$adj = $year.'-'.substr("0".$mth,-2,2).'-'.substr("0".$day,-2,2).' '.$time;
	
	return ($now,$adj);
}



# ---------------------------------------------------------------------------------------------
# Program usage
#
# Argument 1 : Error number
# ---------------------------------------------------------------------------------------------
sub usage {
	my($err,$dir) = @_;
	$err = ($err) ? $err : 0;
	if($err == 1) {
		
		printf("
Invalid action, must be one of:
  DISTRIBUTION ACTIONS
\tcatalogue\tCatalogue the CMS distribution node on the CDS server
\tended\t\tSet the end date for CDS batches that have finished
\tlog\t\tView the last 100 lines from the CDS log file
\tnotify\t\tGenerate and send emails to each site
\tprepare\t\tCreate the content directories for distribution by CDS
\tstart\t\tStart a distribution on CDS
\tstatus\t\tCheck the status of all distributions on CDS
\tstop\t\tStop a distribution on CDS
  QUERIES
\tcomplete\tRetrieve a list of completed distributions from the CDS server
\tcontent\t\tRetrieve the list of catalogued content from the CDS server
\tgroup\t\tRetrieve the list of node groups from the CDS server
\tnode\t\tRetrieve a list of nodes from the CDS server
\trunning\t\tRetrieve a list of active distributions from the CDS server
\n");
	}
	elsif($err == 2) {
		print "\nInvalid server, must be one of: test or live\n\n";
	}
	elsif($err == 3) {
		print "\nFor action 'stop', the package name must be entered\n\n";
	}
	else {
		printf("
Program : $PROGRAM
Version : v$VERSION
Author  : Basil Fisk (c)2013 Airwave Ltd

Summary :
  This script is the interface between the distributions that are planned
  and scheduled on the Portal, and CDS which manages the distributions to
  each site.

Usage   : 
          DISTRIBUTION ACTIONS
            Create the content directories for distribution by CDS.
              $PROGRAM -a=prepare
              
            Catalogue the CMS distribution node on the CDS server.  This is also run
            after new content directories have been created by the prepare action.
              $PROGRAM -a=catalogue
              
            Start a distribution on CDS.
              $PROGRAM -a=start
              
            Stop a distribution on CDS.
              $PROGRAM -a=stop
              
            Update the Portal with the CDS node status
              $PROGRAM -a=node-status
              
            Check the status of all distributions that have been started by CDS.
              $PROGRAM -a=status -from=<CCYY-MM-DD> -to=<CCYY-MM-DD>
              
            Set the end date for CDS batches that finished between the 'from' date and 
            'to' date.  Unless explicitly stated, the default 'from' date is 1 month
            before today and the  default 'to' date is today.
              $PROGRAM -a=ended -from=<CCYY-MM-DD> -to=<CCYY-MM-DD>
              
            Generate and send emails to each site listing the films that have been
            successfully loaded onto the site.
              $PROGRAM -a=notify
              
            View the last 100 lines from the CDS log file.
              $PROGRAM -a=log
              
          QUERIES
            Retrieve a list of completed distributions from the CDS server.
              $PROGRAM -a=complete -from=<CCYY-MM-DD> -to=<CCYY-MM-DD>
              
            Retrieve a list of active distributions from the CDS server.
              $PROGRAM -a=running -from=<CCYY-MM-DD> -to=<CCYY-MM-DD>
              
            Retrieve the list of catalogued content from the CDS server.
              $PROGRAM -a=content
              
            Retrieve the list of node groups from the CDS server.
              $PROGRAM -a=group
              [TDB - List nodes within the group]
              
            Retrieve a list of nodes from the CDS server.
              $PROGRAM -a=node
              [TBD - Group node by company and show status after name]
              
          TEST
            Send test messages via the API to the CDS server.
              $PROGRAM -a=test -t='command,...'
              
              
  MANDATORY
    --a|action=<name>          Action to be performed against the CDS server.

  OPTIONAL
    --f|from=<date/time>       Start date from which to list entries (in 'CCYY-MM-DD' format).
                               Defaults to one month before today if not specified.
    --n|nodes=<list>           Comma separated list of node names the content is to be distributed to.
    --p|package=<name>         Name of the CDS package to be distributed.
    --s|server=live            Run action command against the live CDS server (default).
    --s|server=test            Run action command against the test CDS server.
    --t|to=<date/time>         End date to limit entries (in 'CCYY-MM-DD' format).
                               Defaults to today if not specified.
    --l|log                    If set, the results from the script will be written to the Airwave.
                               log directory, otherwise the results will be written to the screen.
		\n");
	}
	
	# Stop in all cases
	exit;
}


