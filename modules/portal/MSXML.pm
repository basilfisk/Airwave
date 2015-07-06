#!/usr/bin/perl
# *********************************************************************************************
# *********************************************************************************************
#
# Create a spreadsheet in MSXML 2007 format.  The following files are created and then
# zipped up and named with a '.xlsx' file extension.
#
#       ./[Content_Types].xml		   Static
#       ./_rels/.rels				   Static
#       ./docProps/app.xml			      Static
#       ./docProps/core.xml			     Static, barring the author and dates
#       ./xl/sharedStrings.xml		  Unique list of strings
#       ./xl/styles.xml				 List of styles
#       ./xl/workbook.xml			       Structure of workbook
#       ./xl/_rels/workbook.xml.rels    Structure of workbook
#       ./xl/worksheets/SheetN.xml	      Row by row of data for workbook N
#
# *********************************************************************************************
# *********************************************************************************************

# Declare the package name and export the function names
use strict;
use warnings;

# Load modules
use IO::File;
use XML::LibXML;
use XML::Writer;

# Breato modules
use mods::Common qw(formatDateTime);

# Declare the package name and export the function names
package mods::MSXML;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(msxmlCell msxmlClose msxmlColumn msxmlCreate msxmlData msxmlInitialise 
				 msxmlRow msxmlRowNumber msxmlSetParameter msxmlStyleAdd msxmlWorkbook);

# Initialise the styles to be used in the spreadsheet
our $MSXML_ENCODING = 'UTF-8';
our %MSXML_PARAMS;
our %MSXML_STYLE;
our %MSXML_TEXT;
our @MSXML;
our @MSXML_BOOKS;
our %MSXML_TRACK = (
	border => 0,
	fill => 0,
	font => 0,
	number => 0,
	xf => 0 );

1;





# ---------------------------------------------------------------------------------------------
# Column definitions
#
# Argument 1 : Column letter
# Argument 2 : Style of the cell
# Argument 3 : Value in the cell
# ---------------------------------------------------------------------------------------------
sub msxmlCell {
	my($column,$style,$value) = @_;
	my($seq,$type,$class);

	# Style index
	if(!$MSXML_STYLE{"cell-$style"}) {
		print "Cell style [$style] has not been defined\n";
		exit;
	}
	($seq) = @{$MSXML_STYLE{"cell-$style"}};

	# If the value is a formula, set the type to a number and remove the leading '='
	if($value =~ /^=/) {
		$type = 'n';
		$value =~ s/^=//;
		$class = 'f';
	}
	# If the value is an array formula, set the type to a number and remove the leading '{='
	elsif($value =~ /^{=/) {
		$type = 'n';
		$value =~ s/^{=//;
		$value =~ s/}$//;
		$class = 'f';
	}
	# Number if all digits and decimal point (optional)
	else {
		$type = ($value =~ /^[\d\.]+$/) ? 'n' : 's';
		$class = 'v';
	}

	# If data type is a string, add to sharedStrings.xml and use the index as the value
	if($type eq 's') {
		# Try to read value and, if it exists, use returned index as the value
		if(exists $MSXML_TEXT{$value}) {
			$value = $MSXML_TEXT{$value};
		}
		# Add new entry to hash and generate new index
		else {
			$MSXML_TEXT{$value} = $MSXML[3];
			$value = $MSXML[3];
			$MSXML[3]++;
		}
		# Increment total number of strings
		$MSXML[4]++;
	}

	# Open the container
	$MSXML[1]->startTag("c","r"=>$column.$MSXML[2],"s"=>$seq,"t"=>$type);

	# If this is a formula, remove leading '='
	if($class eq 'f') {
		$MSXML[1]->dataElement($class,$value,"aca"=>"false");
	}
	else {
		$MSXML[1]->dataElement($class,$value);
	}

	# Close the container
	$MSXML[1]->endTag("c");
}



# ---------------------------------------------------------------------------------------------
# Close the spreadsheet
#
# Return null if successful, or a message if an error raised
# ---------------------------------------------------------------------------------------------
sub msxmlClose {
	my($rc,$root,$name);

	# Create the dynamic files based on workbook data
	msxmlSharedStrings();
	if($rc) { return $rc; }

	msxmlContentTypes();
	if($rc) { return $rc; }

	msxmlWorkbooks();
	if($rc) { return $rc; }

	msxmlWorkbookRelations();
	if($rc) { return $rc; }

	# Zip file into a ".xlsx", move to target directory, then remove temporary files
	$root = msxmlGetParameter('ROOT');
	$name = msxmlGetParameter('NAME').'.xlsx';
	system("cd $root; zip -r $name *; mv $name ..");
	system("rm -R $root");

	# Return undef for success
	return;
}



# ---------------------------------------------------------------------------------------------
# Column definitions
#
# Argument 1 : Open, insert column or close the column container
# Argument 2 : Width of the column
# Argument 3 : Number of consecutive columns the style is to be applied to
# Argument 4 : Style for the column (optional, which defaults to 'normal')
# ---------------------------------------------------------------------------------------------
sub msxmlColumn {
	my($action,$width,$repeat,$style) = @_;
	my($seq,$last);

	# Create the container
	if($action eq 'open') {
		$MSXML[1]->startTag("cols");
	}
	# Close the container
	elsif($action eq 'close') {
		$MSXML[1]->endTag("cols");
	}
	# Insert a column definition and increment the number of columns counter
	else {
		# If no style set for the column, set default to 'normal'
		if(!$style) { $style = 'normal'; }

		# Determine the style index from the name
		if(!$MSXML_STYLE{"column-$style"}) {
			print "Column style [$style] has not been defined\n";
			exit;
		}
		($seq) = @{$MSXML_STYLE{"column-$style"}};

		# Increment the number of columns counter
		$last = $MSXML[5] + 1;
		$MSXML[5] += $repeat;

		# Create the element
		$MSXML[1]->emptyTag("col","collapsed"=>"false","hidden"=>"false","max"=>$MSXML[5],"min"=>$last,"style"=>$seq,"width"=>$width);
	}
}



# ---------------------------------------------------------------------------------------------
# Create the content type definitions
#
# Return null if successful, or a message if an error raised
# ---------------------------------------------------------------------------------------------
sub msxmlContentTypes {
	my($fh,$index,$file,$xml);
	$file = msxmlGetParameter('ROOT')."/[Content_Types].xml";
	$index = 1;

	# Open the document and write the header
	open($fh,">$file");
	if(!$fh) {
		return "Can't create $file";
	}
	$xml = new XML::Writer(OUTPUT => $fh);
	$xml->xmlDecl($MSXML_ENCODING);

	# Generate the document
	$xml->startTag("Types","xmlns"=>"http://schemas.openxmlformats.org/package/2006/content-types");
	$xml->emptyTag("Override","PartName"=>"/_rels/.rels","ContentType"=>"application/vnd.openxmlformats-package.relationships+xml");
	$xml->emptyTag("Override","PartName"=>"/docProps/core.xml","ContentType"=>"application/vnd.openxmlformats-package.core-properties+xml");
	$xml->emptyTag("Override","PartName"=>"/docProps/app.xml","ContentType"=>"application/vnd.openxmlformats-officedocument.extended-properties+xml");
	$xml->emptyTag("Override","PartName"=>"/xl/_rels/workbook.xml.rels","ContentType"=>"application/vnd.openxmlformats-package.relationships+xml");
	$xml->emptyTag("Override","PartName"=>"/xl/workbook.xml","ContentType"=>"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml");
	foreach my $sheet (@MSXML_BOOKS) {
		$xml->emptyTag("Override","PartName"=>"/xl/worksheets/sheet$index.xml","ContentType"=>"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml");
		$index++;
	}
	$xml->emptyTag("Override","PartName"=>"/xl/styles.xml","ContentType"=>"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml");
	$xml->emptyTag("Override","PartName"=>"/xl/sharedStrings.xml","ContentType"=>"application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml");
	$xml->endTag("Types");

	# Close the document
	$xml->end();
	$fh->close();

	# Return undef for success
	return;
}



# ---------------------------------------------------------------------------------------------
# Core properties
#
# Return null if successful, or a message if an error raised
# ---------------------------------------------------------------------------------------------
sub msxmlCoreProperties {
	my($fh,$file,$date,$xml);
	$file = msxmlGetParameter('ROOT')."/docProps/core.xml";
	$date = mods::Common::formatDateTime('cczy-zm-zdTzh24:mi:ss.00Z');

	# Open the document and write the header
	open($fh,">$file");
	if(!$fh) {
		return "Can't create $file";
	}
	$xml = new XML::Writer(OUTPUT => $fh);
	$xml->xmlDecl($MSXML_ENCODING);

	# Generate the document
	$xml->startTag("cp:coreProperties","xmlns:cp"=>"http://schemas.openxmlformats.org/package/2006/metadata/core-properties","xmlns:dc"=>"http://purl.org/dc/elements/1.1/","xmlns:dcmitype"=>"http://purl.org/dc/dcmitype/","xmlns:dcterms"=>"http://purl.org/dc/terms/","xmlns:xsi"=>"http://www.w3.org/2001/XMLSchema-instance");
	$xml->dataElement("dcterms:created",$date,"xsi:type"=>"dcterms:W3CDTF");
	$xml->dataElement("dcterms:modified",$date,"xsi:type"=>"dcterms:W3CDTF");
	$xml->dataElement("cp:lastModifiedBy",$MSXML_PARAMS{AUTHOR});
	$xml->dataElement("cp:revision",0);
	$xml->endTag("cp:coreProperties");

	# Close the document
	$xml->end();
	$fh->close();

	# Return undef for success
	return;
}



# ---------------------------------------------------------------------------------------------
# Create the temporary directory structure and the static files
#
# Return null if successful, or a message if an error raised
# ---------------------------------------------------------------------------------------------
sub msxmlCreate {
	my($rc);

	msxmlTempDirectories();

	$rc = msxmlRelationships();
	if($rc) { return $rc; }

	$rc = msxmlProperties();
	if($rc) { return $rc; }

	$rc = msxmlCoreProperties();
	if($rc) { return $rc; }

	$rc = msxmlStyleDefinition();
	if($rc) { return $rc; }

	# Last index number used for sharedStrings.xml
	$MSXML[3] = 0;

	# Total number of strings referenced by sharedStrings.xml
	$MSXML[4] = 0;

	# Return undef for success
	return;
}



# ---------------------------------------------------------------------------------------------
# Data container
#
# Argument 1 : Open or close the data container
# ---------------------------------------------------------------------------------------------
sub msxmlData {
	my($action) = @_;

	# Create the container and set the row and style counters
	if($action eq 'open') {
		$MSXML[1]->startTag("sheetData");
	}
	# Close the container
	else {
		$MSXML[1]->endTag("sheetData");
	}
}



# ---------------------------------------------------------------------------------------------
# Return a requested parameter
#
# Argument 1 : Name of parameter
# ---------------------------------------------------------------------------------------------
sub msxmlGetParameter {
	my($key) = @_;
	return $MSXML_PARAMS{$key};
}



# ---------------------------------------------------------------------------------------------
# Initialise the environment for creating an MSXML spreadsheet
# This must be run first
# ---------------------------------------------------------------------------------------------
sub msxmlInitialise {
	# Initialise the default spreadsheet settings
	$MSXML_PARAMS{CENTRE_H}			= 'true';
	$MSXML_PARAMS{CENTRE_V}			= 'false';
	$MSXML_PARAMS{FIT_TO_PAGE}		= 'false';
	$MSXML_PARAMS{FIT_H}			= 'true';
	$MSXML_PARAMS{FIT_W}			= 'true';
	$MSXML_PARAMS{GRID_LINES}		= 'false';
	$MSXML_PARAMS{HEADINGS}			= 'false';
	$MSXML_PARAMS{MARGIN_LEFT}		= 0.5;
	$MSXML_PARAMS{MARGIN_RIGHT}		= 0.5;
	$MSXML_PARAMS{MARGIN_TOP}		= 0.5;
	$MSXML_PARAMS{MARGIN_BOTTOM}	= 0.5;
	$MSXML_PARAMS{MARGIN_HEADER}	= 0.5;
	$MSXML_PARAMS{MARGIN_FOOTER}	= 0.5;
	$MSXML_PARAMS{ORIENTATION}		= 'portrait';
	$MSXML_PARAMS{ROW_HEIGHT}		= 12.6;
	$MSXML_PARAMS{SCALE}			= 100;
	$MSXML_PARAMS{SHOW_ZEROS}		= 'true';

	# Initialise the default styles
	msxmlStyleAdd("number","normal","picture=GENERAL");
	msxmlStyleAdd("font","normal","name=Arial,size=10");
	msxmlStyleAdd("fill","normal","pattern=none");
	msxmlStyleAdd("border","normal","left=0,right=0,top=0,bottom=0");
	msxmlStyleAdd("cell","normal","border=normal,fill=normal,font=normal,number=normal");
	msxmlStyleAdd("column","normal","border=normal,fill=normal,font=normal,number=normal");
}



# ---------------------------------------------------------------------------------------------
# Create the Properties section
#
# Return null if successful, or a message if an error raised
# ---------------------------------------------------------------------------------------------
sub msxmlProperties {
	my($fh,$file,$xml);
	$file = msxmlGetParameter('ROOT')."/docProps/app.xml";

	# Open the document and write the header
	open($fh,">$file");
	if(!$fh) {
		return "Can't create $file";
	}
	$xml = new XML::Writer(OUTPUT => $fh);
	$xml->xmlDecl($MSXML_ENCODING);

	# Generate the document
	$xml->startTag("Properties","xmlns"=>"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties","xmlns:vt"=>"http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes");
	$xml->dataElement("TotalTime",0);
	$xml->endTag("Properties");

	# Close the document
	$xml->end();
	$fh->close();

	# Return undef for success
	return;
}



# ---------------------------------------------------------------------------------------------
# Create the Relationships section
#
# Return null if successful, or a message if an error raised
# ---------------------------------------------------------------------------------------------
sub msxmlRelationships {
	my($fh,$file,$xml);
	$file = msxmlGetParameter('ROOT')."/_rels/.rels";

	# Open the document and write the header
	open($fh,">$file");
	if(!$fh) {
		return "Can't create $file";
	}
	$xml = new XML::Writer(OUTPUT => $fh);
	$xml->xmlDecl($MSXML_ENCODING);

	# Generate the document
	$xml->startTag("Relationships","xmlns"=>"http://schemas.openxmlformats.org/package/2006/relationships");
	$xml->emptyTag("Relationship","Id"=>"rId1","Type"=>"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument","Target"=>"xl/workbook.xml");
	$xml->emptyTag("Relationship","Id"=>"rId2","Type"=>"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties","Target"=>"docProps/core.xml");
	$xml->emptyTag("Relationship","Id"=>"rId3","Type"=>"http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties","Target"=>"docProps/app.xml");
	$xml->endTag("Relationships");

	# Close the document
	$xml->end();
	$fh->close();

	# Return undef for success
	return;
}



# ---------------------------------------------------------------------------------------------
# Row container
#
# Argument 1 : Open or close the row container
# Argument 2 : Row height (optional)
# ---------------------------------------------------------------------------------------------
sub msxmlRow {
	my($action,$height) = @_;
	my $ht = ($height) ? $height : msxmlGetParameter('ROW_HEIGHT');

	# Increment the row counter, then create the container
	if($action eq 'open') {
		$MSXML[2]++;
		$MSXML[1]->startTag("row","collapsed"=>"false","customFormat"=>"false","customHeight"=>"true","hidden"=>"false","ht"=>$ht,"outlineLevel"=>"0","r"=>$MSXML[2]);
	}
	# Close the container
	else {
		$MSXML[1]->endTag("row");
	}
}



# ---------------------------------------------------------------------------------------------
# Return the current row number
# ---------------------------------------------------------------------------------------------
sub msxmlRowNumber {
	return $MSXML[2];
}



# ---------------------------------------------------------------------------------------------
# Register a parameter and it's value
#
# Argument 1 : Name of parameter
# Argument 2 : Value of parameter
# ---------------------------------------------------------------------------------------------
sub msxmlSetParameter {
	my($key,$value) = @_;

	# Escape any spaces in the file name
	if($key eq 'NAME') {
		$value =~ s/ /\\ /g;
	}

	# Escape any spaces in the directory path
	if($key eq 'DIR') {
		$value =~ s/ /\\ /g;
	}

	# Assign the parameter value
	$MSXML_PARAMS{$key} = $value;
}



# ---------------------------------------------------------------------------------------------
# Unique list of strings in the workbooks
#
# Return null if successful, or a message if an error raised
# ---------------------------------------------------------------------------------------------
sub msxmlSharedStrings {
	my($file,$fh,$xml,@data);
	$file = msxmlGetParameter('ROOT')."/xl/sharedStrings.xml";

	# Read each string from the hash and put into sequence in the array
	foreach my $text (keys %MSXML_TEXT) {
		$data[$MSXML_TEXT{$text}] = $text;
	}

	# Open the document and write the header
	open($fh,">$file");
	if(!$fh) {
		return "Can't create $file";
	}
	$xml = new XML::Writer(OUTPUT => $fh);
	$xml->xmlDecl($MSXML_ENCODING);

	# Container for strings
	$xml->startTag("sst","xmlns"=>"http://schemas.openxmlformats.org/spreadsheetml/2006/main","count"=>$MSXML[4],"uniqueCount"=>$MSXML[3]);

	# Process each shared string
	foreach my $text (@data) {
		$xml->startTag("si");
		$xml->dataElement("t",$text);
		$xml->endTag("si");
	}

	# Close the container
	$xml->endTag("sst");

	# Close the document
	$xml->end();
	$fh->close();

	# Return undef for success
	return;
}



# ---------------------------------------------------------------------------------------------
# Generate the XML definition for a style
#
# Argument 1 : Style type (border/cell/column/fill/font/number)
# Argument 2 : Style name
# Argument 3 : Style parameters, which is a string of comma separated parameters that either
#			  hold name/value pairs separated by '=', or the name of a parameter that is to
#			  be set to 'true'
#
# Return null if successful, or a message if an error raised
# ---------------------------------------------------------------------------------------------
sub msxmlStyleAdd {
	my($type,$name,$parameters) = @_;
	my(@params,$id,$elements,$attributes,$attr_xf,$attr_align,$attr_prot,$xml);
	my($diagonalDown,$diagonalUp);
	my($applyAlignment,$applyBorder,$applyFill,$applyFont,$applyNumberFormat,$applyProtection,$shrinkToFit,$wrapText,$hidden,$locked);

	# Don't add duplicate styles within a type
	if($MSXML_STYLE{"$type-$name"}) {
		return "Not adding duplicate style [$name] for type [$type]\n";
	}

	# Border definitions
	if($type eq 'border') {
		# msxmlStyleAdd("border","name",""left=thin,right=medium:FF4F81BD,top=thick,bottom=double,diagonal=thin,diagonalDown,diagonalUp");
		@params = split(/,/,$parameters);
		$diagonalDown = 0;
		$diagonalUp = 0;
		# Create attributes
		foreach my $param (@params) {
			if($param =~ 'diagonalDown')    { $diagonalDown = 1; }
			if($param =~ 'diagonalUp')	      { $diagonalUp = 1; }
		}
		# Create elements
		foreach my $param (@params) {
			if($param =~ '=') {
				my($side,$rest) = split(/=/,$param);
				my($style,$color) = split(/:/,$rest);
				if($color) {
					$elements .= "<$side style='$style'><color rgb='$color'/></$side>";
				}
				else {
					$elements .= "<$side style='$style'/>";
				}
			}
		}
		$attributes .= ($diagonalDown) ? "diagonalDown='true' " : "diagonalDown='false' ";
		$attributes .= ($diagonalUp) ? "diagonalUp='true' " : "diagonalUp='false' ";
		$xml = "<border $attributes>$elements</border>";
	}
	# Cell or column style definitions
	elsif($type eq 'cell' || $type eq 'column') {
		# msxmlStyleAdd("cell/column","name","applyAlignment,applyProtection,border=name,fill=name,font=name,number=name,
		#		horizontal=general,indent=0,textRotation=0,vertical=bottom,shrinkToFit,wrapText,hidden,locked");
		@params = split(/,/,$parameters);
		$applyBorder = $applyFill = $applyFont = $applyNumberFormat = $shrinkToFit = $wrapText = $hidden = $locked = 0;
		$applyAlignment = 0;
		$applyProtection = 0;

		# Create attributes
		foreach my $param (@params) {
			# 'xf' element
			$id = (split(/=/,$param))[1];
			if($param =~ 'border') {
				if($MSXML_STYLE{"border-$id"}) {
					$attr_xf .= "borderId='".(@{$MSXML_STYLE{"border-$id"}})[0]."' ";
					$applyBorder = 1;
				}
			}
			elsif($param =~ 'fill') {
				if($MSXML_STYLE{"fill-$id"}) {
					$attr_xf .= "fillId='".(@{$MSXML_STYLE{"fill-$id"}})[0]."' ";
					$applyFill = 1;
				}
			}
			elsif($param =~ 'font') {
				if($MSXML_STYLE{"font-$id"}) {
					$attr_xf .= "fontId='".(@{$MSXML_STYLE{"font-$id"}})[0]."' ";
					$applyFont = 1;
				}
			}
			elsif($param =~ 'number') {
				if($MSXML_STYLE{"number-$id"}) {
				$attr_xf .= "numFmtId='".(@{$MSXML_STYLE{"number-$id"}})[0]."' ";
				$applyNumberFormat = 1;
				}
			}
			# 'alignment' element
			if($param =~ 'shrinkToFit')	     { $shrinkToFit = 1; }
			if($param =~ 'wrapText')		{ $wrapText = 1; }
			if($param =~ 'horizontal')	      { $attr_align .= "horizontal='".(split(/=/,$param))[1]."' "; $applyAlignment = 1; }
			if($param =~ 'vertical')		{ $attr_align .= "vertical='".(split(/=/,$param))[1]."' "; $applyAlignment = 1; }
			if($param =~ 'indent')		  { $attr_align .= "indent='".(split(/=/,$param))[1]."' "; }
			if($param =~ 'textRotation')    { $attr_align .= "textRotation='".(split(/=/,$param))[1]."' "; }
			# 'protection' element
			if($param =~ 'hidden')		  { $hidden = 1; }
			if($param =~ 'locked')		  { $locked = 1; $applyProtection = 1; }
		}
		# 'xf' element
		$attr_xf .= ($applyAlignment)	   ? "applyAlignment='true' " : "applyAlignment='false' ";
		$attr_xf .= ($applyBorder)		      ? "applyBorder='true' " : "applyBorder='false' ";
		$attr_xf .= ($applyFill)			? "applyFill='true' " : "applyFill='false' ";
		$attr_xf .= ($applyFont)			? "applyFont='true' " : "applyFont='false' ";
		$attr_xf .= ($applyNumberFormat)	? "applyNumberFormat='true' " : "applyNumberFormat='false' ";
		$attr_xf .= ($applyProtection)	  ? "applyProtection='true' " : "applyProtection='false' ";
		# 'alignment' element
		$attr_align .= ($shrinkToFit)	   ? "shrinkToFit='true' " : "shrinkToFit='false' ";
		$attr_align .= ($wrapText)		      ? "wrapText='true' " : "wrapText='false' ";
		# 'protection' element
		$attr_prot .= ($hidden)			 ? "hidden='true' " : "hidden='false' ";
		$attr_prot .= ($locked)			 ? "locked='true' " : "locked='false' ";
		$xml = "<xf $attr_xf><alignment $attr_align/><protection $attr_prot/></xf>";
	}
	# Fill definitions
	elsif($type eq 'fill') {
		# msxmlStyleAdd("fill","name","pattern=solid,front=FF4F81BD,back=FF1281F3");
		@params = split(/,/,$parameters);
		$elements = $attributes = " ";
		foreach my $param (@params) {
			if($param =~ 'pattern') { $attributes = "patternType='".(split(/=/,$param))[1]."'"; }
			if($param =~ 'front') { $elements .= "<fgColor rgb='".(split(/=/,$param))[1]."'/>"; }
			if($param =~ 'back') { $elements .= "<bgColor rgb='".(split(/=/,$param))[1]."'/>"; }
		}
		$xml = "<fill><patternFill $attributes>$elements</patternFill></fill>";
	}
	# Font definitions
	elsif($type eq 'font') {
		# msxmlStyleAdd("font","name","name=Arial,size=16,colour=FF4F81BD,bold,italic,underline=single");
		@params = split(/,/,$parameters);
		foreach my $param (@params) {
			if($param =~ 'name') { $elements .= "<name val='".(split(/=/,$param))[1]."'/>"; }
			if($param =~ 'size') { $elements .= "<sz val='".(split(/=/,$param))[1]."'/>"; }
			if($param =~ 'colour') { $elements .= "<color rgb='".(split(/=/,$param))[1]."'/>"; }
			if($param =~ 'bold') { $elements .= "<b val='true'/>"; }
			if($param =~ 'italic') { $elements .= "<i val='true'/>"; }
			if($param =~ 'underline') { $elements .= "<u val='".(split(/=/,$param))[1]."'/>"; }
		}
		$xml = "<font>$elements</font>";
	}
	# Number formats
	elsif($type eq 'number') {
		# msxmlStyleAdd("number","name","picture=£#,##0.00;[RED]&quot;-£&quot;#,##0.00");
		@params = split(/,/,$parameters,2);
		$attributes .= "numFmtId='".$MSXML_TRACK{$type}."' ";
		foreach my $param (@params) {
			if($param =~ 'picture') { $attributes .= "formatCode='".(split(/=/,$param))[1]."' "; }
		}
		$xml = "<numFmt $attributes/>";
	}

	# Read the next sequence for the style, add the style definition to the styles hash, keyed by
	# style {type-name} then increment the sequence for the style and store
	if($type eq 'cell' || $type eq 'column') {
		$MSXML_STYLE{"$type-$name"} = [($MSXML_TRACK{xf},$xml)];
		$MSXML_TRACK{xf}++;
	}
	else {
		$MSXML_STYLE{"$type-$name"} = [($MSXML_TRACK{$type},$xml)];
		$MSXML_TRACK{$type}++;
	}

	# Return undef for success
	return;
}



# ---------------------------------------------------------------------------------------------
# Create style definitions without data
#
# Return null if successful, or a message if an error raised
# ---------------------------------------------------------------------------------------------
sub msxmlStyleDefinition {
	my($fh,$file,$xml,$style);
	$file = msxmlGetParameter('ROOT')."/xl/styles.xml";

	# Open the document and write the header
	open($fh,">$file");
	if(!$fh) {
		return "Can't create $file";
	}
	$xml = new XML::Writer(OUTPUT => $fh, UNSAFE => 1);
	$xml->xmlDecl($MSXML_ENCODING);

	# Generate the document
	$xml->startTag("styleSheet","xmlns"=>"http://schemas.openxmlformats.org/spreadsheetml/2006/main");
	$style = "<numFmts>";
	$style .= msxmlStyleXML('number');
	$style .= "</numFmts>";
	$style .= "<fonts>";
	$style .= msxmlStyleXML('font');
	$style .= "</fonts>";
	$style .= "<fills>";
	$style .= msxmlStyleXML('fill');
	$style .= "</fills>";
	$style .= "<borders>";
	$style .= msxmlStyleXML('border');
	$style .= "</borders>";
	# ---------
	# WORKS OK IF THIS ISN'T INCLUDED
	#$style .= "<cellStyleXfs>";
	#$style .= "<xf applyAlignment='true' applyBorder='true' applyFont='true' applyProtection='true' borderId='0' fillId='0' fontId='0' numFmtId='164'>";
	#$style .= "<alignment horizontal='general' indent='0' shrinkToFit='false' textRotation='0' vertical='bottom' wrapText='false'/>";
	#$style .= "<protection hidden='false' locked='true'/>";
	#$style .= "</xf>";
	#$style .= "</cellStyleXfs>";
	# ---------
	$style .= "<cellXfs>";
	$style .= msxmlStyleXML('xf');
	$style .= "</cellXfs>";
	$xml->raw($style);
	$xml->endTag("styleSheet");

	# Close the document
	$xml->end();
	$fh->close();

	# Return undef for success
	return;
}



# ---------------------------------------------------------------------------------------------
# Return the XML definitions for all styles within a single type
#
# Argument 1 : Style type
# ---------------------------------------------------------------------------------------------
sub msxmlStyleXML {
	my($typename) = @_;
	my($type,$name,$seq,$xml,%temp,$style);

	# Extract the XML for each style within the requested type
	foreach my $key (keys %MSXML_STYLE) {
		($type,$name) = split(/-/,$key,2);

		# Process border, fill, font and number definitions individually
		if($typename eq $type) {
			($seq,$xml) = @{$MSXML_STYLE{$key}};
			$seq = substr("00$seq",-3,3);
			$temp{$seq} = $xml;
		}

		# Process cell and column definitions together
		if($typename eq 'xf' && ($type eq 'cell' || $type eq 'column')) {
			($seq,$xml) = @{$MSXML_STYLE{$key}};
			$seq = substr("00$seq",-3,3);
			$temp{$seq} = $xml;
		}
	}

	# Compile the style definitions in the correct sequence
	foreach $seq (sort keys %temp) {
		$style .= $temp{$seq};
	}
	# Return the style definitions
	return $style;
}



# ---------------------------------------------------------------------------------------------
# Create a temporary directory structure
# ---------------------------------------------------------------------------------------------
sub msxmlTempDirectories {
	# Read root directory for document and add suffix so temporary directory can be deleted
	my $root = msxmlGetParameter('DIR');
	$root .= '/MSXML';
	msxmlSetParameter('ROOT',$root);

	# Delete directory if it already exists
	if(-d $root) {
		system "rm -R $root";
	}

	# Create the directory tree
	system("mkdir $root");
	system("mkdir $root/_rels");
	system("mkdir $root/docProps");
	system("mkdir $root/xl");
	system("mkdir $root/xl/_rels");
	system("mkdir $root/xl/worksheets");
}



# ---------------------------------------------------------------------------------------------
# Generate either the opening or closing container of a workbook
#
# Argument 1 : Open or close the workbook
# Argument 2 : Name of the workbook
#
# Return null if successful, or a message if an error raised
# ---------------------------------------------------------------------------------------------
sub msxmlWorkbook {
	my($action,$name) = @_;
	my($index,$file,$col,$low,$high,@cols,$dimension,$psr,$doc,$xpc,@nodes,$dim);

	# Create the opening container
	if($action eq 'open') {
		# Save the name of the workbook
		push(@MSXML_BOOKS,$name);
		$index = @MSXML_BOOKS;

		# Reset the row and column counters
		$MSXML[2] = 0;	  # Last row counter used
		$MSXML[5] = 0;	  # Highest column number

		# Open the document and write the header
		$file = msxmlGetParameter('ROOT')."/xl/worksheets/sheet$index.xml";
		open($MSXML[0],">$file");
		if(!$MSXML[0]) {
			return "Can't create $file";
		}
		$MSXML[1] = new XML::Writer(OUTPUT => $MSXML[0]);
		$MSXML[1]->xmlDecl($MSXML_ENCODING);

		# Static relationships
#		$MSXML[1]->startTag("worksheet");
		$MSXML[1]->startTag("worksheet","xmlns"=>"http://schemas.openxmlformats.org/spreadsheetml/2006/main","xmlns:r"=>"http://schemas.openxmlformats.org/officeDocument/2006/relationships");
		$MSXML[1]->startTag("sheetPr","filterMode"=>"false");
		$MSXML[1]->emptyTag("pageSetUpPr","fitToPage"=>$MSXML_PARAMS{FIT_TO_PAGE});
		$MSXML[1]->endTag("sheetPr");
		$MSXML[1]->emptyTag("dimension","ref"=>"REPLACE:ME");
		$MSXML[1]->startTag("sheetViews");
		$MSXML[1]->startTag("sheetView","colorId"=>"64","defaultGridColor"=>"true","rightToLeft"=>"false","showFormulas"=>"false","showGridLines"=>"true","showOutlineSymbols"=>"true","showRowColHeaders"=>"true","showZeros"=>$MSXML_PARAMS{SHOW_ZEROS},"tabSelected"=>"false","topLeftCell"=>"A1","view"=>"normal","windowProtection"=>"false","workbookViewId"=>"0","zoomScale"=>"100","zoomScaleNormal"=>"100","zoomScalePageLayoutView"=>"100");
		$MSXML[1]->emptyTag("selection","activeCell"=>"A1","activeCellId"=>"0","pane"=>"topLeft","sqref"=>"A1");
		$MSXML[1]->endTag("sheetView");
		$MSXML[1]->endTag("sheetViews");
		$MSXML[1]->emptyTag("printOptions","headings"=>$MSXML_PARAMS{HEADINGS},"gridLines"=>$MSXML_PARAMS{GRID_LINES},"gridLinesSet"=>$MSXML_PARAMS{GRID_LINES},"horizontalCentered"=>$MSXML_PARAMS{CENTRE_H},"verticalCentered"=>$MSXML_PARAMS{CENTRE_V});
		$MSXML[1]->emptyTag("pageMargins","left"=>$MSXML_PARAMS{MARGIN_LEFT},"right"=>$MSXML_PARAMS{MARGIN_RIGHT},"top"=>$MSXML_PARAMS{MARGIN_TOP},"bottom"=>$MSXML_PARAMS{MARGIN_BOTTOM},"header"=>$MSXML_PARAMS{MARGIN_HEADER},"footer"=>$MSXML_PARAMS{MARGIN_FOOTER});
		$MSXML[1]->emptyTag("pageSetup","blackAndWhite"=>"false","cellComments"=>"none","copies"=>"1","draft"=>"false","firstPageNumber"=>"0","fitToHeight"=>$MSXML_PARAMS{FIT_H},"fitToWidth"=>$MSXML_PARAMS{FIT_W},"orientation"=>$MSXML_PARAMS{ORIENTATION},"pageOrder"=>"downThenOver","paperSize"=>"9","scale"=>$MSXML_PARAMS{SCALE},"useFirstPageNumber"=>"false","usePrinterDefaults"=>"false","horizontalDpi"=>"300","verticalDpi"=>"300");
		$MSXML[1]->startTag("headerFooter","differentFirst"=>"false","differentOddEven"=>"false");
		$MSXML[1]->emptyTag("oddHeader");
		$MSXML[1]->emptyTag("oddFooter");
		$MSXML[1]->endTag("headerFooter");
	}
	else {
		# Create the closing container and close the document
		$MSXML[1]->endTag("worksheet");
		$MSXML[1]->end();
		$MSXML[0]->close();
return;

		# Work out max area of data on sheet.  Convert last column index into one or more letters
		$col = $MSXML[5];
		$low = $col - 26*int($col/26);
		$high = int($col/26);
		@cols = split(//,'ABCDEFGHIJKLMNOPQRSTUVWXYZ');
		$dimension = ($high > 0) ? $cols[$high-1].$cols[$low] : $cols[$low];
		$dimension = "A1:".$dimension.$MSXML[2];

		# Open and parse the XML file that has just been closed so that the dimension can be updated
		for(my $i=0; $i<@MSXML_BOOKS; $i++) {
			if($MSXML_BOOKS[$i] eq $name) { $index = $i+1; }
		}
		$file = msxmlGetParameter('ROOT')."/xl/worksheets/sheet$index.xml";
		$psr = XML::LibXML->new();
		$doc = $psr->parse_file($file);
		$xpc = XML::LibXML::XPathContext->new($doc);

		# Read the current dimension attribute
		@nodes = $xpc->findnodes("/worksheet/dimension");
		$dim = $nodes[0]->getAttribute("ref");

		# Replace the dimension attribute
		$nodes[0]->setAttribute("ref",$dimension);

		# Save the change
		$doc->toFile($file);
	}

	# Return undef for success
	return;
}



# ---------------------------------------------------------------------------------------------
# Create the Workbook definitions
#
# Return null if successful, or a message if an error raised
# ---------------------------------------------------------------------------------------------
sub msxmlWorkbooks {
	my($file,$index,$fh,$xml);
	$file = msxmlGetParameter('ROOT')."/xl/workbook.xml";
	$index = 1;

	# Open the document and write the header
	open($fh,">$file");
	if(!$fh) {
		return "Can't create $file";
	}
	$xml = new XML::Writer(OUTPUT => $fh);
	$xml->xmlDecl($MSXML_ENCODING);

	# Static relationships
	$xml->startTag("workbook","xmlns"=>"http://schemas.openxmlformats.org/spreadsheetml/2006/main","xmlns:r"=>"http://schemas.openxmlformats.org/officeDocument/2006/relationships");
	$xml->emptyTag("fileVersion","appName"=>"Calc");
	$xml->emptyTag("workbookPr","backupFile"=>"false","showObjects"=>"all","date1904"=>"false");
	$xml->emptyTag("workbookProtection");
	$xml->emptyTag("calcPr","iterateCount"=>"100","refMode"=>"R1C1","iterate"=>"false","iterateDelta"=>"0.001");
	$xml->startTag("bookViews");
	$xml->emptyTag("workbookView","activeTab"=>"0","firstSheet"=>"0","showHorizontalScroll"=>"true","showSheetTabs"=>"true","showVerticalScroll"=>"true","tabRatio"=>"600","windowHeight"=>"8192","windowWidth"=>"16384","xWindow"=>"0","yWindow"=>"0");
	$xml->endTag("bookViews");

	# Workbook definitions
	$xml->startTag("sheets");
	foreach my $sheet (@MSXML_BOOKS) {
		$xml->emptyTag("sheet","name"=>"$sheet","sheetId"=>"$index","state"=>"visible","r:id"=>"rId".(2+$index));
		$index++;
	}
	$xml->endTag("sheets");
	$xml->endTag("workbook");

	# Close the document
	$xml->end();
	$fh->close();

	# Return undef for success
	return;
}



# ---------------------------------------------------------------------------------------------
# Create the Workbook relationships
#
# Return null if successful, or a message if an error raised
# ---------------------------------------------------------------------------------------------
sub msxmlWorkbookRelations {
	my($file,$index,$fh,$xml);
	$file = msxmlGetParameter('ROOT')."/xl/_rels/workbook.xml.rels";
	$index = 1;

	# Open the document and write the header
	open($fh,">$file");
	if(!$fh) {
		return "Can't create $file";
	}
	$xml = new XML::Writer(OUTPUT => $fh);
	$xml->xmlDecl($MSXML_ENCODING);

	# Static relationships
	$xml->startTag("Relationships","xmlns"=>"http://schemas.openxmlformats.org/package/2006/relationships");
	$xml->emptyTag("Relationship","Id"=>"rId1","Type"=>"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles","Target"=>"styles.xml");
	$xml->emptyTag("Relationship","Id"=>"rId2","Type"=>"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings","Target"=>"sharedStrings.xml");		     # rId4 -> rId2

	# Relationships for each worksheet
	foreach my $sheet (@MSXML_BOOKS) {
		$xml->emptyTag("Relationship","Id"=>"rId".(2+$index),"Type"=>"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet","Target"=>"worksheets/sheet$index.xml");
		$index++;
	}
	$xml->endTag("Relationships");

	# Close the document
	$xml->end();
	$fh->close();

	# Return undef for success
	return;
}





# *********************************************************************************************
# *********************************************************************************************
#
# Defaults and possible values
#
# *********************************************************************************************
# *********************************************************************************************

# ---------------------------------------------------------------------------------------------
# Default spreadsheet settings
# ---------------------------------------------------------------------------------------------
#       CENTRE_H		= 'true'
#       CENTRE_V		= 'false'
#       FIT_TO_PAGE	     = 'false'
#       FIT_H		   = 'true'
#       FIT_W		   = 'true'
#       GRID_LINES	      = 'false'
#       HEADINGS		= 'false'
#       MARGIN_LEFT	     = 0.5
#       MARGIN_RIGHT    = 0.5
#       MARGIN_TOP	      = 0.5
#       MARGIN_BOTTOM   = 0.5
#       MARGIN_HEADER   = 0.5
#       MARGIN_FOOTER   = 0.5
#       ORIENTATION	     = 'portrait'
#       ROW_HEIGHT	      = 12.6
#       SCALE		   = 100
#       SHOW_ZEROS	      = 'true'

# ---------------------------------------------------------------------------------------------
# Default styles
# ---------------------------------------------------------------------------------------------
#       TYPE    NAME    SETTINGS
#       number  normal  picture=GENERAL
#       font    normal  name=Arial,size=10
#       fill    normal  pattern=none
#       border  normal  left=0,right=0,top=0,bottom=0
#       cell    normal  border=normal,fill=normal,font=normal,number=normal

# ---------------------------------------------------------------------------------------------
# Style settings that can be changed
# ---------------------------------------------------------------------------------------------
#       TYPE    SETTINGS
#       border
#		       left=thin,hair
#		       right=medium:FF4F81BD
#		       top=thick
#		       bottom=double
#		       diagonal=thin
#		       diagonalDown
#		       diagonalUp
#       cell or column
#		       applyAlignment
#		       applyProtection
#		       border=name
#		       fill=name
#		       font=name
#		       number=name
#		       horizontal=general
#		       indent=0
#		       textRotation=0
#		       vertical=bottom
#		       shrinkToFit
#		       wrapText
#		       hidden
#		       locked
#       fill
#		       pattern=solid
#		       front=FF4F81BD
#		       back=FF1281F3
#       font
#		       name=Arial
#		       size=16
#		       colour=FF4F81BD
#		       bold
#		       italic
#		       underline=single
#       number
#		       picture=£#,##0.00;[RED]&quot;-£&quot;#,##0.00
#			       0
#			       0.00
#			       #,##0
#			       #,##0.00
#			       $#,##0_);($#,##0)
#			       $#,##0_);[Red]($#,##0)
#			       $#,##0.00_);($#,##0.00)
#			       $#,##0.00_);[Red]($#,##0.00)
#			       0%
#			       0.00%
#			       0.00E+00
#			       m/d/yyyy
#			       d-mmm-yy
#			       d-mmm
#			       mmm-yy
#			       h:mm AM/PM
#			       h:mm:ss AM/PM
#			       h:mm
#			       h:mm:ss
#			       m/d/yyyy h:mm
#			       #,##0_);(#,##0)
#			       #,##0_);[Red](#,##0)
#			       #,##0.00_);(#,##0.00)
#			       #,##0.00_);[Red](#,##0.00)
#			       mm:ss
#			       [h]:mm:ss
#			       mm:ss.0
#			       ##0.0E+0
#			       @
