#!/bin/bash

# Copy this script onto the SECONDARY BLUETRUTH server in folder /home/admin/livescripts/live

# Bluetruth KENT Script

# Username and database details to access the PostGres server.
USERNAME=bluetruth
DBNAME=bluetruth

EXPIRYDAYS=7
CURRENTTIME='NOW()::date'
FILELOCATION=/home/admin/livescripts/live/livedatacsv/                                                               
FILENAME=${FILELOCATION}bluetruth_kent_span_journey.csv
FILENAMEDETECTOR=${FILELOCATION}bluetruth_kent_detector.csv
DATABASEIP=192.168.11.206

#Kent Id's - 176545 and 176547. So based these ID's span_name to search for is A20%. 
KENTSPAN1='A20 Beaver Road to A20 Bower Mount Road'
KENTSPAN2='A20 Bower Mount Road to A20 Beaver Road'

SQL_QUERY="select * from span_journey_detection where span_name LIKE 'A20%' and completed_timestamp > ${CURRENTTIME} - interval '${EXPIRYDAYS}' DAY"

SQL_QUERY_DETECTOR="select detector_id, device_id, detection_timestamp from device_detection_historic where detection_timestamp > ${CURRENTTIME} - interval '${EXPIRYDAYS}' DAY and (detector_id = '176545' OR detector_id = '176547' OR detector_id ='178517') ORDER BY detection_timestamp DESC"

startdate=$(date -d '- '${EXPIRYDAYS}' days' +'%d/%m/%Y')

#Email Details
BODY="Bluetruth kent region detector and span journey time details for last ${EXPIRYDAYS} days(${startdate} - $(date +'%d/%m/%Y')). Please find zip file attached to this email."
FROM="bluetruth@simulation-systems.co.uk"
CC="neelesh.chavan@simulation-systems.co.uk, bluetruth@simulation-systems.co.uk"
TO="fs_operations@clearviewtraffic.com"
#TO="neelesh.chavan@simulation-systems.co.uk"
#CC="neelesh.chavan@simulation-systems.co.uk"
SUBJECT="Bluetruth KENT region detector and journey time details"
ZIPFILE=${FILELOCATION}bluetruth_kent_span_journey.zip
ZIPFILEDETECTOR=${FILELOCATION}bluetruth_kent_detector.zip

if [ -f $FILENAME -o -f $FILENAMEDETECTOR ]
then
	rm -rf $FILENAME
	rm -rf $FILENAMEDETECTOR
fi
if [ -f "$ZIPFILE" -o -f $ZIPFILEDETECTOR ]
then 
	rm -rf $ZIPFILE
	rm -rf $ZIPFILEDETECTOR
fi

/opt/postgres/9.1/bin/psql -F , --no-align -U $USERNAME -d $DBNAME -h $DATABASEIP -c "$SQL_QUERY" > $FILENAME

/opt/postgres/9.1/bin/psql -F , --no-align -U $USERNAME -d $DBNAME -h $DATABASEIP -c "$SQL_QUERY_DETECTOR" > $FILENAMEDETECTOR

gzip -c $FILENAME > $ZIPFILE
gzip -c $FILENAMEDETECTOR > $ZIPFILEDETECTOR

mail -s "$SUBJECT" -r "$FROM" -c "$CC" -a $ZIPFILE -a $ZIPFILEDETECTOR $TO  <<< $BODY

