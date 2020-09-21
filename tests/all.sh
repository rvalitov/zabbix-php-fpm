#!/bin/bash
#Ramil Valitov ramilvalitov@gmail.com
#https://github.com/rvalitov/zabbix-php-fpm
#This script is used for testing

################################### START OF CONFIGURATION CONSTANTS

# Number of pools, created for each ondemand, static and dynamic sockets.
MAX_POOLS=3

# Number of port based pools created for each PHP version
MAX_PORTS=3

# Starting port number for port based PHP pools
MIN_PORT=49001

# Maximum number of ports per PHP version, this value is used to define the available port range.
MAX_PORTS_COUNT=100

# Timeout in seconds that we put in the option "pm.process_idle_timeout" of configuration of ondemand PHP pools.
ONDEMAND_TIMEOUT=60

# Timeout in seconds that we put in the configuration of Zabbix agent
ZABBIX_TIMEOUT=20

# Maximum iterations to perform during sequential scans of pools, when the operation is time-consuming and requires
# multiple calls to the discovery script.
# This value should be big enough to be able to get information about all pools in the system.
# It allows to exit from indefinite check loops.
MAX_CHECKS=150

################################### END OF CONFIGURATION CONSTANTS

# A random socket used for tests, this variable is defined when PHP pools are created
TEST_SOCKET=""

# The directory where the PHP socket files are located, for example, /var/run or /run.
# This variable is used as cache, because it may be impossible to detect it when we start and stop the PHP-FPM.
# Don't use this variable directly. Use function getRunPHPDirectory
PHP_SOCKET_DIR=""

# The directory where the PHP configuration files are located, for example, /etc/php or /etc/php5.
# This variable is used as cache. So, don't use this variable directly. Use function getEtcPHPDirectory
PHP_ETC_DIR=""

# List of all services in the system.
# This variable is used as cache. So, don't use this variable directly. Use function getPHPServiceName
LIST_OF_SERVICES=""

# Used for section folding in Travis CI
SECTION_UNIQUE_ID=""

#Parent directory where all cache files are located in the OS
CACHE_ROOT="/var/cache"

#Name of the private directory to store the cache files
CACHE_DIR_NAME="zabbix-php-fpm"

#Full path to directory to store cache files
CACHE_DIRECTORY="$CACHE_ROOT/$CACHE_DIR_NAME"

# ----------------------------------
# Colors
# ----------------------------------
NOCOLOR='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
LIGHTGRAY='\033[0;37m'
DARKGRAY='\033[1;30m'
LIGHTRED='\033[1;31m'
LIGHTGREEN='\033[1;32m'
YELLOW='\033[1;33m'
LIGHTBLUE='\033[1;34m'
LIGHTPURPLE='\033[1;35m'
LIGHTCYAN='\033[1;36m'
WHITE='\033[1;37m'

function printYellow() {
  local info=$1
  echo -e "${YELLOW}$info${NOCOLOR}"
}

function printRed() {
  local info=$1
  echo -e "${RED}$info${NOCOLOR}"
}

function printGreen() {
  local info=$1
  echo -e "${LIGHTGREEN}$info${NOCOLOR}"
}

function printSuccess() {
  local name=$1
  printGreen "✓ OK: test '$name' passed"
}

function printDebug() {
  local info=$1
  echo -e "${DARKGRAY}$info${NOCOLOR}"
}

function printAction() {
  local info=$1
  echo -e "${LIGHTBLUE}$info${NOCOLOR}"
}

function travis_fold_start() {
  local name=$1
  local info=$2
  local CURRENT_TIMING
  CURRENT_TIMING=$(date +%s%3N)
  SECTION_UNIQUE_ID="$name.$CURRENT_TIMING"
  echo -e "travis_fold:start:${SECTION_UNIQUE_ID}\033[33;1m${info}\033[0m"
}

function travis_fold_end() {
  echo -e "\ntravis_fold:end:${SECTION_UNIQUE_ID}\r"
}

function getUserParameters() {
  sudo find /etc/zabbix/ -name 'userparameter_php_fpm.conf' -type f 2>/dev/null | sort | head -n1
}

function restoreUserParameters() {
  PARAMS_FILE=$(getUserParameters)
  sudo rm -f "$PARAMS_FILE"
  sudo cp "$TRAVIS_BUILD_DIR/zabbix/userparameter_php_fpm.conf" "$(sudo find /etc/zabbix/ -name 'zabbix_agentd*.d' -type d 2>/dev/null | sort | head -n1)"
}

function AddSleepToConfig() {
  PARAMS_FILE=$(getUserParameters)
  sudo sed -i 's#.*zabbix_php_fpm_discovery.*#UserParameter=php-fpm.discover[*],sudo /etc/zabbix/zabbix_php_fpm_discovery.sh sleep $1#' "$PARAMS_FILE"
  travis_fold_start "AddSleepToConfig" "ⓘ New UserParameter file"
  sudo cat "$PARAMS_FILE"
  travis_fold_end
  restartService "zabbix-agent"
  sleep 2
}

function StartTimer() {
  START_TIME=$(date +%s%N)
}

function printElapsedTime() {
  local END_TIME

  END_TIME=$(date +%s%N)
  ELAPSED_TIME=$(echo "($END_TIME - $START_TIME)/1000000" | bc)
  printYellow "Elapsed time $ELAPSED_TIME ms"
}

function assertExecutionTime() {
  local MAX_TIME
  MAX_TIME=$(echo "$ZABBIX_TIMEOUT * 1000" | bc)
  assertTrue "The script worked for too long: $ELAPSED_TIME ms, allowed $MAX_TIME ms" "[ $ELAPSED_TIME -lt $MAX_TIME ]"
}

function getPHPVersion() {
  TEST_STRING=$1
  PHP_VERSION=$(echo "$TEST_STRING" | grep -oP "(\d\.\d)")
  if [[ -z "$PHP_VERSION" ]]; then
    PHP_VERSION=$(echo "$TEST_STRING" | grep -oP "php(\d)" | grep -oP "(\d)")
  fi
  echo "$PHP_VERSION"
  if [[ -z "$PHP_VERSION" ]]; then
    return 1
  fi
  return 0
}

function getEtcPHPDirectory() {
  if [[ -n "$PHP_ETC_DIR" ]]; then
    echo "$PHP_ETC_DIR"
    return 0
  fi

  LIST_OF_DIRS=(
    "/etc/php/"
    "/etc/php5/"
  )
  for PHP_TEST_DIR in "${LIST_OF_DIRS[@]}"; do
    if [[ -d "$PHP_TEST_DIR" ]]; then
      PHP_ETC_DIR=$PHP_TEST_DIR
      break
    fi
  done

  if [[ -n "$PHP_ETC_DIR" ]]; then
    echo "$PHP_ETC_DIR"
    return 0
  fi

  return 1
}

function getRunPHPDirectory() {
  if [[ -n "$PHP_SOCKET_DIR" ]]; then
    echo "$PHP_SOCKET_DIR"
    return 0
  fi

  LIST_OF_DIRS=(
    "/run/"
    "/var/run/"
  )
  for PHP_TEST_DIR in "${LIST_OF_DIRS[@]}"; do
    RESULT_DIR=$(sudo find "$PHP_TEST_DIR" -name 'php*-fpm.sock' -type s -exec dirname {} \; 2>/dev/null | sort | head -n1)
    if [[ -d "$RESULT_DIR" ]]; then
      PHP_SOCKET_DIR="$RESULT_DIR/"
      break
    fi
  done

  if [[ -z "$PHP_SOCKET_DIR" ]]; then
    #Try to parse the location from default config
    PHP_DIR=$(getEtcPHPDirectory)
    EXIT_CODE=$?
    assertEquals "Failed to find PHP configuration directory" "0" "$EXIT_CODE"
    assertTrue "PHP configuration directory '$PHP_DIR' is not a directory" "[ -d $PHP_DIR ]"

    DEFAULT_CONF=$(sudo find "$PHP_DIR" -name "www.conf" -type f | uniq | head -n1)
    assertTrue "Failed to find default www.conf file inside '$PHP_DIR'" "[ -n $DEFAULT_CONF ]"

    DEFAULT_SOCKET=$(sudo grep -Po 'listen = (.+)' "$DEFAULT_CONF" | cut -d '=' -f2 | sed -e 's/^[ \t]*//')
    assertTrue "Failed to extract socket information from '$DEFAULT_CONF'" "[ -n $DEFAULT_SOCKET ]"

    RESULT_DIR=$(dirname "$DEFAULT_SOCKET")
    assertTrue "Directory '$RESULT_DIR' does not exist" "[ -d $RESULT_DIR ]"
    if [[ -d "$RESULT_DIR" ]]; then
      PHP_SOCKET_DIR="$RESULT_DIR/"
    fi
  fi

  if [[ -n "$PHP_SOCKET_DIR" ]]; then
    echo "$PHP_SOCKET_DIR"
    return 0
  fi

  return 1
}

copyPool() {
  ORIGINAL_FILE=$1
  POOL_NAME=$2
  POOL_SOCKET=$3
  POOL_TYPE=$4
  POOL_DIR=$(dirname "${ORIGINAL_FILE}")
  PHP_VERSION=$(getPHPVersion "$POOL_DIR")
  assertNotNull "Failed to detect PHP version from string '$POOL_DIR'" "$PHP_VERSION"

  NEW_POOL_FILE="$POOL_DIR/${POOL_NAME}.conf"
  sudo cp "$ORIGINAL_FILE" "$NEW_POOL_FILE"

  #Add status path
  sudo sed -i 's#;pm.status_path.*#pm.status_path = /php-fpm-status#' "$NEW_POOL_FILE"
  #Set pool manager
  sudo sed -i "s#pm = dynamic#pm = $POOL_TYPE#" "$NEW_POOL_FILE"
  #Socket
  sudo sed -i "s#listen =.*#listen = $POOL_SOCKET#" "$NEW_POOL_FILE"
  #Pool name
  sudo sed -i "s#\[www\]#[$POOL_NAME]#" "$NEW_POOL_FILE"

  if [[ $POOL_TYPE == "ondemand" ]]; then
    sudo sed -i "s#;pm.process_idle_timeout.*#pm.process_idle_timeout = ${ONDEMAND_TIMEOUT}s#" "$NEW_POOL_FILE"
  fi
}

getPHPServiceName() {
  PHP_VERSION=$1
  if [[ -z "$LIST_OF_SERVICES" ]]; then
    LIST_OF_SERVICES=$(sudo service --status-all 2>/dev/null | sort)
  fi

  LIST_OF_NAMES=(
    "php${PHP_VERSION}-fpm"
    "php-fpm"
  )

  for SERVICE_NAME in "${LIST_OF_NAMES[@]}"; do
    RESULT=$(echo "$LIST_OF_SERVICES" | grep -F "$SERVICE_NAME")
    if [[ -n "$RESULT" ]]; then
      echo "$SERVICE_NAME"
      return 0
    fi
  done
  return 1
}

setupPool() {
  POOL_FILE=$1
  POOL_DIR=$(dirname "${POOL_FILE}")
  PHP_VERSION=$(getPHPVersion "$POOL_DIR")
  assertNotNull "Failed to detect PHP version from string '$POOL_DIR'" "$PHP_VERSION"

  PHP_RUN_DIR=$(getRunPHPDirectory)
  EXIT_CODE=$?
  assertEquals "Failed to find PHP run directory" "0" "$EXIT_CODE"
  assertTrue "PHP run directory '$PHP_RUN_DIR' is not a directory" "[ -d $PHP_RUN_DIR ]"

  PHP_DIR=$(getEtcPHPDirectory)
  EXIT_CODE=$?
  assertEquals "Failed to find PHP configuration directory" "0" "$EXIT_CODE"
  assertTrue "PHP configuration directory '$PHP_DIR' is not a directory" "[ -d $PHP_DIR ]"

  #Delete all active pools except www.conf:
  sudo find "$POOL_DIR" -name '*.conf' -type f -not -name 'www.conf' -exec rm -rf {} \;

  #Create new socket pools
  for ((c = 1; c <= MAX_POOLS; c++)); do
    POOL_NAME="socket$c"
    POOL_SOCKET="${PHP_RUN_DIR}php${PHP_VERSION}-fpm-${POOL_NAME}.sock"
    copyPool "$POOL_FILE" "$POOL_NAME" "$POOL_SOCKET" "static"
    if [[ -z $TEST_SOCKET ]]; then
      TEST_SOCKET="$POOL_SOCKET"
    fi
  done

  for ((c = 1; c <= MAX_POOLS; c++)); do
    POOL_NAME="dynamic$c"
    POOL_SOCKET="${PHP_RUN_DIR}php${PHP_VERSION}-fpm-${POOL_NAME}.sock"
    copyPool "$POOL_FILE" "$POOL_NAME" "$POOL_SOCKET" "dynamic"
  done

  for ((c = 1; c <= MAX_POOLS; c++)); do
    POOL_NAME="ondemand$c"
    POOL_SOCKET="${PHP_RUN_DIR}php${PHP_VERSION}-fpm-${POOL_NAME}.sock"
    copyPool "$POOL_FILE" "$POOL_NAME" "$POOL_SOCKET" "ondemand"
  done

  PHP_SERIAL_ID=$(sudo find "$PHP_DIR" -maxdepth 1 -mindepth 1 -type d | sort | grep -n -F "$PHP_VERSION" | head -n1 | cut -d : -f 1)
  #Create TCP port based pools
  #Division on 1 is required to convert from float to integer
  START_PORT=$(echo "($MIN_PORT + $PHP_SERIAL_ID * $MAX_PORTS_COUNT + 1)/1" | bc)
  for ((c = 1; c <= MAX_PORTS; c++)); do
    POOL_NAME="port$c"
    POOL_PORT=$(echo "($START_PORT + $c)/1" | bc)
    PORT_IS_BUSY=$(sudo lsof -i:"$POOL_PORT")
    assertNull "Port $POOL_PORT is busy" "$PORT_IS_BUSY"
    copyPool "$POOL_FILE" "$POOL_NAME" "$POOL_PORT" "static"
  done

  #Create TCP IPv4 localhost pool
  POOL_NAME="localhost"
  POOL_PORT=$(echo "($MIN_PORT + $PHP_SERIAL_ID * $MAX_PORTS_COUNT)/1" | bc)
  POOL_SOCKET="127.0.0.1:$POOL_PORT"
  PORT_IS_BUSY=$(sudo lsof -i:"$POOL_PORT")
  assertNull "Port $POOL_PORT is busy" "$PORT_IS_BUSY"
  copyPool "$POOL_FILE" "$POOL_NAME" "$POOL_SOCKET" "static"

  travis_fold_start "list_PHP$PHP_VERSION" "ⓘ List of configured PHP$PHP_VERSION pools"
  sudo ls -l "$POOL_DIR"
  travis_fold_end

  SERVICE_NAME=$(getPHPServiceName "$PHP_VERSION")
  assertNotNull "Failed to detect service name for PHP${PHP_VERSION}" "$SERVICE_NAME"
  printAction "Restarting service $SERVICE_NAME..."
  restartService "$SERVICE_NAME"
  sleep 3

  travis_fold_start "running_PHP$PHP_VERSION" "ⓘ List of running PHP$PHP_VERSION pools"
  E_SYSTEM_CONTROL=$(type -P systemctl)
  if [[ -x "$E_SYSTEM_CONTROL" ]]; then
    sudo systemctl -l status "$SERVICE_NAME.service"
  else
    sudo initctl list | grep -F "$SERVICE_NAME"
  fi
  travis_fold_end
  sleep 2
}

setupPools() {
  PHP_DIR=$(getEtcPHPDirectory)
  EXIT_CODE=$?
  assertEquals "Failed to find PHP configuration directory" "0" "$EXIT_CODE"
  assertTrue "PHP configuration directory '$PHP_DIR' is not a directory" "[ -d $PHP_DIR ]"

  PHP_LIST=$(sudo find "$PHP_DIR" -name 'www.conf' -type f)

  #Call to detect and cache PHP run directory, we need to call it before we stop all PHP-FPM
  PHP_RUN_DIR=$(getRunPHPDirectory)
  EXIT_CODE=$?
  assertEquals "Failed to find PHP run directory" "0" "$EXIT_CODE"
  assertTrue "PHP run directory '$PHP_RUN_DIR' is not a directory" "[ -d $PHP_RUN_DIR ]"

  #First we need to stop all PHP-FPM
  while IFS= read -r pool; do
    if [[ -n $pool ]]; then
      POOL_DIR=$(dirname "$pool")
      PHP_VERSION=$(getPHPVersion "$POOL_DIR")
      assertNotNull "Failed to detect PHP version from string '$POOL_DIR'" "$PHP_VERSION"
      SERVICE_NAME=$(getPHPServiceName "$PHP_VERSION")
      assertNotNull "Failed to detect service name for PHP${PHP_VERSION}" "$SERVICE_NAME"
      printAction "Stopping service $SERVICE_NAME..."
      stopService "$SERVICE_NAME"
    fi
  done <<<"$PHP_LIST"

  #Now we reconfigure them and restart
  while IFS= read -r pool; do
    if [[ -n $pool ]]; then
      setupPool "$pool"
    fi
  done <<<"$PHP_LIST"
}

getNumberOfPHPVersions() {
  PHP_DIR=$(getEtcPHPDirectory)
  EXIT_CODE=$?
  assertEquals "Failed to find PHP configuration directory" "0" "$EXIT_CODE"
  assertTrue "PHP configuration directory '$PHP_DIR' is not a directory" "[ -d $PHP_DIR ]"

  PHP_COUNT=$(sudo find "$PHP_DIR" -name 'www.conf' -type f | wc -l)
  echo "$PHP_COUNT"
}

function startOndemandPoolsCache() {
  PHP_DIR=$(getEtcPHPDirectory)
  EXIT_CODE=$?
  assertEquals "Failed to find PHP configuration directory" "0" "$EXIT_CODE"
  assertTrue "PHP configuration directory '$PHP_DIR' is not a directory" "[ -d $PHP_DIR ]"

  PHP_RUN_DIR=$(getRunPHPDirectory)
  EXIT_CODE=$?
  assertEquals "Failed to find PHP run directory" "0" "$EXIT_CODE"
  assertTrue "PHP run directory '$PHP_RUN_DIR' is not a directory" "[ -d $PHP_RUN_DIR ]"

  # We must start all the pools
  POOL_URL="/php-fpm-status"

  PHP_LIST=$(sudo find "$PHP_DIR" -name 'www.conf' -type f)
  while IFS= read -r pool; do
    if [[ -n $pool ]]; then
      POOL_DIR=$(dirname "$pool")
      PHP_VERSION=$(getPHPVersion "$POOL_DIR")
      assertNotNull "Failed to detect PHP version from string '$POOL_DIR'" "$PHP_VERSION"

      for ((c = 1; c <= MAX_POOLS; c++)); do
        POOL_NAME="ondemand$c"
        POOL_SOCKET="${PHP_RUN_DIR}php${PHP_VERSION}-fpm-${POOL_NAME}.sock"

        PHP_STATUS=$(
          SCRIPT_NAME=$POOL_URL \
            SCRIPT_FILENAME=$POOL_URL \
            QUERY_STRING=json \
            REQUEST_METHOD=GET \
            sudo cgi-fcgi -bind -connect "$POOL_SOCKET" 2>/dev/null
        )
        assertNotNull "Failed to connect to $POOL_SOCKET" "$PHP_STATUS"
      done
    fi
  done <<<"$PHP_LIST"
}

getAnySocket() {
  PHP_DIR=$(getEtcPHPDirectory)
  EXIT_CODE=$?
  assertEquals "Failed to find PHP configuration directory" "0" "$EXIT_CODE"
  assertTrue "PHP configuration directory '$PHP_DIR' is not a directory" "[ -d $PHP_DIR ]"

  PHP_RUN_DIR=$(getRunPHPDirectory)
  EXIT_CODE=$?
  assertEquals "Failed to find PHP run directory" "0" "$EXIT_CODE"
  assertTrue "PHP run directory '$PHP_RUN_DIR' is not a directory" "[ -d $PHP_RUN_DIR ]"

  #Get any socket of PHP-FPM:
  PHP_FIRST=$(sudo find "$PHP_DIR" -name 'www.conf' -type f | sort | head -n1)
  assertNotNull "Failed to get PHP conf" "$PHP_FIRST"
  PHP_VERSION=$(getPHPVersion "$PHP_FIRST")
  assertNotNull "Failed to detect PHP version from string '$PHP_FIRST'" "$PHP_VERSION"
  PHP_POOL=$(sudo find "$PHP_RUN_DIR" -name "php${PHP_VERSION}*.sock" -type s 2>/dev/null | sort | head -n1)
  assertNotNull "Failed to get PHP${PHP_VERSION} socket" "$PHP_POOL"
  echo "$PHP_POOL"
}

getAnyPort() {
  PHP_PORT=$(sudo netstat -tulpn | grep -F "LISTEN" | grep -F "php-fpm" | head -n1 | awk '{print $4}' | rev | cut -d: -f1 | rev)
  assertNotNull "Failed to get PHP port" "$PHP_PORT"
  echo "$PHP_PORT"
}

function actionService() {
  local SERVICE_NAME=$1
  local SERVICE_ACTION=$2
  local SERVICE_INFO
  sleep 3
  SERVICE_INFO=$(sudo service "$SERVICE_NAME" $SERVICE_ACTION)
  STATUS=$?
  if [[ "$STATUS" -ne 0 ]]; then
    printRed "Failed to $SERVICE_ACTION service '$SERVICE_NAME':"
    echo "$SERVICE_INFO"
  fi
  sleep 3
}

function restartService() {
  local SERVICE_NAME=$1
  actionService "$SERVICE_NAME" "restart"
}

function stopService() {
  local SERVICE_NAME=$1
  actionService "$SERVICE_NAME" "stop"
}

oneTimeSetUp() {
  printAction "Started job $TRAVIS_JOB_NAME"

  travis_fold_start "host_info" "ⓘ Host information"
  nslookup localhost
  sudo ifconfig
  sudo cat /etc/hosts
  travis_fold_end

  printAction "Copying Zabbix files..."
  #Install files:
  sudo cp "$TRAVIS_BUILD_DIR/zabbix/zabbix_php_fpm_discovery.sh" "/etc/zabbix"
  sudo cp "$TRAVIS_BUILD_DIR/zabbix/zabbix_php_fpm_status.sh" "/etc/zabbix"
  sudo cp "$TRAVIS_BUILD_DIR/zabbix/userparameter_php_fpm.conf" "$(sudo find /etc/zabbix/ -name 'zabbix_agentd*.d' -type d | sort | head -n1)"
  sudo chmod +x /etc/zabbix/zabbix_php_fpm_discovery.sh
  sudo chmod +x /etc/zabbix/zabbix_php_fpm_status.sh

  #Configure Zabbix:
  echo 'zabbix ALL=NOPASSWD: /etc/zabbix/zabbix_php_fpm_discovery.sh,/etc/zabbix/zabbix_php_fpm_status.sh' | sudo EDITOR='tee -a' visudo
  sudo sed -i "s#.* Timeout=.*#Timeout = $ZABBIX_TIMEOUT#" "/etc/zabbix/zabbix_agentd.conf"

  travis_fold_start "zabbix_agent" "ⓘ Zabbix agent configuration"
  sudo cat "/etc/zabbix/zabbix_agentd.conf"
  travis_fold_end

  restartService "zabbix-agent"

  printAction "Setup PHP-FPM..."

  #Setup PHP-FPM pools:
  setupPools

  printAction "All done, starting tests..."
}

#Called before every test
setUp() {
  #Delete all cache files
  if [[ -d "$CACHE_DIRECTORY" ]]; then
    sudo find "$CACHE_DIRECTORY" -type f -exec rm '{}' \;
  fi
  StartTimer
}

#Called after every test
tearDown() {
  restoreUserParameters
  sleep 2
  restartService "zabbix-agent"
  sleep 2
}

testZabbixGetInstalled() {
  ZABBIX_GET=$(type -P zabbix_get)
  assertNotNull "Utility zabbix-get not installed" "$ZABBIX_GET"
  printSuccess "${FUNCNAME[0]}"
}

testZabbixAgentVersion() {
  #Example: 4.4
  REQUESTED_VERSION=$(echo "$TRAVIS_JOB_NAME" | grep -i -F "zabbix" | head -n1 | cut -d "@" -f1 | cut -d " " -f2)
  INSTALLED_VERSION=$(zabbix_agentd -V | grep -F "zabbix" | head -n1 | rev | cut -d " " -f1 | rev | cut -d "." -f1,2)
  assertSame "Requested version $REQUESTED_VERSION and installed version $INSTALLED_VERSION of Zabbix agent do not match" "$REQUESTED_VERSION" "$INSTALLED_VERSION"
  printSuccess "${FUNCNAME[0]}"
}

testZabbixGetVersion() {
  #Example: 4.4
  REQUESTED_VERSION=$(echo "$TRAVIS_JOB_NAME" | grep -i -F "zabbix" | head -n1 | cut -d "@" -f1 | cut -d " " -f2)
  INSTALLED_VERSION=$(zabbix_get -V | grep -F "zabbix" | head -n1 | rev | cut -d " " -f1 | rev | cut -d "." -f1,2)
  assertSame "Requested version $REQUESTED_VERSION and installed version $INSTALLED_VERSION of zabbix_get do not match" "$REQUESTED_VERSION" "$INSTALLED_VERSION"
  printSuccess "${FUNCNAME[0]}"
}

testNonRootUserPrivilegesDiscovery() {
  #Run the script under non root user
  DATA=$(sudo -u zabbix "/etc/zabbix/zabbix_php_fpm_discovery.sh")
  IS_OK=$(echo "$DATA" | grep -F 'Insufficient privileges')
  printElapsedTime
  assertNotNull "The discovery script must not work for non root user" "$IS_OK"
  printSuccess "${FUNCNAME[0]}"
}

testNonRootUserPrivilegesStatus() {
  #Run the script under non root user
  assertNotNull "Test socket is not defined" "$TEST_SOCKET"
  DATA=$(sudo -u zabbix "/etc/zabbix/zabbix_php_fpm_status.sh" "$TEST_SOCKET" "/php-fpm-status")
  IS_OK=$(echo "$DATA" | grep -F 'Insufficient privileges')
  printElapsedTime
  assertNotNull "The status script must not work for non root user" "$IS_OK"
  printSuccess "${FUNCNAME[0]}"
}

testPHPIsRunning() {
  IS_OK=$(sudo ps ax | grep -F "php-fpm: pool " | grep -F -v "grep" | head -n1)
  assertNotNull "No running PHP-FPM instances found" "$IS_OK"
  printSuccess "${FUNCNAME[0]}"
}

testStatusScriptSocket() {
  assertNotNull "Test socket is not defined" "$TEST_SOCKET"
  DATA=$(sudo -u zabbix sudo "/etc/zabbix/zabbix_php_fpm_status.sh" "$TEST_SOCKET" "/php-fpm-status")
  IS_OK=$(echo "$DATA" | grep -F '{"pool":"')
  printElapsedTime
  assertNotNull "Failed to get status from pool $TEST_SOCKET: $DATA" "$IS_OK"
  assertExecutionTime
  printGreen "Success test of $TEST_SOCKET"
  printSuccess "${FUNCNAME[0]}"
}

testStatusScriptPort() {
  PHP_PORT=$(getAnyPort)
  PHP_POOL="127.0.0.1:$PHP_PORT"

  #Make the test:
  DATA=$(sudo -u zabbix sudo "/etc/zabbix/zabbix_php_fpm_status.sh" "$PHP_POOL" "/php-fpm-status")
  IS_OK=$(echo "$DATA" | grep -F '{"pool":"')
  printElapsedTime
  assertNotNull "Failed to get status from pool $PHP_POOL: $DATA" "$IS_OK"
  assertExecutionTime
  printGreen "Success test of $PHP_POOL"
  printSuccess "${FUNCNAME[0]}"
}

testZabbixStatusSocket() {
  DATA=$(zabbix_get -s 127.0.0.1 -p 10050 -k php-fpm.status["$TEST_SOCKET","/php-fpm-status"])
  IS_OK=$(echo "$DATA" | grep -F '{"pool":"')
  printElapsedTime
  assertNotNull "Failed to get status from pool $PHP_POOL: $DATA" "$IS_OK"
  assertExecutionTime
  printGreen "Success test of $PHP_POOL"
  printSuccess "${FUNCNAME[0]}"
}

testZabbixStatusPort() {
  PHP_PORT=$(getAnyPort)
  PHP_POOL="127.0.0.1:$PHP_PORT"

  DATA=$(zabbix_get -s 127.0.0.1 -p 10050 -k php-fpm.status["$PHP_POOL","/php-fpm-status"])
  IS_OK=$(echo "$DATA" | grep -F '{"pool":"')
  printElapsedTime
  assertNotNull "Failed to get status from pool $PHP_POOL: $DATA" "$IS_OK"
  assertExecutionTime
  printGreen "Success test of $PHP_POOL"
  printSuccess "${FUNCNAME[0]}"
}

testDiscoverScriptReturnsData() {
  DATA=$(sudo -u zabbix sudo "/etc/zabbix/zabbix_php_fpm_discovery.sh" "/php-fpm-status")
  IS_OK=$(echo "$DATA" | grep -F '{"data":[{"{#POOLNAME}"')
  printElapsedTime
  assertNotNull "Discover script failed: $DATA" "$IS_OK"
  assertExecutionTime
  printSuccess "${FUNCNAME[0]}"
}

testDiscoverScriptDebug() {
  local DATA
  local NUMBER_OF_ERRORS
  DATA=$(sudo -u zabbix sudo "/etc/zabbix/zabbix_php_fpm_discovery.sh" "debug" "nosleep" "/php-fpm-status")
  NUMBER_OF_ERRORS=$(echo "$DATA" | grep -o -F 'Error:' | wc -l)

  if [[ $NUMBER_OF_ERRORS -gt 0 ]]; then
    ERRORS_LIST=$(echo "$DATA" | grep -F 'Error:')
    printYellow "Errors list:"
    printYellow "$ERRORS_LIST"
    travis_fold_start "testDiscoverScriptDebug_full" "ⓘ Full output"
    echo "$DATA"
    travis_fold_end
  fi
  printElapsedTime
  assertEquals "Discover script errors mismatch" "0" "$NUMBER_OF_ERRORS"
  assertExecutionTime
  printSuccess "${FUNCNAME[0]}"
}

testDiscoverScriptTimeout() {
  DATA=$(sudo -u zabbix sudo "/etc/zabbix/zabbix_php_fpm_discovery.sh" "debug" "nosleep" "max_tasks" "1" "/php-fpm-status")
  NUMBER_OF_ERRORS=$(echo "$DATA" | grep -o -F 'Error:' | wc -l)
  PHP_COUNT=$(getNumberOfPHPVersions)
  if [[ $PHP_COUNT != "$NUMBER_OF_ERRORS" ]]; then
    ERRORS_LIST=$(echo "$DATA" | grep -F 'Error:')
    printYellow "Errors list:"
    printYellow "$ERRORS_LIST"
    travis_fold_start "testDiscoverScriptTimeout_full" "ⓘ Full output"
    echo "$DATA"
    travis_fold_end
  fi
  printElapsedTime
  assertEquals "Discover script errors mismatch" "$PHP_COUNT" "$NUMBER_OF_ERRORS"
  printSuccess "${FUNCNAME[0]}"
}

testZabbixDiscoverReturnsData() {
  DATA=$(zabbix_get -s 127.0.0.1 -p 10050 -k php-fpm.discover["/php-fpm-status"])
  IS_OK=$(echo "$DATA" | grep -F '{"data":[{"{#POOLNAME}"')
  printElapsedTime
  assertNotNull "Discover script failed: $DATA" "$IS_OK"
  assertExecutionTime
  printSuccess "${FUNCNAME[0]}"
}

testDiscoverScriptSleep() {
  DATA=$(sudo -u zabbix sudo "/etc/zabbix/zabbix_php_fpm_discovery.sh" "debug" "sleep" "/php-fpm-status")
  CHECK_OK_COUNT=$(echo "$DATA" | grep -o -F "execution time OK" | wc -l)
  STOP_OK_COUNT=$(echo "$DATA" | grep -o -F "stop required" | wc -l)

  printElapsedTime
  printYellow "Success time checks: $CHECK_OK_COUNT"
  printYellow "Stop time checks: $STOP_OK_COUNT"

  if [[ $CHECK_OK_COUNT -lt 1 ]] || [[ $STOP_OK_COUNT -lt 1 ]]; then
    travis_fold_start "ScriptSleep" "ⓘ Zabbix response"
    echo "$DATA"
    travis_fold_end
  fi
  assertTrue "No success time checks detected" "[ $CHECK_OK_COUNT -gt 0 ] || [ $STOP_OK_COUNT -eq 1 ]"
  assertTrue "No success stop checks detected" "[ $STOP_OK_COUNT -gt 0 ]"
  assertExecutionTime
  printSuccess "${FUNCNAME[0]}"
}

testZabbixDiscoverSleep() {
  #Add sleep
  AddSleepToConfig

  testZabbixDiscoverReturnsData
  printSuccess "${FUNCNAME[0]}"
}

testDiscoverScriptRunDuration() {
  DATA=$(sudo -u zabbix sudo "/etc/zabbix/zabbix_php_fpm_discovery.sh" "debug" "sleep" "/php-fpm-status")
  CHECK_OK_COUNT=$(echo "$DATA" | grep -o -F "execution time OK" | wc -l)
  STOP_OK_COUNT=$(echo "$DATA" | grep -o -F "stop required" | wc -l)

  printElapsedTime
  printYellow "Success time checks: $CHECK_OK_COUNT"
  printYellow "Stop time checks: $STOP_OK_COUNT"

  assertExecutionTime
  printSuccess "${FUNCNAME[0]}"
}

testZabbixDiscoverRunDuration() {
  #Add sleep
  AddSleepToConfig

  DATA=$(zabbix_get -s 127.0.0.1 -p 10050 -k php-fpm.discover["/php-fpm-status"])

  printElapsedTime
  assertExecutionTime
  printSuccess "${FUNCNAME[0]}"
}

testDiscoverScriptDoubleRun() {
  DATA_FIRST=$(sudo -u zabbix sudo "/etc/zabbix/zabbix_php_fpm_discovery.sh" "debug" "sleep" "/php-fpm-status")
  DATA_SECOND=$(sudo -u zabbix sudo "/etc/zabbix/zabbix_php_fpm_discovery.sh" "debug" "sleep" "/php-fpm-status")

  printElapsedTime
  assertNotEquals "Multiple discovery routines provide the same results: $DATA_FIRST" "$DATA_FIRST" "$DATA_SECOND"
  printSuccess "${FUNCNAME[0]}"
}

testZabbixDiscoverDoubleRun() {
  #Add sleep
  AddSleepToConfig

  DATA_FIRST=$(zabbix_get -s 127.0.0.1 -p 10050 -k php-fpm.discover["/php-fpm-status"])
  DATA_SECOND=$(zabbix_get -s 127.0.0.1 -p 10050 -k php-fpm.discover["/php-fpm-status"])

  printElapsedTime
  assertNotEquals "Multiple discovery routines provide the same results: $DATA_FIRST" "$DATA_FIRST" "$DATA_SECOND"
  printSuccess "${FUNCNAME[0]}"
}

function discoverAllZabbix() {
  DATA_OLD=$1
  DATA_COUNT=$2

  if [[ -z $DATA_COUNT ]]; then
    DATA_COUNT=0
  fi

  DATA=$(zabbix_get -s 127.0.0.1 -p 10050 -k php-fpm.discover["/php-fpm-status"])
  if [[ -n "$DATA" ]] && [[ -n "$DATA_OLD" ]] && [[ "$DATA_OLD" == "$DATA" ]]; then
    echo "$DATA"
    return 0
  else
    DATA_COUNT=$(echo "$DATA_COUNT + 1" | bc)
    if [[ $DATA_COUNT -gt $MAX_CHECKS ]]; then
      printYellow "Data old:"
      printDebug "$DATA_OLD"
      printYellow "Data new:"
      printDebug "$DATA"
      return 1
    fi
    discoverAllZabbix "$DATA" "$DATA_COUNT"
    STATUS=$?
    return $STATUS
  fi
}

checkNumberOfPools() {
  POOL_TYPE=$1
  CHECK_COUNT=$2

  DATA=$(discoverAllZabbix)
  STATUS=$?
  if [[ $STATUS -ne 0 ]]; then
    echo "$DATA"
    return 1
  fi
  assertEquals "Failed to discover all data when checking pools '$POOL_TYPE'" "0" "$STATUS"

  NUMBER_OF_POOLS=$(echo "$DATA" | grep -o -F "{\"{#POOLNAME}\":\"$POOL_TYPE" | wc -l)
  PHP_COUNT=$(getNumberOfPHPVersions)
  if [[ -n "$CHECK_COUNT" ]] && [[ "$CHECK_COUNT" -ge 0 ]]; then
    POOLS_BY_DESIGN="$CHECK_COUNT"
  else
    POOLS_BY_DESIGN=$(echo "$PHP_COUNT * $MAX_POOLS" | bc)
  fi
  assertEquals "Number of '$POOL_TYPE' pools mismatch" "$POOLS_BY_DESIGN" "$NUMBER_OF_POOLS"
  echo "$DATA"
  return 0
}

testZabbixDiscoverNumberOfSocketPools() {
  local DATA
  DATA=$(checkNumberOfPools "socket")
  travis_fold_start "${FUNCNAME[0]}" "ⓘ Zabbix response"
  echo "$DATA"
  travis_fold_end
  printElapsedTime
  printSuccess "${FUNCNAME[0]}"
}

testZabbixDiscoverNumberOfDynamicPools() {
  local DATA
  DATA=$(checkNumberOfPools "dynamic")
  travis_fold_start "${FUNCNAME[0]}" "ⓘ Zabbix response"
  echo "$DATA"
  travis_fold_end
  printElapsedTime
  printSuccess "${FUNCNAME[0]}"
}

testZabbixDiscoverNumberOfOndemandPoolsCold() {
  local DATA
  #If the pools are not started then we have 0 here:
  DATA=$(checkNumberOfPools "ondemand" 0)
  travis_fold_start "${FUNCNAME[0]}" "ⓘ Zabbix response"
  echo "$DATA"
  travis_fold_end
  printElapsedTime
  printSuccess "${FUNCNAME[0]}"
}

testZabbixDiscoverNumberOfOndemandPoolsHot() {
  startOndemandPoolsCache
  local DATA
  DATA=$(checkNumberOfPools "ondemand")
  travis_fold_start "${FUNCNAME[0]}" "ⓘ Zabbix response"
  echo "$DATA"
  travis_fold_end
  printElapsedTime
  printSuccess "${FUNCNAME[0]}"
}

testZabbixDiscoverNumberOfOndemandPoolsCache() {
  startOndemandPoolsCache

  printAction "Empty cache test..."
  INITIAL_DATA=$(checkNumberOfPools "ondemand")
  travis_fold_start "${FUNCNAME[0]}" "ⓘ Zabbix response"
  echo "$INITIAL_DATA"
  travis_fold_end

  WAIT_TIMEOUT=$(echo "$ONDEMAND_TIMEOUT * 2" | bc)
  sleep "$WAIT_TIMEOUT"

  printAction "Full cache test..."
  CACHED_DATA=$(checkNumberOfPools "ondemand")
  travis_fold_start "${FUNCNAME[0]}" "ⓘ Zabbix response"
  echo "$CACHED_DATA"
  travis_fold_end

  printElapsedTime
  assertEquals "Data mismatch" "$INITIAL_DATA" "$CACHED_DATA"
  printSuccess "${FUNCNAME[0]}"
}

testZabbixDiscoverNumberOfIPPools() {
  PHP_COUNT=$(getNumberOfPHPVersions)
  local DATA
  DATA=$(checkNumberOfPools "localhost" "$PHP_COUNT")
  travis_fold_start "${FUNCNAME[0]}" "ⓘ Zabbix response"
  echo "$DATA"
  travis_fold_end
  printElapsedTime
  printSuccess "${FUNCNAME[0]}"
}

testZabbixDiscoverNumberOfPortPools() {
  local DATA
  DATA=$(checkNumberOfPools "port")
  travis_fold_start "${FUNCNAME[0]}" "ⓘ Zabbix response"
  echo "$DATA"
  travis_fold_end
  printElapsedTime
  printSuccess "${FUNCNAME[0]}"
}

#This test should be last in Zabbix tests
testDiscoverScriptManyPools() {
  #Create lots of pools
  MAX_POOLS=20
  MAX_PORTS=20
  setupPools

  testDiscoverScriptReturnsData
  printSuccess "${FUNCNAME[0]}"
}

testZabbixDiscoverManyPools() {
  testZabbixDiscoverReturnsData
  printSuccess "${FUNCNAME[0]}"
}

testDiscoverScriptManyPoolsRunDuration() {
  MAX_RUNS=5
  for ((c = 1; c <= MAX_RUNS; c++)); do
    StartTimer
    printAction "Run #$c..."
    testDiscoverScriptRunDuration
  done
  printSuccess "${FUNCNAME[0]}"
}

testZabbixDiscoverManyPoolsRunDuration() {
  MAX_RUNS=5
  for ((c = 1; c <= MAX_RUNS; c++)); do
    StartTimer
    printAction "Run #$c..."
    testZabbixDiscoverRunDuration
  done
  printSuccess "${FUNCNAME[0]}"
}

# Load shUnit2.
. shunit2
