#!/usr/bin/env bash
set -eo pipefail
: '
Post-first-login setup for a TWLight (Library-Card-Platform)
Cloud VPS instance: installs rootless docker for the service
account and enables lingering. Run as the shared service account,
after the cloud-init half (debian-trixie-init.sh) has finished.
'

metadata_url=http://169.254.169.254/openstack/2025-04-04/meta_data.json
metadata=$(curl -fsS "${metadata_url}") || { echo "failed to fetch instance metadata from ${metadata_url}" >&2; exit 1; }
project=$(jq --raw-output '.meta.project // empty' <<< "${metadata}")
env=$(jq --raw-output '.meta.env // empty' <<< "${metadata}")
: "${project:?meta.project not set in instance metadata}"
: "${env:?meta.env not set in instance metadata}"

if [ "$project" != "$USER" ]
then
	echo "must be run as ${project} (currently ${USER})" >&2 && exit 1
fi

# Sanity-check docker's data-root and the backup dir before starting the
# daemon. Both must be writable by us: mode and ownership let our uid write,
# and the filesystem isn't mounted read-only. A freshly-mounted volume still
# owned by root:root (or mounted ro) is the usual culprit. In production both
# must also sit on their own block device: the root fs is too small to hold
# docker data, and filling it took the site down (T430155). Staging and friends
# run off the root fs, so the block-device requirement is production-only.
root_dev=$(stat -c %d /)
on_root_fs() { [ "$(stat -c %d "$1")" = "${root_dev}" ]; }
writable() {
	[ -w "$1" ] || return 1
	case ",$(findmnt -rno VFS-OPTIONS --target "$1")," in
		*,ro,*) return 1 ;;
	esac
}
for dir in /usr/local/docker-data /usr/local/backup
do
	if ! writable "${dir}"
	then
		echo "ERROR: ${dir} is not writable by ${USER}; fix ownership or mount options and re-run" >&2
		exit 1
	fi
	if [ "${env}" = production ] && on_root_fs "${dir}"
	then
		echo "ERROR: production requires ${dir} on its own block device, not the root fs" >&2
		exit 1
	fi
done

# install dockerd rootless for service account
/usr/bin/dockerd-rootless-setuptool.sh install
# Rootless mode: keep daemon running while logged out
loginctl enable-linger "${project}"

# Install the env crontab (auto-deploy + django-cron); cron reaches the
# rootless daemon via the docker context the setuptool switched to above.
crontab "/srv/${project}/conf/${env}.crontab"
