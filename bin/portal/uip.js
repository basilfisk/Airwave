// *********************************************************************************************
// *********************************************************************************************
//
// UIP Schedule A & E spreadsheet for the unified contract
//
// Argument 1 : Year and month (YYMM)
//
// Copyright 2017 Airwave Ltd.
//
// *********************************************************************************************
// *********************************************************************************************
"use strict"

var	Excel = require('exceljs'),
	fs = require('fs'),
	moment = require('moment'),
	request = require('request'),
	config = require(__dirname + '/etc/uip.json'),
	yymm, mth, current, scheduleE = {}, sites, events;

// Trap any uncaught exceptions
// Write error stack to STDERR, then exit process as state may be inconsistent
process.on('uncaughtException', function(err) {
	console.error('ERROR TRAPPED (uip)');
	console.error(err.stack);
	process.exit(1);
});

// Read year and month from command line
yymm = parseInt(process.argv[2]);
config.period = {};
config.period.year = parseInt(yymm / 100);
mth = yymm - (config.period.year * 100);
config.period.month = ('0' + mth).substr(-2,2);

// Check year and month
current = new Date().getFullYear();
if (config.period.year >= (current - 2001) && config.period.year <= (current - 2000)) {
	if (mth >= 1 && mth <= 12) {
		read_event_data();
	}
	else {
		log("Month must be between 1 and 12");
	}
}
else {
	log("Year must be between " + (current - 2001) + " and " + (current - 2000));
}



// ---------------------------------------------------------------------------------------
// Send a JWT protected command to the API then invoke a callback
//
// Argument 1 : Command to be run
// Argument 2 : Data object in JSON format
// Argument 3 : Callback function to be run after data returned
// ---------------------------------------------------------------------------------------
function apiCall (command, prms, callback) {
	var call, keys, i, auth;

	// Build the API call
	call = 'https://' + config.api.host + ':' + config.api.port + '/3/' + command + '?{';
	call += '"connector":"' + config.api.connector + '"';
	keys = Object.keys(prms);
	for (i=0; i<keys.length; i++) {
		call += ',"' + keys[i] + '":"' + prms[keys[i]] + '"';
	}
	call += '}';

	// Run the call
	auth = { 'auth': { 'bearer': config.api.jwt } };
	request.get(call, auth, function (err, response, body) {
		if (err) {
			log(err.message);
		}
		else {
			if (body.length === 0) {
				callback({});
			}
			else {
				callback(JSON.parse(body));
			}
		}
	});
}



// ---------------------------------------------------------------------------------------------
// Format columns
//
// Argument 1 : Worksheet object
// Argument 2 : Column ID
// Argument 3 : Horizontal alignment
// Argument 4 : Format string (optional)
// ---------------------------------------------------------------------------------------------
function format_column (sheet, id, horiz, format) {
	sheet.getColumn(id).alignment = { vertical: 'middle', horizontal: horiz, wrapText: true };
	sheet.getColumn(id).font = { name: 'Arial', size: 8 };
	if (format !== undefined) {
		sheet.getColumn(id).numFmt = format;
	}
}



// ---------------------------------------------------------------------------------------------
// Generate the spreadsheet
//
// Argument 1 : Events object
//	"United Kingdom": {
//		"vat": 20,
//		"sites" : {
//			"Athena Hotel": {
//				"rooms": 60,
//				"films": {
//					"Big Miracle": {
//						"plays": 8,				- Number of plays
//						"uipid": 12345678,		- UIP film reference
//						"rate": 4.17,			- UIP charge rate (p/room/day)
//						"guest": 4,				- Charge to guest
//						"share": 40,			- Premium film (true=50%, false=40%)
//						"start": "20/10/16",	- Home Entertainment release date of film in this territory
//						"type": "airwave",		- Contract type (airtime|airwave|techlive)
//						"class": "Library"		- Age of film (Library|Current)
//					},
// ---------------------------------------------------------------------------------------------
function generate (data) {
	var wb, schA, schE, margins, filename;

	// Create an empty workbook
	wb = new Excel.Workbook();

	// Set workbook properties
	wb.creator = 'Basil Fisk';
	wb.created = new Date();

	// Add the worksheets
	schA = wb.addWorksheet('Schedule A');
	schE = wb.addWorksheet('Schedule E');

	// Adjust page settings
	margins = {
		left: 0.75, right: 0.75,
		top: 0.75, bottom: 0.75,
		header: 0.3, footer: 0.3
	};
	schA.pageSetup.margins = margins;
	schE.pageSetup.margins = margins;

	// Set print characteristics
	schA.pageSetup.paperSize = 'A4';
	schE.pageSetup.paperSize = 'A4';

	// Create the Schedule A sheet and load data
	schedule_a_sheet(schA);
	schedule_a_data(schA, data);

	// Create the Schedule E sheet and load data
	schedule_e_sheet(schE);
	schedule_e_data(schE);

	// Write workbook to a file in XLSX format
	filename = config.output + '/' + (2000 + config.period.year) + '/UIP Unified ' + config.period.year + config.period.month + '.xlsx';
	wb.xlsx.writeFile(filename).then(function() {
		log('Spreadsheet written to ' + filename);
	});
}



// ---------------------------------------------------------------------------------------------
// Log a message
//
// Argument 1 : Message text
// ---------------------------------------------------------------------------------------------
function log (msg) {
	var line;

	// Build message
	line = moment().format('YYYY-MM-DDTHH:mm:ss.SSS');
	line = '[' + line + '] ' + msg + '\n';

	// Append to log file
	fs.appendFile(config.logfile, line, function (err) {
		if (err) {
			console.error('[uip] Could not write log message to ' + config.logfile);
		}
	});
}



// ---------------------------------------------------------------------------------------------
// Read event data from Airwave CMS
//
//	"key": {
//		"territory": "United Kingdom",
//		"vat": 20,
//		"site" : "Athena Hotel",
//		"rooms": 60,
//		"title": "Big Miracle",
//		"provider_ref": "12345678",
//		"views": "8",
//		"stg": "450",
//		"charge_rate": "3.2",
//		"type": "airtime|airwave|techlive",
//		"ntrdate": "20/10/16"
//		"class": "Current|Library"
//	}
// ---------------------------------------------------------------------------------------------
function read_event_data () {
	var yymm = config.period.year + config.period.month;

	// Run the API call then generate the spreadsheet
	apiCall('uipEvents', {month: yymm}, function (data) {
		var keys, i, flds, events = {}, terr, site, film;

		// Loop through each event
		keys = Object.keys(data);
		for (i=0; i<keys.length; i++) {
			flds = data[keys[i]];

			// Add a new territory
			terr = flds.territory;
			if (events[terr] === undefined) {
				events[terr] = {};
				events[terr].sites = {};
			}

			// VAT rate
			events[terr].vat = 1 + (((flds.vat === 'undefined' || isNaN(parseFloat(flds.vat))) ? config.vat : parseFloat(flds.vat)) / 100);

			// Add a new site
			site = flds.site;
			if (events[terr].sites[site] === undefined) {
				events[terr].sites[site] = {};
				events[terr].sites[site].films = {};
			}

			// Number of rooms
			events[terr].sites[site].rooms = parseInt(flds.rooms);

			// Add a new film
			film = flds.title;
			if (events[terr].sites[site].films[film] === undefined) {
				events[terr].sites[site].films[film] = {};
			}

			// UIP film reference
			events[terr].sites[site].films[film].uipid = flds.provider_ref;

			// Number of plays
			events[terr].sites[site].films[film].plays = parseInt(flds.views);

			// Charge to guest
			events[terr].sites[site].films[film].guest = parseInt(flds.stg) / 100;

			// Contract type (airtime|airwave|techlive)
			events[terr].sites[site].films[film].type = flds.type;

			// Set the Hybrid|Guest to Pay flag for Airtime
			events[terr].sites[site].films[film].hybrid = (flds.type === 'airtime') ? ((flds.charge_rate === '1') ? true : false) : false;

			// UIP charge rate (p/room/day)
			events[terr].sites[site].films[film].rate = (flds.type === 'airtime') ? config.uip.rate : parseFloat(flds.charge_rate);

			// Premium film (true=50%, false=40%)
			events[terr].sites[site].films[film].share = (flds.nominated === 'true' || flds.type === 'airtime') ? config.uip.share.nominated : config.uip.share.standard;

			// Home Entertainment release date of film in this territory
			events[terr].sites[site].films[film].start = flds.ntrdate;

			// Library or Current
			events[terr].sites[site].films[film].class = flds.class;
		}

		// Grenerate the spreadsheet
		generate(events);
	});
}



// ---------------------------------------------------------------------------------------------
// Load the rows into the Schedule A sheet
//
// Argument 1 : Worksheet object
// Argument 2 : Events object
// ---------------------------------------------------------------------------------------------
function schedule_a_data (sheet, data) {
	var terrs, vat, sites, sitenet = {}, key, sitedata, films, film, t, s, f, row, rooms, guarantee, guest, gross, net, totnet, totdue, schede, plays;
	var rowID = 4, site = '', start, end = 4, totals = {};
	totals.guarantee = 0;
	totals.totdue = 0;
	totals.gross = 0;
	totals.net = 0;
	totals.schede = 0;

	// Sorted list of territories
	terrs = Object.keys(data).sort();

	// Aggregate the plays and total due for each site
	for (t=0; t<terrs.length; t++) {
		vat = data[terrs[t]].vat;
		sites = Object.keys(data[terrs[t]].sites).sort();
		for (s=0; s<sites.length; s++) {
			net = plays = 0;
			start = end;
			films = Object.keys(data[terrs[t]].sites[sites[s]].films).sort();
			for (f=0; f<films.length; f++) {
				film = data[terrs[t]].sites[sites[s]].films[films[f]];
				guest = film.guest;
				net += film.plays * guest * film.share / 100 / vat;
				plays += film.plays;
				end++;
			}
			key = terrs[t] + sites[s];
			sitenet[key] = {};
			sitenet[key].net = net;
			sitenet[key].plays = plays;
			sitenet[key].start = start;
			sitenet[key].end = end - 1;
		}
	}

	// Sorted list of territories
	for (t=0; t<terrs.length; t++) {
		// Sorted list of sites within a territory
		vat = data[terrs[t]].vat;
		sites = Object.keys(data[terrs[t]].sites).sort();
		for (s=0; s<sites.length; s++) {
			sitedata = sitenet[terrs[t] + sites[s]];

			// Sorted list of films within a site
			films = Object.keys(data[terrs[t]].sites[sites[s]].films).sort();
			for (f=0; f<films.length; f++) {
				// Extract film data
				film = data[terrs[t]].sites[sites[s]].films[films[f]];

				// New site, show site related cells in the row
				if (site !== sites[s]) {
					sheet.getCell('A'+rowID).value = terrs[t];
					sheet.getCell('B'+rowID).value = sites[s];
					rooms = data[terrs[t]].sites[sites[s]].rooms;
					sheet.getCell('C'+rowID).value = rooms;
					sheet.getCell('F'+rowID).value = film.rate;
					sheet.getCell('G'+rowID).value = config.month.days[config.period.month - 1];
					guarantee = rooms * film.rate * config.month.days[config.period.month - 1] / 100;
					sheet.getCell('H'+rowID).value = { formula: 'C'+rowID+'*F'+rowID+'*G'+rowID+'/100', result: guarantee };
					totnet = sitedata.net;
					sheet.getCell('M'+rowID).value = { formula: 'SUM(L'+sitedata.start+':L'+sitedata.end+')', result: totnet };
					if (film.type === 'airtime') {
						// Hybrid
						if (film.hybrid) {
							totdue = totnet + guarantee;
							sheet.getCell('N'+rowID).value = { formula: 'M'+rowID+'+H'+rowID, result: totdue };
						}
						// Guest to pay
						else {
							totdue = totnet;
							sheet.getCell('N'+rowID).value = { formula: 'M'+rowID, result: totdue };
						}
					}
					else {
						totdue = (guarantee > totnet) ? guarantee : totnet;
						sheet.getCell('N'+rowID).value = { formula: 'MAX(H'+rowID+',M'+rowID+')', result: totdue };
					}
					site = sites[s];

					// Running totals
					totals.guarantee += guarantee;
					totals.totdue += totdue;
				}

				// Same site, show all film related cells
				sheet.getCell('D'+rowID).value = film.plays;
				sheet.getCell('E'+rowID).value = films[f];
				guest = film.guest;
				sheet.getCell('I'+rowID).value = guest;
				gross = film.plays * guest;
				sheet.getCell('J'+rowID).value = { formula: 'D'+rowID+'*I'+rowID, result: gross };
				sheet.getCell('K'+rowID).value = film.share / 100;
				net = gross * film.share / 100 / vat;
				sheet.getCell('L'+rowID).value = { formula: 'J'+rowID+'*K'+rowID+'/'+vat, result: net };
				schede = totdue * film.plays / sitedata.plays;
				sheet.getCell('O'+rowID).value = { formula: 'IF(L'+rowID+'=0,D'+rowID+'*N$'+sitedata.start+'/SUM(D'+sitedata.start+':D'+sitedata.end+'),L'+rowID+'*N$'+sitedata.start+'/M$'+sitedata.start+')', result: schede };
				sheet.getCell('P'+rowID).value = film.start;
				sheet.getCell('Q'+rowID).value = moment(film.start, "DD/MM/YY").add(364, 'days').format("DD/MM/YY");
				sheet.getCell('R'+rowID).value = film.class;
				if (film.type === 'airtime') {
					sheet.getCell('S'+rowID).value = (film.hybrid) ? 'Airtime Hybrid' : 'Airtime Guest to Pay';
				}

				// Running totals
				totals.gross += gross;
				totals.net += net;
				totals.schede += schede;

				// Film totals for Schedule E report
				if (scheduleE[films[f]]) {
					scheduleE[films[f]].value += schede;
				}
				else {
					scheduleE[films[f]] = {};
					scheduleE[films[f]].value = schede;
					scheduleE[films[f]].uipid = film.uipid;
				}

				// Increment the row number
				rowID++;
			}
		}
	}

	// Totals
	sheet.getCell('H'+rowID).value = { formula: 'SUM(H4:H'+(rowID-1)+')', result: totals.guarantee };
	sheet.getCell('J'+rowID).value = { formula: 'SUM(J4:J'+(rowID-1)+')', result: totals.gross };
	sheet.getCell('L'+rowID).value = { formula: 'SUM(L4:L'+(rowID-1)+')', result: totals.net };
	sheet.getCell('N'+rowID).value = { formula: 'SUM(N4:N'+(rowID-1)+')', result: totals.totdue };
	sheet.getCell('O'+rowID).value = { formula: 'SUM(O4:O'+(rowID-1)+')', result: totals.schede };
	sheet.lastRow.font = { name: 'Arial', size: 8, bold: true };
}



// ---------------------------------------------------------------------------------------------
// Create the Schedule A sheet
//
// Argument 1 : Worksheet object
// ---------------------------------------------------------------------------------------------
function schedule_a_sheet (sheet) {
	// Initialise columns
	sheet.columns = [
		{ key: 'territory', width: 20 },
		{ key: 'site', width: 30 },
		{ key: 'rooms', width: 7 },
		{ key: 'plays', width: 7 },
		{ key: 'film', width: 40 },
		{ key: 'dayrate', width: 9 },
		{ key: 'days', width: 9 },
		{ key: 'guarantee', width: 9 },
		{ key: 'guestprice', width: 9 },
		{ key: 'gross', width: 9 },
		{ key: 'percent', width: 9 },
		{ key: 'net', width: 9 },
		{ key: 'totalnet', width: 9 },
		{ key: 'totaldue', width: 9 },
		{ key: 'schede', width: 9 },
		{ key: 'filmstart', width: 9 },
		{ key: 'filmend', width: 9 },
		{ key: 'class', width: 9 },
		{ key: 'type', width: 15 }
	];

	// Format columns
	format_column(sheet, 'territory', 'left');
	format_column(sheet, 'site', 'left');
	format_column(sheet, 'rooms', 'center');
	format_column(sheet, 'plays', 'center');
	format_column(sheet, 'film', 'left');
	format_column(sheet, 'dayrate', 'right', '0.00');
	format_column(sheet, 'days', 'center');
	format_column(sheet, 'guarantee', 'right', '"£"#,##0.00');
	format_column(sheet, 'guestprice', 'right', '"£"#,##0.00');
	format_column(sheet, 'gross', 'right', '"£"#,##0.00');
	format_column(sheet, 'percent', 'right', '0%');
	format_column(sheet, 'net', 'right', '"£"#,##0.00');
	format_column(sheet, 'totalnet', 'right', '"£"#,##0.00');
	format_column(sheet, 'totaldue', 'right', '"£"#,##0.00');
	format_column(sheet, 'schede', 'right', '"£"#,##0.00');
	format_column(sheet, 'filmstart', 'center');
	format_column(sheet, 'filmend', 'center');
	format_column(sheet, 'class', 'center');
	format_column(sheet, 'type', 'left');

	// Add the title row and a blank row
	sheet.addRow({ territory: 'Schedule A for ' + config.month.names[config.period.month - 1] + ' ' + config.period.year });
	sheet.lastRow.height = 25;
	sheet.mergeCells('A1:B1');
	sheet.getCell('A1').font = { name: 'Arial', size: 14, bold: true };
	sheet.addRow({ territory: ' ' });

	// Column headings
	sheet.addRow(['Territory','Site','Rooms','Plays','Title','Daily Rate (pence)','Days','Daily Guarantee','Price to Guest','Gross Receipt','Percentage','Net Receipts','Total Net','Total Due','Total Sched E','Title Start Date','Title End Date','Class','']);
	sheet.lastRow.height = 25;
	sheet.lastRow.font = { name: 'Arial', size: 8, bold: true };
}



// ---------------------------------------------------------------------------------------------
// Load the rows into the Schedule E sheet
//
// Argument 1 : Worksheet object
// ---------------------------------------------------------------------------------------------
function schedule_e_data (sheet) {
	var films, i, total = 0, rowID = 9;

	// Sorted list of films
	films = Object.keys(scheduleE).sort();
	for (i=0; i<films.length; i++) {
		sheet.getCell('A'+rowID).value = films[i];
		sheet.getCell('C'+rowID).value = scheduleE[films[i]].uipid;
		sheet.getCell('D'+rowID).value = scheduleE[films[i]].value;
		sheet.mergeCells('A'+rowID+':B'+rowID);

		// Running total
		total += scheduleE[films[i]].value;

		// Increment the row number
		rowID++;
	}

	// Total
	sheet.getCell('D'+rowID).value = { formula: 'SUM(D9:D'+(rowID-1)+')', result: total };
	sheet.lastRow.font = { name: 'Arial', size: 8, bold: true };
}



// ---------------------------------------------------------------------------------------------
// Create the Schedule E sheet
//
// Argument 1 : Worksheet object
// ---------------------------------------------------------------------------------------------
function schedule_e_sheet (sheet) {
	// Initialise columns
	sheet.columns = [
		{ key: 'colA', width: 12 },
		{ key: 'colB', width: 30 },
		{ key: 'colC', width: 12 },
		{ key: 'colD', width: 12 }
	];

	// Format columns
	format_column(sheet, 'colA', 'left');
	format_column(sheet, 'colB', 'left');
	format_column(sheet, 'colC', 'left');
	format_column(sheet, 'colD', 'right', '"£"#,##0.00');

	// Add the title row and a blank row
	sheet.addRow({ colA: 'Schedule E for ' + config.month.names[config.period.month - 1] + ' ' + config.period.year });
	sheet.lastRow.height = 25;
	sheet.mergeCells('A1:B1');
	sheet.getCell('A1').font = { name: 'Arial', size: 14, bold: true };
	sheet.addRow({ colA: ' ' });

	// Add the customer data header
	sheet.getCell('A3').value = 'Film Size';
	sheet.getCell('A3').font = { name: 'Arial', size: 8, bold: true };
	sheet.getCell('B3').value = '7';
	sheet.getCell('A4').value = 'Customer';
	sheet.getCell('A4').font = { name: 'Arial', size: 8, bold: true };
	sheet.getCell('B4').value = 'Airwave';
	sheet.getCell('A5').value = 'Territory';
	sheet.getCell('A5').font = { name: 'Arial', size: 8, bold: true };
	sheet.getCell('B5').value = 'UK';
	sheet.getCell('A6').value = 'Territory No.';
	sheet.getCell('A6').font = { name: 'Arial', size: 8, bold: true };
	sheet.getCell('B6').value = '627';
	sheet.getCell('C4').value = 'Currency';
	sheet.getCell('C4').font = { name: 'Arial', size: 8, bold: true };
	sheet.getCell('D4').value = 'GBP';
	sheet.getCell('C5').value = 'Year';
	sheet.getCell('C5').font = { name: 'Arial', size: 8, bold: true };
	sheet.getCell('D5').value = 2000 + config.period.year;
	sheet.getCell('D5').numFmt = '0000';
	sheet.getCell('C6').value = 'Period';
	sheet.getCell('C6').font = { name: 'Arial', size: 8, bold: true };
	sheet.getCell('D6').value = config.period.month;
	sheet.getCell('D6').numFmt = '#0';
	sheet.addRow({ colA: ' ' });

	// Column headings
	sheet.addRow(['Film Title',' ','Picture Number','Rental']);
	sheet.lastRow.height = 25;
	sheet.lastRow.font = { name: 'Arial', size: 8, bold: true };
}
