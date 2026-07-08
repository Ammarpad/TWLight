#!/usr/bin/env bash
#
# One-shot database + user setup, invoked from the mariadb container's
# /docker-entrypoint-initdb.d. Reads DJANGO_DB_* and MYSQL_ROOT_PASSWORD
# directly from the environment (env_file'd by the compose overlay).

set -eo pipefail

if [ -n "${MYSQL_ROOT_PASSWORD}" ]
then
    mysql_cmd="mysql -u root -p${MYSQL_ROOT_PASSWORD}"
else
    mysql_cmd="mysql"
fi

${mysql_cmd} <<EOF
CREATE DATABASE IF NOT EXISTS ${DJANGO_DB_NAME};
CREATE DATABASE IF NOT EXISTS test_${DJANGO_DB_NAME};
GRANT ALL PRIVILEGES on \`${DJANGO_DB_NAME}\`.* to ${DJANGO_DB_USER}@'%' IDENTIFIED BY '${DJANGO_DB_PASSWORD}';
GRANT ALL PRIVILEGES on \`test\_${DJANGO_DB_NAME}\`.* to ${DJANGO_DB_USER}@'%' IDENTIFIED BY '${DJANGO_DB_PASSWORD}';
GRANT ALL PRIVILEGES on \`test\_${DJANGO_DB_NAME}\_%\`.* to ${DJANGO_DB_USER}@'%' IDENTIFIED BY '${DJANGO_DB_PASSWORD}';
EOF
