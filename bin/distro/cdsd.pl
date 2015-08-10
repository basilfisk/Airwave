#!/usr/bin/perl
# *********************************************************************************************
# *********************************************************************************************
#
# Airwave CDS Interface daemon
#
# Daemon process that runs the sequence of actions that keep Airwave's CMS and CDS in sync
# This script must only be called by the 'cdsd' Perl script.
#
# *********************************************************************************************
# *********************************************************************************************

# Establish the root directory
our $ROOT;
BEGIN {
	$ROOT = '/home/airwave/bin';
}

# Declare modules
use strict;
use warnings;

# Airwave modules
use lib "$ROOT";
use mods::Common qw(logMsg readConfig);

# Program information
my $PROGRAM = "cdsd.pl";
my $VERSION = "2.0";

# Read the configuration parameters
our %CONFIG  = readConfig("$ROOT/etc/airwave.conf");

# Set up handler for SIGTERM
$SIG{TERM} = \&stop_daemon;

# Start processing
main();





# ---------------------------------------------------------------------------------------------
# Main processing function
# ---------------------------------------------------------------------------------------------
sub main {
	# Set up a loop and wait 5 minutes between each iteration of the CDS interface calls
	LOOP: while(1) {
		# Encrypt films, if needed
		`$ROOT/encrypt.pl -encrypt -append -log`;
		
		# Create links to files to be distributed and catalogue using CDS
		`$ROOT/cds.pl -a=prepare -log`;
		
		# Stop any distributions that have been flagged
		`$ROOT/cds.pl -a=stop -log`;
		
		# Record end time of completed distributions and send email
		`$ROOT/cds.pl -a=ended -log`;
		`$ROOT/cds.pl -a=notify -log`;
		
		# Start new distributions
		`$ROOT/cds.pl -a=start -log`;
		
		# Update status of running distributions
		`$ROOT/cds.pl -a=status -log`;
		
		# Update status of CDS nodes
		`$ROOT/cds.pl -a=node-status -log`;
		
		# Wait before next iteration starts
		sleep($CONFIG{CDS_INTERVAL});
	}
}



# ---------------------------------------------------------------------------------------------
# Set up handler for SIGTERM
# ---------------------------------------------------------------------------------------------
sub stop_daemon {
    logMsg(1,$PROGRAM,"Caught the TERM signal, so shutting down");
	exit;
}


