#!/usr/bin/env bash

# Enable debug mode to print all commands
set -x

# Define log file
LOG_DIR="/var/log/miner/custom/fact-hive"
LOG_FILE="$LOG_DIR/miner.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

# Function to handle cleanup when the miner stops
cleanup() {
    echo "Stopping fact-worker Docker container..." | tee -a "$LOG_FILE"
    sudo docker stop fact-worker 2>&1 | tee -a "$LOG_FILE"
    exit 0
}

# Set trap to catch termination signals (SIGTERM, SIGINT)
trap cleanup SIGTERM SIGINT

# Move to the directory containing this script
cd `dirname $0`

# Source the configuration file (fact-hive.conf)
if [[ ! -f fact-hive.conf ]]; then
    echo "Configuration file fact-hive.conf not found. Exiting..."
    exit 1
fi

. fact-hive.conf

# Debug: Print the variables loaded from the configuration file
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

# Check for application.yml and update it if needed
if [[ -f "$APP_YML" ]]; then
    echo "Found application.yml. Checking for updates..."

    CURRENT_USERNAME=$(grep -oP '^username: "\K[^"]+' "$APP_YML")
    CURRENT_PASSWORD=$(grep -oP '^password: "\K[^"]+' "$APP_YML")

    NEEDS_UPDATE=false

    # Compare and update username
    if [[ "$CURRENT_USERNAME" != "$USERNAME" ]]; then
        echo "Updating username in application.yml..."
        sed -i "s/^username: \".*\"/username: \"$USERNAME\"/" "$APP_YML"
        NEEDS_UPDATE=true
    fi

    # Compare and update password
    if [[ "$CURRENT_PASSWORD" != "$PASSWORD" ]]; then
        echo "Updating password in application.yml..."
        sed -i "s/^password: \".*\"/password: \"$PASSWORD\"/" "$APP_YML"
        NEEDS_UPDATE=true
    fi

    # Rebuild worker if updates were applied
    if [[ "$NEEDS_UPDATE" == true ]]; then
        echo "Changes detected. Running rebuild_worker.sh..."
        sh rebuild_worker.sh 2>&1 | tee -a "${CUSTOM_LOG_BASENAME}.log"
    else
        echo "No changes needed for application.yml."
    fi
else
    echo "application.yml not found. Proceeding without updates."
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
