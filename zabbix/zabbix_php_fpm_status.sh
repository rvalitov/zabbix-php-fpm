#!/bin/bash
#Ramil Valitov ramilvalitov@gmail.com
#https://github.com/rvalitov/zabbix-php-fpm

S_FCGI=`which cgi-fcgi`
S_GREP=`which grep`

if [[ ! -f $S_FCGI ]]; then
	echo "Utility 'cgi-fcgi' not found. Please, install it first."
	echo "In Debian you should install a package libfcgi0ldbl"
	exit 1
fi

if [[ ! -f $S_GREP ]]; then
	echo "Utility 'grep' not found. Please, install it first."
	exit 1
fi

if [[ -z $1 ]] || [[ -z $2 ]]; then
	echo "No input data specified"
	echo "Usage: $0 socket status"
	echo "where:"
	echo "socket - path to socket file, for example, /var/lib/php7.3-fpm/web1.sock"
	echo "status - path configured in pm.status of PHP-FPM"
	exit 1
fi

POOL_URL=$1
POOL_PATH=$2
echo "$POOL_URL $POOL_PATH" > /tmp/test.txt
#connecting to socket or address, https://easyengine.io/tutorials/php/directly-connect-php-fpm/	
PHP_STATUS=`SCRIPT_NAME=$POOL_PATH \
SCRIPT_FILENAME=$POOL_PATH \
QUERY_STRING=json \
REQUEST_METHOD=GET \
$S_FCGI -bind -connect $POOL_URL 2>/dev/null`
echo "$PHP_STATUS" | $S_GREP "{"