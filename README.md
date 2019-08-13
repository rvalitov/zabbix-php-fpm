# PHP-FPM Zabbix Template with Auto Discovery and Multiple Pools

![Zabbix version logo](https://img.shields.io/badge/Zabbix-v4.x+-green.svg?style=flat) ![PHP](https://img.shields.io/badge/PHP-5.6.x+-blue.svg?style=flat) ![PHP7](https://img.shields.io/badge/PHP7-supported-green.svg?style=flat) ![LLD](https://img.shields.io/badge/LLD-yes-green.svg?style=flat) ![ISPConfig](https://img.shields.io/badge/ISPConfig-supported-green.svg?style=flat)

![Banner](https://github.com/rvalitov/zabbix-php-fpm/raw/master/media/repository-open-graph-template.png)

## Main features

- Supports auto discovery of PHP-FPM pools (LLD) and automatic detection of sockets used by pools
- Supports multiple PHP-FPM pools
- Supports multiple PHP versions, i.e. you can use PHP 7.2 and PHP 7.3 on the same server and we will detect them all
- Easy configuration
- Supports ISPConfig
- Script is in pure bash: no need to install Perl, PHP, Go or other languages. 

## Provided Items
We capture only useful data from host and PHP-FPM status page:

- Number of CPUs
- For each pool:

    - **Accepted Connections Per Second** - the number of requests accepted by the pool
    - **Active Processes** - the number of active processes
    - **Idle Processes** - the number of idle processes
    - **Max Children Reached**  – the number of times, the process limit has been reached, when pm tries to start more children (works only for pm `dynamic` and `ondemand`)
    - **CPU Utilization** - CPU load for all processes of the pool in %
    - **CPU Average Utilization** - CPU load for all processes of the pool in % normalized by number of CPUs
    - **Listen Queue** - the number of requests in the queue of pending connections
    - **Max Listen Queue** - the maximum number of requests in the queue of pending connections since FPM has started
    - **Listen Queue Length** - the size of the socket queue of pending connections
    - **Queue Utilization** - queue usage in %
    - **Memory Used** - how much RAM used by the pool in bytes
    - **Memory Utilization** - how much RAM used by the pool in %
    - **Process Manager** - `dynamic`, `ondemand` or `static`, see [PHP manual](https://www.php.net/manual/en/install.fpm.configuration.php#pm).
    - **Slow Requests** - the number of requests that exceeded your [`request_slowlog_timeout`](https://www.php.net/manual/en/install.fpm.configuration.php#request-slowlog-timeout) value.
    - **Start Since** - number of seconds since FPM has started
    - **Start Time** - the date and time FPM has started

History storage period is from 1 hour to 1 day (depends on specific item), trend storage period is 365 days that's optimal for environments with multiple websites.
Data is captured every minute. These timings can be adjusted in template or per host if needed.

## Provided Triggers

- Too many connections on pool
- PHP-FPM uses too much memory
- PHP-FPM manager changed
- PHP-FPM uses queue
- PHP-FPM detected slow request

## Provided Graphs
#### Connections
![Zabbix PHP-FPM connections graph](https://github.com/rvalitov/zabbix-php-fpm/raw/master/media/demo-connections.png)

Displays the following data:

- Accepted connections per second
- CPU average utilization in %
- Memory utilization in %
- Queue utilization in %

#### CPU
![Zabbix PHP-FPM CPU utilization graph](https://github.com/rvalitov/zabbix-php-fpm/raw/master/media/demo-cpu.png)

Displays the following data:

- CPU average utilization in %
- Accepted connections per second

#### Memory
![Zabbix PHP-FPM RAM utilization graph](https://github.com/rvalitov/zabbix-php-fpm/raw/master/media/demo-memory.png)

Displays the following data:

- Memory used in bytes
- CPU average utilization in %
- Memory utilization in %
- Queue utilization in %

#### Process
![Zabbix PHP-FPM CPU utilization graph](https://github.com/rvalitov/zabbix-php-fpm/raw/master/media/demo-process.png)

Displays the following data:

- Active processes
- Idle processes
- Accepted connections per second

#### Queue
Displays the following data:

- Listen Queue

#### Max Children Reached
Displays the following data:

- Max Children Reached
- Accepted connections per second
    
## Installation

### 1. On Zabbix agents
Perform the following operations on all servers with Zabbix and PHP-FPM from which you want to capture the data.

#### 1.1. Install Prerequisites
Install required packages:

```bash
apt-get update
apt-get -y install grep gawk lsof jq libfcgi0ldbl
```

#### 1.2. Install Zabbix PHP-FPM template
Download the latest version of the template:

```console
wget https://github.com/rvalitov/zabbix-php-fpm/archive/master.zip /tmp/zabbix-php-fpm.zip
``` 

Unzip the archive:

```console
unzip /tmp/zabbix-php-fpm.zip
```

Copy the required files to the Zabbix agent configuration directory:

```console
cp /tmp/zabbix-php-fpm/zabbix/userparameter_php_fpm.conf /etc/zabbix/zabbix_agentd.conf/
cp /tmp/zabbix-php-fpm/zabbix/zabbix_php_fpm_discovery.sh /etc/zabbix/
cp /tmp/zabbix-php-fpm/zabbix/zabbix_php_fpm_status.sh /etc/zabbix/
```

Configure access rights:

```console
chmod +x /etc/zabbix/zabbix_php_fpm_discovery.sh
chmod +x /etc/zabbix/zabbix_php_fpm_status.sh
```

#### 1.3. Allow root for Zabbix Agent
Automatic detection of sockets used by pools requires root previliges. Edit Zabbix agent configuration file `/etc/zabbix/zabbix_agentd.conf`, find `AllowRoot` option and enable it:

```
### Option: AllowRoot
#       Allow the agent to run as 'root'. If disabled and the agent is started by 'root', the agent
#       will try to switch to the user specified by the User configuration option instead.
#       Has no effect if started under a regular user.
#       0 - do not allow
#       1 - allow
#
# Mandatory: no
# Default:
# AllowRoot=0
AllowRoot=1
```  

#### 1.4. Linux Tuning (optional)
Usually PHP-FPM [backlog option](https://www.php.net/manual/en/install.fpm.configuration.php#listen-backlog) is limited by Linux kernel settings and equals to `128` by default.
In most cases you want to increase this value (latest PHP use `511` by default).
The main option that limits the PHP-FPM backlog option is `net.core.somaxconn`.
See the current setting, usually it's `128`:

```console
cat /proc/sys/net/core/somaxconn
128
```

Let's increase it to 1024:

```console
echo "net.core.somaxconn=1024" >> /etc/sysctl.conf
```

Now we can cause the settings to be loaded by running:

```console
sysctl -p
```

#### 1.5. Adjust ISPConfig
This step is required only if you use [ISPConfig](https://www.ispconfig.org/).
ISPConfig does not enable PHP-FPM status page by default. 
We will enable it by adding a custom PHP-FPM configuration template.
This file is an original configuration file from [ISPConfig v.3.1.14p2](https://www.ispconfig.org/blog/ispconfig-3-1-14p2-released-important-security-bugfix/), it only enables the status page by adding the following line:

```
pm.status_path = /php-fpm-status
```
Copy the configuration file into ISPConfig custom configuration directory:

```console
cp /tmp/zabbix-php-fpm/ispconfig/php_fpm_pool.conf.master /usr/local/ispconfig/server/conf-custom/
```

Set correct access rights:

```console
chmod +x /usr/local/ispconfig/server/conf-custom/php_fpm_pool.conf.master
```

Now resync the websites using ISPConfig control panel: go to `"Tools"->"Sync Tools"->"Resync"`.
Check "Websites" only and click "Start":

![ISPConfig resync interface](https://github.com/rvalitov/zabbix-php-fpm/raw/master/media/ispconfig-resync.jpg)

### 1.6 Adjust PHP-FPM pools configuration
This step is required if you don't use ISPConfig.
In this case you need to enable the PHP-FPM status page for all of your pools manually.
Each pool must have the same status path, recommended value is `/php-fpm-status`.
Please, edit all the pools configuration files (for example for PHP 7.3 they are located in directory `/etc/php/7.3/fpm/pool.d`) by adding the following line:

```
pm.status_path = /php-fpm-status
```

You can set another path here if needed. Finally, restart the PHP-FPM, for example:

```console
service php7.3-fpm restart
```

#### 1.7. Clean up
Delete temporary files:

```console
rm /tmp/zabbix-php-fpm.zip
rm -rf /tmp/zabbix-php-fpm/
```

### 2. On Zabbix Server
#### 2.1. Import Zabbix PHP-FPM template
In Zabbix frontend go to `"Configuration"->"Templates"->"Import"`:
![Zabbix template import interface](https://github.com/rvalitov/zabbix-php-fpm/raw/master/media/zabbix-import.jpg)

Upload file `/zabbix/zabbix_php_fpm_template.xml` from the [archive](https://github.com/rvalitov/zabbix-php-fpm/archive/master.zip).

#### 2.2. Add the template to your hosts
Add template "Template App PHP-FPM" to the desired hosts.
If you use a custom status path, then configure it in the macros section of the host by adding value:

```
{$PHP_FPM_STATUS_URL}=your status path
```

The setup is finished, just wait a couple of minutes till Zabbix discovers all your pools and captures the data.

# Compatibility
Tested with:
- PHP 7.3
- Zabbix 4.2.5
- ISPConfig v.3.1.14p2

Should work with PHP 5.6.x and later, Zabbix 4.x. Not tested with Zabbix 3.x and earlier: if it works, please let me know. 