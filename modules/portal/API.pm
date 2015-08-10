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
our @EXPORT = qw(apiData apiDML apiMessage apiStatus apiSelect);

our %API;
$API{host}		= 'api.visualsaas.net';
$API{port}		= 8922;
$API{instance}	= 'airwave';
$API{user}		= 'rexcell@techlive.co.uk'; 
$API{password}	= 'A1rwav3';

1;





# =============================================================================================
# =============================================================================================
#
# Public functions
#
# =============================================================================================
# =============================================================================================

# ---------------------------------------------------------------------------------------------
# Parse a response from the Gateway and extract the data or information records
#
# Argument 1 : JSON response message from the Gateway
#
# Return a hash with the data, information or error
# ---------------------------------------------------------------------------------------------
sub apiData {
	my($json) = @_;
	my($hash_ref,$msg);
	my %data = ();
	my %error = ();

	# Check whether any data was returned
	if(!$json) {
		$error{STATUS} = 0;
		$error{SEVERITY} = 'WARN';
		$error{CODE} = 'CLI006';
		$error{MESSAGE} = "No data returned by the Gateway";
		return %error;
	}

	# Convert JSON document to hash - already validated by 'make_request'
	($hash_ref,$msg) = jsonData($json);
	%data = %$hash_ref;
	return %data;
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
	my($response);
	
	# Processing for Select and DML commands is the same
	$response = apiSQL($call,@params);
	
	# Return the JSON response
	return $response;
}



# ---------------------------------------------------------------------------------------------
# Send and email message or an SMS message
#
# Argument 1  : Message command to be initiated (email/sms)
# Argument 2+ : Array of message parameters
#
# Return the JSON response
# ---------------------------------------------------------------------------------------------
sub apiMessage {
	my($call,@params) = @_;
	my($cmd,$name,$value,$msg,$response);
	
	# Email
	if($call eq 'email') {
		# Build the command
		$cmd = "curl -s -X POST -F username=$API{user} -F password=$API{password} -F instance=$API{instance} -F command=email -F format=object ";
		
		# Add the parameters
		# Strip out special characters, then split out name/value pair and reformat
		foreach my $param (@params) {
			$param =~ s/'//g;
			$param =~ s/&/and/g;
			($name,$value) = split(/=/,$param);
			$cmd .= "-F $name='$value' ";
		}
		
		# Close the command
		$cmd .= "https://$API{host}:$API{port}";
		
		# Run the command and check the return code
		$response = `$cmd`;
		if($? == -1) {
			$msg = 'Failed to execute: '.$!;
			$response = '{"status":"0", "severity":"FATAL", "code":"CLI007", "text": "'.$msg.'"}';
		}
		elsif($? & 127) {
			$msg = 'Child died with signal ['.($? & 127).'], '.(($? & 128) ? 'with' : 'without').' coredump';
			$response = '{"status":"0", "severity":"FATAL", "code":"CLI008", "text": "'.$msg.'"}';
		}
		else {
			# SUCCESS CODE: printf "Child exited with value %d\n", $? >> 8;
		}
	
		# Return the JSON response
		return $response;
	}
	else {
		# SMS
	}
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
	my($response);
	
	# Processing for Select and DML commands is the same
	$response = apiSQL($call,@params);
	
	# Return the JSON response
	return $response;
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
	my($cmd,$msg,$response);

	# Build the command
	$cmd = "curl -s -X POST -F username=$API{user} -F password=$API{password} -F instance=$API{instance} -F command=$call -F format=object ";

	# Add the parameters
	foreach my $param (@params) {
		$cmd .= "-F $param ";
	}

	# Close the command
	$cmd .= "https://$API{host}:$API{port}";

	# Run the command and check the return code
	$response = `$cmd`;
	if($? == -1) {
		$msg = 'Failed to execute: '.$!;
		$response = '{"status":"0", "severity":"FATAL", "code":"CLI001", "text": "'.$msg.'"}';
	}
	elsif($? & 127) {
		$msg = 'Child died with signal ['.($? & 127).'], '.(($? & 128) ? 'with' : 'without').' coredump';
		$response = '{"status":"0", "severity":"FATAL", "code":"CLI002", "text": "'.$msg.'"}';
	}
	else {
		# SUCCESS CODE: printf "Child exited with value %d\n", $? >> 8;
	}

	# Return the JSON response
	return $response;
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
		$error{SEVERITY} = 'FATAL';
		$error{CODE} = 'CLI003';
		$error{MESSAGE} = "No data returned by the Gateway";
		return (0,%error);
	}
	
	# If an HTML tag is present, something went wrong with the CURL call
	if($json =~ m/HTML/i) {
		$error{STATUS} = 0;
		$error{SEVERITY} = 'FATAL';
		$error{CODE} = 'CLI004';
		$error{MESSAGE} = "Problem with the CURL call. Check arguments";
		return (0,%error);
	}
	
	# Convert JSON document to hash and check validity of JSON message returned by API
	($hash_ref,$msg) = jsonData($json);
	if(!$hash_ref) {
		$error{STATUS} = 0;
		$error{SEVERITY} = 'FATAL';
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
		$error{SEVERITY} = ($data{severity}) ? $data{severity} : 'WARN';
		$error{CODE} = $data{code};
		$error{MESSAGE} = $data{text};
	}

	# Return (0,%error) or (1,undef)
	return ($status,%error);
}



# ---------------------------------------------------------------------------------------------
# Convert a string in JSON format to a hash
#
# Argument 1 : String in JSON format
#
# Return (pointer,undef) to a hash of data if successful, or (undef,message) if errors
# ---------------------------------------------------------------------------------------------
sub jsonData {
	my($string) = @_;
	my($hash_ref);

	# Remove newlines
#	$string =~ s/\n//g;

	# Parse the string and trap any errors
	eval { $hash_ref = JSON::XS->new->latin1->decode($string) or die "error" };
	if($@) {
		return (undef,$@);
	}

	return ($hash_ref,undef);
}
