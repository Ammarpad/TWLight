#!/usr/bin/env bash
#
# One-shot redeploy for the rootless docker compose stack. Pulls the
# branch_${env} image tag; if a newer image was fetched, syncs the
# local repo checkout and restarts the stack.

set -eo pipefail

if [ -z "$1" ]; then
    echo "Usage: deploy.sh \$env (staging | production)"
    exit 1
fi

env=${1}
tag="branch_${env}"

cd /srv/TWLight || { echo "Repo missing at /srv/TWLight"; exit 1; }

pull=$(docker pull "quay.io/wikipedialibrary/twlight:${tag}")

if echo "${pull}" | grep -q "Status: Downloaded newer image"
then
    # Staging accepts divergent history from the auto-deploy remote.
    if [ "${env}" = "staging" ]
    then
        git fetch
        git reset --hard origin
    fi
    git pull
    # git pull refreshes conf/${env}.crontab in the checkout but not the
    # installed crontab, so re-sync it here on real deploys.
    crontab "conf/${env}.crontab"
    docker compose -f docker-compose.yml -f "docker-compose.${env}.yml" up -d
elif echo "${pull}" | grep -q "Status: Image is up to date"
then
    echo "Up to date"
else
    echo "Error"
    exit 1
fi
