#!/bin/bash
set -eu
# ==================================================================================== #
# VARIABLES
# ==================================================================================== #
# Set the timezone for the server.
TIMEZONE=America/Sao_Paulo

# Set the name of the new user to create.
USERNAME=greenlight

# Prompt to enter a password for the PostgreSQL greenlight user.
read -s -p "Enter password for greenlight DB user: " DB_PASSWORD
echo

# Set locale environment variables.
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8

# ==================================================================================== #
# SCRIPT LOGIC
# ==================================================================================== #

# Enable the "universe" repository.
sudo add-apt-repository --yes universe

# Update all software packages.
sudo apt update

# Set the system timezone and install all locales.
sudo timedatectl set-timezone "${TIMEZONE}"
sudo apt --yes install locales-all

# Add the new user (and give them sudo privileges).
sudo useradd --create-home --shell "/bin/bash" --groups sudo "${USERNAME}"

# Force a password to be set for the new user the first time they log in.
sudo passwd --delete "${USERNAME}"
sudo chage --lastday 0 "${USERNAME}"

# Copy the SSH keys from the root user to the new user.
sudo rsync --archive --chown="${USERNAME}:${USERNAME}" /root/.ssh "/home/${USERNAME}"

# Configure the firewall to allow SSH, HTTP and HTTPS traffic.
sudo ufw allow 22
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable

# Install fail2ban.
sudo apt --yes install fail2ban

# Install the migrate CLI tool.
curl -L https://github.com/golang-migrate/migrate/releases/download/v4.14.1/migrate.linux-amd64.tar.gz | tar xvz
sudo mv migrate.linux-amd64 /usr/local/bin/migrate

# Install PostgreSQL.
sudo apt --yes install postgresql

# Set up the greenlight DB and create a user account with the password entered earlier.
sudo -i -u postgres psql -c "CREATE DATABASE greenlight"
sudo -i -u postgres psql -d greenlight -c "CREATE EXTENSION IF NOT EXISTS citext"
sudo -i -u postgres psql -d greenlight -c "CREATE ROLE greenlight WITH LOGIN PASSWORD '$(printf '%q' "${DB_PASSWORD}")'"

# Add a DSN to system-wide environment variables.
echo "GREENLIGHT_DB_DSN='postgres://greenlight:${DB_PASSWORD}@localhost/greenlight'" | sudo tee -a /etc/environment > /dev/null

# Install Caddy (see https://caddyserver.com/docs/install#debian-ubuntu-raspbian).
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt --yes install caddy

# Upgrade all packages. Replace config files with newer ones if needed.
sudo apt --yes -o Dpkg::Options::="--force-confnew" upgrade

echo "Script complete! Rebooting..."
sudo reboot
