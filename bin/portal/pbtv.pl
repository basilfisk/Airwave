#!/usr/bin/perl
# *********************************************************************************************
# *********************************************************************************************
#
#  Run the monthly usage report for PlayboyTV, which produces a spreadsheet in MS-XML format.
#  The spreadsheet will be written to the Airwave Portal.
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
use Data::Dumper;
use Getopt::Long;

# Breato modules
use lib "$ROOT";
use mods::API qw(apiData apiStatus apiSelect);
use mods::Common qw(formatDateTime logMsg logMsgPortal readConfig);
use mods::MSXML qw(msxmlCell msxmlClose msxmlColumn msxmlCreate msxmlData msxmlInitialise msxmlRow msxmlRowNumber msxmlSetParameter msxmlStyleAdd msxmlWorkbook);

# Program information
our $PROGRAM = "pbtv.pl";
our $VERSION = "2.0";

# Check there are any arguments
if($#ARGV == -1) { usage(); }

# Read command line options
our $LOG	= 0;
our $YYMM	= 'empty';
GetOptions (
	'log'    => \$LOG,
	'yymm=s' => \$YYMM,
	'help'   => sub { usage(); } );

# Check that YYMM argument is present
if($YYMM eq 'empty') { usage(1); }

# Read the configuration parameters
our %CONFIG  = readConfig("$ROOT/etc/airwave-portal.conf");

# Define date related variables
my @mmm = ('January','February','March','April','May','June','July','August','September','October','November','December');
our $CCYY = "20".substr($YYMM,0,2);
our $PERIOD = $mmm[int(substr($YYMM,2,2))-1]." ".$CCYY;

# Spreadsheet parameters
our $FILENAME = "PlayboyTV $YYMM";
msxmlSetParameter('NAME',$FILENAME);
msxmlSetParameter('DIR',"$ROOT/../$CONFIG{PORTAL_PBTV}/$CCYY");
msxmlSetParameter('AUTHOR','Basil Fisk');
msxmlSetParameter('MARGIN_LEFT','0.75');
msxmlSetParameter('MARGIN_RIGHT','0.75');

# Room based charge bands
our %RATES = (
	A => [(1,1000,40)],
	B => [(1001,2000,35)],
	C => [(2001,5000,30)] );

# Row on which the total number of rooms is printed
our $TOTAL_ROW;

# Total number of rooms and the rate for the total number of rooms
our $TOTAL_ROOMS = 0;
our $TOTAL_RATE;

# Run the report
main();





# ---------------------------------------------------------------------------------------------
# Generate the report
# ---------------------------------------------------------------------------------------------
sub main {
	# Set local variables
	my($status,$msg,%error,%sites,$territory,$site,$rooms,$c18,$r18);

	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");
	logMsg($LOG,$PROGRAM,"Running the PlayboyTV Usage report for period '$YYMM'");

	# Retrieve and aggregate the rooms totals by site and genre
	# This is done as the p/room/mth figure depends on the total number of rooms in each genre
	# Return a hash keyed by territory and site name with the site details as the value
	($msg) = apiSelect('pbtvSites',"month=$YYMM".'01');
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"No sites returned from database [$error{CODE}] $error{MESSAGE}");
		exit;
	}
	%sites = apiData($msg);

	# Initialise report and create styles to be used
	msxmlInitialise();
	set_styles();

	# Create the spreadsheet
	$msg = msxmlCreate();
	if($msg) {
		logMsgPortal($LOG,$PROGRAM,'E',$msg);
		return;
	}
	$msg = msxmlWorkbook('open',$PERIOD);
	if($msg) {
		logMsgPortal($LOG,$PROGRAM,'E',$msg);
		return;
	}
	msxmlColumn('open');
	msxmlColumn('insert',30,2);
	msxmlColumn('insert',8,4);
	msxmlColumn('close');
	msxmlData('open');

	# Create the document and column headings
	report_header();
	report_columns();

	# Create the body of the report; 1 record/site
	foreach my $key (sort keys %sites) {
		$territory = $sites{$key}{territory};
		$site = $sites{$key}{site};
		$rooms = $sites{$key}{rooms};
		$c18 = $sites{$key}{soft};
		$r18 = $sites{$key}{strong};
		report_row($territory,$site,$rooms,$c18,$r18);
	}

	# Report totals and financial summary
	report_totals();
	report_footer();

	# Close the data section, the workgroup and the spreadsheet
	msxmlData('close');
	msxmlWorkbook('close',$PERIOD);
	$msg = msxmlClose();
	if($msg) {
		logMsgPortal($LOG,$PROGRAM,'E',$msg);
		return;
	}
}



# ---------------------------------------------------------------------------------------------
# Print the report column headings
# ---------------------------------------------------------------------------------------------
sub report_columns {
	msxmlRow('open',25);
	msxmlCell('A','colhead-l','Territory');
	msxmlCell('B','colhead-l','Site Name');
	msxmlCell('C','colhead-r','Rooms');
	msxmlCell('D','colhead-r','C18 Films');
	msxmlCell('E','colhead-r','R18 Films');
	msxmlRow('close');
}



# ---------------------------------------------------------------------------------------------
# Print the report footer with the financial summary
# ---------------------------------------------------------------------------------------------
sub report_footer {
	my($row,$start,$end,$low,$high,$rate);

	# Blank row
	msxmlRow('open');
	msxmlCell('A','normal','');
	msxmlRow('close');

	# Set the current row number (3 lines after the totals)
	$start = $row = $TOTAL_ROW + 3;

	# Find out the room rate to be used
	foreach my $key (sort keys %RATES) {
		($low,$high,$rate) = @{$RATES{$key}};
		if($TOTAL_ROOMS >= $low && $TOTAL_ROOMS <= $high) {
			$TOTAL_RATE = $rate;
		}
	}

	# Print the totals
	msxmlRow('open');
	msxmlCell('B','text-l',"Room Rate (p/Room)");
	msxmlCell('C','dp1',$TOTAL_RATE);
	msxmlRow('close');

	# Print the totals
	msxmlRow('open');
	msxmlCell('B','text-l',"Total Due");
	msxmlCell('C','stg-bold',"=C$TOTAL_ROW*C".($TOTAL_ROW+2)."/100");
	msxmlRow('close');
}



# ---------------------------------------------------------------------------------------------
# Print the report header
# ---------------------------------------------------------------------------------------------
sub report_header {
	# Title row
	msxmlRow('open',25);
	msxmlCell('A','heading',"PlayboyTV Usage Report for $PERIOD");
	msxmlRow('close');

	# Blank row
	msxmlRow('open');
	msxmlCell('A','normal','');
	msxmlRow('close');
}



# ---------------------------------------------------------------------------------------------
# Create the body of the report
# Arguments : Various items of data
# ---------------------------------------------------------------------------------------------
sub report_row {
	my($territory,$site,$rooms,$c18,$r18) = @_;
	msxmlRow('open');
	msxmlCell('A','text-l',$territory);
	msxmlCell('B','text-l',$site);
	msxmlCell('C','number',$rooms);
	msxmlCell('D','text-r',($c18) ? "Y" : "N");
	msxmlCell('E','text-r',($r18) ? "Y" : "N");
	msxmlRow('close');

	# Running total of rooms
	$TOTAL_ROOMS += $rooms;
}



# ---------------------------------------------------------------------------------------------
# Create the report totals
# ---------------------------------------------------------------------------------------------
sub report_totals {
	# Read the last row number
	my $row = msxmlRowNumber();

	# Open the row container
	msxmlRow('open');

	# Create the cell totals
	msxmlCell('C','number-bold',"=SUM(C4:C$row)");

	# Read the row number and save it for use in the total section
	$TOTAL_ROW = msxmlRowNumber();

	# Close the row container
	msxmlRow('close');
}



# ---------------------------------------------------------------------------------------------
# Initialise the styles to be used in the spreadsheet
# ---------------------------------------------------------------------------------------------
sub set_styles {
	# Numbers
	msxmlStyleAdd("number","stg","id=165,picture=£#,##0.00;[RED]&quot;-£&quot;#,##0.00");
	msxmlStyleAdd("number","int0","id=166,picture=#,##0");
	msxmlStyleAdd("number","int2","id=167,picture=#,##0.00");
	msxmlStyleAdd("number","pct0","id=168,picture=0%");
	msxmlStyleAdd("number","float1","id=166,picture=##0.0");

	# Fonts
	msxmlStyleAdd("font","std","name=Arial,size=8");
	msxmlStyleAdd("font","std-bold","name=Arial,size=8,bold");
	msxmlStyleAdd("font","big-bold","name=Arial,size=14");
	msxmlStyleAdd("font","white","name=Arial,size=8,colour=FFFFFF");

	# Cells
	msxmlStyleAdd("cell","dp1","font=std,number=float1,horizontal=right,vertical=center");
	msxmlStyleAdd("cell","hidden","font=white");
	msxmlStyleAdd("cell","number","font=std,number=int0,horizontal=right,vertical=center");
	msxmlStyleAdd("cell","number-bold","font=std-bold,number=int0,horizontal=right,vertical=center");
	msxmlStyleAdd("cell","number-c-bold","font=std-bold,number=int0,horizontal=center,vertical=center");
	msxmlStyleAdd("cell","heading","font=big-bold,number=int0,horizontal=left,vertical=center");
	msxmlStyleAdd("cell","text-c","font=std,horizontal=center,vertical=center");
	msxmlStyleAdd("cell","text-l",",font=std,horizontal=left,vertical=center");
	msxmlStyleAdd("cell","text-r",",font=std,horizontal=right,vertical=center");
	msxmlStyleAdd("cell","stg","font=std,number=stg,horizontal=right,vertical=center");
	msxmlStyleAdd("cell","stg-bold","font=std-bold,number=stg,horizontal=right,vertical=center");
	msxmlStyleAdd("cell","colhead-c","font=std-bold,number=normal,horizontal=center,vertical=center,wrapText");
	msxmlStyleAdd("cell","colhead-l","font=std-bold,number=normal,horizontal=left,vertical=center,wrapText");
	msxmlStyleAdd("cell","colhead-r","font=std-bold,number=normal,horizontal=right,vertical=center,wrapText");
}



# ---------------------------------------------------------------------------------------------
# Program usage
# ---------------------------------------------------------------------------------------------
sub usage {
	my($err) = @_;
	$err = ($err) ? $err : 0;

	if($err == 1) {
		logMsgPortal($LOG,$PROGRAM,'E',"The 'yymm' argument is mandatory");
	}
	else {
		printf("
Program : $PROGRAM
Version : v$VERSION
Author  : Basil Fisk (c)2013 Airwave Ltd

Summary :
  Run the monthly usage report for PlayboyTV, which produces a spreadsheet in 
  MS-XML format.

Usage :
  $PROGRAM --yymm=<YYMM>

  MANDATORY
  --yymm=<YYMM>		The reporting month in YYMM format.
  
  OPTIONAL
  --log		 If set, the results from the script will be written to the Airwave
			 log directory, otherwise the results will be written to the screen.
		\n");
	}

	# Stop in all cases
	exit;
}
