#!/usr/bin/perl
# *********************************************************************************************
# *********************************************************************************************
#
# Log the server usage statistics, Airship process statistics and number of CDS distributions
# currently running on the server.
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

# System modules
use Data::Dumper;
use DBI;
use Getopt::Long;

# Breato modules
use lib "$ROOT";
use mods::API qw(apiDML apiData apiStatus);
use mods::Common qw(cleanString formatDateTime logMsg logMsgPortal parseDocument readConfig);

# Program information
our $PROGRAM = "monitor.pl";
our $VERSION = "2.0";

# Read command line options
our $LOG	= 0;
GetOptions (
	'log'	=> \$LOG,
	'help'	=> sub { usage(); } );

# Read the configuration parameters
our %CONFIG  = readConfig("$ROOT/etc/airwave.conf");

# Name of temporary and stats files
our $STATFILE = "$CONFIG{LOGDIR}/monitor.stats";
our $TEMPFILE = "$CONFIG{TEMP}/monitor.tmp";

# Global variables
#our $CDS = LWP::UserAgent->new;

# Read and return the server name
our $HOSTNAME = `hostname`;
chomp($HOSTNAME);

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
	my(@net,@svr);
	my $cds = 0;
	
	# Read network statistics
	@net = network_stats();
	
	# Read server statistics
	@svr = server_stats();
	
	# Read CDS distribution statistics
	if($HOSTNAME eq 'distro') {
		$cds = cds_stats();
	}
	
	# Log stats
	if(@svr) {
		log_stats(@svr,$cds,@net);
	}
}



# ---------------------------------------------------------------------------------------------
# CDS distribution statistics
#
# Return the number of CDS processes running or 0 if problem connecting to CDS
# ---------------------------------------------------------------------------------------------
sub cds_stats {
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
	$dbh = DBI->connect("DBI:mysql:database=$CONFIG{CDS_SQL_DATABASE};host=$CONFIG{CDS_SQL_HOST}",$CONFIG{CDS_SQL_USERNAME},$CONFIG{CDS_SQL_PASSWORD});
	if(!$dbh) {
		logMsgPortal($LOG,$PROGRAM,'E',"Can't connect to CDS Portal: ".$DBI::errstr);
		return 0;
	}
	
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
	
	return keys(%data);
}



# ---------------------------------------------------------------------------------------------
# Write the statistics to file
#
# Argument 1 : Array of statistics
#	[0] = Current timestamp
#	[1] = Load average in last minute (0-1)
#	[2] = Load average in last 5 minutes (0-1)
#	[3] = Load average in last 15 minutes (0-1)
#	[4] = Time CPU has spent running users' processes (0-100)
#	[5] = Current CPU usage (0-100)
#	[6] = Current memory usage (0-1)
#	[7] = Number of CDS processes running (+int)
#	[8] = Data received over eth0
#	[9] = Data sent over eth0
# ---------------------------------------------------------------------------------------------
sub log_stats {
	my($time,$load1,$load5,$load15,$cpu,$cpupct,$mempct,$cds,$recv,$sent) = @_;
	my($date,$fh,$status,$msg,%error);
	
	# Today's date
	$date = formatDateTime('ccyy-zm-zd');
	
	# Write stats to log file and append date as 1st field
	if(open($fh,">>$STATFILE")) {
		print $fh "$date $time $load1 $load5 $load15 $cpu $cpupct $mempct $cds $recv $sent\n";
		close($fh);
	}
	
	# Make some changes as needed
	$time = "$date $time";
	$load1 = 100*$load1;
	$load5 = 100*$load5;
	$load15 = 100*$load15;
	
	# Write stats to Portal
	($msg) = apiDML('monitorAddStats',"timestamp='$time'","load1=$load1","load5=$load5","load15=$load15","cpu=$cpu","cpupct=$cpupct","memorypct=$mempct","cdsprocs=$cds","nwrecv=$recv","nwsent=$sent","server=$HOSTNAME");
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsg($LOG,$PROGRAM,"Stats for $time NOT added to Portal [$error{CODE}] $error{MESSAGE}");
		return;
	}
}



# ---------------------------------------------------------------------------------------------
# Return the number of bytes received and sent over the eth0 port
#
# Inter-|   Receive                                                   |  Transmit
#  face |bytes    packets errs drop fifo frame compressed multicast   |bytes    packets errs drop fifo colls carrier compressed
#  wlan0: 4199525413 2957671    0    1    0     0          0         0 169274779 1417137    0    0    0     0       0          0
#     lo:   21575034   91537    0    0    0     0          0         0  21575034   91537    0    0    0     0       0          0
#   eth0:          0       0    0    0    0     0          0         0         0       0    0    0    0     0       0          0
#
# Return an array of network statistics
#	[0] = Bytes received
#	[1] = Bytes sent
# ---------------------------------------------------------------------------------------------
sub network_check {
	my($res,@data,@row);
	my @net = (0,0);
	
	# Read the network statistics
	$res = `cat /proc/net/dev`;
	@data = split(/\n/,$res);
	for(my $i=0; $i<@data; $i++) {
		if($i >= 2) {
			@row = split(/:/,$data[$i]);
			if(cleanString($row[0]) eq 'eth0') {
				@row = split(/ /,cleanString($row[1]));
				$net[0] = $row[0];
				$net[1] = $row[8];
			}
		}
	}
	return @net;
}



# ---------------------------------------------------------------------------------------------
# Return the data rate (bits/sec) received and sent over the eth0 port
#
# Return an array of network statistics
#	[0] = Data rate received (bits/sec)
#	[1] = Data rate sent (bits/sec)
# ---------------------------------------------------------------------------------------------
sub network_stats {
	my(@start,@end,$recv,$sent);
	my $interval = 10;
	
	# Capture the bytes sent/received over a 10 second interval
	@start = network_check();
	sleep $interval;
	@end = network_check();
	
	# Convert to bits/second
	$recv = 8*($end[0]-$start[0])/$interval;
	$sent = 8*($end[1]-$start[1])/$interval;
	return ($recv,$sent);
}



# ---------------------------------------------------------------------------------------------
# Server statistics
#
# Return an array of server statistics
#	[0] = Current timestamp
#	[1] = Load average in last minute
#	[2] = Load average in last 5 minutes
#	[3] = Load average in last 15 minutes
#	[4] = Time CPU has spent running users' processes
#	[5] = Current CPU usage
#	[6] = Current memory usage
# ---------------------------------------------------------------------------------------------
sub server_stats {
	my($pid,$res,@data,@stats,$ts);
	my $cds = 1;
	
	# Read the Airship PID
	$res = `ps -ef | grep -e 'airship\$'`;
	@data = split(/ /,cleanString($res));
	$pid = $data[1];
	
	# If Airship isn't running, use /sbin/init to get the CPU stats
	if(!$pid) {
		$cds = 0;
		$res = `ps -ef | grep -e '/sbin/init'`;
		@data = split(/ /,cleanString($res));
		$pid = $data[1];
	}
	
	# Run top 5 times to get correct CPU data
	$res = `top -p $pid -n 5 -b > $TEMPFILE`;
	
	# Read timestamp and 3 CPU load averages
	# top - 13:28:37 up 23 days, 22:28,  2 users,  load average: 1.10, 0.84, 0.74
	$res = `tail -10 $TEMPFILE | grep average`;
	@data = split(/ /,cleanString($res));
	$data[-3] =~ s/,//;
	$data[-2] =~ s/,//;
	push(@stats,($data[2],$data[-3],$data[-2],$data[-1]));
	
	# Read time CPU has spent running users' processes
	# Cpu(s):  1.7%us,  0.2%sy,  0.0%ni, 97.9%id,  0.1%wa,  0.0%hi,  0.0%si,  0.0%st
	$res = `tail -10 $TEMPFILE | grep Cpu`;
	@data = split(/ /,cleanString($res));
	$data[1] =~ s/%us,//;
	push(@stats,$data[1]);
	
	# Read CPU usage and memory usage
	#   PID USER      PR  NI  VIRT  RES  SHR S %CPU %MEM    TIME+  COMMAND
	#  1909 root      20   0  462m 124m 2792 S   92  1.5   1905:38 airship
	if($cds) {
		$res = `tail -10 $TEMPFILE | grep $pid`;
		@data = split(/ /,cleanString($res));
		push(@stats,($data[8],$data[9]));
	}
	else {
		push(@stats,(0,0));
	}
	
	# Return the stats
	return @stats;
}



# ---------------------------------------------------------------------------------------------
# Program usage
# Argument 1 : Error number
# ---------------------------------------------------------------------------------------------
sub usage {
	my($err) = @_;
	
	printf("
Program : $PROGRAM
Version : v$VERSION
Author  : Basil Fisk (c)2013 Airwave Ltd

Summary :
  Log the server usage statistics, Airship process statistics and number of CDS distributions
  currently running on the server.

Usage   : $PROGRAM
  
  OPTIONAL
    --log                  If set, the results from the script will be written to the Airwave
                           log directory, otherwise the results will be written to the screen.
	\n");
	
	# Stop in all cases
	exit;
}
