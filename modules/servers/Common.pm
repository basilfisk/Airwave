#!/usr/bin/perl
# ***************************************************************************
# ***************************************************************************
#
# Common general purpose functions and common content processing functions
#
# ***************************************************************************
# ***************************************************************************

# Declare modules
use strict;
use warnings;

# System modules
use Digest::MD5;
use Encode qw(decode encode);
use Unicode::Normalize;
use IO::File;
use IO::Socket;
use IO::Socket::INET;
use Socket;
use XML::LibXML;

# API module
use lib "$ENV{'AIRWAVE_ROOT'}";
use mods::API3 qw(apiDML apiStatus);

# Declare the package name and export the function names
package mods::Common;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(cleanNonUTF8 cleanNonAlpha cleanString cleanXML ellipsis escapeSpecialChars formatDateTime
				 formatNumber logMsg logMsgPortal md5Generate metadataJsonToXML msgCache msgLog parseDocument processInfo
				 readConfig readConfigXML validFormat validNumber wrapText writeFile);

# Read the configuration parameters and check that parameters have been read
our %CONFIG  = readConfig("$ENV{'AIRWAVE_ROOT'}/etc/airwave.conf");

# Location of the common log file
our $COMMON_LOG = "$ENV{'AIRWAVE_ROOT'}/$CONFIG{COMMON_LOG}";

# Session number
our $SESSION;

# Pointer to socket for Server
our $SOCKET;

1;





# ***************************************************************************
# ***************************************************************************
#
# Common general purpose functions
#
# ***************************************************************************
# ***************************************************************************

# ---------------------------------------------------------------------------------------------
# Convert odd characters in a string to UTF-8 equivalents
#
# Argument 1 : String to be cleaned
#
# Return (1,cleansed string) or (0,original string) if invalid character found in string
# ---------------------------------------------------------------------------------------------
sub cleanNonUTF8 {
	my($string) = @_;

	$string =~ s/[^[:ascii:]]+//g;
	return (1,$string);
}



# ---------------------------------------------------------------------------------------------
# Strip all non-alphanumeric characters from a string
#
# Argument 1 : String to be cleaned
#
# Return cleaned-up string
# ---------------------------------------------------------------------------------------------
sub cleanNonAlpha {
	my($str) = @_;
	$str =~ s/[^a-zA-Z0-9]//g;
	return $str;
}



# ---------------------------------------------------------------------------------------------
# Strip leading, trailing and internal whitespace from a string
#
# Argument 1 : String to be cleaned
#
# Return cleaned-up string
# ---------------------------------------------------------------------------------------------
sub cleanString {
	my($txt) = @_;
	if(defined($txt)) {
		for($txt) {
			s/^\s+//;		# Remove leading whitespace
			s/\s+$//;		# Remove trailing whitespace
			s/\s+/ /g;		# Collapse internal whitespace to a single space
		}
	}
	return $txt;
}



# ---------------------------------------------------------------------------------------------
# Replace all XML reserved characters from a text string
#
# Argument 1 : Text string
#
# Return the cleansed text string
# ---------------------------------------------------------------------------------------------
sub cleanXML {
	my($text) = @_;
	$text =~ s/&/&amp;/g;
	$text =~ s/</&lt;/g;
	$text =~ s/>/&gt;/g;
	$text =~ s/"/&quot;/g;
	$text =~ s/'/&apos;/g;
	return $text;
}



# ---------------------------------------------------------------------------------------------
# Truncate string and add an ellipsis if it's too long
#
# Argument 1 : String of text
# Argument 2 : Maximum number of characters on a line
#
# Return new string
# ---------------------------------------------------------------------------------------------
sub ellipsis {
	my($text,$len) = @_;
	my(@words,$str,@new);

	# Split string into array of words and initialise new string
	@words = split(' ',$text);
	$str = "";

	# Loop through words
	for(my $w=0; $w<@words; $w++) {
		# If length of new string and next word is less than max length, add next word and a space
		if(length($str)+length($words[$w]) <= $len) {
			$str .= $words[$w]." ";
		}
	}

	# Remove last space
	$str =~ s/\s+$//g;

	# If new string has less words than original, add an ellipsis
	@new = split(/ /,$str);
	$str .= (@words > @new) ? '...' : "";
	return $str;
}



# ---------------------------------------------------------------------------------------------
# Escape special characters in the string
#
# Argument 1 : String to be processed
#
# Return the string with special characters escaped
# ---------------------------------------------------------------------------------------------
sub escapeSpecialChars {
	my($str) = @_;
	$str =~ s/ /\\ /g;
	$str =~ s/'/\\'/g;
	$str =~ s/\(/\\\(/g;
	$str =~ s/\)/\\\)/g;
	return $str;
}



# ---------------------------------------------------------------------------------------------
# Return the date and time as a string. Here are some example:
#    DD/MM/YYYY HH:MI:SS        --> formatDateTime('zd/zm/cczy zh24:mi:ss')
#    Day, DD Mon YYYY HH:MI:SS  --> formatDateTime('wd, zd mon cczy zh24:mi:ss')
#    YYMMDD-HHMISS (default)    --> formatDateTime('zyzmzd-zh24miss')
#    YYYY-MM-DDTHH:MI:SS        --> formatDateTime('cczy-zm-zdsfzh24:mi:ss') (XPath format)
#
# Argument 1 = Format of the timestamp
#				zd		= Day of month with leading zero
#				dd		= Day of month without leading zero
#				sf		= Day of month suffix (st,nd,rd,th)
#				wd		= Day of week (Sun,Mon...)
#				wf		= Day of week (Sunday,Monday...)
#				zm		= Month number with leading zero
#				mm		= Month number without leading zero
#				Mon		= Abbreviated month name (Mar,Sep)
#				Month	= Full month name (March,September)
#				cc		= Century
#				zy		= Year number with leading zero
#				yy		= Year number without leading zero
#				zh24	= 24 hour with leading zero
#				hh24	= 24 hour without leading zero
#				zh		= 12 hour with leading zero
#				hh		= 12 hour without leading zero
#				mi		= Minutes with leading zero
#				ss		= Seconds with leading zero
# Argument 2 = Time stamp to be formatted (optional).  Will use localtime() if no argument
# ---------------------------------------------------------------------------------------------
sub formatDateTime {
	# Read the arguments
	my($format,@time) = @_;
	my(@ts,$sec,$min,$hr,$day,$mth,$yr,$dow);
	my($cc,$yy,$zy,$mm,$zm,$mon,$month,$dd,$wd,$wf,$sf,$hh24,$hh,$zh24,$zh,$am,$mi,$ss);

	# Check if time argument is present, if NULL then use localtime()
	if(scalar(@time) == 0) { @time = localtime(); }

	# Check if format argument is present, if NULL then use default format
	if(!$format) { $format = 'zd/zm/yy hh24:mi:ss'; }

	# Assign array to scalar variables
	($sec,$min,$hr,$day,$mth,$yr,$dow) = @time;

	# Format dates
	$cc = substr("00".(1900+$yr),-4,2);
	$zy = substr("00".$yr,-2,2);
	$yy = $yr-100;
	$mon = ("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec")[$mth];
	$month = ("January","February","March","April","May","June","July","August","September","October","November","December")[$mth];
	$mth++;
	$mm = substr("00".$mth,-2,2);
	$dd = substr("00".$day,-2,2);
	$wd = ("Sun","Mon","Tue","Wed","Thu","Fri","Sat")[$dow];
	$wf = ("Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday")[$dow];
	$sf = ("st","nd","rd","th","th","th","th","th","th","th","th","th","th","th","th","th","th","th","th","th","st","nd","rd","th","th","th","th","th","th","th","st")[$day];

	# Format times
	if($hr > 12) {
		$hh = $hr - 12;
		$am = 'pm';
	}
	else {
		$hh = $hr;
		$am = 'am';
	}
	$zh24 = substr("00".$hr,-2,2);
	$hh24 = $hr;
	$zh = substr("00".$hh,-2,2);
	$mi = substr("00".$min,-2,2);
	$ss = substr("00".$sec,-2,2);

	# Convert format string to uppercase
	$format =~ tr/a-z/A-Z/;

	# Substitute dates
	$format =~ s/CC/$cc/g;
	$format =~ s/YY/$yy/g;
	$format =~ s/ZY/$zy/g;
	$format =~ s/MM/$mth/g;
	$format =~ s/ZM/$mm/g;
	$format =~ s/MONTH/$month/g;
	$format =~ s/MON/$mon/g;
	$format =~ s/DD/$day/g;
	$format =~ s/ZD/$dd/g;
	$format =~ s/WD/$wd/g;
	$format =~ s/WF/$wf/g;
	$format =~ s/SF/$sf/g;

	# Substitute times
	$format =~ s/HH24/$hh24/g;
	$format =~ s/ZH24/$zh24/g;
	$format =~ s/HH/$hh/g;
	$format =~ s/ZH/$zh/g;
	$format =~ s/MI/$mi/g;
	$format =~ s/SS/$ss/g;
	$format =~ s/AM/$am/g;

	return $format;
}



# ---------------------------------------------------------------------------------------------
# Format a number according to the format string
#
# Argument 1 : Number
# Argument 2 : Format string (optional)
#
# Return - formatted string if format argument is present
#        - original string if format argument is not present
#        - original string if number is not valid
# ---------------------------------------------------------------------------------------------
sub formatNumber {
	my($num,$fmt) = @_;
	my($neg,$int,$flt,$bkt,@both,@format,@number,$foundz,$chr,$idx,$tmp,$str);

	# Return original string if no format string is passed as an argument
	if(!$fmt) { return $num; }

	# Return undef if the number is empty
	if(!$num || $num eq ' ') { return undef; }

	# Validate the number and return original string if it is not a valid number
	if(!validNumber($num)) { return $num; }

	# Determine positive/negative, integer part, float part
	$neg = ($num < 0) ? 1 : 0;
	$int = int(abs($num));
	$flt = abs($num)-$int;

	# Ensure format string is lower case
	$fmt =~ tr/A-Z/a-z/;

	# Determine whether brackets should be used for negative numbers, then remove brackets
	$bkt = ($fmt =~ /\(/) ? 1 : 0;
	$fmt =~ s/\(//g;
	$fmt =~ s/\)//g;

	# Split format string into their integer and floating parts
	@both = split(/\./,$fmt);

	# Format the integer part of the number
	# Split format string and number into an array of 1 digit elements
	@format = split(/ */,$both[0]);
	@number = split(/ */,"$int");

	# Substitute zeros into format array
	$foundz = 0;
	for(my $f=0; $f<@format; $f++) {
		if($foundz || $format[$f] eq 'z') {
			if($format[$f] ne ',') {
				$format[$f] = '0';
			}
			$foundz = 1;
		}
	}

	# Substitute number elements into format array
	$idx = @number - 1;
	for(my $f=0; $f<@format; $f++) {
		$chr = $format[@format-$f-1];
		if($chr eq 'n' || $chr eq '0') {
			if($idx >= 0) {
				$format[@format-$f-1] = $number[$idx];
			}
			$idx--;
		}
	}
	# Turn array into a string, then remove leading commas and spare n/z
	$str = join('',@format);
	$str =~ s/n,//g;
	$str =~ s/n//g;

	# Format the floating part of the number
	if($fmt =~ /\./) {
		# Format the floating part to the correct length, then get rid of the integer part
		$flt = sprintf("%.".length($both[1])."f",$flt);
		$flt = (split(/\./,$flt))[1];

		# Split format string and number into an array of 1 digit elements
		@format = split(/ */,$both[1]);
		@number = split(/ */,$flt);

		# Substitute zeros into format array (work backwards to find last 'z')
		$foundz = 0;
		for(my $f=@format-1; $f>=0; $f--) {
			if($foundz || $format[$f] eq 'z') {
				$format[$f] = '0';
				$foundz = 1;
			}
		}

		# Substitute number elements into format array
		for(my $f=0; $f<@number; $f++) {
			$format[$f] = $number[$f];
		}

		# Turn array into a string, then remove spare n/z
		$tmp = join('',@format);
		$tmp =~ s/[n|z]//g;
		$str = "$str.$tmp";
	}

	# Add a negative symbol
	if($neg) {
		if($bkt) { $str = "($str)"; }
		else { $str = "-$str"; }
	}

	# Return the formatted number
	return $str;
}



# ---------------------------------------------------------------------------------------------
# Write a message to the log file (if specified) or STDOUT
#
# Argument 1 : Log to file (1) or standard output (0)
# Argument 2 : Name of programme calling the logger
# Argument 3 : Message
# ---------------------------------------------------------------------------------------------
sub logMsg {
	my($log,$prog,$msg) = @_;
	my($file,$stamp,$fh);

	# Create log file name (remove extension first) and timestamp
	$file = $prog;
	$file =~ s/\.\w+$//;
	$file = "$CONFIG{LOGDIR}/$file.log";
	$stamp = formatDateTime('cczy/zm/zd zh24:mi:ss');

	# Write to log file if logging requested
	if($log) {
		if(open($fh,">>$file")) {
			print $fh "[$stamp] $msg\n";
			close($fh);
		}
	}
	# Write to standard output
	else {
		print "[$stamp] $msg\n";
	}
}



# ---------------------------------------------------------------------------------------------
# Write a message to the log file (if specified) or STDOUT
# In addition, write the message to the Portal
#
# Argument 1 : Log to file (1) or standard output (0)
# Argument 2 : Name of programme calling the logger
# Argument 3 : Type of message being logged (I=Info, E=Error, W=Warning)
# Argument 4 : Message
# ---------------------------------------------------------------------------------------------
sub logMsgPortal {
	my($log,$prog,$type,$msg) = @_;
	my($status,$result,%error,$file,$stamp,$code,$text);

	# Create log file name (remove extension first) and timestamp
	$file = $prog;
	$file =~ s/\.\w+$//;
	$file = "$CONFIG{LOGDIR}/$file.log";
	$stamp = formatDateTime('zd mon cczy zh24:mi:ss');

	# Convert type to uppercase and expand to full description
	$type =~ tr[a-z][A-Z];
	   if($type eq 'E') { $type = 'Error'; }
	elsif($type eq 'I') { $type = 'Information'; }
	elsif($type eq 'W') { $type = 'Warning'; }

	# Write to log file if logging requested and if log file exists
	if($log && -f $file) {
		logMsg($log,$prog,$msg);

		# Remove single and double quotes from the message
		$msg =~ s/\'//g;
		$msg =~ s/\"//g;

		# Write the message to the Portal
		($result) = mods::API3::apiDML('logMessage',"type=$type","prog=$prog","stamp=$stamp","msg=$msg");
		($status,%error) = mods::API3::apiStatus($result);
		if(!$status) {
			# Any problems writing to Portal should be logged
			if(%error) {
				$code = ($error{CODE}) ? $error{CODE} : "Unknown";
				$text = ($error{MESSAGE}) ? $error{MESSAGE} : "No error message text returned";
				logMsg($log,$prog,"[$code] $text");
			}
			logMsg($log,$prog,"Can't write '$type' message to the Portal: $msg");
		}
	}
	# In all other cases, write message to standard out
	else {
		logMsg($log,$prog,$msg);
	}
}



# ---------------------------------------------------------------------------------------------
# Generate the MD5 digest for the file
#
# Argument 1 : Full name of the file to be validated
#
# Return the MD5 checksum, or undef if file not processed
# ---------------------------------------------------------------------------------------------
sub md5Generate {
	my($file) = @_;
	my($fh,$ctx,$md5);

	$fh = new IO::File("<$file");
	if($fh) {
		$ctx = Digest::MD5->new;
		$ctx->addfile($fh);
		$md5 = $ctx->hexdigest;
		$fh->close();
		return $md5;
	}
	else { return; }
}



# ---------------------------------------------------------------------------------------------
# Convert content metadata in JSON format to XML
#
# Argument 1 : Asset code
# Argument 2 : Metadata hash

# Return an XML string
# ---------------------------------------------------------------------------------------------
sub metadataJsonToXML {
	my($filmcode,%meta) = @_;
	my($xml,@arr,@arr2,%attr);

	# Header
	$xml = '<?xml version="1.0" encoding="UTF-8"?>';
	$xml .= '<metadata id="'.$filmcode.'" type="video" creator="Airwave" created="'.formatDateTime('zd/zM/ccyy zh24:mi:ss').'">';

	# General
	@arr = @{$meta{'release'}};
	$xml .= xml_element('release',$arr[0]{'release_date'});
	$xml .= xml_element('year',$arr[0]{'year'});
	$xml .= xml_element('certificate',$arr[0]{'certificate'});
	$xml .= xml_element('duration',$arr[0]{'running_time'});
	$xml .= xml_element('imdb',$arr[0]{'imdb'});
	$xml .= '<provider>';
	$xml .= xml_element('name',$arr[0]{'provider'});
	$xml .= xml_element('reference',$arr[0]{'provider_ref'});
	$xml .= '</provider>';

	# Images
	undef %attr;
	@arr = @{$meta{'images'}};
	$xml .= '<images>';
	for(my $i=0; $i<@arr; $i++) {
		$attr{'type'} = $arr[$i]{'type'};
		$attr{'height'} = $arr[$i]{'height'};
		$attr{'width'} = $arr[$i]{'width'};
		$attr{'mimetype'} = $arr[$i]{'mimetype'};
		$xml .= xml_element_attribute('image',$arr[$i]{'name'},%attr);
	}
	$xml .= '</images>';

	# Territories
	undef %attr;
	@arr = @{$meta{'territories'}};
	$xml .= '<territories>';
	for(my $i=0; $i<@arr; $i++) {
		$attr{'id'} = $arr[$i]{'code'};
		$attr{'name'} = $arr[$i]{'name'};
		$xml .= xml_attribute('territory',%attr);
		$xml .= xml_element('encrypted',$arr[$i]{'encrypted'});
		$xml .= xml_element('clear',$arr[$i]{'clear'});
		$xml .= '</territory>';
	}
	$xml .= '</territories>';

	# Genres
	@arr = @{$meta{'genres'}};
	$xml .= '<genres>';
	for(my $i=0; $i<@arr; $i++) {
		$xml .= xml_element('genre',$arr[$i]{'name'});
	}
	$xml .= '</genres>';

	# Languages
	@arr = @{$meta{'synopses'}};
	$xml .= '<languages>';
	for(my $i=0; $i<@arr; $i++) {
		undef %attr;
		$attr{'name'} = $arr[$i]{'name'};
		$attr{'id'} = $arr[$i]{'code'};
		$xml .= xml_attribute('language',%attr);
		$xml .= xml_element('title',$arr[$i]{'title'});
		$xml .= xml_element('short',$arr[$i]{'short'});
		$xml .= xml_element('full',$arr[$i]{'full'});
		$xml .= '<credits>';
		$xml .= '<directors>';
		@arr2 = @{$arr[$i]{'directors'}};
		for(my $n=0; $n<@arr2; $n++) {
			$xml .= xml_element('director',$arr2[$n]);
		}
		$xml .= '</directors>';
		$xml .= '<actors>';
		@arr2 = @{$arr[$i]{'actors'}};
		for(my $n=0; $n<@arr2; $n++) {
			$xml .= xml_element('actor',$arr2[$n]);
		}
		$xml .= '</actors>';
		$xml .= '</credits>';
		$xml .= '</language>';
	}
	$xml .= '</languages>';

	# Sub-titles
	undef %attr;
	@arr = @{$meta{'subtitles'}};
	$xml .= '<subtitles>';
	for(my $i=0; $i<@arr; $i++) {
		$attr{'language'} = $arr[$i]{'language'};
		$xml .= xml_element_attribute('subtitle',$arr[$i]{'filename'},%attr);
	}
	$xml .= '</subtitles>';

	# Assets
	@arr = @{$meta{'assets'}};
	$xml .= '<assets>';
	for(my $i=0; $i<@arr; $i++) {
		undef %attr;
		$attr{'name'} = $arr[$i]{'name'};
		$attr{'class'} = $arr[$i]{'class'};
		$attr{'coding'} = $arr[$i]{'coding'};
		$attr{'type'} = $arr[$i]{'type'};
		$attr{'quality'} = $arr[$i]{'quality'};
		$attr{'size'} = $arr[$i]{'size'};
		$attr{'md5'} = $arr[$i]{'md5'};
		$attr{'program'} = '2';
		@arr2 = @{$arr[$i]{'streams'}};
		$attr{'streams'} = scalar(@arr2);
		$xml .= xml_attribute('asset',%attr);
		for(my $n=0; $n<@arr2; $n++) {
			undef %attr;
			$attr{'pid'} = $arr2[$n]{'pid'};
			$attr{'coding'} = $arr2[$n]{'coding'};
			$attr{'type'} = $arr2[$n]{'type'};
			$xml .= xml_attribute('stream',%attr);
			$xml .= xml_element('frame_size',$arr2[$n]{'frame_size'});
			$xml .= xml_element('aspect_ratio',$arr2[$n]{'aspect_ratio'});
			$xml .= xml_element('frame_rate',$arr2[$n]{'frame_rate'});
			$xml .= xml_element('encode_rate',$arr2[$n]{'encode_rate'});
			$xml .= xml_element('sample_rate',$arr2[$n]{'sample_rate'});
			$xml .= xml_element('channels',$arr2[$n]{'channels'});
			$xml .= xml_element('language',$arr2[$n]{'language'});
			$xml .= '</stream>';
		}
		$xml .= '</asset>';
	}
	$xml .= '</assets>';

	# Close the XML document and return the XML
	$xml .= "</metadata>";
	return $xml;
}



# ---------------------------------------------------------------------------------------------
# Create a hash of messages at start-up time which can then be used by the main message
# logging function to avoid parsing the XML each time a message is generated.
#
# Argument 1: Name of file holding the messages
#
# Return a hash containing all of the messages in the XML message file
# ---------------------------------------------------------------------------------------------
sub msgCache {
	my($file) = @_;
	my($err,$xpc,@nodes,$code,$type,$level,$text,%result);

	# Open the message file
	($err,$xpc) = parseDocument('file',$file);
	if(!$xpc) {
		msgWrite($COMMON_LOG,"msgCache: Cannot open message file: $file");
		exit;
	}

	# Read the messages from file
	@nodes = $xpc->findnodes('/messages/msg');
	foreach my $node (@nodes) {
		# Read the attributes and text
		$code = $node->getAttribute('id');
		$type = $node->getAttribute('type');
		$level = $node->getAttribute('level');
		$text = $node->textContent;

		# Write to a HoA
		$result{$code} = [($type,$level,$text)];
	}

	# Return the message hash
	return %result;
}



# ---------------------------------------------------------------------------------------------
# Log the error to file or return a message to the caller in XML format
#
# Argument 1 : Fully qualified name of the log file
# Argument 2 : Level of logging (verbosity)
# Argument 3 : Pointer to the hash of messages
# Argument 4 : Where should the message be output
#                'caller'      : Return message to caller as a string
#                'common'      : Write message to log file and return to calling function
#                'log'         : Write message to log file
#                'xml'         : Return the message in XML format
#                Anything Else : Return the message to the calling function
# Argument 5 : Reference number of the message
# Argument 6 : Additional information to be included in the message
# ---------------------------------------------------------------------------------------------
sub msgLog {
	my($log,$verbosity,$msg_ref,$opt,$code,@parameters) = @_;
	my($type,$level,$text,$str,$group,$status,$msg,$resp);
	my %msgs = %{$msg_ref};

	# Read text from the global message hash
	if($msgs{$code}) {
		($type,$level,$text) = @{$msgs{$code}};
	}
	# Trap invalid error numbers (not in hash)
	else {
		@parameters = ($code);
		($type,$level,$text) = (3,0,"msgLog: Error code [$code] does not exist in the message file");
		$code = 'E301';
	}

	# Skip messages if the level of verbosity if too much for configured setting
	if($level <= $verbosity) {
		# Substitute parameters
		for(my $i=0; $i<@parameters; $i++) {
			$str = "_p" . ($i + 1);
			if(defined($parameters[$i])) { $text =~ s/$str/$parameters[$i]/g; }
		}

		# Replace newline characters with spaces and remove trailing spaces
		$text =~ s/\n/ /g;
		$text =~ s/\s+$//;

		# Generate the message type and error status
		if($type == 0) {
			$group = 'information';
			$status = 1;
		}
		elsif($type == 1) {
			$group = 'error';
			$status = 0;
		}
		elsif($type == 2) {
			$group = 'debug';
			$status = 1;
		}
		else {
			$group = 'common';
			$status = 1;
		}

		# Build the message
		$msg = formatDateTime('cczy/zm/zd zh24:mi:ss')." # ".setSession('current')." # $group # $code # $text";

		# Return the message to the caller as a string
		if($opt eq 'caller') {
			return "$code: $text";
		}
		# Write the message to the log file and return to calling function
		elsif($opt eq 'common') {
			$resp = msgWrite($log,$msg);
			if($resp) { return $resp; }
			else { return $msg; }
		}
		# Write the message to the log file
		elsif($opt eq 'log') {
			$resp = msgWrite($log,$msg);
			if($resp) { return $resp; }
			else { return; }
		}
		# Return the message in XML format
		elsif($opt eq 'xml') {
			return "<status>$status</status><code>$code</code><message>$text</message>";
		}
		# Return the message as a text string
		else {
			return $msg;
		}
	}
}



# ---------------------------------------------------------------------------------------------
# Write a message to a log file.
#
# Argument 1: Log file
# Argument 2: Message text
#
# Return null if the message is written to the log file, otherwise return the message
# ---------------------------------------------------------------------------------------------
sub msgWrite {
	my($log,$msg) = @_;
	my($fh);
	my $stamp = formatDateTime('cczy/zm/zd zh24:mi:ss');

	# Open the log file in append mode
	if(!open($fh,">>$log")) {
		# Can't open log file
		print "[$stamp] Can't open log file [$log], however, this message has been reported: $msg\n";
		return $msg;
	}

	# Log the session ID
	print $fh "[$stamp] $msg\n";
	close($fh);
	return;
}



# ---------------------------------------------------------------------------------------------
# Create a LibXML parser object, parse a string or file, and initialise XPath
#
# Argument 1 : Source of data to be parsed ('string' or 'file')
# Argument 2 : String containing the data, or the path/file name holding the data
#
# Return a null message and XPath context handle if OK
# Return an error message if an error is raised
# ---------------------------------------------------------------------------------------------
sub parseDocument {
	# Read the arguments and initialise variables
	my($src,$cmd) = @_;
	my($psr,$doc,$xpc);

	# Check that a string or file name has been provided
	if(!$cmd) {
		if($src eq 'string') {
			return "parseDocument: No string containing data has been provided";
		}
		else {
			return "parseDocument: No file name has been provided";
		}
	}

	# Create the parser object
	$psr = XML::LibXML->new();
	if(!$psr) {
		return "parseDocument: Cannot create a parser object for: $cmd";
	}

	# Parse the string or file
	if($src eq 'string') {
		eval { $doc = $psr->parse_string($cmd) };
		if($@) {
			return "parseDocument: Cannot parse the command: $cmd";
		}
	}
	else {
		eval { $doc = $psr->parse_file($cmd) };
		if($@) {
			return "parseDocument: Cannot parse the file: $cmd";
		}
	}

	# Create an XPath object for the parsed document
	$xpc = XML::LibXML::XPathContext->new($doc);
	if(!$xpc) {
		return "parseDocument: Cannot create an XPath object for: $cmd";
	}

	# Return OK (null error message) and the XPath context handle
	return ("",$xpc);
}



# ---------------------------------------------------------------------------------------------
# Return the process owner and process ID
# ---------------------------------------------------------------------------------------------
sub processInfo {
	# Initialise local variables
	my(@procs,$owner,$proc);

	# Extract the process owner and ID from the 1st matching record
	# Record 1 is the process running the test, 2 is the shell call to 'ps' and 3 is 'grep'
	@procs = `ps -ef | grep $$`;
	$owner = substr($procs[0],0,8);
	$owner =~ s/ //g;
	$proc = substr($procs[0],9,5);
	$proc =~ s/ //g;
	return ($owner,$proc);
}



# ---------------------------------------------------------------------------------------------
# Read the values from a configuration file.  Entries in the configuration are
# name/value pairs separated by an '=', with 1 pair/line.
#
# Argument 1 = URL to configuration file
#
# Return a hash keyed by name with the value
# ---------------------------------------------------------------------------------------------
sub readConfig {
	# Read argument and initialise local variables
	my($file) = @_;
	my($fhdl,$line,$key,$value,@array,%conf);

	# Read the configuration file
	open($fhdl,"< $file") or die "Cannot open file [$file]: $!";
	while($line = readline($fhdl)) {
		chomp($line);
		# Ignore lines with comments and empty lines
		if($line && !($line =~ m/#/)) {
			# Extract the key and the value
			($key,$value) = split('=',$line);

			# Remove all white space from the key and leading space from the value
			$key =~ s/\s*//g;
			$value =~ s/^\s*//g;

			# If comma separators in value string, create an array, otherwise scalar
			if($value =~ m/,/) {
				@array = split(',',$value);
				$conf{$key} = [ @array ];
			}
			else {
				$conf{$key} = $value;
			}
		}
	}
	return %conf;
}



# ---------------------------------------------------------------------------------------------
# Read a set of values from an API configuration file.
# If the search path is terminated with a slash then an array of values matching the list of
# parameters (elements/attributes) will be returned. If there is no terminating slash, the
# path is assumed to include the parameter and a single value will be returned.
#
# Argument 1: Fully qualified name of the configuration file
# Argument 2: Search path (XPath expression)
# Argument 3: List of parameters whose values are to be returned. The parameters will be
#             treated as element names unless prefixed with '@'.
#
# Return a list of values in the same sequence as the parameter list
# ---------------------------------------------------------------------------------------------
sub readConfigXML {
	# Read the arguments
	my($file,$path,@elements) = @_;
	my($psr,$doc,$xpc,$value,@nodes,@result);

	# Read DOM tree from file
	$psr = XML::LibXML->new();
	$doc = $psr->parse_file($file);
	$xpc = XML::LibXML::XPathContext->new($doc);

	# Read a node list of named elements
	if(@elements) {
		for(my $i=0; $i<@elements; $i++) {
			# Read attributes
			if($elements[$i] =~ /^\@/) {
				my $attr = $elements[$i];
				$attr =~ s/^\@//;
				my @node = $xpc->findnodes($path);
				$value = $node[0]->getAttribute($attr);
				if($value) { $result[$i] = $value; }
			}
			# Read elements
			else {
				$value = $xpc->findvalue($path.$elements[$i]);
				if($value) { $result[$i] = $value; }
			}
		}
	}
	# Read all nodes under the search path
	else {
		@nodes = $xpc->findnodes($path);
		foreach my $node (@nodes) {
			push(@result,$node->textContent);
		}
	}

	# Return the parameters
	return @result;
}



# ---------------------------------------------------------------------------------------------
# Manage the session identifier
#
# Argument 1: current : returns the current session ID
#			  update  : increments current ID and returns new ID
#
# Return session ID
# ---------------------------------------------------------------------------------------------
sub setSession {
	my($action) = @_;
	my($day,$ref);

	# If the session number has not been initialised yet, set to current date/time
	if(!$SESSION) {
		$SESSION = formatDateTime('zyzmzd-zh24miss');
	}
	# Increment the session number if it has already been set
	elsif($SESSION && $action eq 'update') {
		($day,$ref) = split(/-/,$SESSION);
		$ref++;
		$SESSION = $day."-".$ref;
	}
	# Return the session number
	else {
		return $SESSION;
	}
}



# ---------------------------------------------------------------------------------------------
# Validate the format string for a number "(£nnz,zzz.zn)"
#	^					# Start of string.
#	[-(]?				# Optional minus sign or left bracket.
#	\$?					# Optional pound, euro or dollar symbol.
#	(					# Begin integer part of number format.
#		,?				# Option comma ar start of string triplet.
#		(nnn|nnz|nzz|zzz) # Triplet must be one of these styles.
#	)*					# End group, can have 0 or more occurances.
#	(					# Begin optional decimal point group.
#	    \.				# The decimal point must be 1st character.
#	    z*n*			# Must have zero or more "z"s followed by zero or more "n"s.
#	)?					# End group, must have only 0 or 1 occurance.
#	\)?					# Optional right bracket. NB: THIS IS NOT MATCHED WITH THE LEFT BRACKET
#	$					# End of string.
#
# Argument 1 : Number
#
# Return 1 if valid, or 0 if invalid
# ---------------------------------------------------------------------------------------------
sub validFormat {
	my($value) = @_;

	# Quit if number to be checked is empty
	if(!$value) { return 1; }

	# Replace £ and € with $ for the regex
	$value =~ s/£/\$/g;
	$value =~ s/€/\$/g;

	# Check the format string
	if($value =~ /^[-(]?\$?(,?(nnn|nnz|nzz|zzz))*(\.z*n*)?\)?$/) { return 1; }
	return 0;
}



# ---------------------------------------------------------------------------------------------
# Validate the integrity of a number
#	^                   # Start of string.
#	-?                  # Optional minus sign.
#	[0-9]*              # Must have zero or more numbers.
#	(                   # Begin optional group.
#	    \.              # The decimal point.
#	    [0-9]*          # Zero or more numbers.
#	)?                  # End group, signify it's optional with ?
#	$                   # End of string.
#
# Argument 1 : Number
#
# Return 1 if valid, or 0 if invalid
# ---------------------------------------------------------------------------------------------
sub validNumber {
	my($value) = @_;
	if($value =~ /^-?[0-9]*(\.[0-9]*)?$/) { return 1; }
	return 0;
}



# ---------------------------------------------------------------------------------------------
# Wrap a string of text over multiple lines
#
# Argument 1 : String of text
# Argument 2 : Maximum number of characters on a line
# Argument 3 : Maximum number of lines
#
# Return new string, with lines delimited by "\n"
# ---------------------------------------------------------------------------------------------
sub wrapText {
	my($text,$len,$max) = @_;
	my(@words,$str,$lines,$new);

	# Split string into array of words, initialise string to hold line text and line counter
	@words = split(' ',$text);
	$str = $new = "";
	$lines = 0;

	# Loop through words
	for(my $w=0; $w<@words; $w++) {
		# Don't print too many lines
		if($lines < $max) {
			# Add word to current line
			if(length($str)+length($words[$w]) <= $len) {
				$str .= $words[$w]." ";
			}
			# Print current line then start a new line
			else {
				$new .= $str."\n";
				$str = $words[$w]." ";
				$lines++;
			}
		}
	}
	# Last line is within maximum allowed (no "\n" needed)
	if($lines < $max) {
		$new .= $str;
	}
}



# ---------------------------------------------------------------------------------------------
# Write a string to a file
#
# Argument 1: File name
# Argument 2: Text
#
# Return 1 if the string is written to the file, 0 if error
# ---------------------------------------------------------------------------------------------
sub writeFile {
	my($file,$text) = @_;
	my($fh);

	if(!open($fh,">$file")) {
		print "Can't open file [$file]\n";
		return 0;
	}
	print $fh $text;
	close($fh);
	return 1;
}



# ---------------------------------------------------------------------------------------------
# Create an opening XML element with attributes
#
# Argument 1 : Element name
# Argument 2 : Hash of attributes
#
# Return XML string
# ---------------------------------------------------------------------------------------------
sub xml_attribute {
	my($name,%attr) = @_;
	my($str);
	$str = '<'.$name;
	foreach my $id (keys %attr) {
		$str .= ' '.$id.'="'.cleanXML($attr{$id}).'"';
	}
	$str .= '>';
	return $str;
}



# ---------------------------------------------------------------------------------------------
# Create an XML element with a data value
#
# Argument 1 : Element name
# Argument 2 : Element value
#
# Return XML string
# ---------------------------------------------------------------------------------------------
sub xml_element {
	my($name,$value) = @_;
	my $str = '';
	if($value) {
		$str .= '<'.$name.'>';
		$str .= cleanXML($value);
		$str .='</'.$name.'>';
	}
	return $str;
}



# ---------------------------------------------------------------------------------------------
# Create an XML element with attributes and a data value
#
# Argument 1 : Element name
# Argument 2 : Element value
# Argument 3 : Hash of attributes
#
# Return XML string
# ---------------------------------------------------------------------------------------------
sub xml_element_attribute {
	my($name,$value,%attr) = @_;
	my($str);
	$str = '<'.$name;
	foreach my $id (keys %attr) {
		$str .= ' '.$id.'="'.cleanXML($attr{$id}).'"';
	}
	$str .= '>';
	$str .= cleanXML($value);
	$str .='</'.$name.'>';
	return $str;
}
