#!/bin/bash
echo "Going to run"
java -cp liquibase-core-${liquibase.version}.jar:postgresql-${postgres.version}.jar:${build.finalName}.jar liquibase.integration.commandline.Main \
  --driver=org.postgresql.Driver \
  --url=jdbc:postgresql://${database.connection.address}:${database.connection.port}/${database.connection.dbname} \
  --username=${database.connection.username} --password=${database.connection.password} \
  --changeLogFile=db.changelog-master.xml \
  updateSQL

java -cp liquibase-core-${liquibase.version}.jar:postgresql-${postgres.version}.jar:${build.finalName}.jar liquibase.integration.commandline.Main \
  --driver=org.postgresql.Driver \
  --url=jdbc:postgresql://${database.connection.address}:${database.connection.port}/${database.connection.dbname} \
  --username=${database.connection.username} --password=${database.connection.password} \
  --changeLogFile=db.changelog-master.xml \
  update