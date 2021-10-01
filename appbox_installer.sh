#!/usr/bin/env bash
# Appbox installer for Ubuntu 20.04
#
# Just run this on your Ubuntu VNC app via SSH or in the terminal (Applications > Terminal Emulator) using:
# sudo bash -c "bash <(curl -Ls https://raw.githubusercontent.com/coder8338/appbox_installer/Ubuntu-20.04/appbox_installer.sh)"
#
# We do not work for appbox, we're a friendly community helping others out, we will try to keep this as uptodate as possible!

set -e
set -u

export DEBIAN_FRONTEND=noninteractive

run_as_root() {
    if ! whoami | grep -q 'root'; then
        echo "Please enter your user password, then run this script again!"
        sudo -s
        return 0
    fi
}

create_service() {
    NAME=$1
    mkdir -p /etc/services.d/${NAME}/log
    echo "3" > /etc/services.d/${NAME}/notification-fd
    cat << EOF > /etc/services.d/${NAME}/log/run
#!/bin/sh
exec logutil-service /var/log/appbox/${NAME}
EOF
    chmod +x /etc/services.d/${NAME}/log/run
    echo "${RUNNER}" > /etc/services.d/${NAME}/run
    chmod +x /etc/services.d/${NAME}/run
    cp -R /etc/services.d/${NAME} /var/run/s6/services
    kill -HUP 1
    s6-svc -u /run/s6/services/${NAME}
}

configure_nginx() {
    NAME=${1}
    PORT=${2}
    OPTION=${3:-default}
    if ! grep -q "/${NAME} {" /etc/nginx/sites-enabled/default; then
        sed -i '/server_name _/a \
        location /'${NAME}' {\
                proxy_pass http://127.0.0.1:'${PORT}';\
        }' /etc/nginx/sites-enabled/default

        if [ "${OPTION}" == 'subfilter' ]; then
            sed -i '/location \/'${NAME}' /a \
                sub_filter "http://"  "https://";\
                sub_filter_once off;' /etc/nginx/sites-enabled/default
        fi
    fi
    pkill -HUP nginx
    url_output "${NAME}"
}

url_output() {
    NAME=${1}
    APPBOX_USER=$(echo "${HOSTNAME}" | awk -F'.' '{print $2}')
    echo -e "\n\n\n\n\n
        Installation sucessful! Please point your browser to:
        \e[4mhttps://${HOSTNAME}/${NAME}\e[39m\e[0m
        
        You can continue the configuration from there.
        \e[96mMake sure you protect the app by setting up a username/password in the app's settings!\e[39m
        
        \e[91mIf you want to use another appbox app in the settings of ${NAME}, make sure you access it on port 80, and without https, for example:
        \e[4mhttp://rutorrent.${APPBOX_USER}.appboxes.co\e[39m\e[0m
        \e[95mIf you want to access Plex from one of these installed apps use port 32400 for example:
        \e[4mhttp://plex.${APPBOX_USER}.appboxes.co:32400\e[39m\e[0m
        
        That's because inside this container, we don't go through the appbox proxy! \n\n\n\n\n\n"
}

setup_radarr() {
    s6-svc -d /run/s6/services/radarr || true
    wget https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
    dpkg -i packages-microsoft-prod.deb
    rm -f packages-microsoft-prod.deb
    apt update
    apt -y install dotnet-runtime-3.1 libmediainfo0v5 || true
    cd /home/appbox/appbox_installer
    curl -L -O $( curl -s https://api.github.com/repos/Radarr/Radarr/releases | grep linux-core-x64.tar.gz | grep browser_download_url | head -1 | cut -d \" -f 4 )
    tar -xvzf Radarr.*.linux-core-x64.tar.gz
    rm -f Radarr.*.linux-core-x64.tar.gz
    chown -R appbox:appbox /home/appbox/appbox_installer/Radarr
    chown -R appbox:appbox /home/appbox/.config
    # Generate config
    /bin/su -s /bin/bash -c "/home/appbox/appbox_installer/Radarr/Radarr" appbox &
    until grep -q 'UrlBase' /home/appbox/.config/Radarr/config.xml; do
        sleep 1
    done
    pkill -f 'Radarr'
    sed -i 's@<UrlBase></UrlBase>@<UrlBase>/radarr</UrlBase>@g' /home/appbox/.config/Radarr/config.xml
    RUNNER=$(cat << EOF
#!/bin/execlineb -P

# Redirect stderr to stdout.
fdmove -c 2 1

s6-setuidgid appbox

foreground { rm /home/appbox/.config/Radarr/radarr.pid }
/home/appbox/appbox_installer/Radarr/Radarr
EOF
)
    create_service 'radarr'
    configure_nginx 'radarr' '7878'
}

setup_sonarr() {
    s6-svc -d /run/s6/services/sonarr || true
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 2009837CBFFD68F45BC180471F4F90DE2A9B4BF8
    echo "deb https://apt.sonarr.tv/ubuntu focal main" | tee /etc/apt/sources.list.d/sonarr.list
    apt update
    apt install -y debconf-utils
    echo "sonarr sonarr/owning_user string appbox" | debconf-set-selections
    echo "sonarr sonarr/owning_group string appbox" | debconf-set-selections
    apt -y install libmediainfo0v5 || true
    apt -y install sonarr || true
    # Generate config
    /bin/su -s /bin/bash -c "/usr/bin/mono --debug /usr/lib/sonarr/bin/Sonarr.exe -nobrowser" appbox &
    until grep -q 'UrlBase' /home/appbox/.config/Sonarr/config.xml; do
        sleep 1
    done
    sleep 5
    pkill -f 'Sonarr.exe'
    sed -i 's@<UrlBase></UrlBase>@<UrlBase>/sonarr</UrlBase>@g' /home/appbox/.config/Sonarr/config.xml
RUNNER=$(cat << EOF
#!/bin/execlineb -P

# Redirect stderr to stdout.
fdmove -c 2 1

s6-setuidgid appbox

foreground { rm /home/appbox/.config/Sonarr/sonarr.pid }
/usr/bin/mono --debug /usr/lib/sonarr/bin/Sonarr.exe -nobrowser
EOF
)
    create_service 'sonarr'
    configure_nginx 'sonarr' '8989'
}

setup_sickchill() {
    s6-svc -d /run/s6/services/sickchill || true
    apt install -y git unrar-free git openssl libssl-dev python mediainfo || true
    git clone --depth 1 https://github.com/SickChill/SickChill.git /home/appbox/appbox_installer/sickchill
    cp /home/appbox/appbox_installer/sickchill/contrib/runscripts/init.ubuntu /etc/init.d/sickchill
    chmod +x /etc/init.d/sickchill
    sed -i 's/--daemon//g' /etc/init.d/sickchill
    cat << EOF > /etc/default/sickchill
SR_HOME=/home/appbox/appbox_installer/sickchill/
SR_DATA=/home/appbox/appbox_installer/sickchill/
SR_USER=appbox
EOF
    cat << EOF >/home/appbox/appbox_installer/sickchill/config.ini
[General]
  web_host = 0.0.0.0
  handle_reverse_proxy = 1
  launch_browser = 0
  web_root = "/sickchill"
EOF
    RUNNER=$(cat << EOF
#!/bin/execlineb -P

# Redirect stderr to stdout.
fdmove -c 2 1

s6-setuidgid appbox

cd /home/appbox/appbox_installer/sickchill/
/usr/bin/python3 SickChill.py -q --nolaunch --pidfile=/var/run/sickchill/sickchill.pid --datadir=/home/appbox/appbox_installer/sickchill/
EOF
)
    chown -R appbox:appbox /home/appbox/appbox_installer/sickchill
    create_service 'sickchill'
    configure_nginx 'sickchill' '8081'
}

setup_jackett() {
    s6-svc -d /run/s6/services/jackett || true
    apt install -y libcurl4-openssl-dev bzip2
    cd /home/appbox/appbox_installer
    curl -L -O $( curl -s https://api.github.com/repos/Jackett/Jackett/releases/latest | grep LinuxAMDx64 | grep browser_download_url | head -1 | cut -d \" -f 4 )
    tar -xvzf Jackett.Binaries.LinuxAMDx64.tar.gz
    rm -f Jackett.Binaries.LinuxAMDx64.tar.gz
    chown -R appbox:appbox /home/appbox/appbox_installer/Jackett
    mkdir -p /home/appbox/.config/Jackett
    cat << EOF > /home/appbox/.config/Jackett/ServerConfig.json
{
  "Port": 9117,
  "AllowExternal": true,
  "BasePathOverride": "/jackett",
}
EOF
    chown -R appbox:appbox /home/appbox/.config/Jackett

    RUNNER=$(cat << EOF
#!/bin/execlineb -P

# Redirect stderr to stdout.
fdmove -c 2 1

s6-setuidgid appbox

/home/appbox/appbox_installer/Jackett/jackett
EOF
)
    create_service 'jackett'
    configure_nginx 'jackett' '9117'
}

setup_couchpotato() {
    s6-svc -d /run/s6/services/couchpotato || true
    apt-get install python git -y || true
    mkdir /home/appbox/appbox_installer/couchpotato && cd /home/appbox/appbox_installer/couchpotato
    git clone --depth 1 https://github.com/RuudBurger/CouchPotatoServer.git
    cat << EOF > /etc/default/couchpotato
CP_USER=appbox
CP_HOME=/home/appbox/appbox_installer/couchpotato/CouchPotatoServer
CP_DATA=/home/appbox/appbox_installer/couchpotato/CouchPotatoData
EOF
    mkdir -p /home/appbox/appbox_installer/couchpotato/CouchPotatoData
    cat << EOF > /home/appbox/appbox_installer/couchpotato/CouchPotatoData/settings.conf
[core]
url_base = /couchpotato
show_wizard = 1
launch_browser = False
EOF
    cp CouchPotatoServer/init/ubuntu /etc/init.d/couchpotato
    chmod +x /etc/init.d/couchpotato
    sed -i 's/--daemon//g' /etc/init.d/couchpotato
    sed -i 's/--quiet//g' /etc/init.d/couchpotato
    chown -R appbox:appbox /home/appbox/appbox_installer/couchpotato/
    RUNNER=$(cat << EOF
#!/bin/execlineb -P

# Redirect stderr to stdout.
fdmove -c 2 1

s6-setuidgid appbox

cd /home/appbox/appbox_installer/couchpotato/CouchPotatoServer
/usr/bin/python CouchPotato.py --pid_file=/var/run/couchpotato/couchpotato.pid --data_dir=/home/appbox/appbox_installer/couchpotato/CouchPotatoData
EOF
)
    create_service 'couchpotato'
    configure_nginx 'couchpotato' '5050'
}

setup_nzbget() {
    s6-svc -d /run/s6/services/nzbget || true
    mkdir /tmp/nzbget
    wget -O /tmp/nzbget/nzbget.run https://nzbget.net/download/nzbget-latest-bin-linux.run
    chown appbox:appbox /tmp/nzbget/nzbget.run
    mkdir -p /home/appbox/appbox_installer/nzbget
    chown appbox:appbox /home/appbox/appbox_installer/nzbget
    /bin/su -s /bin/bash -c "sh /tmp/nzbget/nzbget.run --destdir /home/appbox/appbox_installer/nzbget" appbox
    rm -rf /tmp/nzbget
    RUNNER=$(cat << EOF
#!/bin/execlineb -P

# Redirect stderr to stdout.
fdmove -c 2 1

s6-setuidgid appbox

/home/appbox/appbox_installer/nzbget/nzbget -s -o outputmode=log
EOF
)
    create_service 'nzbget'
    configure_nginx 'nzbget' '6789'
}

setup_sabnzbdplus() {
    s6-svc -d /run/s6/services/sabnzbd || true
    cat << EOF > /etc/lsb-release
DISTRIB_ID=Ubuntu
DISTRIB_RELEASE=20.04
DISTRIB_CODENAME=focal
DISTRIB_DESCRIPTION="Ubuntu 20.04.1 LTS"
EOF
    cat << EOF > /usr/lib/os-release
NAME="Ubuntu"
VERSION="20.04.1 LTS (Focal Fossa)"
ID=ubuntu
ID_LIKE=debian
PRETTY_NAME="Ubuntu 20.04.1 LTS"
VERSION_ID="20.04"
HOME_URL="https://www.ubuntu.com/"
SUPPORT_URL="https://help.ubuntu.com/"
BUG_REPORT_URL="https://bugs.launchpad.net/ubuntu/"
PRIVACY_POLICY_URL="https://www.ubuntu.com/legal/terms-and-policies/privacy-policy"
VERSION_CODENAME=focal
UBUNTU_CODENAME=focal
EOF
    add-apt-repository -y ppa:jcfp/ppa
    apt-get install -y sabnzbdplus
    sed -i 's/--daemon//g' /etc/init.d/sabnzbdplus
    mkdir /home/appbox/.sabnzbd
    chown appbox:appbox /home/appbox/.sabnzbd
    cat << EOF > /etc/default/sabnzbdplus
USER=appbox
HOST=0.0.0.0
PORT=9090
EXTRAOPTS=-b0
EOF
    RUNNER=$(cat << EOF
#!/bin/execlineb -P

# Redirect stderr to stdout.
fdmove -c 2 1

s6-setuidgid appbox

cd /home/appbox/.sabnzbd
/usr/bin/python3 -OO /usr/bin/sabnzbdplus --pidfile /var/run/sabnzbdplus/pid --server 0.0.0.0:9090 -b0 -f /home/appbox/.sabnzbd/sabnzbd.ini
EOF
)
    create_service 'sabnzbd'
    configure_nginx 'sabnzbd' '9090'
}

setup_ombi() {
    s6-svc -d /run/s6/services/ombi || true
    update-locale "LANG=en_US.UTF-8"
    locale-gen --purge "en_US.UTF-8"
    dpkg-reconfigure --frontend noninteractive locales
    wget -qO - https://repo.ombi.turd.me/pubkey.txt | sudo apt-key add -
    echo "deb [arch=amd64,armhf] http://repo.ombi.turd.me/stable/ jessie main" | sudo tee "/etc/apt/sources.list.d/ombi.list"
    mkdir -p opt
    apt update
    apt -y remove ombi || true
    apt -y install ombi
    mv /opt/Ombi /home/appbox/appbox_installer/ombiServer
    mkdir -p /home/appbox/appbox_installer/ombiData
    chown -R appbox:appbox /home/appbox/appbox_installer/ombiData
    chown -R appbox:appbox /home/appbox/appbox_installer/ombiServer
    RUNNER=$(cat << EOF
#!/bin/execlineb -P

# Redirect stderr to stdout.
fdmove -c 2 1

s6-setuidgid appbox

cd /home/appbox/appbox_installer/ombiServer
/home/appbox/appbox_installer/ombiServer/Ombi --baseurl /ombi --host http://*:5000 --storage /home/appbox/appbox_installer/ombiData/
EOF
)
    create_service 'ombi'
    configure_nginx 'ombi' '5000'
}

setup_lidarr() {
    s6-svc -d /run/s6/services/lidarr || true
    apt update
    # Based on https://wiki.servarr.com/lidarr/installation#Debian.2FUbuntu
    apt -y install libmediainfo0v5 curl mediainfo sqlite3 libchromaprint-tools || true
    cd /home/appbox/appbox_installer
    wget --content-disposition 'http://lidarr.servarr.com/v1/update/master/updatefile?os=linux&runtime=netcore&arch=x64'
    tar -xvzf Lidarr*.linux*.tar.gz
    rm -f Lidarr*.linux*.tar.gz
    chown -R appbox:appbox /home/appbox/appbox_installer/Lidarr
    # Generate config
    /bin/su -s /bin/bash -c "/home/appbox/appbox_installer/Lidarr/Lidarr -nobrowser -data=/home/appbox/.config/Lidarr/" appbox &
    until grep -q 'UrlBase' /home/appbox/.config/Lidarr/config.xml; do
        sleep 1
    done
    pkill -f 'Lidarr'
    sed -i 's@<UrlBase></UrlBase>@<UrlBase>/lidarr</UrlBase>@g' /home/appbox/.config/Lidarr/config.xml

    RUNNER=$(cat << EOF
#!/bin/execlineb -P

# Redirect stderr to stdout.
fdmove -c 2 1

s6-setuidgid appbox

foreground { rm /home/appbox/.config/Lidarr/lidarr.pid }
/home/appbox/appbox_installer/Lidarr/Lidarr -nobrowser -data=/home/appbox/.config/Lidarr/
EOF
)
    create_service 'lidarr'
    configure_nginx 'lidarr' '8686'
}

setup_organizr() {
    s6-svc -d /run/s6/services/php-fpm || true
    apt install -y php-mysql php-sqlite3 sqlite3 php-xml php-zip php-curl php-fpm git
    mkdir -p /run/php
    mkdir -p /home/appbox/appbox_installer/organizr
    git clone --depth 1 -b v2-master https://github.com/causefx/Organizr /home/appbox/appbox_installer/organizr/organizr

    echo "Configuring PHP to use sockets"

    if [ ! -f /etc/php/7.4/fpm/pool.d/www.conf.original ]; then
        cp /etc/php/7.4/fpm/pool.d/www.conf /etc/php/7.4/fpm/pool.d/www.conf.original
    fi

    # TODO: Check if settings catch
    # enable PHP-FPM
    sed -i "s#www-data#appbox#g" /etc/php/7.4/fpm/pool.d/www.conf
    sed -i "s#;listen.mode = 0660#listen.mode = 0777#g" /etc/php/7.4/fpm/pool.d/www.conf
    # set our recommended defaults
    sed -i "s#pm = dynamic#pm = ondemand#g" /etc/php/7.4/fpm/pool.d/www.conf
    sed -i "s#pm.max_children = 5#pm.max_children = 4000#g" /etc/php/7.4/fpm/pool.d/www.conf
    sed -i "s#pm.start_servers = 2#;pm.start_servers = 2#g" /etc/php/7.4/fpm/pool.d/www.conf
    sed -i "s#;pm.process_idle_timeout = 10s;#pm.process_idle_timeout = 10s;#g" /etc/php/7.4/fpm/pool.d/www.conf
    sed -i "s#;pm.max_requests = 500#pm.max_requests = 0#g" /etc/php/7.4/fpm/pool.d/www.conf
    chown -R appbox:appbox /var/lib/php

        cat << EOF > /etc/nginx/sites-enabled/organizr
# V0.0.4
server {
  listen 8009;
  root /home/appbox/appbox_installer/organizr;
  index index.html index.htm index.php;

  server_name _;
  client_max_body_size 0;

  # Real Docker IP
  # Make sure to update the IP range with your Docker IP subnet
  real_ip_header X-Forwarded-For;
  #set_real_ip_from 172.17.0.0/16;
  real_ip_recursive on;

  # Deny access to Org .git directory
  location ~ /\.git {
    deny all;
  }

  location /organizr {
    try_files \$uri \$uri/ /organizr/index.html /organizr/index.php?\$args =404;
  }

  location /organizr/api/v2 {
    try_files \$uri /organizr/api/v2/index.php\$is_args\$args;
  }

  location ~ \.php$ {
    fastcgi_split_path_info ^(.+?\.php)(\/.*|)$;
    fastcgi_pass unix:/run/php/php7.4-fpm.sock;
    fastcgi_index index.php;
    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    fastcgi_buffers 32 32k;
    fastcgi_buffer_size 32k;
  }
}
EOF

    chown -R appbox:appbox /home/appbox/appbox_installer/organizr /run/php
    RUNNER=$(cat << EOF
#!/bin/execlineb -P

# Redirect stderr to stdout.
fdmove -c 2 1

/usr/sbin/php-fpm7.4 -F
EOF
)
    create_service 'php-fpm'
    configure_nginx 'organizr/' '8009'
}

setup_nzbhydra2() {
    s6-svc -d /run/s6/services/nzbhydra2 || true
    mkdir -p /var/cache/oracle-jdk11-installer-local
    wget -c --no-cookies --no-check-certificate -O /var/cache/oracle-jdk11-installer-local/jdk-11.0.10_linux-x64_bin.tar.gz https://github.com/coder8338/appbox_installer/releases/download/bin/asd8923ehsa.tar.gz
    add-apt-repository -y ppa:linuxuprising/java
    apt update
    echo debconf shared/accepted-oracle-license-v1-2 select true | debconf-set-selections
    echo debconf shared/accepted-oracle-license-v1-2 seen true | debconf-set-selections
    apt-get install -y oracle-java11-installer-local libchromaprint-tools || true
    sed -i 's/tar xzf $FILENAME/tar xzf $FILENAME --no-same-owner/g' /var/lib/dpkg/info/oracle-java11-installer-local.postinst
    dpkg --configure -a
    mkdir -p /home/appbox/appbox_installer/nzbhydra2
    cd /home/appbox/appbox_installer/nzbhydra2
    curl -L -O $( curl -s https://api.github.com/repos/theotherp/nzbhydra2/releases | grep linux.zip | grep browser_download_url | head -1 | cut -d \" -f 4 )
    unzip -o nzbhydra2*.zip
    rm -f nzbhydra2*.zip
    chmod +x /home/appbox/appbox_installer/nzbhydra2/nzbhydra2
    chown -R appbox:appbox /home/appbox/appbox_installer/nzbhydra2
    # Generate config
    /bin/su -s /bin/bash -c "/home/appbox/appbox_installer/nzbhydra2/nzbhydra2" appbox &
    until grep -q 'urlBase' /home/appbox/appbox_installer/nzbhydra2/data/nzbhydra.yml; do
        sleep 1
    done
    pkill -f 'nzbhydra2'
    sed -i 's@urlBase: "/"@urlBase: "/nzbhydra2"@g' /home/appbox/appbox_installer/nzbhydra2/data/nzbhydra.yml

    RUNNER=$(cat << EOF
#!/bin/execlineb -P

# Redirect stderr to stdout.
fdmove -c 2 1

s6-setuidgid appbox

/home/appbox/appbox_installer/nzbhydra2/nzbhydra2
EOF
)
    create_service 'nzbhydra2'
    configure_nginx 'nzbhydra2' '5076'
}

setup_bazarr() {
    s6-svc -d /run/s6/services/bazarr || true
    apt update
    apt -y install git-core python3-pip python3-distutils || true
    cd /home/appbox/appbox_installer
    git clone --depth 1 https://github.com/morpheus65535/bazarr.git
    cd /home/appbox/appbox_installer/bazarr
    pip3 install -r requirements.txt
    chown -R appbox:appbox /home/appbox/appbox_installer/bazarr
    /bin/su -s /bin/bash -c "python3 /home/appbox/appbox_installer/bazarr/bazarr.py" appbox &
    until grep -q 'base_url' /home/appbox/appbox_installer/bazarr/data/config/config.ini; do
        sleep 1
    done
    pkill -f 'bazarr'
    sed -i '0,/base_url = /s//base_url = \/bazarr\//' /home/appbox/appbox_installer/bazarr/data/config/config.ini

    RUNNER=$(cat << EOF
#!/bin/execlineb -P

# Redirect stderr to stdout.
fdmove -c 2 1

s6-setuidgid appbox

python3 /home/appbox/appbox_installer/bazarr/bazarr.py
EOF
)
    create_service 'bazarr'
    configure_nginx 'bazarr' '6767'
}

setup_flexget() {
    s6-svc -d /run/s6/services/flexget || true
    apt install -y \
    python3-pip \
    libcap2-bin \
    curl || true
    pip3 install --upgrade pip && \
    hash -r pip3 && \
    pip3 install --upgrade setuptools && \
    pip3 install flexget[webui]
    mkdir -p /home/appbox/.config/flexget
    chown -R appbox:appbox /home/appbox/.config/flexget
    cat << EOF > /home/appbox/.config/flexget/config.yml
templates:
  Example-Template:
    accept_all: yes
    download: /APPBOX_DATA/storage
tasks:
  Task-1:
    rss: 'http://example'
    template: 'Example Template'
schedules:
  - tasks: 'Task-1'
    interval:
      minutes: 1
web_server:
  bind: 0.0.0.0
  port: 9797
  web_ui: yes
  base_url: /flexget
  run_v2: yes
EOF
    cat << EOF > /tmp/flexpasswd
#!/usr/bin/env bash
GOOD_PASSWORD=0
until [ "\${GOOD_PASSWORD}" == "1" ]; do
    echo 'Please enter a password for flexget'
    read FLEXGET_PASSWORD
    if ! flexget web passwd "\${FLEXGET_PASSWORD}" | grep -q 'is not strong enough'; then
        GOOD_PASSWORD=1
    else
        echo -e 'Your password is not strong enough, please enter a few more words.';
    fi
done
EOF
    chmod +x /tmp/flexpasswd
    /bin/su -s /bin/bash -c "/tmp/flexpasswd" appbox
    rm -f /tmp/flexpasswd

    RUNNER=$(cat << EOF
#!/bin/execlineb -P

# Redirect stderr to stdout.
fdmove -c 2 1

s6-setuidgid appbox

/usr/local/bin/flexget daemon start
EOF
)
    create_service 'flexget'
    configure_nginx 'flexget' '9797'
}

setup_filebot() {
    mkdir -p /var/cache/oracle-jdk11-installer-local
    wget -c --no-cookies --no-check-certificate -O /var/cache/oracle-jdk11-installer-local/jdk-11.0.10_linux-x64_bin.tar.gz https://github.com/coder8338/appbox_installer/releases/download/bin/asd8923ehsa.tar.gz
    add-apt-repository -y ppa:linuxuprising/java
    apt update
    echo debconf shared/accepted-oracle-license-v1-2 select true | debconf-set-selections
    echo debconf shared/accepted-oracle-license-v1-2 seen true | debconf-set-selections
    apt-get install -y oracle-java11-installer-local libchromaprint-tools || true
    sed -i 's/tar xzf $FILENAME/tar xzf $FILENAME --no-same-owner/g' /var/lib/dpkg/info/oracle-java11-installer-local.postinst
    dpkg --configure -a
    mkdir /home/appbox/appbox_installer/filebot && cd /home/appbox/appbox_installer/filebot
    wget -O /usr/share/pixmaps/filebot.png https://www.filebot.net/icon.png
    sh -xu <<< "$(curl -fsSL https://raw.githubusercontent.com/filebot/plugins/master/installer/tar.sh)"
    cat << EOF > /usr/share/applications/filebot.desktop
[Desktop Entry]
Version=1.0
Name=Filebot
GenericName=Filebot
X-GNOME-FullName=Filebot
TryExec=filebot
Exec=filebot
Terminal=false
Icon=filebot
Type=Application
Categories=Network;FileTransfer;GTK;
StartupWMClass=filebot
StartupNotify=true
X-GNOME-UsesNotifications=true
EOF
    chown -R appbox:appbox /home/appbox/appbox_installer/filebot
    pkill -HUP -f 'wingpanel'
    echo -e "\n\n\n\n\n
    Installation sucessful! Please launch filebot using the \"Applications\" menu on the top left of your screen."
}

setup_synclounge() {
    s6-svc -d /run/s6/services/synclounge || true
    apt install -y git npm
    npm install -g synclounge
    RUNNER=$(cat << EOF
#!/bin/execlineb -P

# Redirect stderr to stdout.
fdmove -c 2 1

s6-setuidgid appbox

/usr/local/bin/synclounge
EOF
)
    create_service 'synclounge'
    configure_nginx 'synclounge/' '8088'
}

setup_medusa() {
    s6-svc -d /run/s6/services/medusa || true
    apt install -y git unrar-free git openssl libssl-dev python3-pip python3-distutils python3 mediainfo || true
    git clone --depth 1 https://github.com/pymedusa/Medusa.git /home/appbox/appbox_installer/medusa
    cp /home/appbox/appbox_installer/medusa/runscripts/init.ubuntu /etc/init.d/medusa
    chmod +x /etc/init.d/medusa
    sed -i 's/--daemon//g' /etc/init.d/medusa
    cat << EOF > /etc/default/medusa
APP_HOME=/home/appbox/appbox_installer/medusa/
APP_DATA=/home/appbox/appbox_installer/medusa/
APP_USER=appbox
EOF
    cat << EOF >/home/appbox/appbox_installer/medusa/config.ini
[General]
  web_host = 0.0.0.0
  handle_reverse_proxy = 1
  launch_browser = 0
  web_use_gzip = false
  web_root = "/medusa"
  web_port = 8082
EOF
    chown -R appbox:appbox /home/appbox/appbox_installer/medusa
    RUNNER=$(cat << EOF
#!/bin/execlineb -P

# Redirect stderr to stdout.
fdmove -c 2 1

cd /home/appbox/appbox_installer/medusa
/usr/bin/python3 start.py -q --nolaunch --pidfile=/var/run/PyMedusa/Medusa.pid --datadir=/home/appbox/appbox_installer/medusa/
EOF
)
    create_service 'medusa'
    configure_nginx 'medusa' '8082' 'subfilter'
}

setup_lazylibrarian() {
    s6-svc -d /run/s6/services/lazylibrarian || true
    apt install -y git unrar-free git openssl libssl-dev python3-pip python3-distutils python3 mediainfo || true
    git clone --depth 1 https://gitlab.com/LazyLibrarian/LazyLibrarian.git /home/appbox/appbox_installer/lazylibrarian
    cp /home/appbox/appbox_installer/lazylibrarian/init/lazylibrarian.initd /etc/init.d/lazylibrarian
    chmod +x /etc/init.d/lazylibrarian
    sed -i 's/--daemon//g' /etc/init.d/lazylibrarian
    cat << EOF > /etc/default/lazylibrarian
CONFIG=/home/appbox/appbox_installer/lazylibrarian/config.ini
APP_PATH=/home/appbox/appbox_installer/lazylibrarian/
DATADIR=/home/appbox/appbox_installer/lazylibrarian/
RUN_AS=appbox
EOF
    cat << EOF >/home/appbox/appbox_installer/lazylibrarian/config.ini
[General]
  http_host = 0.0.0.0
  launch_browser = 0
  http_root = "/lazylibrarian"
EOF
chown -R appbox:appbox /home/appbox/appbox_installer/lazylibrarian
    RUNNER=$(cat << EOF
#!/bin/execlineb -P

# Redirect stderr to stdout.
fdmove -c 2 1

s6-setuidgid appbox

cd /home/appbox/appbox_installer/lazylibrarian
/usr/bin/python3 LazyLibrarian.py --nolaunch --config=/home/appbox/appbox_installer/lazylibrarian/config.ini --datadir=/home/appbox/appbox_installer/lazylibrarian/ --pidfile=/var/run/lazylibrarian/lazylibrarian.pid
EOF
)
    create_service 'lazylibrarian'
    configure_nginx 'lazylibrarian' '5299'
}

setup_pyload() {
    mkdir -p /home/appbox/appbox_installer/pyload && cd /home/appbox/appbox_installer/pyload
    s6-svc -d /run/s6/services/pyload || true
    apt install -y git python python-crypto python-pycurl python-pil tesseract-ocr libtesseract-dev  python-jinja2 libmozjs-52-0 libmozjs-52-dev
    ln -sf /usr/bin/js52 /usr/bin/js
    git clone --depth 1 -b stable https://github.com/pyload/pyload.git /home/appbox/appbox_installer/pyload
    echo "/home/appbox/.config/pyload" > /home/appbox/appbox_installer/pyload/module/config/configdir
    if  [ ! -f "/home/appbox/.config/pyload/files.db" ] || [ ! -f "/home/appbox/.config/pyload/files.version" ] || [ ! -f "/home/appbox/.config/pyload/plugin.conf" ] || [ ! -f "/home/appbox/.config/pyload/pyload.conf" ]
        then
        mkdir -p /home/appbox/.config/pyload
        chmod 777 /home/appbox/.config/pyload
        wget -O /home/appbox/.config/pyload/files.db https://raw.githubusercontent.com/Cobraeti/docker-pyload/master/config/files.db
        wget -O /home/appbox/.config/pyload/files.version https://raw.githubusercontent.com/Cobraeti/docker-pyload/master/config/files.version
        wget -O /home/appbox/.config/pyload/plugin.conf https://raw.githubusercontent.com/Cobraeti/docker-pyload/master/config/plugin.conf
        wget -O /home/appbox/.config/pyload/pyload.conf https://raw.githubusercontent.com/Cobraeti/docker-pyload/master/config/pyload.conf

        sed -i 's#"Path Prefix" =#"Path Prefix" = /pyload#g' /home/appbox/.config/pyload/pyload.conf
        sed -i 's#/downloads#/home/appbox/Downloads/#g' /home/appbox/.config/pyload/pyload.conf
    fi
    chown -R appbox:appbox /home/appbox/.config/pyload
    chown -R appbox:appbox /home/appbox/appbox_installer/pyload

    RUNNER=$(cat << EOF
#!/bin/execlineb -P

# Redirect stderr to stdout.
fdmove -c 2 1

s6-setuidgid appbox

cd /home/appbox/appbox_installer/pyload
/usr/bin/python /home/appbox/appbox_installer/pyload/pyLoadCore.py
EOF
)
    create_service 'pyload'
    configure_nginx 'pyload' '8000'
    echo -e "\n\n\n\n\n
    The default user for pyload is: admin
    The default password for pyload is: pyload"
}

setup_ngpost() {
    mkdir /home/appbox/appbox_installer/ngpost && cd /home/appbox/appbox_installer/ngpost
    curl -L -O $( curl -s https://api.github.com/repos/mbruel/ngPost/releases | grep 'debian8.AppImage' | grep browser_download_url | head -1 | cut -d \" -f 4 )
    chmod +x /home/appbox/appbox_installer/ngpost/*.AppImage
    FILENAME=$(ls -la /home/appbox/appbox_installer/ngpost | grep 'AppImage' | awk '{print $9}')
    wget -O /usr/share/pixmaps/ngPost.png https://raw.githubusercontent.com/mbruel/ngPost/master/src/resources/icons/ngPost.png
        cat << EOF > /usr/share/applications/ngpost.desktop
[Desktop Entry]
Version=1.0
Name=ngPost
GenericName=ngPost
X-GNOME-FullName=ngPost
TryExec=/home/appbox/appbox_installer/ngpost/${FILENAME}
Exec=/home/appbox/appbox_installer/ngpost/${FILENAME}
Terminal=false
Icon=ngPost
Type=Application
Categories=Network;FileTransfer;GTK;
StartupWMClass=ngPost
StartupNotify=true
X-GNOME-UsesNotifications=true
EOF
    chown -R appbox:appbox /home/appbox/appbox_installer/ngpost
    pkill -HUP -f 'wingpanel'
    echo -e "\n\n\n\n\n
    Installation sucessful! Please launch ngpost using the \"Applications\" menu on the top left of your screen."
}

setup_komga() {
    s6-svc -d /run/s6/services/komga || true
    mkdir -p /var/cache/oracle-jdk11-installer-local
    wget -c --no-cookies --no-check-certificate -O /var/cache/oracle-jdk11-installer-local/jdk-11.0.10_linux-x64_bin.tar.gz https://github.com/coder8338/appbox_installer/releases/download/bin/asd8923ehsa.tar.gz
    add-apt-repository -y ppa:linuxuprising/java
    apt update
    echo debconf shared/accepted-oracle-license-v1-2 select true | debconf-set-selections
    echo debconf shared/accepted-oracle-license-v1-2 seen true | debconf-set-selections
    apt-get install -y oracle-java11-installer-local || true
    sed -i 's/tar xzf $FILENAME/tar xzf $FILENAME --no-same-owner/g' /var/lib/dpkg/info/oracle-java11-installer-local.postinst
    dpkg --configure -a
    mkdir /home/appbox/appbox_installer/komga
    cd /home/appbox/appbox_installer/komga
    curl -L -O $( curl -s https://api.github.com/repos/gotson/komga/releases | grep jar | grep browser_download_url | head -1 | cut -d \" -f 4 )
    chown -R appbox:appbox /home/appbox/appbox_installer/komga

    FILENAME=$(ls -la /home/appbox/appbox_installer/komga | grep jar | awk '{print $9}')
    RUNNER=$(cat << EOF
#!/bin/execlineb -P

# Redirect stderr to stdout.
fdmove -c 2 1

s6-setuidgid appbox

/usr/bin/java -jar /home/appbox/appbox_installer/komga/${FILENAME} --server.servlet.context-path="/komga" --server.port=8443
EOF
)
    create_service 'komga'
    configure_nginx 'komga' '8443'
}

setup_ombiv4() {
    s6-svc -d /run/s6/services/ombiv4 || true
    update-locale "LANG=en_US.UTF-8"
    locale-gen --purge "en_US.UTF-8"
    dpkg-reconfigure --frontend noninteractive locales
    curl -sSL https://apt.ombi.app/pub.key | sudo apt-key add -
    echo "deb https://apt.ombi.app/develop jessie main" | sudo tee /etc/apt/sources.list.d/ombiv4.list
    mkdir -p opt
    apt update
    apt -y remove ombi || true
    apt -y install ombi
    mv /opt/Ombi /home/appbox/appbox_installer/ombiv4Server
    mkdir -p /home/appbox/appbox_installer/ombiv4Data
    chown -R appbox:appbox /home/appbox/appbox_installer/ombiv4Data
    chown -R appbox:appbox /home/appbox/appbox_installer/ombiv4Server
    RUNNER=$(cat << EOF
#!/bin/execlineb -P

# Redirect stderr to stdout.
fdmove -c 2 1

s6-setuidgid appbox

cd /home/appbox/appbox_installer/ombiv4Server
/home/appbox/appbox_installer/ombiv4Server/Ombi --baseurl /ombiv4 --host http://*:6050 --storage /home/appbox/appbox_installer/ombiv4Data/
EOF
)
    create_service 'ombiv4'
    configure_nginx 'ombiv4' '6050'
}

setup_readarr() {
    s6-svc -d /run/s6/services/readarr || true
    mkdir /home/appbox/appbox_installer/Readarr
    chown appbox:appbox /home/appbox/appbox_installer/Readarr
    apt install -y curl sqlite
    wget -O /tmp/readarr.tar.gz https://github.com/coder8338/appbox_installer/releases/download/readarr-10.0.0.27010/readarr.tar.gz
    tar zxvf /tmp/readarr.tar.gz -C /home/appbox/appbox_installer/Readarr/
    cp -R /home/appbox/appbox_installer/Readarr/publish/* /home/appbox/appbox_installer/Readarr/
    chown -R appbox:appbox /home/appbox/appbox_installer/Readarr
    # Generate config
    cd /home/appbox/appbox_installer/Readarr
    /bin/su -s /bin/bash -c "/home/appbox/appbox_installer/Readarr/Readarr -nobrowser -data /home/appbox/appbox_installer/Readarr" appbox &
    until grep -q 'UrlBase' /home/appbox/.config/Readarr/config.xml; do
        sleep 1
    done
    pkill -f 'Readarr'
    sed -i 's@<UrlBase></UrlBase>@<UrlBase>/readarr</UrlBase>@g' /home/appbox/.config/Readarr/config.xml
    RUNNER=$(cat << EOF
#!/bin/execlineb -P

# Redirect stderr to stdout.
fdmove -c 2 1

s6-setuidgid appbox

foreground { rm /home/appbox/.config/Readarr/readarr.pid }
/home/appbox/appbox_installer/Readarr/Readarr -nobrowser -data /home/appbox/appbox_installer/Readarr
EOF
)
    create_service 'readarr'
    configure_nginx 'readarr' '8787'

    # Build commands:
    # curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
    # echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
    # wget https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb
    # wget -qO- https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
    # dpkg -i /tmp/packages-microsoft-prod.deb
    # rm -f /tmp/packages-microsoft-prod.deb
    # apt update
    # apt install -y dotnet-sdk-5.0 
    # /bin/su -s /bin/bash -c "mkdir /tmp/build/" appbox
    # cd /tmp/build/
    # /bin/su -s /bin/bash -c "git clone https://github.com/Readarr/Readarr ." appbox
    # #find . -name '*.csproj' -exec dotnet restore {} \;
    # /bin/su -s /bin/bash -c "bash build.sh" appbox
    # cd /tmp/build/_output/net5.0/linux-x64/
    # /bin/su -s /bin/bash -c "rsync -av --progress * /home/appbox/appbox_installer/Readarr" appbox
    # cd /tmp/build/_output/
    # /bin/su -s /bin/bash -c "rsync -av --progress UI /home/appbox/appbox_installer/Readarr/" appbox
    # /bin/su -s /bin/bash -c "cp /tmp/build/_output/Readarr.Update/net5.0/linux-x64/fpcalc /home/appbox/appbox_installer/Readarr/" appbox
    # # rm -rf /tmp/build
}

setup_overseerr() {
    s6-svc -d /run/s6/services/overseerr || true
    mkdir /home/appbox/appbox_installer/overseerr
    chown appbox:appbox /home/appbox/appbox_installer/overseerr
    curl -sL https://deb.nodesource.com/setup_12.x | bash -
    curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
    echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
    apt update
    apt install -y yarn sqlite jq nodejs
    dlurl="$(curl -sS https://api.github.com/repos/sct/overseerr/releases/latest | jq .tarball_url -r)"
    wget "$dlurl" -q -O /tmp/overseerr.tar.gz
    tar --strip-components=1 -C /home/appbox/appbox_installer/overseerr -xzvf /tmp/overseerr.tar.gz
    yarn install --cwd /home/appbox/appbox_installer/overseerr
    NODE_ENV=production yarn --cwd /home/appbox/appbox_installer/overseerr build
    chown -R appbox:appbox /home/appbox/appbox_installer/overseerr
    RUNNER=$(cat << EOF
#!/bin/execlineb -P

# Redirect stderr to stdout.
fdmove -c 2 1

s6-setuidgid appbox

export NODE_ENV production
export HOST 127.0.0.1
export PORT 5055

cd /home/appbox/appbox_installer/overseerr
/usr/bin/node dist/index.js
EOF
)
    create_service 'overseerr'
    if ! grep -q "overseerr {" /etc/nginx/sites-enabled/default; then
        sed -i '/server_name _/a \
        location /overseerr {\
                set $app "overseerr";\
                # Remove /overseerr path to pass to the app\
                rewrite ^/overseerr/?(.*)$ /$1 break;\
                proxy_pass http://127.0.0.1:5055; # NO TRAILING SLASH\
\
                # Redirect location headers\
                proxy_redirect ^ /$app;\
                proxy_redirect /setup /$app/setup;\
                proxy_redirect /login /$app/login;\
\
                # Sub filters to replace hardcoded paths\
                proxy_set_header Accept-Encoding "";\
                sub_filter_once off;\
                sub_filter_types *;\
                sub_filter '\''href="/"'\'' '\''href="/$app"'\'';\
                sub_filter '\''href="/login"'\'' '\''href="/$app/login"'\'';\
                sub_filter '\''href:"/"'\'' '\''href:"/$app"'\'';\
                sub_filter '\''/_next'\'' '\''/$app/_next'\'';\
                sub_filter '\''/api/v1'\'' '\''/$app/api/v1'\'';\
                sub_filter '\''/login/plex/loading'\'' '\''/$app/login/plex/loading'\'';\
                sub_filter '\''/images/'\'' '\''/$app/images/'\'';\
                sub_filter '\''/android-'\'' '\''/$app/android-'\'';\
                sub_filter '\''/apple-'\'' '\''/$app/apple-'\'';\
                sub_filter '\''/favicon'\'' '\''/$app/favicon'\'';\
                sub_filter '\''/logo.png'\'' '\''/$app/logo.png'\'';\
                sub_filter '\''/site.webmanifest'\'' '\''/$app/site.webmanifest'\'';\
        }' /etc/nginx/sites-enabled/default
    fi
    pkill -HUP nginx
    url_output "overseerr"
}

setup_requestrr() {
    s6-svc -d /run/s6/services/requestrr || true
    
    # Get Version
    RQRR_DOWNLOAD=requestrr-linux-x64.zip
    RQRR_URL=https://github.com/darkalfx/requestrr/releases
    RQRR_VERSION=$(curl -s $RQRR_URL | grep "$RQRR_DOWNLOAD" | grep -Po ".*\/download\/V([0-9\.]+).*" | awk -F'/' '{print $6}' | tr -d 'v' | sort -V | tail -1)
    
    if [[ -d /home/appbox/appbox_installer/requestrr ]]; then
        rm -rf /home/appbox/appbox_installer/requestrr
    fi

    mkdir -p /home/appbox/appbox_installer/requestrr
    cd /home/appbox/appbox_installer/requestrr
    
    # Pass on version to wget
    wget -qN $RQRR_URL/download/$RQRR_VERSION/$RQRR_DOWNLOAD
    
    # Unzip
    unzip -o requestrr*.zip
    rm -f requestrr*.zip
    
    # Move everything one directory up
    mv /home/appbox/appbox_installer/requestrr/requestrr-linux-x64/* .
    
    # Delete old folder
    rm -rf requestrr-linux-x64
    
    # Make the requestrr executable and chown the folder
    chmod +x /home/appbox/appbox_installer/requestrr/Requestrr.WebApi
    chown -R appbox:appbox /home/appbox/appbox_installer/requestrr
    
    # Generate config
    /bin/su -s /bin/bash -c "/home/appbox/appbox_installer/requestrr/Requestrr.WebApi" appbox &
    until grep -q 'BaseUrl' /home/appbox/appbox_installer/requestrr/config/settings.json; do
        sleep 1
    done
    pkill -f 'Requestrr.WebApi'

    # Need to edit baseurl in config
    sed -i 's@"BaseUrl" : ""@"BaseUrl" : "/requestrr"@g' /home/appbox/appbox_installer/requestrr/config/settings.json
    
    # Need to chown once more for the configs
    chown -R appbox:appbox /home/appbox/appbox_installer/requestrr
    
    RUNNER=$(cat << EOF
#!/bin/execlineb -P

# Redirect stderr to stdout.
fdmove -c 2 1

s6-setuidgid appbox

cd /home/appbox/appbox_installer/requestrr/
/home/appbox/appbox_installer/requestrr/Requestrr.WebApi
EOF
)
    create_service 'requestrr'
    configure_nginx 'requestrr' '4545'
}

# setup_deemixrr() {
#     s6-svc -d /run/s6/services/deemixrr || true
#     wget https://packages.microsoft.com/config/ubuntu/18.04/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb
#     wget -qO- https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
#     dpkg -i /tmp/packages-microsoft-prod.deb
#     rm -f /tmp/packages-microsoft-prod.deb
#     add-apt-repository "$(wget -qO- https://packages.microsoft.com/config/ubuntu/18.04/mssql-server-2019.list)"
#     apt-get update; \
#     apt-get install -y apt-transport-https && \
#     apt-get update && \
#     apt-get install -y dotnet-sdk-5.0 python3 python3-pip aspnetcore-runtime-3.1 mssql-server
#     mkdir -p /var/opt/mssql/
#     git clone --depth 1 -b master https://github.com/TheUltimateC0der/Deemixrr.git /opt/deemixrr
#     cd /opt/deemixrr
#     dotnet restore "Deemixrr/Deemixrr.csproj"
#     dotnet build "Deemixrr/Deemixrr.csproj" -c Release -o /opt/deemixrr/app/build
#     dotnet publish "Deemixrr/Deemixrr.csproj" -c Release -o /opt/deemixrr/app/publish
#     python3 -m pip install --quiet deemix
#     mkdir /home/appbox/.config/deemix
#     chown -R appbox:appbox /opt/deemixrr /home/appbox/.config/deemix /var/opt/mssql
#     cat << EOF > /etc/supervisor/conf.d/deemixrr.conf
# [program:deemixrr]
# command=/bin/su -s /bin/bash -c "export Kestrel__EndPoints__Http__Url=http://0.0.0.0:5555/deemixrr;export ConnectionStrings__DefaultConnection=\"server=localhost;uid=sa;pwd=TAOIDh89333iundafkjasd;database=Deemixrr;pooling=true\";export Hangfire__DashboardPath=/autoloaderjobs;export Hangfire__Password=TAOIDh89333iundafkjasd;export Hangfire__Username=Deemixrr;export Hangfire__Workers=2;export JobConfiguration__GetUpdatesRecurringJob='0 2 * * *';export JobConfiguration__SizeCalculatorRecurringJob='0 12 * * *';export DelayConfiguration__ImportArtistsBackgroundJob_ExecuteDelay=1000;export DelayConfiguration__CheckArtistForUpdatesBackgroundJob_GetTrackCountDelay=1000;export DelayConfiguration__CheckArtistForUpdatesBackgroundJob_ExecuteDelay=1000;export DelayConfiguration__CheckPlaylistForUpdatesBackgroundJob_ExecuteDelay=1000;export DelayConfiguration__CreateArtistBackgroundJob_FromPlaylistDelay=1000;export DelayConfiguration__CreateArtistBackgroundJob_FromUserDelay=1000;export DelayConfiguration__CreateArtistBackgroundJob_FromCsvDelay=1000;export DelayConfiguration__CreatePlaylistBackgroundJob_FromCsvDelay=1000;export PGID=1000;export PUID=1000;dotnet /opt/deemixrr/app/publish/Deemixrr.dll" appbox
# autostart=true
# autorestart=true
# priority=5
# stdout_events_enabled=true
# stderr_events_enabled=true
# stdout_logfile=/tmp/deemixrr.log
# stdout_logfile_maxbytes=0
# stderr_logfile=/tmp/deemixrr.log
# stderr_logfile_maxbytes=0
# EOF
#     cat << EOF > /etc/supervisor/conf.d/mssql.conf
# [program:mssql]
# command=/bin/su -s /bin/bash -c "export SA_PASSWORD=TAOIDh89333iundafkjasd; export ACCEPT_EULA=Y;/opt/mssql/bin/sqlservr" appbox
# autostart=true
# autorestart=true
# priority=5
# stdout_events_enabled=true
# stderr_events_enabled=true
# stdout_logfile=/tmp/mssql.log
# stdout_logfile_maxbytes=0
# stderr_logfile=/tmp/mssql.log
# stderr_logfile_maxbytes=0
# EOF
#     configure_nginx 'deemixrr' '5555'
# }

# Based on: https://github.com/mynttt/UpdateTool/issues/70

setup_updatetool() {
    s6-svc -d /run/s6/services/updatetool || true
    apt install -y libcurl4-openssl-dev bzip2 default-jre
    cd /home/appbox/appbox_installer
    mkdir -p /home/appbox/appbox_installer/UpdateTool
    cd /home/appbox/appbox_installer/UpdateTool
    curl -L -O $( curl -s https://api.github.com/repos/mynttt/UpdateTool/releases/latest | grep UpdateTool | grep browser_download_url | head -1 | cut -d \" -f 4 )
    chown -R appbox:appbox /home/appbox/appbox_installer/UpdateTool    
    chmod +x /home/appbox/appbox_installer/UpdateTool/UpdateTool-1.6.3.jar
    cat << EOF > /home/appbox/appbox_installer/UpdateTool/runner.sh
#!/bin/bash

export JAVA="/usr/bin/java"
export TOOL_JAR="/home/appbox/appbox_installer/UpdateTool/UpdateTool-1.6.3.jar"
export JVM_MAX_HEAP="-Xmx256m"
export RUN_EVERY_N_HOURS="12"
PLEX_DATA_DIR="/APPBOX_DATA/apps/plex.${HOSTNAME}/config/Library/Application Support/Plex Media Server/"
export PLEX_DATA_DIR

\$JAVA -Xms64m "\${JVM_MAX_HEAP}" -XX:+UseG1GC -XX:MinHeapFreeRatio=15 -XX:MaxHeapFreeRatio=30 -jar "\${TOOL_JAR}" imdb-docker "{schedule=\$RUN_EVERY_N_HOURS}"
EOF
    chmod +x /home/appbox/appbox_installer/UpdateTool/runner.sh
    RUNNER=$(cat << EOF
#!/bin/execlineb -P

# Redirect stderr to stdout.
fdmove -c 2 1

s6-setuidgid appbox
cd /home/appbox/appbox_installer/UpdateTool/
/home/appbox/appbox_installer/UpdateTool/runner.sh
EOF
)
    create_service 'updatetool'
}

setup_flood() {
    s6-svc -d /run/s6/services/flood || true
    curl -sL https://deb.nodesource.com/setup_12.x | bash -
    curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
    echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
    apt install -y libcurl4-openssl-dev nodejs curl git
    cd /home/appbox/appbox_installer
    git clone https://github.com/jesec/flood.git
    cd /home/appbox/appbox_installer/flood
    npm install --global flood
    chown -R appbox:appbox /home/appbox/appbox_installer/flood

    RUNNER=$(cat << EOF
#!/usr/bin/with-contenv bash

s6-setuidgid appbox

exec flood --baseuri /flood
EOF
)
    create_service 'flood'
    configure_nginx 'flood' '3000'
}

setup_tautulli() {
    s6-svc -d /run/s6/services/tautulli || true
    apt install -y git
    cd /home/appbox/appbox_installer
    git clone --depth 1 https://github.com/Tautulli/Tautulli.git /home/appbox/appbox_installer/Tautulli
    chown -R appbox:appbox /home/appbox/appbox_installer/Tautulli

    # Generate config
    /bin/su -s /bin/bash -c "/usr/bin/python3.8 /home/appbox/appbox_installer/Tautulli/Tautulli.py --nolaunch" appbox &
    until grep -q 'http_root' /home/appbox/appbox_installer/Tautulli/config.ini; do
        sleep 1
    done
    pkill -f 'Tautulli.py'
    sed -i 's/http_root.*/http_root = \/tautulli/' /home/appbox/appbox_installer/Tautulli/config.ini

    RUNNER=$(cat << EOF
#!/bin/execlineb -P

# Redirect stderr to stdout.
fdmove -c 2 1

s6-setuidgid appbox

/usr/bin/python3.8 /home/appbox/appbox_installer/Tautulli/Tautulli.py --config /home/appbox/appbox_installer/Tautulli/config.ini --nolaunch
EOF
)
    create_service 'tautulli'
    configure_nginx 'tautulli' '8181'
}

# Add new setups below this line

setup_prowlarr() {
    s6-svc -d /run/s6/services/prowlarr || true
    mkdir /home/appbox/appbox_installer/Prowlarr
    chown appbox:appbox /home/appbox/appbox_installer/Prowlarr
    apt install -y curl sqlite3
    wget -O /home/appbox/appbox_installer/prowlarr.tar.gz --content-disposition 'http://prowlarr.servarr.com/v1/update/develop/updatefile?os=linux&runtime=netcore&arch=x64'
    tar -zxf /home/appbox/appbox_installer/prowlarr.tar.gz -C /home/appbox/appbox_installer/
    rm home/appbox/appbox_installer/prowlarr.tar.gz
    chown -R appbox:appbox /home/appbox/appbox_installer/Prowlarr
    # Generate config
    cd /home/appbox/appbox_installer/Prowlarr
    /bin/su -s /bin/bash -c "/home/appbox/appbox_installer/Prowlarr/Prowlarr -nobrowser -data /home/appbox/appbox_installer/Prowlarr" appbox &
    until grep -q 'UrlBase' /home/appbox/.config/Prowlarr/config.xml; do
        sleep 1
    done
    pkill -f 'Prowlarr'
    sed -i 's@<UrlBase></UrlBase>@<UrlBase>/prowlarr</UrlBase>@g' /home/appbox/.config/Prowlarr/config.xml
    RUNNER=$(cat << EOF
#!/bin/execlineb -P
# Redirect stderr to stdout.
fdmove -c 2 1
s6-setuidgid appbox
foreground { rm /home/appbox/.config/Prowlarr/prowlarr.pid }
/home/appbox/appbox_installer/Prowlarr/Prowlarr -nobrowser -data /home/appbox/appbox_installer/Prowlarr
EOF
)
    create_service 'prowlarr'
    configure_nginx 'prowlarr' '9696'
}

install_prompt() {
    echo "Welcome to the install script, please select one of the following options to install:
    
    1) radarr
    2) sonarr
    3) sickchill
    4) jackett
    5) couchpotato
    6) nzbget
    7) sabnzbdplus
    8) ombi
    9) lidarr
    10) organizr
    11) nzbhydra2
    12) bazarr
    13) flexget
    14) filebot
    15) synclounge
    16) medusa
    17) lazylibrarian
    18) pyload
    19) ngpost
    20) komga
    21) ombiv4
    22) readarr
    23) overseerr
    24) requestrr
    25) updatetool
    26) flood
    27) tautulli
    28) prowlarr
    "
    echo -n "Enter the option and press [ENTER]: "
    read OPTION
    echo

    case "$OPTION" in
        1|radarr)
            echo "Setting up radarr.."
            setup_radarr
            ;;
        2|sonarr)
            echo "Setting up sonarr.."
            setup_sonarr
            ;;
        3|sickchill)
            echo "Setting up sickchill.."
            setup_sickchill
            ;;
        4|jackett)
            echo "Setting up jackett.."
            setup_jackett
            ;;
        5|couchpotato)
            echo "Setting up couchpotato.."
            setup_couchpotato
            ;;
        6|nzbget)
            echo "Setting up nzbget.."
            setup_nzbget
            ;;
        7|sabnzbdplus)
            echo "Setting up sabnzbdplus.."
            setup_sabnzbdplus
            ;;
        8|ombi)
            echo "Setting up ombi.."
            setup_ombi
            ;;
        9|lidarr)
            echo "Setting up lidarr.."
            setup_lidarr
            ;;
        10|organizr)
            echo "Setting up organizr.."
            setup_organizr
            ;;
        11|nzbhydra2)
            echo "Setting up nzbhydra2.."
            setup_nzbhydra2
            ;;
        12|bazarr)
            echo "Setting up bazarr.."
            setup_bazarr
            ;;
        13|flexget)
            echo "Setting up flexget.."
            setup_flexget
            ;;
        14|filebot)
            echo "Setting up filebot.."
            setup_filebot
            ;;
        15|synclounge)
            echo "Setting up synclounge.."
            setup_synclounge
            ;;
        16|medusa)
            echo "Setting up medusa.."
            setup_medusa
            ;;
        17|lazylibrarian)
            echo "Setting up lazylibrarian.."
            setup_lazylibrarian
            ;;
        18|pyload)
            echo "Setting up pyload.."
            setup_pyload
            ;;
        19|ngpost)
            echo "Setting up ngpost.."
            setup_ngpost
            ;;
        20|komga)
            echo "Setting up komga.."
            setup_komga
            ;;
        21|ombiv4)
            echo "Setting up ombi v4.."
            setup_ombiv4
            ;;
        22|readarr)
            echo "Setting up readarr.."
            setup_readarr
            ;;
        23|overseerr)
            echo "Setting up overseerr.."
            setup_overseerr
            ;;
        24|requestrr)
            echo "Setting up requestrr.."
            setup_requestrr
            ;;
        25|updatetool)
            echo "Setting up updatetool..."
            setup_updatetool
            ;;
        26|flood)
            echo "Setting up flood..."
            setup_flood
            ;;
        27|tautulli)
            echo "Setting up tautulli..."
            setup_tautulli
            ;;            
        28|prowlarr)
            echo "Setting up prowlarr.."
            setup_prowlarr
            ;;
        *) 
            echo "Sorry, that option doesn't exist, please try again!"
            return 1
        ;;
        esac
}

run_as_root
sed -i 's/www-data/appbox/g' /etc/nginx/nginx.conf
echo -e "\nEnsuring appbox_installer folder exists..."
mkdir -p /home/appbox/appbox_installer
echo -e "\nUpdating apt packages..."
echo >>/etc/apt/apt.conf.d/99verify-peer.conf "Acquire { https::Verify-Peer false }"
if ! apt update >/dev/null 2>&1; then
    echo -e "\napt update failed! Please fix repo issues and try again!"
    exit
fi
until install_prompt ; do : ; done
