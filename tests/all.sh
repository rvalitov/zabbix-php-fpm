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

  #Make copies and create new pools
  MAX_POOLS=2
  for ((c = 1; c <= MAX_POOLS; c++)); do
    POOL_NAME="www-$c"
    NEW_POOL_FILE="$POOL_DIR/${POOL_NAME}.conf"
    sudo cp "$POOL_FILE" "$NEW_POOL_FILE"

    sudo sed -i "s#listen =.*#/run/php/php${PHP_VERSION}-fpm-${POOL_NAME}.sock#" "$NEW_POOL_FILE"
    sudo sed -i "s#\[www\]#[$POOL_NAME]#" "$NEW_POOL_FILE"
  done

  sudo service "php${PHP_VERSION}-fpm" restart
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
  echo 'zabbix ALL=NOPASSWD: /etc/zabbix/zabbix_php_fpm_discovery.sh' | sudo EDITOR='tee -a' visudo

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

testStatusScriptSocket() {
  #Get any socket of PHP-FPM:
  PHP_FIRST=$(find /etc/php/ -name 'www.conf' -type f | head -n1)
  assertNotNull "Failed to get PHP conf" "$PHP_FIRST"
  PHP_VERSION=$(echo "$PHP_FIRST" | grep -oP "(\d\.\d)")
  assertNotNull "Failed to get PHP version" "$PHP_VERSION"
  PHP_FIRST=$(find /run/php/ -name "php${PHP_VERSION}*.sock" -type s | head -n1)
  assertNotNull "Failed to get PHP${PHP_VERSION} socket" "$PHP_FIRST"

  #Make the test:
  DATA=$(bash "/etc/zabbix/zabbix_php_fpm_status.sh" "{$PHP_FIRST}" "/php-fpm-status")
  IS_OK=$(echo "$DATA" | grep -F '{"pool":"')
  assertNotNull "Failed to get status from pool: $DATA" "$IS_OK"
}

testDiscoverScriptReturnsData() {
  DATA=$(sudo bash "/etc/zabbix/zabbix_php_fpm_discovery.sh" "/php-fpm-status")
  IS_OK=$(echo "$DATA" | grep -F '{"data":[{"{#POOLNAME}"')
  assertNotNull "Discover script failed: $DATA" "$IS_OK"
}

# Load shUnit2.
. shunit2
