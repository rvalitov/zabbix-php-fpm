#!/bin/bash
#Ramil Valitov ramilvalitov@gmail.com
#https://github.com/rvalitov/zabbix-php-fpm
#This script is used for testing

# Used for section folding in Travis CI
SECTION_UNIQUE_ID=""

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
  sudo cp "$TRAVIS_BUILD_DIR/zabbix/userparameter_php_fpm.conf" "$(find /etc/zabbix/ -name 'zabbix_agentd*.d' -type d | head -n1)"
  sudo chmod +x /etc/zabbix/zabbix_php_fpm_discovery.sh
  sudo chmod +x /etc/zabbix/zabbix_php_fpm_status.sh

  printAction "All done, starting tests..."
}

testMissingPackagesDiscoveryScript() {
  DATA=$(sudo bash "/etc/zabbix/zabbix_php_fpm_discovery.sh" "/php-fpm-status")
  IS_OK=$(echo "$DATA" | grep -F ' not found.')
  assertNotNull "Discovery script didn't report error on missing utilities $DATA" "$IS_OK"
  printSuccess "${FUNCNAME[0]}"
}

testMissingPackagesStatusScript() {
  DATA=$(sudo bash "/etc/zabbix/zabbix_php_fpm_status.sh" "localhost:9000" "/php-fpm-status")
  IS_OK=$(echo "$DATA" | grep -F ' not found.')
  assertNotNull "Status script didn't report error on missing utilities $DATA" "$IS_OK"
  printSuccess "${FUNCNAME[0]}"
}

# Load shUnit2.
. shunit2
