#!/usr/bin/env bash
#
# Runs the LTR -> RTL CSS conversion script and collects static files.

set -eo pipefail

# Generate right to left css.
cd "${TWLIGHT_HOME}" && node twlight_cssjanus

mkdir -p "${TWLIGHT_HOME}/TWLight/collectedstatic"

echo "collectstatic --noinput --clear"
python3 manage.py collectstatic --noinput --clear
