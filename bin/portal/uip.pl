#!/usr/bin/perl
# *********************************************************************************************
# *********************************************************************************************
#
#  Run the monthly usage report for UIP, which produces a spreadsheet in MS-XML format.
#  The spreadsheet contains 2 tabs holding the Schedule A and Schedule E reports, whose
#  format have been specified by UIP.
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
use IO::File;
use XML::LibXML;
use XML::Writer;

# Breato modules
use lib "$ROOT";
use mods::API qw(apiData apiStatus apiSelect);
use mods::Common qw(cleanNonUTF8 formatDateTime logMsg logMsgPortal readConfig);
use mods::MSXML qw(msxmlCell msxmlClose msxmlColumn msxmlCreate msxmlData msxmlInitialise msxmlRow msxmlRowNumber msxmlSetParameter msxmlStyleAdd msxmlWorkbook);

# Program information
our $PROGRAM = "uip.pl";
our $VERSION = "2.0";

# Check there are any arguments
if($#ARGV == -1) { usage(); }

# Read command line options
our $COMPANY	= 'empty';
our $LOG		= 0;
our $YYMM		= 'empty';
GetOptions (
	'c|company=s'	=> \$COMPANY,
	'log'			=> \$LOG,
	'yymm=s'		=> \$YYMM,
	'help'			=> sub { usage(); } );

# Check that arguments are present
if($YYMM eq 'empty') { usage(1); }
if($COMPANY ne 'airwave' && $COMPANY ne 'techlive') { usage(2); }

# Read the configuration parameters and check that parameters have been read
our %CONFIG  = readConfig("$ROOT/etc/airwave-portal.conf");

# Declare global variables
our($FILENAME,%SCHED_E_DATA,$SCHED_A_ROWS,$SHEET_SCHED_A,$SHEET_SCHED_E);

# Define date related variables
our($MONTH,$CCYY,$PERIOD,$DAYS,$MONTH_START);
my @dpm = (31,28,31,30,31,30,31,31,30,31,30,31);
my @mmm = ('January','February','March','April','May','June','July','August','September','October','November','December');
$MONTH = int(substr($YYMM,2,2));
$CCYY = "20".substr($YYMM,0,2);
$PERIOD = $mmm[$MONTH-1]." $CCYY";
$DAYS = $dpm[$MONTH-1];
$MONTH_START = $YYMM."01";

# Declare global parameters
our $VAT = 0.2;			# Current VAT rate
our $FIRST_ROW = 4;		# First row number for a site

# Name of spreadsheet
if($COMPANY eq 'airwave') {
	$FILENAME = "UIP Schedules $YYMM Airwave";
}
else {
	$FILENAME = "UIP Schedules $YYMM Techlive";
}

# Spreadsheet parameters
msxmlSetParameter('NAME',$FILENAME);
msxmlSetParameter('DIR',"$ROOT/../$CONFIG{PORTAL_UIP}/$CCYY");
msxmlSetParameter('AUTHOR','Basil Fisk');
msxmlSetParameter('MARGIN_LEFT','0.75');
msxmlSetParameter('MARGIN_RIGHT','0.75');
msxmlSetParameter('ORIENTATION','landscape');

# Run the reports
main();





# ---------------------------------------------------------------------------------------------
# Main function
# ---------------------------------------------------------------------------------------------
sub main {
	my($status,$msg);

	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");
	logMsg($LOG,$PROGRAM,"Running the UIP Usage report for period '$YYMM'");

	# Initialise report and create styles to be used
	msxmlInitialise();
	set_styles();

	# Create the spreadsheet
	$msg = msxmlCreate();
	if($msg) {
		logMsgPortal($LOG,$PROGRAM,'E',$msg);
		return;
	}

	# For Airwave, generate a pair of sheets for hotels and a pair for ferries
	if($COMPANY eq 'airwave') {
		# Run the reports for hotels
		$SHEET_SCHED_A = "Schedule A $YYMM";
		schedule_a('hotel');
		$SHEET_SCHED_E = "Schedule E $YYMM";
		schedule_e('hotel');

		# Reset the Schedule E tracker
		%SCHED_E_DATA = ();

		# Run the reports for ferries
		$SHEET_SCHED_A = "Schedule A $YYMM Ferry";
		schedule_a('ferry');
		$SHEET_SCHED_E = "Schedule E $YYMM Ferry";
		schedule_e('ferry');
	}
	# For Techlive, generate a pair of sheets for standard films and a pair for classic films
	else {
		# Run the reports for standard films
		$SHEET_SCHED_A = "Schedule A $YYMM";
		schedule_a('standard');
		$SHEET_SCHED_E = "Schedule E $YYMM";
		schedule_e('standard');

		# Reset the Schedule E tracker
		%SCHED_E_DATA = ();

		# Run the reports for classic films
		$SHEET_SCHED_A = "Schedule A $YYMM Classics";
		schedule_a('classic');
		$SHEET_SCHED_E = "Schedule E $YYMM Classics";
		schedule_e('classic');
	}

	# Close the spreadsheet
	$msg = msxmlClose();
	if($msg) {
		logMsgPortal($LOG,$PROGRAM,'E',$msg);
		return;
	}
}



# ---------------------------------------------------------------------------------------------
# Schedule A report
#
# Argument 1 : hotel/ferry (Airwave) standard/classic (Techlive)
# ---------------------------------------------------------------------------------------------
sub schedule_a {
	my($type) = @_;
	my($status,$msg,%error);
	my(%sites,$site,$sitename,$rooms,$package,$tariff,$territory,$currents);
	my(%site_events,$title,$uipref,$release,$start,$library,$pct);
	my($charge,$plays,%all_events,%totals,$last_site,$site_1st_film,$siteref);

	logMsg($LOG,$PROGRAM,"Schedule A report for $COMPANY '$type' : $YYMM");

	# Read a hash of active sites of required site type that subscribe to UIP films
	# Hash is keyed by territory and site code
	if($COMPANY eq 'airwave') {
		# For Airwave, type is 'hotel' or 'ferry'
		($msg) = apiSelect('uipSitesAirwave',"period=$MONTH_START","type=$type");
	}
	else {
		# For Techlive, type is 'hotel' or 'classic'
		($msg) = apiSelect('uipSitesTechlive',"period=$MONTH_START","type=$type");
	}
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"No sites returned from database [$error{CODE}] $error{MESSAGE}");
		exit;
	}
	%sites = apiData($msg);

	# Process usage data for each site
	NEXTSITE: foreach my $id (sort keys %sites) {
		# Read the site details and generate the file name
		$site = $sites{$id}{site_code};
		$sitename = $sites{$id}{site};
		$rooms = $sites{$id}{rooms};
		$package = $sites{$id}{tariff};
		$tariff = $sites{$id}{tariff_rate};
		$territory = $sites{$id}{territory};
		$currents = $sites{$id}{films};

		# Tariff for Techlive Classic films is 0.25p/r/d
		if($COMPANY eq 'techlive') {
			$tariff = ($type eq 'classic') ? 0.25 : $tariff;
		}

		# Read the event data for the site
		%site_events = schedule_a_data($site,$sitename,$type,$currents);
		if(!%site_events) {
			logMsg($LOG,$PROGRAM,"$territory: $sitename [$site] - NO EVENTS RETURNED");
			next NEXTSITE;
		}

		# Create a hash of arrays (%all_events) that lists play data for each film in every site
		logMsg($LOG,$PROGRAM,"$territory: $sitename [$site]");
		foreach my $key (keys %site_events) {
			$title = $site_events{$key}{title};
			$uipref = $site_events{$key}{provider_ref};
			$release = $site_events{$key}{release_date};
			$start = $site_events{$key}{start_date};
			$library = $site_events{$key}{library_date};
			$plays = $site_events{$key}{views};
			$charge = $site_events{$key}{sterling};
			$pct = $site_events{$key}{percent};
			$all_events{"$territory:$sitename:$title"} = [($rooms,$charge,$release,$plays,$uipref,$pct,$package,$tariff,$start,$library,$territory,$sitename,$title,$site)];
		}
	}

	# Create hash of number of unique films watched in each site
	# Hash keyed by site name, value is number of unique films watched in the site
	foreach my $key (sort keys %all_events) {
		$site = $all_events{$key}[13];

		# Increment values for existing site
		if($totals{$site}) {
			$totals{$site} += 1;
		}
		# Create value for new site
		else {
			$totals{$site} = 1;
		}
	}

	# Open the output file and the XML writer object
	schedule_a_header($type);

	# Column headings
	schedule_a_columns();

	# Process each film in each site (sorted by site)
	$last_site = "";
	foreach my $key (sort keys %all_events) {
		# Extract the data for the current site/film from the hash
		($territory,$site,$title) = split(":",$key);
		($rooms,$charge,$release,$plays,$uipref,$pct,$package,$tariff,$start,$library,$territory,$site,$title,$siteref) = @{$all_events{$key}};

		# Flag whether this is the first film for the site - this is for report formatting only
		$site_1st_film = 0;
		if($last_site ne $siteref) {
			$site_1st_film = 1;
			$last_site = $siteref;
			$FIRST_ROW = 1 + msxmlRowNumber();
		}

		# Store the reference (key) and film name for the Schedule E report
		if(!$SCHED_E_DATA{$uipref}) {
			$SCHED_E_DATA{$uipref} = $title;
		}

		# 1 row/film for the site.  Some cell are empty if they are not in the 1st row
		schedule_a_row($site_1st_film,$territory,$site,$rooms,$plays,$title,$charge,$pct,$totals{$siteref},$release,$start,$library,$package,$tariff);
	}

	# Report totals
	schedule_a_totals();

	# Close output file
	schedule_a_footer();
}



# ---------------------------------------------------------------------------------------------
# Schedule A column titles
# ---------------------------------------------------------------------------------------------
sub schedule_a_columns {
	msxmlRow('open',35);
	msxmlCell('A','colhead-l','Territory');
	msxmlCell('B','colhead-l','Site');
	msxmlCell('C','colhead-c','Rooms');
	msxmlCell('D','colhead-c','Plays');
	msxmlCell('E','colhead-l','Title');
	msxmlCell('F','colhead-c','Daily Rate (pence)');
	msxmlCell('G','colhead-c','Days');
	msxmlCell('H','colhead-r','Daily Guarantee');
	msxmlCell('I','colhead-r','Price to Guest');
	msxmlCell('J','colhead-r','Gross Receipt');
	msxmlCell('K','colhead-c','Percentage');
	msxmlCell('L','colhead-r','Net Receipts');
	msxmlCell('M','colhead-r','Total Net');
	msxmlCell('N','colhead-r','Total Due');
	msxmlCell('O','colhead-r','Total Sched E');
	if($COMPANY eq 'airwave') {
		msxmlCell('P','colhead-c','Film Released');
		msxmlCell('Q','colhead-c','View Start Date');
		msxmlCell('R','colhead-c','Library Start Date');
		msxmlCell('S','colhead-l','Internal Package');
	}
	msxmlRow('close');
}



# ---------------------------------------------------------------------------------------------
# Read the usage data for the Schedule A report from the Portal events 
#
# Argument 1 : Site reference
# Argument 2 : Site name
# Argument 3 : hotel/ferry (Airwave) standard/classic (Techlive)
# Argument 4 : Number of current films in the package
#
# Return a hash of arrays or undef if no usage data exists for site
#       [key]=UID (1001+)
#       [0]=Asset code
#       [1]=Asset name
#       [2]=UIP reference
#       [3]=Release date
#       [4]=Library date (15 months after release date)
#       [5]=Number of views
#       [6]=Total guest revenue (Sterling)
#       [7]=UIP nominated (true/false)
#       [8]=Airwave percentage
#       [9]=Techlive percentage
# ---------------------------------------------------------------------------------------------
sub schedule_a_data {
	my($site,$sitename,$type,$currents) = @_;
	my($status,$msg,%error,%events);

	# Read list of aggregated events for site
	if($COMPANY eq 'airwave') {
		# For Airwave, type is 'hotel' or 'ferry'
		($msg) = apiSelect('uipEventsAirwave',"monthstart=$MONTH_START","site=$site");
	}
	else {
		# For Techlive, type is 'standard' or 'classic'
		($msg) = apiSelect('uipEventsTechlive',"monthstart=$MONTH_START","site=$site","type=$type");
	}
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"No usage data for $sitename '$site' [$error{CODE}] $error{MESSAGE}");
		return;
	}
	%events = apiData($msg);

	# Return the hash of events for the site
	return %events;
}



# ---------------------------------------------------------------------------------------------
# Close the Schedule A report
# ---------------------------------------------------------------------------------------------
sub schedule_a_footer {
	msxmlData('close');
	msxmlWorkbook('close',$SHEET_SCHED_A);
}



# ---------------------------------------------------------------------------------------------
# Open the Schedule A report
#
# Argument 1 : hotel/ferry (Airwave) standard/classic (Techlive)
# ---------------------------------------------------------------------------------------------
sub schedule_a_header {
	my($type) = @_;
	my($class,$msg);

	if($COMPANY eq 'airwave') {
		$class = ($type eq 'hotel') ? 'Hotels' : 'Ferries';
	}
	else {
		$class = ($type eq 'standard') ? 'Standard Films' : 'Classic Films';
	}

	# Create the spreadsheet
	$msg = msxmlWorkbook('open',$SHEET_SCHED_A);
	if($msg) {
		logMsgPortal($LOG,$PROGRAM,'E',$msg);
		return;
	}
	msxmlColumn('open');
	msxmlColumn('insert',20,1);
	msxmlColumn('insert',30,1);
	msxmlColumn('insert',7,2);
	msxmlColumn('insert',30,1);
	msxmlColumn('insert',9,13);
	msxmlColumn('insert',20,1);
	msxmlColumn('close');
	msxmlData('open');

	# Title row
	msxmlRow('open',25);
	msxmlCell('A','heading',"Schedule A Report for $class during $PERIOD");
	msxmlRow('close');

	# Blank row
	msxmlRow('open');
	msxmlCell('A','normal','');
	msxmlRow('close');
}



# ---------------------------------------------------------------------------------------------
# 1 row/film for the site. Some cell are empty if they are not in the 1st row
#
# Argument  1 : 1 if this is the first film for the site, 0 otherwise
# Argument  2 : Territory in which the site is located
# Argument  3 : Name of the site
# Argument  4 : Number of rooms
# Argument  5 : Number of film plays
# Argument  6 : Film title
# Argument  7 : Price the guest paid for the film
# Argument  8 : Percentage of purchase price to UIP
# Argument  9 : Number of unique films watched in this site
# Argument 10 : Release date of film
# Argument 11 : NTR date
# Argument 12 : Start date of Library contract
# Argument 13 : Name of company's content package
# Argument 14 : Pence/room/day rate for the content package
# ---------------------------------------------------------------------------------------------
sub schedule_a_row {
	my($site_1st_film,$territory,$site,$rooms,$plays,$title,$charge,$pct,$tot_films,$release,$start,$library,$package,$tariff) = @_;
	my($row,$ok);

	# Open the row container and fetch the row number
	msxmlRow('open');
	$row = msxmlRowNumber();

	# Set charge to 0 if null
	if(!$charge) { $charge = 0; }

	# Clean up and log invalid characters found in the film title
	($ok,$title) = cleanNonUTF8($title);
	if(!$ok) {
		logMsgPortal($LOG,$PROGRAM,'W',"Invalid character found in film name: $title");
	}

	# Print the first film for the site.  This record shows both site and film data
	if($site_1st_film) {
		msxmlCell('A','text-l',$territory);
		msxmlCell('B','text-l',$site);
		msxmlCell('C','dp0',$rooms);
		msxmlCell('D','dp0',$plays);
		msxmlCell('E','text-l',$title);
		msxmlCell('F','dp1',$tariff);
		msxmlCell('G','dp0',$DAYS);
		msxmlCell('H','stg',"=C$row*F$row*G$row/100");
		msxmlCell('I','stg',$charge/100);
		msxmlCell('J','stg',"=D$row*I$row");
		msxmlCell('K','pct',$pct/100);
		msxmlCell('L','stg',"=(J$row/".(1+$VAT).")*K$row");
		msxmlCell('M','stg',"=SUM(L$FIRST_ROW:L".($FIRST_ROW+$tot_films-1).")");
		msxmlCell('N','stg',"=MAX(H$row,M$row)");
		msxmlCell('O','stg',"=IF(L$row=0,D$row*N\$$FIRST_ROW/SUM(D$FIRST_ROW:D".($FIRST_ROW+$tot_films-1)."),L$row*N\$$FIRST_ROW/M\$$FIRST_ROW)");
		if($COMPANY eq 'airwave') {
			msxmlCell('P','text-c',$release);
			msxmlCell('Q','text-c',$start);
			msxmlCell('R','text-c',$library);
			msxmlCell('S','text-l',$package);
		}
	}
	# Print subsequent films for the site.  This record only shows film data
	else {
		msxmlCell('D','dp0',$plays);
		msxmlCell('E','text-l',$title);
		msxmlCell('I','stg',$charge/100);
		msxmlCell('J','stg',"=D$row*I$row");
		msxmlCell('K','pct',$pct/100);
		msxmlCell('L','stg',"=(J$row/".(1+$VAT).")*K$row");
		msxmlCell('O','stg',"=IF(L$row=0,D$row*N\$$FIRST_ROW/SUM(D$FIRST_ROW:D".($FIRST_ROW+$tot_films-1)."),L$row*N\$$FIRST_ROW/M\$$FIRST_ROW)");
		if($COMPANY eq 'airwave') {
			msxmlCell('P','text-c',$release);
			msxmlCell('Q','text-c',$start);
			msxmlCell('R','text-c',$library);
		}
	}

	# Close the row container
	msxmlRow('close');
}



# ---------------------------------------------------------------------------------------------
# Totals at the bottom of the Schedule A report
# ---------------------------------------------------------------------------------------------
sub schedule_a_totals {
	# Read the last row number and save it as it will be used by the Schedule E report as well
	$SCHED_A_ROWS = msxmlRowNumber();

	# Open the row container
	msxmlRow('open');

	# Open the row container
	msxmlCell('H','stg-bold',"=SUM(H4:H$SCHED_A_ROWS)");
	msxmlCell('J','stg-bold',"=SUM(J4:J$SCHED_A_ROWS)");
	msxmlCell('L','stg-bold',"=SUM(L4:L$SCHED_A_ROWS)");
	msxmlCell('N','stg-bold',"=SUM(N4:N$SCHED_A_ROWS)");
	msxmlCell('O','stg-bold',"=SUM(O4:O$SCHED_A_ROWS)");

	# Close the row container
	msxmlRow('close');
}



# ---------------------------------------------------------------------------------------------
# Schedule E report
#
# Argument 1 : hotel/ferry (Airwave) standard/classic (Techlive)
# ---------------------------------------------------------------------------------------------
sub schedule_e {
	my($type) = @_;
	logMsg($LOG,$PROGRAM,"Schedule E: $YYMM");

	# Open the report and create the header
	schedule_e_header($type);

	# Column headings
	schedule_e_columns();

	# Film totals for the site and keep a running total
	foreach my $ref (sort keys %SCHED_E_DATA) {
		schedule_e_row($SCHED_E_DATA{$ref},$ref);
	}

	# Report totals
	schedule_e_totals();

	# Close XML output file
	schedule_e_footer();
}



# ---------------------------------------------------------------------------------------------
# Schedule E column titles
# ---------------------------------------------------------------------------------------------
sub schedule_e_columns {
	msxmlRow('open',29);
	msxmlCell('A','colhead-l','Film Title');
	msxmlCell('B','colhead-l','');
	msxmlCell('C','colhead-c','Picture Number');
	msxmlCell('D','colhead-r','Rental');
	msxmlRow('close');
}



# ---------------------------------------------------------------------------------------------
# Close the Schedule E report
# ---------------------------------------------------------------------------------------------
sub schedule_e_footer {
	msxmlData('close');
	msxmlWorkbook('close',$SHEET_SCHED_E);
}



# ---------------------------------------------------------------------------------------------
# Open the Schedule E report and create the heading at top
#
# Argument 1 : hotel/ferry (Airwave) standard/classic (Techlive)
# ---------------------------------------------------------------------------------------------
sub schedule_e_header {
	my($type) = @_;
	my($class,$name,$territory,$terr_no,$size,$msg);

	# Set up report title
	if($COMPANY eq 'airwave') {
		$class = ($type eq 'hotel') ? 'Hotels' : 'Ferries';
	}
	else {
		$class = ($type eq 'standard') ? 'Standard Films' : 'Classic Films';
	}

	# Customer name, territory name and number, and film size
	$name = ($COMPANY eq 'airwave') ? 'Airwave' : 'Techlive';
	$territory = ($COMPANY eq 'airwave') ? 'UK' : 'Europe';
	$terr_no = ($COMPANY eq 'airwave') ? '627' : '588';
	$size = ($type eq 'ferry') ? '1' : '7';

	# Create the spreadsheet
	$msg = msxmlWorkbook('open',$SHEET_SCHED_E);
	if($msg) {
		logMsgPortal($LOG,$PROGRAM,'E',$msg);
		return;
	}
	msxmlColumn('open');
	msxmlColumn('insert',12,1);
	msxmlColumn('insert',30,1);
	msxmlColumn('insert',12,2);
	msxmlColumn('close');
	msxmlData('open');

	# Title row
	msxmlRow('open',25);
	msxmlCell('A','heading',"Schedule E Report for $class during $PERIOD");
	msxmlRow('close');

	# Blank row
	msxmlRow('open');
	msxmlCell('A','normal','');
	msxmlRow('close');

	# Provider details
	msxmlRow('open');
	msxmlCell('A','colhead-l','Film Size');
	msxmlCell('B','text-l',$size);
	msxmlRow('close');

	msxmlRow('open');
	msxmlCell('A','colhead-l','Customer');
	msxmlCell('B','text-l',$name);
	msxmlCell('C','colhead-l','Currency');
	msxmlCell('D','text-l','GBP');
	msxmlRow('close');

	msxmlRow('open');
	msxmlCell('A','colhead-l','Territory');
	msxmlCell('B','text-l',$territory);
	msxmlCell('C','colhead-l','Year');
	msxmlCell('D','text-l',$CCYY);
	msxmlRow('close');

	msxmlRow('open');
	msxmlCell('A','colhead-l','Territory No.');
	msxmlCell('B','text-l',$terr_no);
	msxmlCell('C','colhead-l','Period');
	msxmlCell('D','text-l',$MONTH);
	msxmlRow('close');

	# Spacer row between tables
	msxmlRow('open');
	msxmlCell('A','text-l','');
	msxmlRow('close');
}



# ---------------------------------------------------------------------------------------------
# 1 row/film. Some cell are empty if they are not in the 1st row
#
# Argument 1 : Film title
# Argument 2 : UIP film reference
# ---------------------------------------------------------------------------------------------
sub schedule_e_row {
	my($title,$ref) = @_;
	my($ok,$row);

	# Clean up and log invalid characters found in the film title
	($ok,$title) = cleanNonUTF8($title);
	if(!$ok) {
		logMsgPortal($LOG,$PROGRAM,'W',"Invalid character found in film name: $title");
	}

	# Open the container
	msxmlRow('open');

	# Read the current row number
	$row = msxmlRowNumber();

	# Trim ref to 7 characters (UIP refs will be same for 1 film with 2 encodings and we have to add a suffix to make unique)
	$ref = substr($ref,0,7);

	# Print the row
	msxmlCell('A','text-l',$title);
	msxmlCell('B','text-l','');
	msxmlCell('C','text-c',$ref);
	msxmlCell('D','dp2',"=SUMIF('$SHEET_SCHED_A'!\$E\$4:\$E\$$SCHED_A_ROWS,A$row,'$SHEET_SCHED_A'!\$O\$4:\$O\$$SCHED_A_ROWS)");

	# Close the container
	msxmlRow('close');
}



# ---------------------------------------------------------------------------------------------
# Totals at the bottom of the Schedule E report
# ---------------------------------------------------------------------------------------------
sub schedule_e_totals {
	# Read the last row number
	my $row = msxmlRowNumber();

	# Open the container
	msxmlRow('open');

	# Print the total amount
	msxmlCell('D','dp2-bold',"=SUM(D9:D$row)");

	# Close the container
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

	# Fonts
	msxmlStyleAdd("font","std","name=Arial,size=8");
	msxmlStyleAdd("font","std-bold","name=Arial,size=8,bold");
	msxmlStyleAdd("font","big-bold","name=Arial,size=14");

	# Cells
	msxmlStyleAdd("cell","heading","font=big-bold,number=int0,horizontal=left,vertical=center");
	msxmlStyleAdd("cell","colhead-c","font=std-bold,number=normal,horizontal=center,vertical=center,wrapText");
	msxmlStyleAdd("cell","colhead-l","font=std-bold,number=normal,horizontal=left,vertical=center,wrapText");
	msxmlStyleAdd("cell","colhead-r","font=std-bold,number=normal,horizontal=right,vertical=center,wrapText");
	msxmlStyleAdd("cell","text-c","font=std,horizontal=center,vertical=center");
	msxmlStyleAdd("cell","text-l",",font=std,horizontal=left,vertical=center");
	msxmlStyleAdd("cell","dp0","font=std,number=int0,horizontal=center,vertical=center");
	msxmlStyleAdd("cell","dp0-bold","font=std-bold,number=int0,horizontal=center,vertical=center");
	msxmlStyleAdd("cell","dp1","font=std,number=int1,horizontal=right,vertical=center");
	msxmlStyleAdd("cell","dp2","font=std,number=int2,horizontal=right,vertical=center");
	msxmlStyleAdd("cell","dp2-bold","font=std-bold,number=int2,horizontal=right,vertical=center");
	msxmlStyleAdd("cell","stg","font=std,number=stg,horizontal=right,vertical=center");
	msxmlStyleAdd("cell","stg-bold","font=std-bold,number=stg,horizontal=right,vertical=center");
	msxmlStyleAdd("cell","pct","font=std,number=pct0,horizontal=right,vertical=center");
}



# ---------------------------------------------------------------------------------------------
# Program usage
# ---------------------------------------------------------------------------------------------
sub usage {
	my($err) = @_;
	$err = ($err) ? $err : 0;

	if($err == 1) {
		logMsg($LOG,$PROGRAM,"The 'yymm' argument is mandatory");
	}
	elsif($err == 2) {
		logMsg($LOG,$PROGRAM,"The 'company' must either be 'airwave' or 'techlive'");
	}
	else {
		printf("
Program : $PROGRAM
Version : v$VERSION
Author  : Basil Fisk (c)2013 Airwave Ltd

Summary :
  Run the monthly usage report for UIP, which produces a spreadsheet in MS-XML format.
  The spreadsheet contains 2 tabs holding the Schedule A and Schedule E reports, whose
  format have been specified by UIP. The spreadsheet will be written to the Airwave Portal.

Usage :
  $PROGRAM --yymm=<YYMM>
  
  MANDATORY
  --company=<name>	The company for whom the figures are being generated (airwave/techlive).
  --yymm=<YYMM>		The reporting month in YYMM format.
  
  OPTIONAL
  --log		If set, the results from the script will be written to the Airwave
			log directory, otherwise the results will be written to the screen.
		\n");
	}
	exit;
}
