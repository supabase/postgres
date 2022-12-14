ARG VERSION=15.1

FROM postgres:$VERSION

COPY ansible/ /tmp/ansible/

# needed for plv8 Makefile selection
# ENV DOCKER true
ENV CCACHE_DIR=/ccache
ENV PATH=/usr/lib/ccache:$PATH
ENV DEBIAN_FRONTEND noninteractive

RUN apt update && \
    apt install -y ansible sudo git ccache && \
    apt -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade

RUN --mount=type=bind,source=docker/cache,target=/ccache,rw \
    ccache -s && \
    cd /tmp/ansible && \
    ansible-playbook -e '{"async_mode": false}' playbook-docker.yml && \
    apt -y autoremove && \
    apt -y autoclean && \
    ccache -s && \
    apt install -y default-jdk-headless locales && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen && \
    rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/* 

ENV LANGUAGE en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8

COPY ansible/files/pgbouncer_config/pgbouncer_auth_schema.sql /docker-entrypoint-initdb.d/00-schema.sql
COPY ansible/files/stat_extension.sql /docker-entrypoint-initdb.d/01-extension.sql
# COPY ansible/files/sodium_extension.sql /docker-entrypoint-initdb.d/02-sodium-extension.sql
COPY migrations/db/ /docker-entrypoint-initdb.d/

CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]
