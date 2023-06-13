ARG postgres_version=15.1.0.83

ARG pgbouncer_release=1.18.0
ARG postgrest_release=10.1.2
ARG gotrue_release=2.47.0
ARG kong_release=2.8.1
ARG adminapi_release=0.44.3
ARG adminmgr_release=0.5.0
ARG vector_release=0.22.3
ARG postgres_exporter_release=0.9.0

FROM supabase/postgres:${postgres_version} as base
ARG TARGETARCH
ARG postgresql_major

FROM base as builder
# Install build dependencies
RUN apt-get update && apt-get install -y \
    postgresql-server-dev-${postgresql_major} \
    build-essential \
    checkinstall \
    pkg-config \
    cmake \
    && rm -rf /var/lib/apt/lists/*

####################
# Install pgbouncer
####################
FROM builder as pgbouncer-source
# Download and extract
ARG pgbouncer_release
ADD "https://www.pgbouncer.org/downloads/files/${pgbouncer_release}/pgbouncer-${pgbouncer_release}.tar.gz" /tmp/pgbouncer.tar.gz
RUN tar -xvf /tmp/pgbouncer.tar.gz -C /tmp && \
    rm -rf /tmp/pgbouncer.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y \
    libevent-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/pgbouncer-${pgbouncer_release}
RUN ./configure --prefix=/usr/local
RUN make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --requires=libevent-2.1-7 --nodoc

FROM base as pgbouncer
# Download pre-built packages
RUN apt-get update && apt-get install -y --no-install-recommends --download-only \
    pgbouncer \
    && rm -rf /var/lib/apt/lists/*
RUN mv /var/cache/apt/archives/*.deb /tmp/

####################
# Install PostgREST
####################
FROM postgrest/postgrest:v${postgrest_release} as pgrst

####################
# Install GoTrue
####################
FROM supabase/gotrue:v${gotrue_release} as gotrue

####################
# Install Kong
####################
FROM base as kong
ARG kong_release
ADD "https://download.konghq.com/gateway-2.x-ubuntu-focal/pool/all/k/kong/kong_${kong_release}_${TARGETARCH}.deb" \
    /tmp/kong.deb

####################
# Install admin api
####################
FROM base as adminapi
ARG adminapi_release
ADD "https://supabase-public-artifacts-bucket.s3.amazonaws.com/supabase-admin-api/v${adminapi_release}/supabase-admin-api_${adminapi_release}_linux_${TARGETARCH}.tar.gz" /tmp/supabase-admin-api.tar.gz
RUN tar -xvf /tmp/supabase-admin-api.tar.gz -C /tmp && \
    rm -rf /tmp/supabase-admin-api.tar.gz

####################
# Install admin mgr
####################
FROM base as adminmgr
ARG adminmgr_release
ADD "https://supabase-public-artifacts-bucket.s3.amazonaws.com/admin-mgr/v${adminmgr_release}/admin-mgr_${adminmgr_release}_linux_${TARGETARCH}.tar.gz" /tmp/admin-mgr.tar.gz
RUN tar -xvf /tmp/admin-mgr.tar.gz -C /tmp && \
    rm -rf /tmp/admin-mgr.tar.gz

####################
# Install Prometheus Exporter
####################
FROM base as exporter
ARG postgres_exporter_release
ADD "https://github.com/prometheus-community/postgres_exporter/releases/download/v${postgres_exporter_release}/postgres_exporter-${postgres_exporter_release}.linux-${TARGETARCH}.tar.gz" /tmp/postgres_exporter.tar.gz
RUN tar -xvf /tmp/postgres_exporter.tar.gz -C /tmp --strip-components 1 && \
    rm -rf /tmp/postgres_exporter.tar.gz

####################
# Install vector
####################
FROM base as vector
ARG vector_release
ADD "https://packages.timber.io/vector/${vector_release}/vector_${vector_release}-1_${TARGETARCH}.deb" /tmp/vector.deb

####################
# Install supervisord
####################
FROM base as supervisor
# Download pre-built packages
RUN apt-get update -y && apt-get install -y --no-install-recommends --download-only \
    supervisor \
    && rm -rf /var/lib/apt/lists/*
RUN mv /var/cache/apt/archives/*.deb /tmp/

####################
# Create the final image for production
####################
FROM base as production

# Copy dependencies from previous build stages
COPY --from=pgbouncer /tmp/*.deb /tmp/
COPY --from=vector /tmp/*.deb /tmp/
COPY --from=kong /tmp/*.deb /tmp/
COPY --from=supervisor /tmp/*.deb /tmp/

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    /tmp/*.deb \
    # For health check
    curl \
    # For parsing init payload
    jq \
    # Security tools
    fail2ban \
    # sudo
    sudo \
    # reading files using cat sucks
    less \
    && rm -rf /var/lib/apt/lists/* /tmp/*

# Copy single binary dependencies
COPY --from=pgrst /bin/postgrest /opt/
COPY --from=gotrue /usr/local/bin/gotrue /opt/gotrue/
COPY --from=gotrue /usr/local/etc/gotrue /opt/gotrue/
COPY --from=adminapi /tmp/supabase-admin-api /opt/
COPY --chown=root:root --from=adminmgr /tmp/admin-mgr /usr/bin/
COPY --from=exporter /tmp/postgres_exporter /opt/postgres_exporter/
COPY docker/all-in-one/opt/postgres_exporter /opt/postgres_exporter/

# Scripts for adminapi
COPY ansible/files/admin_api_scripts /root 
COPY --chown=adminapi:adminapi docker/all-in-one/etc/adminapi /etc/adminapi
COPY docker/all-in-one/etc/sudoers.d /etc/sudoers.d/

# Customizations for pgbouncer
COPY docker/all-in-one/etc/pgbouncer /etc/pgbouncer
COPY docker/all-in-one/etc/pgbouncer-custom /etc/pgbouncer-custom
COPY docker/all-in-one/etc/tmpfiles.d /etc/tmpfiles.d

# Customizations for postgres
COPY --chown=postgres:postgres docker/all-in-one/etc/postgresql/pg_hba.conf /etc/postgresql/
COPY --chown=postgres:postgres docker/all-in-one/etc/postgresql/logging.conf /etc/postgresql/
COPY --chown=postgres:postgres docker/all-in-one/etc/postgresql-custom /etc/postgresql-custom
COPY --chown=postgres:postgres docker/all-in-one/etc/postgresql.schema.sql /etc/postgresql.schema.sql

# Customizations for postgres_exporter
COPY --chown=postgres:postgres docker/all-in-one/opt/postgres_exporter/queries.yml /opt/postgres_exporter/queries.yml

COPY docker/all-in-one/etc/fail2ban/filter.d /etc/fail2ban/filter.d/
COPY docker/all-in-one/etc/fail2ban/jail.d /etc/fail2ban/jail.d/

# Customizations for postgrest
COPY --chown=postgrest:postgrest docker/all-in-one/etc/postgrest/base.conf /etc/postgrest/base.conf
COPY --chown=postgrest:postgrest docker/all-in-one/etc/postgrest/generated.conf /etc/postgrest/generated.conf

# Customizations for gotrue
COPY docker/all-in-one/etc/gotrue.env /etc/gotrue.env

# Customizations for kong
COPY docker/all-in-one/etc/kong/kong.conf /etc/kong/kong.conf
COPY docker/all-in-one/etc/kong/kong.yml /etc/kong/kong.yml

# Customizations for vector
COPY --chown=vector:vector docker/all-in-one/etc/vector/vector.yaml /etc/vector/vector.yaml

# Customizations for supervisor
COPY docker/all-in-one/etc/supervisor /etc/supervisor

# Configure service ports
ENV PGRST_SERVER_PORT=3000
ENV PGRST_ADMIN_SERVER_PORT=3001
EXPOSE ${PGRST_SERVER_PORT}

ENV GOTRUE_SITE_URL=http://localhost:${PGRST_SERVER_PORT}
ENV GOTRUE_API_PORT=9999
EXPOSE ${GOTRUE_API_PORT}

ENV KONG_HTTP_PORT=8000
ENV KONG_HTTPS_PORT=8443
EXPOSE ${KONG_HTTP_PORT} ${KONG_HTTPS_PORT}

ENV ADMIN_API_CERT_DIR=/etc/ssl/adminapi
ENV ADMIN_API_PORT=8085
EXPOSE ${ADMIN_API_PORT}

ENV PGBOUNCER_PORT=6543
EXPOSE ${PGBOUNCER_PORT}

ENV PGEXPORTER_PORT=9187
EXPOSE ${PGEXPORTER_PORT}

ENV VECTOR_API_PORT=9001

# Create system users
RUN useradd --create-home --shell /bin/bash postgrest && \
    useradd --create-home --shell /bin/bash gotrue && \
    useradd --create-home --shell /bin/bash pgbouncer -G postgres,ssl-cert && \
    # root,admin,kong,pgbouncer,postgres,postgrest,systemd-journal,wal-g
    useradd --create-home --shell /bin/bash adminapi -G root,kong,pgbouncer,postgres,postgrest,wal-g && \
    usermod --append --shell /bin/bash -G postgres vector
RUN mkdir -p /etc/wal-g && \
    chown -R adminapi:adminapi /etc/wal-g && \
    chmod g+w /etc/wal-g
RUN mkdir -p /var/log/wal-g && chown -R postgres:postgres /var/log/wal-g && chmod +x /usr/bin/admin-mgr && chmod ug+s /usr/bin/admin-mgr && touch /etc/wal-g/config.json && chown adminapi:adminapi /etc/wal-g/config.json && echo '{}' > /etc/wal-g/config.json
RUN chown -R adminapi:adminapi /etc/adminapi

# Add healthcheck and entrypoint scripts
COPY docker/all-in-one/healthcheck.sh /usr/local/bin/
HEALTHCHECK --interval=3s --timeout=2s --start-period=4s --retries=10 CMD [ "healthcheck.sh" ]

COPY docker/all-in-one/init /init
COPY docker/all-in-one/entrypoint.sh /usr/local/bin/
COPY docker/all-in-one/postgres-entrypoint.sh /usr/local/bin/
COPY docker/all-in-one/shutdown.sh /usr/local/bin/supa-shutdown.sh
ENTRYPOINT [ "entrypoint.sh" ]
