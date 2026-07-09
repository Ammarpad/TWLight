#!/usr/bin/env bash
#
# Generates example data for local development. Log in to the account
# you want to be a superuser first.

set -eo pipefail

echo "Creating user data"
python3 manage.py user_example_data 200

echo "Creating resource data"
python3 manage.py resources_example_data 50

echo "Creating applications data"
python3 manage.py applications_example_data 1000
