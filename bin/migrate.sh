#!/usr/bin/env bash
#
# Runs the full Django migration process
# (https://docs.djangoproject.com/en/stable/topics/migrations/).

set -eo pipefail

"${TWLIGHT_HOME}/bin/wait_for_db.sh"

echo "migrate"
# createinitialrevisions fails on existing installs; ignore.
python3 "${TWLIGHT_HOME}/manage.py" createinitialrevisions || :
python3 "${TWLIGHT_HOME}/manage.py" makemigrations || exit 1

if ! python3 "${TWLIGHT_HOME}/manage.py" migrate; then
    python3 "${TWLIGHT_HOME}/manage.py" migrate
fi

# List of TWLIGHT_APPS
apps=($(python3 "${TWLIGHT_HOME}/manage.py" diffsettings | grep 'TWLIGHT_APPS' | grep -o "'[^']*'" | xargs))
for path in "${apps[@]}"; do
    # Strip 'TWLight.' from the front of each TWLIGHT_APP
    app=${path:8}
    # skip apps that don't need migrations
    if [ ! -d "${app}/migrations" ]; then
        continue
    fi
    echo "createinitialrevisions ${app}"
    python3 "${TWLIGHT_HOME}/manage.py" createinitialrevisions ${app} || :
    echo "makemigrations ${app}"
    python3 "${TWLIGHT_HOME}/manage.py" makemigrations ${app} || exit 1
    echo "migrate ${app}"
    if ! python3 "${TWLIGHT_HOME}/manage.py" migrate ${app}; then
        python3 "${TWLIGHT_HOME}/manage.py" migrate ${app}
    fi
done

# Run black on all migrations.
find "${TWLIGHT_HOME}/TWLight" -type d -name "migrations" -print0 | xargs -0 black -t py311
