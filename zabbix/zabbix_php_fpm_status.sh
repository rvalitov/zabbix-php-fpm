#!/bin/bash
#Ramil Valitov ramilvalitov@gmail.com
#https://github.com/rvalitov/zabbix-php-fpm
#Script gets status of PHP-FPM pool

S_FCGI=$(type -P cgi-fcgi)
S_GREP=$(type -P grep)
S_CAT=$(type -P cat)

if [[ ! -x $S_CAT ]]; then
  echo "Utility 'cat' not found. Please, install it first."
  exit 1
fi
if [[ ! -x $S_FCGI ]]; then
  echo "Utility 'cgi-fcgi' not found. Please, install it first. The required package's name depends on your OS type and version and can be 'libfcgi-bin' or 'libfcgi0ldbl' or 'fcgi'."
  exit 1
fi
if [[ ! -x $S_GREP ]]; then
  echo "Utility 'grep' not found. Please, install it first."
  exit 1
fi

USER_ID=$(id -u)
if [[ $USER_ID -ne 0 ]]; then
  echo "Insufficient privileges. This script must be run under 'root' user or with 'sudo'."
  exit 1
fi

if [[ -z $1 ]] || [[ -z $2 ]]; then
  $S_CAT <<EOF
No input data specified

NAME: status script for zabbix-php-fpm
USAGE: $0 <SOCKET_IP> <STATUS_PATH>
OPTIONS:
  <SOCKET_IP> - either path to socket file, for example, "/var/lib/php7.3-fpm/web1.sock", or IP and port of the PHP-FPM, for example, "127.0.0.1:9000"
  <STATUS_PATH> - path configured in "pm.status" option of the PHP-FPM pool

AUTHOR: Ramil Valitov ramilvalitov@gmail.com
PROJECT PAGE: https://github.com/rvalitov/zabbix-php-fpm
WIKI & DOCS: https://github.com/rvalitov/zabbix-php-fpm/wiki
EOF
  exit 1
fi

POOL_URL=$1
POOL_PATH=$2
#connecting to socket or address, https://easyengine.io/tutorials/php/directly-connect-php-fpm/
PHP_STATUS=$(
  SCRIPT_NAME=$POOL_PATH \
    SCRIPT_FILENAME=$POOL_PATH \
    QUERY_STRING=json \
    REQUEST_METHOD=GET \
    $S_FCGI -bind -connect "$POOL_URL" 2>/dev/null
)
echo "$PHP_STATUS" | $S_GREP "{"
exit 0
