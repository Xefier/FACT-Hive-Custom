#!/bin/bash

yml_file="application.yml"

cat > "$yml_file" <<EOL
username: "$1"
password: "$2"
EOL

echo "done"

rm install_docker_slave*
wget https://github.com/filthz/fact-worker-public/releases/download/base_files/install_docker_slave.sh
/bin/bash install_docker_slave.sh

rm fact_worker*
wget https://github.com/filthz/fact-worker-public/releases/download/1.9/fact_worker_1.9.tar.gz
tar -xvf fact_worker_1.9.tar.gz

cp /etc/machine-id fact_dist/machine_id.cnf

sudo docker build --network=host -t fact-worker -f Dockerfile .

/bin/bash start_worker.sh