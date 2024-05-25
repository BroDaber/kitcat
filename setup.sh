#!/bin/bash -ex

# Function to log messages
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Ensure essential commands are available
for cmd in psql awk sed cp systemctl; do
    if ! command_exists $cmd; then
        log "Error: Required command $cmd is not available."
        exit 1
    fi
done

# Function to check if PostgreSQL 15 is installed
check_postgres_15_installed() {
    if [ -d /etc/postgresql/15 ]; then
        log "PostgreSQL 15 is installed"
        return 0
    else
        log "PostgreSQL 15 is not installed"
        return 1
    fi
}

# Function to set PostgreSQL 15 as the default
set_postgres_15_as_default() {
    update-alternatives --set postgresql /usr/lib/postgresql/15/bin/psql
    DEFAULT_PG_VERSION=$(psql -V | awk '{print $3}')
    log "PostgreSQL 15 is now the default version: $DEFAULT_PG_VERSION"
}

# Function to ensure PostgreSQL 15 uses default port 5432
ensure_default_port_5432() {
    PG_CONF="/etc/postgresql/15/main/postgresql.conf"
    if grep -q "^port = 5432" $PG_CONF; then
        log "PostgreSQL 15 is set to use the default port 5432"
    else
        log "Setting PostgreSQL 15 to use the default port 5432"
        sed -i "s/^#port = 5432/port = 5432/" $PG_CONF
    fi
}

# Function to update pg_hba.conf
update_pg_hba_conf() {
    if [ -f /etc/postgresql/15/main/pg_hba.conf ]; then
        cp /etc/postgresql/15/main/pg_hba.conf /etc/postgresql/15/main/pg_hba.conf.orig
        awk '{if($1 == "local"){ gsub("peer","trust",$4) }print $0}' /etc/postgresql/15/main/pg_hba.conf.orig > /etc/postgresql/15/main/pg_hba.conf
    else
        log "Error: pg_hba.conf not found"
        exit 1
    fi
}

# Function to configure PostgreSQL user and database
configure_postgres() {
    log "Altering PostgreSQL user and creating database"
    psql -U postgres << EOF
      ALTER USER postgres WITH PASSWORD 'password';
      CREATE DATABASE catsdb;
EOF
    if [ $? -ne 0 ]; then
        log "Error: Failed to alter user and create database"
        exit 1
    else
        log "Successfully altered user and created database"
    fi

    log "Importing database schema from db/catsploit.sql"
    psql -U postgres catsdb < db/catsploit.sql
    if [ $? -ne 0 ]; then
        log "Error: Failed to import database schema"
        exit 1
    else
        log "Successfully imported database schema"
    fi
}

# Update package list and install necessary packages
log "Updating package list and installing necessary packages"
apt update && apt install -y python3-gvm python3-numpy python3-pandas python3-psycopg2 python3-pymetasploit3 python3-rich python3-ruamel.yaml python3-torch gvm greenbone-security-assistant postgresql

# Install Python packages
log "Installing Python packages"
pip3 install pgmpy pyperplan pg8000

# Check the default PostgreSQL version
DEFAULT_PG_VERSION=$(psql -V | awk '{print $3}')
log "Default PostgreSQL version is $DEFAULT_PG_VERSION"

# Check if PostgreSQL 15 is installed and set it as the default if it is
if check_postgres_15_installed; then
    set_postgres_15_as_default
else
    log "Exiting script as PostgreSQL 15 is not installed"
    exit 1
fi

# Ensure the default port for PostgreSQL 15 is 5432
ensure_default_port_5432

# Stop PostgreSQL service
log "Stopping PostgreSQL service"
systemctl stop postgresql

# Update pg_hba.conf to allow local connections without a password
update_pg_hba_conf

# Start PostgreSQL service
log "Starting PostgreSQL service"
systemctl start postgresql

# Configure PostgreSQL user and database
configure_postgres

# Stop PostgreSQL service
log "Stopping PostgreSQL service"
systemctl stop postgresql

# Stop ospd-openvas service
log "Stopping ospd-openvas service"
systemctl stop ospd-openvas

# Run gvm-setup
log "Running gvm-setup"
gvm-setup

# Add user to _gvm group
log "Adding user kali to _gvm group"
usermod -aG _gvm kali

# Set new password for GVM admin user
log "Setting new password for GVM admin user"
sudo -u _gvm gvmd --user=admin --new-password=password

# Check GVM setup
log "Checking GVM setup"
gvm-check-setup

# Set SUID for nmap
log "Setting SUID for nmap"
chmod u+s /usr/bin/nmap
