# pulls community scripts from git repo
FROM python:3.10.8-slim AS GET_SCRIPTS_STAGE

RUN apt-get update &&
    apt-get install -y --no-install-recommends git &&
    git clone https://github.com/nativeit/community-scripts.git /community-scripts

FROM python:3.10.8-slim

ENV NATIVERMM_DIR /opt/nativermm
ENV NATIVE_READY_FILE ${NATIVERMM_DIR}/tmp/nativermm.ready
ENV WORKSPACE_DIR /workspace
ENV NATIVE_USER native
ENV VIRTUAL_ENV ${WORKSPACE_DIR}/api/nativermm/env
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

EXPOSE 8000 8383 8005

RUN apt-get update &&
    apt-get install -y build-essential

RUN groupadd -g 1000 nativermm &&
    useradd -u 1000 -g 1000 nativermm

# copy community scripts
COPY --from=GET_SCRIPTS_STAGE /community-scripts /community-scripts

# Copy dev python reqs
COPY .devcontainer/requirements.txt /

# Copy docker entrypoint.sh
COPY .devcontainer/entrypoint.sh /
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

WORKDIR ${WORKSPACE_DIR}/api/nativermm
