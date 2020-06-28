#!/bin/bash
#Ramil Valitov ramilvalitov@gmail.com
#https://github.com/rvalitov/zabbix-php-fpm
#This script is used for testing

testZabbixAgentInstalled() {
  ZABBIX_AGENT=$(type -P zabbix-agent)
  assertNotNull "Zabbix agent not installed" "$ZABBIX_AGENT"
}

# Load shUnit2.
. shunit2
