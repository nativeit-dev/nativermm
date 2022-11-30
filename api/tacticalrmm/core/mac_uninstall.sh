i-de	printf >&2 "\n\n"
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
