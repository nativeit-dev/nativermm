#!/usr/bin/env bash

set -e

: "${NATIVERMM_USER:=nativermm}"
: "${NATIVERMM_PASS:=nativermm}"
: "${POSTGRES_HOST:=nativermm-postgres}"
: "${POSTGRES_PORT:=5432}"
: "${POSTGRES_USER:=nativermm}"
: "${POSTGRES_PASS:=nativermm}"
: "${POSTGRES_DB:=nativermm}"
: "${MESH_SERVICE:=nativermm-meshcentral}"
: "${MESH_WS_URL:=ws://${MESH_SERVICE}:4443}"
: "${MESH_USER:=meshcentral}"
: "${MESH_PASS:=meshcentralpass}"
: "${MESH_HOST:=nativermm-meshcentral}"
: "${API_HOST:=nativermm-backend}"
: "${APP_HOST:=nativermm-frontend}"
: "${REDIS_HOST:=nativermm-redis}"

: "${CERT_PRIV_PATH:=${NATIVERMM_DIR}/certs/privkey.pem}"
: "${CERT_PUB_PATH:=${NATIVERMM_DIR}/certs/fullchain.pem}"

function check_native_ready {
  sleep 15
  until [ -f "${NATIVE_READY_FILE}" ]; do
    echo "waiting for init container to finish install or update..."
    sleep 10
  done
}

# nativermm-init
if [ "$1" = 'nativermm-init' ]; then

  test -f "${NATIVE_READY_FILE}" && rm "${NATIVE_READY_FILE}"

  # copy container data to volume
  rsync -a --no-perms --no-owner --delete --exclude "tmp/*" --exclude "certs/*" --exclude="api/nativermm/private/*" "${NATIVE_TMP_DIR}/" "${NATIVERMM_DIR}/"

  mkdir -p /meshcentral-data
  mkdir -p ${NATIVERMM_DIR}/tmp
  mkdir -p ${NATIVERMM_DIR}/certs
  mkdir -p /mongo/data/db
  mkdir -p /redis/data
  touch /meshcentral-data/.initialized && chown -R 1000:1000 /meshcentral-data
  touch ${NATIVERMM_DIR}/tmp/.initialized && chown -R 1000:1000 ${NATIVERMM_DIR}
  touch ${NATIVERMM_DIR}/certs/.initialized && chown -R 1000:1000 ${NATIVERMM_DIR}/certs
  touch /mongo/data/db/.initialized && chown -R 1000:1000 /mongo/data/db
  touch /redis/data/.initialized && chown -R 1000:1000 /redis/data
  mkdir -p ${NATIVERMM_DIR}/api/nativermm/private/exe
  mkdir -p ${NATIVERMM_DIR}/api/nativermm/private/log
  touch ${NATIVERMM_DIR}/api/nativermm/private/log/django_debug.log
  
  until (echo > /dev/tcp/"${POSTGRES_HOST}"/"${POSTGRES_PORT}") &> /dev/null; do
    echo "waiting for postgresql container to be ready..."
    sleep 5
  done

  until (echo > /dev/tcp/"${MESH_SERVICE}"/4443) &> /dev/null; do
    echo "waiting for meshcentral container to be ready..."
    sleep 5
  done

  # configure django settings
  MESH_TOKEN=$(cat ${NATIVERMM_DIR}/tmp/mesh_token)
  ADMINURL=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 70 | head -n 1)
  DJANGO_SEKRET=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 80 | head -n 1)
  
  localvars="$(cat << EOF
SECRET_KEY = '${DJANGO_SEKRET}'

DEBUG = False

DOCKER_BUILD = True

CERT_FILE = '${CERT_PUB_PATH}'
KEY_FILE = '${CERT_PRIV_PATH}'

EXE_DIR = '/opt/nativermm/api/nativermm/private/exe'
LOG_DIR = '/opt/nativermm/api/nativermm/private/log'

SCRIPTS_DIR = '/opt/nativermm/community-scripts'

ALLOWED_HOSTS = ['${API_HOST}', 'nativermm-backend']

ADMIN_URL = '${ADMINURL}/'

CORS_ORIGIN_WHITELIST = [
    'https://${APP_HOST}'
]

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': '${POSTGRES_DB}',
        'USER': '${POSTGRES_USER}',
        'PASSWORD': '${POSTGRES_PASS}',
        'HOST': '${POSTGRES_HOST}',
        'PORT': '${POSTGRES_PORT}',
    }
}

MESH_USERNAME = '${MESH_USER}'
MESH_SITE = 'https://${MESH_HOST}'
MESH_TOKEN_KEY = '${MESH_TOKEN}'
REDIS_HOST    = '${REDIS_HOST}'
MESH_WS_URL = '${MESH_WS_URL}'
ADMIN_ENABLED = False
EOF
)"

  echo "${localvars}" > ${NATIVERMM_DIR}/api/nativermm/local_settings.py

  # run migrations and init scripts
  python manage.py pre_update_tasks
  python manage.py migrate --no-input
  python manage.py collectstatic --no-input
  python manage.py initial_db_setup
  python manage.py initial_mesh_setup
  python manage.py load_chocos
  python manage.py load_community_scripts
  python manage.py reload_nats
  python manage.py create_natsapi_conf
  python manage.py create_uwsgi_conf
  python manage.py create_installer_user
  python manage.py post_update_tasks

  # create super user 
  echo "Creating dashboard user if it doesn't exist"
  echo "from accounts.models import User; User.objects.create_superuser('${NATIVERMM_USER}', 'admin@example.com', '${NATIVERMM_PASS}') if not User.objects.filter(username='${NATIVERMM_USER}').exists() else 0;" | python manage.py shell

  # chown everything to nativermm user
  echo "Updating permissions on files"
  chown -R "${NATIVE_USER}":"${NATIVE_USER}" "${NATIVERMM_DIR}"

  # create install ready file
  echo "Creating install ready file"
  su -c "echo 'nativermm-init' > ${NATIVE_READY_FILE}" "${NATIVE_USER}"

fi

# backend container
if [ "$1" = 'nativermm-backend' ]; then
  check_native_ready

  uwsgi ${NATIVERMM_DIR}/api/app.ini
fi

if [ "$1" = 'nativermm-celery' ]; then
  check_native_ready
  celery -A nativermm worker -l info
fi

if [ "$1" = 'nativermm-celerybeat' ]; then
  check_native_ready
  test -f "${NATIVERMM_DIR}/api/celerybeat.pid" && rm "${NATIVERMM_DIR}/api/celerybeat.pid"
  celery -A nativermm beat -l info
fi

# websocket container
if [ "$1" = 'nativermm-websockets' ]; then
  check_native_ready

  export DJANGO_SETTINGS_MODULE=nativermm.settings

  daphne nativermm.asgi:application --port 8383 -b 0.0.0.0
fi
