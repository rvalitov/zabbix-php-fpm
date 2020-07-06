#!/bin/bash
#Ramil Valitov ramilvalitov@gmail.com
#https://github.com/rvalitov/zabbix-php-fpm
#This script is used for testing

MAX_POOLS=3
MAX_PORTS=3
MIN_PORT=9000

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
}

setupPool() {
  POOL_FILE=$1
  POOL_DIR=$(dirname "${POOL_FILE}")
  PHP_VERSION=$(echo "$POOL_DIR" | grep -oP "(\d\.\d)")

  #Delete all active pools except www.conf:
  sudo find "$POOL_DIR" -name '*.conf' -type f -not -name 'www.conf' -exec rm -rf {} \;

  #Add status path
  sudo sed -i 's#;pm.status_path.*#pm.status_path = /php-fpm-status#' "$POOL_FILE"
  #Set pool manager
  sudo sed -i 's#pm = dynamic#pm = static#' "$POOL_FILE"

  #Create new socket pools
  for ((c = 1; c <= MAX_POOLS; c++)); do
    POOL_NAME="static$c"
    POOL_SOCKET="/run/php/php${PHP_VERSION}-fpm-${POOL_NAME}.sock"
    copyPool "$POOL_FILE" "$POOL_NAME" "$POOL_SOCKET" "static"
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

  #Create TCP port based pools
  #Division on 1 is required to convert from float to integer
  START_PORT=$(echo "($MIN_PORT + $PHP_VERSION * 100 + 1)/1" | bc)
  for ((c = 1; c <= MAX_PORTS; c++)); do
    POOL_NAME="port$c"
    POOL_PORT=$(echo "($START_PORT + $c)/1" | bc)
    copyPool "$POOL_FILE" "$POOL_NAME" "$POOL_PORT" "static"
  done

  #Create TCP IPv4 localhost pool
  POOL_NAME="localhost"
  POOL_PORT=$(echo "($MIN_PORT + $PHP_VERSION * 100)/1" | bc)
  POOL_SOCKET="127.0.0.1:$POOL_PORT"
  copyPool "$POOL_FILE" "$POOL_NAME" "$POOL_SOCKET" "static"

  sudo service "php${PHP_VERSION}-fpm" restart
}

setupPools() {
  PHP_LIST=$(find /etc/php/ -name 'www.conf' -type f)
  while IFS= read -r pool; do
    if [[ -n $pool ]]; then
      setupPool "$pool"
    fi
  done <<<"$PHP_LIST"
}

getNumberOfPHPVersions() {
  PHP_COUNT=$(find /etc/php/ -name 'www.conf' -type f | wc -l)
  echo "$PHP_COUNT"
}

getAnySocket() {
  #Get any socket of PHP-FPM:
  PHP_FIRST=$(find /etc/php/ -name 'www.conf' -type f | head -n1)
  assertNotNull "Failed to get PHP conf" "$PHP_FIRST"
  PHP_VERSION=$(echo "$PHP_FIRST" | grep -oP "(\d\.\d)")
  assertNotNull "Failed to get PHP version" "$PHP_VERSION"
  PHP_POOL=$(find /run/php/ -name "php${PHP_VERSION}*.sock" -type s | head -n1)
  assertNotNull "Failed to get PHP${PHP_VERSION} socket" "$PHP_POOL"
  echo "$PHP_POOL"
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
  sudo cp "$TRAVIS_BUILD_DIR/zabbix/userparameter_php_fpm.conf" "$(find /etc/zabbix/ -name 'zabbix_agentd*.d' -type d | head -n1)"
  sudo chmod +x /etc/zabbix/zabbix_php_fpm_discovery.sh
  sudo chmod +x /etc/zabbix/zabbix_php_fpm_status.sh

  #Configure Zabbix:
  echo 'zabbix ALL=NOPASSWD: /etc/zabbix/zabbix_php_fpm_discovery.sh,/etc/zabbix/zabbix_php_fpm_status.sh' | sudo EDITOR='tee -a' visudo
  sudo service zabbix-agent restart

  echo "Setup PHP-FPM..."

  #Setup PHP-FPM pools:
  setupPools

  echo "All done, starting tests..."
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
  PHP_POOL=$(getAnySocket)

  #Make the test:
  DATA=$(sudo bash "/etc/zabbix/zabbix_php_fpm_status.sh" "$PHP_POOL" "/php-fpm-status")
  IS_OK=$(echo "$DATA" | grep -F '{"pool":"')
  assertNotNull "Failed to get status from pool $PHP_POOL: $DATA" "$IS_OK"
  echo "Success test of $PHP_POOL"
}

testStatusScriptPort() {
  PHP_PORT=$(getAnyPort)
  PHP_POOL="127.0.0.1:$PHP_PORT"

  #Make the test:
  DATA=$(sudo bash "/etc/zabbix/zabbix_php_fpm_status.sh" "$PHP_POOL" "/php-fpm-status")
  IS_OK=$(echo "$DATA" | grep -F '{"pool":"')
  assertNotNull "Failed to get status from pool $PHP_POOL: $DATA" "$IS_OK"
  echo "Success test of $PHP_POOL"
}

testZabbixStatusSocket() {
  PHP_POOL=$(getAnySocket)

  DATA=$(zabbix_get -s 127.0.0.1 -p 10050 -k php-fpm.status["$PHP_POOL","/php-fpm-status"])
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
  DATA=$(sudo bash "/etc/zabbix/zabbix_php_fpm_discovery.sh" "/php-fpm-status")
  IS_OK=$(echo "$DATA" | grep -F '{"data":[{"{#POOLNAME}"')
  assertNotNull "Discover script failed: $DATA" "$IS_OK"
}

testDiscoverScriptDebug() {
  DATA=$(sudo bash "/etc/zabbix/zabbix_php_fpm_discovery.sh" "debug" "/php-fpm-status")
  ERRORS_LIST=$(echo "$DATA" | grep -F 'Error:')
  assertNull "Discover script errors: $DATA" "$ERRORS_LIST"
}

testZabbixDiscoverReturnsData() {
  DATA=$(zabbix_get -s 127.0.0.1 -p 10050 -k php-fpm.discover["/php-fpm-status"])
  IS_OK=$(echo "$DATA" | grep -F '{"data":[{"{#POOLNAME}"')
  assertNotNull "Discover script failed: $DATA" "$IS_OK"
}

testZabbixDiscoverNumberOfStaticPools() {
  DATA=$(zabbix_get -s 127.0.0.1 -p 10050 -k php-fpm.discover["/php-fpm-status"])
  NUMBER_OF_POOLS=$(echo "$DATA" | grep -o -F '{"{#POOLNAME}":"static' | wc -l)
  PHP_COUNT=$(getNumberOfPHPVersions)
  assertEquals "Number of pools mismatch" "$PHP_COUNT" "$NUMBER_OF_POOLS"
}

testZabbixDiscoverNumberOfDynamicPools() {
  DATA=$(zabbix_get -s 127.0.0.1 -p 10050 -k php-fpm.discover["/php-fpm-status"])
  NUMBER_OF_POOLS=$(echo "$DATA" | grep -o -F '{"{#POOLNAME}":"dynamic' | wc -l)
  PHP_COUNT=$(getNumberOfPHPVersions)
  assertEquals "Number of pools mismatch" "$PHP_COUNT" "$NUMBER_OF_POOLS"
}

testZabbixDiscoverNumberOfOndemandPools() {
  DATA=$(zabbix_get -s 127.0.0.1 -p 10050 -k php-fpm.discover["/php-fpm-status"])
  NUMBER_OF_POOLS=$(echo "$DATA" | grep -o -F '{"{#POOLNAME}":"ondemand' | wc -l)
  PHP_COUNT=$(getNumberOfPHPVersions)
  assertEquals "Number of pools mismatch" "$PHP_COUNT" "$NUMBER_OF_POOLS"
}

testZabbixDiscoverNumberOfIPPools() {
  DATA=$(zabbix_get -s 127.0.0.1 -p 10050 -k php-fpm.discover["/php-fpm-status"])
  NUMBER_OF_POOLS=$(echo "$DATA" | grep -o -F '{"{#POOLNAME}":"localhost",' | wc -l)
  PHP_COUNT=$(getNumberOfPHPVersions)
  assertEquals "Number of pools mismatch" "$PHP_COUNT" "$NUMBER_OF_POOLS"
}

testZabbixDiscoverNumberOfPortPools() {
  DATA=$(zabbix_get -s 127.0.0.1 -p 10050 -k php-fpm.discover["/php-fpm-status"])
  NUMBER_OF_POOLS=$(echo "$DATA" | grep -o -F '{"{#POOLNAME}":"port1",' | wc -l)
  PHP_COUNT=$(getNumberOfPHPVersions)
  assertEquals "Number of pools mismatch" "$PHP_COUNT" "$NUMBER_OF_POOLS"
}

#This test should be last in Zabbix tests
testZabbixDiscoverTimeout() {
  #Create lots of pools
  MAX_POOLS=100
  MAX_PORTS=100
  setupPools

  testZabbixDiscoverReturnsData
}

#################################
#The following tests should be last, no tests of actual data should be done afterwards

testMissingPackagesDiscoveryScript() {
  sudo apt-get -y purge jq

  DATA=$(sudo bash "/etc/zabbix/zabbix_php_fpm_discovery.sh" "/php-fpm-status")
  IS_OK=$(echo "$DATA" | grep -F ' not found.')
  assertNotNull "Discovery script didn't report error on missing utility 'jq'"
}

testMissingPackagesStatusScript() {
  sudo apt-get -y purge libfcgi-bin libfcgi0ldbl

  PHP_POOL=$(getAnySocket)
  DATA=$(sudo bash "/etc/zabbix/zabbix_php_fpm_status.sh" "$PHP_POOL" "/php-fpm-status")
  IS_OK=$(echo "$DATA" | grep -F ' not found.')
  assertNotNull "Status script didn't report error on missing utility 'cgi-fcgi'"
}

# Load shUnit2.
. shunit2
