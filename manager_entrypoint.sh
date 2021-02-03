#!/bin/bash
APIKEY=$(cat /configs/apikey)
USER=$(cat /configs/user)
PASSWORD=$(cat /configs/password)
TASKS_DOMAIN="tasks.$(echo $(echo $SERVICE_NAME | awk -F_ '{$NF="";print $0}') | tr -d ' ')_app."
mkdir -p /configs/devices

# $1 = HTTP Request Type
# $2 = API Key
# $3 = Host Address
# $4 = API Path
# $5+ = (optional) Payload Data
api() {
    case $1 in
        GET)
            curl -sk -X GET -H "X-API-Key: $2" https://$3:8384/rest/$4
        ;;
        *)
            if [ -f $5 ]; then
                echo $1"ing $4 with $5 on $3" 1>&2
                curl -sk -X $1 -H 'Content-Type: application/json' -H "X-API-Key: $2" --data-binary @$5 https://$3:8384/rest/$4
            else
                payload=$(format_json ${@:5})
                echo $1"ing $4 $payload on $3" 1>&2
                curl -sk -X $1 -H 'Content-Type: application/json' -H "X-API-Key: $2" --data $payload https://$3:8384/rest/$4
            fi
        ;;
    esac
}
syncthing() {
    api $1 $APIKEY ${@:2}
    UPDATES_APPLIED=1
}
format_json() {
    if [[ $1 =~ ^\[.* ]] || [[ $1 =~ ^\{.* ]]; then
        echo "$@"
    else
        if  [[ $2 =~ ^\[.* ]] || [[ $2 =~ ^\{.* ]] || [[ $2 == true ]] || [[ $2 == false ]] || [[ $2 == 0 ]] || [[ $2 -lt 0 ]] || [[ $2 -gt 0 ]]; then 
            echo "{\"$1\":${@:2}}"
        else 
            echo "{\"$1\":\"${@:2}\"}"
        fi
    fi
}
# $1 = Path of config file to compare
# $2 = Host Address
# $3 = API Path
# $4 = Key to Patch
# $5 = Value to Use
syncthing_patch() {
    TIMEOUT=3
    TRIES=0
    ENDPOINT=$(echo $3 | awk -F/ '{$1="";print $0}' | tr ' ' '.')
    if [[ $(jq -r "$ENDPOINT.$4" $1) != $5 ]]; then
        syncthing PATCH $2 $3 $4 $5
        while [[ $(jq -r "$ENDPOINT.$4" $1) != $5 ]] || [[ $TRIES == $TIMEOUT ]]; do sleep 1; syncthing GET $2 config > $1; TRIES=$(($TRIES + 1)); done
        if [[ $TRIES == $TIMEOUT ]]; then syncthing_patch $@; fi
    fi
}
while true; do
    UPDATES_APPLIED=0
    DEVICES_JSON=""
    FOLDER_JSON=""
    NODE_IPS=($(dig $TASKS_DOMAIN +short))
    
    # Get current config for each discovered device
    if [ ! -z "$NODE_IPS" ]; then 
        for NODE_IP in ${NODE_IPS[@]}; do
            DATA=$(syncthing GET $NODE_IP config | jq -c '.')
            if [ ! -z "$(echo $DATA)" ]; then
                ID=$(syncthing GET $NODE_IP system/status | jq -r '.myID')
                NAME=$(echo $DATA | jq -r ".devices[] | select(.deviceID==\"$ID\") | .name")
                DEVICES_JSON+="{\"deviceID\":\"$ID\",\"name\":\"$NAME\",\"autoAcceptFolders\":true},"
                FOLDER_JSON+="{\"deviceID\":\"$ID\"},"
                echo $DATA > /configs/devices/$NODE_IP
            fi
        done
        DEVICES_JSON="[${DEVICES_JSON::-1}]"
        FOLDER_JSON="{\"devices\":[${FOLDER_JSON::-1}]}"
        
        # Propogate Configurations
        for CONFIG in /configs/devices/*; do
            NODE_IP=$(basename $CONFIG)
            ID=$(syncthing GET $NODE_IP system/status | jq -r '.myID')
            NAME=$(jq -r '.devices[0].name' $CONFIG)
            NETWORK=$(echo $NODE_IP | awk -F. '{print $1"."$2"."$3".0/24"}')

            # Enable TLS
            syncthing_patch $CONFIG $NODE_IP config/gui useTLS true
            # Set Credentials 
            syncthing_patch $CONFIG $NODE_IP config/gui user $USER
            if [ -z "$(jq -r '.gui.password' $CONFIG)" ]; then
                syncthing PUT $NODE_IP config/gui $(jq -c --arg password $PASSWORD '.gui.password=$password | .gui' $CONFIG)
                while [[ -z $(jq -r '.gui.password' $CONFIG) ]]; do sleep 1; syncthing GET $NODE_IP config > $CONFIG; done
            fi
            # Disable Usage Reporting
            syncthing_patch $CONFIG $NODE_IP config/options urAccepted -1
            syncthing_patch $CONFIG $NODE_IP config/options urSeen 3
            # Devices
            DEVICES=($(echo $DEVICES_JSON | jq -r '.[].deviceID'))
            for DEVICE_ID in ${DEVICES[@]}; do
                if [ "$DEVICE_ID" != "$ID" ]; then
                    if [ -z "$(jq -r '.devices[].deviceID' $CONFIG | grep $DEVICE_ID)" ]; then
                        syncthing PUT $NODE_IP config/devices/$DEVICE_ID $(echo $DEVICES_JSON | jq -c ".[] | select(.deviceID==\"$DEVICE_ID\")")
                    fi
                    if [ -z "$(jq -r '.folders[] | select(.id=="default") | .devices[].deviceID' $CONFIG | grep $DEVICE_ID)" ]; then
                        syncthing PATCH $NODE_IP config/folders/default $FOLDER_JSON
                    fi
                fi
            done

            # Restart if necessary
            if [[ $(syncthing GET $NODE_IP system/config/insync | jq -r '.configInSync') != "true" ]]; then
                syncthing POST $NODE_IP system/restart
            fi
        done
        if [[ $UPDATES_APPLIED == 0 ]]; then sleep 55; fi
    fi
    sleep 5
done