#! /bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

function init_freeradius() {
    install_freeradius
    
    install_daloradius
    config_boot
}

function install_freeradius() {
    apt-add-repository ppa:freeradius/stable-3.0
    apt-get update
    apt-get install -y freeradius freeradius-mysql freeradius-rest mariadb-server
    sed -i 's/force-reload/restart/g' /var/lib/dpkg/info/freeradius-mysql.postinst
    sed -i 's/force-reload/restart/g' /var/lib/dpkg/info/freeradius-rest.postinst
    dpkg --configure -a
}

function install_daloradius() {
    apt-get install unzip apache2 php-common php-gd php-curl php-mail php-mail-mime \
        php-pear php-db php-mysql
    wget https://github.com/lirantal/daloradius/archive/master.zip -O daloradius-master.zip
    unzip daloradius-master.zip
    mv daloradius-master /var/www/html/daloradius
    chmod 664 /var/www/html/daloradius/library/daloradius.conf.php
    cd /var/www/html/daloradius/
    mysql -u radius -p radius < contrib/db/fr2-mysql-daloradius-and-freeradius.sql
    mysql -u radius -p radius < contrib/db/mysql-daloradius.sql
}

function config_boot() {
    cat > /etc/init.d/radius_setup<<EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:          radius_setup
# Required-Start:    \$local_fs \$remote_fs \$network \$syslog
# Required-Stop:     \$local_fs \$remote_fs \$network \$syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: starts the freeradius daemon
# Description:       starts freeradius using start-stop-daemon
### END INIT INFO

systemctl start freeradius.service

EOF
    chmod +x /etc/init.d/radius_setup
    update-rc.d radius_setup defaults 101
}