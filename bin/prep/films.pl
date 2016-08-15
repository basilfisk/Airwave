#!/usr/bin/perl
# ***************************************************************************
# ***************************************************************************
#
#  Display a set of pages that show the meta-data and images for all films
#  on the attached content drive.  The films and trailers can be played.
#
# ***************************************************************************
# ***************************************************************************

# Declare modules
use strict;
use warnings;

# System modules
use XML::LibXML;
use Gtk2 '-init';
use Getopt::Long;

# Breato modules
use Airwave::Common qw(formatDateTime logMsgPortal readConfig);

# Initialise constants
use constant TRUE  => 1;
use constant FALSE => 0;

# Program information
our $PROGRAM = "films.pl";
our $VERSION = "2.0";

# Check there are any arguments
if($#ARGV == -1) { usage(); }

# Read command line options
our $CLASS    = 'empty';
our $LOG	  = 0;
GetOptions (
	'class=s'    => \$CLASS,
	'log'		 => \$LOG,
	'help'       => sub { usage(); } );

# Read the configuration parameters
our %CONFIG  = readConfig("$ENV{'AIRWAVE_ROOT'}/etc/airwave.conf");

# Declare and initialise global variables
our($FILM_ROOT,@FILMS,%STREAMS);

# Check that the content type argument is present
if($CLASS eq 'empty') { usage(1); }

# Check validity of 'class' argument
if($CLASS ne 'uip' && $CLASS ne 'pbtv' && $CLASS ne 'bbc' && $CLASS ne 'disney') { usage(2); }

$CLASS =~ tr[a-z][A-Z];
$FILM_ROOT = "$CONFIG{CS_ROOT}/$CLASS";

# Check that the content directory exists
if(!-d $FILM_ROOT) { usage(3); }

# Load the data from XML metadata files then show the UI
load_data();
show_films();





# ---------------------------------------------------------------------------------------------
# Load the film data from the meta-data file into a global array of arrays
# ---------------------------------------------------------------------------------------------
sub load_data {
	# Initialise local variables
	my($dh,@files,$psr,$doc,$xpc,@temp,@nodes,$node,$tmp);

	# Read the information from the metadata files in cache
	opendir($dh,$FILM_ROOT);
	@files = sort grep { $_ ne '.' and $_ ne '..' } readdir($dh);
	foreach my $file (@files) {
		if(-e "$FILM_ROOT/$file/$file.xml") {
			# Open and parse the XML metadata file
			$psr = XML::LibXML->new();
			$doc = $psr->parse_file("$FILM_ROOT/$file/$file.xml");
			$xpc = XML::LibXML::XPathContext->new($doc);

			# Read the synopsis information for the film
			@temp = ();
			# [0] Asset code
			@nodes = $xpc->findnodes("/metadata");
			$temp[0] = $nodes[0]->getAttribute("id");
			# [1] Film title
			@nodes = $xpc->findnodes("/metadata/languages/language[\@id='en']/title");
			$temp[1] = (@nodes) ? $nodes[0]->textContent : undef;
			# [2] Strapline
			@nodes = $xpc->findnodes("/metadata/languages/language[\@id='en']/short");
			$temp[2] = (@nodes) ? $nodes[0]->textContent : undef;
			# [3] Synopsis
			@nodes = $xpc->findnodes("/metadata/languages/language[\@id='en']/full");
			$temp[3] = (@nodes) ? $nodes[0]->textContent : undef;
			# [4] Credits
			@nodes = $xpc->findnodes("/metadata/languages/language[\@id='en']/credits/item");
			$tmp = "";
			foreach my $node (@nodes) {
				$tmp .= ($node->textContent)."\n";
			}
			$temp[4] = substr($tmp,0,-1);
			# [5] Certificate
			@nodes = $xpc->findnodes("/metadata/certificate");
			$temp[5] = (@nodes) ? $nodes[0]->textContent : undef;
			# [6] Release date
			@nodes = $xpc->findnodes("/metadata/release");
			$temp[6] = (@nodes) ? $nodes[0]->textContent : undef;
			# [7] Running time
			@nodes = $xpc->findnodes("/metadata/duration");
			$temp[7] = (@nodes) ? ($nodes[0]->textContent)." Minutes" : undef;
			# [8] IMDB ref
			@nodes = $xpc->findnodes("/metadata/imdb");
			$temp[8] = (@nodes) ? $nodes[0]->textContent : undef;
			# [9] Provider
			@nodes = $xpc->findnodes("/metadata/provider/name");
			$temp[9] = (@nodes) ? $nodes[0]->textContent : undef;
			# [10] Provider ref
			@nodes = $xpc->findnodes("/metadata/provider/reference");
			$temp[10] = (@nodes) ? $nodes[0]->textContent : undef;
			# [11] Licence territory
			@nodes = $xpc->findnodes("/metadata/licences/licence");
			$temp[11] = (@nodes) ? $nodes[0]->getAttribute("territory") : undef;
			# [12] Licence start
			@nodes = $xpc->findnodes("/metadata/licences/licence/start");
			$temp[12] = (@nodes) ? $nodes[0]->textContent : undef;
			# [13] Licence end
			@nodes = $xpc->findnodes("/metadata/licences/licence/end");
			$temp[13] = (@nodes) ? $nodes[0]->textContent : undef;
			# [14] Language
			@nodes = $xpc->findnodes("/metadata/languages/language");
			$temp[14] = (@nodes) ? $nodes[0]->getAttribute("id") : undef;
			# [15] Genre
			@nodes = $xpc->findnodes("/metadata/genres/genre");
			$tmp = "";
			foreach my $node (@nodes) {
				$tmp .= ($node->textContent)."\n";
			}
			$temp[15] = substr($tmp,0,-1);

			# [20+] Trailer file
			@nodes = $xpc->findnodes("/metadata/assets/asset[\@class='trailer']");
			foreach my $node (@nodes) {
				$temp[20] = $node->getAttribute("name");
				$temp[21] = $node->getAttribute("class");
				$temp[22] = $node->getAttribute("coding");
				$temp[23] = $node->getAttribute("type");
				$temp[24] = ($temp[23] eq 'transport') ? $node->getAttribute("program") : undef;
				$temp[25] = ($temp[23] eq 'transport') ? $node->getAttribute("streams") : undef;
				# Read the stream data for the film
				read_stream($node,$temp[0],$temp[21],$temp[23]);
			}

			# [30+] Film file
			@nodes = $xpc->findnodes("/metadata/assets/asset[\@class='film']");
			foreach my $node (@nodes) {
				$temp[30] = $node->getAttribute("name");
				$temp[31] = $node->getAttribute("class");
				$temp[32] = $node->getAttribute("coding");
				$temp[33] = $node->getAttribute("type");
				$temp[34] = ($temp[33] eq 'transport') ? $node->getAttribute("program") : undef;
				$temp[35] = ($temp[33] eq 'transport') ? $node->getAttribute("streams") : undef;
				# Read the stream data for the film
				read_stream($node,$temp[0],$temp[31],$temp[33]);
			}

			# Add film to the array of films
			push(@FILMS,[@temp]);
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Play a trailer or film in full screen mode
# Argument 1 : Address of media to be played
# Argument 2 : Type of stream (transport/program)
# Argument 3 : Video PID
# Argument 4 : Audio PID
# ---------------------------------------------------------------------------------------------
sub play_media {
	my($asset,$type,$video,$audio) = @_;

	# TEMPORARY FUDGE
	if($CLASS eq 'UIP' || $CLASS eq 'BBC') {
		$video = 33;
		$audio = 36;
	}
	else {
		$video = 4130;
		$audio = 4131;
	}

	# Play a transport stream asset
	if($type eq 'transport') {
		system("mplayer -fs -vid $video -aid $audio $asset");
	}
	# Play a programme stream asset
	else {
		system("mplayer -fs $asset");
	}
}



# ---------------------------------------------------------------------------------------------
# Read the stream data for a media asset
# Argument 1 : Asset node pointer
# Argument 2 : Asset code
# Argument 3 : Asset class (film/trailer)
# Argument 4 : Asset encoding mechanism (transport/program)
# ---------------------------------------------------------------------------------------------
sub read_stream {
	# Read arguments and initialise variables
	my($node,$code,$class,$type) = @_;
	my(@streams,@aoa,@strm);
	my $idx = "$code-$class";

	# Record details of each stream within the asset
	@streams = $node->findnodes("stream");
	foreach my $stream (@streams) {
		@strm = ();
		$strm[0] = $stream->getAttribute("coding");
		$strm[1] = $stream->getAttribute("type");
		if($type eq 'transport') {
			$strm[2] = $stream->getAttribute("pid");
		}
		if($strm[1] eq 'video') {
			$strm[3] = ($stream->findnodes("frame_size"))[0]->textContent;
			$strm[4] = ($stream->findnodes("aspect_ratio"))[0]->textContent;
			$strm[5] = ($stream->findnodes("frame_rate"))[0]->textContent;
			$strm[6] = ($stream->findnodes("encode_rate"))[0]->textContent;
		}
		if($strm[1] eq 'audio') {
			$strm[3] = ($stream->findnodes("sample_rate"))[0]->textContent;
			$strm[4] = ($stream->findnodes("channels"))[0]->textContent;
			$strm[5] = ($stream->findnodes("encode_rate"))[0]->textContent;
			$strm[6] = ($stream->findnodes("language"))[0]->textContent;
		}

		# Build up an array of arrays of streams
		push(@aoa,[@strm]);
	}

	# Add the stream array to the hash of arrays
	$STREAMS{$idx} = [@aoa];
}



# ---------------------------------------------------------------------------------------------
# Display the UI that allows trailers and films to be played
# ---------------------------------------------------------------------------------------------
sub show_films {
	# Initialise local variables
	my($window,$table,$vbox,$ref,$image);
	my $count = 1;
	my $max = @FILMS;

	# Font definitions
	my $font_title = "foreground='blue' size='x-large' weight='heavy'";
	my $font_label = "foreground='black' size='x-large' weight='heavy'";
	my $font_value = "foreground='black' size='x-large'";

	# Create a window object
	$window = Gtk2::Window->new;
	$window->set_title('Breato IPTV Player');
	$window->signal_connect(destroy => sub { Gtk2->main_quit; });
	$window->set_border_width(3);
	$window->maximize();

	# As a window can only contain 1 widget, create a vbox to hold the table of field
	# labels and values, the status message area and the buttons
	$vbox = Gtk2::VBox->new(FALSE,10);
	$window->add($vbox);

	# Create an hbox to pack the table and image
	my $hbox1 = Gtk2::HBox->new(FALSE,10);
	$vbox->add($hbox1);
	$hbox1->set_border_width(3);

	#
	# FIELD LABELS AND VALUES
	#
	# Create a table to hold the synopsis information
	$table = Gtk2::Table->new(7,3,FALSE);
	$table->set_row_spacings(5);
	$table->set_col_spacings(30);
	$hbox1->add($table);

	# Image
	$ref = $FILMS[$count-1][0];
	if($ref) {
		$image = Gtk2::Image->new_from_file("$FILM_ROOT/$ref/$ref-large.jpg");
		$image->set_alignment(0.0, 0.0);
		$hbox1->add($image);
	}

	# Title
	$table->attach_defaults(show_label("Title","L","T",$font_label),0,1,1,2);
	my $fld_title = show_label($FILMS[$count-1][1],"L","T",$font_title);
	$table->attach_defaults($fld_title,1,2,1,2);

	# Certificate
	$table->attach_defaults(show_label("Certificate","L","T",$font_label),0,1,5,6);
	my $fld_cert = show_label($FILMS[$count-1][5],"L","T",$font_value);
	$table->attach_defaults($fld_cert,1,2,5,6);

	# Duration
	$table->attach_defaults(show_label("Running Time","L","T",$font_label),0,1,7,8);
	my $fld_duration = show_label($FILMS[$count-1][7],"L","T",$font_value);
	$table->attach_defaults($fld_duration,1,2,7,8);

	# Release date
	$table->attach_defaults(show_label("Release Date","L","T",$font_label),0,1,9,10);
	my $fld_release = show_label($FILMS[$count-1][6],"L","T",$font_value);
	$table->attach_defaults($fld_release,1,2,9,10);

	# Genre
	$table->attach_defaults(show_label("Genre","L","T",$font_label),0,1,11,12);
	my $fld_genre = show_label($FILMS[$count-1][15],"L","T",$font_value);
	$table->attach_defaults($fld_genre,1,2,11,12);

	# Credits
	$table->attach_defaults(show_label("Credits","L","T",$font_label),0,1,13,14);
	my $fld_credits = show_label($FILMS[$count-1][4],"L","T",$font_value);
	$table->attach_defaults($fld_credits,1,2,13,14);

	# Strapline
	$table->attach_defaults(show_label("Strap Line","L","T",$font_label),0,1,15,16);
	my $fld_strap = show_label(wrap_text($FILMS[$count-1][2],40,10),"L","T",$font_value);
	$table->attach_defaults($fld_strap,1,2,15,16);

	# Synopsis
	$table->attach_defaults(show_label("Synopsis","L","T",$font_label),0,1,17,18);
	my $fld_synopsis = show_label(wrap_text($FILMS[$count-1][3],40,10),"L","T",$font_value);
	$table->attach_defaults(special_chars($fld_synopsis),1,2,17,18);

	#
	# STATUS MESSAGE AREA
	#
	# Create a status message area within the vbox
	my $status = Gtk2::Label->new();
	$vbox->pack_start($status,FALSE,FALSE,0);

	#
	# BUTTONS
	#
	# Create a frame in which to group the buttons and attach to the vbox
	my $buttons = Gtk2::Frame->new('Buttons');
	$buttons->set_border_width(3);
	$buttons->set_label(" Film $count of $max ");
	$vbox->pack_start($buttons,FALSE,FALSE,0);

	# Create an hbox to pack the buttons into, left to right
	my $hbox = Gtk2::HBox->new(FALSE,10);
	$buttons->add($hbox);
	$hbox->set_border_width(3);

	# Button to play the film trailer
	my $trailer_button = Gtk2::Button->new('_Trailer');
	$hbox->pack_start($trailer_button,FALSE,FALSE,0);
	if($FILMS[$count-1][20]) {
		$trailer_button->set_label('_Trailer');
		$trailer_button->signal_connect( clicked => sub {
			$status->set_text("");
			my $asset = "$FILM_ROOT/".$FILMS[$count-1][0]."/".$FILMS[$count-1][20];
			if(-f $asset) {
				$status->set_text("Playing trailer: $asset");
				$asset =~ s/ /\\ /g;
				play_media($asset,$FILMS[$count-1][23]);
			}
			else{
				$status->set_text("No trailer file: $asset");
			}
		});
	}
	else {
		$trailer_button->set_label('No Trailer');
		$status->set_text("No trailer for this film");
	}

	# Button to play the film
	my $film_button = Gtk2::Button->new('_Film');
	$hbox->pack_start($film_button, FALSE, FALSE, 0);
	if($FILMS[$count-1][30]) {
		$film_button->set_label('_Film');
		$film_button->signal_connect( clicked => sub {
			$status->set_text("");
			my $asset = "$FILM_ROOT/".$FILMS[$count-1][0]."/".$FILMS[$count-1][30];
			if(-f $asset) {
				$status->set_text("Playing film: $asset");
				$asset =~ s/ /\\ /g;
				play_media($asset,$FILMS[$count-1][33]);
			}
			else{
				$status->set_text("No film file: $asset");
			}
		});
	}
	else {
		$film_button->set_label('No Film');
		$status->set_text("No film for this film");
	}

	# Button to move to previous film in list
	my $dec_button = Gtk2::Button->new('_Prev');
	$hbox->pack_start($dec_button, FALSE, FALSE, 0);
	$dec_button->signal_connect( clicked => sub {
		if($count > 1) { $count--; }
		$status->set_text("");
		$buttons->set_label(" Film $count of $max ");
		$fld_title = show_label_change($fld_title,$FILMS[$count-1][1],$font_title);
		$fld_cert = show_label_change($fld_cert,$FILMS[$count-1][5],$font_value);
		$fld_duration = show_label_change($fld_duration,$FILMS[$count-1][7],$font_value);
		$fld_release = show_label_change($fld_release,$FILMS[$count-1][6],$font_value);
		$fld_genre = show_label_change($fld_genre,$FILMS[$count-1][15],$font_value);
		$fld_credits = show_label_change($fld_credits,$FILMS[$count-1][4],$font_value);
		$fld_strap = show_label_change($fld_strap,wrap_text($FILMS[$count-1][2],40,10),$font_value);
		$fld_synopsis = show_label_change($fld_synopsis,wrap_text($FILMS[$count-1][3],40,10),$font_value);
		$ref = $FILMS[$count-1][0];
		if($ref) {
			$image->set_from_file("$FILM_ROOT/$ref/$ref-large.jpg");
		}
		if($FILMS[$count-1][20]) {
			$trailer_button->set_label('_Trailer');
		}
		else {
			$trailer_button->set_label('No Trailer');
			$status->set_text("No trailer for this film");
		}
	});

	# Button to move to next film in list
	my $inc_button = Gtk2::Button->new('_Next');
	$hbox->pack_start($inc_button, FALSE, FALSE, 0);
	$inc_button->signal_connect( clicked => sub {
		if($count < $max) { $count++; }
		$status->set_text("");
		$buttons->set_label(" Film $count of $max ");
		$fld_title = show_label_change($fld_title,$FILMS[$count-1][1],$font_title);
		$fld_cert = show_label_change($fld_cert,$FILMS[$count-1][5],$font_value);
		$fld_duration = show_label_change($fld_duration,$FILMS[$count-1][7],$font_value);
		$fld_release = show_label_change($fld_release,$FILMS[$count-1][6],$font_value);
		$fld_genre = show_label_change($fld_genre,$FILMS[$count-1][15],$font_value);
		$fld_credits = show_label_change($fld_credits,$FILMS[$count-1][4],$font_value);
		$fld_strap = show_label_change($fld_strap,wrap_text($FILMS[$count-1][2],40,10),$font_value);
		$fld_synopsis = show_label_change($fld_synopsis,wrap_text($FILMS[$count-1][3],40,10),$font_value);
		$ref = $FILMS[$count-1][0];
		if($ref) {
			$image->set_from_file("$FILM_ROOT/$ref/$ref-large.jpg");
		}
		if($FILMS[$count-1][20]) {
			$trailer_button->set_label('_Trailer');
		}
		else {
			$trailer_button->set_label('No Trailer');
			$status->set_text("No trailer for this film");
		}
	});

	# Button to show detailed film information
	my $info_button = Gtk2::Button->new('_Info');
	$hbox->pack_start($info_button, FALSE, FALSE, 0);
	$info_button->signal_connect( clicked => sub {
		$status->set_text("");
		show_info($FILMS[$count-1]);
	});

	# Button to quit the UI
	my $quit_button = Gtk2::Button->new('_Quit');
	$hbox->pack_start($quit_button, FALSE, FALSE, 0);
	$quit_button->signal_connect( clicked => sub {
		Gtk2->main_quit;
	});

	# Display the window and all widgets within it
	$window->show_all;

	# Main event-loop
	Gtk2->main;
}



# ---------------------------------------------------------------------------------------------
# Display a window with all film information
# Arguments : Array of film data
# ---------------------------------------------------------------------------------------------
sub show_info {
	# Read arguments and initialise local variables
	my($dataref) = @_;
	my(@data,$window,$listbox);
	@data = @$dataref;

	# Create a new window for the data
	$window = Gtk2::Window->new('toplevel');
	$window->set_title($data[1]);
	$window->signal_connect('delete_event' => sub { Gtk2->main_quit; });
	$window->set_border_width(5);
	$window->set_position('center_always');

	# Invoke the function that will build up and display the information
	$listbox = &show_info_data(@data);

	# Show the list box
	$window->add($listbox);
	$window->show();

	# Main event loop
	Gtk2->main;
}



# ---------------------------------------------------------------------------------------------
# Build up and display the information about the film
# Arguments : Array of film data
# ---------------------------------------------------------------------------------------------
sub show_info_data {
	# Read arguments and initialise local variables
	my(@data) = @_;
	my($vbox,$sw,$tree_store,$branch,$leaf,$text,$tree_view,$tree_column,$renderer,@attr,$cod,$typ,$pid,$vl1,$vl2,$vl3,$vl4,$branch2,$leaf2);
	my %groups = (
		'General'		=> ['Asset Code',0,'Certificate',5,'Release Date',6,'Running Time',7,'IMDB Ref.',8,'Provider',9,'Provider Ref.',10,'Genre',15],
		'Languages'		=> ['Language',14,'Title',1,'Strap Line',2,'Synopsis',3,'Credits',4],
		'Licences'		=> ['Territory',11,'Licence Start',12,'Licence End',13],
		'Asset Film'	=> ['URL',30,'Class',31,'Coding',32,'Type',33,'Program',34,'Streams',35],
		'Asset Trailer'	=> ['URL',20,'Class',21,'Coding',22,'Type',23,'Program',24,'Streams',25] );

	# Create a vbox for the list options
	$vbox = Gtk2::VBox->new(FALSE,5);

	# Create a scrolled window that will host the treeview
	$sw = Gtk2::ScrolledWindow->new (undef,undef);
 	$sw->set_shadow_type('etched-out');
	$sw->set_policy('automatic','automatic');

	# Force a minimum size on the widget
	$sw->set_size_request(300,300);

	# Set the border width
	$sw->set_border_width(5);

	# Create the trunk of the tree structure
	$tree_store = Gtk2::TreeStore->new(qw/Glib::String/);

	# Populate the main nodes
	foreach my $group (sort keys %groups) {
		# Add a branch to the tree
		$branch = $tree_store->append(undef);
		$tree_store->set($branch,0 =>$group);
		# Create the leaves
		for(my $i=0; $i<=$#{$groups{$group}}; $i=$i+2) {
			$text = $data[$groups{$group}[$i+1]];
			if($text) {
				# Add leaf showing data type and value
				$leaf = $tree_store->append($branch);
				$tree_store->set($leaf,0 =>$groups{$group}[$i]." : ".$text);
				# If this is the 'Streams' leaf, add a branch showing the stream data
				if($groups{$group}[$i] eq 'Streams') {
					# Process each stream
					my $idx = $data[0]."-".(($group =~ m/Film/) ? 'film' : 'trailer');
					@attr = ();
					for(my $n=0; $n<@{$STREAMS{$idx}}; $n++) {
						$cod = $STREAMS{$idx}[$n][0];
						$typ = $STREAMS{$idx}[$n][1];
						$pid = $STREAMS{$idx}[$n][2];
						$vl1 = $STREAMS{$idx}[$n][3];
						$vl2 = $STREAMS{$idx}[$n][4];
						$vl3 = $STREAMS{$idx}[$n][5];
						$vl4 = $STREAMS{$idx}[$n][6];
						# Add a branch for the stream attributes
						$branch2 = $tree_store->append($branch);
						$tree_store->set($branch2,0 =>"Stream ($typ".(($typ eq 'audio') ? " $vl4" : "").")");
						# Add each stream attribute as a leaf
						# Coding
						$leaf2 = $tree_store->append($branch2);
						$tree_store->set($leaf2,0 =>"Coding : $cod");
						# Type
						$leaf2 = $tree_store->append($branch2);
						$tree_store->set($leaf2,0 =>"Type : $typ");
						# PID
						if($pid) {
							$leaf2 = $tree_store->append($branch2);
							$tree_store->set($leaf2,0 =>"PID : $pid");
						}
						# Video attributes
						if($typ eq 'video') {
							$leaf2 = $tree_store->append($branch2);
							$tree_store->set($leaf2,0 =>"Frame Size : $vl1");
							$leaf2 = $tree_store->append($branch2);
							$tree_store->set($leaf2,0 =>"Aspect Ratio : $vl2");
							$leaf2 = $tree_store->append($branch2);
							$tree_store->set($leaf2,0 =>"Frame Rate : $vl3");
							$leaf2 = $tree_store->append($branch2);
							$tree_store->set($leaf2,0 =>"Encode Rate : $vl4");
						}
						# Audio attributes
						if($typ eq 'audio') {
							$leaf2 = $tree_store->append($branch2);
							$tree_store->set($leaf2,0 =>"Sample Rate : $vl1");
							$leaf2 = $tree_store->append($branch2);
							$tree_store->set($leaf2,0 =>"Channels : $vl2");
							$leaf2 = $tree_store->append($branch2);
							$tree_store->set($leaf2,0 =>"Encode Rate : $vl3");
							$leaf2 = $tree_store->append($branch2);
							$tree_store->set($leaf2,0 =>"Language : $vl4");
						}
					}
				}
			}
		}
	}

	# Create a treeview, specify $tree_store as its model ?????????????????
	$tree_view = Gtk2::TreeView->new($tree_store);

	# Create a Gtk2::TreeViewColumn to add to $tree_view ??????????????????
	$tree_column = Gtk2::TreeViewColumn->new();
	$tree_column->set_title ("Click to sort");

	# Create a renderer that will be used to display info in the model
	$renderer = Gtk2::CellRendererText->new;

	# Add this renderer to $tree_column. This works like a Gtk2::Hbox
	# so you can add more than one renderer to $tree_column
	$tree_column->pack_start ($renderer, FALSE);

	# set the cell "text" attribute to column 0
	#- retrieve text from that column in treestore
	# Thus, the "text" attribute's value will depend on the row's value
	# of column 0 in the model($treestore),
	# and this will be displayed by $renderer,
	# which is a text renderer
	$tree_column->add_attribute($renderer, text => 0);

	# Add $tree_column to the treeview
	$tree_view->append_column ($tree_column);

	# Make it searchable
#	$tree_view->set_search_column(0);

	# Allow sorting on the column
#	$tree_column->set_sort_column_id(0);

	# Allow drag and drop reordering of rows
#	$tree_view->set_reorderable(TRUE);

	# Add the treeview to the window
	$sw->add($tree_view);
	$vbox->pack_start($sw,TRUE,TRUE,0);
	$vbox->show_all();
	return $vbox;
}



# ---------------------------------------------------------------------------------------------
# Create a label (read-only text)
# Argument 1 : Text to be written to the label
# Argument 2 : Horizontal alignment ('L'eft, 'Middle', 'R'ight)
# Argument 3 : Vertical alignment ('T'op, 'M'iddle, 'B'ottom)
# Argument 4 : Format to be applied (optional)
# Return the Label handle
# ---------------------------------------------------------------------------------------------
sub show_label {
	my($text,$ha,$va,$fmt) = @_;
	my($label,$h,$v);

	# Horizontal alignment
	# Alignment: horizontal (0=left,0.5=middle,1=right)
	if($ha eq "M") { $h = 0.5; }
	elsif($ha eq "R") { $h = 1; }
	else { $h = 0; }

	# Vertical alignment
	# Alignment: vertical (0=top,0.5=middle,1=bottom)
	if($va eq "M") { $v = 0.5; }
	elsif($va eq "B") { $v = 1; }
	else { $v = 0; }

	# Create the label and set the alignment
	$label = Gtk2::Label->new($text);
	$label->set_alignment($h,$v);

	# Apply the mark-up if a format argument is present
	if($fmt) {
		$label->set_markup("<span $fmt>".special_chars($text)."</span>");
	}

	# Return the lable address
	return $label;
}



# ---------------------------------------------------------------------------------------------
# Change the text in a label (read-only text)
# Argument 1 : Label handle
# Argument 2 : Text to be written to the label
# Argument 3 : Format to be applied
# ---------------------------------------------------------------------------------------------
sub show_label_change {
	my($label,$text,$fmt) = @_;
	if($fmt) {
		$label->set_markup("<span $fmt>$text</span>");
	}
	else {
		$label->set_text($text);
	}
	return $label;
}



# ---------------------------------------------------------------------------------------------
# Map special characters
# Argument 1 : Text string to be mapped
# Return the clean string
# ---------------------------------------------------------------------------------------------
sub special_chars {
	my($str) = @_;
	$str =~ s/&/&amp;/g;
	return $str;
}



# ---------------------------------------------------------------------------------------------
# Split a string of text over several lines
# Argument 1 : Text string
# Argument 2 : Max. number of characters in line
# Argument 3 : Max. number of lines
# ---------------------------------------------------------------------------------------------
sub wrap_text {
	# Read arguments and initialise local variables
	my($string,$max_chars,$max_lines) = @_;
	my(@words);
	my $result = "";
	my $lines = 0;
	my $line = "";

	# Split words into an array
	@words = split(' ',$string);
	for(my $w=0; $w<@words; $w++) {
		# Don't display too many lines
		if($lines < $max_lines) {
			# Show current line then start a new line
			if(length($line)+length($words[$w]) > $max_chars) {
				$result .= $line."\n";
				$line = $words[$w]." ";
				$lines++;
			}
			# Add word to current line
			else {
				$line .= $words[$w]." ";
			}
		}
	}
	# Add the current line
	if($lines < $max_lines) {
		$result .= $line."\n";
	}
	# Return the result
	return $result;
}



# ---------------------------------------------------------------------------------------------
# Program usage
# Argument 1 : Error number
# ---------------------------------------------------------------------------------------------
sub usage {
	my($err) = @_;
	$err = ($err) ? $err : 0;

	if($err == 1) {
		logMsgPortal($LOG,$PROGRAM,'E',"The 'class' argument must be present");
	}
	elsif($err == 2) {
		logMsgPortal($LOG,$PROGRAM,'E',"Argument 'class' must be 'uip', 'pbtv', 'bbc' or 'disney'");
	}
	elsif($err == 3) {
		logMsgPortal($LOG,$PROGRAM,'E',"The content directory [$FILM_ROOT] does not exist");
	}
	else {
		printf("
Program : $PROGRAM
Version : v$VERSION
Author  : Basil Fisk (c)2010 Breato Ltd

Summary :
  Display a set of pages that show the meta-data and images for all films
  on the attached content drive.  The films and trailers can be played.

Usage :
  $PROGRAM --class=<uip|pbtv|bbc|disney> --content=<path>

  MANDATORY
  --class=bbc               Play BBC films from the Content Server.
  --class=disney            Play Disney films from the Content Server.
  --class=pbtv              Play PlayboyTV films from the Content Server.
  --class=uip               Play UIP films from the Content Server.

  OPTIONAL
  --log                     If set, the results from the script will be written
                            to the Airwave log directory, otherwise the results
                            will be written to the screen.
		\n");
	}

	# Stop in all cases
	exit;
}
