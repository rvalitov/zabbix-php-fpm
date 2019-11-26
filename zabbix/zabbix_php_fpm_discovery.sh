#!/bin/bash
#Ramil Valitov ramilvalitov@gmail.com
#https://github.com/rvalitov/zabbix-php-fpm

S_PS=`type -P ps`
S_GREP=`type -P grep`
S_AWK=`type -P awk`
S_SORT=`type -P sort`
S_HEAD=`type -P head`
S_LSOF=`type -P lsof`
S_JQ=`type -P jq`

if [[ ! -f $S_PS ]]; then
	echo "Utility 'ps' not found. Please, install it first."
	exit 1
fi
if [[ ! -f $S_GREP ]]; then
	echo "Utility 'grep' not found. Please, install it first."
	exit 1
fi
if [[ ! -f $S_AWK ]]; then
	echo "Utility 'awk' not found. Please, install it first."
	exit 1
fi
if [[ ! -f $S_SORT ]]; then
	echo "Utility 'sort' not found. Please, install it first."
	exit 1
fi
if [[ ! -f $S_HEAD ]]; then
	echo "Utility 'head' not found. Please, install it first."
	exit 1
fi
if [[ ! -f $S_LSOF ]]; then
	echo "Utility 'lsof' not found. Please, install it first."
	exit 1
fi
if [[ ! -f $S_JQ ]]; then
	echo "Utility 'jq' not found. Please, install it first."
	exit 1
fi

mapfile -t PS_LIST < <( $S_PS ax | $S_GREP "php-fpm: pool " | $S_GREP -v grep )
POOL_LIST=`printf '%s\n' "${PS_LIST[@]}" | $S_AWK '{print $NF}' | $S_SORT -u`
POOL_FIRST=0
echo -n "{\"data\":["
while IFS= read -r line
do
    POOL_PID=`printf '%s\n' "${PS_LIST[@]}" | $S_GREP "php-fpm: pool $line" | $S_HEAD -1 | $S_AWK '{print $1}'`
    if [[ ! -z $POOL_PID ]]; then
        POOL_SOCKET=`$S_LSOF -p $POOL_PID 2>/dev/null | $S_GREP unix | $S_HEAD -1 | $S_AWK '{ print $(NF)}'`
        if [[ ! -z $POOL_SOCKET ]]; then
            if [[ $POOL_FIRST == 1 ]]; then
                echo -n ","
            fi
            echo -n "{\"{#POOLNAME}\":"
            echo -n "$line" | $S_JQ -aR .
            echo -n ",\"{#POOLSOCKET}\":"
            echo -n "$POOL_SOCKET" | $S_JQ -aR .
            echo -n "}"
            POOL_FIRST=1
        fi
    fi
done <<< "$POOL_LIST"
echo -n "]}"
