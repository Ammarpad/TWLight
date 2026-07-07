#!/usr/bin/env bash
#
# Runs Django tests (https://docs.djangoproject.com/en/stable/topics/testing/).

set -euo pipefail

{
    echo "[$(date)]"
    echo "Django version: $(python -c 'import django; print(django.get_version())')"

    echo "black --target-version py311 --check TWLight"
    if black --target-version py311 --check TWLight
    then
        echo "${TWLIGHT_HOME}/tests/shunit/twlight_i18n_lint_test.sh"
        "${TWLIGHT_HOME}/tests/shunit/twlight_i18n_lint_test.sh"

        # https://github.com/WikipediaLibrary/TWLight/wiki/Translation
        echo "Checking for localization issues"
        find TWLight -type f \( -name "*.py" \) -print0 | xargs -0 -I % "${TWLIGHT_HOME}/bin/twlight_i18n_lint.pl" %
        echo "No localization issues found"

        # Run test suite via coverage so we can get a report without having to run separate tests for it.
        DJANGO_LOG_LEVEL=CRITICAL DJANGO_SETTINGS_MODULE=TWLight.settings.local \
        coverage run manage.py test --keepdb --noinput --parallel --timing
        coverage report
    else
        # If linting fails, offer some useful feedback to the user.
        black --target-version py311 --quiet --diff TWLight
        echo "You can fix these issues by running the following command on your host"
        echo "docker exec CONTAINER $(which black) -t py311 ${TWLIGHT_HOME}/TWLight"
        exit 1
    fi
} 2>&1
