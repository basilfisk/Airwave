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
use HTTP::Request;
use JSON::XS;
use LWP::UserAgent;

# Declare the package name and export the function names
package mods::API3Portal;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(apiData apiDML apiMetadata apiStatus apiSelect);

# Credentials for the portal@airwave.tv user
our %API;
$API{host}		= 'api.visualsaas.net';
$API{port}		= 19001;
$API{connector}	= 'airwave-live';
$API{jwt}		= 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c3IiOiJwb3J0YWxAYWlyd2F2ZS50diIsImlwcyI6WyIqIl0sInBhY2thZ2UiOiI5ZWYxZGI2MWFhZDA4ZmEzZDFiZWM0MmRmNjg2OWQ5MyJ9.9U9mxco5VNhemAVbHtWdhQZafZhPFWv4X_mS0lZdM3Q';

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
# Processing for Select and DML commands is the same
#
# Argument 1 : Function to be called
# Argument 2 : Array of arguments to the function (name=value)
#
# Return the JSON response
# ---------------------------------------------------------------------------------------------
sub apiDML {
	my($call,@params) = @_;
	return apiSQL($call,@params);
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
	my($cmd);

	# Build the command
	$cmd = "https://$API{host}:$API{port}/3/$call?";
	$cmd .= "{\"connector\":\"$API{connector}\"";
	$cmd .= ",\"assetcode\":\"$assetcode\",\"format\":\"$format\"}";

	# Run the command and return a JSON object
	return run_command($cmd);
}



# ---------------------------------------------------------------------------------------------
# Run an SQL SELECT query
# Processing for Select and DML commands is the same
#
# Argument 1 : Function to be called
# Argument 2 : Array of arguments to the function (name=value)
#
# Return the JSON response
# ---------------------------------------------------------------------------------------------
sub apiSelect {
	my($call,@params) = @_;
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
	my($cmd,$name,$value);

	# Build the command
	$cmd = "https://$API{host}:$API{port}/3/$call?";
	$cmd .= "{\"connector\":\"$API{connector}\"";

	# Add the parameters
	foreach my $param (@params) {
		$param =~ s/ /%20/g;
		($name,$value) = split(/=/,$param);
		$cmd .= ",\"$name\":\"$value\"";
	}

	# Close the command
	$cmd .= "}";

	# Run the command and return a JSON object
	return run_command($cmd);
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



# ---------------------------------------------------------------------------------------------
# Run the API command and check the response returned from the API
#
# Argument 1 : API command
#
# Return data or error message in JSON format
# {"status":"1", "data": {...} }'
# {"status":"0", "data": { "code":"...", "session":"...", "text":"..."}}'
# ---------------------------------------------------------------------------------------------
sub run_command {
	my($cmd) = @_;
	my($request,$ua,$response,$code,$msg,$id);

	# Make the request
	$request = HTTP::Request->new('GET', $cmd);
	$request->header("Authorization" => "Bearer $API{jwt}");
	$ua = LWP::UserAgent->new;
	$response = $ua->request($request);

	# Check the response
	if($response->is_success) {
		# Return data
		if($response->header('Gateway-Status') eq '1') {
			if ($response->content) {
				return '{"status":"1", "data": '.$response->content.'}';
			}
			else {
				return '{"status":"1", "data": {} }';
			}
		}
		# Return error
		else {
			$code = $response->header('Gateway-Code');
			$msg = $response->header('Gateway-Message');
			$id = $response->header('Gateway-ID');
			return '{"status":"0", "data": { "code":"'.$code.'", "session":"'.$id.'", "text":"'.$msg.'"}}';
		}
	}
	# Empty response
	else {
		return '{"status":"0", "data": { "code":"CLI009", "text":"No response from API"}}';
	}
}
