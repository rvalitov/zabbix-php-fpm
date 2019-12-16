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

DEBUG_MODE=""
if [[ ! -z $1 ]] && [[ $1 == "debug" ]]; then
    DEBUG_MODE="1"
    echo "Debug mode enabled"
fi

# Prints a string on screen. Works only if debug mode is enabled.
function PrintDebug(){
	if [[ ! -z $DEBUG_MODE ]] && [[ ! -z $1 ]]; then
	    echo $1
	fi
}

mapfile -t PS_LIST < <( $S_PS ax | $S_GREP "php-fpm: pool " | $S_GREP -v grep )
POOL_LIST=`printf '%s\n' "${PS_LIST[@]}" | $S_AWK '{print $NF}' | $S_SORT -u`
POOL_FIRST=0
#We store the resulting JSON data for Zabbix in the following var:
RESULT_DATA="{\"data\":["
while IFS= read -r line
do
    POOL_PID=`printf '%s\n' "${PS_LIST[@]}" | $S_GREP "php-fpm: pool $line$" | $S_HEAD -1 | $S_AWK '{print $1}'`
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
        POOL_PARAMS_LIST=`$S_LSOF -p $POOL_PID 2>/dev/null | $S_GREP -e unix -e TCP`
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
                                FOUND_POOL="1"
                                PrintDebug "Success: found socket $POOL_SOCKET"
                            else
                                PrintDebug "Error: specified socket $POOL_SOCKET is not valid"
                            fi
                        elif [[ $POOL_TYPE == "IPv4" ]] || [[ $POOL_TYPE == "IPv6" ]]; then
                            #We have a TCP connection here, check it:
                            CONNECTION_TYPE=`echo "${pool}" | $S_AWK '{print $8}'`
                            if [[ $CONNECTION_TYPE == "TCP" ]]; then
                                #The connection must have state LISTEN:
                                LISTEN=`echo ${pool} | $S_GREP -e (LISTEN)`
                                if [[ ! -z $LISTEN ]]; then
                                    #Check and replace * to localhost if it's found. Asterisk means that the PHP listens on
                                    #all interfaces.
                                    POOL_SOCKET=`echo -n ${POOL_SOCKET/*:/localhost:}`
                                    FOUND_POOL="1"
                                    PrintDebug "Success: found TCP connection $POOL_SOCKET"
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

        if [[ ! -z $FOUND_POOL ]]; then
            JSON_POOL=`echo -n "$line" | $S_JQ -aR .`
            JSON_SOCKET=`echo -n "$POOL_SOCKET" | $S_JQ -aR .`
            if [[ $POOL_FIRST == 1 ]]; then
                RESULT_DATA="$RESULT_DATA,"
            fi
            RESULT_DATA="$RESULT_DATA{\"{#POOLNAME}\":$JSON_POOL,\"{#POOLSOCKET}\":$JSON_SOCKET}"
            POOL_FIRST=1
        else
            PrintDebug "Error: failed to discover information for pool $line"
        fi
    else
        PrintDebug "Error: failed to find PID for pool $line"
    fi
done <<< "$POOL_LIST"
RESULT_DATA="$RESULT_DATA]}"
PrintDebug "Resulting JSON data for Zabbix:"
echo -n $RESULT_DATA
