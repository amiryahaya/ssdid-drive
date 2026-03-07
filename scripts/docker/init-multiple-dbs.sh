#!/bin/bash
# PostgreSQL Multi-Database Initialization Script
# Creates multiple databases and users for SecureSharing services
#
# Environment Variables:
#   POSTGRES_USER: Primary admin user (default: securesharing)
#   POSTGRES_MULTIPLE_DATABASES: Comma-separated list of databases to create
#
# Usage: This script is mounted to /docker-entrypoint-initdb.d/ and runs automatically

set -e
set -u

# Function to create database and user
function create_database() {
    local database=$1
    echo "Creating database '$database' ..."

    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
        CREATE DATABASE "$database";
        GRANT ALL PRIVILEGES ON DATABASE "$database" TO "$POSTGRES_USER";
EOSQL

    echo "Database '$database' created successfully"
}

# Parse POSTGRES_MULTIPLE_DATABASES environment variable
if [ -n "${POSTGRES_MULTIPLE_DATABASES:-}" ]; then
    echo "========================================"
    echo "Multiple database creation requested"
    echo "Databases: $POSTGRES_MULTIPLE_DATABASES"
    echo "========================================"

    for db in $(echo $POSTGRES_MULTIPLE_DATABASES | tr ',' ' '); do
        create_database $db
    done

    echo "========================================"
    echo "All databases created successfully"
    echo "========================================"
fi

# Create extensions commonly needed
echo "Creating common extensions..."

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Enable UUID functions
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    -- Enable crypto functions (for secure comparisons)
    CREATE EXTENSION IF NOT EXISTS pgcrypto;
EOSQL

# Create extensions in additional databases
if [ -n "${POSTGRES_MULTIPLE_DATABASES:-}" ]; then
    for db in $(echo $POSTGRES_MULTIPLE_DATABASES | tr ',' ' '); do
        echo "Creating extensions in '$db'..."
        psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db" <<-EOSQL
            CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
            CREATE EXTENSION IF NOT EXISTS pgcrypto;
EOSQL
    done
fi

echo "PostgreSQL initialization complete!"
