#! /bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

function init_freeradius() {
    install_freeradius
    
    install_daloradius
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
