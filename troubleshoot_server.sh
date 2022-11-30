#!/usr/bin/env bash

SCRIPT_VERSION="70"
SCRIPT_URL='https://raw.githubusercontent.com/nativeit/nativermm/master/install.sh'

sudo apt install -y curl wget dirmngr gnupg lsb-release

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPTS_DIR='/opt/nativermm-community-scripts'
PYTHON_VER='3.10.8'
SETTINGS_FILE='/rmm/api/nativermm/nativermm/settings.py'

TMP_FILE=$(mktemp -p "" "rmminstall_XXXXXXXXXX")
curl -s -L "${SCRIPT_URL}" > ${TMP_FILE}
NEW_VER=$(grep "^SCRIPT_VERSION" "$TMP_FILE" | awk -F'[="]' '{print $3}')

if [ "${SCRIPT_VERSION}" -ne "${NEW_VER}" ]; then
    printf >&2 "${YELLOW}Old install script detected, downloading and replacing with the latest version...${NC}\n"
    wget -q "${SCRIPT_URL}" -O install.sh
    printf >&2 "${YELLOW}Script updated! Please re-run ./install.sh${NC}\n"
    rm -f $TMP_FILE
    exit 1
fi

rm -f $TMP_FILE

arch=$(uname -m)
if [ "$arch" != "x86_64" ]; then
    echo -ne "${RED}ERROR: Only x86_64 arch is supported, not ${arch}${NC}\n"
    exit 1
fi

osname=$(lsb_release -si); osname=${osname^}
osname=$(echo "$osname" | tr  '[A-Z]' '[a-z]')
fullrel=$(lsb_release -sd)
codename=$(lsb_release -sc)
relno=$(lsb_release -sr | cut -d. -f1)
fullrelno=$(lsb_release -sr)

# Fallback if lsb_release -si returns anything else than Ubuntu, Debian or Raspbian
if [ ! "$osname" = "ubuntu" ] && [ ! "$osname" = "debian" ]; then
    osname=$(grep -oP '(?<=^ID=).+' /etc/os-release | tr -d '"')
    osname=${osname^}
fi


# determine system
if ([ "$osname" = "ubuntu" ] && [ "$fullrelno" = "20.04" ]) || ([ "$osname" = "debian" ] && [ $relno -ge 10 ]); then
    echo $fullrel
else
    echo $fullrel
    echo -ne "${RED}Supported versions: Ubuntu 20.04, Debian 10 and 11\n"
    echo -ne "Your system does not appear to be supported${NC}\n"
    exit 1
fi

if [ $EUID -eq 0 ]; then
    echo -ne "${RED}Do NOT run this script as root. Exiting.${NC}\n"
    exit 1
fi

if [[ "$LANG" != *".UTF-8" ]]; then
    printf >&2 "\n${RED}System locale must be ${GREEN}<some language>.UTF-8${RED} not ${YELLOW}${LANG}${NC}\n"
    printf >&2 "${RED}Run the following command and change the default locale to your language of choice${NC}\n\n"
    printf >&2 "${GREEN}sudo dpkg-reconfigure locales${NC}\n\n"
    printf >&2 "${RED}You will need to log out and back in for changes to take effect, then re-run this script.${NC}\n\n"
    exit 1
fi

if ([ "$osname" = "ubuntu" ]); then
    mongodb_repo="deb [arch=amd64] https://repo.mongodb.org/apt/$osname $codename/mongodb-org/4.4 multiverse"
    # there is no bullseye repo yet for mongo so just use buster on debian 11
    elif ([ "$osname" = "debian" ] && [ $relno -eq 11 ]); then
    mongodb_repo="deb [arch=amd64] https://repo.mongodb.org/apt/$osname buster/mongodb-org/4.4 main"
else
    mongodb_repo="deb [arch=amd64] https://repo.mongodb.org/apt/$osname $codename/mongodb-org/4.4 main"
fi

postgresql_repo="deb [arch=amd64] https://apt.postgresql.org/pub/repos/apt/ $codename-pgdg main"


# prevents logging issues with some VPS providers like Vultr if this is a freshly provisioned instance that hasn't been rebooted yet
sudo systemctl restart systemd-journald.service

DJANGO_SEKRET=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 80 | head -n 1)
ADMINURL=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 70 | head -n 1)
MESHPASSWD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 25 | head -n 1)
pgusername=$(cat /dev/urandom | tr -dc 'a-z' | fold -w 8 | head -n 1)
pgpw=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)
meshusername=$(cat /dev/urandom | tr -dc 'a-z' | fold -w 8 | head -n 1)

cls() {
    printf "\033c"
}

print_green() {
    printf >&2 "${GREEN}%0.s-${NC}" {1..80}
    printf >&2 "\n"
    printf >&2 "${GREEN}${1}${NC}\n"
    printf >&2 "${GREEN}%0.s-${NC}" {1..80}
    printf >&2 "\n"
}

cls

while [[ $rmmdomain != *[.]*[.]* ]]
do
    echo -ne "${YELLOW}Enter the subdomain for the backend (e.g. api.example.com)${NC}: "
    read rmmdomain
done

while [[ $frontenddomain != *[.]*[.]* ]]
do
    echo -ne "${YELLOW}Enter the subdomain for the frontend (e.g. rmm.example.com)${NC}: "
    read frontenddomain
done

while [[ $meshdomain != *[.]*[.]* ]]
do
    echo -ne "${YELLOW}Enter the subdomain for meshcentral (e.g. mesh.example.com)${NC}: "
    read meshdomain
done

echo -ne "${YELLOW}Enter the root domain (e.g. example.com or example.co.uk)${NC}: "
read rootdomain

while [[ $letsemail != *[@]*[.]* ]]
do
    echo -ne "${YELLOW}Enter a valid email address for django and meshcentral${NC}: "
    read letsemail
done

# if server is behind NAT we need to add the 3 subdomains to the host file
# so that nginx can properly route between the frontend, backend and meshcentral
# EDIT 8-29-2020
# running this even if server is __not__ behind NAT just to make DNS resolving faster
# this also allows the install script to properly finish even if DNS has not fully propagated
CHECK_HOSTS=$(grep 127.0.1.1 /etc/hosts | grep "$rmmdomain" | grep "$meshdomain" | grep "$frontenddomain")
HAS_11=$(grep 127.0.1.1 /etc/hosts)

if ! [[ $CHECK_HOSTS ]]; then
    print_green 'Adding subdomains to hosts file'
    if [[ $HAS_11 ]]; then
        sudo sed -i "/127.0.1.1/s/$/ ${rmmdomain} ${frontenddomain} ${meshdomain}/" /etc/hosts
    else
        echo "127.0.1.1 ${rmmdomain} ${frontenddomain} ${meshdomain}" | sudo tee --append /etc/hosts > /dev/null
    fi
fi

BEHIND_NAT=false
IPV4=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)
if echo "$IPV4" | grep -qE '^(10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.|192\.168)'; then
    BEHIND_NAT=true
fi

sudo apt install -y software-properties-common
sudo apt update
sudo apt install -y certbot openssl

print_green 'Getting wildcard cert'

sudo certbot certonly --manual -d *.${rootdomain} --agree-tos --no-bootstrap --preferred-challenges dns -m ${letsemail} --no-eff-email
while [[ $? -ne 0 ]]
do
    sudo certbot certonly --manual -d *.${rootdomain} --agree-tos --no-bootstrap --preferred-challenges dns -m ${letsemail} --no-eff-email
done

CERT_PRIV_KEY=/etc/letsencrypt/live/${rootdomain}/privkey.pem
CERT_PUB_KEY=/etc/letsencrypt/live/${rootdomain}/fullchain.pem

sudo chown ${USER}:${USER} -R /etc/letsencrypt

print_green 'Installing Nginx'

wget -qO - https://nginx.org/packages/keys/nginx_signing.key | sudo apt-key add -

nginxrepo="$(cat << EOF
deb https://nginx.org/packages/$osname/ $codename nginx
deb-src https://nginx.org/packages/$osname/ $codename nginx
EOF
)"
echo "${nginxrepo}" | sudo tee /etc/apt/sources.list.d/nginx.list > /dev/null

sudo apt update
sudo apt install -y nginx
sudo systemctl stop nginx

nginxdefaultconf='/etc/nginx/nginx.conf'

nginxconf="$(cat << EOF
worker_rlimit_nofile 1000000;
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
        worker_connections 4096;
}

http {
        sendfile on;
        tcp_nopush on;
        types_hash_max_size 2048;
        server_names_hash_bucket_size 64;
        include /etc/nginx/mime.types;
        default_type application/octet-stream;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers on;
        access_log /var/log/nginx/access.log;
        error_log /var/log/nginx/error.log;
        gzip on;
        include /etc/nginx/conf.d/*.conf;
        include /etc/nginx/sites-enabled/*;
}
EOF
)"
echo "${nginxconf}" | sudo tee $nginxdefaultconf > /dev/null

for i in sites-available sites-enabled
do
sudo mkdir -p /etc/nginx/$i
done

print_green 'Installing NodeJS'

curl -sL https://deb.nodesource.com/setup_16.x | sudo -E bash -
sudo apt update
sudo apt install -y gcc g++ make
sudo apt install -y nodejs
sudo npm install -g npm

print_green 'Installing MongoDB'

wget -qO - https://www.mongodb.org/static/pgp/server-4.4.asc | sudo apt-key add -
echo "$mongodb_repo" | sudo tee /etc/apt/sources.list.d/mongodb-org-4.4.list
sudo apt update
sudo apt install -y mongodb-org
sudo systemctl enable mongod
sudo systemctl restart mongod

print_green "Installing Python ${PYTHON_VER}"

sudo apt install -y build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-de	printf >&2 "\n\n"
else
	printf >&2 "\n\n" | tee -a checklog.log
    echo -ne ${RED}  'celery Service isnt running (Native wont work without this)' | tee -a checklog.log
	printf >&2 "\n\n"

fi

# celerybeat Service
if [ $celerybeatstatus = active ]; then
    echo -ne ${GREEN} Success celerybeat Service is Running | tee -a checklog.log
	printf >&2 "\n\n"
else
	printf >&2 "\n\n" | tee -a checklog.log
    echo -ne ${RED}  'celerybeat Service isnt running (Native wont work without this)' | tee -a checklog.log
	printf >&2 "\n\n"

fi

# nginx Service
if [ $nginxstatus = active ]; then
    echo -ne ${GREEN} Success nginx Service is Running | tee -a checklog.log
	printf >&2 "\n\n"
else
	printf >&2 "\n\n" | tee -a checklog.log
    echo -ne ${RED}  'nginx Service isnt running (Native wont work without this)' | tee -a checklog.log
	printf >&2 "\n\n"

fi

# nats Service
if [ $natsstatus = active ]; then
    echo -ne ${GREEN} Success nats Service is running | tee -a checklog.log
	printf >&2 "\n\n"
else
	printf >&2 "\n\n" | tee -a checklog.log
    echo -ne ${RED}  'nats Service isnt running (Native wont work without this)' | tee -a checklog.log
	printf >&2 "\n\n"

fi

# nats-api Service
if [ $natsapistatus = active ]; then
    echo -ne ${GREEN} Success nats-api Service is running | tee -a checklog.log
	printf >&2 "\n\n"
else
	printf >&2 "\n\n" | tee -a checklog.log
    echo -ne ${RED}  'nats-api Service isnt running (Native wont work without this)' | tee -a checklog.log
	printf >&2 "\n\n"

fi

# meshcentral Service
if [ $meshcentralstatus = active ]; then
    echo -ne ${GREEN} Success meshcentral Service is running | tee -a checklog.log
	printf >&2 "\n\n"
else
	printf >&2 "\n\n" | tee -a checklog.log
    echo -ne ${RED}  'meshcentral Service isnt running (Native wont work without this)' | tee -a checklog.log
	printf >&2 "\n\n"

fi

# mongod Service
if [ $mongodstatus = active ]; then
    echo -ne ${GREEN} Success mongod Service is running | tee -a checklog.log
	printf >&2 "\n\n"
else
	printf >&2 "\n\n" | tee -a checklog.log
    echo -ne ${RED}  'mongod Service isnt running (Native wont work without this)' | tee -a checklog.log
	printf >&2 "\n\n"

fi

# postgresql Service
if [ $postgresqlstatus = active ]; then
    echo -ne ${GREEN} Success postgresql Service is running | tee -a checklog.log
	printf >&2 "\n\n"
else
	printf >&2 "\n\n" | tee -a checklog.log
    echo -ne ${RED}  'postgresql Service isnt running (Native wont work without this)' | tee -a checklog.log
	printf >&2 "\n\n"

fi

# redis-server Service
if [ $redisserverstatus = active ]; then
    echo -ne ${GREEN} Success redis-server Service is running | tee -a checklog.log
	printf >&2 "\n\n"
else
	printf >&2 "\n\n" | tee -a checklog.log
    echo -ne ${RED}  'redis-server Service isnt running (Native wont work without this)' | tee -a checklog.log
	printf >&2 "\n\n"

fi

	echo -ne ${YELLOW} Checking Open Ports | tee -a checklog.log 
	printf >&2 "\n\n"

#Get WAN IP
wanip=$(dig @resolver4.opendns.com myip.opendns.com +short)

echo -ne ${GREEN} WAN IP is $wanip | tee -a checklog.log
printf >&2 "\n\n"

#Check if HTTPs Port is open
if ( nc -zv $wanip 443 2>&1 >/dev/null ); then
    echo -ne ${GREEN} 'HTTPs Port is open' | tee -a checklog.log
	printf >&2 "\n\n"
else
    echo -ne ${RED} 'HTTPs port is closed (you may want this if running locally only)' | tee -a checklog.log
	printf >&2 "\n\n"
fi

	echo -ne ${YELLOW} Checking For Proxy | tee -a checklog.log 
	printf >&2 "\n\n"
	echo -ne ${YELLOW} ......this might take a while!!
	printf >&2 "\n\n"

# Detect Proxy via cert
proxyext=$(openssl s_client -showcerts -servername $remapiip -connect $remapiip:443 2>/dev/null | openssl x509 -inform pem -noout -text)
proxyint=$(openssl s_client -showcerts -servername 127.0.0.1 -connect 127.0.0.1:443 2>/dev/null | openssl x509 -inform pem -noout -text)

if [[ $proxyext == $proxyint ]]; then
    echo -ne ${GREEN} No Proxy detected using Certificate | tee -a checklog.log
	printf >&2 "\n\n"
else
    echo -ne ${RED} Proxy detected using Certificate | tee -a checklog.log
	printf >&2 "\n\n"
fi

# Detect Proxy via IP
if [ $wanip != $remrmmip ]; then
    echo -ne ${RED} Proxy detected using IP | tee -a checklog.log
	printf >&2 "\n\n"
else
    echo -ne ${GREEN} No Proxy detected using IP | tee -a checklog.log
	printf >&2 "\n\n"
fi

	echo -ne ${YELLOW} Checking SSL Certificate is up to date | tee -a checklog.log 
	printf >&2 "\n\n"

#SSL Certificate check
cert=$(sudo certbot certificates)

if [[ "$cert" != *"INVALID"* ]]; then
    echo -ne ${GREEN} SSL Certificate for $domain is fine  | tee -a checklog.log
	printf >&2 "\n\n"

else
    echo -ne ${RED} SSL Certificate has expired or doesnt exist for $domain  | tee -a checklog.log
	printf >&2 "\n\n"
fi

# Get List of Certbot Certificates
sudo certbot certificates | tee -a checklog.log

	echo -ne ${YELLOW} Getting summary output of logs | tee -a checklog.log  

tail /rmm/api/nativermm/nativermm/private/log/django_debug.log  | tee -a checklog.log
	printf >&2 "\n\n"
tail /rmm/api/nativermm/nativermm/private/log/error.log  | tee -a checklog.log
	printf >&2 "\n\n"

printf >&2 "\n\n"
echo -ne ${YELLOW} 
printf >&2 "You will have a log file called checklog.log in the directory you ran this script from\n\n"
echo -ne ${NC}
