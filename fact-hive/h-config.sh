#!/usr/bin/env bash

# Initialize configuration
conf=""

# Add CUSTOM_TEMPLATE if available
if [[ ! -z $CUSTOM_TEMPLATE ]]; then
    conf+="USERNAME="
    conf+=$CUSTOM_TEMPLATE
    conf+="\n"
fi

# Add CUSTOM_PASS if available
if [[ ! -z $CUSTOM_PASS ]]; then
    conf+="PASSWORD="
    conf+=$CUSTOM_PASS
    conf+="\n"
fi

# Output configuration to the expected config file
echo -e "$conf" > $CUSTOM_CONFIG_FILENAME
