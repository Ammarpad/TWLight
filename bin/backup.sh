#!/usr/bin/env bash

set -eo pipefail

# Use a lockfile to prevent overruns.
self=$(basename ${0})
exec {lockfile}>/var/lock/${self}
flock -n ${lockfile}
{

    # Environment variables should be loaded under all conditions.
    if [ -z "${TWLIGHT_HOME}" ]
    then
        exit 1
    fi

    PATH=/usr/local/bin:/usr/bin:/bin:/sbin:$PATH

    : "${TWLIGHT_BACKUP_KEEP:=30}"
    : "${TWLIGHT_BACKUP_DAYS:=30}"

    date=$(date +'%Y%m%d%H%M')

    ## Dump DB

    source ${TWLIGHT_HOME}/bin/mysqldump.sh

    echo "Backing up database and media"

    ## Perform backup
    tar -czf "${TWLIGHT_BACKUP_DIR}/${date}.tar.gz" -C "${TWLIGHT_BACKUP_DIR}" "./twlight.sql" -C "${TWLIGHT_HOME}" "./media"

    ## Root only
    chmod 0600 "${TWLIGHT_BACKUP_DIR}/${date}.tar.gz"

    ## The uncompressed dump was only scaffolding for the tarball; drop it so a
    ## full dump doesn't linger on the backup volume between runs.
    rm -f "${TWLIGHT_BACKUP_DIR}/twlight.sql"

    echo "Finished TWLight backup."

    ## Prune backups past either limit: older than TWLIGHT_BACKUP_DAYS days, or
    ## beyond the newest TWLIGHT_BACKUP_KEEP. Whichever bites first: count where a
    ## box redeploys often, age otherwise.
    find "${TWLIGHT_BACKUP_DIR}" -maxdepth 1 -name "*.tar.gz" -mtime "+${TWLIGHT_BACKUP_DAYS}" -delete || :
    mapfile -t stale < <(
        find "${TWLIGHT_BACKUP_DIR}" -maxdepth 1 -name "*.tar.gz" -printf "%T@ %p\n" \
            | sort -rn | tail -n +$((TWLIGHT_BACKUP_KEEP + 1)) | cut -d' ' -f2-
    )
    [ "${#stale[@]}" -eq 0 ] || rm -f "${stale[@]}"

    echo "Kept the newest ${TWLIGHT_BACKUP_KEEP} backups within ${TWLIGHT_BACKUP_DAYS} days."
} {lockfile}>&-
