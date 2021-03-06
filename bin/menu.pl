#!/usr/bin/perl
# *********************************************************************************************
# *********************************************************************************************
#
#  This script presents all the Airwave functions through a single GUI application
#
# *********************************************************************************************
# *********************************************************************************************

# Declare modules
use strict;
use warnings;

# Breato modules
use lib "$ENV{'AIRWAVE_ROOT'}";
use mods::API3 qw(apiData apiSelect apiStatus);
use mods::Common qw(formatDateTime logMsg readConfig);
use mods::TK;

# Program information
our $PROGRAM = "menu.pl";
our $VERSION = "2.0";

# Read the configuration parameters
our %CONFIG  = readConfig("$ENV{'AIRWAVE_ROOT'}/etc/airwave.conf");

# Determine the server the menu is running on
our $SERVER = `hostname`;
chomp $SERVER;

# Set logging to file
our $LOG = 1;

# Set up global variables
our %LISTVALUES;
read_listvalues();
our @PROVIDER = ('BBC','Disney','GFC','Giving Tales','PBTV','TVF','UIP');
our %TOPLEFT = (
		'x'		=> 20,
		'y'		=> 20,
		'xinc'	=> 110,
		'yinc'	=> 30);

# Open the database connection and run the reports
main();





# ---------------------------------------------------------------------------------------------
# Main processing loop
# ---------------------------------------------------------------------------------------------
sub main {
	my($name);

	# Open the application window and create the menus
	tkAppOpen('Airwave','Airwave Content Management System',200,200,650,500);

	# File menu
	tkMenu('File');
	tkMenuOption('File','Exit','tkClose','Airwave');

	# Functions available on the Preparation Workstation
	if($SERVER eq 'prep' || $SERVER eq 'bf') {
		# Film processing options
		tkMenu('Preparation');
		tkMenuOption('Preparation','Ingest Film','ingest_film','ask');

		# Log files
		tkMenu('Logs');
		$name = 'Menu Warnings/Errors';
		tkMenuOption('Logs',$name,'view_log',$name,'menu.log');
		$name = 'Ingest Log';
		tkMenuOption('Logs',$name,'view_log',$name,'ingest_film.log');
		$name = 'Sync-Server Log';
		tkMenuOption('Logs',$name,'view_log',$name,'sync-server.log');
	}

	# Functions available on the Distribution Server
	if($SERVER eq 'distro' || $SERVER eq 'bf') {
		# Daemon process options
		tkMenu('Distribution');
		tkMenuOption('Distribution','Start CDS Processes','cds_start','ask');
		tkMenuOption('Distribution','Stop CDS Processes','cds_stop','ask');
		tkMenuOption('Distribution','Status of CDS Processes','cds_status','ask');

		# Log files
		tkMenu('Logs');
		$name = 'Menu Warnings/Errors';
		tkMenuOption('Logs',$name,'view_log',$name,'menu.log');
		$name = 'CDS Distributions Log';
		tkMenuOption('Logs',$name,'view_log',$name,'cds.log');
	}

	# Start the main processing loop
	tkMain();
}





# *********************************************************************************************
# *********************************************************************************************
#
# Common functions
#
# *********************************************************************************************
# *********************************************************************************************

# ---------------------------------------------------------------------------------------------
# Holding page
# ---------------------------------------------------------------------------------------------
sub holding_page {
	tkOption('Airwave','Holding Page','This feature has not been implemented yet','OK');
}



# ---------------------------------------------------------------------------------------------
# Calculate position of buttons at bottom of form, given size of form
#
# Argument 1 : Width of form
# Argument 2 : Height of form
# Argument 3 : Number of buttons
# Argument 4 : Length of the button
#
# Return the Y coord, follows by as many X coords as buttons
# ---------------------------------------------------------------------------------------------
sub button_coords {
	my($w,$h,$n,$l) = @_;
	my($left,@x,$y);

	# Set gap between buttons and offset from bottom of form to top of button
	my $gap = 20;
	my $offset = 45;

	# Calculate Y coord
	$y = $h-$offset;

	# Calculate X coords, starting from left of 1st button
	$left = ($w-($n*$l*10)-(($n-1)*$gap))/2;
	for(my $i=0; $i<$n; $i++) {
		push(@x,$left+($i*(($l*10)+$gap)));
	}

	return ($y,@x);
}



# ---------------------------------------------------------------------------------------------
# Create a list of months for the period selection list box
#
# Argument 1 : Start month, relative to this month (0=this month)
# Argument 2 : Number of months to be generated, starting from argument 1
#
# Return a hash keyed by month (yymm) with the full month and year as the value
# ---------------------------------------------------------------------------------------------
sub months_list {
	# Read arguments and initialise variables
	my($start,$months) = @_;
	my(%mths,@mmm,$yy,$mm,$yymm,$full);

	# List of months
	@mmm = ('January','February','March','April','May','June','July','August','September','October','November','December');

	# Establish the current month, then subtract the number of historic months
	$yy = int(formatDateTime('yy'));
	$mm = int(formatDateTime('mm'));
	$mm += $start;
	if($mm < 1) {
		$mm += 12;
		$yy--;
	}

	# Generate list of months
	for(my $i=0; $i<$months; $i++) {
		$yymm = substr('0'.$yy,-2,2).substr('0'.$mm,-2,2);
		$full = $mmm[$mm-1]." 20".substr('0'.$yy,-2,2);
		$mths{$yymm} = $full;
		$mm++;
		if($mm > 12) {
			$mm = 1;
			$yy++;
		}
	}

	# Return the hash of months
	return %mths;
}



# ---------------------------------------------------------------------------------------------
# Read a list of films for the selected provider from the Portal
#
# Argument 1 : Name of the provider
#
# Return a hash keyed by film name with the asset code as the value
# ---------------------------------------------------------------------------------------------
sub read_films {
	# Read argument and initialise local variables
	my($provider) = @_;
	my($status,$msg,%error);

	# If no provider has been selected by the user, return undef
	if(!$provider) { return; }

	# Return a hash keyed by film name
	($msg) = apiSelect('menuFilms',"provider=$provider");
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsg($LOG,$PROGRAM,"[$error{CODE}] $error{MESSAGE}");
		logMsg($LOG,$PROGRAM,"No '$provider' films returned from Portal");
		exit;
	}
	return apiData($msg);
}



# ---------------------------------------------------------------------------------------------
# Create a hash of hashes holding list values
# ---------------------------------------------------------------------------------------------
sub read_listvalues {
	my($status,$msg,%error,%data,$group,$item);

	# Read PIDs
	($msg) = apiSelect('menuListValues');
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsg($LOG,$PROGRAM,"[$error{CODE}] $error{MESSAGE}");
		logMsg($LOG,$PROGRAM,"No list values returned from Portal");
		exit;
	}
	%data = apiData($msg);

	# Create hash
	foreach my $id (keys %data) {
		$group = $data{$id}{type};
		$item = $data{$id}{value};
		$LISTVALUES{$group}{$item} = $id;
	}
}



# ---------------------------------------------------------------------------------------------
# Read a list of sites from the Portal
#
# Return a hash keyed by site name with the asset code as the value
# ---------------------------------------------------------------------------------------------
sub read_sites {
	my($status,$msg,%error);

	($msg) = apiSelect('menuSites');
	($status,%error) = apiStatus($msg);
	if(!$status) {
		logMsg($LOG,$PROGRAM,"[$error{CODE}] $error{MESSAGE}");
		logMsg($LOG,$PROGRAM,"No sites returned from Portal");
		exit;
	}
	return apiData($msg);
}



# ---------------------------------------------------------------------------------------------
# Update the file list with files for the selected batch
# Argument 1 : Name of control the list is bound to
# ---------------------------------------------------------------------------------------------
sub update_files {
	# Read the argument
	my($ctl,$batch) = @_;
	my($dir,$dh,@files);

	# Read list of films from the batch directory
	$dir = "$CONFIG{CS_DOWNLOAD}/$batch";
	if(!opendir($dh,$dir)) { print "Can't read directory [$dir]\n"; return; }
	@files = grep { !/^\./ } readdir($dh);
	closedir($dh);

	# Clear film list and reload
	tkListBoxAction($ctl,'delete');
	tkListBoxAction($ctl,'add',sort @files);
}



# ---------------------------------------------------------------------------------------------
# Update the film list with films for the selected provider
#
# Argument 1 : Name of control the list is bound to
# ---------------------------------------------------------------------------------------------
sub update_films {
	# Read the argument
	my($ctl,$provider) = @_;
	my(%films,@filmlist);

	# Read list of films from database depending on provider selected
	%films = read_films($provider);
	@filmlist = sort keys %films;

	# Clear film list and reload
	tkListBoxAction($ctl,'delete');
	tkListBoxAction($ctl,'add',@filmlist);
}



# ---------------------------------------------------------------------------------------------
# Show the log file
#
# Argument 1 : Title of dialog
# Argument 2 : Name of log file
# Argument 3 : Path to log file (optional, uses $CONFIG{LOGDIR} by default)
# ---------------------------------------------------------------------------------------------
sub view_log {
	my($title,$file,$path) = @_;
	my($log,$fh,$line);

	# Set up path to log file
	if(!$path) { $path = $CONFIG{LOGDIR}; }

	# Check that the log file exists
	$log = "$path/$file";
	if(!-f $log) {
		tkOption('Airwave','View Log',"Can't read log file [$title]",'OK');
		return;
	}

	# Open a dialog to show the log file
	tkDialogOpen('Airwave','log',100,100,850,500,$title);
	tkViewer('log','logfile',130,40);

	# Read the log file and add the records
	open($fh,"<$log");
	while($line = readline($fh)) {
		tkViewerAdd('logfile',$line);
	}
	close($fh);

	# Set window to the end of the text to see the newest events immediately
	tkViewerSee('logfile','end');
}





# *********************************************************************************************
# *********************************************************************************************
#
# Run on PREPARATION Server
#
# *********************************************************************************************
# *********************************************************************************************

# ---------------------------------------------------------------------------------------------
# Display the film ingestion parameters form and run the command
#
# Argument 1 : 'ask' will display the parameters form, undef will run the command
# ---------------------------------------------------------------------------------------------
sub ingest_film {
	my($action) = @_;
	my(%films,@filmlist,$asset,$prov,$filmname,$test,$dir,$dh,@files,@types,@qualities,$file,$type,$quality);
	my $x2 = $TOPLEFT{x}+$TOPLEFT{xinc};
	my $y = $TOPLEFT{y};

	# Read list of films from database for the default content provider
	%films = read_films($PROVIDER[0]);
	@filmlist = sort keys %films;

	# Display the parameters dialog
	if($action eq 'ask') {
		# Create the dialog box
		tkDialogOpen('Airwave','ingest_film',100,300,550,430,'Ingest a Film into the Content Server');

		# Read the films that can be ingested
		$dir = $CONFIG{CS_DOWNLOAD};
		if(!opendir($dh,$dir)) { print "Can't read directory [$dir]\n"; return; }
		@files = grep { !/^\./ } sort readdir($dh);
		closedir($dh);

		# Show list of files that can be ingested
		$y += $TOPLEFT{yinc};
		tkLabel('ingest_film',$TOPLEFT{x},$y,'File');
		tkDropdown('ingest_film','di_file',$x2,$y,50,'',@files);

		# Asset type
		foreach my $value (sort keys %{$LISTVALUES{'Asset Type'}}) {
			push(@types,$value);
		}
		$y += $TOPLEFT{yinc};
		tkLabel('ingest_film',$TOPLEFT{x},$y,'Asset Type');
		tkDropdown('ingest_film','di_type',$x2,$y,15,'',@types);

		# Asset quality
		foreach my $value (sort keys %{$LISTVALUES{'Content Quality'}}) {
			push(@qualities,$value);
		}
		$y += $TOPLEFT{yinc};
		tkLabel('ingest_film',$TOPLEFT{x},$y,'Asset Quality');
		tkDropdown('ingest_film','di_quality',$x2,$y,15,'',@qualities);

		# List of content providers
		$y += $TOPLEFT{yinc};
		tkLabel('ingest_film',$TOPLEFT{x},$y,'Provider');
		tkDropdown('ingest_film','di_provider',$x2,$y,15,'update_films(di_filmlist)',@PROVIDER);

		# List of films from the content provider (empty to start with)
		$y += $TOPLEFT{yinc};
		tkLabel('ingest_film',$TOPLEFT{x},$y,'Films');
		tkDropdown('ingest_film','di_filmlist',$x2,$y,50,'',@filmlist);

		# Check box to ask whether to run in test mode
		$y += $TOPLEFT{yinc};
		tkLabel('ingest_film',$TOPLEFT{x},$y,'Test Ingestion?');
		tkCheckBox('ingest_film','di_test',$x2,$y);

		# OK and Cancel buttons
		my($y,$b1x,$b2x) = button_coords(500,430,2,8);
		tkButton('ingest_film',$b1x,$y,8,'OK','ingest_film');
		tkButton('ingest_film',$b2x,$y,8,'Cancel');
	}
	# Run the film ingestion script
	else {
		$file = tkDropdownAction('di_file','value');
		if($file =~ m/ /) {
			tkOption('ingest_film','Film Ingestion','The film file name must not contain any spaces','OK');
			return;
		}

		# Read the asset type and quality
		$type = tkDropdownAction('di_type','value');
		$quality = tkDropdownAction('di_quality','value');

		# Read the content provider selected by the user
		$prov = tkDropdownAction('di_provider','value');

		# Read the film selected by the user
		$filmname = tkDropdownAction('di_filmlist','value');

		# Read the asset code of the selected film
		%films = read_films($prov);
		$asset = $films{$filmname}{asset_code};
		if(!$asset) {
			tkOption('ingest_film','Film Ingestion','The selected film does not have an asset code','OK');
			return;
		}

		# Read the test flag
		$test = (tkCheckBoxValue('di_test')) ? '-test' : '';

		# Run the ingestion
		system("$ENV{'AIRWAVE_ROOT'}/ingest_film.pl -asset=$asset -file=$file -type=$type -quality=$quality $test -log");

		# Close the parameter dialog
		tkClose('ingest_film');

		# Show log file
		view_log('Film Ingestion Log','ingest_film.log');
	}
}



# ---------------------------------------------------------------------------------------------
# Display the parameters form for loading a USB disk with films, then run the command
#
# Argument 1 : 'ask' will display the parameters form, undef will run the command
# ---------------------------------------------------------------------------------------------
sub load_disk {
	my($action) = @_;
	my(%sites,$dh,@dirfiles,@files,$site,$dest,$todo,$args);
	my $x2 = $TOPLEFT{x}+$TOPLEFT{xinc}+20;
	my $y = $TOPLEFT{y};
	my $master = '/media';

	# Read the list of sites
	%sites = read_sites();

	# Display the parameters dialog
	if($action eq 'ask') {
		# Create the dialog box
		tkDialogOpen('Airwave','load_disk',100,300,560,320,"Load a USB Disk with Films");

		# List of sites
		tkLabel('load_disk',$TOPLEFT{x},$y,'Select a Site');
		tkDropdown('load_disk','ld_site',$x2,$y,50,'',sort keys %sites);

		# Read the list of devices attached to the computer
		if(!opendir($dh,$master)) {
			tkOption('Airwave','Load Disk',"Can't read directory [$master]",'OK');
			return;
		}
		@dirfiles = readdir($dh);
		push(@files,grep { !/^\./ } sort @dirfiles);
		closedir($dh);
		if(!@files) { push(@files,'No storage devices present'); }

		# Target drive
		$y += $TOPLEFT{yinc};
		tkLabel('load_disk',$TOPLEFT{x},$y,'Target Drive');
		tkDropdown('load_disk','ld_target',$x2,$y,50,'',@files);

		# Copy or list the data
		$y += $TOPLEFT{yinc};
		tkRadioButton('load_disk','ld_todo',$x2,$y,'Show','Copy');

		# Check box to ask whether to ingest or not
		$y += 2*$TOPLEFT{yinc};
		tkLabel('load_disk',$TOPLEFT{x},$y,'Load Film?');
		tkCheckBox('load_disk','ld_film',$x2,$y);

		# Check box to ask whether to ingest or not
		$y += $TOPLEFT{yinc};
		tkLabel('load_disk',$TOPLEFT{x},$y,'Load Trailer?');
		tkCheckBox('load_disk','ld_trlr',$x2,$y);

		# Check box to ask whether to ingest or not
		$y += $TOPLEFT{yinc};
		tkLabel('load_disk',$TOPLEFT{x},$y,'Load Meta-Data?');
		tkCheckBox('load_disk','ld_meta',$x2,$y);

		# OK and Cancel buttons
		my($y,$b1x,$b2x) = button_coords(560,320,2,8);
		tkButton('load_disk',$b1x,$y,8,'OK','load_disk');
		tkButton('load_disk',$b2x,$y,8,'Cancel');
	}
	# Run the command
	else {
		# Read the parameters
		$site = tkDropdownAction('ld_site','value');
		$site = $sites{$site}{site_code};
		$args = "-site=$site";
		$todo = (tkRadioButtonValue('ld_todo') eq 'Copy') ? 'copy' : 'show';
		$args .= " -$todo";
		$args .= (tkCheckBoxValue('ld_film')) ? ' -f' : '';
		$args .= (tkCheckBoxValue('ld_trlr')) ? ' -t' : '';
		$args .= (tkCheckBoxValue('ld_meta')) ? ' -m' : '';
		$args .= " -log";

		# Target directory must be entered if 'copy' is selected
		if($todo eq 'copy') {
			$dest = tkDropdownAction('ld_target','value');
			if($dest) {
				$args .= " -tgt=$master/$dest";
			}
			else {
				tkOption('load_disk','Load Disk Error',"Target directory must be entered if 'copy' is selected",'OK');
				return;
			}
		}

		# Run the script
		system("$ENV{'AIRWAVE_ROOT'}/load_disk.pl $args");

		# Close the parameter dialog
		tkClose('load_disk');

		# Show log file
		view_log("Log for Load a USB Disk with Films",'load_disk.log');
	}
}





# *********************************************************************************************
# *********************************************************************************************
#
# Run on DISTRIBUTION Server
#
# *********************************************************************************************
# *********************************************************************************************

# ---------------------------------------------------------------------------------------------
# Start the CDS daemon processes
# ---------------------------------------------------------------------------------------------
sub cds_start {
	system("$ENV{'AIRWAVE_ROOT'}/cdsd start");
	view_log("Log for the CDS Daemon processes",'cdsd.log');
}



# ---------------------------------------------------------------------------------------------
# Status of the CDS daemon processes
# ---------------------------------------------------------------------------------------------
sub cds_status {
	system("$ENV{'AIRWAVE_ROOT'}/cdsd status");
	view_log("Log for the CDS Daemon processes",'cdsd.log');
}



# ---------------------------------------------------------------------------------------------
# Stop the CDS daemon processes
# ---------------------------------------------------------------------------------------------
sub cds_stop {
	system("$ENV{'AIRWAVE_ROOT'}/cdsd stop");
	view_log("Log for the CDS Daemon processes",'cdsd.log');
}
