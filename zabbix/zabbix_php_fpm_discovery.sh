#!/bin/bash
#Ramil Valitov ramilvalitov@gmail.com
#https://github.com/rvalitov/zabbix-php-fpm
#This script scans local machine for active PHP-FPM pools and returns them as a list in JSON format

#This parameter is used to limit the execution time of this script. Zabbix allows us to run maximum of 3 seconds, so
#we need to stop and save our state in case we need more time to run. This parameter sets the maximum number of
#seconds that the script is allowed to run. After this duration is reached, the script will stop running and save its
#state. So, the actual execution time will be slightly more than this parameter.
#We put value 2 here, because we can use only integers.
MAX_EXECUTION_TIME=2

#Reset the seconds variable
SECONDS=0

#Status path used in calls to PHP-FPM
STATUS_PATH="/php-fpm-status"

#Debug mode is disabled by default
DEBUG_MODE=""

#Local directory
LOCAL_DIR=$(${S_DIRNAME} "$0")

#Cache file for ondemand pools
#File format:
#<pool name> <socket or TCP>
ONDEMAND_CACHE_FILE="$LOCAL_DIR/php_fpm_ondemand.cache"

#Cache file for pending pools, used to store execution state
#File format:
#<pool name>
PENDING_FILE="$LOCAL_DIR/php_fpm_pending.cache"

#Cache file with list of active pools, used to store execution state
#File format:
#<pool name> <socket or TCP>
RESULTS_CACHE_FILE="$LOCAL_DIR/php_fpm_results.cache"

#Path to status script, another script of this bundle
STATUS_SCRIPT="$LOCAL_DIR/zabbix_php_fpm_status.sh"

#Checking all the required executables
S_PS=$(type -P ps)
S_GREP=$(type -P grep)
S_AWK=$(type -P awk)
S_SORT=$(type -P sort)
S_UNIQ=$(type -P uniq)
S_HEAD=$(type -P head)
S_LSOF=$(type -P lsof)
S_JQ=$(type -P jq)
S_DIRNAME=$(type -P dirname)
S_CAT=$(type -P cat)
S_BASH=$(type -P bash)
S_ECHO=$(type -P echo)
S_PRINTF=$(type -P printf)
S_WHOAMI=$(type -P whoami)

if [[ ! -f $S_PS ]]; then
  ${S_ECHO} "Utility 'ps' not found. Please, install it first."
  exit 1
fi
if [[ ! -f $S_GREP ]]; then
  ${S_ECHO} "Utility 'grep' not found. Please, install it first."
  exit 1
fi
if [[ ! -f $S_AWK ]]; then
  ${S_ECHO} "Utility 'awk' not found. Please, install it first."
  exit 1
fi
if [[ ! -f $S_SORT ]]; then
  ${S_ECHO} "Utility 'sort' not found. Please, install it first."
  exit 1
fi
if [[ ! -f $S_UNIQ ]]; then
  ${S_ECHO} "Utility 'uniq' not found. Please, install it first."
  exit 1
fi
if [[ ! -f $S_HEAD ]]; then
  ${S_ECHO} "Utility 'head' not found. Please, install it first."
  exit 1
fi
if [[ ! -f $S_LSOF ]]; then
  ${S_ECHO} "Utility 'lsof' not found. Please, install it first."
  exit 1
fi
if [[ ! -f $S_JQ ]]; then
  ${S_ECHO} "Utility 'jq' not found. Please, install it first."
  exit 1
fi
if [[ ! -f ${S_DIRNAME} ]]; then
  ${S_ECHO} "Utility 'dirname' not found. Please, install it first."
  exit 1
fi
if [[ ! -f ${S_CAT} ]]; then
  ${S_ECHO} "Utility 'cat' not found. Please, install it first."
  exit 1
fi
if [[ ! -f ${S_BASH} ]]; then
  ${S_ECHO} "Utility 'bash' not found. Please, install it first."
  exit 1
fi
if [[ ! -f ${S_PRINTF} ]]; then
  ${S_ECHO} "Utility 'printf' not found. Please, install it first."
  exit 1
fi
if [[ ! -f ${S_WHOAMI} ]]; then
  ${S_ECHO} "Utility 'whoami' not found. Please, install it first."
  exit 1
fi

ACTIVE_USER=$(${S_WHOAMI})

# Prints a string on screen. Works only if debug mode is enabled.
function PrintDebug() {
  if [[ -n $DEBUG_MODE ]] && [[ -n $1 ]]; then
    ${S_ECHO} "$1"
  fi
}

# Encodes input data to JSON and saves it to result string
# Input arguments:
# - pool name
# - pool socket
# Function returns 1 if all OK, and 0 otherwise.
function EncodeToJson() {
  POOL_NAME=$1
  POOL_SOCKET=$2
  if [[ -z ${POOL_NAME} ]] || [[ -z ${POOL_SOCKET} ]]; then
    return 0
  fi

  JSON_POOL=$(${S_ECHO} -n "$POOL_NAME" | ${S_JQ} -aR .)
  JSON_SOCKET=$(${S_ECHO} -n "$POOL_SOCKET" | ${S_JQ} -aR .)
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
function IsInCache() {
  SEARCH_NAME=$1
  SEARCH_SOCKET=$2
  if [[ -z ${SEARCH_NAME} ]] || [[ -z ${SEARCH_SOCKET} ]]; then
    return 0
  fi
  for CACHE_ITEM in "${NEW_CACHE[@]}"; do
    # shellcheck disable=SC2016
    ITEM_NAME=$(${S_ECHO} "$CACHE_ITEM" | ${S_AWK} '{print $1}')
    # shellcheck disable=SC2016
    ITEM_SOCKET=$(${S_ECHO} "$CACHE_ITEM" | ${S_AWK} '{print $2}')
    if [[ ${ITEM_NAME} == "${SEARCH_NAME}" ]] && [[ ${ITEM_SOCKET} == "${SEARCH_SOCKET}" ]]; then
      return 1
    fi
  done
  return 0
}

function CheckExecutionTime() {
  if [[ $SECONDS -lt $MAX_EXECUTION_TIME ]]; then
    #All good, we can continue
    return 1;
  fi

  #We need to save our state and exit
}

# Validates the specified pool by getting its status and working with cache.
# Pass two arguments: pool name and pool socket
# Function returns:
# 0 if the pool is invalid
# 1 if the pool is OK and is ondemand and is not in cache
# 2 if the pool is OK and is ondemand and is in cache
# 3 if the pool is OK and is not ondemand and is not in cache
function ProcessPool() {
  POOL_NAME=$1
  POOL_SOCKET=$2
  if [[ -z ${POOL_NAME} ]] || [[ -z ${POOL_SOCKET} ]]; then
    PrintDebug "Invalid arguments for ProcessPool"
    return 0
  fi

  IsInCache "${POOL_NAME}" "${POOL_SOCKET}"
  FOUND=$?
  if [[ ${FOUND} == 1 ]]; then
    return 2
  fi

  STATUS_JSON=$(${S_BASH} "${STATUS_SCRIPT}" "${POOL_SOCKET}" ${STATUS_PATH})
  EXIT_CODE=$?
  if [[ ${EXIT_CODE} == 0 ]]; then
    # The exit code is OK, let's check the JSON data
    # JSON data example:
    # {"pool":"www2","process manager":"ondemand","start time":1578181845,"start since":117,"accepted conn":3,"listen queue":0,"max listen queue":0,"listen queue len":0,"idle processes":0,"active processes":1,"total processes":1,"max active processes":1,"max children reached":0,"slow requests":0}
    # We use basic regular expression here, i.e. we need to use \+ and not escape { and }
    if [[ -n $(${S_ECHO} "${STATUS_JSON}" | ${S_GREP} -G '^{.*\"pool\":\".\+\".*,\"process manager\":\".\+\".*}$') ]]; then
      PrintDebug "Status data for pool $POOL_NAME, socket $POOL_SOCKET, status path $STATUS_PATH is valid"
      # Checking if we have ondemand pool
      if [[ -n $(${S_ECHO} "${STATUS_JSON}" | ${S_GREP} -F '"process manager":"ondemand"') ]]; then
        PrintDebug "Detected pool's process manager is ondemand, it needs to be cached"
        NEW_CACHE+=("$POOL_NAME $POOL_SOCKET")
        return 1
      fi
      PrintDebug "Detected pool's process manager is NOT ondemand, it will not be cached"
      return 3
    fi

    PrintDebug "Failed to validate status data for pool $POOL_NAME, socket $POOL_SOCKET, status path $STATUS_PATH"
    if [[ -n ${STATUS_JSON} ]]; then
      PrintDebug "Status script returned: $STATUS_JSON"
    fi
    return 0
  fi
  PrintDebug "Failed to get status for pool $POOL_NAME, socket $POOL_SOCKET, status path $STATUS_PATH"
  if [[ -n ${STATUS_JSON} ]]; then
    PrintDebug "Status script returned: $STATUS_JSON"
  fi
  return 0
}

for ARG in "$@"; do
  if [[ ${ARG} == "debug" ]]; then
    DEBUG_MODE="1"
    ${S_ECHO} "Debug mode enabled"
  elif [[ ${ARG} == /* ]]; then
    STATUS_PATH=${ARG}
    PrintDebug "Argument $ARG is interpreted as status path"
  else
    PrintDebug "Argument $ARG is unknown and skipped"
  fi
done
PrintDebug "Current user is $ACTIVE_USER"
PrintDebug "Status path to be used: $STATUS_PATH"

PrintDebug "Local directory is $LOCAL_DIR"
if [[ ! -f ${STATUS_SCRIPT} ]]; then
  ${S_ECHO} "Helper script $STATUS_SCRIPT not found"
  exit 1
fi
if [[ ! -r ${STATUS_SCRIPT} ]]; then
  ${S_ECHO} "Helper script $STATUS_SCRIPT is not readable"
  exit 1
fi
PrintDebug "Helper script $STATUS_SCRIPT is reachable"

# Loading cached data for ondemand pools.
# The cache file consists of lines, each line contains pool name, then space, then socket (or TCP info)
CACHE=()
NEW_CACHE=()
if [[ -r ${ONDEMAND_CACHE_FILE} ]]; then
  PrintDebug "Reading cache file of ondemand pools $ONDEMAND_CACHE_FILE..."
  mapfile -t CACHE < <(${S_CAT} "${ONDEMAND_CACHE_FILE}")
else
  PrintDebug "Cache file of ondemand pools $ONDEMAND_CACHE_FILE not found, skipping..."
fi

#Loading pending tasks
PENDING_LIST=()
if [[ -r $PENDING_FILE ]]; then
  PrintDebug "Reading file of pending pools ${PENDING_FILE}..."
  mapfile -t PENDING_LIST < <(${S_CAT} "${PENDING_FILE}")
else
  PrintDebug "List of pending pools ${PENDING_FILE} not found, skipping..."
fi

mapfile -t PS_LIST < <($S_PS ax | $S_GREP -F "php-fpm: pool " | $S_GREP -F -v "grep")
# shellcheck disable=SC2016
POOL_NAMES_LIST=$(${S_PRINTF} '%s\n' "${PS_LIST[@]}" | $S_AWK '{print $NF}' | $S_SORT -u)
POOL_FIRST=0
#We store the resulting JSON data for Zabbix in the following var:
RESULT_DATA="{\"data\":["
while IFS= read -r line; do
  # shellcheck disable=SC2016
  POOL_PID_LIST=$(${S_PRINTF} '%s\n' "${PS_LIST[@]}" | $S_GREP -F -w "php-fpm: pool $line" | $S_AWK '{print $1}')
  POOL_PID_ARGS=""
  while IFS= read -r POOL_PID; do
    if [[ -n $POOL_PID ]]; then
      POOL_PID_ARGS="$POOL_PID_ARGS -p $POOL_PID"
    fi
  done <<<"$POOL_PID_LIST"

  if [[ -n $POOL_PID_ARGS ]]; then
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

    PrintDebug "Started analysis of pool $line, PID(s): $POOL_PID_ARGS"
    #Extract only important information:
    #Use -P to show port number instead of port name, see https://github.com/rvalitov/zabbix-php-fpm/issues/24
    #Use -n flag to show IP address and not convert it to domain name (like localhost)
    #Sometimes different PHP-FPM versions may have the same names of pools, so we need to consider that.
    # It's considered that a pair of pool name and socket must be unique.
    #Sorting is required, because uniq needs it
    POOL_PARAMS_LIST=$($S_LSOF -n -P $POOL_PID_ARGS 2>/dev/null | $S_GREP -w -e "unix" -e "TCP" | $S_SORT -u | $S_UNIQ -f8)
    FOUND_POOL=""
    while IFS= read -r pool; do
      if [[ -n $pool ]]; then
        PrintDebug "Checking process: $pool"
        # shellcheck disable=SC2016
        POOL_TYPE=$(${S_ECHO} "${pool}" | $S_AWK '{print $5}')
        # shellcheck disable=SC2016
        POOL_SOCKET=$(${S_ECHO} "${pool}" | $S_AWK '{print $9}')
        if [[ -n $POOL_TYPE ]] && [[ -n $POOL_SOCKET ]]; then
          if [[ $POOL_TYPE == "unix" ]]; then
            #We have a socket here, test if it's actually a socket:
            if [[ -S $POOL_SOCKET ]]; then
              PrintDebug "Found socket $POOL_SOCKET"
              ProcessPool "${line}" "${POOL_SOCKET}"
              POOL_STATUS=$?
              if [[ ${POOL_STATUS} -gt 0 ]]; then
                FOUND_POOL="1"
                PrintDebug "Success: socket $POOL_SOCKET returned valid status data"
                EncodeToJson "${line}" "${POOL_SOCKET}"
              else
                PrintDebug "Error: socket $POOL_SOCKET didn't return valid data"
              fi
            else
              PrintDebug "Error: specified socket $POOL_SOCKET is not valid"
            fi
          elif [[ $POOL_TYPE == "IPv4" ]] || [[ $POOL_TYPE == "IPv6" ]]; then
            #We have a TCP connection here, check it:
            # shellcheck disable=SC2016
            CONNECTION_TYPE=$(${S_ECHO} "${pool}" | $S_AWK '{print $8}')
            if [[ $CONNECTION_TYPE == "TCP" ]]; then
              #The connection must have state LISTEN:
              LISTEN=$(${S_ECHO} "${pool}" | $S_GREP -F -w "(LISTEN)")
              if [[ -n $LISTEN ]]; then
                #Check and replace * to localhost if it's found. Asterisk means that the PHP listens on
                #all interfaces.
                PrintDebug "Found TCP connection $POOL_SOCKET"
                POOL_SOCKET=${POOL_SOCKET/\*:/localhost:}
                PrintDebug "Processed TCP connection $POOL_SOCKET"
                ProcessPool "${line}" "${POOL_SOCKET}"
                POOL_STATUS=$?
                if [[ ${POOL_STATUS} -gt 0 ]]; then
                  FOUND_POOL="1"
                  PrintDebug "Success: TCP connection $POOL_SOCKET returned valid status data"
                  EncodeToJson "${line}" "${POOL_SOCKET}"
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
        PrintDebug "Error: failed to get process information. Probably insufficient privileges. Use sudo or run this script under root."
      fi
    done <<<"$POOL_PARAMS_LIST"

    if [[ -z ${FOUND_POOL} ]]; then
      PrintDebug "Error: failed to discover information for pool $line"
    fi
  else
    PrintDebug "Error: failed to find PID for pool $line"
  fi
done <<<"$POOL_NAMES_LIST"

PrintDebug "Processing pools from old cache..."
for CACHE_ITEM in "${CACHE[@]}"; do
  # shellcheck disable=SC2016
  ITEM_NAME=$(${S_ECHO} "$CACHE_ITEM" | ${S_AWK} '{print $1}')
  # shellcheck disable=SC2016
  ITEM_SOCKET=$(${S_ECHO} "$CACHE_ITEM" | ${S_AWK} '{print $2}')
  ProcessPool "${ITEM_NAME}" "${ITEM_SOCKET}"
  POOL_STATUS=$?
  if [[ ${POOL_STATUS} == "1" ]]; then
    # This is a new pool and we must add it
    EncodeToJson "${ITEM_NAME}" "${ITEM_SOCKET}"
  fi
done

if [[ -f ${ONDEMAND_CACHE_FILE} ]] && [[ ! -w ${ONDEMAND_CACHE_FILE} ]]; then
  ${S_ECHO} "Error: write permission is not granted to user $ACTIVE_USER for cache file $ONDEMAND_CACHE_FILE"
  exit 1
fi

PrintDebug "Saving new cache file $ONDEMAND_CACHE_FILE..."
${S_PRINTF} "%s\n" "${NEW_CACHE[@]}" >"${ONDEMAND_CACHE_FILE}"

RESULT_DATA="$RESULT_DATA]}"
PrintDebug "Resulting JSON data for Zabbix:"
${S_ECHO} -n "$RESULT_DATA"
