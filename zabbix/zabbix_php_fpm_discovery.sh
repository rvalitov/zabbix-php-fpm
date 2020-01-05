#!/bin/bash
#Ramil Valitov ramilvalitov@gmail.com
#https://github.com/rvalitov/zabbix-php-fpm
#This script scans local machine for active PHP-FPM pools and returns them as a list in JSON format

S_PS=`type -P ps`
S_GREP=`type -P grep`
S_AWK=`type -P awk`
S_SORT=`type -P sort`
S_HEAD=`type -P head`
S_LSOF=`type -P lsof`
S_JQ=`type -P jq`
S_DIRNAME=`type -P dirname`
S_CAT=`type -P cat`
S_BASH=`type -P bash`

if [[ ! -f $S_PS ]]; then
	echo "Utility 'ps' not found. Please, install it first."
	exit 1
fi
if [[ ! -f $S_GREP ]]; then
	echo "Utility 'grep' not found. Please, install it first."
	exit 1
fi
if [[ ! -f $S_AWK ]]; then
	echo "Utility 'awk' not found. Please, install it first."
	exit 1
fi
if [[ ! -f $S_SORT ]]; then
	echo "Utility 'sort' not found. Please, install it first."
	exit 1
fi
if [[ ! -f $S_HEAD ]]; then
	echo "Utility 'head' not found. Please, install it first."
	exit 1
fi
if [[ ! -f $S_LSOF ]]; then
	echo "Utility 'lsof' not found. Please, install it first."
	exit 1
fi
if [[ ! -f $S_JQ ]]; then
	echo "Utility 'jq' not found. Please, install it first."
	exit 1
fi
if [[ ! -f ${S_DIRNAME} ]]; then
	echo "Utility 'dirname' not found. Please, install it first."
	exit 1
fi
if [[ ! -f ${S_CAT} ]]; then
	echo "Utility 'cat' not found. Please, install it first."
	exit 1
fi
if [[ ! -f ${S_BASH} ]]; then
	echo "Utility 'bash' not found. Please, install it first."
	exit 1
fi

STATUS_PATH="/php-fpm-status"
DEBUG_MODE=""

# Prints a string on screen. Works only if debug mode is enabled.
function PrintDebug(){
	if [[ ! -z $DEBUG_MODE ]] && [[ ! -z $1 ]]; then
	    echo $1
	fi
}

# Encodes input data to JSON and saves it to result string
# Input arguments:
# - pool name
# - pool socket
# Function returns 1 if all OK, and 0 otherwise.
function EncodeToJson(){
    POOL_NAME=$1
    POOL_SOCKET=$2
    if [[ -z ${POOL_NAME} ]] || [[ -z ${POOL_SOCKET} ]]; then
        return 0
    fi

    JSON_POOL=`echo -n "$POOL_NAME" | ${S_JQ} -aR .`
    JSON_SOCKET=`echo -n "$POOL_SOCKET" | ${S_JQ} -aR .`
    if [[ ${POOL_FIRST} == 1 ]]; then
        RESULT_DATA="$RESULT_DATA,"
    fi
    RESULT_DATA="$RESULT_DATA{\"{#POOLNAME}\":$JSON_POOL,\"{#POOLSOCKET}\":$JSON_SOCKET}"
    POOL_FIRST=1
    return 1
}

# Checks if selected pool is in cache.
# Input arguments:
# - pool name
# - pool socket
# Function returns 1 if the pool is in cache, and 0 otherwise.
function IsInCache(){
    SEARCH_NAME=$1
    SEARCH_SOCKET=$2
    if [[ -z ${SEARCH_NAME} ]] || [[ -z ${SEARCH_SOCKET} ]]; then
        return 0
    fi
    for CACHE_ITEM in "${NEW_CACHE[@]}"
    do
        ITEM_NAME=`echo "$CACHE_ITEM" | ${S_AWK} '{print $1}'`
        ITEM_SOCKET=`echo "$CACHE_ITEM" | ${S_AWK} '{print $2}'`
        if [[ ${ITEM_NAME} == ${SEARCH_NAME} ]] && [[ ${ITEM_SOCKET} == ${SEARCH_SOCKET} ]]; then
            return 1
        fi
    done
    return 0
}

# Validates the specified pool by getting its status and working with cache.
# Pass two arguments: pool name and pool socket
# Function returns:
# 0 if the pool is invalid
# 1 if the pool is OK and is ondemand and is not in cache
# 2 if the pool is OK and is ondemand and is in cache
# 3 if the pool is OK and is not ondemand and is not in cache
function ProcessPool(){
    POOL_NAME=$1
    POOL_SOCKET=$2
    if [[ -z ${POOL_NAME} ]] || [[ -z ${POOL_SOCKET} ]]; then
        return 0
    fi

    IsInCache ${POOL_NAME} ${POOL_SOCKET}
    FOUND=$?
    if [[ ${FOUND} == 1 ]]; then
        return 2
    fi

    STATUS_JSON=`${S_BASH} ${STATUS_SCRIPT} ${POOL_SOCKET} ${STATUS_PATH}`
    EXIT_CODE=$?
    if [[ ${EXIT_CODE} == 0 ]]; then
        # The exit code is OK, let's check the JSON data
        # JSON data example:
        # {"pool":"www2","process manager":"ondemand","start time":1578181845,"start since":117,"accepted conn":3,"listen queue":0,"max listen queue":0,"listen queue len":0,"idle processes":0,"active processes":1,"total processes":1,"max active processes":1,"max children reached":0,"slow requests":0}
        # We use basic regular expression here, i.e. we need to use \+ and not escape { and }
        if [[ ! -z `echo ${STATUS_JSON} | ${S_GREP} -G '^{.*\"pool\":\".\+\".*,\"process manager\":\".\+\".*}$'` ]]; then
            PrintDebug "Status data for pool $POOL_NAME, socket $POOL_SOCKET, status path $STATUS_PATH is valid"
            # Checking if we have ondemand pool
            if [[ ! -z `echo ${STATUS_JSON} | ${S_GREP} -F '"process manager":"ondemand"'` ]]; then
                PrintDebug "Detected pool's process manager is ondemand, it needs to be cached"
                NEW_CACHE+=("$POOL_NAME $POOL_SOCKET")
                return 1
            fi
            PrintDebug "Detected pool's process manager is NOT ondemand, it will not be cached"
            return 3
        fi

        PrintDebug "Failed to validate status data for pool $POOL_NAME, socket $POOL_SOCKET, status path $STATUS_PATH"
        if [[ ! -z ${STATUS_JSON} ]]; then
            PrintDebug "Status script returned: $STATUS_JSON"
        fi
        return 0
    fi
    PrintDebug "Failed to get status for pool $POOL_NAME, socket $POOL_SOCKET, status path $STATUS_PATH"
    if [[ ! -z ${STATUS_JSON} ]]; then
        PrintDebug "Status script returned: $STATUS_JSON"
    fi
    return 0
}

for ARG in "$@"; do
    if [[ ${ARG} == "debug" ]]; then
        DEBUG_MODE="1"
        echo "Debug mode enabled"
    elif [[ ${ARG} == /* ]]; then
        STATUS_PATH=${ARG}
        PrintDebug "Argument $ARG is interpreted as status path"
    else
        PrintDebug "Argument $ARG is unknown and skipped"
    fi
done
PrintDebug "Status path to be used: $STATUS_PATH"

LOCAL_DIR=`${S_DIRNAME} $0`
CACHE_FILE="$LOCAL_DIR/php_fpm.cache"
STATUS_SCRIPT="$LOCAL_DIR/zabbix_php_fpm_status.sh"
PrintDebug "Local directory is $LOCAL_DIR"
if [[ ! -f ${STATUS_SCRIPT} ]]; then
    echo "Helper script $STATUS_SCRIPT not found"
    exit 1
fi
if [[ ! -r ${STATUS_SCRIPT} ]]; then
    echo "Helper script $STATUS_SCRIPT is not readable"
    exit 1
fi
PrintDebug "Helper script $STATUS_SCRIPT is reachable"

# Loading cached data for ondemand pools.
# The cache file consists of lines, each line contains pool name, then space, then socket (or TCP info)
CACHE=()
NEW_CACHE=()
if [[ -r ${CACHE_FILE} ]]; then
    PrintDebug "Reading cache file $CACHE_FILE..."
    mapfile -t CACHE < <( ${S_CAT} ${CACHE_FILE} )
else
    PrintDebug "Cache file $CACHE_FILE not found, skipping..."
fi

mapfile -t PS_LIST < <( $S_PS ax | $S_GREP -F "php-fpm: pool " | $S_GREP -F -v "grep" )
POOL_LIST=`printf '%s\n' "${PS_LIST[@]}" | $S_AWK '{print $NF}' | $S_SORT -u`
POOL_FIRST=0
#We store the resulting JSON data for Zabbix in the following var:
RESULT_DATA="{\"data\":["
while IFS= read -r line
do
    POOL_PID=`printf '%s\n' "${PS_LIST[@]}" | $S_GREP -F -w "php-fpm: pool $line" | $S_HEAD -1 | $S_AWK '{print $1}'`
    if [[ ! -z $POOL_PID ]]; then
        #We search for socket or IP address and port
        #Socket example:
        #php-fpm7. 25897 root 9u unix 0x000000006509e31f 0t0 58381847 /run/php/php7.3-fpm.sock type=STREAM
        #IP example:
        #php-fpm7. 1110 default 0u IPv4 15760 0t0 TCP localhost:8002 (LISTEN)

        #Check all matching processes, because we may face a redirect (or a symlink?), examples:
        #php-fpm7. 1203 www-data 5u unix 0x000000006509e31f 0t0 15068771 type=STREAM
        #php-fpm7. 6086 www-data 11u IPv6 21771 0t0 TCP *:9000 (LISTEN)
        #php-fpm7. 1203 www-data 8u IPv4 15070917 0t0 TCP localhost.localdomain:23054->localhost.localdomain:postgresql (ESTABLISHED)
        #More info at https://github.com/rvalitov/zabbix-php-fpm/issues/12

        PrintDebug "Started analysis of pool $line, PID $POOL_PID"
        #Extract only important information:
        POOL_PARAMS_LIST=`$S_LSOF -p $POOL_PID 2>/dev/null | $S_GREP -w -e "unix" -e "TCP"`
        FOUND_POOL=""
        while IFS= read -r pool
        do
            if [[ ! -z $pool ]]; then
                if [[ -z $FOUND_POOL ]]; then
                    PrintDebug "Checking process: $pool"
                    POOL_TYPE=`echo "${pool}" | $S_AWK '{print $5}'`
                    POOL_SOCKET=`echo "${pool}" | $S_AWK '{print $9}'`
                    if [[ ! -z $POOL_TYPE ]] && [[ ! -z $POOL_SOCKET ]]; then
                        if [[ $POOL_TYPE == "unix" ]]; then
                            #We have a socket here, test if it's actually a socket:
                            if [[ -S $POOL_SOCKET ]]; then
                                PrintDebug "Found socket $POOL_SOCKET"
                                ProcessPool ${line} ${POOL_SOCKET}
                                POOL_STATUS=$?
                                if [[ ${POOL_STATUS} > 0 ]]; then
                                    FOUND_POOL="1"
                                    PrintDebug "Success: socket $POOL_SOCKET returned valid status data"
                                else
                                    PrintDebug "Error: socket $POOL_SOCKET didn't return valid data"
                                fi
                            else
                                PrintDebug "Error: specified socket $POOL_SOCKET is not valid"
                            fi
                        elif [[ $POOL_TYPE == "IPv4" ]] || [[ $POOL_TYPE == "IPv6" ]]; then
                            #We have a TCP connection here, check it:
                            CONNECTION_TYPE=`echo "${pool}" | $S_AWK '{print $8}'`
                            if [[ $CONNECTION_TYPE == "TCP" ]]; then
                                #The connection must have state LISTEN:
                                LISTEN=`echo ${pool} | $S_GREP -F -w "(LISTEN)"`
                                if [[ ! -z $LISTEN ]]; then
                                    #Check and replace * to localhost if it's found. Asterisk means that the PHP listens on
                                    #all interfaces.
                                    POOL_SOCKET=`echo -n ${POOL_SOCKET/*:/localhost:}`
                                    PrintDebug "Found TCP connection $POOL_SOCKET"
                                    ProcessPool ${line} ${POOL_SOCKET}
                                    POOL_STATUS=$?
                                    if [[ ${POOL_STATUS} > 0 ]]; then
                                        FOUND_POOL="1"
                                        PrintDebug "Success: TCP connection $POOL_SOCKET returned valid status data"
                                    else
                                        PrintDebug "Error: TCP connection $POOL_SOCKET didn't return valid data"
                                    fi
                                else
                                    PrintDebug "Warning: expected connection state must be LISTEN, but it was not detected"
                                fi
                            else
                                PrintDebug "Warning: expected connection type is TCP, but found $CONNECTION_TYPE"
                            fi
                        else
                            PrintDebug "Unsupported type $POOL_TYPE, skipping"
                        fi
                    else
                        PrintDebug "Warning: pool type or socket is empty"
                    fi
                else
                    PrintDebug "Pool already found, skipping process: $pool"
                fi
            else
                PrintDebug "Error: failed to get process information. Probably insufficient privileges. Use sudo or run this script under root."
            fi
        done <<< "$POOL_PARAMS_LIST"

        if [[ ! -z ${FOUND_POOL} ]]; then
            EncodeToJson ${line} ${POOL_SOCKET}
        else
            PrintDebug "Error: failed to discover information for pool $line"
        fi
    else
        PrintDebug "Error: failed to find PID for pool $line"
    fi
done <<< "$POOL_LIST"

PrintDebug "Processing pools from old cache..."
for CACHE_ITEM in "${CACHE[@]}"
do
    ITEM_NAME=`echo "$CACHE_ITEM" | ${S_AWK} '{print $1}'`
    ITEM_SOCKET=`echo "$CACHE_ITEM" | ${S_AWK} '{print $2}'`
    ProcessPool ${ITEM_NAME} ${ITEM_SOCKET}
    POOL_STATUS=$?
    if [[ ${POOL_STATUS} == "1" ]]; then
        # This is a new pool and we must add it
        EncodeToJson ${ITEM_NAME} ${ITEM_SOCKET}
    fi
done

PrintDebug "Saving new cache file $CACHE_FILE..."
printf "%s\n" "${NEW_CACHE[@]}" > ${CACHE_FILE}

RESULT_DATA="$RESULT_DATA]}"
PrintDebug "Resulting JSON data for Zabbix:"
echo -n $RESULT_DATA
