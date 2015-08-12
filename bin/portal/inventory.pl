#!/usr/bin/perl
# *********************************************************************************************
# *********************************************************************************************
# 
#  Generate an inventory of assets that are currently located in each site, as well as a list
#  of the assets that are now out of licence and which should be deleted.
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
use mods::Common qw(cleanNonUTF8 formatDateTime logMsg logMsgPortal readConfig);
use mods::PDF qw(pdfReport);

# Program information
our $PROGRAM = "inventory.pl";
our $VERSION = "2.0";

# Check there are any arguments
our $LOG		= 0;
our $OBSOLETE	= 1;
our $SITE		= 'all';
our $UPDATES	= 1;
GetOptions (
	'no|nonoobsolete'	=> sub { $OBSOLETE = 0; },
	'nu|noupdates'		=> sub { $UPDATES = 0; },
	's|site=s'			=> \$SITE,
	'log'				=> \$LOG,
	'help'				=> sub { usage(); } );

# Read the configuration parameters
our %CONFIG  = readConfig("$ROOT/etc/airwave-portal.conf");

# Name of data file and configuration file
our($FILEHANDLE,$XML);
our $CONFFILE = "$ROOT/etc/inventory.conf";
our $DATAFILE = "$CONFIG{TEMP}/inventory.xml";

# Start processing
main();





# ---------------------------------------------------------------------------------------------
# Run the report
# ---------------------------------------------------------------------------------------------
sub main {
	# Initialise local variables
	my($period,$status,$msg,%error,%sites);
	my($partner,$sitecode,$encryption,$territory,$package,$ok,$filename);

	# Start up message
	logMsg($LOG,$PROGRAM,"=================================================================================");
	logMsg($LOG,$PROGRAM,"Inventories");

	# Read the list of sites
	$period = formatDateTime('yyzmzd');
	($msg) = apiSelect('inventorySites',"site=$SITE","period=$period");
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"No sites returned from database [$error{CODE}] $error{MESSAGE}");
		exit;
	}
	%sites = apiData($msg);

	# Process each site
	foreach my $sitename (sort keys %sites) {
		$partner = $sites{$sitename}{'partner'};
		$sitecode = $sites{$sitename}{'site_code'};
		$encryption = $sites{$sitename}{'encryption'};
		$territory = $sites{$sitename}{'territory'};
		$package = $sites{$sitename}{'package'};

		# Clean up site nae
		$sitename =~ s/&amp;/&/g;
		($ok,$sitename) = cleanNonUTF8($sitename);
		if(!$ok) {
			logMsgPortal($LOG,$PROGRAM,'W',"Invalid character found in site name: $sitename");
		}
		logMsg($LOG,$PROGRAM,"Site: $sitename");

		# Generate data file with current inventory of films
		open_file();
		boilerplate($sitename);
		summary_page($sitecode,$sitename,$encryption,$territory,$package);
		current_films($sitecode,$sitename);
		if($OBSOLETE) {
			obsolete_films($sitecode,$sitename);
		}
		close_file();

		# Remove non-alphanumeric characters
		$filename = "Inventory - $sitename.pdf";
		$filename =~ s/[^a-zA-Z0-9 \.\-]//g;

		# Generate PDF file with current inventory of films
		pdfReport($CONFFILE,$DATAFILE,"$ROOT/../$CONFIG{PORTAL_INVENTORY}/$sitecode/$filename");
	}
}



# ---------------------------------------------------------------------------------------------
# Create the static 'boilerplate' definitions to be shown on each page
#
# Argument 1 : Site name
# ---------------------------------------------------------------------------------------------
sub boilerplate {
	my($sitename) = @_;

	# Generate the static section in the data file
	$XML->startTag('static');

	# Header and footer
	$XML->dataElement('sitename',$sitename);
	$XML->dataElement('section1',"Summary of Content Packages and Latest Distributions");
	$XML->dataElement('section2',"Licenced Films");
	if($OBSOLETE) {
		$XML->dataElement('section3',"Expired Films");
	}
	$XML->dataElement('timestamp',formatDateTime('zd/zm/ccyy hh24:mi'));

	# Close static container
	$XML->endTag('static');

	# Open the dynamic section in the data file
	$XML->startTag('dynamic');
}



# ---------------------------------------------------------------------------------------------
# Close the data file and the XML document that holds the document definitions
# ---------------------------------------------------------------------------------------------
sub close_file {
	$XML->endTag('dynamic');
	$XML->endTag('data');
	$XML->end();
	$FILEHANDLE->close();
}



# ---------------------------------------------------------------------------------------------
# Open the data file and the XML document that holds the document definitions
# ---------------------------------------------------------------------------------------------
sub open_file {
	open($FILEHANDLE,">$DATAFILE");
	$XML = new XML::Writer(OUTPUT => $FILEHANDLE);
	$XML->startTag('data');
}



# ---------------------------------------------------------------------------------------------
# Create the XML data file for the current inventory of films
#
# Argument 1 : Site reference
# Argument 2 : Site name
# Argument 3 : Type of encryption
# Argument 4 : Territory
# Argument 5 : Content package details
# ---------------------------------------------------------------------------------------------
sub summary_page {
	my($sitecode,$sitename,$encryption,$territory,$package) = @_;
	my($status,$msg,%error,%films);
	my($filmname,$certificate,$languages,$installed,$deleted,$ok);

	# Open a container for the summary data
	$XML->startTag('record','id'=>'summary');

	# Territory and encryption
	$XML->dataElement('territory',$territory);
	$XML->dataElement('encryption',$encryption);

	# Packages
	$package =~ s/, /\\n/g;
	$XML->dataElement('package',$package);

	# Close the container for the summary data
	$XML->endTag('record');

	# Only print list of added and retired films if requested by user
	if($UPDATES) {
		# Read the list of added films
		($msg) = apiSelect('inventoryAdditions',"site=$sitecode");
		($status,%error) = apiStatus($msg);
		if(!$status) {
			logMsgPortal($LOG,$PROGRAM,'E',"No 'added' films found for '$sitename' [$error{CODE}] $error{MESSAGE}");
		}
		# Print each added film
		else {
			%films = apiData($msg);
			foreach my $film (sort keys %films) {
				# Read the film record
				$package = $films{$film}{'package'};
				$filmname = $films{$film}{'title'};
				$certificate = $films{$film}{'certificate'};
				$languages = $films{$film}{'languages'};
				$installed = $films{$film}{'licence_start'};
				$filmname =~ s/&amp;/&/g;
				($ok,$filmname) = cleanNonUTF8($filmname);
				if(!$ok) {
					logMsgPortal($LOG,$PROGRAM,'W',"Invalid character found in film name: $filmname");
				}
	
				# Create the film record
				$XML->startTag('record','id'=>'new');
				$XML->dataElement('package',$package);
				$XML->dataElement('filmname',$filmname);
				$XML->dataElement('certificate',$certificate);
				$XML->dataElement('languages',$languages);
				$XML->dataElement('installed',$installed);
				$XML->endTag('record');
			}
		}

		# Read the list of retired films
		($msg) = apiSelect('inventoryRemovals',"site=$sitecode");
		($status,%error) = apiStatus($msg);
		if(!$status) {
			logMsgPortal($LOG,$PROGRAM,'E',"No 'retired' films found for '$sitename' [$error{CODE}] $error{MESSAGE}");
		}
		# Print each retired film
		else {
			%films = apiData($msg);
			foreach my $film (sort keys %films) {
				# Read the film record
				$package = $films{$film}{'package'};
				$filmname = $films{$film}{'title'};
				$certificate = $films{$film}{'certificate'};
				$languages = $films{$film}{'languages'};
				$deleted = $films{$film}{'licence_end'};
	
				$filmname =~ s/&amp;/&/g;
				($ok,$filmname) = cleanNonUTF8($filmname);
				if(!$ok) {
					logMsgPortal($LOG,$PROGRAM,'W',"Invalid character found in film name: $filmname");
				}
	
				# Create the film record
				$XML->startTag('record','id'=>'old');
				$XML->dataElement('package',$package);
				$XML->dataElement('filmname',$filmname);
				$XML->dataElement('certificate',$certificate);
				$XML->dataElement('languages',$languages);
				$XML->dataElement('deleted',$deleted);
				$XML->endTag('record');
			}
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Append the current inventory of films to the XML data file
#
# Argument 1 : Site reference
# Argument 2 : Site name
# ---------------------------------------------------------------------------------------------
sub current_films {
	my($sitecode,$sitename) = @_;
	my($status,$msg,%error,%films);
	my($count,$last,$package,$filmname,$certificate,$languages,$installed,$ok);

	# Read the list of films
	($msg) = apiSelect('inventoryInstalled',"site=$sitecode");
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"No 'installed' films for site '$sitename' [$error{CODE}] $error{MESSAGE}");
	}
	%films = apiData($msg);

	# Initialise the counter and the last package tracker
	$count = 0;
	$last = '';

	# Output each film
	foreach my $film (sort keys %films) {
		# Read the film record
		$package = $films{$film}{'package'};
		$filmname = $films{$film}{'title'};
		$certificate = $films{$film}{'certificate'};
		$languages = $films{$film}{'languages'};
		$installed = $films{$film}{'licence_start'};

		$filmname =~ s/&amp;/&/g;
		($ok,$filmname) = cleanNonUTF8($filmname);
		if(!$ok) {
			logMsgPortal($LOG,$PROGRAM,'W',"Invalid character found in film name: $filmname");
		}

		# Increment the counter for packages
		if($package eq $last) {
			$count++;
		}
		else {
			$count = 1;
			$last = $package;
		}

		# Create the film record
		$XML->startTag('record','id'=>'current');
		$XML->dataElement('count',$count);
		$XML->dataElement('package',$package);
		$XML->dataElement('filmname',$filmname);
		$XML->dataElement('certificate',$certificate);
		$XML->dataElement('languages',$languages);
		$XML->dataElement('installed',$installed);
		$XML->endTag('record');
	}
}



# ---------------------------------------------------------------------------------------------
# Append the obsolete inventory of films to the XML data file
#
# Argument 1 : Site reference
# Argument 2 : Site name
# ---------------------------------------------------------------------------------------------
sub obsolete_films {
	my($sitecode,$sitename) = @_;
	my($status,$msg,%error,%films);
	my($count,$last,$provider,$filmname,$certificate,$retired,$installed,$ok);

	# Read the list of films
	($msg) = apiSelect('inventoryObsolete',"site=$sitecode");
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsgPortal($LOG,$PROGRAM,'E',"No 'obsolete' films for site '$sitename' [$error{CODE}] $error{MESSAGE}");
	}
	%films = apiData($msg);

	# Initialise the counter and the last package tracker
	$count = 0;
	$last = '';

	# Output each film
	foreach my $film (sort keys %films) {
		# Read the film record
		$provider = $films{$film}{'provider'};
		$filmname = $films{$film}{'title'};
		$certificate = $films{$film}{'certificate'};
		$retired = $films{$film}{'licence_end'};
		$installed = $films{$film}{'licence_start'};

		$filmname =~ s/&amp;/&/g;
		($ok,$filmname) = cleanNonUTF8($filmname);
		if(!$ok) {
			logMsgPortal($LOG,$PROGRAM,'W',"Invalid character found in film name: $filmname");
		}

		# Increment the counter for packages
		if($provider eq $last) {
			$count++;
		}
		else {
			$count = 1;
			$last = $provider;
		}

		# Create the film record
		$XML->startTag('record','id'=>'obsolete');
		$XML->dataElement('count',$count);
		$XML->dataElement('provider',$provider);
		$XML->dataElement('filmname',$filmname);
		$XML->dataElement('certificate',$certificate);
		$XML->dataElement('installed',$installed);
		$XML->dataElement('retired',$retired);
		$XML->endTag('record');
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
  Generate an inventory of assets that are currently located in each site, as well as a list
  of the assets that are now out of licence and which should be deleted.
  The report is a PDF file.

Usage :
  $PROGRAM

  OPTIONAL
    --no|noobsolete	Prevents the pages of obsolete films from being printed.  If this 
					argument is not specified, the paages will be printed.
    --nu|noupdates	Prevents the list of new and retired films from being printed on the 
					summary page.  If this argument is not specified, the details will
					be printed on the summary page.
    --s|site=<name>	Site for which the inventory is to be run.  The default is all sites.
    --log			If set, the results from the script will be written to the Airwave
					log directory, otherwise the results will be written to the screen.
		\n");
	exit;
}
