#!/bin/bash
#Ramil Valitov ramilvalitov@gmail.com
#https://github.com/rvalitov/zabbix-php-fpm
#This script is used for testing

MAX_POOLS=3
MAX_PORTS=3
MIN_PORT=49001
MAX_PORTS_COUNT=100
TEST_SOCKET=""
ONDEMAND_TIMEOUT=60
ZABBIX_TIMEOUT=20

function getUserParameters() {
  sudo find /etc/zabbix/ -name 'userparameter_php_fpm.conf' -type f | head -n1
}

function restoreUserParameters() {
  PARAMS_FILE=$(getUserParameters)
  sudo rm -f $PARAMS_FILE
  sudo cp "$TRAVIS_BUILD_DIR/zabbix/userparameter_php_fpm.conf" "$(sudo find /etc/zabbix/ -name 'zabbix_agentd*.d' -type d | head -n1)"
}

function AddSleepToConfig() {
  PARAMS_FILE=$(getUserParameters)
  sudo sed -i 's#.*zabbix_php_fpm_discovery.*#UserParameter=php-fpm.discover[*],sudo /etc/zabbix/zabbix_php_fpm_discovery.sh sleep $1#' "$PARAMS_FILE"
  echo "New UserParameter file:"
  sudo cat "$PARAMS_FILE"
  sudo service zabbix-agent restart
  sleep 2
}

copyPool() {
  ORIGINAL_FILE=$1
  POOL_NAME=$2
  POOL_SOCKET=$3
  POOL_TYPE=$4
  POOL_DIR=$(dirname "${ORIGINAL_FILE}")
  PHP_VERSION=$(echo "$POOL_DIR" | grep -oP "(\d\.\d)")

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

setupPool() {
  POOL_FILE=$1
  POOL_DIR=$(dirname "${POOL_FILE}")
  PHP_VERSION=$(echo "$POOL_DIR" | grep -oP "(\d\.\d)")

  #Delete all active pools except www.conf:
  sudo find "$POOL_DIR" -name '*.conf' -type f -not -name 'www.conf' -exec rm -rf {} \;

  #Create new socket pools
  for ((c = 1; c <= MAX_POOLS; c++)); do
    POOL_NAME="static$c"
    POOL_SOCKET="/run/php/php${PHP_VERSION}-fpm-${POOL_NAME}.sock"
    copyPool "$POOL_FILE" "$POOL_NAME" "$POOL_SOCKET" "static"
    if [[ -z $TEST_SOCKET ]]; then
      TEST_SOCKET="$POOL_SOCKET"
    fi
  done

  for ((c = 1; c <= MAX_POOLS; c++)); do
    POOL_NAME="dynamic$c"
    POOL_SOCKET="/run/php/php${PHP_VERSION}-fpm-${POOL_NAME}.sock"
    copyPool "$POOL_FILE" "$POOL_NAME" "$POOL_SOCKET" "dynamic"
  done

  for ((c = 1; c <= MAX_POOLS; c++)); do
    POOL_NAME="ondemand$c"
    POOL_SOCKET="/run/php/php${PHP_VERSION}-fpm-${POOL_NAME}.sock"
    copyPool "$POOL_FILE" "$POOL_NAME" "$POOL_SOCKET" "ondemand"
  done

  PHP_SERIAL_ID=$(find /etc/php/ -maxdepth 1 -mindepth 1 -type d | sort | grep -n -F "$PHP_VERSION" | cut -d : -f 1)
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

  echo "List of configured PHP$PHP_VERSION pools:"
  sudo ls -l "$POOL_DIR"
  sudo service "php${PHP_VERSION}-fpm" restart
  sleep 3

  echo "List of running PHP$PHP_VERSION pools:"
  sudo systemctl -l status "php${PHP_VERSION}-fpm.service"
  sleep 2
}

setupPools() {
  PHP_LIST=$(sudo find /etc/php/ -name 'www.conf' -type f)

  #First we need to stop all PHP-FPM
  while IFS= read -r pool; do
    if [[ -n $pool ]]; then
      POOL_DIR=$(dirname "$pool")
      PHP_VERSION=$(echo "$POOL_DIR" | grep -oP "(\d\.\d)")
      sudo service "php${PHP_VERSION}-fpm" stop
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
  PHP_COUNT=$(sudo find /etc/php/ -name 'www.conf' -type f | wc -l)
  echo "$PHP_COUNT"
}

function startOndemandPoolsCache() {
  # We must start all the pools
  POOL_URL="/php-fpm-status"

  PHP_LIST=$(sudo find /etc/php/ -name 'www.conf' -type f)
  while IFS= read -r pool; do
    if [[ -n $pool ]]; then
      POOL_DIR=$(dirname "$pool")
      PHP_VERSION=$(echo "$POOL_DIR" | grep -oP "(\d\.\d)")

      for ((c = 1; c <= MAX_POOLS; c++)); do
        POOL_NAME="ondemand$c"
        POOL_SOCKET="/run/php/php${PHP_VERSION}-fpm-${POOL_NAME}.sock"

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

getAnyPort() {
  PHP_PORT=$(sudo netstat -tulpn | grep -F "LISTEN" | grep -F "php-fpm" | head -n1 | awk '{print $4}' | rev | cut -d: -f1 | rev)
  assertNotNull "Failed to get PHP port" "$PHP_PORT"
  echo "$PHP_PORT"
}

oneTimeSetUp() {
  echo "Started job $TRAVIS_JOB_NAME"
  echo "Host info:"
  nslookup localhost
  sudo ifconfig
  sudo cat /etc/hosts
  echo "Copying Zabbix files..."
  #Install files:
  sudo cp "$TRAVIS_BUILD_DIR/zabbix/zabbix_php_fpm_discovery.sh" "/etc/zabbix"
  sudo cp "$TRAVIS_BUILD_DIR/zabbix/zabbix_php_fpm_status.sh" "/etc/zabbix"
  sudo cp "$TRAVIS_BUILD_DIR/zabbix/userparameter_php_fpm.conf" "$(sudo find /etc/zabbix/ -name 'zabbix_agentd*.d' -type d | head -n1)"
  sudo chmod +x /etc/zabbix/zabbix_php_fpm_discovery.sh
  sudo chmod +x /etc/zabbix/zabbix_php_fpm_status.sh

  #Configure Zabbix:
  echo 'zabbix ALL=NOPASSWD: /etc/zabbix/zabbix_php_fpm_discovery.sh,/etc/zabbix/zabbix_php_fpm_status.sh' | sudo EDITOR='tee -a' visudo
  sudo sed -i "s#.* Timeout=.*#Timeout = $ZABBIX_TIMEOUT#" "/etc/zabbix/zabbix_agentd.conf"
  sudo service zabbix-agent restart

  echo "Setup PHP-FPM..."

  #Setup PHP-FPM pools:
  setupPools

  echo "All done, starting tests..."
}

#Called before every test
setUp() {
  #Delete all cache files
  sudo rm -f "/etc/zabbix/php_fpm_results.cache"
  sudo rm -f "/etc/zabbix/php_fpm_pending.cache"
}

#Called after every test
tearDown() {
  restoreUserParameters
  sleep 2
  sudo service zabbix-agent restart
  sleep 2
}

testZabbixGetInstalled() {
  ZABBIX_GET=$(type -P zabbix_get)
  assertNotNull "Utility zabbix-get not installed" "$ZABBIX_GET"
}

testZabbixAgentVersion() {
  #Example: 4.4
  REQUESTED_VERSION=$(echo "$TRAVIS_JOB_NAME" | grep -i -F "zabbix" | head -n1 | cut -d "@" -f1 | cut -d " " -f2)
  INSTALLED_VERSION=$(zabbix_agentd -V | grep -F "zabbix" | head -n1 | rev | cut -d " " -f1 | rev | cut -d "." -f1,2)
  assertSame "Requested version $REQUESTED_VERSION and installed version $INSTALLED_VERSION of Zabbix agent do not match" "$REQUESTED_VERSION" "$INSTALLED_VERSION"
}

testZabbixGetVersion() {
  #Example: 4.4
  REQUESTED_VERSION=$(echo "$TRAVIS_JOB_NAME" | grep -i -F "zabbix" | head -n1 | cut -d "@" -f1 | cut -d " " -f2)
  INSTALLED_VERSION=$(zabbix_get -V | grep -F "zabbix" | head -n1 | rev | cut -d " " -f1 | rev | cut -d "." -f1,2)
  assertSame "Requested version $REQUESTED_VERSION and installed version $INSTALLED_VERSION of zabbix_get do not match" "$REQUESTED_VERSION" "$INSTALLED_VERSION"
}

testPHPIsRunning() {
  IS_OK=$(sudo ps ax | grep -F "php-fpm: pool " | grep -F -v "grep" | head -n1)
  assertNotNull "No running PHP-FPM instances found" "$IS_OK"
}

testStatusScriptSocket() {
  assertNotNull "Test socket is not defined" "$TEST_SOCKET"
  DATA=$(sudo -u zabbix sudo "/etc/zabbix/zabbix_php_fpm_status.sh" "$TEST_SOCKET" "/php-fpm-status")
  IS_OK=$(echo "$DATA" | grep -F '{"pool":"')
  assertNotNull "Failed to get status from pool $TEST_SOCKET: $DATA" "$IS_OK"
  echo "Success test of $TEST_SOCKET"
}

testStatusScriptPort() {
  PHP_PORT=$(getAnyPort)
  PHP_POOL="127.0.0.1:$PHP_PORT"

  #Make the test:
  DATA=$(sudo -u zabbix sudo "/etc/zabbix/zabbix_php_fpm_status.sh" "$PHP_POOL" "/php-fpm-status")
  IS_OK=$(echo "$DATA" | grep -F '{"pool":"')
  assertNotNull "Failed to get status from pool $PHP_POOL: $DATA" "$IS_OK"
  echo "Success test of $PHP_POOL"
}

testZabbixStatusSocket() {
  DATA=$(zabbix_get -s 127.0.0.1 -p 10050 -k php-fpm.status["$TEST_SOCKET","/php-fpm-status"])
  IS_OK=$(echo "$DATA" | grep -F '{"pool":"')
  assertNotNull "Failed to get status from pool $PHP_POOL: $DATA" "$IS_OK"
  echo "Success test of $PHP_POOL"
}

testZabbixStatusPort() {
  PHP_PORT=$(getAnyPort)
  PHP_POOL="127.0.0.1:$PHP_PORT"

  DATA=$(zabbix_get -s 127.0.0.1 -p 10050 -k php-fpm.status["$PHP_POOL","/php-fpm-status"])
  IS_OK=$(echo "$DATA" | grep -F '{"pool":"')
  assertNotNull "Failed to get status from pool $PHP_POOL: $DATA" "$IS_OK"
  echo "Success test of $PHP_POOL"
}

testDiscoverScriptReturnsData() {
  DATA=$(sudo -u zabbix sudo "/etc/zabbix/zabbix_php_fpm_discovery.sh" "/php-fpm-status")
  IS_OK=$(echo "$DATA" | grep -F '{"data":[{"{#POOLNAME}"')
  assertNotNull "Discover script failed: $DATA" "$IS_OK"
}

testDiscoverScriptDebug() {
  DATA=$(sudo -u zabbix sudo "/etc/zabbix/zabbix_php_fpm_discovery.sh" "debug" "nosleep" "/php-fpm-status")
  NUMBER_OF_ERRORS=$(echo "$DATA" | grep -o -F 'Error:' | wc -l)
  PHP_COUNT=$(getNumberOfPHPVersions)
  if [[ $PHP_COUNT != "$NUMBER_OF_ERRORS" ]]; then
    ERRORS_LIST=$(echo "$DATA" | grep -F 'Error:')
    echo "Errors list:"
    echo "$ERRORS_LIST"
    echo "Full output:"
    echo "$DATA"
  fi
  assertEquals "Discover script errors mismatch" "$PHP_COUNT" "$NUMBER_OF_ERRORS"
}

testZabbixDiscoverReturnsData() {
  DATA=$(zabbix_get -s 127.0.0.1 -p 10050 -k php-fpm.discover["/php-fpm-status"])
  IS_OK=$(echo "$DATA" | grep -F '{"data":[{"{#POOLNAME}"')
  assertNotNull "Discover script failed: $DATA" "$IS_OK"
}

testDiscoverScriptSleep() {
  DATA=$(sudo -u zabbix sudo "/etc/zabbix/zabbix_php_fpm_discovery.sh" "debug" "sleep" "/php-fpm-status")
  CHECK_OK_COUNT=$(echo "$DATA" | grep -o -F "execution time OK" | wc -l)
  STOP_OK_COUNT=$(echo "$DATA" | grep -o -F "stop required" | wc -l)

  echo "Success time checks: $CHECK_OK_COUNT"
  echo "Stop time checks: $STOP_OK_COUNT"

  if [[ $CHECK_OK_COUNT -lt 1 ]] || [[ $STOP_OK_COUNT -lt 1 ]]; then
    echo "$DATA"
  fi
  assertTrue "No success time checks detected" "[ $CHECK_OK_COUNT -gt 0 ]"
  assertTrue "No success stop checks detected" "[ $STOP_OK_COUNT -gt 0 ]"
}

testZabbixDiscoverSleep() {
  #Add sleep
  AddSleepToConfig

  testZabbixDiscoverReturnsData
}

testDiscoverScriptRunDuration() {
  START_TIME=$(date +%s%N)
  DATA=$(sudo -u zabbix sudo "/etc/zabbix/zabbix_php_fpm_discovery.sh" "debug" "sleep" "/php-fpm-status")
  END_TIME=$(date +%s%N)
  ELAPSED_TIME=$(echo "($END_TIME - $START_TIME)/1000000" | bc)
  CHECK_OK_COUNT=$(echo "$DATA" | grep -o -F "execution time OK" | wc -l)
  STOP_OK_COUNT=$(echo "$DATA" | grep -o -F "stop required" | wc -l)
  MAX_TIME=$(echo "$ZABBIX_TIMEOUT * 1000" | bc)

  echo "Elapsed time $ELAPSED_TIME ms"
  echo "Success time checks: $CHECK_OK_COUNT"
  echo "Stop time checks: $STOP_OK_COUNT"

  assertTrue "The script worked for too long" "[ $ELAPSED_TIME -lt $MAX_TIME ]"
}

testZabbixDiscoverRunDuration() {
  #Add sleep
  AddSleepToConfig

  START_TIME=$(date +%s%N)
  DATA=$(zabbix_get -s 127.0.0.1 -p 10050 -k php-fpm.discover["/php-fpm-status"])
  END_TIME=$(date +%s%N)
  ELAPSED_TIME=$(echo "($END_TIME - $START_TIME)/1000000" | bc)
  MAX_TIME=$(echo "$ZABBIX_TIMEOUT * 1000" | bc)

  echo "Elapsed time $ELAPSED_TIME ms"

  assertTrue "The script worked for too long" "[ $ELAPSED_TIME -lt $MAX_TIME ]"
}

testDiscoverScriptDoubleRun() {
  DATA_FIRST=$(sudo -u zabbix sudo "/etc/zabbix/zabbix_php_fpm_discovery.sh" "debug" "sleep" "/php-fpm-status")
  DATA_SECOND=$(sudo -u zabbix sudo "/etc/zabbix/zabbix_php_fpm_discovery.sh" "debug" "sleep" "/php-fpm-status")

  assertNotEquals "Multiple discovery routines provide the same results" "$DATA_FIRST" "$DATA_SECOND"
}

testZabbixDiscoverDoubleRun() {
  #Add sleep
  AddSleepToConfig

  DATA_FIRST=$(zabbix_get -s 127.0.0.1 -p 10050 -k php-fpm.discover["/php-fpm-status"])
  DATA_SECOND=$(zabbix_get -s 127.0.0.1 -p 10050 -k php-fpm.discover["/php-fpm-status"])

  assertNotEquals "Multiple discovery routines provide the same results" "$DATA_FIRST" "$DATA_SECOND"
}

function discoverAllZabbix() {
  DATA_OLD=$1
  DATA_COUNT=$2
  MAX_CHECKS=150

  if [[ -z $DATA_COUNT ]]; then
    DATA_COUNT=0
  fi

  DATA=$(zabbix_get -s 127.0.0.1 -p 10050 -k php-fpm.discover["/php-fpm-status"])
  if [[ "$DATA_OLD" == "$DATA" ]]; then
    echo "$DATA"
    return 0
  else
    DATA_COUNT=$(echo "$DATA_COUNT + 1" | bc)
    if [[ $DATA_COUNT -gt $MAX_CHECKS ]]; then
      echo "Data old: $DATA_OLD"
      echo "Data new: $DATA"
      return 1
    fi
    discoverAllZabbix "$DATA" "$DATA_COUNT"
  fi
}

testZabbixDiscoverNumberOfStaticPools() {
  DATA=$(discoverAllZabbix)
  STATUS=$?
  if [[ $STATUS -ne 0 ]]; then
    echo "$DATA"
  fi
  assertEquals "Failed to discover all data" "0" "$STATUS"

  NUMBER_OF_POOLS=$(echo "$DATA" | grep -o -F '{"{#POOLNAME}":"static' | wc -l)
  PHP_COUNT=$(getNumberOfPHPVersions)
  POOLS_BY_DESIGN=$(echo "$PHP_COUNT * $MAX_POOLS" | bc)
  assertEquals "Number of pools mismatch" "$POOLS_BY_DESIGN" "$NUMBER_OF_POOLS"
}

testZabbixDiscoverNumberOfDynamicPools() {
  DATA=$(discoverAllZabbix)
  STATUS=$?
  if [[ $STATUS -ne 0 ]]; then
    echo "$DATA"
  fi
  assertEquals "Failed to discover all data" "0" "$STATUS"

  NUMBER_OF_POOLS=$(echo "$DATA" | grep -o -F '{"{#POOLNAME}":"dynamic' | wc -l)
  PHP_COUNT=$(getNumberOfPHPVersions)
  POOLS_BY_DESIGN=$(echo "$PHP_COUNT * $MAX_POOLS" | bc)
  assertEquals "Number of pools mismatch" "$POOLS_BY_DESIGN" "$NUMBER_OF_POOLS"
}

testZabbixDiscoverNumberOfOndemandPoolsCold() {
  DATA=$(discoverAllZabbix)
  STATUS=$?
  if [[ $STATUS -ne 0 ]]; then
    echo "$DATA"
  fi
  assertEquals "Failed to discover all data" "0" "$STATUS"

  NUMBER_OF_POOLS=$(echo "$DATA" | grep -o -F '{"{#POOLNAME}":"ondemand' | wc -l)
  #If the pools are not started then we have 0 here:
  assertEquals "Number of pools mismatch" "0" "$NUMBER_OF_POOLS"
}

testZabbixDiscoverNumberOfOndemandPoolsHot() {
  PHP_COUNT=$(getNumberOfPHPVersions)
  startOndemandPoolsCache

  DATA=$(discoverAllZabbix)
  STATUS=$?
  if [[ $STATUS -ne 0 ]]; then
    echo "$DATA"
  fi
  assertEquals "Failed to discover all data" "0" "$STATUS"

  NUMBER_OF_POOLS=$(echo "$DATA" | grep -o -F '{"{#POOLNAME}":"ondemand' | wc -l)
  PHP_COUNT=$(getNumberOfPHPVersions)
  POOLS_BY_DESIGN=$(echo "$PHP_COUNT * $MAX_POOLS" | bc)
  assertEquals "Number of pools mismatch" "$POOLS_BY_DESIGN" "$NUMBER_OF_POOLS"
}

testZabbixDiscoverNumberOfOndemandPoolsCache() {
  PHP_COUNT=$(getNumberOfPHPVersions)
  startOndemandPoolsCache

  DATA=$(discoverAllZabbix)
  STATUS=$?
  if [[ $STATUS -ne 0 ]]; then
    echo "$DATA"
  fi
  assertEquals "Failed to discover all data (initial check)" "0" "$STATUS"

  NUMBER_OF_POOLS=$(echo "$DATA" | grep -o -F '{"{#POOLNAME}":"ondemand' | wc -l)
  PHP_COUNT=$(getNumberOfPHPVersions)
  POOLS_BY_DESIGN=$(echo "$PHP_COUNT * $MAX_POOLS" | bc)
  assertEquals "Number of pools mismatch (initial check)" "$POOLS_BY_DESIGN" "$NUMBER_OF_POOLS"

  WAIT_TIMEOUT=$(echo "$ONDEMAND_TIMEOUT * 2" | bc)
  sleep "$WAIT_TIMEOUT"

  DATA_CACHE=$(discoverAllZabbix)
  STATUS=$?
  if [[ $STATUS -ne 0 ]]; then
    echo "$DATA"
  fi
  assertEquals "Failed to discover all data (final check)" "0" "$STATUS"

  NUMBER_OF_POOLS=$(echo "$DATA" | grep -o -F '{"{#POOLNAME}":"ondemand' | wc -l)
  PHP_COUNT=$(getNumberOfPHPVersions)
  POOLS_BY_DESIGN=$(echo "$PHP_COUNT * $MAX_POOLS" | bc)
  assertEquals "Number of pools mismatch (final check)" "$POOLS_BY_DESIGN" "$NUMBER_OF_POOLS"
  assertEquals "Data mismatch" "$DATA" "$DATA_CACHE"
}

testZabbixDiscoverNumberOfIPPools() {
  DATA=$(discoverAllZabbix)
  STATUS=$?
  if [[ $STATUS -ne 0 ]]; then
    echo "$DATA"
  fi
  assertEquals "Failed to discover all data" "0" "$STATUS"

  NUMBER_OF_POOLS=$(echo "$DATA" | grep -o -F '{"{#POOLNAME}":"localhost",' | wc -l)
  PHP_COUNT=$(getNumberOfPHPVersions)
  POOLS_BY_DESIGN="$PHP_COUNT"
  assertEquals "Number of pools mismatch" "$POOLS_BY_DESIGN" "$NUMBER_OF_POOLS"
}

testZabbixDiscoverNumberOfPortPools() {
  DATA=$(discoverAllZabbix)
  STATUS=$?
  if [[ $STATUS -ne 0 ]]; then
    echo "$DATA"
  fi
  assertEquals "Failed to discover all data" "0" "$STATUS"

  NUMBER_OF_POOLS=$(echo "$DATA" | grep -o -F '{"{#POOLNAME}":"port' | wc -l)
  PHP_COUNT=$(getNumberOfPHPVersions)
  POOLS_BY_DESIGN=$(echo "$PHP_COUNT * $MAX_POOLS" | bc)
  assertEquals "Number of pools mismatch" "$POOLS_BY_DESIGN" "$NUMBER_OF_POOLS"
}

#This test should be last in Zabbix tests
testDiscoverScriptManyPools() {
  #Create lots of pools
  MAX_POOLS=20
  MAX_PORTS=20
  setupPools

  testDiscoverScriptReturnsData
}

testZabbixDiscoverManyPools() {
  testZabbixDiscoverReturnsData
}

testDiscoverScriptManyPoolsRunDuration() {
  MAX_RUNS=5
  for ((c = 1; c <= MAX_RUNS; c++)); do
    echo "Run #$c..."
    testDiscoverScriptRunDuration
  done
}

testZabbixDiscoverManyPoolsRunDuration() {
  MAX_RUNS=5
  for ((c = 1; c <= MAX_RUNS; c++)); do
    echo "Run #$c..."
    testZabbixDiscoverRunDuration
  done
}

# Load shUnit2.
. shunit2
