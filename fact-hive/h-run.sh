#!/usr/bin/env bash

# Enable debug mode to print all commands
set -x

# Define log file
LOG_DIR="/var/log/miner/custom"
LOG_FILE="$LOG_DIR/miner.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

# Function to handle cleanup when Hive OS stops the miner
cleanup() {
    echo "Stopping fact-worker..." | tee -a "$LOG_FILE"
    sudo docker stop fact-worker 2>&1 | tee -a "$LOG_FILE"
    exit 0
}

# Trap SIGTERM and SIGINT (sent when Hive OS stops the miner)
trap cleanup SIGTERM SIGINT

# Clear previous logs
echo "Starting fact-worker..." | tee "$LOG_FILE"

WALLET="%WAL%"  # Hive OS will replace this with the configured wallet

# Check if fact-worker exists in Docker
if ! sudo docker ps -a --format "{{.Names}}" | grep -q "^fact-worker$"; then
    echo "fact-worker not found. Installing..." | tee -a "$LOG_FILE"
    
    wget -O setup_worker.sh https://github.com/filthz/fact-worker-public/releases/download/base_files/setup_worker.sh 2>&1 | tee -a "$LOG_FILE"
    chmod +x setup_worker.sh 2>&1 | tee -a "$LOG_FILE"
    sh setup_worker.sh "$WALLET" 2>&1 | tee -a "$LOG_FILE"

    # Install required dependencies
    sudo apt-get install -y iptables arptables ebtables 2>&1 | tee -a "$LOG_FILE"
    sudo update-alternatives --set iptables /usr/sbin/iptables-legacy 2>&1 | tee -a "$LOG_FILE"
    sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>&1 | tee -a "$LOG_FILE"

    # Ensure Docker is running
    sudo systemctl enable --now docker 2>&1 | tee -a "$LOG_FILE"
    sudo systemctl restart docker 2>&1 | tee -a "$LOG_FILE"

    # Re-run setup in case Docker was not running previously
    sh setup_worker.sh "$WALLET" 2>&1 | tee -a "$LOG_FILE"
else
    echo "fact-worker already exists. Starting..." | tee -a "$LOG_FILE"
fi

# Start the Docker container
sudo docker start fact-worker 2>&1 | tee -a "$LOG_FILE"

# Keep the script running to prevent Hive OS from marking it as stopped
echo "Monitoring Docker logs..."
sudo docker logs -f fact-worker 2>&1 | tee -a "$LOG_FILE" &

# Wait for the logging process to exit (so the script stays alive)
wait
