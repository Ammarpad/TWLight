#!/usr/bin/env bash
set -eo pipefail

# Grab deploy metadata and fail early if we're missing something
apt update
apt install -y cron curl jq

metadata_url=http://169.254.169.254/openstack/2025-04-04/meta_data.json
metadata=$(curl -fsS "${metadata_url}") || { echo "failed to fetch instance metadata from ${metadata_url}" >&2; exit 1; }
project=$(jq --raw-output '.meta.project // empty' <<< "${metadata}")
env=$(jq --raw-output '.meta.env // empty' <<< "${metadata}")
: "${project:?meta.project not set in instance metadata}"
: "${env:?meta.env not set in instance metadata}"
# Unix account/group name is lowercased; the checkout dir and GitHub URL
# keep the project's original casing (github.com is case-insensitive).
user="${project,,}"

# Add swap
fallocate -l 8G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
grep -q '^/swapfile ' /etc/fstab || echo "/swapfile none swap sw 0 0">>/etc/fstab

# Add Docker's official GPG key:
apt install -y ca-certificates
mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
arch=$(dpkg --print-architecture)
release=$(. /etc/os-release && echo "$VERSION_CODENAME")
# read -d '' returns non-zero at EOF; the || keeps set -e from aborting here
read -r -d '' docker_list <<- EOF || true
	deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${release} stable
EOF
echo "${docker_list}" > /etc/apt/sources.list.d/docker.list

# Install docker packages
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Rootless mode: install packages
apt install -y dbus-user-session docker-ce-rootless-extras slirp4netns uidmap

# Rootless mode: disable root services
systemctl disable --now docker.socket
systemctl disable --now docker.service
systemctl disable --now containerd.service
rm -f /var/run/docker.sock

# Rootless mode: allow binding to privileged ports
setcap cap_net_bind_service=+ep /usr/bin/rootlesskit

# Rootless mode: set kernel.unprivileged_userns_clone
sysctl -w kernel.unprivileged_userns_clone=1
# /etc/sysctl.d/ gets cleaned out by WMF wikitech puppet, here's another approach:
mkdir -m 0755 -p /usr/local/lib/sysctl.d
echo 'kernel.unprivileged_userns_clone = 1' >/usr/local/lib/sysctl.d/99-userns-clone.conf

# Rootless mode: create shared shell account
adduser --quiet --disabled-password --gecos "" "${user}" || true

# Clone repo and assign ownership to service account
[ -d "/srv/${project}/.git" ] || git clone "https://github.com/WikipediaLibrary/${project}.git" "/srv/${project}"
cd "/srv/${project}" || exit
git checkout "${env}"
chown -R "${user}:${user}" "/srv/${project}"

# make docker data volume mountpoint
mkdir -p /usr/local/docker-data && chown "${user}:${user}" /usr/local/docker-data
# make backup volume mountpoint
mkdir -p /usr/local/backup && chown "${user}:${user}" /usr/local/backup

# Rootless mode: run commands as service account
XDG_RUNTIME_DIR=/run/user/$(id -u "${user}")
sudo -i -u "${user}" bash <<- EOF
	#  symlink to project daemon.json
	mkdir -p ~/.config/docker
	ln -sf /srv/${project}/daemon.json ~/.config/docker/daemon.json
	# Create .env once from the template; a filled-in .env (real secrets,
	# gitignored) then survives re-provisioning untouched.
	[ -f /srv/${project}/.env ] || cp /srv/${project}/template.env /srv/${project}/.env
	# Configure bashrc
	cat <<- BASHRC >> ~/.bashrc
	# Environment variable for Docker Rootless:
	export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}
	export DOCKER_HOST=unix://${XDG_RUNTIME_DIR}/docker.sock
	export COMPOSE_FILE=/srv/${project}/docker-compose.yml:/srv/${project}/docker-compose.${env}.yml
	# Start in ${project} project
	cd /srv/${project}
	BASHRC
EOF
