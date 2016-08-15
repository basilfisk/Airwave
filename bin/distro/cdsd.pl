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

# Declare modules
use strict;
use warnings;

# Airwave modules
use lib "$ENV{'AIRWAVE_ROOT'}";
use mods::Common qw(logMsg readConfig);

# Program information
my $PROGRAM = "cdsd.pl";
my $VERSION = "2.0";

# Read the configuration parameters
our %CONFIG  = readConfig("$ENV{'AIRWAVE_ROOT'}/etc/airwave.conf");

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
		`$ENV{'AIRWAVE_ROOT'}/encrypt.pl -encrypt -append -log`;

		# Create links to files to be distributed and catalogue using CDS
		`$ENV{'AIRWAVE_ROOT'}/cds.pl -a=prepare -log`;

		# Stop any distributions that have been flagged
		`$ENV{'AIRWAVE_ROOT'}/cds.pl -a=stop -log`;

		# Record end time of completed distributions and send email
		`$ENV{'AIRWAVE_ROOT'}/cds.pl -a=ended -log`;
		`$ENV{'AIRWAVE_ROOT'}/cds.pl -a=notify -log`;

		# Start new distributions
		`$ENV{'AIRWAVE_ROOT'}/cds.pl -a=start -log`;

		# Update status of running distributions
		`$ENV{'AIRWAVE_ROOT'}/cds.pl -a=status -log`;

		# Update status of CDS nodes
		`$ENV{'AIRWAVE_ROOT'}/cds.pl -a=node-status -log`;

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
