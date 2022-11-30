#!/usr/bin/env bash

SCRIPT_VERSION="140"
SCRIPT_URL='https://raw.githubusercontent.com/nativeit/nativermm/master/update.sh'
LATEST_SETTINGS_URL='https://raw.githubusercontent.com/nativeit/nativermm/master/api/nativermm/nativermm/settings.py'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
THIS_SCRIPT=$(readlink -f "$0")

SCRIPTS_DIR='/opt/nativermm-community-scripts'
PYTHON_VER='3.10.8'
SETTINGS_FILE='/rmm/api/nativermm/nativermm/settings.py'

TMP_FILE=$(mktemp -p "" "rmmupdate_XXXXXXXXXX")
curl -s -L "${SCRIPT_URL}" > ${TMP_FILE}
NEW_VER=$(grep "^SCRIPT_VERSION" "$TMP_FILE" | awk -F'[="]' '{print $3}')

if [ "${SCRIPT_VERSION}" -ne "${NEW_VER}" ]; then
    printf >&2 "${YELLOW}Old update script detected, downloading and replacing with the latest version...${NC}\n"
    wget -q "${SCRIPT_URL}" -O update.sh
    exec ${THIS_SCRIPT}
fi

rm -f $TMP_FILE

force=false
if [[ $* == *--force* ]]; then
    force=true
fi

if [ $EUID -eq 0 ]; then
    echo -ne "\033[0;31mDo NOT run this script as root. Exiting.\e[0m\n"
    exit 1
fi

sudo apt update

strip="User="
ORIGUSER=$(grep ${strip} /etc/systemd/system/rmm.service | sed -e "s/^${strip}//")

if [ "$ORIGUSER" != "$USER" ]; then
    printf >&2 "${RED}ERROR: You must run this update script from the same user account used during install: ${GREEN}${ORIGUSER}${NC}\n"
    exit 1
fi

TMP_SETTINGS=$(mktemp -p "" "rmmsettings_XXXXXXXXXX")
curl -s -L "${LATEST_SETTINGS_URL}" > ${TMP_SETTINGS}

LATEST_NATIVERMM_VER=$(grep "^NATIVERMM_VERSION" "$TMP_SETTINGS" | awk -F'[= "]' '{print $5}')
CURRENT_NATIVERMM_VER=$(grep "^NATIVERMM_VERSION" "$SETTINGS_FILE" | awk -F'[= "]' '{print $5}')

if [[ "${CURRENT_NATIVERMM_VER}" == "${LATEST_NATIVERMM_VER}" ]] && ! [[ "$force" = true ]]; then
    printf >&2 "${GREEN}Already on latest version. Current version: ${CURRENT_NATIVERMM_VER} Latest version: ${LATEST_NATIVERMM_VER}${NC}\n"
    rm -f $TMP_SETTINGS
    exit 0
fi

LATEST_MESH_VER=$(grep "^MESH_VER" "$TMP_SETTINGS" | awk -F'[= "]' '{print $5}')
LATEST_PIP_VER=$(grep "^PIP_VER" "$TMP_SETTINGS" | awk -F'[= "]' '{print $5}')
NATS_SERVER_VER=$(grep "^NATS_SERVER_VER" "$TMP_SETTINGS" | awk -F'[= "]' '{print $5}')

CURRENT_PIP_VER=$(grep "^PIP_VER" "$SETTINGS_FILE" | awk -F'[= "]' '{print $5}')

cls() {
    printf "\033c"
}


CHECK_NATS_LIMITNOFILE=$(grep LimitNOFILE /etc/systemd/system/nats.service)
if ! [[ $CHECK_NATS_LIMITNOFILE ]]; then
    
    sudo rm -f /etc/systemd/system/nats.service
    
natsservice="$(cat << EOF
[Unit]
Description=NATS Server
After=network.target

[Service]
PrivateTmp=true
Type=simple
ExecStart=/usr/local/bin/nats-server -c /rmm/api/nativermm/nats-rmm.conf
ExecReload=/usr/bin/kill -s HUP \$MAINPID
ExecStop=/usr/bin/kill -s SIGINT \$MAINPID
User=${USER}
Group=www-data
Restart=always
RestartSec=5s
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
)"
echo "${natsservice}" | sudo tee /etc/systemd/system/nats.service > /dev/null
sudo systemctl daemon-reload
fi

rmmconf='/etc/nginx/sites-available/rmm.conf'
CHECK_NATS_WEBSOCKET=$(grep natsws $rmmconf)
if ! [[ $CHECK_NATS_WEBSOCKET ]]; then
echo "Adding nats websocket to nginx config"
echo "$(awk '
  /location \/ {/ {
      print "    location ~ ^/natsws {"
      print "        proxy_pass http://127.0.0.1:9235;"
      print "        proxy_http_version 1.1;"
      print "        proxy_set_header Host $host;"
      print "        proxy_set_header Upgrade $http_upgrade;"
      print "        proxy_set_header Connection \"upgrade\";"
      print "        proxy_set_header X-Forwarded-Host $host:$server_port;"
      print "        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;"
      print "        proxy_set_header X-Forwarded-Proto $scheme;"
      print "    }"
      print "\n"
  }
  { print }
' $rmmconf)" | sudo tee $rmmconf > /dev/null
fi


for i in nginx nats-api nats rmm daphne celery celerybeat
do
printf >&2 "${GREEN}Stopping ${i} service...${NC}\n"
sudo systemctl stop ${i}
done

CHECK_DAPHNE=$(grep v2 /etc/systemd/system/daphne.service)
if ! [[ $CHECK_DAPHNE ]]; then

sudo rm -f /etc/systemd/system/daphne.service

daphneservice="$(cat << EOF
[Unit]
Description=django channels daemon v2
After=network.target

[Service]
User=${USER}
Group=www-data
WorkingDirectory=/rmm/api/nativermm
Environment="PATH=/rmm/api/env/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/rmm/api/env/bin/daphne -u /rmm/daphne.sock nativermm.asgi:application
ExecStartPre=rm -f /rmm/daphne.sock
ExecStartPre=rm -f /rmm/daphne.sock.lock
Restart=always
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF
)"
echo "${daphneservice}" | sudo tee /etc/systemd/system/daphne.service > /dev/null
sudo systemctl daemon-reload
fi

if [ ! -f /etc/apt/sources.list.d/nginx.list ]; then
osname=$(lsb_release -si); osname=${osname^}
osname=$(echo "$osname" | tr  '[A-Z]' '[a-z]')
codename=$(lsb_release -sc)
nginxrepo="$(cat << EOF
deb https://nginx.org/packages/$osname/ $codename nginx
deb-src https://nginx.org/packages/$osname/ $codename nginx
EOF
)"
echo "${nginxrepo}" | sudo tee /etc/apt/sources.list.d/nginx.list > /dev/null
wget -qO - https://nginx.org/packages/keys/nginx_signing.key | sudo apt-key add -
sudo apt update
sudo apt install -y nginx
fi

nginxdefaultconf='/etc/nginx/nginx.conf'
CHECK_NGINX_WORKER_CONN=$(grep "worker_connections 4096" $nginxdefaultconf)
if ! [[ $CHECK_NGINX_WORKER_CONN ]]; then
printf >&2 "${GREEN}Changing nginx worker connections to 4096${NC}\n"
sudo sed -i 's/worker_connections.*/worker_connections 4096;/g' $nginxdefaultconf
fi

CHECK_NGINX_NOLIMIT=$(grep "worker_rlimit_nofile 1000000" $nginxdefaultconf)
if ! [[ $CHECK_NGINX_NOLIMIT ]]; then
sudo sed -i '/worker_rlimit_nofile.*/d' $nginxdefaultconf
printf >&2 "${GREEN}Increasing nginx open file limit${NC}\n"
sudo sed -i '1s/^/worker_rlimit_nofile 1000000;\
/' $nginxdefaultconf
fi

backend_conf='/etc/nginx/sites-available/rmm.conf'
CHECK_NGINX_REUSEPORT=$(grep reuseport $backend_conf)
if ! [[ $CHECK_NGINX_REUSEPORT ]]; then
printf >&2 "${GREEN}Setting nginx reuseport${NC}\n"
sudo sed -i 's/listen 443 ssl;/listen 443 ssl reuseport;/g' $backend_conf
fi

sudo sed -i 's/# server_names_hash_bucket_size.*/server_names_hash_bucket_size 64;/g' $nginxdefaultconf

if ! sudo nginx -t > /dev/null 2>&1; then
sudo nginx -t
echo -ne "\n"
echo -ne "${RED}You have syntax errors in your nginx configs. See errors above. Please fix them and re-run this script.${NC}\n"
echo -ne "${RED}Aborting...${NC}\n"
exit 1
fi

HAS_PY310=$(python3.10 --version | grep ${PYTHON_VER})
if ! [[ $HAS_PY310 ]]; then
printf >&2 "${GREEN}Updating to ${PYTHON_VER}${NC}\n"
sudo apt install -y build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev libsqlite3-dev libbz2-dev
numprocs=$(nproc)
cd ~
wget https://www.python.org/ftp/python/${PYTHON_VER}/Python-${PYTHON_VER}.tgz
tar -xf Python-${PYTHON_VER}.tgz
cd Python-${PYTHON_VER}
./configure --enable-optimizations
make -j $numprocs
sudo make altinstall
cd ~
sudo rm -rf Python-${PYTHON_VER} Python-${PYTHON_VER}.tgz
fi

HAS_LATEST_NATS=$(/usr/local/bin/nats-server -version | grep "${NATS_SERVER_VER}")
if ! [[ $HAS_LATEST_NATS ]]; then
printf >&2 "${GREEN}Updating nats to v${NATS_SERVER_VER}${NC}\n"
nats_tmp=$(mktemp -d -t nats-XXXXXXXXXX)
wget https://github.com/nats-io/nats-server/releases/download/v${NATS_SERVER_VER}/nats-server-v${NATS_SERVER_VER}-linux-amd64.tar.gz -P ${nats_tmp}
tar -xzf ${nats_tmp}/nats-server-v${NATS_SERVER_VER}-linux-amd64.tar.gz -C ${nats_tmp}
sudo rm -f /usr/local/bin/nats-server
sudo mv ${nats_tmp}/nats-server-v${NATS_SERVER_VER}-linux-amd64/nats-server /usr/local/bin/
sudo chmod +x /usr/local/bin/nats-server
sudo chown ${USER}:${USER} /usr/local/bin/nats-server
rm -rf ${nats_tmp}
fi

if [ -d ~/.npm ]; then
sudo rm -rf ~/.npm
fi

if [ -d ~/.cache ]; then
sudo rm -rf ~/.cache
fi

if [ -d ~/.config ]; then
sudo chown -R $USER:$GROUP ~/.config
fi

HAS_NODE16=$(node --version | grep v16)
if ! [[ $HAS_NODE16 ]]; then
printf >&2 "${GREEN}Updating NodeJS to v16${NC}\n"
rm -rf /rmm/web/node_modules
sudo systemctl stop meshcentral
sudo apt remove -y nodejs
sudo rm -rf /usr/lib/node_modules
curl -sL https://deb.nodes