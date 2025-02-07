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
[[ -z $CUSTOM_LOG_BASENAME ]] && echo "No CUSTOM_LOG_BASEDIR is set. Exiting..." && exit 1
[[ -z $CUSTOM_CONFIG_FILENAME ]] && echo "No CUSTOM_CONFIG_FILENAME is set. Exiting..." && exit 1
[[ ! -f $CUSTOM_CONFIG_FILENAME ]] && echo "Custom config $CUSTOM_CONFIG_FILENAME is not found. Exiting..." && exit 1

# Ensure the log directory exists
[[ ! -d $CUSTOM_LOG_BASEDIR ]] && mkdir -p "$CUSTOM_LOG_BASEDIR"

# Path to application.yml on the host system
APP_YML="/hive/miners/custom/fact-hive/application.yml"

# Full path to rebuild_worker.sh and setup_worker.sh
REBUILD_SCRIPT="/hive/miners/custom/fact-hive/rebuild_worker.sh"
SETUP_SCRIPT="/hive/miners/custom/fact-hive/setup_worker.sh"

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
    echo -e "username: \"$USERNAME\"\npassword: \"$PASSWORD\"" > "$APP_YML"
    echo "application.yml updated successfully."
fi

# Check if setup_worker.sh exists (indicates if setup has ever run)
if [[ ! -f $SETUP_SCRIPT ]]; then
    echo "setup_worker.sh not found. Downloading it..."
    wget -O $SETUP_SCRIPT https://github.com/filthz/fact-worker-public/releases/download/base_files/setup_worker.sh 2>&1 | tee -a "$LOG_FILE"
    chmod +x $SETUP_SCRIPT
fi

# Check if Docker exists and fix issues if needed
if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. Installing Docker..."
    sudo apt-get install -y iptables arptables ebtables 2>&1 | tee -a "$LOG_FILE"
    sudo update-alternatives --set iptables /usr/sbin/iptables-legacy 2>&1 | tee -a "$LOG_FILE"
    sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>&1 | tee -a "$LOG_FILE"
    sudo systemctl enable --now docker 2>&1 | tee -a "$LOG_FILE"
    sudo systemctl restart docker 2>&1 | tee -a "$LOG_FILE"

    # Wait for Docker to start
    echo "Waiting for Docker to start..."
    for i in {1..10}; do
        if sudo docker ps &> /dev/null; then
            echo "Docker is running now."
            break
        fi
        echo "Retrying... ($i/10)"
        sleep 5
    done

    if ! sudo docker ps &> /dev/null; then
        echo "Docker daemon could not be started. Exiting..." | tee -a "$LOG_FILE"
        exit 1
    fi
fi

# Start or install the fact-worker Docker container
if ! sudo docker ps -a --format "{{.Names}}" | grep -q "^fact-worker$"; then
    echo "fact-worker container not found. Installing..."
    if ! sh $SETUP_SCRIPT "$USERNAME" "$PASSWORD" 2>&1 | tee -a "$LOG_FILE"; then
        echo "setup_worker.sh failed. Exiting..."
        exit 1
    fi
else
    echo "Starting fact-worker container..."
    sudo docker start fact-worker 2>&1 | tee -a "$LOG_FILE"
fi

# Keep the script running to prevent Hive OS from marking it as stopped
echo "Monitoring Docker logs..."
sudo docker logs -f fact-worker 2>&1 | tee -a "$LOG_FILE"
