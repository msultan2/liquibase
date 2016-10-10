#!/bin/bash

# Copy this script onto the SECONDARY BLUETRUTH server in folder /home/admin/livescripts/live

# Bluetruth Dartford Script

# Username and database details to access the PostGres server.
USERNAME=bluetruth
DBNAME=bluetruth

EXPIRYDAYS=7
CURRENTTIME='NOW()::date'
FILELOCATION=/home/admin/livescripts/live/livedatacsv/                                                              
FILENAME=${FILELOCATION}bluetruth_dartford_span_journey.csv
FILENAMEDETECTOR=${FILELOCATION}bluetruth_dartford_detector.csv
DATABASEIP=192.168.11.206

#Dartford has IDs - 178534, 178539, 178540, 190501
DARTFORDSPAN='M25%'

SQL_QUERY="select * from span_journey_detection where span_name LIKE '${DARTFORDSPAN}' and completed_timestamp > ${CURRENTTIME} - interval '${EXPIRYDAYS}' DAY"

SQL_QUERY_DETECTOR="select detector_id, device_id, detection_timestamp from device_detection_historic where detection_timestamp > ${CURRENTTIME} - interval '${EXPIRYDAYS}' DAY and (detector_id = '178534' OR detector_id = '178539' OR detector_id = '178540' OR detector_id = '190501') ORDER BY detection_timestamp DESC"

startdate=$(date -d '- '${EXPIRYDAYS}' days' +'%d/%m/%Y')

#Email Details
BODY="Bluetruth DARTFORD region detector and span journey details for last ${EXPIRYDAYS} days(${startdate} - $(date +'%d/%m/%Y')). Please find zip file attached to this email."
FROM="bluetruth@simulation-systems.co.uk"
#CC="neelesh.chavan@simulation-systems.co.uk"
#TO="neelesh.chavan@simulation-systems.co.uk"
CC="neelesh.chavan@simulation-systems.co.uk, bluetruth@simulation-systems.co.uk"
TO="fs_operations@clearviewtraffic.com"
SUBJECT="Bluetruth DARTFORD region detector and journey time details"

ZIPFILE=${FILELOCATION}bluetruth_dartford_span_journey.zip
ZIPFILEDETECTOR=${FILELOCATION}bluetruth_dartford_detector.zip

if [ -f $FILENAME -o -f $FILENAMEDETECTOR ];
then
	rm -rf $FILENAME
	rm -rf $FILENAMEDETECTOR  
fi

if [ -f $ZIPFILE -o -f $ZIPFILEDETECTOR ];
then 
	rm -rf $ZIPFILE
	rm -rf $ZIPFILEDETECTOR
fi

/opt/postgres/9.1/bin/psql -F , --no-align -U $USERNAME -d $DBNAME -h $DATABASEIP -c "$SQL_QUERY" > $FILENAME

/opt/postgres/9.1/bin/psql -F , --no-align -U $USERNAME -d $DBNAME -h $DATABASEIP -c "$SQL_QUERY_DETECTOR" > $FILENAMEDETECTOR

gzip -c $FILENAME > $ZIPFILE
gzip -c $FILENAMEDETECTOR > $ZIPFILEDETECTOR

mail -s "$SUBJECT" -r "$FROM" -c "$CC" -a $ZIPFILE -a $ZIPFILEDETECTOR $TO  <<< $BODY
