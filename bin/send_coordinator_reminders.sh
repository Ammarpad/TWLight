#!/usr/bin/env bash
#
# Sends coordinator reminder emails via the send_coordinator_reminders
# management command.

python3 manage.py send_coordinator_reminders --app_status PENDING
