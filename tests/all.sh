#!/bin/bash
#Ramil Valitov ramilvalitov@gmail.com
#https://github.com/rvalitov/zabbix-php-fpm
#This script is used for testing

setupPool() {
  POOL_FILE=$1
  POOL_DIR=$(dirname "${POOL_FILE}")
  PHP_VERSION=$(echo "$POOL_DIR" | grep -oP "(\d\.\d)")

  #Add status path
  echo 'pm.status_path = /php-fpm-status' | sudo tee -a "$POOL_FILE"
  #Set pool manager
  sudo sed -i 's#pm = dynamic#pm = static#' "$POOL_FILE"

  #Make copies and create new socket pools
  MAX_POOLS=50
  for ((c = 1; c <= MAX_POOLS; c++)); do
    POOL_NAME="socket$c"
    NEW_POOL_FILE="$POOL_DIR/${POOL_NAME}.conf"
    sudo cp "$POOL_FILE" "$NEW_POOL_FILE"

    sudo sed -i "s#listen =.*#listen = /run/php/php${PHP_VERSION}-fpm-${POOL_NAME}.sock#" "$NEW_POOL_FILE"
    sudo sed -i "s#\[www\]#[$POOL_NAME]#" "$NEW_POOL_FILE"
  done

  #Make copies and create HTTP pools
  MAX_PORTS=50
  #Division on 1 is required to convert from float to integer
  START_PORT=$(echo "(9000 + $PHP_VERSION * 100)/1" | bc)
  for ((c = 1; c <= MAX_PORTS; c++)); do
    POOL_NAME="http$c"
    POOL_PORT=$(echo "($START_PORT + $c)/1" | bc)
    NEW_POOL_FILE="$POOL_DIR/${POOL_NAME}.conf"
    sudo cp "$POOL_FILE" "$NEW_POOL_FILE"

    sudo sed -i "s#listen =.*#listen = 127.0.0.1:$POOL_PORT#" "$NEW_POOL_FILE"
    sudo sed -i "s#\[www\]#[$POOL_NAME]#" "$NEW_POOL_FILE"
  done

  sudo service "php${PHP_VERSION}-fpm" restart
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
  PHP_LIST=$(find /etc/php/ -name 'www.conf' -type f)
  while IFS= read -r pool; do
    if [[ -n $pool ]]; then
      setupPool "$pool"
    fi
  done <<<"$PHP_LIST"

  echo "All done, starting tests..."
}

testZabbixGetInstalled() {
  ZABBIX_GET=$(type -P zabbix_get)
  assertNotNull "Utility zabbix-get not installed" "$ZABBIX_GET"
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
}

testStatusScriptPort() {
  PHP_PORT=$(getAnyPort)
  PHP_POOL="127.0.0.1:$PHP_PORT"

  #Make the test:
  DATA=$(sudo bash "/etc/zabbix/zabbix_php_fpm_status.sh" "$PHP_POOL" "/php-fpm-status")
  IS_OK=$(echo "$DATA" | grep -F '{"pool":"')
  assertNotNull "Failed to get status from pool $PHP_POOL: $DATA" "$IS_OK"
}

testZabbixStatusSocket() {
  PHP_POOL=$(getAnySocket)

  DATA=$(zabbix_get -s 127.0.0.1 -p 10050 -k php-fpm.status["$PHP_POOL","/php-fpm-status"])
  IS_OK=$(echo "$DATA" | grep -F '{"pool":"')
  assertNotNull "Failed to get status from pool $PHP_POOL: $DATA" "$IS_OK"
}

testZabbixStatusPort() {
  PHP_PORT=$(getAnyPort)
  PHP_POOL="127.0.0.1:$PHP_PORT"

  DATA=$(zabbix_get -s 127.0.0.1 -p 10050 -k php-fpm.status["$PHP_POOL","/php-fpm-status"])
  IS_OK=$(echo "$DATA" | grep -F '{"pool":"')
  assertNotNull "Failed to get status from pool $PHP_POOL: $DATA" "$IS_OK"
}

testDiscoverScriptReturnsData() {
  DATA=$(sudo bash "/etc/zabbix/zabbix_php_fpm_discovery.sh" "/php-fpm-status")
  IS_OK=$(echo "$DATA" | grep -F '{"data":[{"{#POOLNAME}"')
  assertNotNull "Discover script failed: $DATA" "$IS_OK"
}

# Load shUnit2.
. shunit2
