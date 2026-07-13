#!/usr/bin/env bash

# Environment variables should be loaded under all conditions.
if [ -z "${TWLIGHT_HOME}" ]
then
    exit 1
fi

PATH=/usr/local/bin:/usr/bin:/bin:/sbin:$PATH

echo "Importing TWLight database"

## Drop existing DB.
bash -c "mysql -h '${DJANGO_DB_HOST}' -u '${DJANGO_DB_USER}' -p'${DJANGO_DB_PASSWORD}' -D '${DJANGO_DB_NAME}' -e 'DROP DATABASE ${DJANGO_DB_NAME}; CREATE DATABASE ${DJANGO_DB_NAME};'" | :

## Import the dump streamed on stdin.
bash -c "mysql -h '${DJANGO_DB_HOST}' -u '${DJANGO_DB_USER}' -p'${DJANGO_DB_PASSWORD}' -D '${DJANGO_DB_NAME}'"

echo "Finished importing TWLight database."
