#! /bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

function init_strongswan() {
    load_env
    get_ip
    install_strongswan
    backup_config
    copy_certificate
    config_ipsec
    config_strongswan
    config_radius
    config_secrets
    config_iptables
    config_boot
}

function load_env() {
    vpn_env="./ipsec.env"
    if [ -f "${vpn_env}" ]; then
        . "$vpn_env"
    else
        echo "VPN environment variables not found."
        return 1;
    fi
}

function get_ip() {
    IP=`wget -qO- icanhazip.com`
    if [ -z ${IP} ]; then
        IP=`wget -qO- ifconfig.me`
    fi
}

function install_strongswan() {
    wget http://download.strongswan.org/strongswan-5.6.3.tar.gz -O strongswan.tar.gz
    tar zxvf strongswan.tar.gz
    cd strongswan-5.6.3
    ./configure --prefix=/usr --sysconfdir=/etc/strongswan --enable-eap-identity \
        --enable-eap-md5 --enable-eap-mschapv2 --enable-eap-tls --enable-eap-ttls \
        --enable-eap-peap --enable-eap-tnc --enable-eap-dynamic --enable-eap-radius \
        --enable-xauth-eap --enable-xauth-pam  --enable-dhcp  --enable-openssl \
        --enable-addrblock --enable-unity --enable-certexpire --enable-radattr \
        --enable-swanctl --enable-openssl --disable-gmp
    make
    make install
}

function backup_config() {
    cp /etc/strongswan/ipsec.conf /etc/strongswan/ipsec.conf.backup
    cp /etc/strongswan/ipsec.secrets /etc/strongswan/ipsec.secrets.backup
    cp /etc/strongswan/strongswan.conf /etc/strongswan/strongswan.conf.backup
    cp /etc/strongswan/strongswan.d/charon/eap-radius.conf /etc/strongswan/strongswan.d/charon/eap-radius.conf.backup
    cp /etc/strongswan/strongswan.d/charon/xauth-eap.conf /etc/strongswan/strongswan.d/charon/xauth-eap.conf.backup
}

function copy_certificate() {
    wget https://get.acme.sh -O acme.sh
    acme.sh --issue -d ${DOMAIN} --apache
    acme.sh --installcert -d ${DOMAIN} \
        --key-file /etc/strongswan/ipsec.d/private/server.pem \
        --fullchain-file /etc/strongswan/ipsec.d/certs/server.cert.pem \
        --reloadcmd "ipsec restart"
    acme.sh --installcert -d ${DOMAIN} \
        --key-file /etc/strongswan/ipsec.d/private/client.pem \
        --fullchain-file /etc/strongswan/ipsec.d/certs/client.cert.pem \
        --reloadcmd "ipsec restart"
}

function config_ipsec() {
    cat > /etc/strongswan/ipsec.conf <<EOF
config setup
    strictcrlpolicy=yes
    uniqueids = no

conn %default
    ikelifetime = 60m
    keylife = 20m
    rekeymargin = 3m
    rekey = no
    keyingtries = 1
    keyexchange = ike
    leftsubnet = 0.0.0.0/0
    right = %any
    dpdaction = clear
    dpddelay = 300s
    dpdtimeout = 1h

conn Windows7-OSX
    keyexchange = ikev2
    esp = aes256-sha256,aes256-sha1,3des-sha1!
    ike = aes256-sha1-modp1024,aes128-sha1-modp1024,3des-sha1-modp1024!
    leftauth = pubkey
    leftcert = server.cert.pem
    rightsourceip = ${RIGHT_SOURCE_IP}/24
    rightauth = eap-radius
    rightsendcert = never
    eap_identity = %identity
    compress = yes
    auto = add

conn iOS_OSX
    keyexchange = ikev2
    ike = aes256-sha256-modp2048,3des-sha1-modp2048!
    esp = aes256-sha256,3des-sha1!
    rekey = no
    left = %defaultroute
    leftid = ${DOMAIN}
    leftsendcert = always
    leftsubnet = 0.0.0.0/0
    leftcert = server.cert.pem
    right = %any
    rightauth = eap-radius
    rightsourceip = ${RIGHT_SOURCE_IP}/24
    rightsendcert = never
    eap_identity = %any
    dpdaction = clear
    fragmentation = yes
    auto = add

conn Android_XAuth_PSK
    keyexchange = ikev1
    left = %defaultroute
    leftauth = psk
    leftsubnet = 0.0.0.0/0
    right = %any
    rightauth = psk
    rightauth2 = xauth
    rightsourceip = ${RIGHT_SOURCE_IP}/24
    auto = add

conn Cisco_IPSec
    keyexchange = ikev1
    aggressive = yes
    compress = yes
    ike = aes256-sha1-modp1024!
    esp = aes256-sha1!
    dpdaction = clear
    leftid = %defaultroute
    type = tunnel
    xauth = server
    leftauth = psk
    leftfirewall = yes
    rightauth = psk
    rightauth2 = xauth-eap
    rightsourceip = ${RIGHT_SOURCE_IP}/24
    auto = add

EOF
}

function config_strongswan() {
    cat > /etc/strongswan.conf <<EOF
charon {
    load_modular = yes
    duplicheck.enable = no
    compress = yes
    plugins {
        include strongswan.d/charon/*.conf
    }
    filelog {
        /var/log/charon.log {
            time_format = %b %e %T
            ike_name = yes
            append = no
            default = 2
            flush_line = yes
        }
        stderr {
            ike = 2
            knl = 3
        }
    }
    syslog {
        identifier = charon-custom
        daemon {
        }
        auth {
            default = -1
            ike = 0
        }
    }
    dns1 = 114.114.114.114
    dns2 = 8.8.8.8
}
include strongswan.d/*.conf

EOF
}

function config_radius() {
    cat > /etc/strongswan/strongswan.d/charon/eap-radius.conf <<EOF
eap-radius {

    accounting = yes
    load = yes

    dae {
    }

    forward {
    }

    servers {
	    primary {
		    secret = ${RADIUS_SECRET}
		    address = ${RADIUS_ADDRESS}
	    }
    }

    xauth {

    }
}

EOF

    cat > /etc/strongswan/strongswan.d/charon/xauth-eap.conf <<EOF
xauth-eap {

    backend = radius

    load = yes
}

EOF
}

function config_secrets() {
    cat > /etc/ipsec.secrets <<EOF
: RSA server.pem
: PSK ${PSK_SECRET}
: XAUTH ${XAUTH_SECRET}
${EAP_ACCOUNT} %any : EAP ${EAP_SECRET}

EOF
}

function config_iptables() {

    iptables -F
    iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -i ppp+ -m state --state NEW,RELATED,ESTABLISHED -j ACCEPT

    iptables -A FORWARD -d ${RIGHT_SOURCE_IP}/24  -j ACCEPT
    iptables -A FORWARD -s ${RIGHT_SOURCE_IP}/24  -j ACCEPT

    iptables -A INPUT -i ${NETWORK_INTERFACE} -p esp -j ACCEPT
    iptables -A INPUT -i ${NETWORK_INTERFACE} -p tcp --dport 500 -j ACCEPT
    iptables -A INPUT -i ${NETWORK_INTERFACE} -p udp --dport 4500 -j ACCEPT
    iptables -A INPUT -i ${NETWORK_INTERFACE} -p tcp --dport 1723 -j ACCEPT
    iptables -A INPUT -i ${NETWORK_INTERFACE} -p udp --dport 1701 -j ACCEPT

    iptables -t nat -A POSTROUTING -s ${RIGHT_SOURCE_IP}/24 -o ${NETWORK_INTERFACE} -j MASQUERADE

    # 如果使用 SNAT,可以使用下面的代码
    # iptables -t nat -A POSTROUTING -s ${RIGHT_SOURCE_IP}/24 -o ${NETWORK_INTERFACE} -j SNAT --to-source ${IP}

    iptables-save > /etc/iptables.rules
    cat > /etc/network/if-up.d/iptables<<EOF
#!/bin/sh
iptables-restore < /etc/iptables.rules

EOF
    chmod +x /etc/network/if-up.d/iptables
}

function config_boot() {
    cat > /etc/profile.d/ipsec_auto_start.sh<<EOF
#!/bin/sh
cp /root/.acme.sh/zoonode.com/ca.cer /etc/strongswan/ipsec.d/cacerts/
ipsec start

EOF
    chmod +x /etc/profile.d/ipsec_auto_start.sh
}

init_strongswan
