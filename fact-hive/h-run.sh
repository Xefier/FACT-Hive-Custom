#!/usr/bin/env bash

# Enable debug mode to print all commands
set -x

# Define log file
LOG_DIR="/var/log/miner/custom"
LOG_FILE="$LOG_DIR/miner.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

# Debug: Print the received environment variables
echo "CUSTOM_TEMPLATE: $CUSTOM_TEMPLATE" | tee -a "$LOG_FILE"
echo "CUSTOM_PASS: $CUSTOM_PASS" | tee -a "$LOG_FILE"

# Extract wallet and password
WALLET="${CUSTOM_TEMPLATE:-default_wallet_address}"
PASS="${CUSTOM_PASS:-x}"  # Default to "x" if CUSTOM_PASS is empty

# Clear previous logs
echo "Starting fact-worker with WALLET=$WALLET and PASS=$PASS" | tee "$LOG_FILE"

# Path to application.yml on the host system
APP_YML="./application.yml"  # Replace with the actual path to application.yml on your host

# Check if fact-worker exists in Docker
if ! sudo docker ps -a --format "{{.Names}}" | grep -q "^fact-worker$"; then
    echo "fact-worker not found. Installing..." | tee -a "$LOG_FILE"
    
    wget -O setup_worker.sh https://github.com/filthz/fact-worker-public/releases/download/base_files/setup_worker.sh 2>&1 | tee -a "$LOG_FILE"
    chmod +x setup_worker.sh 2>&1 | tee -a "$LOG_FILE"
    sh setup_worker.sh "$WALLET" "$PASS" 2>&1 | tee -a "$LOG_FILE"

    # Install required dependencies
    sudo apt-get install -y iptables arptables ebtables 2>&1 | tee -a "$LOG_FILE"
    sudo update-alternatives --set iptables /usr/sbin/iptables-legacy 2>&1 | tee -a "$LOG_FILE"
    sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>&1 | tee -a "$LOG_FILE"

    # Ensure Docker is running
    sudo systemctl enable --now docker 2>&1 | tee -a "$LOG_FILE"
    sudo systemctl restart docker 2>&1 | tee -a "$LOG_FILE"

    # Re-run setup in case Docker was not running previously
    sh setup_worker.sh "$WALLET" "$PASS" 2>&1 | tee -a "$LOG_FILE"
else
    echo "fact-worker already exists. Checking application.yml..." | tee -a "$LOG_FILE"

    # Read the current username and password from the application.yml on the host system
    if [[ -f "$APP_YML" ]]; then
        CURRENT_USERNAME=$(grep -oP '^username: "\K[^"]+' "$APP_YML")
        CURRENT_PASSWORD=$(grep -oP '^password: "\K[^"]+' "$APP_YML")

        echo "Current username: $CURRENT_USERNAME" | tee -a "$LOG_FILE"
        echo "Current password: $CURRENT_PASSWORD" | tee -a "$LOG_FILE"

        # Flag to determine if application.yml needs updating
        NEEDS_UPDATE=false

        # Compare username
        if [[ "$CURRENT_USERNAME" != "$WALLET" ]]; then
            echo "Updating username in application.yml..." | tee -a "$LOG_FILE"
            sed -i "s/^username: \".*\"/username: \"$WALLET\"/" "$APP_YML"
            NEEDS_UPDATE=true
        fi

        # Compare password
        if [[ "$CURRENT_PASSWORD" != "$PASS" ]]; then
            echo "Updating password in application.yml..." | tee -a "$LOG_FILE"
            sed -i "s/^password: \".*\"/password: \"$PASS\"/" "$APP_YML"
            NEEDS_UPDATE=true
        fi

        # If updates were made, rebuild the worker
        if [[ "$NEEDS_UPDATE" == true ]]; then
            echo "Changes detected. Running rebuild_worker.sh..." | tee -a "$LOG_FILE"
            sh rebuild_worker.sh 2>&1 | tee -a "$LOG_FILE"
        else
            echo "No changes needed for application.yml." | tee -a "$LOG_FILE"
        fi
    else
        echo "application.yml not found on the host system. Exiting..." | tee -a "$LOG_FILE"
        exit 1
    fi
fi

# Start the Docker container
sudo docker start fact-worker 2>&1 | tee -a "$LOG_FILE"

# Keep the script running to prevent Hive OS from marking it as stopped
echo "Monitoring Docker logs..."
sudo docker logs -f fact-worker 2>&1 | tee -a "$LOG_FILE"
