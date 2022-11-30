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
: "${REDIS_HOST:=nativermm-redis}"
: "${API_PORT:=8000}"

: "${CERT_PRIV_PATH:=${NATIVERMM_DIR}/certs/privkey.pem}"
: "${CERT_PUB_PATH:=${NATIVERMM_DIR}/certs/fullchain.pem}"

# Add python venv to path
export PATH="${VIRTUAL_ENV}/bin:$PATH"

function check_native_ready {
  sleep 15
  until [ -f "${NATIVE_READY_FILE}" ]; do
    echo "waiting for init container to finish install or update..."
    sleep 10
  done
}

function django_setup {
  until (echo > /dev/tcp/"${POSTGRES_HOST}"/"${POSTGRES_PORT}") &> /dev/null; do
    echo "waiting for postgresql container to be ready..."
    sleep 5
  done

  until (echo > /dev/tcp/"${MESH_SERVICE}"/4443) &> /dev/null; do
    echo "waiting for meshcentral container to be ready..."
    sleep 5
  done

  echo "setting up django environment"

  # configure django settings
  MESH_TOKEN="$(cat ${NATIVERMM_DIR}/tmp/mesh_token)"

  DJANGO_SEKRET=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 80 | head -n 1)
  
  localvars="$(cat << EOF
SECRET_KEY = '${DJANGO_SEKRET}'

DEBUG = True

DOCKER_BUILD = True

SWAGGER_ENABLED = True

CERT_FILE = '${CERT_PUB_PATH}'
KEY_FILE = '${CERT_PRIV_PATH}'

SCRIPTS_DIR = '/community-scripts'

ALLOWED_HOSTS = ['${API_HOST}', '*']

ADMIN_URL = 'admin/'

CORS_ORIGIN_ALLOW_ALL = True

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
ADMIN_ENABLED = True
EOF
)"

  echo "${localvars}" > ${WORKSPACE_DIR}/api/nativermm/nativermm/local_settings.py

  # run migrations and init scripts
  "${VIRTUAL_ENV}"/bin/python manage.py pre_update_tasks
  "${VIRTUAL_ENV}"/bin/python manage.py migrate --no-input
  "${VIRTUAL_ENV}"/bin/python manage.py collectstatic --no-input
  "${VIRTUAL_ENV}"/bin/python manage.py initial_db_setup
  "${VIRTUAL_ENV}"/bin/python manage.py initial_mesh_setup
  "${VIRTUAL_ENV}"/bin/python manage.py load_chocos
  "${VIRTUAL_ENV}"/bin/python manage.py load_community_scripts
  "${VIRTUAL_ENV}"/bin/python manage.py reload_nats
  "${VIRTUAL_ENV}"/bin/python manage.py create_natsapi_conf
  "${VIRTUAL_ENV}"/bin/python manage.py create_installer_user
  "${VIRTUAL_ENV}"/bin/python manage.py post_update_tasks
  

  # create super user 
  echo "from accounts.models import User; User.objects.create_superuser('${NATIVERMM_USER}', 'admin@example.com', '${NATIVERMM_PASS}') if not User.objects.filter(username='${NATIVERMM_USER}').exists() else 0;" | python manage.py shell
}

if [ "$1" = 'nativermm-init-dev' ]; then

  # make directories if they don't exist
  mkdir -p "${NATIVERMM_DIR}/tmp"

  test -f "${NATIVE_READY_FILE}" && rm "${NATIVE_READY_FILE}"

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

  # setup Python virtual env and install dependencies
  ! test -e "${VIRTUAL_ENV}" && python -m venv ${VIRTUAL_ENV}
  "${VIRTUAL_ENV}"/bin/python -m pip install --upgrade pip
  "${VIRTUAL_ENV}"/bin/pip install --no-cache-dir setuptools wheel
  "${VIRTUAL_ENV}"/bin/pip install --no-cache-dir -r /requirements.txt

  django_setup

  # chown everything to nativermm user
  chown -R "${NATIVE_USER}":"${NATIVE_USER}" "${WORKSPACE_DIR}"
  chown -R "${NATIVE_USER}":"${NATIVE_USER}" "${NATIVERMM_DIR}"

  # create install ready file
  su -c "echo 'nativermm-init' > ${NATIVE_READY_FILE}" "${NATIVE_USER}"
fi

if [ "$1" = 'nativermm-api' ]; then
  check_native_ready
  "${VIRTUAL_ENV}"/bin/python manage.py runserver 0.0.0.0:"${API_PORT}"
fi

if [ "$1" = 'nativermm-celery-dev' ]; then
  check_native_ready
  "${VIRTUAL_ENV}"/bin/celery -A nativermm worker -l debug
fi

if [ "$1" = 'nativermm-celerybeat-dev' ]; then
  check_native_ready
  test -f "${WORKSPACE_DIR}/api/nativermm/celerybeat.pid" && rm "${WORKSPACE_DIR}/api/nativermm/celerybeat.pid"
  "${VIRTUAL_ENV}"/bin/celery -A nativermm beat -l debug
fi

if [ "$1" = 'nativermm-websockets-dev' ]; then
  check_native_ready
  "${VIRTUAL_ENV}"/bin/daphne nativermm.asgi:application --port 8383 -b 0.0.0.0
fi
