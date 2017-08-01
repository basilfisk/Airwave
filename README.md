# Airwave Issues

## Portal

- View Report Logs - Does not open log files for viewing

- Edit AW/TL Events - Clicking on the period column should show a form or do nothing

- Invoice Report - On new contracts we are issuing we are stipulating a price increase of 2.5% on the anniversary of each renewal – is there any way we can automate this?

- Techlive - Bulk load event files

- API.pm - Change user to portal@airwave.tv, or user who logs in

- API.pm - Move %API into a config file

- Usage reports - Upload the Techlive usage reports all at once, maybe in a .zip file

### Monitor file access on Portal

- Install

	- apt install inotify-tools

- Watch for any event in any file or directories under the 'airwave' directory

	- inotifywait /srv/visualsaas/instances/airwave -r -d -o /var/log/breato/airwave-watch.log

- Watch for specified events in any file or directores under the 'airwave' directory

	- inotifywait /srv/visualsaas/instances/airwave -r -d -o /var/log/breato/airwave-watch.log -e modify -e move -e create -e delete

## Scripts

- logMsg - Add error/warning and log centrally

- logMsgPortal - DNW on Portal

- crontab - Change ownership to Apache after nightly scripts run

## Prep

- archive.pl - Rework

- archive.pl - PBTV over 1 year

- archive.pl - Special files over 3 months old

- All Perl scripts - Port to Windows ActiveState Perl

- API.pm - Change user to prep@airwave.tv

- API.pm - Move %API into a config file

## Distro

- API.pm - Change user to distro@airwave.tv

- API.pm - Move %API into a config file

- All Airwave software and content - Migrate to a hosted server

- CDS TA - Migrate to a hosted server

- cds.pl - Rewrite with node.js and forever

## API

- SnapTV - List of the ‘coming soon’ movies for individual sites

- Upgrade Gateway3 -> VeryAPI

# Airtime VOD

## Encoding

- Trap if there is no film or trailer file

- Subtitles are not added to the MP4 file correctly

## Immediate

- Tidy up configuration.js

- synopsis.setLanguage - where is this displayed on the UI

- Choose language from Settings

- If login fails due to API error, trap error and display message

- Login should use interface.js (std port) which routes to login.js connector

- 	Merge OTT.events into qplayer or airtime

- What points App to airtime or qplayer?
## Short Term

- Link payments to Stripe

- Encryption required

- Implement location radius checks

- Store config on Mongo

- Load config into App on startup depending on user

- Set menu options in config

- Set functional options in config

## Long Term

- VOD metadata - switch between Airwave and TMDB in config

- Get ratings and enhanced metadata from TMDB

## EPG

- Get EPG from meta-broadcast

- Write HTML/device/day to Mongo

- Only load progs into App for active channels

- Set channel list based on user group

- Parse description for servies/episode: (S4 Ep7/8) [AD,S] S1,E01

- Run EPG generator (grid.js) as a cron job

- Read EPG into App from Mongo

- epg.css -> epg-phone.css and epg-browser.css

- Play TV from Cambridge server

# AirDrop

## Ingest

- Open source file

- Read sequentially in chunks (10MB)
	- Encrypt chunk and change keys every so often
	- Calculate MD5 on chunk
	- Add MD5, chunk ID, offset of chunk in file and key ref to manifest
	- Add key and key ref to key map file
	- Save chunk in file in WIP directory

- Close source file

- Save manifest file

- Upload manifest and key map to Portal

## Upload

- Read list of target servers from Portal

- Upload each chunk to target servers

- Track status of uploaded block

- When all chunks uploaded to a server update Portal

## Download

- Receive notification from the Portal including manifest file and list of available servers

- Update status on Portal

- Make a request to the servers to find best source

- Create an empty file of the correct size

- Read list of chunks from manifest file

- Download key map from Portal

- For each chunk
	- Download chunk from server (can server be changed during download?)
	- Check MD5 of chunk
	- Decrypt chunk
	- Insert chunk into file at offset
	- Update status on Portal

- Close file

- MD5 check of file

- Update status on Portal
