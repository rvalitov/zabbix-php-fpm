#!/bin/bash
#Ramil Valitov ramilvalitov@gmail.com
#https://github.com/rvalitov/zabbix-php-fpm
#This script is used for testing

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

  sudo apt-get -y purge jq
  sudo apt-get -y purge libfcgi-bin libfcgi0ldbl
  sudo apt autoremove

  echo "All done, starting tests..."
}

testMissingPackagesDiscoveryScript() {
  DATA=$(sudo bash "/etc/zabbix/zabbix_php_fpm_discovery.sh" "/php-fpm-status")
  IS_OK=$(echo "$DATA" | grep -F ' not found.')
  assertNotNull "Discovery script didn't report error on missing utilities $DATA" "$IS_OK"
}

testMissingPackagesStatusScript() {
  DATA=$(sudo bash "/etc/zabbix/zabbix_php_fpm_status.sh" "localhost:9000" "/php-fpm-status")
  IS_OK=$(echo "$DATA" | grep -F ' not found.')
  assertNotNull "Status script didn't report error on missing utilities $DATA" "$IS_OK"
}

# Load shUnit2.
. shunit2
