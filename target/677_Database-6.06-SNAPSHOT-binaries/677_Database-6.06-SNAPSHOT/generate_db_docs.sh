#!/bin/bash
java -cp liquibase-core-3.4.1.jar:postgresql-9.3-1101-jdbc4.jar:677_Database-6.06-SNAPSHOT.jar liquibase.integration.commandline.Main \
  --driver=org.postgresql.Driver \
  --url=jdbc:postgresql://localhost:5432/bluetruth \
  --username=bluetruth --password=ssl1324 \
  --changeLogFile=db.changelog-master.xml \
  dbDoc dbdocs
