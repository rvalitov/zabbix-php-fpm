#!/bin/bash
#Ramil Valitov ramilvalitov@gmail.com
#https://github.com/rvalitov/zabbix-php-fpm
#Script gets status of PHP-FPM pool

S_FCGI=`type -P cgi-fcgi`
S_GREP=`type -P grep`

if [[ ! -f $S_FCGI ]]; then
	echo "Utility 'cgi-fcgi' not found. Please, install it first."
	exit 1
fi

if [[ ! -f $S_GREP ]]; then
	echo "Utility 'grep' not found. Please, install it first."
	exit 1
fi

if [[ -z $1 ]] || [[ -z $2 ]]; then
	echo "No input data specified"
	echo "Usage: $0 php-path status"
	echo "where:"
	echo "php-path - path to socket file, for example, /var/lib/php7.3-fpm/web1.sock"
	echo "or IP and port of the PHP-FPM, for example, 127.0.0.1:9000"
	echo "status - path configured in pm.status of PHP-FPM"
	exit 1
fi

POOL_URL=$1
POOL_PATH=$2
#connecting to socket or address, https://easyengine.io/tutorials/php/directly-connect-php-fpm/	
PHP_STATUS=`SCRIPT_NAME=$POOL_PATH \
SCRIPT_FILENAME=$POOL_PATH \
QUERY_STRING=json \
REQUEST_METHOD=GET \
$S_FCGI -bind -connect $POOL_URL 2>/dev/null`
echo "$PHP_STATUS" | $S_GREP "{"