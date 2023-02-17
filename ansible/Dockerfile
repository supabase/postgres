# syntax=docker/dockerfile:1.5-labs
ARG postgresql_major=15
ARG postgresql_release=${postgresql_major}.1

# Bump default build arg to build a package from source
# Bump vars.yml to specify runtime package version
ARG sfcgal_release=1.3.10
ARG postgis_release=3.3.2
ARG pgrouting_release=3.4.1
ARG pgtap_release=1.2.0
ARG pg_cron_release=1.4.2
ARG pgaudit_release=1.7.0
ARG pgjwt_release=9742dab1b2f297ad3811120db7b21451bca2d3c9
ARG pgsql_http_release=1.5.0
ARG plpgsql_check_release=2.2.5
ARG pg_safeupdate_release=1.4
ARG timescaledb_release=2.9.1
ARG wal2json_release=2_5
ARG pljava_release=1.6.4
ARG plv8_release=3.1.5
ARG pg_plan_filter_release=5081a7b5cb890876e67d8e7486b6a64c38c9a492
ARG pg_net_release=0.7.1
ARG rum_release=1.3.13
ARG pg_hashids_release=cd0e1b31d52b394a0df64079406a14a4f7387cd6
ARG libsodium_release=1.0.18
ARG pgsodium_release=3.1.5
ARG pg_graphql_release=1.1.0
ARG pg_stat_monitor_release=1.1.1
ARG pg_jsonschema_release=0.1.4
ARG vault_release=0.2.8
ARG groonga_release=12.0.8
ARG pgroonga_release=2.4.0
ARG wrappers_release=0.1.7
ARG hypopg_release=1.3.1
ARG pg_repack_release=1.4.8
ARG pgvector_release=0.4.0

FROM postgres:${postgresql_release} as base
# Redeclare args for use in subsequent stages
ARG TARGETARCH
ARG postgresql_major

FROM base as builder
# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-server-dev-${postgresql_major} \
    build-essential \
    checkinstall \
    cmake \
    && rm -rf /var/lib/apt/lists/*

FROM builder as ccache
# Cache large build artifacts
RUN apt-get update && apt-get install -y --no-install-recommends \
    clang \
    ccache \
    && rm -rf /var/lib/apt/lists/*
ENV CCACHE_DIR=/ccache
ENV PATH=/usr/lib/ccache:$PATH
# Used to update ccache
ARG CACHE_EPOCH

####################
# 01-postgis.yml
####################
FROM ccache as sfcgal
# Download and extract
ARG sfcgal_release
ARG sfcgal_release_checksum
ADD --checksum=${sfcgal_release_checksum} \
    "https://gitlab.com/Oslandia/SFCGAL/-/archive/v${sfcgal_release}/SFCGAL-v${sfcgal_release}.tar.gz" \
    /tmp/sfcgal.tar.gz
RUN tar -xvf /tmp/sfcgal.tar.gz -C /tmp --one-top-level --strip-components 1 && \
    rm -rf /tmp/sfcgal.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcgal-dev \
    libboost-serialization1.74-dev \
    libmpfr-dev \
    libgmp-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/sfcgal/build
RUN cmake ..
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=yes --fstrans=no --backup=no --pakdir=/tmp --requires=libgmpxx4ldbl,libboost-serialization1.74.0,libmpfr6 --nodoc

FROM sfcgal as postgis-source
# Download and extract
ARG postgis_release
ARG postgis_release_checksum
ADD --checksum=${postgis_release_checksum} \
    "https://supabase-public-artifacts-bucket.s3.amazonaws.com/postgis-${postgis_release}.tar.gz" \
    /tmp/postgis.tar.gz
RUN tar -xvf /tmp/postgis.tar.gz -C /tmp && \
    rm -rf /tmp/postgis.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
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
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --requires=libgeos-c1v5,libproj19,libjson-c5,libprotobuf-c1 --nodoc

FROM base as postgis
# Download pre-built packages
RUN apt-get update && apt-get install -y --no-install-recommends --download-only \
    postgresql-${postgresql_major}-postgis-3 \
    && rm -rf /var/lib/apt/lists/*
RUN mv /var/cache/apt/archives/*.deb /tmp/

####################
# 02-pgrouting.yml
####################
FROM ccache as pgrouting
# Download and extract
ARG pgrouting_release
ARG pgrouting_release_checksum
ADD --checksum=${pgrouting_release_checksum} \
    "https://github.com/pgRouting/pgrouting/releases/download/v${pgrouting_release}/pgrouting-${pgrouting_release}.tar.gz" \
    /tmp/pgrouting.tar.gz
RUN tar -xvf /tmp/pgrouting.tar.gz -C /tmp && \
    rm -rf /tmp/pgrouting.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libboost-all-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/pgrouting-${pgrouting_release}/build
RUN cmake -DBUILD_HTML=OFF -DBUILD_DOXY=OFF ..
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --pkgname=pgrouting --pkgversion=${pgrouting_release} --nodoc

####################
# 03-pgtap.yml
####################
FROM builder as pgtap
# Download and extract
ARG pgtap_release
ARG pgtap_release_checksum
ADD --checksum=${pgtap_release_checksum} \
    "https://github.com/theory/pgtap/archive/v${pgtap_release}.tar.gz" \
    /tmp/pgtap.tar.gz
RUN tar -xvf /tmp/pgtap.tar.gz -C /tmp && \
    rm -rf /tmp/pgtap.tar.gz
# Build from source
WORKDIR /tmp/pgtap-${pgtap_release}
RUN make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --nodoc

####################
# 04-pg_cron.yml
####################
FROM ccache as pg_cron
# Download and extract
ARG pg_cron_release
ARG pg_cron_release_checksum
ADD --checksum=${pg_cron_release_checksum} \
    "https://github.com/citusdata/pg_cron/archive/refs/tags/v${pg_cron_release}.tar.gz" \
    /tmp/pg_cron.tar.gz
RUN tar -xvf /tmp/pg_cron.tar.gz -C /tmp && \
    rm -rf /tmp/pg_cron.tar.gz
# Build from source
WORKDIR /tmp/pg_cron-${pg_cron_release}
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --nodoc

####################
# 05-pgaudit.yml
####################
FROM ccache as pgaudit
# Download and extract
ARG pgaudit_release
ARG pgaudit_release_checksum
ADD --checksum=${pgaudit_release_checksum} \
    "https://github.com/pgaudit/pgaudit/archive/refs/tags/${pgaudit_release}.tar.gz" \
    /tmp/pgaudit.tar.gz
RUN tar -xvf /tmp/pgaudit.tar.gz -C /tmp && \
    rm -rf /tmp/pgaudit.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl-dev \
    libkrb5-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/pgaudit-${pgaudit_release}
ENV USE_PGXS=1
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --nodoc

####################
# 06-pgjwt.yml
####################
FROM builder as pgjwt
# Download and extract
ARG pgjwt_release
ADD "https://github.com/michelp/pgjwt.git#${pgjwt_release}" \
    /tmp/pgjwt-${pgjwt_release}
# Build from source
WORKDIR /tmp/pgjwt-${pgjwt_release}
RUN make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --pkgversion=1 --nodoc

####################
# 07-pgsql-http.yml
####################
FROM ccache as pgsql-http
# Download and extract
ARG pgsql_http_release
ARG pgsql_http_release_checksum
ADD --checksum=${pgsql_http_release_checksum} \
    "https://github.com/pramsey/pgsql-http/archive/refs/tags/v${pgsql_http_release}.tar.gz" \
    /tmp/pgsql-http.tar.gz
RUN tar -xvf /tmp/pgsql-http.tar.gz -C /tmp && \
    rm -rf /tmp/pgsql-http.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-gnutls-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/pgsql-http-${pgsql_http_release}
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --nodoc

####################
# 08-plpgsql_check.yml
####################
FROM ccache as plpgsql_check
# Download and extract
ARG plpgsql_check_release
ARG plpgsql_check_release_checksum
ADD --checksum=${plpgsql_check_release_checksum} \
    "https://github.com/okbob/plpgsql_check/archive/refs/tags/v${plpgsql_check_release}.tar.gz" \
    /tmp/plpgsql_check.tar.gz
RUN tar -xvf /tmp/plpgsql_check.tar.gz -C /tmp && \
    rm -rf /tmp/plpgsql_check.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libicu-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/plpgsql_check-${plpgsql_check_release}
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --nodoc

####################
# 09-pg-safeupdate.yml
####################
FROM ccache as pg-safeupdate
# Download and extract
ARG pg_safeupdate_release
ARG pg_safeupdate_release_checksum
ADD --checksum=${pg_safeupdate_release_checksum} \
    "https://github.com/eradman/pg-safeupdate/archive/refs/tags/${pg_safeupdate_release}.tar.gz" \
    /tmp/pg-safeupdate.tar.gz
RUN tar -xvf /tmp/pg-safeupdate.tar.gz -C /tmp && \
    rm -rf /tmp/pg-safeupdate.tar.gz
# Build from source
WORKDIR /tmp/pg-safeupdate-${pg_safeupdate_release}
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --nodoc

####################
# 10-timescaledb.yml
####################
FROM ccache as timescaledb
# Download and extract
ARG timescaledb_release
ARG timescaledb_release_checksum
ADD --checksum=${timescaledb_release_checksum} \
    "https://github.com/timescale/timescaledb/archive/refs/tags/${timescaledb_release}.tar.gz" \
    /tmp/timescaledb.tar.gz
RUN tar -xvf /tmp/timescaledb.tar.gz -C /tmp && \
    rm -rf /tmp/timescaledb.tar.gz
# Build from source
WORKDIR /tmp/timescaledb-${timescaledb_release}/build
RUN cmake -DAPACHE_ONLY=1 ..
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --pkgname=timescaledb --pkgversion=${timescaledb_release} --nodoc

####################
# 11-wal2json.yml
####################
FROM ccache as wal2json
# Download and extract
ARG wal2json_release
ARG wal2json_release_checksum
ADD --checksum=${wal2json_release_checksum} \
    "https://github.com/eulerto/wal2json/archive/refs/tags/wal2json_${wal2json_release}.tar.gz" \
    /tmp/wal2json.tar.gz
RUN tar -xvf /tmp/wal2json.tar.gz -C /tmp --one-top-level --strip-components 1 && \
    rm -rf /tmp/wal2json.tar.gz
# Build from source
WORKDIR /tmp/wal2json
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
ENV version=${wal2json_release}
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --pkgversion="\${version/_/.}" --nodoc

####################
# 12-pljava.yml
####################
FROM builder as pljava-source
# Download and extract
# TODO: revert to using main repo after PG15 support is merged: https://github.com/tada/pljava/pull/413
ARG pljava_release=master
ARG pljava_release_checksum=sha256:e99b1c52f7b57f64c8986fe6ea4a6cc09d78e779c1643db060d0ac66c93be8b6
ADD --checksum=${pljava_release_checksum} \
    "https://github.com/supabase/pljava/archive/refs/heads/${pljava_release}.tar.gz" \
    /tmp/pljava.tar.gz
RUN tar -xvf /tmp/pljava.tar.gz -C /tmp && \
    rm -rf /tmp/pljava.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    maven \
    default-jdk \
    libssl-dev \
    libkrb5-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/pljava-${pljava_release}
RUN mvn -T 1C clean install -Dmaven.test.skip -DskipTests -Dmaven.javadoc.skip=true
# Create debian package
RUN cp pljava-packaging/target/pljava-pg${postgresql_major}.jar /tmp/

FROM base as pljava
# Download pre-built packages
RUN apt-get update && apt-get install -y --no-install-recommends --download-only \
    default-jdk-headless \
    postgresql-${postgresql_major}-pljava \
    && rm -rf /var/lib/apt/lists/*
RUN mv /var/cache/apt/archives/*.deb /tmp/

####################
# 13-plv8.yml
####################
FROM ccache as plv8-source
# Download and extract
ARG plv8_release
ARG plv8_release_checksum
ADD --checksum=${plv8_release_checksum} \
    "https://github.com/plv8/plv8/archive/refs/tags/v${plv8_release}.tar.gz" \
    /tmp/plv8.tar.gz
RUN tar -xvf /tmp/plv8.tar.gz -C /tmp && \
    rm -rf /tmp/plv8.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    pkg-config \
    ninja-build \
    git \
    libtinfo5 \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/plv8-${plv8_release}
ENV DOCKER=1
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --nodoc

FROM scratch as plv8-deb
COPY --from=plv8-source /tmp/*.deb /tmp/

FROM ghcr.io/supabase/plv8:${plv8_release}-pg${postgresql_major} as plv8

####################
# 14-pg_plan_filter.yml
####################
FROM ccache as pg_plan_filter
# Download and extract
ARG pg_plan_filter_release
ADD "https://github.com/pgexperts/pg_plan_filter.git#${pg_plan_filter_release}" \
    /tmp/pg_plan_filter-${pg_plan_filter_release}
# Build from source
WORKDIR /tmp/pg_plan_filter-${pg_plan_filter_release}
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --pkgversion=1 --nodoc

####################
# 15-pg_net.yml
####################
FROM ccache as pg_net
# Download and extract
ARG pg_net_release
ARG pg_net_release_checksum
ADD --checksum=${pg_net_release_checksum} \
    "https://github.com/supabase/pg_net/archive/refs/tags/v${pg_net_release}.tar.gz" \
    /tmp/pg_net.tar.gz
RUN tar -xvf /tmp/pg_net.tar.gz -C /tmp && \
    rm -rf /tmp/pg_net.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-gnutls-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/pg_net-${pg_net_release}
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --requires=libcurl3-gnutls --nodoc

####################
# 16-rum.yml
####################
FROM ccache as rum
# Download and extract
ARG rum_release
ARG rum_release_checksum
ADD --checksum=${rum_release_checksum} \
    "https://github.com/postgrespro/rum/archive/refs/tags/${rum_release}.tar.gz" \
    /tmp/rum.tar.gz
RUN tar -xvf /tmp/rum.tar.gz -C /tmp && \
    rm -rf /tmp/rum.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    systemtap-sdt-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/rum-${rum_release}
ENV USE_PGXS=1
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --nodoc

####################
# 17-pg_hashids.yml
####################
FROM ccache as pg_hashids
# Download and extract
ARG pg_hashids_release
ADD "https://github.com/iCyberon/pg_hashids.git#${pg_hashids_release}" \
    /tmp/pg_hashids-${pg_hashids_release}
# Build from source
WORKDIR /tmp/pg_hashids-${pg_hashids_release}
RUN make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --pkgversion=1 --nodoc

####################
# 18-pgsodium.yml
####################
FROM ccache as libsodium
# Download and extract
ARG libsodium_release
ARG libsodium_release_checksum
ADD --checksum=${libsodium_release_checksum} \
    "https://download.libsodium.org/libsodium/releases/libsodium-${libsodium_release}.tar.gz" \
    /tmp/libsodium.tar.gz
RUN tar -xvf /tmp/libsodium.tar.gz -C /tmp && \
    rm -rf /tmp/libsodium.tar.gz
# Build from source
WORKDIR /tmp/libsodium-${libsodium_release}
RUN ./configure
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
RUN make install

FROM libsodium as pgsodium
# Download and extract
ARG pgsodium_release
ARG pgsodium_release_checksum
ADD --checksum=${pgsodium_release_checksum} \
    "https://github.com/michelp/pgsodium/archive/refs/tags/v${pgsodium_release}.tar.gz" \
    /tmp/pgsodium.tar.gz
RUN tar -xvf /tmp/pgsodium.tar.gz -C /tmp && \
    rm -rf /tmp/pgsodium.tar.gz
# Build from source
WORKDIR /tmp/pgsodium-${pgsodium_release}
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --requires=libsodium23 --nodoc

####################
# 19-pg_graphql.yml
####################
FROM base as pg_graphql
# Download package archive
ARG pg_graphql_release
ADD "https://github.com/supabase/pg_graphql/releases/download/v${pg_graphql_release}/pg_graphql-v${pg_graphql_release}-pg${postgresql_major}-${TARGETARCH}-linux-gnu.deb" \
    /tmp/pg_graphql.deb

####################
# 20-pg_stat_monitor.yml
####################
FROM ccache as pg_stat_monitor
# Download and extract
ARG pg_stat_monitor_release
ARG pg_stat_monitor_release_checksum
ADD --checksum=${pg_stat_monitor_release_checksum} \
    "https://github.com/percona/pg_stat_monitor/archive/refs/tags/${pg_stat_monitor_release}.tar.gz" \
    /tmp/pg_stat_monitor.tar.gz
RUN tar -xvf /tmp/pg_stat_monitor.tar.gz -C /tmp && \
    rm -rf /tmp/pg_stat_monitor.tar.gz
# Build from source
WORKDIR /tmp/pg_stat_monitor-${pg_stat_monitor_release}
ENV USE_PGXS=1
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --nodoc

####################
# 21-auto_explain.yml
####################

####################
# 22-pg_jsonschema.yml
####################
FROM base as pg_jsonschema
# Download package archive
ARG pg_jsonschema_release
ADD "https://github.com/supabase/pg_jsonschema/releases/download/v${pg_jsonschema_release}/pg_jsonschema-v${pg_jsonschema_release}-pg${postgresql_major}-${TARGETARCH}-linux-gnu.deb" \
    /tmp/pg_jsonschema.deb

####################
# 23-vault.yml
####################
FROM builder as vault
# Download and extract
ARG vault_release
ARG vault_release_checksum
ADD --checksum=${vault_release_checksum} \
    "https://github.com/supabase/vault/archive/refs/tags/v${vault_release}.tar.gz" \
    /tmp/vault.tar.gz
RUN tar -xvf /tmp/vault.tar.gz -C /tmp && \
    rm -rf /tmp/vault.tar.gz
# Build from source
WORKDIR /tmp/vault-${vault_release}
RUN make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --nodoc

####################
# 24-pgroonga.yml
####################
FROM ccache as groonga
# Download and extract
ARG groonga_release
ARG groonga_release_checksum
ADD --checksum=${groonga_release_checksum} \
    "https://packages.groonga.org/source/groonga/groonga-${groonga_release}.tar.gz" \
    /tmp/groonga.tar.gz
RUN tar -xvf /tmp/groonga.tar.gz -C /tmp && \
    rm -rf /tmp/groonga.tar.gz
# Build from source
WORKDIR /tmp/groonga-${groonga_release}
RUN ./configure
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=yes --fstrans=no --backup=no --pakdir=/tmp --nodoc

FROM groonga as pgroonga-source
# Download and extract
ARG pgroonga_release
ARG pgroonga_release_checksum
ADD --checksum=${pgroonga_release_checksum} \
    "https://packages.groonga.org/source/pgroonga/pgroonga-${pgroonga_release}.tar.gz" \
    /tmp/pgroonga.tar.gz
RUN tar -xvf /tmp/pgroonga.tar.gz -C /tmp && \
    rm -rf /tmp/pgroonga.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/pgroonga-${pgroonga_release}
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --nodoc

FROM scratch as pgroonga-deb
COPY --from=pgroonga-source /tmp/*.deb /tmp/

FROM base as pgroonga
# Download pre-built packages
ADD "https://packages.groonga.org/debian/groonga-apt-source-latest-bullseye.deb" /tmp/source.deb
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    /tmp/source.deb \
    && rm -rf /var/lib/apt/lists/*
RUN rm /tmp/source.deb
RUN apt-get update && apt-get install -y --no-install-recommends --download-only \
    postgresql-${postgresql_major}-pgdg-pgroonga \
    && rm -rf /var/lib/apt/lists/*
RUN mv /var/cache/apt/archives/*.deb /tmp/

####################
# 25-wrappers.yml
####################
FROM base as wrappers
# Download package archive
ARG wrappers_release
ADD "https://github.com/supabase/wrappers/releases/download/v${wrappers_release}/wrappers-v${wrappers_release}-pg${postgresql_major}-${TARGETARCH}-linux-gnu.deb" \
    /tmp/wrappers.deb

####################
# 26-hypopg.yml
####################
FROM ccache as hypopg
# Download and extract
ARG hypopg_release
ARG hypopg_release_checksum
ADD --checksum=${hypopg_release_checksum} \
    "https://github.com/HypoPG/hypopg/archive/refs/tags/${hypopg_release}.tar.gz" \
    /tmp/hypopg.tar.gz
RUN tar -xvf /tmp/hypopg.tar.gz -C /tmp && \
    rm -rf /tmp/hypopg.tar.gz
# Build from source
WORKDIR /tmp/hypopg-${hypopg_release}
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --nodoc

####################
# 27-pg_repack.yml
####################
FROM ccache as pg_repack
ARG pg_repack_release
ARG pg_repack_release_checksum
ADD --checksum=${pg_repack_release_checksum} \
    "https://github.com/reorg/pg_repack/archive/refs/tags/ver_${pg_repack_release}.tar.gz" \
    /tmp/pg_repack.tar.gz
RUN tar -xvf /tmp/pg_repack.tar.gz -C /tmp && \
    rm -rf /tmp/pg_repack.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    liblz4-dev \
    libz-dev \
    libzstd-dev \
    libreadline-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/pg_repack-ver_${pg_repack_release}
ENV USE_PGXS=1
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --pkgversion=${pg_repack_release} --nodoc

####################
# 28-pgvector.yml
####################
FROM ccache as pgvector
ARG pgvector_release
ARG pgvector_release_checksum
ADD --checksum=${pgvector_release_checksum} \
    "https://github.com/pgvector/pgvector/archive/refs/tags/v${pgvector_release}.tar.gz" \
    /tmp/pgvector.tar.gz
RUN tar -xvf /tmp/pgvector.tar.gz -C /tmp && \
    rm -rf /tmp/pgvector.tar.gz
# Build from source
WORKDIR /tmp/pgvector-${pgvector_release}
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --nodoc

####################
# Collect extension packages
####################
FROM scratch as extensions
COPY --from=postgis-source /tmp/*.deb /tmp/
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
# COPY --from=pljava /tmp/*.deb /tmp/
COPY --from=plv8 /tmp/*.deb /tmp/
COPY --from=pg_plan_filter /tmp/*.deb /tmp/
COPY --from=pg_net /tmp/*.deb /tmp/
COPY --from=rum /tmp/*.deb /tmp/
COPY --from=pgsodium /tmp/*.deb /tmp/
COPY --from=pg_hashids /tmp/*.deb /tmp/
COPY --from=pg_graphql /tmp/*.deb /tmp/
COPY --from=pg_stat_monitor /tmp/*.deb /tmp/
COPY --from=pg_jsonschema /tmp/*.deb /tmp/
COPY --from=vault /tmp/*.deb /tmp/
COPY --from=pgroonga-source /tmp/*.deb /tmp/
COPY --from=wrappers /tmp/*.deb /tmp/
COPY --from=hypopg /tmp/*.deb /tmp/
COPY --from=pg_repack /tmp/*.deb /tmp/
COPY --from=pgvector /tmp/*.deb /tmp/

####################
# Build final image
####################
FROM base as production

# tasks/docker/setup.yml
COPY files/postgresql_config/postgresql.conf.j2 /etc/postgresql/postgresql.conf
COPY files/postgresql_config/pg_hba.conf.j2 /etc/postgresql/pg_hba.conf
COPY files/postgresql_config/pg_ident.conf.j2 /etc/postgresql/pg_ident.conf

# tasks/setup-extensions.yml
COPY --from=extensions /tmp /tmp
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    /tmp/*.deb \
    && rm -rf /var/lib/apt/lists/* /tmp/*

# tasks/docker/finalize.yml
COPY --chown=postgres:postgres files/postgresql_config/postgresql-stdout-log.conf /etc/postgresql/logging.conf
COPY --chown=postgres:postgres files/pgsodium_getkey_urandom.sh.j2 /usr/lib/postgresql/${postgresql_major}/bin/pgsodium_getkey.sh
COPY files/pgbouncer_config/pgbouncer_auth_schema.sql /docker-entrypoint-initdb.d/00-schema.sql
COPY files/stat_extension.sql /docker-entrypoint-initdb.d/01-extension.sql

RUN sed -i "s/#unix_socket_directories = '\/tmp'/unix_socket_directories = '\/var\/run\/postgresql'/g" /etc/postgresql/postgresql.conf && \
    echo "cron.database_name = 'postgres'" >> /etc/postgresql/postgresql.conf && \
    echo "pljava.libjvm_location = '/usr/lib/jvm/java-11-openjdk-${TARGETARCH}/lib/server/libjvm.so'" >> /etc/postgresql/postgresql.conf && \
    echo "pgsodium.getkey_script= '/usr/lib/postgresql/${postgresql_major}/bin/pgsodium_getkey.sh'" >> /etc/postgresql/postgresql.conf && \
    echo 'auto_explain.log_min_duration = 10s' >> /etc/postgresql/postgresql.conf && \
    mkdir -p /etc/postgresql-custom && \
    chown postgres:postgres /etc/postgresql-custom

ENV POSTGRES_HOST=/var/run/postgresql
CMD ["postgres", "-D", "/etc/postgresql"]

HEALTHCHECK --interval=2s --timeout=2s --retries=10 CMD pg_isready -U postgres -h localhost

####################
# Update build cache
####################
FROM ccache as stats
COPY --from=extensions /tmp/*.deb /dev/null
# Additional packages that are separately built from source
# COPY --from=plv8-deb /tmp/*.deb /dev/null
# Cache mount is only populated by docker build --no-cache
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    ccache -s && \
    cp -r /ccache/* /tmp
FROM scratch as buildcache
COPY --from=stats /tmp /
