<?xml version="1.0"?>
<!-- Message file for the Breato Gateway Client
		id    : Unique ID of the error message
		type  : 0=Information, 1=Error, 2=debug
		level : Verbosity level for the message 
-->
<messages>
	<!-- General debug messages -->
	<msg id='D1' type='2' level='1'>_p1: _p2</msg>
	<msg id='D2' type='2' level='2'>_p1: _p2</msg>
	<msg id='D3' type='2' level='3'>_p1: _p2</msg>
	
	<!-- Internal error messages written to log files -->
	<msg id='E200' type='1' level='0'>submitCall: Port number cannot be read from Gateway Client configuration file</msg>
	<msg id='E201' type='1' level='0'>submitCall: Cannot create socket on [_p1:_p2]: _p3</msg>
	<msg id='E202' type='1' level='0'>submitCall: No command submitted by Client</msg>
	<msg id='E206' type='1' level='0'>submitCall: Cannot parse command: _p1</msg>
	<msg id='E207' type='1' level='0'>submitCall: Server name is not specified in command: _p1</msg>
	<msg id='E210' type='1' level='0'>gatewayFile: File transfer parameter [_p1] is missing</msg>
	<msg id='E211' type='1' level='0'>gatewayFile: Source file is not readable: _p1</msg>
	<msg id='E215' type='1' level='0'>submitCall: Interaction with Gateway failed: _p1</msg>
	<msg id='E216' type='1' level='0'>gatewayFile: Direction is either 'upload' or 'download', not '_p1'</msg>
	<msg id='E217' type='1' level='0'>gatewayFile: Target file is not writeable: _p1</msg>
	<msg id='E219' type='1' level='0'>submitInteract: File _p1 failed (_p2 bytes), MD5 checksum does not match the target file</msg>
	<msg id='E221' type='1' level='0'>fileUpload: File upload stopped by Server</msg>
	<msg id='E222' type='1' level='0'>fileDownload: File download stopped by Server</msg>
	<msg id='E223' type='1' level='0'>submitInteract: File download stopped as file [_p1] cannot be created</msg>
	<msg id='E224' type='1' level='0'>submitInteract: File upload stopped as file [_p1] cannot be opened for reading</msg>
	<msg id='E225' type='1' level='0'>fileUpload: Can't read from source file: _p1</msg>
	<msg id='E226' type='1' level='0'>gatewayMessage: Message type is either 'email' or 'sms', not [_p1]</msg>
	<msg id='E227' type='1' level='0'>gatewayMessage: These parameters are mandatory: recipient, sender, subject, body</msg>
	<msg id='E228' type='1' level='0'>msgHeader: Server name '_p1' is not registered</msg>
	
	<!-- Internal information messages written to log files -->
	<msg id='I200' type='0' level='0'>submitCall: Opening socket to server at _p1:_p2</msg>
	<msg id='I201' type='0' level='0'>submitCall: Socket created to server at _p1:_p2</msg>
	<msg id='I214' type='0' level='0'>submitCall: Successful interaction with Gateway: _p1</msg>
	<msg id='I218' type='0' level='0'>submitInteract: File _p1 complete (_p2 bytes), MD5 checksum matches the target file</msg>
	<msg id='I220' type='0' level='0'>fileUpload: File _p1 complete</msg>
	
	<!-- Messages returned to Clients -->
	<msg id='U200' type='1' level='0'>Port number cannot be read from Gateway Client configuration file</msg>
	<msg id='U201' type='1' level='0'>Cannot create socket on [_p1:_p2]</msg>
	<msg id='U202' type='1' level='0'>No command submitted by Client</msg>
	<msg id='U206' type='1' level='0'>Cannot parse command: _p1</msg>
	<msg id='U207' type='1' level='0'>Server name is not specified in command: _p1</msg>
	<msg id='U210' type='1' level='0'>File transfer parameter [_p1] is missing</msg>
	<msg id='U211' type='1' level='0'>Source file is not readable: _p1</msg>
	<msg id='U216' type='1' level='0'>Direction is either 'upload' or 'download', not '_p1'</msg>
	<msg id='U217' type='1' level='0'>Target file is not writeable: _p1</msg>
	<msg id='U218' type='0' level='0'>File _p1 complete (_p2 bytes), MD5 checksum matches the target file</msg>
	<msg id='U219' type='1' level='0'>File _p1 failed (_p2 bytes), MD5 checksum does not match the target file</msg>
	<msg id='U220' type='0' level='0'>File _p1 complete</msg>
	<msg id='U223' type='1' level='0'>File download stopped as file [_p1] cannot be created</msg>
	<msg id='U224' type='1' level='0'>File upload stopped as file [_p1] cannot be opened for reading</msg>
	<msg id='U225' type='1' level='0'>Can't read from source file: _p1</msg>
	<msg id='U226' type='1' level='0'>Message type is either 'email' or 'sms', not [_p1]</msg>
	<msg id='U227' type='1' level='0'>These parameters are mandatory: recipient, sender, subject, body</msg>
	<msg id='U228' type='1' level='0'>Server name '_p1' is not registered</msg>
</messages>
