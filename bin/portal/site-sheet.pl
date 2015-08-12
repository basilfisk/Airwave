#!/usr/bin/perl
# *********************************************************************************************
# *********************************************************************************************
# 
#  Generate a page showing all details for a named site or site(s)
#  The report is a PDF file.
# 
# *********************************************************************************************
# *********************************************************************************************

# Establish the root directory
our $ROOT;
BEGIN {
	$ROOT = '/srv/visualsaas/instances/aa002/bin';
}

# Declare modules
use strict;
use warnings;

# System modeles
use Data::Dumper;
use Getopt::Long;
use IO::File;
use XML::Writer;

# Breato modules
use lib "$ROOT";
use mods::API qw(apiData apiStatus apiSelect);
use mods::Common qw(formatDateTime logMsg logMsgPortal readConfig);
use mods::PDF qw(pdfReport);

# Program information
our $PROGRAM = "site-sheet.pl";
our $VERSION = "2.0";

# Check there are any arguments
our $SITE	= 'empty';
our $LOG	= 0;
GetOptions (
	's|site=s'	=> \$SITE,
	'log'		=> \$LOG,
	'help'		=> sub { usage(); } );

# Read the configuration parameters
our %CONFIG  = readConfig("$ROOT/etc/airwave-portal.conf");

# Name of data file and configuration file
our $SITECONF = "$ROOT/etc/site_sheet.conf";
our $DATAFILE = "$CONFIG{TEMP}/site_sheet.xml";
our $PDFDIR = "$CONFIG{TEMP}";
our $PDFFILE = "Site\ Sheet.pdf";

# Check that site argument has been entered
if($SITE eq 'empty') { usage(1); }

# Use wild card for searching if all sites requested
if($SITE eq 'all') { $SITE = '*'; }

# Start processing
main();





# ---------------------------------------------------------------------------------------------
# Run the report
# ---------------------------------------------------------------------------------------------
sub main {
	# Initialise local variables
	my($status,$msg,%error,%sites,$fh,$xml,$sitename,$sitecode,$address,$packages);

	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");
	logMsg($LOG,$PROGRAM,"Site Sheets");

	# Read the list of sites
	($msg) = apiSelect('sitesActive',"sitecode=$SITE");
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"No sites returned from database [$error{CODE}] $error{MESSAGE}");
		exit;
	}
	%sites = apiData($msg);

	# Process each site
	foreach my $id (sort keys %sites) {
		$sitename = $sites{$id}{site_name};
		$sitename =~ s/&amp;/&/g;
		$sitecode = $sites{$id}{site_code};
		logMsg($LOG,$PROGRAM,"Printing site sheet for $sitename");

		# Open the XML document and create the container elements
		open($fh,">$DATAFILE");
		$xml = new XML::Writer(OUTPUT => $fh);
		$xml->xmlDecl("ISO-8859-1");
		$xml->startTag('data');

		# Generate the static section in the configuration file
		$xml->startTag('static');
		$xml->dataElement('page-title','Site Data Sheet');
		$xml->dataElement('timestamp',formatDateTime('zd/zm/ccyy hh24:mi'));
		$xml->endTag('static');

		# Generate the dynamic section in the configuration file
		$xml->startTag('dynamic');

		# Print a single page for the site
		$xml->startTag('record','id'=>'data');
		$xml->dataElement('name',$sitename);
		$xml->dataElement('code',$sitecode);
		$address = $sites{$id}{address};
		$address =~ s/\n/\\n/g;
		$address =~ s/#nl#/\\n/g;
		$address =~ s/&amp;/&/g;
		$xml->dataElement('address',$address);
		$xml->dataElement('postcode',$sites{$id}{postcode});
		$xml->dataElement('contact',$sites{$id}{contact_name});
		$xml->dataElement('telephone',$sites{$id}{contact_phone});
		$xml->dataElement('email',$sites{$id}{contact_email});
		$xml->dataElement('territory',$sites{$id}{territory});
		$xml->dataElement('partner',$sites{$id}{partner_name});
		$xml->dataElement('pcontact',$sites{$id}{partner_contact});
		$xml->dataElement('ptelephone',$sites{$id}{partner_phone});
		$xml->dataElement('pemail',$sites{$id}{partner_email});
		$xml->dataElement('invoiceco',$sites{$id}{invoiced_by});
		$xml->dataElement('live',$sites{$id}{live});
		$xml->dataElement('term',$sites{$id}{term});
		$packages = $sites{$id}{package};
		$packages =~ s/, /\\n/g;
		$xml->dataElement('package',$packages);
		$xml->dataElement('server',$sites{$id}{vod_server});
		$xml->dataElement('encryption',$sites{$id}{encryption});
		$xml->dataElement('stb',$sites{$id}{stb});
		$xml->dataElement('distribution',$sites{$id}{distribution});
		$xml->dataElement('type',$sites{$id}{site_type});
		$xml->dataElement('rooms',$sites{$id}{rooms});
		$xml->endTag('record');

		# Close the containers, then close the XML file
		$xml->endTag('dynamic');
		$xml->endTag('data');
		$xml->end();
		$fh->close();

		# Generate PDF file with 1 page/site
		pdfReport($SITECONF,$DATAFILE,"$ROOT/../$CONFIG{PORTAL_INVENTORY}/$sitecode/$PDFFILE");
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
		print "\nA single site must be specified, or 'all' for all active sites\n\n";
	}
	else {
		printf("
Program : $PROGRAM
Version : v$VERSION
Author  : Basil Fisk (c)2013 Airwave Ltd

Summary :
  Generate a page showing all details for a named site or site(s)
  The report is a PDF file.

Usage :
  $PROGRAM

  MANDATORY
    --s|site=<name>      Site to be processed, or 'all' for all active sites.
  
  OPTIONAL
    --log		If set, the results from the script will be written to the Airwave
				log directory, otherwise the results will be written to the screen.
		\n");
	}

	# Stop in all cases
	exit;
}
