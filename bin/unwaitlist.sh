#!/usr/bin/env bash
#
# Un-waitlists proxy partners having at least one available account.

echo "Probing for waitlisted partners with at least one available account"
python3 manage.py proxy_waitlist_disable
