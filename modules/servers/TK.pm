#!/usr/bin/perl
# ***************************************************************************
# ***************************************************************************
#
# Breato Tk functions
#
# ***************************************************************************
# ***************************************************************************

# Declare the package name and export the function names
use strict;
use warnings;

# System modules
use Tk;
use Tk::BrowseEntry;
use Tk::Dialog;
use Tk::DialogBox;
use Tk::Font;
use Tk::HList;
use Tk::Radiobutton;
use Tk::ROText;
use Tk::StatusBar;

# Declare the package name and export the function names
package mods::TK;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(tkAppOpen tkButton tkCheckBox tkCheckBoxValue tkClose tkDialogOpen 
				 tkDropdown tkDropdownAction tkEntry tkEntryValue tkGrid tkGridDefaultRow 
				 tkGridDelete tkGridInsert tkLabel tkListBox tkListBoxAction tkMain 
				 tkMenu tkMenuBar tkMenuOption tkMenuSeparator tkOption tkRadioButton 
				 tkRadioButtonValue tkStatus tkViewer tkViewerAdd tkViewerSee);

# Initialise variables used by the module
our(%TK_REFS,%TK_VALUES,@TK_GRID,%FONT);

# Determine the server the application is running on
our $SERVER = `hostname`;
chomp $SERVER;

# Set default font
$FONT{name} = 'Ubuntu';
$FONT{size} = 8;

1;





# ---------------------------------------------------------------------------------------------
# Open the main application window
# If there is only one argument, open the window maximized
# Argument 1 : Name of application window
# Argument 2 : Title of application window
# Argument 3 : X coordinate of the top left corner (optional)
# Argument 4 : Y coordinate of the top left corner (optional)
# Argument 5 : Width of window (optional)
# Argument 6 : Height of window (optional)
# ---------------------------------------------------------------------------------------------
sub tkAppOpen {
	my($name,$title,$x,$y,$width,$height) = @_;
	my($font,$status,$label);
	
	# Create main window
	$TK_REFS{$name} = MainWindow->new(-title => $title);
	
	# Create and apply new system font
	$font = $TK_REFS{$name}->fontCreate('standard', -family=>$FONT{name}, -size=>$FONT{size});
	$TK_REFS{$name}->optionAdd('*font',$font);
	
	# If co-ordinates passed in, use them
	if($x) {
		$TK_REFS{$name}->geometry($width."x".$height."+".$x."+".$y);
	}
	else {
		$TK_REFS{$name}->geometry($TK_REFS{$name}->screenwidth.'x'.$TK_REFS{$name}->screenheight.'+0+0');
	}
	
	# Create menu and status bars
	tkMenuBar($name);
	$status = $TK_REFS{$name}->StatusBar();
	$label = $status->addLabel(
				-relief	=> 'flat',
				-text	=> ' ');
	$TK_REFS{'StatusBar'} = $label;
}



# ---------------------------------------------------------------------------------------------
# Add a button to the parent control
# Argument 1 : Name of parent control
# ---------------------------------------------------------------------------------------------
sub tkButton {
	my($parent,$x,$y,$width,$name,$cmd) = @_;
	my($ref,$ctl);
	$cmd = ($cmd) ? $cmd : "tkClose";
	$cmd = "main::$cmd";
	$ref = \&$cmd;
	$ctl = $TK_REFS{$parent}->Button(
					-text    => $name,
					-width   => $width,
					-command => sub { $ref->($parent); } );
	$ctl->place(-x => $x, -y => $y);
}



# ---------------------------------------------------------------------------------------------
# Add a check box to the parent control
# Argument 1 : Name of parent control
# Argument 2 : Name of the check box
# ---------------------------------------------------------------------------------------------
sub tkCheckBox {
	my($parent,$self,$x,$y,$default) = @_;
	my($ctl);
	
	# Default value
	$TK_VALUES{$self} = ($default) ? $default : 0;
	
	$ctl = $TK_REFS{$parent}->Checkbutton(
					-offvalue	=> 0,
					-onvalue	=> 1,
					-variable	=> \$TK_VALUES{$self})
					->pack;
	$ctl->place(-x => $x, -y => $y);
	$TK_REFS{$self} = $ctl;
}



# ---------------------------------------------------------------------------------------------
# Return the value in a check box control
# Argument 1 : Name of the check box control
# ---------------------------------------------------------------------------------------------
sub tkCheckBoxValue {
	my($self) = @_;
	return $TK_VALUES{$self};
}



# ---------------------------------------------------------------------------------------------
# Close a TK contral
# Argument 1 : Name of the control
# ---------------------------------------------------------------------------------------------
sub tkClose {
	my($self) = @_;
	if($TK_REFS{$self}) {
		$TK_REFS{$self}->destroy;
	}
}



# ---------------------------------------------------------------------------------------------
# Open a dialog box onto which other controls will be added
# Argument 1 : Name of parent control
# Argument 2 : Name of the dialog
# ---------------------------------------------------------------------------------------------
sub tkDialogOpen {
	my($parent,$self,$x,$y,$width,$height,$title) = @_;
	$TK_REFS{$self} = $TK_REFS{$parent}->Toplevel(-title  => $title);
	$TK_REFS{$self}->geometry($width."x".$height."+".$x."+".$y);
}



# ---------------------------------------------------------------------------------------------
# Add a drop down list to the parent control
# Argument 1 : Name of parent control
# Argument 2 : Name of the drop down list control
# ---------------------------------------------------------------------------------------------
sub tkDropdown {
	# Read arguments and initialise local variables
	my($parent,$self,$x,$y,$width,$command,@items) = @_;
	my($cmd,@args,$ref,$ctl);
	
	# Default value is the first item in the list
	$TK_VALUES{$self} = $items[0];
	
	if($command) {
		# Extract command and arguments
		# Remove trailing bracket, replace first bracket with comma, split on commas
		$command =~ s/\)//;
		$command =~ s/\(/,/;
		($cmd,@args) = split(/,/,$command);
		$cmd = "main::$cmd";
		$ref = \&$cmd;
		
		# Create dropdown list with command
		$ctl = $TK_REFS{$parent}->BrowseEntry(
						-browsecmd		=> sub { $ref->(@args,$TK_VALUES{$self}); },
						-state			=> 'readonly',
						-variable		=> \$TK_VALUES{$self},
						-width			=> $width)
						->pack;
	}
	else {
		# Create dropdown list without command
		$ctl = $TK_REFS{$parent}->BrowseEntry(
						-variable		=> \$TK_VALUES{$self},
						-state			=> 'readonly',
						-width			=> $width)
						->pack;
	}
	$ctl->place(-x => $x, -y => $y);
	
	# Populate dropdown with values
	foreach my $item (@items) {
		$ctl->insert('end',$item);
	}
	$TK_REFS{$self} = $ctl;
}



# ---------------------------------------------------------------------------------------------
# Return the value in a list box control
# Argument 1 : Name of the list box control
# Argument 2 : Action to be performed (add/delete/set/value)
# Argument 3 : List of values (for 'add' and 'set' only)
# ---------------------------------------------------------------------------------------------
sub tkDropdownAction {
	my($self,$action,@data) = @_;
	
	# Add new values to the list
	if($action eq 'add') {
		foreach my $item (@data) {
			$TK_REFS{$self}->insert('end',$item);
		}
	}
	# Remove all values from the list
	elsif($action eq 'delete') {
		$TK_REFS{$self}->delete(0,'end');
	}
	# Set the selected value
	elsif($action eq 'set') {
		$TK_VALUES{$self} = $data[0];
	}
	# Return the currently selected value
	elsif($action eq 'value') {
		return $TK_VALUES{$self};
	}
}



# ---------------------------------------------------------------------------------------------
# Add a text input to the parent control
# Argument 1 : Name of parent control
# Argument 2 : Name of the text input control
# ---------------------------------------------------------------------------------------------
sub tkEntry {
	my($parent,$self,$x,$y,$width) = @_;
	my($ctl);
	$ctl = $TK_REFS{$parent}->Entry(-width => $width);
	$ctl->place(-x => $x, -y => $y);
	$TK_REFS{$self} = $ctl;
}



# ---------------------------------------------------------------------------------------------
# Return the value in a text input control
# Argument 1 : Name of the text input control
# ---------------------------------------------------------------------------------------------
sub tkEntryValue {
	my($self) = @_;
	return $TK_REFS{$self}->get;
}



# ---------------------------------------------------------------------------------------------
# Add a grid to the parent control
# Argument 1 : Name of parent control
# Argument 2 : Name of the grid control
# Argument 3 : Column holding the unique key
# ---------------------------------------------------------------------------------------------
sub tkGrid {
	my($parent,$self,$id,$x,$y,$width,$height,$bars,@heading) = @_;
	my($cols,$ctl);
	$cols = scalar(@heading);
	$ctl = $TK_REFS{$parent}->Scrolled(
		'HList',
		-head       => 1,
		-columns    => $cols,
		-scrollbars => $bars,
		-width      => $width,
		-height     => $height,
		-background => 'white',)
		->pack;
	$ctl->place(-x => $x, -y => $y);
	$TK_REFS{$self} = $ctl;
	
	# Populate the heading
	for(my $i=0; $i<@heading; $i++) {
		$ctl->header(
				'create',
				$i,
				-text             => $heading[$i],
				-headerbackground => 'gray');
	}
}



# ---------------------------------------------------------------------------------------------
# Set the default row in a grid control
# Argument 1 : Name of the grid control
# Argument 2 : Row number (starts at 0)
# ---------------------------------------------------------------------------------------------
sub tkGridDefaultRow {
	my($self,$id) = @_;
	$TK_REFS{$self}->selectionSet($TK_GRID[1]->[$id+1]);
}



# ---------------------------------------------------------------------------------------------
# Delete a row from a grid control
# Argument 1 : Name of the grid control
# Argument 2 : 'all'
# ---------------------------------------------------------------------------------------------
sub tkGridDelete {
	my($self,$action) = @_;
	if($TK_REFS{$self}) {
		$TK_REFS{$self}->delete('all');
	}
}



# ---------------------------------------------------------------------------------------------
# Add a row to a grid control
# Argument 1  : Name of the grid control
# Argument 2  : Column that is holds the unique key (starts at 0)
# Argument 3+ : Array of values
# ---------------------------------------------------------------------------------------------
sub tkGridInsert {
	my($self,$id,@data) = @_;
	my($key);
	$key = $data[$id];
	$TK_REFS{$self}->add($key);
	for(my $i=0; $i<@data; $i++) {
		$TK_REFS{$self}->itemCreate(
					$key,
					$i,
					-text => $data[$i]);
	}
}



# ---------------------------------------------------------------------------------------------
# Add a text label to the parent control
# Argument 1 : Name of parent control
# ---------------------------------------------------------------------------------------------
sub tkLabel {
	my($parent,$x,$y,$text,$width,$height,$anchor,$justify) = @_;
	my($ctl);
	$width = ($width) ? $width : 20;
	$height = ($height) ? $height : 1;
	$anchor = ($anchor) ? $anchor : 'nw';
	$justify = ($justify) ? $justify : 'left';

	$ctl = $TK_REFS{$parent}->Label(
					-width   => $width,
					-height  => $height,
					-anchor  => $anchor,
					-justify => $justify,
					-text    => $text);
	$ctl->place(-x => $x, -y => $y);
}



# ---------------------------------------------------------------------------------------------
# Add a list box to the parent control
# Argument 1 : Name of parent control
# Argument 2 : Name of the list box control
# ---------------------------------------------------------------------------------------------
sub tkListBox {
	my($parent,$self,$x,$y,$height,$width,$type,@items) = @_;
	my($frame,$list,$scroll,@data);
	
	# Create a frame to hold the list and scrollbar
	$frame = $TK_REFS{$parent}->Frame(
				 -height 	=> $height,
				 -width		=> $width);
	$frame->pack(-side		=> 'top',
				 -anchor	=> 'n',
				 -expand	=> 'yes');
	$frame->place(-x => $x, -y => $y);
	
	# Create the scrollbar
	$scroll = $frame->Scrollbar;
	$scroll->pack(-side	=> 'right',
				  -fill	=> 'y');
	
	# Create the list
	$list = $frame->Listbox(
					-selectmode 		=> 'extended',
					-yscrollcommand		=> ['set', $scroll],
					-height 			=> $height,
					-width				=> $width);
	$list->pack(-side	=> 'left',
				-expand	=> 'yes',
				-fill	=> 'y');
	
	# Link the scrollbar to the list
	$scroll->configure(-command=>['yview', $list]);
	
	# Load the list
	foreach my $item (@items) {
		$list->insert('end',$item);
	}
	
	# Register the list so it can have values inserted and deleted later
	$TK_REFS{$self} = $list;
}



# ---------------------------------------------------------------------------------------------
# Return the value in a list box control
# Argument 1 : Name of the list box control
# Argument 2 : Action to be performed (add/delete/value)
# Argument 3 : List of values (for 'add' only)
# ---------------------------------------------------------------------------------------------
sub tkListBoxAction {
	my($self,$action,@data) = @_;
	
	# Add new values to the list
	if($action eq 'add') {
		foreach my $item (@data) {
			$TK_REFS{$self}->insert('end',$item);
		}
	}
	# Remove all values from the list
	elsif($action eq 'delete') {
		$TK_REFS{$self}->delete(0,'end');
	}
	# Return the currently selected value
	elsif($action eq 'value') {
		@data = $TK_REFS{$self}->curselection;
		if(@data) { return @data; }
		else { return -1; }
	}
}



# ---------------------------------------------------------------------------------------------
# Start processing the Tk commands
# ---------------------------------------------------------------------------------------------
sub tkMain {
	Tk::MainLoop();
}



# ---------------------------------------------------------------------------------------------
# Create a menu on the menu bar
# Argument 1 : Name of the menu
# Argument 2 : Index of menu name to be set as the accelerator key
# ---------------------------------------------------------------------------------------------
sub tkMenu {
	my($name,$key) = @_;
	$key = ($key) ? $key : 0;
	my $ctl = $TK_REFS{menubar}->Menubutton(
					-text		=> $name,
					-underline	=> $key,
					-tearoff	=> 0)
					->pack(-side => "left");
	$TK_REFS{$name} = $ctl;
}



# ---------------------------------------------------------------------------------------------
# Create a horizontal space at the top of the window for the menu bar
# Argument 1 : Name of application window
# ---------------------------------------------------------------------------------------------
sub tkMenuBar {
	my($parent) = @_;
	my $ctl = $TK_REFS{$parent}->Frame(
					-relief			=> "raised",
					-borderwidth	=> 2)
					->pack(-anchor	=> "nw",
						   -fill	=> "x");
	$TK_REFS{menubar} = $ctl;
}



# ---------------------------------------------------------------------------------------------
# Create an option on the menu
# Argument 1  : Name of the menu
# Argument 2  : Name of the option
# Argument 3  : Command to be run on selection
# Argument 4+ : Argument(s) to the command
# ---------------------------------------------------------------------------------------------
sub tkMenuOption {
	my($menu,$name,$cmd,@args) = @_;
	$cmd = "main::$cmd";
	my $ref = \&$cmd;
	$TK_REFS{$menu}->command(
					-label => $name,
					-command => sub { $ref->(@args); } );
}



# ---------------------------------------------------------------------------------------------
# Create a separator line on the menu
# Argument 1 : Name of the menu
# ---------------------------------------------------------------------------------------------
sub tkMenuSeparator {
	my($menu) = @_;
	$TK_REFS{$menu}->separator;
}



# ---------------------------------------------------------------------------------------------
# Display a dialog that presents several buttons
# Argument 1 : Name of parent control
# Argument 2 : Title of the dialog
# Argument 3 : Text to be displayed in the dialog
# Argument 4 : Buttons to be shown in the dialog
# Return the name of the button pressed
# ---------------------------------------------------------------------------------------------
sub tkOption {
	my($parent,$title,$text,@buttons) = @_;
	my $ctl = $TK_REFS{$parent}->Dialog(
					-title			=> $title,
					-text			=> $text,
					-default_button => $buttons[0],
					-buttons		=> [@buttons]);
	return $ctl->Show;
}



# ---------------------------------------------------------------------------------------------
# Add a set of radio buttons to the parent control
# Argument 1  : Name of parent control
# Argument 2  : Name of the group of radio buttons
# Argument 5+ : Names of the radio buttons
# ---------------------------------------------------------------------------------------------
sub tkRadioButton {
	my($parent,$self,$x,$y,@names) = @_;
	my($ctl);
	$TK_VALUES{$self} = $names[0];
	foreach my $name (@names) {
		$ctl = $TK_REFS{$parent}->Radiobutton(-text			=> $name,
											  -value		=> $name,
											  -variable		=> \$TK_VALUES{$self})
											  ->pack(-side	=> 'left');
		$ctl->place(-x => $x, -y => $y);
		$y += 20;
	}
}



# ---------------------------------------------------------------------------------------------
# Return the selected value of a group of radio buttons
# Argument 1 : Name of the group of radio buttons
# ---------------------------------------------------------------------------------------------
sub tkRadioButtonValue {
	my($self) = @_;
	return $TK_VALUES{$self};
}



# ---------------------------------------------------------------------------------------------
# Display a message on the status bar of the main application window
# Argument 1 : Text to be displayed in the status bar
# ---------------------------------------------------------------------------------------------
sub tkStatus {
	my($text) = @_;
	$TK_REFS{'StatusBar'}->configure(-text => $text);
	$TK_REFS{'StatusBar'}->update;
}



# ---------------------------------------------------------------------------------------------
# Display a scrollable control to allow a user to browse text
# Argument 1 : Name of parent control
# Argument 2 : Name of the scrollable control
# ---------------------------------------------------------------------------------------------
sub tkViewer {
	my($parent,$self,$width,$height) = @_;
	my($ctl);
	$ctl = $TK_REFS{$parent}->Scrolled(
					'ROText',
					-scrollbars	=> 'se',
					-width		=> $width,
					-height		=> $height,
					-wrap		=> 'none')
					->pack(-side => 'left', -padx => 10);
	$TK_REFS{$self} = $ctl;
}



# ---------------------------------------------------------------------------------------------
# Add records to a scrollable control
# Argument 1 : Name of the scrollable control
# Argument 2 : Line of text to be added to the control
# ---------------------------------------------------------------------------------------------
sub tkViewerAdd {
	my($self,$line) = @_;
	$TK_REFS{$self}->insert('end',$line);
}



# ---------------------------------------------------------------------------------------------
# Set to pointer within the scrollable control
# Argument 1 : Name of the scrollable control
# Argument 2 : Position of the pointer (end/..........)
# ---------------------------------------------------------------------------------------------
sub tkViewerSee {
	my($self,$place) = @_;
	$TK_REFS{$self}->see($place);
}



