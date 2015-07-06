// ****************************************************************************
//
// Check that the date was entered in 'dd/mm' format
//
// Argument 1 : Date string in 'dd/mm' format
//
// Return true or false
//
// ****************************************************************************
function checkDDMM(string) {
    // Check the separator is correct
    var parts = string.split("/");
    if(parts.length < 2) {
        alert("Invalid date format.  Use '/' as the separator between day and month");
        return false;
    }
    if(parts.length > 2) {
		alert("Invalid date format.  Only use one '/' as the separator between day and month");
		return false;
	}
	
	// Valid month?
	if(parts[1] < 1 || parts[1] > 12) {
		alert("Month must be between 1 and 12");
		return false;
	}
	
	// Valid day?
	if(parts[1] == 2) {
		if(parts[0] <1 || parts[0] >28) {
			alert("Day must be between 1 and 28");
			return false;
		}
	}
	else if(parts[1] == 4 || parts[1] == 6 || parts[1] == 9 || parts[1] == 11) {
		if(parts[0] <1 || parts[0] >30) {
			alert("Day must be between 1 and 30");
			return false;
		}
	}
	else {
		if(parts[0] <1 || parts[0] >31) {
			alert("Day must be between 1 and 31");
			return false;
		}
	}
		
	// Valid date
	return true;
}



//****************************************************************************
//
// Convert date in 'DD/MM/YY HH24:MI' format to a Breato date
//
// Argument 1 : Date in 'DD/MM/YY HH24:MI' format
//
// Return the date in 'DD Mon YYYY HH24:MI' format
//
// ****************************************************************************
function convertDDMMYYtoBreato(string)
{
    // Split out date and time
    var datetime = string.split(" ",2);

    // Split out DD, MM, and YY
    var datestr = datetime[0].split("/",3);

    // Month from 01-12 to text
    var month;
    switch (datestr[1])
    {
        case '01': month = 'Jan'; break;
        case '02': month = 'Feb'; break;
        case '03': month = 'Mar'; break;
        case '04': month = 'Apr'; break;
        case '05': month = 'May'; break;
        case '06': month = 'Jun'; break;
        case '07': month = 'Jul'; break;
        case '08': month = 'Aug'; break;
        case '09': month = 'Sep'; break;
        case '10': month = 'Oct'; break;
        case '11': month = 'Nov'; break;
        case '12': month = 'Dec'; break;
    }

    // Year from CCYY to YY
    var year = datestr[2].substr(-2,2);

    // Return Breato date
    return datestr[0] + " " + month + " 20" + datestr[2] + " " + datetime[1];
}



// ****************************************************************************
//
// Convert Breato date to date in 'YYMM' format
//
// Argument 1 : Breato date in 'DD Mon YYYY' format
//
// Return the date in 'YYMM' format
//
// ****************************************************************************
function convertDateYYMM(string)
{
    // Split out DD, Mon, and YYYY
    var datestr = string.split(" ",3);

    // Month text to number from 01-12
    var month;
    switch (datestr[1])
    {
        case 'Jan': month = '01'; break;
        case 'Feb': month = '02'; break;
        case 'Mar': month = '03'; break;
        case 'Apr': month = '04'; break;
        case 'May': month = '05'; break;
        case 'Jun': month = '06'; break;
        case 'Jul': month = '07'; break;
        case 'Aug': month = '08'; break;
        case 'Sep': month = '09'; break;
        case 'Oct': month = '10'; break;
        case 'Nov': month = '11'; break;
        case 'Dec': month = '12'; break;
    }

    // Year from CCYY to YY
    var year = datestr[2].substr(-2,2);

    // Return YYMM
    return year + month;
}



// ****************************************************************************
//
// Convert a JavaScript date to a Breato date format
// By default, the current date is used
//
// Argument 1 : 'short' returns date in 'DD Mon YYYY' format
//              'full'  returns date in 'DD Mon YYYY HH24:MI' format
// Argument 2 : Date to be converted (optional)
//
// Return the formatted date
// 
// ****************************************************************************
function getBreatoDate(type, datetime)
{
	// Read date or set to current date/time if not specified
    if(datetime === undefined) datetime = new Date();

	// Year
	var year = datetime.getFullYear();

	// Month
	var mth = datetime.getMonth();
	var month;
	switch (mth)
	{
		case 0: month = 'Jan'; break;
		case 1: month = 'Feb'; break;
		case 2: month = 'Mar'; break;
		case 3: month = 'Apr'; break;
		case 4: month = 'May'; break;
		case 5: month = 'Jun'; break;
		case 6: month = 'Jul'; break;
		case 7: month = 'Aug'; break;
		case 8: month = 'Sep'; break;
		case 9: month = 'Oct'; break;
		case 10: month = 'Nov'; break;
		case 11: month = 'Dec'; break;
	}

	// Day
	var dom = datetime.getDate();
	var day = ('0'+dom).substr(-2,2);


	// Hour
	var hr = datetime.getHours();
	var hour = ('0'+hr).substr(-2,2);

	// Minute
	var mn = datetime.getMinutes();
	var mins = ('0'+mn).substr(-2,2);

	// Return date and optionally time
	var fmtdate;
	if(type == 'short') {
		fmtdate = day + ' ' + month + ' ' + year;
	}
	else {
		fmtdate = day + ' ' + month + ' ' + year + ' ' + hour + ':' + mins;
	}
	return fmtdate;
}



// ****************************************************************************
//
// Convert Breato date to JS date
//
// Argument 1 : Breato date in 'DD Mon YYYY HH24:MI:SS' format
//
// Return the JS date
//
// ****************************************************************************
function getDate(string)
{
	// Split out DD, Mon, and YYYY
	var datetime = string.split(" ",3);
	
	// Extract hours, minutes and seconds
	datetime.push(string.substr(12,2));
	datetime.push(string.substr(15,2));
	datetime.push(string.substr(18,2));
	
	// Month text to number from 0-11
	switch (datetime[1])
	{
		case 'Jan': datetime[1] = 0; break;
		case 'Feb': datetime[1] = 1; break;
		case 'Mar': datetime[1] = 2; break;
		case 'Apr': datetime[1] = 3; break;
		case 'May': datetime[1] = 4; break;
		case 'Jun': datetime[1] = 5; break;
		case 'Jul': datetime[1] = 6; break;
		case 'Aug': datetime[1] = 7; break;
		case 'Sep': datetime[1] = 8; break;
		case 'Oct': datetime[1] = 9; break;
		case 'Nov': datetime[1] = 10; break;
		case 'Dec': datetime[1] = 11; break;
	}

	// Convert to a JS date and return
	var date1 = new Date(datetime[2], datetime[1], datetime[0], datetime[3], datetime[4], datetime[5], 0);
	return date1;
}





// ============================================================================
// ============================================================================
//
// APPLICATION SPECIFIC FUNCTIONS THAT ARE CALLED BY XMLHttpRequest
//
// ============================================================================
// ============================================================================

// ****************************************************************************
//
// Create a distribution record and update the distribution ID on each 
// inventory record
//
// Called by the 'dist_planned_cds' form
//
// Argument 1 : Object with arguments passed in from On-Click event
// Argument 2 : Results from brManageData that invoked this function
//
// ****************************************************************************
function addDistribution(args, results) {
	try {
		if(results.setsReturned > 0) {
			// Find ID of created record
			var distid = results[0].processed['id'];

			// Split the ID string into an array of IDs
			var ids = args.idlist.split(",");

			// Update each inventory record with the distribution ID
			for(i=0; i<ids.length; i++) {
				// Create an object holding the parameters for the API call
				var params = {
					id: ids[i],
					entity_type: 'airwave_distributioninventory',
					action: 'save',
					name: '',
					description: '',
					Distributions: distid
				};

				// Arguments to pass to 'updateDistributionInventory'
				var updateargs = {
					distributionref: args.distributionref
				};

				// Update the distribution ID on each inventory record
				brManageData(container, params, 'updateDistributionInventory(args, results)', updateargs);
			}
		}
		else {
			alert(args.failure);
		}
	}
	catch(err) {
		// Handle errors
		alert("Function 'addDistribution' failed: " + err);
	}
}



// ****************************************************************************
//
// Create a distribution bundle record and a distribution inventory record
// for each film
//
// Called by the 'dist_bundle' form
//
// Argument 1 : Object with arguments passed in from On-Click event
// Argument 2 : Results from brManageData that invoked this function
//
// ****************************************************************************
function addDistributionBundle(args, results) {
	try {
		if(results.setsReturned > 0) {
			// Find ID of created record
			var bundleid = results[0].processed['id'];

			// Split the ID strings into arrays
			var films = args.filmlist.split(",");
			var sites = args.sitelist.split(",");

			// Add 1 distribution record for each combination of film and site
			for(s=0; s<sites.length; s++) {
				for(f=0; f<films.length; f++) {
					// Create an object holding the parameters for the API call
					var params = {
						id: 0,
						entity_type: 'airwave_distributioninventory',
						action: 'new',
						name: '',
						description: '',
						licencestart: args.licencestart,
						'Distribution Bundles': bundleid,
						'Distribution Films': films[f],
						'Distribution Sites': sites[s]
					};

					// Arguments to pass to 'addDistributionInventory'
					var newargs = {
						bundleid: bundleid,
						site: sites[s],
						film: films[f],
						licencestart: args.licencestart
					};

					// Create a distribution inventory record
					brManageData(container, params, 'addDistributionInventory(args, results)', newargs);
				}
			}
		}
		else {
			alert(args.failure);
		}
	}
	catch(err) {
		// Handle errors
		alert("Function 'addDistributionBundle' failed: " + err);
	}
}



// ****************************************************************************
//
// Create a distribution inventory record
//
// Called by the 'addDistributionBundle' function
//
// Argument 1 : Object with arguments passed in from Click widget JS
// Argument 2 : Results from brManageData
//
// ****************************************************************************
function addDistributionInventory(args, results) {
	try {
		if(results.setsReturned > 0) {
			// Find ID of created record
			var inventoryid = results[0].processed['id'];
//			alert("Create inventory item on bundle [" + args.bundleid + "] for site [" + args.site + "] with film [" + args.film + "] starting on [" + args.licencestart + "]");
		}
		else {
			alert("No distribution inventory record created");
		}
	}
	catch(err) {
		// Handle errors
		alert("Function 'addDistributionInventory' failed: " + err);
	}
}



//****************************************************************************
//
// Processes results after a distribution inventory record has been updated
//
// Called by the 'addDistribution' function
//
// Argument 1 : Object with arguments passed in from Click widget JS
// Argument 2 : Results from brManageData
//
// ****************************************************************************
function updateDistributionInventory(args, results) {
	try {
		if(results.setsReturned > 0) {
			// Find ID of updated record
			var inventoryid = results[0].processed['id'];
//			alert("Updated inventory item [" + inventoryid + "] with [" + args.distributionref + "]");
		}
		else {
			alert("No distribution inventory record updated");
		}
	}
	catch(err) {
		// Handle errors
		alert("Function 'updateDistributionInventory' failed: " + err);
	}
}



