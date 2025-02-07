#!/usr/bin/env bash

# Enable debug mode to print all commands
set -x

# Define log file
LOG_DIR="/var/log/miner/custom/fact-hive"
LOG_FILE="$LOG_DIR/miner.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

# Source h-manifest.conf to get the necessary variables
if [[ ! -f h-manifest.conf ]]; then
    echo "Configuration file h-manifest.conf not found. Exiting..."
    exit 1
fi

. h-manifest.conf

# Source the custom configuration file
if [[ ! -f $CUSTOM_CONFIG_FILENAME ]]; then
    echo "Configuration file $CUSTOM_CONFIG_FILENAME not found. Exiting..."
    exit 1
fi

. $CUSTOM_CONFIG_FILENAME

# Debug: Print the variables loaded from h-manifest.conf and fact-hive.conf
echo "USERNAME = $USERNAME"
echo "PASSWORD = $PASSWORD"
echo "CUSTOM_LOG_BASEDIR = $CUSTOM_LOG_BASEDIR"
echo "CUSTOM_LOG_BASENAME = $CUSTOM_LOG_BASENAME"
echo "CUSTOM_CONFIG_FILENAME = $CUSTOM_CONFIG_FILENAME"

# Ensure required variables are set
[[ -z $CUSTOM_LOG_BASENAME ]] && echo "No CUSTOM_LOG_BASENAME is set. Exiting..." && exit 1
[[ -z $CUSTOM_CONFIG_FILENAME ]] && echo "No CUSTOM_CONFIG_FILENAME is set. Exiting..." && exit 1
[[ ! -f $CUSTOM_CONFIG_FILENAME ]] && echo "Custom config $CUSTOM_CONFIG_FILENAME is not found. Exiting..." && exit 1

# Ensure the log directory exists
[[ ! -d $CUSTOM_LOG_BASEDIR ]] && mkdir -p "$CUSTOM_LOG_BASEDIR"

# Path to application.yml on the host system
APP_YML="/hive/miners/custom/fact-hive/application.yml"

# Function to handle cleanup when the miner stops
cleanup() {
    echo "Stopping fact-worker Docker container..." | tee -a "$LOG_FILE"
    sudo docker stop fact-worker 2>&1 | tee -a "$LOG_FILE"
    exit 0
}

# Set trap to catch termination signals (SIGTERM, SIGINT)
trap cleanup SIGTERM SIGINT

# Check for application.yml and update it if needed
if [[ ! -s "$APP_YML" ]]; then
    echo "Error: application.yml is either missing or blank. Rewriting the file..."
    NEEDS_UPDATE=true
else
    echo "Found application.yml. Checking for updates..."

    CURRENT_USERNAME=$(grep -oP '^username: "\K[^"]+' "$APP_YML")
    CURRENT_PASSWORD=$(grep -oP '^password: "\K[^"]+' "$APP_YML")

    NEEDS_UPDATE=false

    # Check if username matches
    if [[ "$CURRENT_USERNAME" != "$USERNAME" ]]; then
        echo "Username mismatch detected. Updating..."
        NEEDS_UPDATE=true
    fi

    # Check if password matches
    if [[ "$CURRENT_PASSWORD" != "$PASSWORD" ]]; then
        echo "Password mismatch detected. Updating..."
        NEEDS_UPDATE=true
    fi
fi

# Rewrite application.yml if needed
if [[ "$NEEDS_UPDATE" == true ]]; then
    echo "Writing updated application.yml..."
    echo -e "username: \"$USERNAME\"\npassword: \"$PASSWORD\"" > "$APP_YML"
    echo "application.yml updated successfully."
else
    echo "No changes needed for application.yml."
fi

# Start the fact-worker Docker container
if ! sudo docker ps -a --format "{{.Names}}" | grep -q "^fact-worker$"; then
    echo "fact-worker container not found. Installing..."
    wget -O setup_worker.sh https://github.com/filthz/fact-worker-public/releases/download/base_files/setup_worker.sh 2>&1 | tee -a "${CUSTOM_LOG_BASENAME}.log"
    chmod +x setup_worker.sh
    sh setup_worker.sh "$USERNAME" "$PASSWORD" 2>&1 | tee -a "${CUSTOM_LOG_BASENAME}.log"
else
    echo "Starting fact-worker container..."
    sudo docker start fact-worker 2>&1 | tee -a "${CUSTOM_LOG_BASENAME}.log"
fi

# Keep the script running to prevent Hive OS from marking it as stopped
echo "Monitoring Docker logs..."
sudo docker logs -f fact-worker 2>&1 | tee -a "${CUSTOM_LOG_BASENAME}.log"
