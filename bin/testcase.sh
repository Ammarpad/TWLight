#!/usr/bin/env bash
#
# Runs a specific set of Django tests, rather than all of them.

if [ -z "$1" ]; then
    echo "Please specify a test case."
    exit 1
fi

DJANGO_LOG_LEVEL=CRITICAL DJANGO_SETTINGS_MODULE=TWLight.settings.local \
    coverage run --source TWLight manage.py test --parallel --keepdb --noinput --timing "$1" 2>&1
