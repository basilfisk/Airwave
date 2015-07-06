#!/usr/bin/perl
# ***************************************************************************
# ***************************************************************************
#
# Breato PDF report functions
#
# ***************************************************************************
# ***************************************************************************

# Declare modules
use strict;
use warnings;

# Declare the package name and export the function names
package mods::PDF;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(pdfReport);

# Load system modules
use Data::Dumper;
use PDF::Create;
use XML::LibXML;

# Load user modules
use lib '/usr/local/bin';
use mods::Common qw(ellipsis escapeSpecialChars formatDateTime formatNumber validFormat validNumber);

# References to the PDF document, current page and internal font set
our($PDF_DOC,$PDF_PAGE,%PDF_FONT);
our $MODULE = "Airwave::PDF";

# Report definitions loaded from the configuration file
our %PDF_REPORT = ();

# Colours and font definitions loaded from the configuration file
# Internal definitions for error messages
our %PDF_COLOURS = ();
$PDF_COLOURS{'##internal##'} = [ (255,0,0) ];
our %PDF_STYLES = ();
$PDF_STYLES{'##internal##'} = [ (8,'normal','##internal##') ];

# Absolute co-ordinates for each element
our %PDF_COORDS = ();

# Values read from the data file (static and dynamic) and names of repeating columns
our %PDF_STATIC = ();
our %PDF_DYNAMIC = ();
our %PDF_REPEAT = ();

# Hash for grouping values
our %PDF_GROUP = ();

# Page counters and sizes
our $PDF_PAGENO = 0;
our %PDF_PAGESIZE = (
	A0		=> [ 0, 0, 2380, 3368 ],
	A0L		=> [ 0, 0, 3368, 2380 ],
	A1		=> [ 0, 0, 1684, 2380 ],
	A1L		=> [ 0, 0, 2380, 1684 ],
	A2		=> [ 0, 0, 1190, 1684 ],
	A2L		=> [ 0, 0, 1684, 1190 ],
	A3		=> [ 0, 0, 842, 1190 ],
	A3L		=> [ 0, 0, 1190, 842 ],
	A4		=> [ 0, 0, 595, 842 ],
	A4L		=> [ 0, 0, 842, 595 ],
	A5		=> [ 0, 0, 421, 595 ],
	A5L		=> [ 0, 0, 595, 421 ],
	A6		=> [ 0, 0, 297, 421 ],
	A6L		=> [ 0, 0, 421, 297 ],
	Letter	=> [ 0, 0, 612, 792 ],
	LetterL	=> [ 0, 0, 792, 612 ],
);

1;





# ---------------------------------------------------------------------------------------------
# Read the configuration and data files, then run the report
#
# Argument 1 : Fully qualified name of the configuration file
# Argument 2 : Fully qualified name of the data file
# Argument 3 : Fully qualified name of the output file
# ---------------------------------------------------------------------------------------------
sub pdfReport {
	# Read the arguments and initialise variables
	my($conf,$data,$outp) = @_;
	my($psr,$doc,$xpc,@nodes,$psrd,$docd,$xpcd,$static,@data,$records,@dynamic,$tail,$relative,$index,$id,$no,$colhead,$newpage,$x,$y,@ddnodes,$parent);

	# ------------------------------------------------------------
	# CHECK FILES
	# ------------------------------------------------------------
	# Check configuration file exists, then store location
	if($conf) {
		if(!-f $conf) { error_msg("Configuration file does not exist [$conf]"); }
	}
	else { error_msg("Configuration file has not been specified"); }
	$PDF_REPORT{'config'} = $conf;

	# Check data file exists, then store location
	if($data) {
		if(!-f $data) { error_msg("Data file does not exist [$data]"); }
	}
	else { error_msg("Data file has not been specified"); }
	$PDF_REPORT{'data'} = $data;

	# Store location of output file
	$PDF_REPORT{'file'} = $outp;

	# ------------------------------------------------------------
	# VALIDATE THE CONFIGURATION FILE
	# ------------------------------------------------------------
	# Open and parse the XML configuration file
	$psr = XML::LibXML->new();
	$doc = $psr->parse_file($PDF_REPORT{'config'});
	$xpc = XML::LibXML::XPathContext->new($doc);

	# Read and validate the colour and style definitions
	read_colours($xpc);
	read_styles($xpc);

	# Validate the rest of the configuration file
	validate($xpc);

	# ------------------------------------------------------------
	# READ REPORT DEFINITIONS
	# ------------------------------------------------------------
	# Read the report description
	@nodes = $xpc->findnodes("/report/layout/report/author");
	$PDF_REPORT{'author'} = $nodes[0]->textContent;
	@nodes = $xpc->findnodes("/report/layout/report/reportname");
	$PDF_REPORT{'name'} = $nodes[0]->textContent;

	# Read page size and orientation
	@nodes = $xpc->findnodes("/report/layout/page/size");
	$PDF_REPORT{'size'} = $nodes[0]->textContent;
	@nodes = $xpc->findnodes("/report/layout/page/orientation");
	$PDF_REPORT{'orientation'} = $nodes[0]->textContent;

	# Read margins and alignment grid details
	@nodes = $xpc->findnodes("/report/layout/page/margin");
	$PDF_REPORT{'margin-x'} = $nodes[0]->getAttribute("x");
	$PDF_REPORT{'margin-y'} = $nodes[0]->getAttribute("y");
	@nodes = $xpc->findnodes("/report/layout/page/grid");
	$PDF_REPORT{'grid-status'} = $nodes[0]->getAttribute("status");
	$PDF_REPORT{'grid-spacing'} = $nodes[0]->getAttribute("spacing");
	$PDF_REPORT{'grid-weight'} = $nodes[0]->getAttribute("weight");

	# ------------------------------------------------------------
	# READ BOILERPLATE DEFINITIONS - SAME ON EVERY PAGE
	# ------------------------------------------------------------
	# Read the static data from the XML data file
	$psrd = XML::LibXML->new();
	$docd = $psrd->parse_file($PDF_REPORT{'data'});
	$xpcd = XML::LibXML::XPathContext->new($docd);
	@nodes = $xpcd->findnodes("/data/static/*");
	foreach my $node (@nodes) {
		$PDF_STATIC{$node->nodeName} = $node->textContent;
	}

	# Read the static page group
	@nodes = $xpc->findnodes("/report/process/static");
	$static = $nodes[0]->textContent;

	# Read the repeating group list
	@nodes = $xpc->findnodes("/report/process/repeat");
	if(@nodes) {
		@data = split(/ /,$nodes[0]->textContent);
		foreach my $id (@data) {
			$PDF_REPEAT{$id} = ' ';
		}
	}

	# Create the first page
	add_page($xpc,$static);

	# ------------------------------------------------------------
	# READ THE VARIABLE DATA
	# ------------------------------------------------------------
	# Read the group or groups in the data page
	@nodes = $xpc->findnodes("/report/process/data");
	foreach my $node (@nodes) {
		$id = $node->getAttribute('id');
		$no = $node->getAttribute('records');
		$newpage = $node->getAttribute('newpage');
		$newpage = ($newpage) ? 'yes' : 'no';
		$colhead = $node->getAttribute('colhead');
		$x = $node->getAttribute('x');
		$x = ($x) ? $x : 0;
		$y = $node->getAttribute('y');
		$y = ($y) ? $y : 0;
		@data = split(/ /,$node->textContent);

		# Read list of nodes holding data records matching this data ID
		@dynamic = $xpcd->findnodes("/data/dynamic/record[\@id='$id']");

		# Throw page at start of section if requested
		if($newpage eq 'yes') {
			add_page($xpc,$static);
		}

		# Loop through each record
		for(my $r=0; $r<@dynamic; $r++) {
			# Calculate the group number within the page
			$index = $r-((@data*$no)*int($r/(@data*$no)));

			# If this is the first row of the page, print the column heading
			if($index == 0 && $colhead) {
				prep_group($xpc,$colhead);
			}

			# Read the dynamic data from the XML data file
			@ddnodes = $dynamic[$r]->findnodes("*");
			%PDF_DYNAMIC = ();
			foreach my $dnode (@ddnodes) {
				$PDF_DYNAMIC{$dnode->nodeName} = $dnode->textContent;
			}

			# Print the group
			$parent = (@data > 1) ? $data[$index] : $data[0];
			prep_group($xpc,$parent,$static,$x,$y,$index);

			# If this is the last group on the page, start a new page and print static groups
			if((1+$index) == (@data*$no)) {
				# Dont throw new page if this is the last record of the set
				if((1+$r) < @dynamic) {
					add_page($xpc,$static);
				}
			}
		}
	}

	# ------------------------------------------------------------
	# PROCESS 'TAIL' DEFINITIONS
	# ------------------------------------------------------------
	# Process the tail group on the last page (optional)
	@nodes = $xpc->findnodes("/report/process/tail");
	if(@nodes) {
		$relative = $nodes[0]->getAttribute("relative");
		$tail = $nodes[0]->textContent;
		if($tail) {
			# Position relative to the named group
			if($relative) { prep_group($xpc,$tail,$relative); }
			# Position absolute on page
			else { prep_group($xpc,$tail); }
		}
	}

	# Close the PDF file
	close_pdf_file();
}





# =============================================================================================
# =============================================================================================
#
# INTERNAL FUNCTIONS
#
# =============================================================================================
# =============================================================================================

# ---------------------------------------------------------------------------------------------
# Add a page which inherits its attributes from $PDF_DOC
#
# Argument 1 : XPath Context
# Argument 2 : Name of static group
# ---------------------------------------------------------------------------------------------
sub add_page {
	# Read the arguments
	my($xpc,$static) = @_;

	# If this is the 1st page, create the file
	if(!$PDF_PAGENO) {
		open_pdf_file();
	}

	# Create index for page size hash
	my $size = $PDF_REPORT{'size'};
	if($PDF_REPORT{'orientation'} eq 'landscape') { $size .= "L"; }
	$size =~ tr/a-z/A-Z/;

	# Determine page sizes
	$PDF_REPORT{'page-x'} = $PDF_PAGESIZE{$size}[2];
	$PDF_REPORT{'page-y'} = $PDF_PAGESIZE{$size}[3];

	# Set the page size and increment the page number
	$PDF_PAGE = $PDF_DOC->new_page('MediaBox' => $PDF_PAGESIZE{$size});
	$PDF_PAGENO++;

	# Display the grid if needed
	if($PDF_REPORT{'grid-status'} eq 'on') { alignment_grid(); }

	# Clear out the repeating group to force all data to be shown on 1st record of page
	foreach my $key (keys %PDF_REPEAT) {
		$PDF_REPEAT{$key} = ' ';
	}

	# Print the static text on the page
	prep_group($xpc,$static);
}



# ---------------------------------------------------------------------------------------------
# Draw the alignment grid
# ---------------------------------------------------------------------------------------------
sub alignment_grid {
	my(@loop,$shade,$x,$y);

	# Number of iterations in each axis
	$loop[0] = 1+int(($PDF_REPORT{'page-y'}-2*$PDF_REPORT{'margin-y'})/$PDF_REPORT{'grid-spacing'});
	$loop[1] = 1+int(($PDF_REPORT{'page-x'}-2*$PDF_REPORT{'margin-x'})/$PDF_REPORT{'grid-spacing'});

	# Shading stroke to be applied
	$shade = (100-$PDF_REPORT{'grid-weight'})/100;

	# Draw vertical grid lines along x-axis
	for(my $i=0; $i<=$loop[1]; $i++) {
		$PDF_PAGE->setrgbcolorstroke($shade,$shade,$shade);
		$x = $PDF_REPORT{'margin-x'}+$i*$PDF_REPORT{'grid-spacing'};
		$y = $PDF_REPORT{'margin-y'}+$loop[0]*$PDF_REPORT{'grid-spacing'};
		$PDF_PAGE->moveto($x,$PDF_REPORT{'margin-y'});
		$PDF_PAGE->lineto($x,$y);
		$PDF_PAGE->stroke;
	}

	# Draw horizontal grid lines along y-axis
	for(my $i=0; $i<=$loop[0]; $i++) {
		$PDF_PAGE->setrgbcolorstroke($shade,$shade,$shade);
		$x = $PDF_REPORT{'margin-x'}+$loop[1]*$PDF_REPORT{'grid-spacing'};
		$y = $PDF_REPORT{'margin-y'}+$i*$PDF_REPORT{'grid-spacing'};
		$PDF_PAGE->moveto($PDF_REPORT{'margin-x'},$y);
		$PDF_PAGE->lineto($x,$y);
		$PDF_PAGE->stroke;
	}
}



# ---------------------------------------------------------------------------------------------
# Apply a group function to an element
#
# Argument 1  : ID of element that is being grouped
# Argument 2  : Group function to be applied (max/min/sum/count)
# Argument 3  : Value to be grouped
# ---------------------------------------------------------------------------------------------
sub apply_group_function {
	my($id,$fn,$new) = @_;
	my($curr);

	# If value is non-numeric, use 0 as the group holds text so only 'count' will work
	if(!validNumber($new)) { $new = 0; }

	# Read current value or use new value if no current value defined yet for group
	$curr = ($PDF_GROUP{$id}) ? $PDF_GROUP{$id} : $new;

	# Apply function and store updated value
	if($fn eq 'max') { $PDF_GROUP{$id} = ($new > $curr) ? $new : $curr; }
	if($fn eq 'min') { $PDF_GROUP{$id} = ($new < $curr) ? $new : $curr; }
	if($fn eq 'sum') { $PDF_GROUP{$id} += $new; }
	if($fn eq 'count') { $PDF_GROUP{$id}++; }
}



# ---------------------------------------------------------------------------------------------
# Close the PDF file
# ---------------------------------------------------------------------------------------------
sub close_pdf_file {
	# Only close it it has any pages
	if($PDF_PAGENO) {
		$PDF_DOC->close;
	}

	# Reset the page count to zero so that a new file can be created in the same session
	$PDF_PAGENO = 0;
}



# ---------------------------------------------------------------------------------------------
# Display an error message then quit
#
# Argument 1 : Error message
# ---------------------------------------------------------------------------------------------
sub error_msg {
	my($msg) = @_;
	print "\n[$MODULE] $msg\n\n";
	exit;
}



# ---------------------------------------------------------------------------------------------
# Create the PDF file
# ---------------------------------------------------------------------------------------------
sub open_pdf_file {
	# Create the PDF object
	$PDF_DOC = new PDF::Create('filename'		=> $PDF_REPORT{file},
							   'Version'		=> 1.2,
							   'Author'			=> $PDF_REPORT{author},
							   'Title'			=> $PDF_REPORT{name},
							   'CreationDate'	=> [ localtime ],
							 );

	# Font definitions
	$PDF_FONT{'normal'} = 
			$PDF_DOC->font('Subtype'  => 'Type1',
						   'Encoding' => 'WinAnsiEncoding',
						   'BaseFont' => 'Helvetica');
	$PDF_FONT{'bold'} = 
			$PDF_DOC->font('Subtype'  => 'Type1',
						   'Encoding' => 'WinAnsiEncoding',
						   'BaseFont' => 'Helvetica-Bold');
	$PDF_FONT{'oblique'} = 
			$PDF_DOC->font('Subtype'  => 'Type1',
						   'Encoding' => 'WinAnsiEncoding',
						   'BaseFont' => 'Helvetica-Oblique');
	$PDF_FONT{'bold-oblique'} = 
			$PDF_DOC->font('Subtype'  => 'Type1',
						   'Encoding' => 'WinAnsiEncoding',
						   'BaseFont' => 'Helvetica-BoldOblique');
}



# ---------------------------------------------------------------------------------------------
# Prepare an element for drawing on the PDF document
#
# Argument 1  : XPath context reference
# Argument 2  : ID of element
# Argument 3  : ID of element's parent
# ---------------------------------------------------------------------------------------------
sub prep_element {
	my($xpc,$id,$parent) = @_;
	my(@nodes,$type,@data,$stamp,$a,$c,$d,$f,$g,$h,$l,$r,$s,$sx,$sy,$t,$v,$w,$x,$y,$x1,$y1,$x2,$y2,$maxc,$maxl,$space,$res);

	# Determine the type of element
	@nodes = $xpc->findnodes("/report/elements/element[\@id='$id']");
	$type = $nodes[0]->getAttribute("type");

	# Box (rectangle with rounded corners)
	if($type eq 'box') {
		# Read co-ordinates, then add parent co-ordinates to get absolute position on page
		$x = $nodes[0]->getAttribute("x");
		$y = $nodes[0]->getAttribute("y");
		$x += @{$PDF_COORDS{$parent}}[0];
		$y += @{$PDF_COORDS{$parent}}[1];
		# Read size and style
		$w = $nodes[0]->getAttribute("width");
		$h = $nodes[0]->getAttribute("height");
		$d = $nodes[0]->getAttribute("weight");
		$l = $nodes[0]->getAttribute("lines");
		$f = $nodes[0]->getAttribute("fill");
		# Read radius of the corner
		$r = $nodes[0]->getAttribute("r");
		# Print the box
		draw_box($x,$y,$w,$h,$f,$l,$d,$r);
	}
	# Calculated field
	elsif($type eq 'calc') {
		# Read co-ordinates, then add parent co-ordinates to get absolute position on page
		$x = $nodes[0]->getAttribute("x");
		$y = $nodes[0]->getAttribute("y");
		$x += @{$PDF_COORDS{$parent}}[0];
		$y += @{$PDF_COORDS{$parent}}[1];
		# Read alignment and text style
		$a = $nodes[0]->getAttribute("align");
		$s = $nodes[0]->getAttribute("style");
		$f = $nodes[0]->getAttribute("format");
		# Read formula and substitute field names with data values
		$t = substitute_tag_values($nodes[0]->textContent);
		# Execute the formula and trap any errors
		$res = 0;
		eval('$res = '.$t);
		if($@) { error_msg("Formula failed in element '$id': $t"); }
		# Group the value if needed
		$g = $nodes[0]->getAttribute("group");
		if($g) { apply_group_function($id,$g,$res); }
		# Format the result
		$t = formatNumber($res,$f);
		# Print the string
		draw_string($x,$y,$t,$a,$s);
	}
	# Image read from file
	elsif($type eq 'image') {
		# Read co-ordinates, then add parent co-ordinates to get absolute position on page
		$x = $nodes[0]->getAttribute("x");
		$y = $nodes[0]->getAttribute("y");
		$x += @{$PDF_COORDS{$parent}}[0];
		$y += @{$PDF_COORDS{$parent}}[1];
		# Read scaling factors and URL of image
		$sx = $nodes[0]->getAttribute("scale-x");
		$sy = $nodes[0]->getAttribute("scale-y");
		# Read image tag and substitute with data values
		$t = substitute_tag_values($nodes[0]->textContent);
		# Print the image or 'Not found'
		if(-f $t) { draw_image($x,$y,$sx/100,$sy/100,$t); }
		else { draw_string($x,$y,'No Image','left','##internal##'); }
	}
	# Line
	elsif($type eq 'line') {
		# Read co-ordinates, then add parent co-ordinates to get absolute position on page
		$x1 = $nodes[0]->getAttribute("x1");
		$y1 = $nodes[0]->getAttribute("y1");
		$x1 += @{$PDF_COORDS{$parent}}[0];
		$y1 += @{$PDF_COORDS{$parent}}[1];
		$x2 = $nodes[0]->getAttribute("x2");
		$y2 = $nodes[0]->getAttribute("y2");
		$x2 += @{$PDF_COORDS{$parent}}[0];
		$y2 += @{$PDF_COORDS{$parent}}[1];
		# Read style of line
		$c = $nodes[0]->getAttribute("colour");
		# Print the line
		draw_line($x1,$y1,$x2,$y2,$c);
	}
	# Rectangle
	elsif($type eq 'rect') {
		# Read co-ordinates, then add parent co-ordinates to get absolute position on page
		$x = $nodes[0]->getAttribute("x");
		$y = $nodes[0]->getAttribute("y");
		$x += @{$PDF_COORDS{$parent}}[0];
		$y += @{$PDF_COORDS{$parent}}[1];
		# Read size and style of rectangle
		$w = $nodes[0]->getAttribute("width");
		$h = $nodes[0]->getAttribute("height");
		$d = $nodes[0]->getAttribute("weight");
		$l = $nodes[0]->getAttribute("lines");
		$f = $nodes[0]->getAttribute("fill");
		# Print the rectangle
		draw_rectangle($x,$y,$w,$h,$d,$l,$f);
	}
	# String of text defined in the configuration file
	elsif($type eq 'text') {
		# Read co-ordinates, then add parent co-ordinates to get absolute position on page
		$x = $nodes[0]->getAttribute("x");
		$y = $nodes[0]->getAttribute("y");
		$x += @{$PDF_COORDS{$parent}}[0];
		$y += @{$PDF_COORDS{$parent}}[1];
		# Read alignment and text style
		$a = $nodes[0]->getAttribute("align");
		$s = $nodes[0]->getAttribute("style");
		$f = $nodes[0]->getAttribute("format");
		# Read text
		$t = $nodes[0]->textContent;
		$t = ($t) ? $t : ' ';
		# Substitute page numbers
		$t =~ s/#pagenum#/$PDF_PAGENO/g;
		# Substitute date/time tagged with #date {picture}#
		if($t =~ /#date.*#/) {
			@data = split(/#date /,$t);
			@data = split(/#/,$data[1]);
			$stamp = formatDateTime($data[0]);
			$t =~ s/#date.*#/$stamp/g;
		}
		# Substitute aggregated values tagged with #group {name}#
		if($t =~ /#group.*#/) {
			@data = split(/#group /,$t);
			@data = split(/#/,$data[1]);
			$v = $PDF_GROUP{$data[0]};
			if($v) { $t =~ s/#group.*#/$v/; }
		}
		# Substitute field names with data values
		$t = substitute_tag_values($t);
		# Format the result
		$t = formatNumber($t,$f);
		# Truncate or wrap string
		$maxc = $nodes[0]->getAttribute("max-chars");
		$maxl = $nodes[0]->getAttribute("max-lines");
		$space = $nodes[0]->getAttribute("spacing");
		if($maxc) {
			# Wrap text over lines
			if($maxl) { $t = wrap_text($t,$maxc,$maxl); }
			# Truncate string with an ellipsis if longer than max. no. chars
			else { $t = ellipsis($t,$maxc); }
		}
		# Print the string
		draw_string($x,$y,$t,$a,$s,$space);
	}
	# String of text read from the database
	elsif($type eq 'value') {
		# Read co-ordinates, then add parent co-ordinates to get absolute position on page
		$x = $nodes[0]->getAttribute("x");
		$y = $nodes[0]->getAttribute("y");
		$x += @{$PDF_COORDS{$parent}}[0];
		$y += @{$PDF_COORDS{$parent}}[1];
		# Read alignment and text style
		$a = $nodes[0]->getAttribute("align");
		$s = $nodes[0]->getAttribute("style");
		$f = $nodes[0]->getAttribute("format");
		# Read field name and substitute with data value
		$t = substitute_tag_values($nodes[0]->textContent);
		$t = ($t) ? $t : ' ';
		# Format the result
		$t = formatNumber($t,$f);
		# Group the value if needed
		$g = $nodes[0]->getAttribute("group");
		if($g) { apply_group_function($id,$g,$t); }
		# Don't print if this is a repeating group
		if(!($PDF_REPEAT{$id} && $PDF_REPEAT{$id} eq "$t")) {
			# Truncate or wrap string
			$maxc = $nodes[0]->getAttribute("max-chars");
			$maxl = $nodes[0]->getAttribute("max-lines");
			$space = $nodes[0]->getAttribute("spacing");
			if($maxc) {
				# Wrap text over lines
				if($maxl) { $t = wrap_text($t,$maxc,$maxl); }
				# Truncate string with an ellipsis if longer than max. no. chars
				else { $t = ellipsis($t,$maxc); }
			}
			# Print the string
			draw_string($x,$y,$t,$a,$s,$space);
		}
		# Update the last value if this is a repeating group
		if($PDF_REPEAT{$id}) { $PDF_REPEAT{$id} = $t; }
	}
	else {
		print "Unknown element type\n";
	}
}



# ---------------------------------------------------------------------------------------------
# Recurse through the group structure
#
# Argument 1 : XPath context reference
# Argument 2 : ID of element
# Argument 3 : ID of element's parent (optional)
# Argument 4 : X offset of record from previous record (optional)
# Argument 5 : Y offset of record from previous record (optional)
# Argument 6 : Index into groups holding more than 1 group (optional)
# ---------------------------------------------------------------------------------------------
sub prep_group {
	my($xpc,$id,$parent,$xoffset,$yoffset,$index) = @_;
	my(@nodes,$x,$y,@margin,@children);

	# Read co-ordinates of group (relative to parent)
	@nodes = $xpc->findnodes("/report/groups/group[\@id='$id']");
	$x = $nodes[0]->getAttribute("x");
	$y = $nodes[0]->getAttribute("y");

	# Calculate absolute position of group on page
	# If element has a parent, add parent co-ordinates to child
	if($parent) {
		$x += @{$PDF_COORDS{$parent}}[0];
		$y += @{$PDF_COORDS{$parent}}[1];
		# If more than 1 record/page, apply x/y offsets from last record
		if($index) {
			$x += $xoffset*$index;
			$y -= $yoffset*$index;
		}
	}
	# If there is no parent, this is the top of the tree so use the page margins
	else {
		$x += $PDF_REPORT{'margin-x'};
		$y += $PDF_REPORT{'margin-y'};
	}

	# Add absolute co-ordinates to hash
	$PDF_COORDS{$id} = [ ($x,$y) ];

	# Process list of children
	@children = split(/ /,$nodes[0]->textContent);
	foreach my $child (@children) {
		@nodes = $xpc->findnodes("/report/groups/group[\@id='$child']");
		if(@nodes) {
			# It's a group
			prep_group($xpc,$child,$id,$xoffset,$yoffset,$index);
		}
		else {
			# It's an element, so draw it
			prep_element($xpc,$child,$id,1,1);
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Read the colour definitions from the configuration file
#
# Argument 1 : XPath Context
# ---------------------------------------------------------------------------------------------
sub read_colours {
	my($xpc) = @_;
	my($path,@nodes,$id,$r,$g,$b);

	# Read the colour definitions. There must be at least 1
	$path = "/report/format/colours/colour";
	@nodes = $xpc->findnodes($path);
	if(!@nodes) { error_msg("No colours defined: $path"); }

	# Check each node before loading hash
	foreach my $node (@nodes) {
		# 'id' must be present and alphanumeric
		$id = $node->getAttribute("id");
		if(!$id) { error_msg("Missing 'id' for colour: $path"); }
		if($id =~ /\W/) { error_msg("'id' attribute must be alphanumeric, not '$id': $path"); }

		# Red attribute must be present and an integer in range 0-255
		$r = $node->getAttribute("r");
		val_int($r,'Red',$id,0,255,$path);

		# Green attribute must be present and an integer in range 0-255
		$g = $node->getAttribute("g");
		val_int($g,'Green',$id,0,255,$path);

		# Blue attribute must be present and an integer in range 0-255
		$b = $node->getAttribute("b");
		val_int($b,'Blue',$id,0,255,$path);

		# Load hash
		$PDF_COLOURS{$id} = [ ($r,$g,$b) ];
	}
}



# ---------------------------------------------------------------------------------------------
# Read the style definitions from the configuration file
#
# Argument 1 : XPath Context
# ---------------------------------------------------------------------------------------------
sub read_styles {
	my($xpc) = @_;
	my($path,@nodes,$id,$s,$w,$c);

	# Read the style definitions. There must be at least 1
	$path = "/report/format/styles/style";
	@nodes = $xpc->findnodes($path);
	if(!@nodes) { error_msg("No styles defined: $path"); }

	# Check each node before loading hash
	foreach my $node (@nodes) {
		# 'id' must be present and alphanumeric
		$id = $node->getAttribute("id");
		if(!$id) { error_msg("Missing 'id' for style: $path"); }
		if($id =~ /\W/) { error_msg("'id' attribute must be alphanumeric, not '$id': $path"); }

		# Size attribute must be present and an integer >=6
		$s = $node->getAttribute("size");
		if(!$s) { error_msg("Missing size attribute for '$id': $path"); }
		if($s =~ /\D/) { error_msg("Size attribute for '$id' must be an integer, not '$s': $path"); }
		if($s < 6) { error_msg("Size attribute for '$id' must be in 6 or more, not '$s': $path"); }

		# Weight attribute must be present and normal/bold
		$w = $node->getAttribute("weight");
		if(!$w) { error_msg("Missing weight attribute for '$id': $path"); }
		if($w ne 'bold' && $w ne 'normal') { error_msg("Weight attribute for '$id' must be 'normal' or 'bold', not '$w': $path"); }

		# Colour attribute must be in $PDF_COLOURS
		$c = $node->getAttribute("colour");
		if(!$c) { error_msg("Missing colour attribute for '$id': $path"); }
		if(!$PDF_COLOURS{$c}) { error_msg("Colour attribute '$c' for '$id' has not been defined: $path"); }

		# Load hash
		$PDF_STYLES{$id} = [ ($s,$w,$c) ];
	}
}



# ---------------------------------------------------------------------------------------------
# Substitute data tags with data values
#
# Argument 1 : String to be parsed
#
# Return the parsed string
# ---------------------------------------------------------------------------------------------
sub substitute_tag_values {
	my($str) = @_;

	# Replace data tags with static values
	foreach my $key (keys %PDF_STATIC) {
		$str =~ s/#$key#/$PDF_STATIC{$key}/g;
	}

	# Replace data tags with dynamic values
	foreach my $key (keys %PDF_DYNAMIC) {
		$str =~ s/#$key#/$PDF_DYNAMIC{$key}/g;
	}

	# Replace remaining data tags with 0
	$str =~ s/#.*#/0/g;

	# Return modified string
	return $str;
}



# ---------------------------------------------------------------------------------------------
# Validate the contents of the configuration file
#
# Argument 1 : XPath Context
# ---------------------------------------------------------------------------------------------
sub validate {
	my($xpc)= @_;
	my($path,@nodes,$node,$str,@groups,@grps,$id,%names,@values,@elems,@elms,$type,$psrd,$docd,$xpcd,@dynamic);

	# ------------------------------------------------------------
	# AUTHOR
	# ------------------------------------------------------------
	# Author must be present and alphanumeric
	$path = "/report/layout/report/author";
	@nodes = $xpc->findnodes($path);
	if(!@nodes) { error_msg("Author element must be defined: $path"); }
	$str = $nodes[0]->textContent;
	if(!$str =~ /\W/) { error_msg("Author element must be alphanumeric, not '$str': $path"); }

	# ------------------------------------------------------------
	# REPORT NAME
	# ------------------------------------------------------------
	# Report name must be present and alphanumeric
	$path = "/report/layout/report/reportname";
	@nodes = $xpc->findnodes($path);
	if(!@nodes) { error_msg("Report name element must be defined: $path"); }
	$str = $nodes[0]->textContent;
	if(!$str =~ /\W/) { error_msg("Report name element must be alphanumeric, not '$str': $path"); }

	# ------------------------------------------------------------
	# PAGE SIZE
	# ------------------------------------------------------------
	# Must be one of the preset values
	$path = "/report/layout/page/size";
	@nodes = $xpc->findnodes($path);
	if(!@nodes) { error_msg("Page size element must be defined: $path"); }
	$str = $nodes[0]->textContent;
	$str =~ tr/A-Z/a-z/;
	if($str ne 'a0' && $str ne 'a1' && $str ne 'a2' && $str ne 'a3' && $str ne 'a4' && $str ne 'a5' && $str ne 'a6' && $str ne 'letter') {
		error_msg("Page size attribute must be 'A0,A1,A2,A3,A4,A5,A6,Letter', not '$str': $path");
	}

	# ------------------------------------------------------------
	# PAGE ORIENTATION
	# ------------------------------------------------------------
	# Portrait or landscape
	$path = "/report/layout/page/orientation";
	@nodes = $xpc->findnodes($path);
	if(!@nodes) { error_msg("Page orientation element must be defined: $path"); }
	$str = $nodes[0]->textContent;
	$str =~ tr/A-Z/a-z/;
	if($str ne 'portrait' && $str ne 'landscape') { error_msg("Page orientation attribute must be 'portrait' or 'landscape', not '$str': $path"); }

	# ------------------------------------------------------------
	# PAGE MARGINS
	# ------------------------------------------------------------
	# Mandatory
	$path = "/report/layout/page/margin";
	@nodes = $xpc->findnodes($path);
	if(!@nodes) { error_msg("Page margin element must be defined: $path"); }

	# X margin must be integer >= 0
	$str = $nodes[0]->getAttribute('x');
	val_int($str,'x','Page Margin',0,'',$path);

	# Y margin must be integer >= 0
	$str = $nodes[0]->getAttribute('y');
	val_int($str,'y','Page Margin',0,'',$path);

	# ------------------------------------------------------------
	# PAGE ALIGNMENT GRID
	# ------------------------------------------------------------
	# Mandatory
	$path = "/report/layout/page/grid";
	@nodes = $xpc->findnodes($path);
	if(!@nodes) { error_msg("Page grid element must be defined: $path"); }

	# Status attribute must be present (on/off)
	$str = $nodes[0]->getAttribute('status');
	if(!$str) { error_msg("Missing 'status' attribute for page grid: $path"); }
	if($str ne 'on' && $str ne 'off') { error_msg("Status attribute for page grid must be 'on' or 'off', not '$str': $path"); }

	# Spacing attribute must be in range 10-200
	$str = $nodes[0]->getAttribute('spacing');
	val_int($str,'spacing','Grid',10,200,$path);

	# Weight attribute must be in range 10-100
	$str = $nodes[0]->getAttribute('weight');
	val_int($str,'weight','Grid',10,100,$path);

	# ------------------------------------------------------------
	# STATIC LAYOUT
	# ------------------------------------------------------------
	# Single group in static page layout
	# Must be only 1 'static' node
	$path = "/report/process/static";
	@nodes = $xpc->findnodes($path);
	if(!@nodes) { error_msg("The static page layout is missing: $path"); }
	if(@nodes > 1) { error_msg("There must only be 1 static page layout: $path"); }

	# Must hold only 1 group
	$str = $nodes[0]->textContent;
	@groups = split(/ /,$str);
	if(@groups != 1) { error_msg("There must be 1 and only 1 group in the 'static' page layout: $path"); }

	# Groups must be valid
	foreach my $grp (@groups) {
		@grps = $xpc->findnodes("/report/groups/group[\@id='$grp']");
		if(!@grps) { error_msg("'$grp' is not a valid group: $path"); }
	}

	# ------------------------------------------------------------
	# DATA LAYOUT
	# ------------------------------------------------------------
	# Must be 1 or more 'data' nodes
	$path = "/report/process/data";
	@nodes = $xpc->findnodes($path);
	if(!@nodes) { error_msg("The dynamic page layout is missing: $path"); }

	# Parse the data file
	$psrd = XML::LibXML->new();
	$docd = $psrd->parse_file($PDF_REPORT{'data'});
	$xpcd = XML::LibXML::XPathContext->new($docd);

	# Each node must hold 1 or more groups
	NODE: foreach my $node (@nodes) {
		$str = $node->textContent;
		@groups = split(/ /,$str);
		if(!@groups) { error_msg("There must be at least 1 group in the 'data' page layout: $path"); }

		# Groups must be valid
		foreach my $grp (@groups) {
			@grps = $xpc->findnodes("/report/groups/group[\@id='$grp']");
			if(!@grps) { error_msg("'$grp' is not a valid group: $path"); }
		}

		# ID is mandatory and must be referenced at least once in data file
		$str = $node->getAttribute('id');
		if(!$str) { error_msg("Data elements in '/report/process/data' must have IDs"); }

		# If node is not defined, don't process the data
		@dynamic = $xpcd->findnodes("/data/dynamic/record[\@id='$str']");
		next NODE if(!@dynamic);

		# Number of records/page is mandatory and >= 1
		$str = $node->getAttribute('records');
		val_int($str,'records','Data Element',1,'',$path);

		# X margin is optional and >= 0
		$str = $node->getAttribute('x');
		if($str) { val_int($str,'x','Data Element',0,'',$path); }

		# Y margin is optional and >= 0
		$str = $node->getAttribute('y');
		if($str) { val_int($str,'y','Data Element',0,'',$path); }

		# New page is optional and either 'yes' or 'no'
		$str = $node->getAttribute('newpage');
		if($str) {
			if($str ne 'yes' && $str ne 'no') { error_msg("'newpage' attribute for data element must be 'yes' or 'no', not '$str': $path"); }
		}

		# Column heading is optional and only holds 1 group
		$str = $node->getAttribute('colhead');
		if($str) {
			@groups = split(/ /,$str);
			if(@groups != 1) { error_msg("There must only be 1 group in the 'colhead' attribute: $path"); }
			@grps = $xpc->findnodes("/report/groups/group[\@id='$str']");
			if(!@grps) { error_msg("'colhead' group '$str' is not defined: $path"); }
		}
	}

	# ------------------------------------------------------------
	# REPEATING GROUPS
	# ------------------------------------------------------------
	# List of elements in repeating fields (>=1, optional)
	# Optionally there can be 1 'repeat' node holding 1 or more groups
	$path = "/report/process/repeat";
	@nodes = $xpc->findnodes($path);
	if(@nodes > 1) { error_msg("There must only be 1 repeating field definition: $path"); }

	# Groups must be valid
	if(@nodes) {
		$str = $nodes[0]->textContent;
		@elems = split(/ /,$str);
		foreach my $elm (@elems) {
			@elms = $xpc->findnodes("/report/elements/element[\@id='$elm' and \@type='value']");
			if(!@elms) { error_msg("'$elm' is not a valid 'value' element: $path"); }
		}
	}

	# ------------------------------------------------------------
	# TAIL GROUPS AT END OF REPORT
	# ------------------------------------------------------------
	# List of groups in tail page layout (>=1, optional)
	$path = "/report/process/tail";
	@nodes = $xpc->findnodes($path);
	if(@nodes) {
		$str = $nodes[0]->textContent;
		@groups = split(/ /,$str);
		foreach my $grp (@groups) {
			@grps = $xpc->findnodes("/report/groups/group[\@id='$grp']");
			if(!@grps) { error_msg("'$grp' is not a valid group: $path"); }
		}
	}

	# ------------------------------------------------------------
	# GROUPS
	# ------------------------------------------------------------
	# Each with one or more valid groups or elements, id=Mand
	%names = ();
	$path = "/report/groups/group";
	@nodes = $xpc->findnodes($path);
	if(!@nodes) { error_msg("There must be at least 1 group element in /report/groups"); }
	foreach $node (@nodes) {
		# 'id' must be present and alphanumeric
		$id = $node->getAttribute("id");
		if(!$id) { error_msg("Missing 'id' for group: $path"); }
		if($id =~ /\W/) { error_msg("'id' attribute must be alphanumeric, not '$id': $path"); }

		# Check if group name is a duplicate
		if($names{$id}) { error_msg("'$id' is a duplicate group: $path"); }
		$names{$id} = 1;

		# X margin
		$str = $node->getAttribute('x');
		val_int($str,'x',$id,'','',$path);

		# Y margin
		$str = $node->getAttribute('y');
		val_int($str,'y',$id,'','',$path);

		# Check that the named groups and elements are valid
		$str = $node->textContent;
		@values = split(/ /,$str);
		foreach my $value (@values) {
			@grps = $xpc->findnodes("/report/groups/group[\@id='$value']");
			@elms = $xpc->findnodes("/report/elements/element[\@id='$value']");
			if(!(@grps||@elms)) { error_msg("'$value' is not a valid group or element in group '$id': $path"); }
		}
	}

	# ------------------------------------------------------------
	# ELEMENTS
	# ------------------------------------------------------------
	# Each with id=Mand, type=Mand and attributes specific to the type value
	%names = ();
	$path = "/report/elements/element";
	@nodes = $xpc->findnodes($path);
	if(!@nodes) { error_msg("There must be at least 1 element in /report/elements"); }
	foreach $node (@nodes) {
		# 'id' must be present and alphanumeric
		$id = $node->getAttribute("id");
		if(!$id) { error_msg("Missing 'id' for element: $path"); }
		if($id =~ /\W/) { error_msg("'id' attribute must be alphanumeric, not '$id': $path"); }

		# Check if element name is a duplicate
		if($names{$id}) { error_msg("'$id' is a duplicate element: $path"); }
		$names{$id} = 1;

		# 'type' must be present and one of: box/calc/image/line/rect/text/value
		$type = $node->getAttribute("type");
		if(!$type) { error_msg("Missing 'type' for element '$id': $path"); }
		if($type ne 'box' && $type ne 'calc' && $type ne 'image' && $type ne 'line' && $type ne 'rect' && $type ne 'text' && $type ne 'value') {
			error_msg("'type' attribute for element '$id' must be one of 'box/calc/image/line/rect/text/value': $path");
		}

		# Check each type of element
		if($type eq 'box') {
			# X offset of bottom left of box from parent container
			$str = $node->getAttribute('x');
			val_int($str,'x',$id,0,'',$path);
			# Y offset of bottom left of box from parent container
			$str = $node->getAttribute('y');
			val_int($str,'y',$id,0,'',$path);
			# Width
			$str = $node->getAttribute('width');
			val_int($str,'width',$id,10,'',$path);
			# Height
			$str = $node->getAttribute('height');
			val_int($str,'height',$id,10,'',$path);
			# Weight
			$str = $node->getAttribute('weight');
			val_int($str,'weight',$id,1,10,$path);
			# Radius
			$str = $node->getAttribute('r');
			val_int($str,'r',$id,0,20,$path);
			# Line colour attribute must be in $PDF_COLOURS
			$str = $node->getAttribute("lines");
			if(!$str) { error_msg("'lines' attribute missing for '$id': $path"); }
			if(!$PDF_COLOURS{$str}) { error_msg("Line colour attribute '$str' for '$id' has not been defined: $path"); }
			# Fill colour attribute must be in $PDF_COLOURS
			$str = $node->getAttribute("fill");
			if(!$str) { error_msg("'fill' attribute missing for '$id': $path"); }
			if(!$PDF_COLOURS{$str}) { error_msg("Line colour attribute '$str' for '$id' has not been defined: $path"); }
		}
		if($type eq 'calc') {
			# X offset of bottom left of text from parent container
			$str = $node->getAttribute('x');
			val_int($str,'x',$id,0,'',$path);
			# Y offset of bottom left of text from parent container
			$str = $node->getAttribute('y');
			val_int($str,'y',$id,0,'',$path);
			# Style of text must be in $PDF_STYLES
			$str = $node->getAttribute("style");
			if(!$str) { error_msg("'style' attribute missing for '$id': $path"); }
			if(!$PDF_STYLES{$str}) { error_msg("Style attribute '$str' for '$id' has not been defined: $path"); }
			# Alignment (optional)
			$str = $node->getAttribute('align');
			if(!$str) { $str = 'left'; }
			if($str ne 'left' && $str ne 'right' && $str ne 'centre') {
				error_msg("'align' attribute for '$id' must be one of 'left/right/centre': $path");
			}
			# Number format (optional)
			$str = $node->getAttribute('format');
			validFormat($str);
			# Grouping (optional)
			$str = $node->getAttribute('group');
			if($str && $str ne 'max' && $str ne 'min' && $str ne 'sum' && $str ne 'count') {
				error_msg("'group' attribute for '$id' must be one of 'max/min/sum/count': $path");
			}
		}
		if($type eq 'image') {
			# X offset of bottom left of image from parent container
			$str = $node->getAttribute('x');
			val_int($str,'x',$id,0,'',$path);
			# Y offset of bottom left of image from parent container
			$str = $node->getAttribute('y');
			val_int($str,'y',$id,0,'',$path);
			# Scaling of X axis (1-100%)
			$str = $node->getAttribute('scale-x');
			val_int($str,'scale-x',$id,1,100,$path);
			# Scaling of Y axis (1-100%)
			$str = $node->getAttribute('scale-y');
			val_int($str,'scale-y',$id,1,100,$path);
		}
		if($type eq 'line') {
			# X offset of start of line from parent container
			$str = $node->getAttribute('x1');
			val_int($str,'x1',$id,0,'',$path);
			# Y offset of start of line from parent container
			$str = $node->getAttribute('y1');
			val_int($str,'y1',$id,0,'',$path);
			# X offset of end of line from parent container
			$str = $node->getAttribute('x2');
			val_int($str,'x2',$id,0,'',$path);
			# Y offset of end of line from parent container
			$str = $node->getAttribute('y2');
			val_int($str,'y2',$id,0,'',$path);
			# Colour attribute must be in $PDF_COLOURS
			$str = $node->getAttribute("colour");
			if(!$str) { error_msg("'colour' attribute missing for '$id': $path"); }
			if(!$PDF_COLOURS{$str}) { error_msg("Colour attribute '$str' for '$id' has not been defined: $path"); }
		}
		if($type eq 'rect') {
			# X offset of bottom left of rectangle from parent container
			$str = $node->getAttribute('x');
			val_int($str,'x',$id,0,'',$path);
			# Y offset of bottom left of rectangle from parent container
			$str = $node->getAttribute('y');
			val_int($str,'y',$id,0,'',$path);
			# Width
			$str = $node->getAttribute('width');
			val_int($str,'width',$id,10,'',$path);
			# Height
			$str = $node->getAttribute('height');
			val_int($str,'height',$id,10,'',$path);
			# Weight
			$str = $node->getAttribute('weight');
			val_int($str,'weight',$id,1,10,$path);
			# Colour of lines must be in $PDF_COLOURS
			$str = $node->getAttribute("lines");
			if(!$str) { error_msg("'colour' attribute missing for '$id': $path"); }
			if(!$PDF_COLOURS{$str}) { error_msg("Colour attribute '$str' for '$id' has not been defined: $path"); }
			# Colour of fill must be in $PDF_COLOURS
			$str = $node->getAttribute("fill");
			if(!$str) { error_msg("'fill'r attribute missing for '$id': $path"); }
			if(!$PDF_COLOURS{$str}) { error_msg("Colour attribute '$str' for '$id' has not been defined: $path"); }
		}
		if($type eq 'text') {
			# X offset of bottom left of text from parent container
			$str = $node->getAttribute('x');
			val_int($str,'x',$id,0,'',$path);
			# Y offset of bottom left of text from parent container
			$str = $node->getAttribute('y');
			val_int($str,'y',$id,0,'',$path);
			# Style of text must be in $PDF_STYLES
			$str = $node->getAttribute("style");
			if(!$str) { error_msg("'style' attribute missing for '$id': $path"); }
			if(!$PDF_STYLES{$str}) { error_msg("Style attribute '$str' for '$id' has not been defined: $path"); }
			# Text string must exist
			$str = $node->textContent;
			if(!$str) { error_msg("No text string has been entered for '$id': $path"); }
			# Alignment (optional)
			$str = $node->getAttribute('align');
			if(!$str) { $str = 'left'; }
			if($str ne 'left' && $str ne 'right' && $str ne 'centre') {
				error_msg("'align' attribute for '$id' must be one of 'left/right/centre': $path");
			}
			# Number format (optional)
			$str = $node->getAttribute('format');
			validFormat($str);
			# Line spacing (optional)
			$str = $node->getAttribute('spacing');
			if(!$str) { $str = '5'; }
			val_int($str,'spacing',$id,5,'',$path);
			# Maximum number of characters on a line before it is wrapped (optional)
			$str = $node->getAttribute('max-chars');
			if(!$str) { $str = '10'; }
			val_int($str,'max-chars',$id,10,'',$path);
			# Maximum number of lines (optional)
			$str = $node->getAttribute('max-lines');
			if(!$str) { $str = '1'; }
			val_int($str,'max-lines',$id,1,'',$path);
		}
		if($type eq 'value') {
			# X offset of bottom left of text from parent container
			$str = $node->getAttribute('x');
			val_int($str,'x',$id,0,'',$path);
			# Y offset of bottom left of text from parent container
			$str = $node->getAttribute('y');
			val_int($str,'y',$id,0,'',$path);
			# Style of text must be in $PDF_STYLES
			$str = $node->getAttribute("style");
			if(!$str) { error_msg("'style' attribute missing for '$id': $path"); }
			if(!$PDF_STYLES{$str}) { error_msg("Style attribute '$str' for '$id' has not been defined: $path"); }
			# Value string must exist
			$str = $node->textContent;
			if(!$str) { error_msg("No value string has been entered for '$id': $path"); }
			# Alignment (optional)
			$str = $node->getAttribute('align');
			if(!$str) { $str = 'left'; }
			if($str ne 'left' && $str ne 'right' && $str ne 'centre') {
				error_msg("'align' attribute for '$id' must be one of 'left/right/centre': $path");
			}
			# Number format (optional)
			$str = $node->getAttribute('format');
			validFormat($str);
			# Grouping (optional)
			$str = $node->getAttribute('group');
			if($str && $str ne 'max' && $str ne 'min' && $str ne 'sum' && $str ne 'count') {
				error_msg("'group' attribute for '$id' must be one of 'max/min/sum/count': $path");
			}
			# Line spacing (optional)
			$str = $node->getAttribute('spacing');
			if(!$str) { $str = '5'; }
			val_int($str,'spacing',$id,5,'',$path);
			# Maximum number of characters on a line before it is wrapped (optional)
			$str = $node->getAttribute('max-chars');
			if(!$str) { $str = '10'; }
			val_int($str,'max-chars',$id,10,'',$path);
			# Maximum number of lines (optional)
			$str = $node->getAttribute('max-lines');
			if(!$str) { $str = '1'; }
			val_int($str,'max-lines',$id,1,'',$path);
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Validate a string as an integer
#
# Argument 1 : String containing the integer
# Argument 2 : Name of the attribute being tested
# Argument 3 : Name of the element
# Argument 4 : Minimum value allowed (optional)
# Argument 5 : Maximum value allowed (optional)
# Argument 6 : Path to the element holding the attribute
# ---------------------------------------------------------------------------------------------
sub val_int {
	my($str,$attr,$id,$min,$max,$path) = @_;
	if($str eq '0' || $str || defined $str) {
		# String exists
		if(!validNumber($str)) { error_msg("'$attr' attribute for '$id' must be an integer, not '$str': $path"); }
		if($min && $str < $min ) { error_msg("'$attr' attribute for '$id' must be >=$min, not '$str': $path"); }
		if($max && $str > $max ) { error_msg("'$attr' attribute for '$id' must be <=$max, not '$str': $path"); }
	}
	else {
		# String doesn't exist
		error_msg("'$attr' attribute missing for '$id': $path");
	}
}



# ---------------------------------------------------------------------------------------------
# Wrap a string of text over multiple lines
#
# Argument 1 : String of text
# Argument 2 : Maximum number of characters on a line
# Argument 3 : Maximum number of lines
#
# Return new string, with lines delimited by "@nl@"
# ---------------------------------------------------------------------------------------------
sub wrap_text {
	my($text,$len,$max) = @_;
	my(@lines,@words,$lineno,$new,$line);

	# If any newlines are embedded in string, use these to wrap first
	if($text =~ /\@nl\@/) {
		@lines = split(/\@nl\@/,$text);
		for(my $l=0; $l<$max; $l++) {
			# Line is not empty
			if($lines[$l]) {
				# Last line doesn't need newline
				if(($l+1) == $max) {
					# Truncate string with an ellipsis if longer than max. no. chars
					$line = ellipsis($lines[$l],$len);
					$new .= $line;
				}
				else {
					# Truncate string with an ellipsis if longer than max. no. chars
					$line = ellipsis($lines[$l],$len);
					$new .= $line.'@nl@';
				}
			}
			# Line is empty
			else {
				$new .= '@nl@';
			}
		}
	}
	# Wrap string based on chars/line and max lines
	else {
		# Split string into array of words, initialise string to hold line text and line counter
		@words = split(/ /,$text);
		$line = $new = "";
		$lineno = 0;

		# Loop through each word and build up a line
		WORD: for(my $w=0; $w<@words; $w++) {
			# Don't print too many lines
			if($lineno < $max) {
				# If word can fit on current line, add word to current line
				if(length($line)+length($words[$w]) <= $len) {
					$line .= $words[$w]." ";
				}
				# If word will overflow...
				else {
					# If this is the last line
					if(($lineno+1) == $max) {
						# Terminate string with an ellipsis if words remaining (remove last space)
						if(($w+1) < @words) {
							$line = substr($line,0,-1);
							$line .= '...';
							$new .= $line;
							last WORD;
						}
					}
					# This is not the last line
					else {
						# Add current line to buffer and restart line
						$new .= $line.'@nl@';
						$line = $words[$w]." ";
						$lineno++;
					}
				}
			}
			# If last word or last line, all current line to buffer
			if(($w+1) == @words || $lineno == $max) {
				$new .= $line;
			}
		}
	}

	# Return new string
	return $new;
}





# =============================================================================================
# =============================================================================================
#
# PDF DRAWING FUNCTIONS
#
# =============================================================================================
# =============================================================================================

# ---------------------------------------------------------------------------------------------
# Draw a box
#
# Argument 1 : X-coordinate of bottom left
# Argument 2 : Y-coordinate of bottom left
# Argument 3 : Width of box
# Argument 4 : Height of box
# Argument 5 : Fill colour (from list of defined colours)
# Argument 6 : Colour of lines (from list of defined colours)
# Argument 7 : Weight of lines in points
# Argument 8 : Radius of corner in points
# ---------------------------------------------------------------------------------------------
sub draw_box {
	my($x,$y,$w,$h,$fill,$lines,$weight,$radius) = @_;
	my $bend;
	my($rl,$gl,$bl) = @{$PDF_COLOURS{$lines}};
	my($rf,$gf,$bf) = @{$PDF_COLOURS{$fill}};

	# By default, the box has no curved corners
	$radius = ($radius) ? $radius : 0;
	$bend = 0.5;    # Degree of bending ???????????????????????????????????????
	$bend = $radius*$bend;

	# By default, the weight is 1pt
	$weight = ($weight) ? $weight : 1;

	# Draw the shape and fill with colour
	$PDF_PAGE->newpath;
	$PDF_PAGE->setrgbcolor($rf/255,$gf/255,$bf/255);
	draw_box_shape($x,$y,$w,$h,$radius,$bend);
	$PDF_PAGE->fill();

	# Draw the shape and set colour and width of box lines
	$PDF_PAGE->newpath;
	$PDF_PAGE->setrgbcolorstroke($rl/255,$gl/255,$bl/255);
	$PDF_PAGE->set_width($weight);
	draw_box_shape($x,$y,$w,$h,$radius,$bend);
	$PDF_PAGE->stroke;
}



# ---------------------------------------------------------------------------------------------
# Draw the box shape
#
# Argument 1 : X-coordinate of bottom left
# Argument 2 : Y-coordinate of bottom left
# Argument 3 : Width of box
# Argument 4 : Height of box
# Argument 5 : Radius of corner
# Argument 6 : Bend of corner
# ---------------------------------------------------------------------------------------------
sub draw_box_shape {
	my($x,$y,$w,$h,$radius,$bend) = @_;

	# Start drawing from lower right of the bottom left corner
	$PDF_PAGE->moveto($x+$radius,$y);

	# Draw the bottom left corner (from lower right to top left)
	if($radius) {
		$PDF_PAGE->curveto($x+$bend,$y,$x,$y+$bend,$x,$y+$radius);
	}

	# Draw the left-hand vertical line (from bottom to top)
	$PDF_PAGE->lineto($x,$y+$h-$radius);

	# Draw the top left corner (from lower left to top right)
	if($radius) {
		$PDF_PAGE->curveto($x,$y+$h-$bend,$x+$radius-$bend,$y+$h,$x+$radius,$y+$h);
	}

	# Draw the top horizontal line (from left to right)
	$PDF_PAGE->lineto($x+$w-$radius,$y+$h);

	# Draw the top right corner (from top left to bottom right)
	if($radius) {
		$PDF_PAGE->curveto($x+$w-$bend,$y+$h,$x+$w,$y+$h-$bend,$x+$w,$y+$h-$radius);
	}

	# Draw the right-hand vertical line (from top to bottom)
	$PDF_PAGE->lineto($x+$w,$y+$radius);

	# Draw the bottom right corner (from top right to bottom left)
	if($radius) {
		$PDF_PAGE->curveto($x+$w,$y+$bend,$x+$w-$radius+$bend,$y,$x+$w-$radius,$y);
	}

	# Draw the bottom horizontal line (from right to left)
	$PDF_PAGE->lineto($x+$radius,$y);
}



# ---------------------------------------------------------------------------------------------
# Draw a JPEG or GIF image
#
# Argument 1 : X-coordinate of bottom left
# Argument 2 : Y-coordinate of bottom left
# Argument 3 : Scaling of image on X-axis
# Argument 4 : Scaling of image on Y-axis
# Argument 5 : Source of image
# Argument 6 : Anchor point ('bl','tl') - 'bl' is the default
#
# Return 0 if drawn OK, 1 if failed
# ---------------------------------------------------------------------------------------------
sub draw_image {
	# Read arguments and define local variables
	my($x,$y,$xscale,$yscale,$image,$anchor) = @_;
	my($hdl,$ax,$ay,$rc);

	# Set the default anchor position
	$anchor = ($anchor) ? $anchor : 'bl';
	if($anchor eq 'bl') { $ax = 0; $ay = 0; }
	if($anchor eq 'tl') { $ax = 0; $ay = 2; }

	# Check the image file exists
	if(!-e $image) {
		print "No image file [$image]\n";
		return 1;
	}

	# Open the image file
	$hdl = $PDF_DOC->image($image);
	local $SIG{__WARN__} = sub { print "--->" . $_[0] . "\n"; };
	eval {
		$PDF_PAGE->image('image'=>$hdl,'xscale'=>$xscale,'yscale'=>$yscale,'xalign'=>$ax,'yalign'=>$ay,'xpos'=>$x,'ypos'=>$y);
	};

	# Return the result
	$rc = ($@) ? 1 : 0;
	return $rc;
}



# ---------------------------------------------------------------------------------------------
# Draw a line
#
# Argument 1 : X-coordinate of start
# Argument 2 : Y-coordinate of start
# Argument 3 : X-coordinate of end
# Argument 4 : Y-coordinate of end
# Argument 5 : Colour of line
# ---------------------------------------------------------------------------------------------
sub draw_line {
	my($x1,$y1,$x2,$y2,$colour) = @_;
	my($rc,$gc,$bc) = @{$PDF_COLOURS{$colour}};

	# Set the colour of the line
	$PDF_PAGE->setrgbcolorstroke($rc/255,$gc/255,$bc/255);

	# Draw the line
	$PDF_PAGE->moveto($x1,$y1);
	$PDF_PAGE->lineto($x2,$y2);

	# Draw the lines to the page
	$PDF_PAGE->stroke;
}



# ---------------------------------------------------------------------------------------------
# Draw a rectangle
#
# Argument 1 : X-coordinate of bottom left
# Argument 2 : Y-coordinate of bottom left
# Argument 3 : Width
# Argument 4 : Height
# Argument 5 : Weight of lines (points)
# Argument 6 : Colour of lines
# Argument 7 : Fill colour
# ---------------------------------------------------------------------------------------------
sub draw_rectangle {
	my($x,$y,$w,$h,$weight,$lines,$fill) = @_;
	my($rl,$gl,$bl) = @{$PDF_COLOURS{$lines}};
	my($rf,$gf,$bf) = @{$PDF_COLOURS{$fill}};

	# Draw the rectangle and fill it with colour
	$PDF_PAGE->newpath();
	$PDF_PAGE->rectangle($x,$y,$w,$h);
	$PDF_PAGE->setrgbcolor($rf/255,$gf/255,$bf/255);
	$PDF_PAGE->fill();

	# Redraw the rectangle and add the border
	$PDF_PAGE->setrgbcolorstroke($rl/255,$gl/255,$bl/255);
	$PDF_PAGE->set_width($weight);
	$PDF_PAGE->rectangle($x,$y,$w,$h);

	# Draw the rectangle to the page
	$PDF_PAGE->stroke;
}



# ---------------------------------------------------------------------------------------------
# Draw a string of text.  If the text string contains newline characters, it will be drawn
# over multiple lines.
#
# Argument 1 : X-coordinate of bottom left
# Argument 2 : Y-coordinate of bottom left
# Argument 3 : Text to be written
# Argument 4 : Alignment (left,centre,right)
# Argument 5 : Style name
# Argument 6 : Line spacing (optional)
# ---------------------------------------------------------------------------------------------
sub draw_string {
	# Read the arguments
	my($x,$y,$str,$align,$stype,$space) = @_;
	my($size,$weight,$colour,$r,$g,$b,@lines);

	# Read the style details
	($size,$weight,$colour) = @{$PDF_STYLES{$stype}};

	# Use the bold font if the 'bold' weight is specified in the style
	$weight = ($weight eq 'bold') ? $PDF_FONT{bold} : $PDF_FONT{normal};

	# Read the colour details and set the palette
	($r,$g,$b) = @{$PDF_COLOURS{$colour}};
	$PDF_PAGE->setrgbcolor($r/255,$g/255,$b/255);

	# Use left alignment by default
	$align = ($align) ? $align : 'l';
	if($align eq 'right') { $align = 'r'; }
	elsif($align eq 'centre') { $align = 'c'; }
	else { $align = 'l'; }

	# Use 10pt spacing by default
	$space = ($space) ? $space : 10;

	# Split the string using embedded newlines, then print
	if($str =~ /\@nl\@/) {
		@lines = split(/\@nl\@/,$str);
	}
	else {
		@lines = split(/\\n/,$str);
	}

	# Print each line
	foreach my $line (@lines) {
		$PDF_PAGE->string($weight,$size,$x,$y,$line,$align);
		# Decrement the y co-ordinate by the line spacing
		$y -= $space;
	}

	# Reset the palette
	$PDF_PAGE->setrgbcolor(0,0,0);
}
