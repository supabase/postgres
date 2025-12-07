#!/bin/bash
#
# Scripts in this directory are run during the build process.
# each script will be uploaded to /tmp on your build droplet, 
# given execute permissions and run.  The cleanup process will
# remove the scripts from your build system after they have run
# if you use the build_image task.
#
echo "Commencing Checks"

function check_database_is_ready {
    echo -e "\nChecking if database is ready and accepting connections:"
    if [ "$(pg_isready)" = "/tmp:5432 - accepting connections" ]; then
        echo "Database is ready"
    else
        echo "Error: Database is not ready. Exiting"
        exit 1
    fi
}

function check_postgres_owned_dir_exists {
    DIR=$1
    USER="postgres"

    echo -e "\nChecking if $DIR exists and owned by postgres user:" 

    if [ -d "$DIR" ]; then
        echo "$DIR exists"
        if [ $(stat -c '%U' $DIR) = "$USER" ]; then
            echo "$DIR is owned by $USER"
        else
            echo "Error: $DIR is not owned by $USER"
            exit 1
        fi
    else
        echo "Error: ${DIR} not found. Exiting."
        exit 1
    fi
}

function check_lse_enabled {
    ARCH=$(uname -m)
    if [ $ARCH = "aarch64" ]; then
        echo -e "\nArchitecture is $ARCH. Checking for LSE:"

        LSE_COUNT=$(objdump -d /usr/lib/postgresql/bin/postgres | grep -i 'ldxr\|ldaxr\|stxr\|stlxr' | wc -l)
        MOUTLINE_ATOMICS_COUNT=$(nm /usr/lib/postgresql/bin/postgres | grep __aarch64_have_lse_atomics | wc -l)

        # Checking for load and store exclusives    
        if [ $LSE_COUNT -gt 0 ]; then
            echo "Postgres has LSE enabled" 
        else
            echo "Error: Postgres failed to be compiled with LSE. Exiting"
            exit 1
        fi

        # Checking if successfully compiled with -moutline-atomics
        if [ $MOUTLINE_ATOMICS_COUNT -gt 0 ]; then
            echo "Postgres has been compiled with -moutline-atomics" 
        else
            echo "Error: Postgres failed to be compiled with -moutline-atomics. Exiting"
            exit 1
        fi
    else
        echo "Architecture is $ARCH. Not checking for LSE."
    fi
}

check_database_is_ready
check_postgres_owned_dir_exists "/var/lib/postgresql"
check_postgres_owned_dir_exists "/etc/postgresql"
check_lse_enabled