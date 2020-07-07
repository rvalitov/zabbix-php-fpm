#!/bin/bash
#Ramil Valitov ramilvalitov@gmail.com
#https://github.com/rvalitov/zabbix-php-fpm
#This script scans local machine for active PHP-FPM pools and returns them as a list in JSON format

# This parameter is used to limit the execution time of this script.
# Zabbix allows us to use a script that runs no more than 3 seconds by default. This option can be adjusted in settings:
# see Timeout option https://www.zabbix.com/forum/zabbix-help/1284-server-agentd-timeout-parameter-in-config
# So, we need to stop and save our state in case we need more time to run.
# This parameter sets the maximum number of seconds that the script is allowed to run.
# After this duration is reached, the script will stop running and save its state.
# So, the actual execution time will be slightly more than this parameter.
# We put value equivalent to 2 seconds here.
MAX_EXECUTION_TIME="2"

#Status path used in calls to PHP-FPM
STATUS_PATH="/php-fpm-status"

#Debug mode is disabled by default
DEBUG_MODE=""

#Use sleep for testing timeouts, disabled by default. Can be used for testing & debugging
USE_SLEEP_TIMEOUT=""

#Sleep timeout in seconds
SLEEP_TIMEOUT="0.5"

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
S_PRINTF=$(type -P printf)
S_WHOAMI=$(type -P whoami)
S_DATE=$(type -P date)
S_BC=$(type -P bc)
S_SLEEP=$(type -P sleep)
S_FCGI=$(type -P cgi-fcgi)

if [[ ! -x $S_PS ]]; then
  echo "Utility 'ps' not found. Please, install it first."
  exit 1
fi
if [[ ! -x $S_GREP ]]; then
  echo "Utility 'grep' not found. Please, install it first."
  exit 1
fi
if [[ ! -x $S_AWK ]]; then
  echo "Utility 'awk' not found. Please, install it first."
  exit 1
fi
if [[ ! -x $S_SORT ]]; then
  echo "Utility 'sort' not found. Please, install it first."
  exit 1
fi
if [[ ! -x $S_UNIQ ]]; then
  echo "Utility 'uniq' not found. Please, install it first."
  exit 1
fi
if [[ ! -x $S_HEAD ]]; then
  echo "Utility 'head' not found. Please, install it first."
  exit 1
fi
if [[ ! -x $S_LSOF ]]; then
  echo "Utility 'lsof' not found. Please, install it first."
  exit 1
fi
if [[ ! -x $S_JQ ]]; then
  echo "Utility 'jq' not found. Please, install it first."
  exit 1
fi
if [[ ! -x ${S_DIRNAME} ]]; then
  echo "Utility 'dirname' not found. Please, install it first."
  exit 1
fi
if [[ ! -x ${S_CAT} ]]; then
  echo "Utility 'cat' not found. Please, install it first."
  exit 1
fi
if [[ ! -x ${S_BASH} ]]; then
  echo "Utility 'bash' not found. Please, install it first."
  exit 1
fi
if [[ ! -x ${S_PRINTF} ]]; then
  echo "Utility 'printf' not found. Please, install it first."
  exit 1
fi
if [[ ! -x ${S_WHOAMI} ]]; then
  echo "Utility 'whoami' not found. Please, install it first."
  exit 1
fi
if [[ ! -x ${S_DATE} ]]; then
  echo "Utility 'date' not found. Please, install it first."
  exit 1
fi
if [[ ! -x $S_BC ]]; then
  echo "Utility 'bc' not found. Please, install it first."
  exit 1
fi
if [[ ! -x $S_SLEEP ]]; then
  echo "Utility 'sleep' not found. Please, install it first."
  exit 1
fi
if [[ ! -x $S_FCGI ]]; then
  echo "Utility 'cgi-fcgi' not found. Please, install it first."
  exit 1
fi

#Local directory
LOCAL_DIR=$(${S_DIRNAME} "$0")

#Cache file for pending pools, used to store execution state
#File format:
#<pool name> <socket or TCP>
PENDING_FILE="$LOCAL_DIR/php_fpm_pending.cache"

#Cache file with list of active pools, used to store execution state
#File format:
#<pool name> <socket or TCP> <pool manager type>
RESULTS_CACHE_FILE="$LOCAL_DIR/php_fpm_results.cache"

#Path to status script, another script of this bundle
STATUS_SCRIPT="$LOCAL_DIR/zabbix_php_fpm_status.sh"

#Start time of the script
START_TIME=$($S_DATE +%s)

ACTIVE_USER=$(${S_WHOAMI})

# Prints a string on screen. Works only if debug mode is enabled.
function PrintDebug() {
  if [[ -n $DEBUG_MODE ]] && [[ -n $1 ]]; then
    echo "$1"
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

  JSON_POOL=$(echo -n "$POOL_NAME" | ${S_JQ} -aR .)
  JSON_SOCKET=$(echo -n "$POOL_SOCKET" | ${S_JQ} -aR .)
  if [[ ${POOL_FIRST} == 1 ]]; then
    RESULT_DATA="$RESULT_DATA,"
  fi
  RESULT_DATA="$RESULT_DATA{\"{#POOLNAME}\":$JSON_POOL,\"{#POOLSOCKET}\":$JSON_SOCKET}"
  POOL_FIRST=1
  return 1
}

# Updates information about the pool in cache.
# Input arguments:
# - pool name
# - pool socket
# - pool type
function UpdatePoolInCache() {
  POOL_NAME=$1
  POOL_SOCKET=$2
  POOL_TYPE=$3

  if [[ -z $POOL_NAME ]] || [[ -z $POOL_SOCKET ]] || [[ -z $POOL_TYPE ]]; then
    PrintDebug "Error: Invalid arguments for UpdatePoolInCache"
    return 0
  fi

  for ITEM_INDEX in "${!CACHE[@]}"; do
    CACHE_ITEM="${CACHE[$ITEM_INDEX]}"
    # shellcheck disable=SC2016
    ITEM_NAME=$(echo "$CACHE_ITEM" | ${S_AWK} '{print $1}')
    # shellcheck disable=SC2016
    ITEM_SOCKET=$(echo "$CACHE_ITEM" | ${S_AWK} '{print $2}')
    # shellcheck disable=SC2016
    ITEM_POOL_TYPE=$(echo "$CACHE_ITEM" | ${S_AWK} '{print $3}')
    if [[ $ITEM_NAME == "$POOL_NAME" && $ITEM_SOCKET == "$POOL_SOCKET" ]] || [[ -z $ITEM_POOL_TYPE ]]; then
      PrintDebug "Pool $POOL_NAME $POOL_SOCKET is in cache, deleting..."
      #Deleting the pool first
      mapfile -d $'\0' -t CACHE < <($S_PRINTF '%s\0' "${CACHE[@]}" | $S_GREP -Fwzv "$ITEM_NAME $ITEM_SOCKET")
    fi
  done

  CACHE+=("$POOL_NAME $POOL_SOCKET $POOL_TYPE")
  PrintDebug "Added pool $POOL_NAME $POOL_SOCKET to cache list"
  return 0
}

# Removes pools from cache that are currently inactive and are missing in pending list
function UpdateCacheList() {
  for ITEM_INDEX in "${!CACHE[@]}"; do
    CACHE_ITEM="${CACHE[$ITEM_INDEX]}"
    # shellcheck disable=SC2016
    ITEM_NAME=$(echo "$CACHE_ITEM" | ${S_AWK} '{print $1}')
    # shellcheck disable=SC2016
    ITEM_SOCKET=$(echo "$CACHE_ITEM" | ${S_AWK} '{print $2}')
    # shellcheck disable=SC2016
    ITEM_POOL_TYPE=$(echo "$CACHE_ITEM" | ${S_AWK} '{print $3}')

    if [[ $ITEM_NAME == "$POOL_NAME" && $ITEM_SOCKET == "$POOL_SOCKET" ]] || [[ -z $ITEM_POOL_TYPE ]]; then
      PrintDebug "Pool $POOL_NAME $POOL_SOCKET is in cache, deleting..."
      #Deleting the pool first
      mapfile -d $'\0' -t CACHE < <($S_PRINTF '%s\0' "${CACHE[@]}" | $S_GREP -Fwzv "ITEM_NAME $ITEM_SOCKET")
    fi
  done
}

# Checks if selected pool is in pending list
# Function returns 1 if pool is in list, and 0 otherwise
function IsInPendingList() {
  POOL_NAME=$1
  POOL_SOCKET=$2

  if [[ -z $POOL_NAME ]] || [[ -z $POOL_SOCKET ]]; then
    PrintDebug "Error: Invalid arguments for IsInPendingList"
    return 0
  fi

  for ITEM in "${PENDING_LIST[@]}"; do
    if [[ "$ITEM" == "$POOL_NAME $POOL_SOCKET" ]]; then
      return 1
    fi
  done
  return 0
}

# Adds a pool to the pending list
# The pool is added only if it's not already in the list.
# A new pool is added to the end of the list.
# Function returns 1, if a pool was added, and 0 otherwise.
function AddPoolToPendingList() {
  POOL_NAME=$1
  POOL_SOCKET=$2

  if [[ -z $POOL_NAME ]] || [[ -z $POOL_SOCKET ]]; then
    PrintDebug "Error: Invalid arguments for AddPoolToPendingList"
    return 0
  fi

  IsInPendingList "$POOL_NAME" "$POOL_SOCKET"
  FOUND=$?

  if [[ ${FOUND} == 1 ]]; then
    #Already in list, quit
    PrintDebug "Pool $POOL_NAME $POOL_SOCKET is already in pending list"
    return 0
  fi

  #Otherwise add this pool to the end of the list
  PENDING_LIST+=("$POOL_NAME $POOL_SOCKET")
  PrintDebug "Added pool $POOL_NAME $POOL_SOCKET to pending list"
  return 1
}

# Removes a pool from pending list
# Returns 1 if success, 0 otherwise
function DeletePoolFromPendingList() {
  POOL_NAME=$1
  POOL_SOCKET=$2

  if [[ -z $POOL_NAME ]] || [[ -z $POOL_SOCKET ]]; then
    PrintDebug "Error: Invalid arguments for DeletePoolFromPendingList"
    return 0
  fi

  IsInPendingList "$POOL_NAME" "$POOL_SOCKET"
  FOUND=$?

  if [[ ${FOUND} == 0 ]]; then
    #Not in list, quit
    PrintDebug "Error: Pool $POOL_NAME $POOL_SOCKET is already missing in pending list"
    return 0
  fi

  #Otherwise we remove this pool from the list
  mapfile -d $'\0' -t PENDING_LIST < <($S_PRINTF '%s\0' "${PENDING_LIST[@]}" | $S_GREP -Fxzv "$POOL_NAME $POOL_SOCKET")
  PrintDebug "Removed pool $POOL_NAME $POOL_SOCKET from pending list"
  return 1
}

function SavePrintResults() {
  #Saving pending list:
  if [[ -f $PENDING_FILE ]] && [[ ! -w $PENDING_FILE ]]; then
    echo "Error: write permission is not granted to user $ACTIVE_USER for cache file $PENDING_FILE"
    exit 1
  fi

  PrintDebug "Saving pending pools list to file $PENDING_FILE..."
  ${S_PRINTF} "%s\n" "${PENDING_LIST[@]}" >"$PENDING_FILE"

  #We must sort the cache list
  readarray -t CACHE < <(for a in "${CACHE[@]}"; do echo "$a"; done | $S_SORT)

  if [[ -n $DEBUG_MODE ]]; then
    PrintDebug "List of pools to be saved to cache pools file:"
    PrintCacheList
  fi

  if [[ -f $RESULTS_CACHE_FILE ]] && [[ ! -w $RESULTS_CACHE_FILE ]]; then
    echo "Error: write permission is not granted to user $ACTIVE_USER for cache file $RESULTS_CACHE_FILE"
    exit 1
  fi

  PrintDebug "Saving cache file to file $RESULTS_CACHE_FILE..."
  ${S_PRINTF} "%s\n" "${CACHE[@]}" >"$RESULTS_CACHE_FILE"

  POOL_FIRST=0
  #We store the resulting JSON data for Zabbix in the following var:
  RESULT_DATA="{\"data\":["

  for CACHE_ITEM in "${CACHE[@]}"; do
    # shellcheck disable=SC2016
    ITEM_NAME=$(echo "$CACHE_ITEM" | ${S_AWK} '{print $1}')
    # shellcheck disable=SC2016
    ITEM_SOCKET=$(echo "$CACHE_ITEM" | ${S_AWK} '{print $2}')
    EncodeToJson "${ITEM_NAME}" "${ITEM_SOCKET}"
  done

  RESULT_DATA="$RESULT_DATA]}"
  PrintDebug "Resulting JSON data for Zabbix:"
  echo -n "$RESULT_DATA"
}

function CheckExecutionTime() {
  CURRENT_TIME=$($S_DATE +%s)
  ELAPSED_TIME=$(echo "$CURRENT_TIME - $START_TIME" | $S_BC)
  if [[ $ELAPSED_TIME -lt $MAX_EXECUTION_TIME ]]; then
    #All good, we can continue
    PrintDebug "Check execution time OK, elapsed $ELAPSED_TIME"
    return 1
  fi

  #We need to save our state and exit
  PrintDebug "Check execution time: stop required, elapsed $ELAPSED_TIME"

  SavePrintResults

  exit 0
}

# Validates the specified pool by getting its status and working with cache.
# Pass two arguments: pool name and pool socket
# Function returns:
# 0 if the pool is invalid
# 1 if the pool is OK
function CheckPool() {
  POOL_NAME=$1
  POOL_SOCKET=$2
  if [[ -z ${POOL_NAME} ]] || [[ -z ${POOL_SOCKET} ]]; then
    PrintDebug "Error: Invalid arguments for CheckPool"
    return 0
  fi

  STATUS_JSON=$(${S_BASH} "${STATUS_SCRIPT}" "${POOL_SOCKET}" ${STATUS_PATH})
  EXIT_CODE=$?
  if [[ ${EXIT_CODE} == 0 ]]; then
    # The exit code is OK, let's check the JSON data
    # JSON data example:
    # {"pool":"www2","process manager":"ondemand","start time":1578181845,"start since":117,"accepted conn":3,"listen queue":0,"max listen queue":0,"listen queue len":0,"idle processes":0,"active processes":1,"total processes":1,"max active processes":1,"max children reached":0,"slow requests":0}
    # We use basic regular expression here, i.e. we need to use \+ and not escape { and }
    if [[ -n $(echo "${STATUS_JSON}" | ${S_GREP} -G '^{.*\"pool\":\".\+\".*,\"process manager\":\".\+\".*}$') ]]; then
      PrintDebug "Status data for pool $POOL_NAME, socket $POOL_SOCKET, status path $STATUS_PATH is valid"

      PROCESS_MANAGER=$(echo "$STATUS_JSON" | $S_GREP -oP '"process manager":"\K([a-z]+)')
      if [[ -n $PROCESS_MANAGER ]]; then
        PrintDebug "Detected pool's process manager is $PROCESS_MANAGER"
        UpdatePoolInCache "$POOL_NAME" "$POOL_SOCKET" "$PROCESS_MANAGER"
        return 1
      else
        PrintDebug "Error: Failed to detect process manager of the pool"
      fi
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

#Sleeps for a specified predefined amount of time. Works only if "sleep mode" is enabled.
function sleepNow() {
  if [[ -n $USE_SLEEP_TIMEOUT ]]; then
    PrintDebug "Debug: Sleep for $SLEEP_TIMEOUT sec"
    $S_SLEEP "$SLEEP_TIMEOUT"
  fi
}

# Analysis of pool by name, scans the processes, and adds them to pending list for further checks
function AnalyzePool() {
  POOL_NAME=$1
  if [[ -z ${POOL_NAME} ]]; then
    PrintDebug "Invalid arguments for AnalyzePool"
    return 0
  fi

  # shellcheck disable=SC2016
  POOL_PID_LIST=$(${S_PRINTF} '%s\n' "${PS_LIST[@]}" | $S_GREP -F -w "php-fpm: pool $POOL_NAME" | $S_AWK '{print $1}')
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

    PrintDebug "Started analysis of pool $POOL_NAME, PID(s): $POOL_PID_ARGS"
    #Extract only important information:
    #Use -P to show port number instead of port name, see https://github.com/rvalitov/zabbix-php-fpm/issues/24
    #Use -n flag to show IP address and not convert it to domain name (like localhost)
    #Sometimes different PHP-FPM versions may have the same names of pools, so we need to consider that.
    # It's considered that a pair of pool name and socket must be unique.
    #Sorting is required, because uniq needs it
    # shellcheck disable=SC2086
    POOL_PARAMS_LIST=$($S_LSOF -n -P $POOL_PID_ARGS 2>/dev/null | $S_GREP -w -e "unix" -e "TCP" | $S_SORT -u | $S_UNIQ -f8)
    FOUND_POOL=""
    while IFS= read -r pool; do
      if [[ -n $pool ]]; then
        PrintDebug "Checking process: $pool"
        # shellcheck disable=SC2016
        POOL_TYPE=$(echo "${pool}" | $S_AWK '{print $5}')
        # shellcheck disable=SC2016
        POOL_SOCKET=$(echo "${pool}" | $S_AWK '{print $9}')
        if [[ -n $POOL_TYPE ]] && [[ -n $POOL_SOCKET ]]; then
          if [[ $POOL_TYPE == "unix" ]]; then
            #We have a socket here, test if it's actually a socket:
            if [[ -S $POOL_SOCKET ]]; then
              FOUND_POOL="1"
              PrintDebug "Found socket $POOL_SOCKET"
              AddPoolToPendingList "$POOL_NAME" "$POOL_SOCKET"
            else
              PrintDebug "Error: specified socket $POOL_SOCKET is not valid"
            fi
          elif [[ $POOL_TYPE == "IPv4" ]] || [[ $POOL_TYPE == "IPv6" ]]; then
            #We have a TCP connection here, check it:
            # shellcheck disable=SC2016
            CONNECTION_TYPE=$(echo "${pool}" | $S_AWK '{print $8}')
            if [[ $CONNECTION_TYPE == "TCP" ]]; then
              #The connection must have state LISTEN:
              LISTEN=$(echo "${pool}" | $S_GREP -F -w "(LISTEN)")
              if [[ -n $LISTEN ]]; then
                #Check and replace * to localhost if it's found. Asterisk means that the PHP listens on
                #all interfaces.
                FOUND_POOL="1"
                PrintDebug "Found TCP connection $POOL_SOCKET"
                POOL_SOCKET=${POOL_SOCKET/\*:/localhost:}
                AddPoolToPendingList "$POOL_NAME" "$POOL_SOCKET"
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
      PrintDebug "Error: failed to discover information for pool $POOL_NAME"
    fi
  else
    PrintDebug "Error: failed to find PID for pool $POOL_NAME"
  fi

  return 1
}

# Prints list of pools in pending list
function PrintPendingList() {
  COUNTER=1
  for POOL_ITEM in "${PENDING_LIST[@]}"; do
    # shellcheck disable=SC2016
    POOL_NAME=$(echo "$POOL_ITEM" | $S_AWK '{print $1}')
    # shellcheck disable=SC2016
    POOL_SOCKET=$(echo "$POOL_ITEM" | $S_AWK '{print $2}')
    if [[ -n "$POOL_NAME" ]] && [[ -n "$POOL_SOCKET" ]]; then
      PrintDebug "#$COUNTER $POOL_NAME $POOL_SOCKET"
      COUNTER=$(echo "$COUNTER + 1" | $S_BC)
    fi
  done
}

# Prints list of pools in cache
function PrintCacheList() {
  COUNTER=1
  for POOL_ITEM in "${CACHE[@]}"; do
    # shellcheck disable=SC2016
    POOL_NAME=$(echo "$POOL_ITEM" | $S_AWK '{print $1}')
    # shellcheck disable=SC2016
    POOL_SOCKET=$(echo "$POOL_ITEM" | $S_AWK '{print $2}')
    # shellcheck disable=SC2016
    PROCESS_MANAGER=$(echo "$POOL_ITEM" | $S_AWK '{print $3}')
    if [[ -n "$POOL_NAME" ]] && [[ -n "$POOL_SOCKET" ]] && [[ -n "$PROCESS_MANAGER" ]]; then
      PrintDebug "#$COUNTER $POOL_NAME $POOL_SOCKET $PROCESS_MANAGER"
      COUNTER=$(echo "$COUNTER + 1" | $S_BC)
    fi
  done
}

# Functions processes a pool by name: makes all required checks and adds it to cache, etc.
function ProcessPool() {
  POOL_NAME=$1
  POOL_SOCKET=$2
  if [[ -z $POOL_NAME ]] || [[ -z $POOL_SOCKET ]]; then
    PrintDebug "Invalid arguments for ProcessPool"
    return 0
  fi

  PrintDebug "Processing pool $POOL_NAME $POOL_SOCKET"
  CheckPool "$POOL_NAME" "${POOL_SOCKET}"
  POOL_STATUS=$?
  if [[ ${POOL_STATUS} -gt 0 ]]; then
    FOUND_POOL="1"
    PrintDebug "Success: socket $POOL_SOCKET returned valid status data"
  else
    PrintDebug "Error: socket $POOL_SOCKET didn't return valid data"
  fi

  DeletePoolFromPendingList "$POOL_NAME" "$POOL_SOCKET"
  return 1
}

for ARG in "$@"; do
  if [[ ${ARG} == "debug" ]]; then
    DEBUG_MODE="1"
    echo "Debug mode enabled"
  elif [[ ${ARG} == "sleep" ]]; then
    USE_SLEEP_TIMEOUT="1"
    echo "Debug: Sleep timeout enabled"
  elif [[ ${ARG} == "nosleep" ]]; then
    MAX_EXECUTION_TIME="10000000"
    echo "Debug: Timeout checks disabled"
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
  echo "Helper script $STATUS_SCRIPT not found"
  exit 1
fi
if [[ ! -r ${STATUS_SCRIPT} ]]; then
  echo "Helper script $STATUS_SCRIPT is not readable"
  exit 1
fi
PrintDebug "Helper script $STATUS_SCRIPT is reachable"

# Loading cached data for pools.
CACHE=()
if [[ -r $RESULTS_CACHE_FILE ]]; then
  PrintDebug "Reading cache file of pools $RESULTS_CACHE_FILE..."
  mapfile -t CACHE < <(${S_CAT} "$RESULTS_CACHE_FILE")
else
  PrintDebug "Cache file of pools $RESULTS_CACHE_FILE not found, skipping..."
fi

if [[ -n $DEBUG_MODE ]]; then
  PrintDebug "List of pools loaded from cache pools file:"
  PrintCacheList
fi

#Loading pending tasks
PENDING_LIST=()
if [[ -r $PENDING_FILE ]]; then
  PrintDebug "Reading file of pending pools $PENDING_FILE..."
  mapfile -t PENDING_LIST < <($S_CAT "$PENDING_FILE")
else
  PrintDebug "List of pending pools $PENDING_FILE not found, skipping..."
fi

if [[ -n $DEBUG_MODE ]]; then
  PrintDebug "List of pools loaded from pending pools file:"
  PrintPendingList
fi

mapfile -t PS_LIST < <($S_PS ax | $S_GREP -F "php-fpm: pool " | $S_GREP -F -v "grep")
# shellcheck disable=SC2016
POOL_NAMES_LIST=$(${S_PRINTF} '%s\n' "${PS_LIST[@]}" | $S_AWK '{print $NF}' | $S_SORT -u)

#Update pending list with pools that are active and running
while IFS= read -r POOL_NAME; do
  AnalyzePool "$POOL_NAME"
done <<<"$POOL_NAMES_LIST"

if [[ -n $DEBUG_MODE ]]; then
  PrintDebug "Pending list generated:"
  PrintPendingList
fi

#Process pending list
PrintDebug "Processing pools"

for POOL_ITEM in "${PENDING_LIST[@]}"; do
  # shellcheck disable=SC2016
  POOL_NAME=$(echo "$POOL_ITEM" | $S_AWK '{print $1}')
  # shellcheck disable=SC2016
  POOL_SOCKET=$(echo "$POOL_ITEM" | $S_AWK '{print $2}')
  if [[ -n "$POOL_NAME" ]] && [[ -n "$POOL_SOCKET" ]]; then
    ProcessPool "$POOL_NAME" "$POOL_SOCKET"

    #Confirm that we run not too much time
    CheckExecutionTime

    #Used for debugging:
    sleepNow
  fi
done

SavePrintResults
