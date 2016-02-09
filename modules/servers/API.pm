#!/usr/bin/perl
# *********************************************************************************************
# *********************************************************************************************
# 
# Client side functions to send/receive XML messages to/from the Breato Gateway
#
# *********************************************************************************************
# *********************************************************************************************

# Declare modules
use strict;
use warnings;
use JSON::XS;

# Declare the package name and export the function names
package mods::API;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(apiData apiDML apiEmail apiFileDownload apiMetadata apiStatus apiSelect);

our %API;
$API{host}		= 'api.visualsaas.net';
$API{port}		= 8822;
$API{instance}	= 'airwave';
$API{key}		= '8950d855b82084a3229a8048698c5ead';

1;





# ---------------------------------------------------------------------------------------------
# Parse a response from the Gateway and extract the data or information records
#
# Argument 1 : JSON response message from the Gateway
#
# Return a hash with the data, information or error
# ---------------------------------------------------------------------------------------------
sub apiData {
	my($json) = @_;
	my($hash_ref,$msg,%hash,$item,$iteminitem,%new);
	my %error = ();

	# Check whether any data was returned
	if(!$json) {
		$error{STATUS} = 0;
		$error{CODE} = 'CLI006';
		$error{MESSAGE} = "No data returned by the Gateway";
		return %error;
	}

	# Convert JSON document to hash
	($hash_ref,$msg) = json_data($json);

	# Extract inner 'data' hash
	%hash = %$hash_ref{data};
	foreach $item (keys %hash) {
		foreach $iteminitem (keys %{$hash{$item}}) {
			$new{$iteminitem} = $hash{$item}{$iteminitem};
		}
	}
	return %new;
}



# ---------------------------------------------------------------------------------------------
# Run an SQL DML query
#
# Argument 1 : Function to be called
# Argument 2 : Array of arguments to the function (name=value)
#
# Return the JSON response
# ---------------------------------------------------------------------------------------------
sub apiDML {
	my($call,@params) = @_;
	
	# Processing for Select and DML commands is the same
	return apiSQL($call,@params);
}



# ---------------------------------------------------------------------------------------------
# Send an email message
#
# Argument 1+ : Array of message parameters
#
# Return the JSON response
# ---------------------------------------------------------------------------------------------
sub apiEmail {
	my(@params) = @_;
	my($cmd,$name,$value,$response);
	
	# Build the command
	$cmd = "curl -s -u $API{key}: 'https://$API{host}:$API{port}/2/msgEmail?instance=$API{instance}";
	
	# Add the parameters
	foreach my $param (@params) {
		# Strip out special characters
		$param =~ s/'//g;
		$param =~ s/&/and/g;
		$param =~ s/ /%20/g;
		# Split out name/value pair
		($name,$value) = split(/=/,$param);
#		# If value starts with a '<' add a leading space to stop curl interpreting this as a file name
#		if(substr($value,0,1) eq '<') {
#			$value = ' '.$value;
#		}
		# Add to command string
		$cmd .= "&$name=$value";
	}
	
	# Close the command
	$cmd .= "'";
	
	# Run the command and check the return code
	$response = `$cmd`;
	return check_response($response,$?,$!);
}



# ---------------------------------------------------------------------------------------------
# Download a file from the Portal
#
# Argument 1 : Name of source file
# Argument 2 : Path to source file
# Argument 3 : Name of target file
# Argument 4 : Path to target file
#
# Return the JSON response
# ---------------------------------------------------------------------------------------------
sub apiFileDownload {
	my($sfile,$sdir,$tfile,$tdir) = @_;
	my($cmd,$response,$msg);
	
	# Build the command
	$cmd = "curl -s -u $API{key}: -F instance=$API{instance} ";
	$cmd .= "-F source=$sdir/$sfile -o $tdir/$tfile ";
	$cmd .= "https://$API{host}:$API{port}/2/fileDownload";
	
	# Download the file
	$response = `$cmd`;
	
	# Check the start of the downloaded file to see if an error was returned
	if(-f "$tdir/$tfile") {
		$msg = `head -c 15 $tdir/$tfile`;
		if($msg =~ /{"status"/) {
			# Download failed
			$msg = `cat $tdir/$tfile`;
		}
		else {
			# Download succeeded
			$msg = "Download of file [$tdir/$tfile] was successful";
			$msg = '{"status":"1", "data": { "code":"CLI001", "text": "'.$msg.'"}}';
		}
	}
	# No response from API
	else {
		$msg = "Couldn't read file [$tdir/$tfile]";
		$msg = '{"status":"0", "data": { "code":"CLI002", "text": "'.$msg.'"}}';
	}
	return $msg;
}



# ---------------------------------------------------------------------------------------------
# Run a query to retrieve metadata
#
# Argument 1 : Function to be called
# Argument 2 : Asset reference
# Argument 3 : Format of results (xml/json)
#
# If successful return (1,data) otherwise (0,JSON error)
# ---------------------------------------------------------------------------------------------
sub apiMetadata {
	my($call,$assetcode,$format) = @_;
	my($cmd,$response);

	# Build the command
	$cmd = "curl -s -u $API{key}: 'https://$API{host}:$API{port}/2/$call?instance=$API{instance}";
	$cmd .= "&assetcode=$assetcode&format=$format'";

	# Run the command
	$response = `$cmd`;
	return check_response($response,$?,$!);
}



# ---------------------------------------------------------------------------------------------
# Run an SQL SELECT query
#
# Argument 1 : Function to be called
# Argument 2 : Array of arguments to the function (name=value)
#
# Return the JSON response
# ---------------------------------------------------------------------------------------------
sub apiSelect {
	my($call,@params) = @_;
	
	# Processing for Select and DML commands is the same
	return apiSQL($call,@params);
}



# ---------------------------------------------------------------------------------------------
# Run an SQL SELECT or DML query
#
# Argument 1 : Function to be called
# Argument 2 : Array of arguments to the function (name=value)
#
# Return the JSON response
# ---------------------------------------------------------------------------------------------
sub apiSQL {
	my($call,@params) = @_;
	my($cmd,$response);

	# Build the command
	$cmd = "curl -s -u $API{key}: 'https://$API{host}:$API{port}/2/$call?instance=$API{instance}";

	# Add the parameters
	foreach my $param (@params) {
		$param =~ s/ /%20/g;
		$cmd .= "&$param";
	}

	# Close the command
	$cmd .= "'";

	# Run the command and check the return code
	$response = `$cmd`;
	return check_response($response,$?,$!);
}



# ---------------------------------------------------------------------------------------------
# Parse a response from the Gateway and extract the status information
#
# Argument 1 : JSON response message from the Gateway
#
# Return the status information as a two element array
#   [1] Is the status (1=success, 0=failure)
#   [2] Is a hash {{status|code|text}
# ---------------------------------------------------------------------------------------------
sub apiStatus {
	my($json) = @_;
	my($hash_ref,$msg,$status);
	my %data = ();
	my %error = ();

	# Check whether any data was returned
	if(!$json) {
		$error{STATUS} = 0;
		$error{CODE} = 'CLI003';
		$error{MESSAGE} = "No data returned by the Gateway";
		return (0,%error);
	}
	
	# If an HTML tag is present, something went wrong with the CURL call
	if($json =~ m/HTML/i) {
		$error{STATUS} = 0;
		$error{CODE} = 'CLI004';
		$error{MESSAGE} = "Problem with the CURL call. Check arguments";
		return (0,%error);
	}
	
	# Convert JSON document to hash and check validity of JSON message returned by API
	($hash_ref,$msg) = json_data($json);
	if(!$hash_ref) {
		$error{STATUS} = 0;
		$error{CODE} = 'CLI005';
		$error{MESSAGE} = "Error parsing JSON response message: $msg";
		return (0,%error);
	}
	%data = %$hash_ref;

	# Check status and return error hash if call failed
    # Status element will not be set if data is returned, only if an error message is returned
    $status = (defined($data{status}) && $data{status} eq '0') ? 0 : 1;
	if(!$status) {
		$error{STATUS} = $status;
		$error{CODE} = $data{data}{code};
		$error{MESSAGE} = $data{data}{text};
	}

	# Return (0,%error) or (1,undef)
	return ($status,%error);
}



# ---------------------------------------------------------------------------------------------
# Check the response returned from the API
#
# Argument 1 : Response message string
# Argument 2 : Error number
# Argument 3 : Error text
#
# Return response string or error message in JSON format
# ---------------------------------------------------------------------------------------------
sub check_response {
	my($response,$result,$error) = @_;
	my($msg);
	
	# Command failed
	if($result == -1) {
		$msg = 'Failed to execute: '.$error;
		return '{"status":"0", "data": { "code":"CLI007", "text": "'.$msg.'"}}';
	}
	# Command process terminated
	elsif($result & 127) {
		$msg = 'Child died with signal ['.($result & 127).'], '.(($result & 128) ? 'with' : 'without').' coredump';
		return '{"status":"0", "data": { "code":"CLI008", "text": "'.$msg.'"}}';
	}
	# Empty response
	elsif(!$response) {
		$msg = 'No response from API';
		return '{"status":"0", "data": { "code":"CLI009", "text":"'.$msg.'"}}';
	}
	# Response text received
	else {
		return $response;
	}
}



# ---------------------------------------------------------------------------------------------
# Convert a string in JSON format to a hash
#
# Argument 1 : String in JSON format
#
# Return (pointer,undef) to a hash of data if successful, or (undef,message) if errors
# ---------------------------------------------------------------------------------------------
sub json_data {
	my($string) = @_;
	my($hash_ref);

	# Parse the string and trap any errors
	eval { $hash_ref = JSON::XS->new->latin1->decode($string) or die "error" };
	if($@) {
		return (undef,$@);
	}

	return ($hash_ref,undef);
}
