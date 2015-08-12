#!/usr/bin/perl
# ***************************************************************************
# ***************************************************************************
# 
# Encrypt all UIP films within 6 months of the NTR date that are due for
# distribution to site.
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

# System modules
use Getopt::Long;

# Breato modules
use lib "$ROOT";
use mods::API qw(apiData apiSelect apiStatus);
use mods::Common qw(cleanNonAlpha formatDateTime logMsg logMsgPortal parseDocument readConfig);

# Program information
our $PROGRAM = "encrypt.pl";
our $VERSION = "2.0";

# Check there are any arguments
if($#ARGV == -1) { usage(); }

# Read command line options
our $LOG		= 0;
our $STATE		= 'append';
our $ENCRYPT	= 0;
GetOptions (
	'append'		=> sub { $STATE = 'append'; },
	'new'			=> sub { $STATE = 'new'; },
	'encrypt'		=> sub { $ENCRYPT = 1; },
	'test'			=> sub { $ENCRYPT = 0; },
	'l|log'			=> sub { $LOG = 1; },
	'help'			=> sub { usage(); } );

# Read the configuration parameters
our %CONFIG  = readConfig("$ROOT/etc/airwave.conf");

# Start processing
main();





# ---------------------------------------------------------------------------------------------
# Main processing function
# ---------------------------------------------------------------------------------------------
sub main {
	my($status,$msg,%error,$asset,$source);
	my(%films,$svrcode,$svrname,$filmcode,$filmname,$provider,$encryption,$url,$user,$pass,$catalogue,$keylength,$ok);
	my $lastsvr = '';
	
	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");
	logMsg($LOG,$PROGRAM,"Encrypt the films to be distributed");
	
	# Read the list of Current (within 6 months of NTR) Hollywood films to be encrypted
	($msg) = apiSelect('encryptServerFilms');
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"Problem reading films to be encrypted [$error{CODE}] $error{MESSAGE}");
		return;
	}
	%films = apiData($msg);
	if(!%films) {
		logMsg($LOG,$PROGRAM,"There are no films to be encrypted");
		return;
	}
	
	# Encrypt each combination of server and film
	foreach my $key (sort keys %films) {
		# Server and film details
		$svrname = $films{$key}{server_name};
		$svrcode = $films{$key}{server_ref};
		$filmcode = $films{$key}{asset_code};
		$filmname = $films{$key}{title};
		$provider = $films{$key}{provider};
		$encryption = $films{$key}{enc_type};
		$url = $films{$key}{sm_url};
		$user = $films{$key}{sm_user};
		$pass = $films{$key}{sm_pass};
		$catalogue = $films{$key}{sm_catalogue};
		$keylength = $films{$key}{sm_key_length};
		
		# SecureMedia encryption
		if($encryption eq 'securemedia') {
			# If this film is not for the same server as the last, check parameters are present then register
			if($lastsvr ne $svrcode) {
				securemedia_check($url,$user,$pass,$catalogue,$keylength);
				$ok = securemedia_register($svrname,$url,$user,$pass,$keylength);
			}
			
			# Only encrypt films if successfully registered with the server
			if($ok) {
				# Create the name of the film file
				$asset = get_file_name("$CONFIG{CS_ROOT}/$provider",$filmcode);
				
				# Encrypt using SecureMedia
				$source = "$CONFIG{CS_ROOT}/$provider/$filmcode/$asset";
				securemedia_encrypt($svrcode,$catalogue,$keylength,$filmname,$source,$filmcode,$asset,$provider);
				
				# Reset last server name
				$lastsvr = $svrcode;
			}
		}
		# For anything else, throw a warning and stop
		else {
			logMsgPortal($LOG,$PROGRAM,'W',"[$encryption] is an unsupported method of encryption ");
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Find the file name of an asset from the XML metadata file
#
# Argument 1 : Repository directory of the film
# Argument 2 : Reference of film
#
# Return the asset file name
# ---------------------------------------------------------------------------------------------
sub get_file_name {
	my($repo,$film) = @_;
	my($file,$err,$xpc,@nodes);
	
	# Open and parse the XML metadata file
	$file = "$repo/$film/$film.xml";
	($err,$xpc) = parseDocument('file',$file);
	if(!$xpc) {
		logMsgPortal($LOG,$PROGRAM,'E',"Cannot open the XML file: $file: $err");
		return;
	}
	
	# Read the film asset name
	@nodes = $xpc->findnodes("/metadata/assets/asset[\@class='film']");
	
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
# Check that all SecureMedia parameters have been entered
# 
# Argument 1 : URL to the SecureMedia key vault server
# Argument 2 : SecureMedia user name for the encryption client
# Argument 3 : SecureMedia password for the encryption client
# Argument 4 : SecureMedia catalogue in which the key is to be stored
# Argument 5 : SecureMedia encryption key length
# ---------------------------------------------------------------------------------------------
sub securemedia_check {
	my($host,$user,$password,$catalogue,$keylength) = @_;
	
	# Check that the required encryption parameters have been defined
	if(!$host) {
		logMsgPortal($LOG,$PROGRAM,'E',"URL of the SecureMedia key vault server has not been specified");
		exit;
	}
	if(!$user) {
		logMsgPortal($LOG,$PROGRAM,'E',"Name of the SecureMedia user has not been specified");
		exit;
	}
	if(!$password) {
		logMsgPortal($LOG,$PROGRAM,'E',"Password for the SecureMedia user has not been specified");
		exit;
	}
	if(!$catalogue) {
		logMsgPortal($LOG,$PROGRAM,'E',"Name of the SecureMedia catalogue has not been specified");
		exit;
	}
	if(!$keylength) {
		logMsgPortal($LOG,$PROGRAM,'E',"Length of the encryption key has not been specified");
		exit;
	}
}



# ---------------------------------------------------------------------------------------------
# Encrypt a film against the SecureMedia key vault server
# 
# Argument 1 : Name of directory into which encrypted files are to be written
# Argument 2 : SecureMedia catalogue in which the key is to be stored
# Argument 3 : SecureMedia encryption key length
# Argument 4 : Film title
# Argument 5 : Full path and name of the source file
# Argument 6 : Asset code of the film to be encrypted
# Argument 7 : Name of the encrypted file to be created
# ---------------------------------------------------------------------------------------------
sub securemedia_encrypt {
	my($server,$catalogue,$keylength,$filmname,$repo,$filmcode,$encfile,$provider) = @_;
	my($encdir,$dist,$cmd,$res,@errs);
	my $smlog = "$CONFIG{LOGDIR}/$CONFIG{SM_LOG_ENCRYPT}";
	
	# Output directory for the encrypted film (remove spaces from server name)
	$encdir = "$CONFIG{CS_PROC}/$provider/$server/$filmcode";
	$encdir =~ s/ //g;
	
	# Add an extension to output file name and remove white space and quotes from film name
	$dist = "$encdir/$encfile.sm";
	$filmname = cleanNonAlpha($filmname);
	
	# Don't re-encrypt if the encrypted output file already exists
	if(!-f $dist) {
		# Remove the last log file, if it exists
		if(-f $smlog) { $res = `rm $smlog`; }
		
		# Build the encryption command
		$cmd = "/usr/local/bin/smm2encrypt -mcat $catalogue -mn $filmname -i $repo -o $dist -media.keylen $keylength -l 2 -lf $smlog";
		
		# Encrypt the film, unless running in 'test' mode
		if($ENCRYPT) {
			logMsg($LOG,$PROGRAM,"Encrypting asset '$filmname' with SecureMedia: $cmd");
			
			# Create the directory to hold the encrypted films for this encryption server
			if(!-d $encdir) {
				$res = `mkdir $encdir`;
				if(!-d $encdir) {
					logMsgPortal($LOG,$PROGRAM,'E',"Can't create directory for encryption server '$encdir': $res");
					return;
				}
			}
			
			# Start the encryption
			$res = `$cmd`;
			
			# Add the output of the SecureMedia log file to the Airwave log file
			@errs = grep { /ERROR/ } `cat $smlog`;
			foreach my $err (@errs) {
				chomp $err;
				logMsgPortal($LOG,$PROGRAM,'E',"SecureMedia Encryption Error: $err");
			}
		}
		# Running in 'test' mode
		else {
			logMsg($LOG,$PROGRAM,"TEST: Encrypting asset '$filmname' with SecureMedia: $cmd");
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Register against the SecureMedia key vault server (before first asset is encrypted)
# 
# Argument 1 : Name of the SecureMedia key vault server
# Argument 2 : URL to the SecureMedia key vault server
# Argument 3 : SecureMedia user name for the encryption client
# Argument 4 : SecureMedia password for the encryption client
# Argument 5 : SecureMedia encryption key length
#
# Return 1 for success or 0 for failure
# ---------------------------------------------------------------------------------------------
sub securemedia_register {
	my($server,$host,$user,$password,$keylength) = @_;
	my($cmd,$res,@errs);
	my $smlog = "$CONFIG{LOGDIR}/$CONFIG{SM_LOG_REGISTER}";
	
	# Remove the last log file, if it exists
	if(-f $smlog) { $res = `rm $smlog`; }
	
	# Register with the SecureMedia server
	$cmd = "/usr/local/bin/smm2encrypt -register -rsurl $host -user $user -pass $password -esam.keylen $keylength -l 2 -lf $smlog";
	if($ENCRYPT) {
		logMsg($LOG,$PROGRAM,"Registering with the '$server' SecureMedia key vault server: $cmd");
		$res = `$cmd`;
		
		# Trap any errors and exit. Add output of SecureMedia log file to Airwave log file
		@errs = grep { /ERROR/ } `cat $smlog`;
		if(@errs) {
			foreach my $err (@errs) {
				chomp $err;
				logMsgPortal($LOG,$PROGRAM,'E',"SecureMedia Registration Error: $err");
			}
			return 0;
		}
		else {
			return 1;
		}
	}
	# Running in 'test' mode
	else {
		logMsg($LOG,$PROGRAM,"TEST: Registering with the '$server' SecureMedia key vault server: $cmd");
		return 1;
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
	
	if($err == 1) {
		logMsgPortal($LOG,$PROGRAM,'E',"The 'server' argument must be provided");
	}
	else {
		printf("
Program : $PROGRAM
Version : v$VERSION
Author  : Basil Fisk (c)2013 Airwave Ltd

Summary :
  Encrypt all UIP films within 6 months of the NTR date that are due for distribution to site.

Usage :
  $PROGRAM
  
  OPTIONAL
    --append             Append encrypted files in this batch to the work directory.
                         This is the opposite of -new.
                         'append' is the default option, not 'new'.
                         
    --new                Move files in the work directory to the Archive directory before
                         encrypting files in this batch and writing to existing directory.
                         This is the opposite of -append.
                         
    --encrypt            Encrypt the films.
                         This is the opposite of -test.
                         
    --test               Dry run without encrypting the films.
                         This is the opposite of -encrypt.
                         'test' is the default option, not 'encrypt'.
                         
    --log                If set, the results from the script will be written to the Airwave
                         log directory, otherwise the results will be written to the screen.
		\n");
	}
	
	# Stop in all cases
	exit;
}


