ARG MAJOR=15
ARG MINOR=1

ARG sfcgal_release=1.3.10
ARG postgis_release=3.3.2
ARG pgrouting_release=3.4.1
ARG pgtap_release=1.2.0
ARG pg_cron_release=1.4.2
ARG pgaudit_release=1.7.0
ARG pgjwt_release=master
ARG pgsql_http_release=1.5.0
ARG plpgsql_check_release=2.2.5
ARG pg_safeupdate_release=1.4
ARG timescaledb_release=2.9.1
ARG wal2json_release=2_5
ARG pljava_release=1.6.4
ARG plv8_release=3.1.5
ARG pg_plan_filter_release=master
ARG pg_net_release=0.7
ARG rum_release=1.3.13
ARG pg_hashids_release=master
ARG pg_graphql_release=1.1.0
ARG pg_stat_monitor_release=1.1.1
ARG pg_jsonschema_release=0.1.4
ARG vault_release=0.2.9
ARG pgroonga_release=2.4.0
ARG wrappers_release=0.1.7
ARG hypopg_release=1.3.1
ARG pg_repack_release=1.4.8
ARG pgvector_release=0.4.0

FROM postgres:$MAJOR.$MINOR as base
ARG TARGETARCH

FROM base as builder
ARG MAJOR
# Install build dependencies
RUN apt-get update && apt-get install -y \
    postgresql-server-dev-${MAJOR} \
    build-essential \
    checkinstall \
    cmake \
    && rm -rf /var/lib/apt/lists/*

####################
# 01-postgis.yml
####################
FROM builder as sfcgal
# Download and extract
ARG sfcgal_release
ADD "https://gitlab.com/Oslandia/SFCGAL/-/archive/v${sfcgal_release}/SFCGAL-v${sfcgal_release}.tar.gz" /tmp/sfcgal.tar.gz
RUN tar -xvf /tmp/sfcgal.tar.gz -C /tmp --one-top-level --strip-components 1 && \
    rm -rf /tmp/sfcgal.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y \
    libcgal-dev \
    libboost-all-dev \
    libmpfr-dev \
    libgmp-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/sfcgal/build
RUN cmake ..
RUN make -j$(nproc)
RUN make install

FROM sfcgal as postgis
# Download and extract
ARG postgis_release
ADD "https://supabase-public-artifacts-bucket.s3.amazonaws.com/postgis-${postgis_release}.tar.gz" /tmp/postgis.tar.gz
RUN tar -xvf /tmp/postgis.tar.gz -C /tmp && \
    rm -rf /tmp/postgis.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y \
    protobuf-c-compiler \
    libgeos-dev \
    libproj-dev \
    libgdal-dev \
    libjson-c-dev \
    libxml2-dev \
    libprotobuf-c-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/postgis-${postgis_release}
RUN ./configure --with-sfcgal
RUN make -j$(nproc)
RUN make install
# Create debian package
RUN checkinstall -D --install=no --pakdir=/tmp --nodoc

####################
# 02-pgrouting.yml
####################
FROM builder as pgrouting
# Download and extract
ARG pgrouting_release
ADD "https://github.com/pgRouting/pgrouting/releases/download/v${pgrouting_release}/pgrouting-${pgrouting_release}.tar.gz" /tmp/pgrouting.tar.gz
RUN tar -xvf /tmp/pgrouting.tar.gz -C /tmp && \
    rm -rf /tmp/pgrouting.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y \
    libboost-all-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/pgrouting-${pgrouting_release}/build
RUN cmake -DBUILD_HTML=OFF -DBUILD_DOXY=OFF ..
RUN make -j$(nproc)
RUN make install
# Create debian package
RUN checkinstall -D --install=no --pakdir=/tmp --pkgname=pgrouting --pkgversion=${pgrouting_release} --nodoc

####################
# 03-pgtap.yml
####################
FROM builder as pgtap
# Download and extract
ARG pgtap_release
ADD "https://github.com/theory/pgtap/archive/v${pgtap_release}.tar.gz" /tmp/pgtap.tar.gz
RUN tar -xvf /tmp/pgtap.tar.gz -C /tmp && \
    rm -rf /tmp/pgtap.tar.gz
# Build from source
WORKDIR /tmp/pgtap-${pgtap_release}
RUN make install
# Create debian package
RUN checkinstall -D --install=no --pakdir=/tmp --nodoc

####################
# 04-pg_cron.yml
####################
FROM builder as pg_cron
# Download and extract
ARG pg_cron_release
ADD "https://github.com/citusdata/pg_cron/archive/refs/tags/v${pg_cron_release}.tar.gz" /tmp/pg_cron.tar.gz
RUN tar -xvf /tmp/pg_cron.tar.gz -C /tmp && \
    rm -rf /tmp/pg_cron.tar.gz
# Build from source
WORKDIR /tmp/pg_cron-${pg_cron_release}
RUN make -j$(nproc)
RUN make install
# Create debian package
RUN checkinstall -D --install=no --pakdir=/tmp --nodoc

####################
# 05-pgaudit.yml
####################
FROM builder as pgaudit
# Download and extract
ARG pgaudit_release
ADD "https://github.com/pgaudit/pgaudit/archive/refs/tags/${pgaudit_release}.tar.gz" /tmp/pgaudit.tar.gz
RUN tar -xvf /tmp/pgaudit.tar.gz -C /tmp && \
    rm -rf /tmp/pgaudit.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y \
    libssl-dev \
    libkrb5-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/pgaudit-${pgaudit_release}
ENV USE_PGXS=1
RUN make install
# Create debian package
RUN checkinstall -D --install=no --pakdir=/tmp --nodoc

####################
# 06-pgjwt.yml
####################
FROM builder as pgjwt
# Download and extract
ARG pgjwt_release
ADD "https://github.com/michelp/pgjwt/archive/refs/heads/${pgjwt_release}.tar.gz" /tmp/pgjwt.tar.gz
RUN tar -xvf /tmp/pgjwt.tar.gz -C /tmp && \
    rm -rf /tmp/pgjwt.tar.gz
# Build from source
WORKDIR /tmp/pgjwt-${pgjwt_release}
RUN make install
# Create debian package
RUN checkinstall -D --install=no --pakdir=/tmp --nodoc

####################
# 07-pgsql-http.yml
####################
FROM builder as pgsql-http
# Download and extract
ARG pgsql_http_release
ADD "https://github.com/pramsey/pgsql-http/archive/refs/tags/v${pgsql_http_release}.tar.gz" /tmp/pgsql-http.tar.gz
RUN tar -xvf /tmp/pgsql-http.tar.gz -C /tmp && \
    rm -rf /tmp/pgsql-http.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y \
    libcurl4-gnutls-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/pgsql-http-${pgsql_http_release}
RUN make -j$(nproc)
RUN make install
# Create debian package
RUN checkinstall -D --install=no --pakdir=/tmp --nodoc

####################
# 08-plpgsql_check.yml
####################
FROM builder as plpgsql_check
# Download and extract
ARG plpgsql_check_release
ADD "https://github.com/okbob/plpgsql_check/archive/refs/tags/v${plpgsql_check_release}.tar.gz" /tmp/plpgsql_check.tar.gz
RUN tar -xvf /tmp/plpgsql_check.tar.gz -C /tmp && \
    rm -rf /tmp/plpgsql_check.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y \
    libicu-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/plpgsql_check-${plpgsql_check_release}
RUN make clean
RUN make install
# Create debian package
RUN checkinstall -D --install=no --pakdir=/tmp --nodoc

####################
# 09-pg-safeupdate.yml
####################
FROM builder as pg-safeupdate
# Download and extract
ARG pg_safeupdate_release
ADD "https://github.com/eradman/pg-safeupdate/archive/refs/tags/${pg_safeupdate_release}.tar.gz" /tmp/pg-safeupdate.tar.gz
RUN tar -xvf /tmp/pg-safeupdate.tar.gz -C /tmp && \
    rm -rf /tmp/pg-safeupdate.tar.gz
# Build from source
WORKDIR /tmp/pg-safeupdate-${pg_safeupdate_release}
RUN make
RUN make install
# Create debian package
RUN checkinstall -D --install=no --pakdir=/tmp --nodoc

####################
# 10-timescaledb.yml
####################
FROM builder as timescaledb
# Download and extract
ARG timescaledb_release
ADD "https://github.com/timescale/timescaledb/archive/refs/tags/${timescaledb_release}.tar.gz" /tmp/timescaledb.tar.gz
RUN tar -xvf /tmp/timescaledb.tar.gz -C /tmp && \
    rm -rf /tmp/timescaledb.tar.gz
# Build from source
WORKDIR /tmp/timescaledb-${timescaledb_release}/build
RUN cmake -DAPACHE_ONLY=1 ..
RUN make -j$(nproc)
RUN make install
# Create debian package
RUN checkinstall -D --install=no --pakdir=/tmp --pkgname=timescaledb --pkgversion=${timescaledb_release} --nodoc

####################
# 11-wal2json.yml
####################
FROM builder as wal2json
# Download and extract
ARG wal2json_release
ADD "https://github.com/eulerto/wal2json/archive/refs/tags/wal2json_${wal2json_release}.tar.gz" /tmp/wal2json.tar.gz
RUN tar -xvf /tmp/wal2json.tar.gz -C /tmp --one-top-level --strip-components 1 && \
    rm -rf /tmp/wal2json.tar.gz
# Build from source
WORKDIR /tmp/wal2json
RUN make install
# Create debian package
RUN checkinstall -D --install=no --pakdir=/tmp --pkgversion=${wal2json_release} --nodoc

####################
# 12-pljava.yml
####################
FROM builder as pljava-source
# Download and extract
# TODO: revert to using main repo after PG15 support is merged: https://github.com/tada/pljava/pull/413
ARG pljava_release=master
ADD "https://github.com/supabase/pljava/archive/refs/heads/${pljava_release}.tar.gz" /tmp/pljava.tar.gz
RUN tar -xvf /tmp/pljava.tar.gz -C /tmp && \
    rm -rf /tmp/pljava.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y \
    maven \
    default-jdk \
    libssl-dev \
    libkrb5-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/pljava-${pljava_release}
RUN mvn -T 1C clean install -Dmaven.test.skip -DskipTests -Dmaven.javadoc.skip=true
# Create debian package
RUN cp pljava-packaging/target/pljava-pg${MAJOR}.jar /tmp/

FROM builder as pljava
# Download pre-built packages
RUN apt-get update && apt-get install -y --download-only \
    default-jdk-headless \
    postgresql-${MAJOR}-pljava \
    && rm -rf /var/lib/apt/lists/*
RUN mv /var/cache/apt/archives/*.deb /tmp/

####################
# 13-plv8.yml
####################
FROM builder as plv8
# Download and extract
ARG plv8_release
ADD "https://github.com/plv8/plv8/archive/refs/tags/v${plv8_release}.tar.gz" /tmp/plv8.tar.gz
RUN tar -xvf /tmp/plv8.tar.gz -C /tmp && \
    rm -rf /tmp/plv8.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y \
    libtinfo5 \
    ninja-build \
    clang \
    git \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/plv8-${plv8_release}
ENV DOCKER=true
RUN make
RUN make install
# Create debian package
RUN checkinstall -D --install=no --pakdir=/tmp --nodoc

####################
# 14-pg_plan_filter.yml
####################
FROM builder as pg_plan_filter
# Download and extract
ARG pg_plan_filter_release
ADD "https://github.com/pgexperts/pg_plan_filter/archive/refs/heads/${pg_plan_filter_release}.tar.gz" /tmp/pg_plan_filter.tar.gz
RUN tar -xvf /tmp/pg_plan_filter.tar.gz -C /tmp && \
    rm -rf /tmp/pg_plan_filter.tar.gz
# Build from source
WORKDIR /tmp/pg_plan_filter-${pg_plan_filter_release}
RUN make
RUN make install
# Create debian package
RUN checkinstall -D --install=no --pakdir=/tmp --nodoc

####################
# 15-pg_net.yml
####################
FROM builder as pg_net
# Download and extract
ARG pg_net_release
ADD "https://github.com/supabase/pg_net/archive/refs/tags/v${pg_net_release}.tar.gz" /tmp/pg_net.tar.gz
RUN tar -xvf /tmp/pg_net.tar.gz -C /tmp && \
    rm -rf /tmp/pg_net.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y \
    libcurl4-gnutls-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/pg_net-${pg_net_release}
RUN make
RUN make install
# Create debian package
RUN checkinstall -D --install=no --pakdir=/tmp --nodoc

####################
# 16-rum.yml
####################
FROM builder as rum
# Download and extract
ARG rum_release
ADD "https://github.com/postgrespro/rum/archive/refs/tags/${rum_release}.tar.gz" /tmp/rum.tar.gz
RUN tar -xvf /tmp/rum.tar.gz -C /tmp && \
    rm -rf /tmp/rum.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y \
    systemtap-sdt-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/rum-${rum_release}
ENV USE_PGXS=1
RUN make
RUN make install
# Create debian package
RUN checkinstall -D --install=no --pakdir=/tmp --nodoc

####################
# 17-pg_hashids.yml
####################
FROM builder as pg_hashids
# Download and extract
ARG pg_hashids_release
ADD "https://github.com/iCyberon/pg_hashids/archive/refs/heads/${pg_hashids_release}.tar.gz" /tmp/pg_hashids.tar.gz
RUN tar -xvf /tmp/pg_hashids.tar.gz -C /tmp && \
    rm -rf /tmp/pg_hashids.tar.gz
# Build from source
WORKDIR /tmp/pg_hashids-${pg_hashids_release}
RUN make
RUN make install
# Create debian package
RUN checkinstall -D --install=no --pakdir=/tmp --nodoc

####################
# 18-pgsodium.yml
####################

####################
# 19-pg_graphql.yml
####################
FROM builder as pg_graphql
# Download package archive
ARG pg_graphql_release
ADD "https://github.com/supabase/pg_graphql/releases/download/v${pg_graphql_release}/pg_graphql-v${pg_graphql_release}-pg${MAJOR}-${TARGETARCH}-linux-gnu.deb" /tmp/pg_graphql.deb

####################
# 20-pg_stat_monitor.yml
####################
FROM builder as pg_stat_monitor
# Download and extract
ARG pg_stat_monitor_release
ADD "https://github.com/percona/pg_stat_monitor/archive/refs/tags/${pg_stat_monitor_release}.tar.gz" /tmp/pg_stat_monitor.tar.gz
RUN tar -xvf /tmp/pg_stat_monitor.tar.gz -C /tmp && \
    rm -rf /tmp/pg_stat_monitor.tar.gz
# Build from source
WORKDIR /tmp/pg_stat_monitor-${pg_stat_monitor_release}
ENV USE_PGXS=1
RUN make
RUN make install
# Create debian package
RUN checkinstall -D --install=no --pakdir=/tmp --nodoc

####################
# 21-auto_explain.yml
####################

####################
# 22-pg_jsonschema.yml
####################
FROM builder as pg_jsonschema
# Download package archive
ARG pg_jsonschema_release
ADD "https://github.com/supabase/pg_jsonschema/releases/download/v${pg_jsonschema_release}/pg_jsonschema-v${pg_jsonschema_release}-pg${MAJOR}-${TARGETARCH}-linux-gnu.deb" /tmp/pg_jsonschema.deb

####################
# 23-vault.yml
####################
FROM builder as vault
# Download and extract
ARG vault_release
ADD "https://github.com/supabase/vault/archive/refs/tags/v${vault_release}.tar.gz" /tmp/vault.tar.gz
RUN tar -xvf /tmp/vault.tar.gz -C /tmp && \
    rm -rf /tmp/vault.tar.gz
# Build from source
WORKDIR /tmp/vault-${vault_release}
RUN make
RUN make install
# Create debian package
RUN checkinstall -D --install=no --pakdir=/tmp --nodoc

####################
# 24-pgroonga.yml
####################
FROM builder as groonga
# Download and extract
ARG groonga_release=12.0.8
ADD "https://packages.groonga.org/source/groonga/groonga-${groonga_release}.tar.gz" /tmp/groonga.tar.gz
RUN tar -xvf /tmp/groonga.tar.gz -C /tmp && \
    rm -rf /tmp/groonga.tar.gz
# Build from source
WORKDIR /tmp/groonga-${groonga_release}
RUN ./configure
RUN make -j$(nproc)
RUN make install

FROM groonga as pgroonga-source
# Download and extract
ARG pgroonga_release
ADD "https://packages.groonga.org/source/pgroonga/pgroonga-${pgroonga_release}.tar.gz" /tmp/pgroonga.tar.gz
RUN tar -xvf /tmp/pgroonga.tar.gz -C /tmp && \
    rm -rf /tmp/pgroonga.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/pgroonga-${pgroonga_release}
RUN make -j$(nproc)
RUN make install
# Create debian package
RUN checkinstall -D --install=no --pakdir=/tmp --nodoc

FROM builder as pgroonga
# Download pre-built packages
ADD "https://packages.groonga.org/debian/groonga-apt-source-latest-bullseye.deb" /tmp/source.deb
RUN apt-get update && apt-get install -y \
    /tmp/source.deb \
    && rm -rf /var/lib/apt/lists/*
RUN rm /tmp/source.deb
RUN apt-get update && apt-get install -y --download-only \
    postgresql-${MAJOR}-pgdg-pgroonga \
    && rm -rf /var/lib/apt/lists/*
RUN mv /var/cache/apt/archives/*.deb /tmp/

####################
# 25-wrappers.yml
####################
FROM builder as wrappers
# Download package archive
ARG wrappers_release
ADD "https://github.com/supabase/wrappers/releases/download/v${wrappers_release}/wrappers-v${wrappers_release}-pg${MAJOR}-${TARGETARCH}-linux-gnu.deb" /tmp/wrappers.deb

####################
# 26-hypopg.yml
####################
FROM builder as hypopg
# Download and extract
ARG hypopg_release
ADD "https://github.com/HypoPG/hypopg/archive/refs/tags/${hypopg_release}.tar.gz" /tmp/hypopg.tar.gz
RUN tar -xvf /tmp/hypopg.tar.gz -C /tmp && \
    rm -rf /tmp/hypopg.tar.gz
# Build from source
WORKDIR /tmp/hypopg-${hypopg_release}
RUN make install
# Create debian package
RUN checkinstall -D --install=no --pakdir=/tmp --nodoc

####################
# 27-pg_repack.yml
####################
FROM builder as pg_repack
ARG pg_repack_release
ADD "https://github.com/reorg/pg_repack/archive/refs/tags/ver_${pg_repack_release}.tar.gz" /tmp/pg_repack.tar.gz
RUN tar -xvf /tmp/pg_repack.tar.gz -C /tmp && \
    rm -rf /tmp/pg_repack.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y \
    liblz4-dev \
    libz-dev \
    libzstd-dev \
    libreadline-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/pg_repack-ver_${pg_repack_release}
ENV USE_PGXS=1
RUN make
RUN make install
# Create debian package
RUN checkinstall -D --install=no --pakdir=/tmp --pkgversion=${pg_repack_release} --nodoc

####################
# 28-pgvector.yml
####################
FROM builder as pgvector
ARG pgvector_release
ADD "https://github.com/pgvector/pgvector/archive/refs/tags/v${pgvector_release}.tar.gz" /tmp/pgvector.tar.gz
RUN tar -xvf /tmp/pgvector.tar.gz -C /tmp && \
    rm -rf /tmp/pgvector.tar.gz
# Build from source
WORKDIR /tmp/pgvector-${pgvector_release}
RUN make
RUN make install
# Create debian package
RUN checkinstall -D --install=no --pakdir=/tmp --nodoc

####################
# Build final image
####################
FROM base as production

COPY files/postgresql_config/postgresql.conf.j2 /etc/postgresql/postgresql.conf
COPY files/postgresql_config/pg_hba.conf.j2 /etc/postgresql/pg_hba.conf
COPY files/postgresql_config/pg_ident.conf.j2 /etc/postgresql/pg_ident.conf

# tasks/docker/setup.yml
RUN sed -i "s/#unix_socket_directories = '\/tmp'/unix_socket_directories = '\/var\/run\/postgresql'/g" /etc/postgresql/postgresql.conf

COPY --from=sfcgal /usr/local/lib/libSFCGAL.* /usr/local/lib/
COPY --from=postgis /tmp/*.deb /tmp/
COPY --from=pgrouting /tmp/*.deb /tmp/
COPY --from=pgtap /tmp/*.deb /tmp/
COPY --from=pg_cron /tmp/*.deb /tmp/
COPY --from=pgaudit /tmp/*.deb /tmp/
COPY --from=pgjwt /tmp/*.deb /tmp/
COPY --from=pgsql-http /tmp/*.deb /tmp/
COPY --from=plpgsql_check /tmp/*.deb /tmp/
COPY --from=pg-safeupdate /tmp/*.deb /tmp/
COPY --from=timescaledb /tmp/*.deb /tmp/
COPY --from=wal2json /tmp/*.deb /tmp/
COPY --from=pljava /tmp/*.deb /tmp/
# COPY --from=plv8 /tmp/*.deb /tmp/
COPY --from=pg_plan_filter /tmp/*.deb /tmp/
COPY --from=pg_net /tmp/*.deb /tmp/
COPY --from=rum /tmp/*.deb /tmp/
COPY --from=pg_hashids /tmp/*.deb /tmp/
COPY --from=pg_graphql /tmp/*.deb /tmp/
COPY --from=pg_stat_monitor /tmp/*.deb /tmp/
COPY --from=pg_jsonschema /tmp/*.deb /tmp/
COPY --from=vault /tmp/*.deb /tmp/
COPY --from=pgroonga /tmp/*.deb /tmp/
COPY --from=wrappers /tmp/*.deb /tmp/
COPY --from=hypopg /tmp/*.deb /tmp/
COPY --from=pg_repack /tmp/*.deb /tmp/
COPY --from=pgvector /tmp/*.deb /tmp/

RUN apt-get update && apt-get install -y \
    /tmp/*.deb \
    && rm -rf /var/lib/apt/lists/*

# tasks/docker/finalize.yml
COPY --chown=postgres:postgres files/postgresql_config/postgresql-stdout-log.conf /etc/postgresql/logging.conf
# COPY --chown=postgres:postgres files/pgsodium_getkey_urandom.sh.j2 ${pg_bindir}/pgsodium_getkey.sh
RUN echo "pljava.libjvm_location = '/usr/lib/jvm/java-11-openjdk-${TARGETARCH}/lib/server/libjvm.so'" >> /etc/postgresql/postgresql.conf
RUN echo 'auto_explain.log_min_duration = 10s' >> /etc/postgresql/postgresql.conf
