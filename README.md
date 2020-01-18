# PHP-FPM Zabbix Template with Auto Discovery and Multiple Pools

![Zabbix versions](https://img.shields.io/badge/Zabbix_versions-4.4,_4.2,_4.0-green.svg?style=flat) ![PHP](https://img.shields.io/badge/PHP-5.3.3+-blue.svg?style=flat) ![PHP7](https://img.shields.io/badge/PHP7-supported-green.svg?style=flat) ![LLD](https://img.shields.io/badge/LLD-yes-green.svg?style=flat) ![ISPConfig](https://img.shields.io/badge/ISPConfig-supported-green.svg?style=flat)

![Banner](https://github.com/rvalitov/zabbix-php-fpm/raw/master/media/repository-open-graph-template.png)

## Main features

- Provides auto discovery of PHP-FPM pools (LLD)
- Detects pools that [listen](https://www.php.net/manual/en/install.fpm.configuration.php#listen) via socket and via TCP
- Supported types of PHP [process manager](https://www.php.net/manual/en/install.fpm.configuration.php#pm):
	- [x] dynamic
	- [x] static
	- [x] ondemand. Such pools are invisible (undiscoverable) if they are not active because of their nature, i.e. when no PHP-FPM processes related to the pools spawned during the discovery process of Zabbix agent. After a pool has been discovered for the first time, it becomes permanently visible for Zabbix. Regular checks performed by Zabbix agent require at least one active PHP-FPM process that can report the status, and if such process does not exist, then it will be spawned. As a result, Zabbix agent will always report that there's at least one active PHP-FPM process for the pool. Besides, there's a chance that such behaviour may have a negative impact on the pool's performance and you may consider changing to another type of process manager, for example, dynamic.   
- Supports multiple PHP versions, i.e. you can use PHP 7.2 and PHP 7.3 on the same server and we will detect them all
- Easy configuration
- Supports [ISPConfig](https://www.ispconfig.org/)
- Script is in pure `bash`: no need to install `Perl`, `Go` or other languages. 

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
    - **Listen Queue Length** - the size of the socket queue of pending connections. This value is defined by the [backlog](https://www.php.net/manual/en/install.fpm.configuration.php#listen-backlog) option in your pool's configuration. On Debian the length is always reported zero for pools that listen via socket.
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

|Title|Severity|Description|
|-----|--------|-----------|
|Too many connections on pool|High|It means this pool is under high load. Please, make sure that your website is reachable and works as expected. For high load websites with huge amount of traffic please manually adjust this trigger to higher values (default is 500 concurrent connections). For websites with low or standard amount of visitors you may be under DDoS attack. Anyway, please, check the status of your server (CPU, memory utilization) to make sure that your server can handle this traffic and does not have performance issues.|
|PHP-FPM uses too much memory|Average|Please, make sure that your server has sufficient resources to handle this pool, and check that the traffic of your website is not abnormal (check that your website is not under DDoS attack).|
|PHP-FPM uses queue|Warning|The current number of connections that have been initiated on pool, but not yet accepted are greater than zero. It typically means that all the available server processes are currently busy, and there are no processes available to serve the next request. Raising pm.max_children (provided the server can handle it) should help keep this number low. This trigger follows from the fact that PHP-FPM listens via a socket (TCP or file based), and thus inherits some of the characteristics of sockets. Low values of the listen queue generally result in performance issues of this pool. High values may lead to severe errors when requests can't be processed and will be rejected generating errors such as HTTP 500. You need to set the [backlog](https://www.php.net/manual/en/install.fpm.configuration.php#listen-backlog) option in your pool's configuration if you want to use this trigger. Otherwise the trigger will never be fired. Don't trust the default value of the `backlog` option - it may differ from what you expect and set your max queue length to zero.|
|PHP-FPM detected slow request|Warning|PHP-FPM detected slow request on pool. A slow request means that it took more time to execute than expected (defined in the configuration of your pool). It means that your pool has performance issues: either it is under high load, your pool has non-optimal configuration, your server has insufficient resources, or your PHP scripts have slow code (have bugs or bad programming style). You need to set [request_slowlog_timeout](https://www.php.net/manual/en/install.fpm.configuration.php#request-slowlog-timeout) and [slowlog](https://www.php.net/manual/en/install.fpm.configuration.php#slowlog) options in your pool's configuration if you want to use this trigger. Otherwise the trigger will never be fired.|
|PHP-FPM manager changed|Information|The [process manager](https://www.php.net/manual/en/install.fpm.configuration.php#pm) of PHP-FPM for this pool has changed.|

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

## Provided Screens
Screens are based on the graphs above:

- Connections
- Processes
- CPU utilization
- Memory utilization
- Queue
- Max children riched

![Zabbix screens example](https://github.com/rvalitov/zabbix-php-fpm/raw/master/media/zabbix-screens.jpg)

## Installation

### 1. On Zabbix agents
Perform the following operations on all servers with Zabbix and PHP-FPM from which you want to capture the data.

#### 1.1. Install Prerequisites
Install required packages.

##### For `apt-get` based environments (Debian, Ubuntu, etc.):

```bash
apt-get update
apt-get -y install grep gawk lsof jq libfcgi0ldbl
```
Additionally, for Debian Jessie 8.x and earlier (or for equivalent Ubuntu version):

```bash
apt-get -y install libfcgi0ldbl
```

Additionally, for Debian Stretch 9.x and later (or for equivalent Ubuntu version):

```bash
apt-get -y install libfcgi-bin
```

##### For `yum` based environments (CentOS):

```bash
yum check-update
yum install grep gawk lsof jq fcgi
```

#### 1.2. Install Zabbix PHP-FPM template
First, please, download the template archive: you can use either the [latest published release](https://github.com/rvalitov/zabbix-php-fpm/releases/latest) (the latest stable version, I hope :sweat_smile:) or use the active development version (that contains all the latest features and updates).
Below we will download the archive to a temporary directory `/tmp` that usually presents in all OS. 
If you don't have such directory, please, create it first. 

##### 1.2.1. To use stable release
To download a stable release, run command:

```console
curl -L $(curl -s https://api.github.com/repos/rvalitov/zabbix-php-fpm/releases/latest | grep 'zipball_' | cut -d\" -f4) --output /tmp/zabbix-php-fpm.zip
```

##### 1.2.2. To use development version

To download a developement version, run command:

```console
wget https://github.com/rvalitov/zabbix-php-fpm/archive/master.zip -O /tmp/zabbix-php-fpm.zip
```
##### 1.2.3. Unzip and configure
 
Unzip the downloaded archive:

```console
unzip -j /tmp/zabbix-php-fpm.zip "*/zabbix/*" "*/ispconfig/*" -d /tmp/zabbix-php-fpm
```

Copy the required files to the Zabbix agent configuration directory:

```console
cp /tmp/zabbix-php-fpm/userparameter_php_fpm.conf /etc/zabbix/zabbix_agentd.d/
cp /tmp/zabbix-php-fpm/zabbix_php_fpm_discovery.sh /etc/zabbix/
cp /tmp/zabbix-php-fpm/zabbix_php_fpm_status.sh /etc/zabbix/
```

Configure access rights:

```console
chmod +x /etc/zabbix/zabbix_php_fpm_discovery.sh
chmod +x /etc/zabbix/zabbix_php_fpm_status.sh
```

#### 1.3. Root privileges
Automatic detection of pools requires root privileges. You can achieve it using one of the methods below.

##### 1.3.1. Method #1. Root privileges for Zabbix Agent
This method sets root privileges for Zabbix Agent, i.e. the Zabbix Agent will run under `root` user, as a result all user scripts will also have the root access rights. 

Edit Zabbix agent configuration file `/etc/zabbix/zabbix_agentd.conf`, find `AllowRoot` option and enable it:

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

In the same file find option `User` and set it to `root`:


```
### Option: User
#       Drop privileges to a specific, existing user on the system.
#       Only has effect if run as 'root' and AllowRoot is disabled.
#
# Mandatory: no
# Default:
# User=zabbix
User=root
```

Restart the Zabbix agent service, for example:

```console
systemctl restart zabbix-agent
```

Check that the Zabbix agent runs under `root` user:

```console
user@server:~$ ps aux | grep "zabbix_agent"
user       3761  0.0  0.0   8132   928 pts/0    S+   18:32   0:00 grep zabbix_agent
root      6026  0.0  0.0  86968  3472 ?        S    Dec14   0:00 /usr/sbin/zabbix_agentd -c /etc/zabbix/zabbix_agentd.conf
root      6027  0.7  0.0  87056  5044 ?        S    Dec14  76:00 /usr/sbin/zabbix_agentd: collector [idle 1 sec]
root      6028  0.0  0.0 161160 11092 ?        S    Dec14   7:41 /usr/sbin/zabbix_agentd: listener #1 [waiting for connection]
root      6029  0.0  0.0 161244 11180 ?        S    Dec14   7:43 /usr/sbin/zabbix_agentd: listener #2 [waiting for connection]
root      6030  0.0  0.0 161136 11072 ?        S    Dec14   7:43 /usr/sbin/zabbix_agentd: listener #3 [waiting for connection]
```

You should see `root` above. Otherwise, the Zabbix agent works without `root` privileges and will not be able to discover the PHP pools.

Since some updates of Zabbix agent and in some OS the above changes are not enough and the following actions must be performed (as desribed in Zabbix manual for versions [4.0](https://www.zabbix.com/documentation/4.0/manual/appendix/install/run_agent_as_root), [4.4](https://www.zabbix.com/documentation/4.4/manual/appendix/install/run_agent_as_root)). 

Create a directory for configuration file:

```console
mkdir /etc/systemd/system/zabbix-agent.service.d

```

Create file `/etc/systemd/system/zabbix-agent.service.d/override.conf` with the following content:

```console
[Service]
User=root
Group=root
```

Reload daemons and restart `zabbix-agent` service:

```console
systemctl daemon-reload
systemctl restart zabbix-agent
```

Check again that the Zabbix agent runs as `root` now.

##### 1.3.2. Method #2. Grant privileges to the PHP-FPM auto discovery script only
If you don't want to run Zabbix Agent as root, then you can configure the privileges only to our script. In this case you need to have `sudo` installed:

```console
apt-get install sudo
```

Now edit the `/etc/sudoers` file by running command:

```console
visudo
```

Add the following line to this file:

```
zabbix ALL = NOPASSWD: /etc/zabbix/zabbix_php_fpm_discovery.sh
```

Here we specified `zabbix` as the user under which the Zabbix Agent is run. This is the default name, but if you have a custom installation with different name, then please, change it accordingly. Save and exit the editor. Your modifications will be applied.

Now edit the file `userparameter_php_fpm.conf`. Find the line:

```
UserParameter=php-fpm.discover[*],/etc/zabbix/zabbix_php_fpm_discovery.sh $1
```

Add `sudo` there, so the line should be:

```
UserParameter=php-fpm.discover[*],sudo /etc/zabbix/zabbix_php_fpm_discovery.sh $1
```

That's all. 

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
We will enable it by making an override of original template of ISPConfig and add a custom directive there.
Please, check the installation path of ISPConfig in your system.
Below we use default paths as used in Debian 9/10.
Please, use one of the methods below to adjust the settings of ISPConfig.

**Note**: every time you upgrade the ISPConfig you may want to perform the operations below again to use the latest PHP-FPM template shipped with ISPConfig.

##### 1.5.1. Method #1. Apply a patch
**Caution**: don't use this method if you already have your own customizations of the PHP-FPM template in ISPConfig. 

Apply the patch using the following command:

```console
patch /usr/local/ispconfig/server/conf/php_fpm_pool.conf.master --input=/tmp/zabbix-php-fpm/ispconfig.patch --output=/usr/local/ispconfig/server/conf-custom/php_fpm_pool.conf.master --reject-file=-
```

##### 1.5.2. Method #2. Manually adjust the template
Use this method if any of the statements below are true:
- the patch above does not work
- you already have your own customizations of the PHP-FPM template in ISPConfig
- you prefer to have a full control of what happens on your server.

First we need to copy the original template file `php_fpm_pool.conf.master` of ISPConfig to the override directory (don't do that if you already have your own customizations of the PHP-FPM template in ISPConfig - in this case you should already have the required file in the required location):

```console
cp /usr/local/ispconfig/server/conf/php_fpm_pool.conf.master /usr/local/ispconfig/server/conf-custom/
```

Edit the copied file `/usr/local/ispconfig/server/conf-custom/php_fpm_pool.conf.master` and add there the following line after the last `pm` setting:

```
pm.status_path = /php-fpm-status
```

In our version of ISPConfig the last `pm` setting is `pm.max_requests`, so the resulting part of the file will have the following contents (the new line is bold):

<pre>
&lt;tmpl_if name='pm' op='==' value='ondemand'&gt;
pm.process_idle_timeout = &lt;tmpl_var name='pm_process_idle_timeout'&gt;s;
&lt;/tmpl_if>
pm.max_requests = &lt;tmpl_var name='pm_max_requests'&gt;
<b>pm.status_path = /php-fpm-status</b>

chdir = /
&lt;tmpl_if name='php_fpm_chroot'&gt;
</pre>

##### 1.5.3. Final adjustments for ISPConfig

Set correct access rights:

```console
chmod +x /usr/local/ispconfig/server/conf-custom/php_fpm_pool.conf.master
```

Now resync the websites using ISPConfig control panel: go to `"Tools"->"Sync Tools"->"Resync"`.
Check "Websites" only and click "Start":

![ISPConfig resync interface](https://github.com/rvalitov/zabbix-php-fpm/raw/master/media/ispconfig-resync.jpg)

### 1.6. Adjust PHP-FPM pools configuration
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
Download this project's archive to your computer (the release must be the same you selected when installing template archive at Zabbix agent):

- To use a stable release, open the [latest release page](https://github.com/rvalitov/zabbix-php-fpm/releases/latest) and click on "Source code (zip)" button at the end of the page.
- To use a developement version, download [this archive](https://github.com/rvalitov/zabbix-php-fpm/archive/master.zip).

Extract the XML template file from the archive that corresponds to your version of Zabbix server.
For example, use file `/zabbix/zabbix_php_fpm_template_4.0.xml` for Zabbix server 4.0. If there's no version of the template that matches your version of Zabbix server, then try to use the nearest version of the template that is not higher than your version of Zabbix server.
For example, template version 4.0 also works for higher versions of Zabbix server, such as 4.2 and 4.4. But template version 4.0 will not work for Zabbix 3.x.
Upload the extracted file to your Zabbix server. To do so go to `"Configuration"->"Templates"->"Import"` in Zabbix frontend:
![Zabbix template import interface](https://github.com/rvalitov/zabbix-php-fpm/raw/master/media/zabbix-import.jpg)

#### 2.2. Add the template to your hosts
Add template "Template App PHP-FPM" to the desired hosts.
If you use a custom status path (the default is `/php-fpm-status`), then configure it in the macros section of the host by adding value:

```
{$PHP_FPM_STATUS_URL}=your status path
```

The setup is finished, just wait a couple of minutes till Zabbix discovers all your pools and captures the data.

# Testing and Troubleshooting
## Check auto discovery
First test that auto discovery of PHP-FPM pools works on your machine. Run the following command (replace `POOL_PATH` with the status path of PHP-FPM that you set in [`pm.status_path`](https://github.com/rvalitov/zabbix-php-fpm#16-adjust-php-fpm-pools-configuration), the default value is `/php-fpm-status`):

```console
root@server:/etc/zabbix#bash /etc/zabbix/zabbix_php_fpm_discovery.sh POOL_PATH
```
**Important:** please make sure that you use `bash` in the command above, not `sh` or other alternatives, otherwise you may get a script syntax error message.

The output should be a valid JSON with a list of pools and their sockets, something like below (you may want to use [online JSON tool](https://jsonformatter.curiousconcept.com/) for pretty formatting of the response):

```json
{
   "data":[
      {
         "{#POOLNAME}":"web1",
         "{#POOLSOCKET}":"/var/lib/php7.3-fpm/web1.sock"
      },
      {
         "{#POOLNAME}":"web4",
         "{#POOLSOCKET}":"/var/lib/php7.3-fpm/web4.sock"
      },
      {
         "{#POOLNAME}":"www",
         "{#POOLSOCKET}":"127.0.0.1:9000"
      }
   ]
}
```

For further investigation you can run the script above with `debug` option to get more details, example:
```console
root@server:/etc/zabbix#bash /etc/zabbix/zabbix_php_fpm_discovery.sh POOL_PATH debug
Debug mode enabled
Success: found socket /var/lib/php7.3-fpm/web1.sock for pool web1, raw process info: php-fpm7. 5094 web1 11u unix 0x00000000dd9ea858 0t0 104495372 /var/lib/php7.3-fpm/web1.sock type=STREAM
Success: found socket /var/lib/php7.3-fpm/web4.sock for pool web4, raw process info: php-fpm7. 5096 web4 11u unix 0x00000000562748dd 0t0 104495374 /var/lib/php7.3-fpm/web4.sock type=STREAM
Success: found socket /run/php/php7.3-fpm.sock for pool www, raw process info: php-fpm7. 5098 www-data 11u unix 0x00000000ef5ef2fb 0t0 104495376 /run/php/php7.3-fpm.sock type=STREAM
Resulting JSON data for Zabbix:
{"data":[{"{#POOLNAME}":"web1","{#POOLSOCKET}":"/var/lib/php7.3-fpm/web1.sock"},{"{#POOLNAME}":"web4","{#POOLSOCKET}":"/var/lib/php7.3-fpm/web4.sock"},{"{#POOLNAME}":"www","{#POOLSOCKET}":"/run/php/php7.3-fpm.sock"}]}
```

Any warning or error messages will be displayed here. 

**Note:** having a warning messages does not necessarily mean that you have a error here, because different OS may provide data about processes differently. So, if you don't see any error messages here, then the script works fine.

The script can show you the list of utilities that are missing on your system and must be installed. We require the following utilities to be installed:

- `awk`
- `ps`
- `grep`
- `sort`
- `head`
- `lsof`
- `jq`   

If some pools are missing, then you can manually check that they do really exist and are running, for example, using command:

```console
ps aux | grep "php-fpm"
```

In the list you should see your pool. If it's not there, then it means it's not running (not functional).

## How to troubleshoot template import failure
To view the import errors, please click the "Details" section in the Zabbix GUI. It should be on the same import page near the error message:

![Zabbix template import error details](https://github.com/rvalitov/zabbix-php-fpm/raw/master/media/zabbix-import-error.jpg)

Then check the Zabbix server log, for Debian/Ubuntu it's located at `/var/log/zabbix/zabbix_server.log`.

## Test with `zabbix_get`
Please, use the [`zabbix_get`](https://www.zabbix.com/documentation/4.4/manual/concepts/get) utility from your Zabbix Server to test that you can get the data from the Zabbix Agent (host).

### Installation
Please, install this utility first, because usually it's not installed automatically:

```console
apt-get install zabbix-get
```

### Command examples
In the examples below we use the following parameter names:

- `ZABBIX_HOST_IP` is the IP address of the host where the Zabbix Agent is installed and where the PHP-FPM is running, for example `127.0.0.1`
- `ZABBIX_HOST_PORT` is the port of the Zabbix Agent, for example `10050`
- `POOL_URL` is the socket of the pool or IP and port combination, example: `/var/lib/php7.3-fpm/web1.sock` or `127.0.0.1:9000`
- `POOL_PATH` is the status path of PHP-FPM that you set in [`pm.status_path`](https://github.com/rvalitov/zabbix-php-fpm#16-adjust-php-fpm-pools-configuration), the default value is `/php-fpm-status`.

All commands should return valid JSON data. If any error happens then it will be displayed.

#### 1. Discover PHP-FPM pools
Command syntax:

```
zabbix_get -s ZABBIX_HOST_IP -p ZABBIX_HOST_PORT -k php-fpm.discover["POOL_URL"]
```

Command output example:
```console
root@server:/# zabbix_get -s 127.0.0.1 -p 10050 -k php-fpm.discover["/php-fpm-status"]
{"data":[{"{#POOLNAME}":"www","{#POOLSOCKET}":"/run/php/php7.3-fpm.sock"},{"{#POOLNAME}":"www2","{#POOLSOCKET}":"localhost:9001"}]}
```

Most common problems of testing the `php-fpm.discover` key:

- The resulting JSON data is empty, but the discovery script started manually works. Then it's a problem of insufficient privileges of Zabbix agent. Please, check again section "Root privileges" of this document.
- Error `ZBX_NOTSUPPORTED: Unsupported item key`. It means the `userparameter_php_fpm.conf` file is ignored by the Zabbix agent. Please, make sure that you copied this file to correct location and you have restarted the Zabbix agent.
- Error `php_fpm.cache: Permission denied` means that the script has insufficient permissions. Please, check that you granted privileges to the PHP-FPM auto discovery script or run Zabbix agent as root user. Please, check again section "Root privileges" of this document.
- Message `Error: write permission is not granted to user USER for cache file php_fpm.cache` means that the user of Zabbix agent does not have required privileges. Please, check that you granted privileges to the PHP-FPM auto discovery script or run Zabbix agent as root user. Please, check again section "Root privileges" of this document. You may need to manually delete the `php_fpm.cache` after granting the privileges. 

#### 2. Get status of required pool
Command syntax:

```console
zabbix_get -s ZABBIX_HOST_IP -p ZABBIX_HOST_PORT -k php-fpm.discover.status["POOL_URL","POOL_PATH"]
```

Command output example:

```console
root@server:/# zabbix_get -s 127.0.0.1 -p 10050 -k php-fpm.status["localhost:9001","/php-fpm-status"]
{"pool":"www2","process manager":"static","start time":1578093850,"start since":149,"accepted conn":3,"listen queue":0,"max listen queue":0,"listen queue len":511,"idle processes":4,"active processes":1,"total processes":5,"max active processes":1,"max children reached":0,"slow requests":0}
```

# Compatibility
Should work with any version of PHP-FPM (starting with PHP 5.3.3), Zabbix 4.0.x and later.
Can work with any version of ISPConfig as long as you have a valid PHP-FPM status page configuration there.

Tested with:
- PHP 7.3
- Zabbix 4.0.16, 4.2.5, 4.4.4
- ISPConfig v.3.1.14p2