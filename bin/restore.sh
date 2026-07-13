#!/usr/bin/env bash

set -eo pipefail

if [  -z "$1" ]; then
    echo "Please specify a backup file."
    exit 1
fi

# Environment variables should be loaded under all conditions.
if [ -z "${TWLIGHT_HOME}" ]
then
    exit 1
fi

PATH=/usr/local/bin:/usr/bin:/bin:/sbin:$PATH

restore_file=${1}

## A valid backup carries both the DB dump and media. Verify both are present
## up front, so a malformed or wrong-format archive fails here rather than after
## mysqlimport.sh has already dropped the live database.
for member in ./twlight.sql ./media
do
    if ! tar -tzf "${restore_file}" "${member}" > /dev/null 2>&1
    then
        echo "restore: ${restore_file} is missing ${member}; aborting" >&2
        exit 1
    fi
done

## Restore media into place.
tar -xvzf "${restore_file}" -C "${TWLIGHT_HOME}" --no-overwrite-dir ./media

## Stream the DB dump straight from the tarball into the import so the
## uncompressed SQL never lands on disk.
if "${TWLIGHT_HOME}/bin/wait_for_db.sh"
then
    tar -xzOf "${restore_file}" ./twlight.sql | "${TWLIGHT_HOME}/bin/mysqlimport.sh"
fi

## Only media needs reowning; a chown -R over TWLIGHT_HOME trips on the backup
## mount's root-owned lost+found and aborts the script under set -e.
chown -R "${TWLIGHT_UNIXNAME}" "${TWLIGHT_HOME}/media"
find "${TWLIGHT_HOME}/media" -type f -exec chmod 644 {} +

## Run any necessary DB operations.
"${TWLIGHT_HOME}/bin/migrate.sh"

echo "Finished TWLight restore."
