# syntax=docker/dockerfile:1.6
ARG postgresql_major=15
ARG postgresql_release=${postgresql_major}.1

# Bump default build arg to build a package from source
# Bump vars.yml to specify runtime package version
ARG sfcgal_release=1.3.10
ARG postgis_release=3.3.2
ARG pgrouting_release=3.4.1
ARG pgtap_release=1.2.0
ARG pg_cron_release=1.6.2
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
ARG pg_net_release=0.9.2
ARG rum_release=1.3.13
ARG pg_hashids_release=cd0e1b31d52b394a0df64079406a14a4f7387cd6
ARG libsodium_release=1.0.18
ARG pgsodium_release=3.1.6
ARG pg_graphql_release=1.5.1
ARG pg_stat_monitor_release=1.1.1
ARG pg_jsonschema_release=0.1.4
ARG pg_repack_release=1.4.8
ARG vault_release=0.2.8
ARG groonga_release=12.0.8
ARG pgroonga_release=2.4.0
ARG wrappers_release=0.4.1
ARG hypopg_release=1.3.1
ARG pgvector_release=0.4.0
ARG pg_tle_release=1.3.2
ARG index_advisor_release=0.2.0
ARG supautils_release=2.5.0
ARG wal_g_release=2.0.1

####################
# Setup Postgres PPA
####################
FROM ubuntu:focal as ppa
# Redeclare args for use in subsequent stages
ARG postgresql_major
RUN apt-get update && apt-get install -y --no-install-recommends \
    gnupg \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*
# Add Postgres PPA
# In the off-chance that the key in the repository expires, it can be replaced by running the following in the repository's root:
#  gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys $NEW_POSTGRESQL_GPG_KEY
#  gpg --export --armor $NEW_POSTGRESQL_GPG_KEY > postgresql.gpg.key
COPY postgresql.gpg.key /tmp/postgresql.gpg.key
RUN apt-key add /tmp/postgresql.gpg.key && \
    echo "deb https://apt-archive.postgresql.org/pub/repos/apt focal-pgdg-archive main" > /etc/apt/sources.list.d/pgdg.list

####################
# Download pre-built postgres
####################
FROM ppa as pg
ARG postgresql_release
# Download .deb packages
RUN apt-get update && apt-get install -y --no-install-recommends --download-only \
    postgresql-${postgresql_major}=${postgresql_release}-1.pgdg20.04+1 \
    && rm -rf /var/lib/apt/lists/*
RUN mv /var/cache/apt/archives/*.deb /tmp/

FROM ppa as pg-dev
ARG postgresql_release
# Download .deb packages
RUN apt-get update && apt-get install -y --no-install-recommends --download-only \
    postgresql-server-dev-${postgresql_major}=${postgresql_release}-1.pgdg20.04+1 \
    && rm -rf /var/lib/apt/lists/*
RUN mv /var/cache/apt/archives/*.deb /tmp/

####################
# Install postgres
####################
FROM ubuntu:focal as base
# Redeclare args for use in subsequent stages
ARG TARGETARCH
ARG postgresql_major

# Install postgres
COPY --from=pg /tmp /tmp
# Ref: https://github.com/docker-library/postgres/blob/master/15/bullseye/Dockerfile#L91
ENV DEBIAN_FRONTEND=noninteractive
RUN set -ex; \
    export PYTHONDONTWRITEBYTECODE=1; \
    apt-get update; \
    apt-get install -y --no-install-recommends /tmp/postgresql-common_*.deb /tmp/postgresql-client-common_*.deb; \
    sed -ri 's/#(create_main_cluster) .*$/\1 = false/' /etc/postgresql-common/createcluster.conf; \
    apt-get install -y --no-install-recommends /tmp/*.deb; \
    rm -rf /var/lib/apt/lists/* /tmp/*; \
    find /usr -name '*.pyc' -type f -exec bash -c 'for pyc; do dpkg -S "$pyc" &> /dev/null || rm -vf "$pyc"; done' -- '{}' +

ENV PATH=$PATH:/usr/lib/postgresql/${postgresql_major}/bin
ENV PGDATA=/var/lib/postgresql/data

# Make the "en_US.UTF-8" locale so postgres will be utf-8 enabled by default
RUN localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LC_CTYPE=C.UTF-8
ENV LC_COLLATE=C.UTF-8

FROM base as builder
# Install build dependencies
COPY --from=pg-dev /tmp /tmp
RUN apt-get update && \
    rm -f /tmp/libssl-dev* && \
    apt-get install -y --no-install-recommends \
    /tmp/*.deb \
    build-essential \
    checkinstall \
    cmake \
    && rm -rf /var/lib/apt/lists/* /tmp/*

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
    "https://supabase-public-artifacts-bucket.s3.amazonaws.com/sfcgal/SFCGAL-v${sfcgal_release}.tar.gz" \
    /tmp/sfcgal.tar.gz
RUN tar -xvf /tmp/sfcgal.tar.gz -C /tmp --one-top-level --strip-components 1 && \
    rm -rf /tmp/sfcgal.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcgal-dev \
    libboost-serialization1.71-dev \
    libmpfr-dev \
    libgmp-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/sfcgal/build
RUN cmake ..
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=yes --fstrans=no --backup=no --pakdir=/tmp --pkgname=sfcgal --pkgversion=${sfcgal_release} --requires=libgmpxx4ldbl,libboost-serialization1.71.0,libmpfr6 --nodoc

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
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --requires=libgeos-c1v5,libproj15,libjson-c4,libprotobuf-c1,libgdal26 --nodoc

FROM ppa as postgis
# Latest available is 3.3.2
ARG postgis_release
# Download pre-built packages
RUN apt-get update && apt-get install -y --no-install-recommends --download-only \
    postgresql-${postgresql_major}-postgis-3=${postgis_release}+dfsg-1.pgdg20.04+1 \
    && rm -rf /var/lib/apt/lists/*
RUN mv /var/cache/apt/archives/*.deb /tmp/

####################
# 02-pgrouting.yml
####################
FROM ccache as pgrouting-source
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

FROM ppa as pgrouting
ARG pgrouting_release
# Download pre-built packages
RUN apt-get update && apt-get install -y --no-install-recommends --download-only \
    postgresql-${postgresql_major}-pgrouting=${pgrouting_release}-1.pgdg20.04+1 \
    && rm -rf /var/lib/apt/lists/*
RUN mv /var/cache/apt/archives/*.deb /tmp/

####################
# 03-pgtap.yml
####################
FROM builder as pgtap-source
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
FROM ccache as pg_cron-source
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
FROM ccache as pgaudit-source
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
FROM builder as pgjwt-source
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
FROM ccache as pgsql-http-source
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
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --requires=libcurl3-gnutls --nodoc

####################
# 08-plpgsql_check.yml
####################
FROM ccache as plpgsql_check-source
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
FROM ccache as pg-safeupdate-source
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
FROM ccache as timescaledb-source
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
FROM ccache as wal2json-source
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
    "https://github.com/supabase/plv8/archive/refs/tags/v${plv8_release}.tar.gz" \
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
    libstdc++-10-dev \
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
FROM ccache as pg_plan_filter-source
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
FROM ccache as pg_net-source
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
FROM ccache as rum-source
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
FROM ccache as pg_hashids-source
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
    "https://supabase-public-artifacts-bucket.s3.amazonaws.com/libsodium/libsodium-${libsodium_release}.tar.gz" \
    /tmp/libsodium.tar.gz
RUN tar -xvf /tmp/libsodium.tar.gz -C /tmp && \
    rm -rf /tmp/libsodium.tar.gz
# Build from source
WORKDIR /tmp/libsodium-${libsodium_release}
RUN ./configure
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
RUN make install

FROM libsodium as pgsodium-source
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
FROM ccache as pg_stat_monitor-source
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
FROM builder as vault-source
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
# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    zlib1g-dev \
    liblz4-dev \
    libzstd-dev \
    libmsgpack-dev \
    libzmq3-dev \
    libevent-dev \
    libmecab-dev \
    rapidjson-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/groonga-${groonga_release}
RUN ./configure
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=yes --fstrans=no --backup=no --pakdir=/tmp --requires=zlib1g,liblz4-1,libzstd1,libmsgpackc2,libzmq5,libevent-2.1-7,libmecab2 --nodoc

FROM groonga as pgroonga-source
# Download and extract
ARG pgroonga_release
ARG pgroonga_release_checksum
ADD --checksum=${pgroonga_release_checksum} \
    "https://packages.groonga.org/source/pgroonga/pgroonga-${pgroonga_release}.tar.gz" \
    /tmp/pgroonga.tar.gz
RUN tar -xvf /tmp/pgroonga.tar.gz -C /tmp && \
    rm -rf /tmp/pgroonga.tar.gz
# Build from source
WORKDIR /tmp/pgroonga-${pgroonga_release}
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --requires=mecab-naist-jdic --nodoc

FROM scratch as pgroonga-deb
COPY --from=pgroonga-source /tmp/*.deb /tmp/

FROM base as pgroonga
# Latest available is 3.0.3
ARG pgroonga_release
# Download pre-built packages
ADD "https://packages.groonga.org/ubuntu/groonga-apt-source-latest-focal.deb" /tmp/source.deb
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    /tmp/source.deb \
    && rm -rf /var/lib/apt/lists/*
RUN rm /tmp/source.deb
RUN apt-get update && apt-get install -y --no-install-recommends --download-only \
    postgresql-${postgresql_major}-pgdg-pgroonga=${pgroonga_release}-1 \
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
FROM ccache as hypopg-source
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
 FROM ccache as pg_repack-source
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
FROM ccache as pgvector-source
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
# 29-pg_tle.yml
####################
FROM ccache as pg_tle-source
ARG pg_tle_release
ARG pg_tle_release_checksum
ADD --checksum=${pg_tle_release_checksum} \
    "https://github.com/aws/pg_tle/archive/refs/tags/v${pg_tle_release}.tar.gz" \
    /tmp/pg_tle.tar.gz
RUN tar -xvf /tmp/pg_tle.tar.gz -C /tmp && \
    rm -rf /tmp/pg_tle.tar.gz
RUN apt-get update && apt-get install -y --no-install-recommends \
    flex \
    libkrb5-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/pg_tle-${pg_tle_release}
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --nodoc

######################
# 30-index_advisor.yml
######################
FROM ccache as index_advisor
ARG index_advisor_release
ARG index_advisor_release_checksum
ADD --checksum=${index_advisor_release_checksum} \
    "https://github.com/olirice/index_advisor/archive/refs/tags/v${index_advisor_release}.tar.gz" \
    /tmp/index_advisor.tar.gz
RUN tar -xvf /tmp/index_advisor.tar.gz -C /tmp && \
    rm -rf /tmp/index_advisor.tar.gz
# Build from source
WORKDIR /tmp/index_advisor-${index_advisor_release}
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --nodoc

####################
# internal/supautils.yml
####################
FROM base as supautils
# Download package archive
ARG supautils_release
# Define checksums for different architectures
ARG supautils_release_arm64_deb_checksum
ARG supautils_release_amd64_deb_checksum

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Set up a script to download the correct package
RUN echo '#!/bin/sh' > /tmp/download_supautils.sh && \
    echo 'set -e' >> /tmp/download_supautils.sh && \
    echo 'if [ "$TARGETARCH" = "amd64" ]; then' >> /tmp/download_supautils.sh && \
    echo '    CHECKSUM="${supautils_release_amd64_deb_checksum}"' >> /tmp/download_supautils.sh && \
    echo '    ARCH="amd64"' >> /tmp/download_supautils.sh && \
    echo 'elif [ "$TARGETARCH" = "arm64" ]; then' >> /tmp/download_supautils.sh && \
    echo '    CHECKSUM="${supautils_release_arm64_deb_checksum}"' >> /tmp/download_supautils.sh && \
    echo '    ARCH="arm64"' >> /tmp/download_supautils.sh && \
    echo 'else' >> /tmp/download_supautils.sh && \
    echo '    echo "Unsupported architecture: $TARGETARCH" >&2' >> /tmp/download_supautils.sh && \
    echo '    exit 1' >> /tmp/download_supautils.sh && \
    echo 'fi' >> /tmp/download_supautils.sh && \
    echo 'CHECKSUM=$(echo $CHECKSUM | sed "s/^sha256://")' >> /tmp/download_supautils.sh && \
    echo 'curl -fsSL -o /tmp/supautils.deb \\' >> /tmp/download_supautils.sh && \
    echo '    "https://github.com/supabase/supautils/releases/download/v${supautils_release}/supautils-v${supautils_release}-pg${postgresql_major}-$ARCH-linux-gnu.deb"' >> /tmp/download_supautils.sh && \
    echo 'echo "$CHECKSUM  /tmp/supautils.deb" | sha256sum -c -' >> /tmp/download_supautils.sh && \
    chmod +x /tmp/download_supautils.sh

# Run the script to download and verify the package
RUN /tmp/download_supautils.sh && rm /tmp/download_supautils.sh

####################
# setup-wal-g.yml
####################
FROM base as walg
ARG wal_g_release
# ADD "https://github.com/wal-g/wal-g/releases/download/v${wal_g_release}/wal-g-pg-ubuntu-20.04-${TARGETARCH}.tar.gz" /tmp/wal-g.tar.gz
RUN arch=$([ "$TARGETARCH" = "arm64" ] && echo "aarch64" || echo "$TARGETARCH") && \
    apt-get update && apt-get install -y --no-install-recommends curl && \
    curl -kL "https://github.com/wal-g/wal-g/releases/download/v${wal_g_release}/wal-g-pg-ubuntu-20.04-${arch}.tar.gz" -o /tmp/wal-g.tar.gz && \
    tar -xvf /tmp/wal-g.tar.gz -C /tmp && \
    rm -rf /tmp/wal-g.tar.gz && \
    mv /tmp/wal-g-pg-ubuntu*20.04-$arch /tmp/wal-g

####################
# Collect extension packages
####################
FROM scratch as extensions
COPY --from=postgis-source /tmp/*.deb /tmp/
COPY --from=pgrouting-source /tmp/*.deb /tmp/
COPY --from=pgtap-source /tmp/*.deb /tmp/
COPY --from=pg_cron-source /tmp/*.deb /tmp/
COPY --from=pgaudit-source /tmp/*.deb /tmp/
COPY --from=pgjwt-source /tmp/*.deb /tmp/
COPY --from=pgsql-http-source /tmp/*.deb /tmp/
COPY --from=plpgsql_check-source /tmp/*.deb /tmp/
COPY --from=pg-safeupdate-source /tmp/*.deb /tmp/
COPY --from=timescaledb-source /tmp/*.deb /tmp/
COPY --from=wal2json-source /tmp/*.deb /tmp/
# COPY --from=pljava /tmp/*.deb /tmp/
COPY --from=plv8 /tmp/*.deb /tmp/
COPY --from=pg_plan_filter-source /tmp/*.deb /tmp/
COPY --from=pg_net-source /tmp/*.deb /tmp/
COPY --from=rum-source /tmp/*.deb /tmp/
COPY --from=pgsodium-source /tmp/*.deb /tmp/
COPY --from=pg_hashids-source /tmp/*.deb /tmp/
COPY --from=pg_graphql /tmp/*.deb /tmp/
COPY --from=pg_stat_monitor-source /tmp/*.deb /tmp/
COPY --from=pg_jsonschema /tmp/*.deb /tmp/
COPY --from=vault-source /tmp/*.deb /tmp/
COPY --from=pgroonga-source /tmp/*.deb /tmp/
COPY --from=wrappers /tmp/*.deb /tmp/
COPY --from=hypopg-source /tmp/*.deb /tmp/
COPY --from=pg_repack-source /tmp/*.deb /tmp/
COPY --from=pgvector-source /tmp/*.deb /tmp/
COPY --from=pg_tle-source /tmp/*.deb /tmp/
COPY --from=index_advisor /tmp/*.deb /tmp/
COPY --from=supautils /tmp/*.deb /tmp/

####################
# Download gosu for easy step-down from root
####################
FROM ubuntu:focal as gosu
ARG TARGETARCH
# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gnupg \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*
# Download binary
ARG GOSU_VERSION=1.16
ARG GOSU_GPG_KEY=B42F6819007F00F88E364FD4036A9C25BF357DD4
ADD https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$TARGETARCH \
    /usr/local/bin/gosu
ADD https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$TARGETARCH.asc \
    /usr/local/bin/gosu.asc
# Verify checksum
RUN gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys $GOSU_GPG_KEY && \
    gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu && \
    gpgconf --kill all && \
    chmod +x /usr/local/bin/gosu

####################
# Build final image
####################
FROM base as production

# Setup extensions
COPY --from=extensions /tmp /tmp
COPY --from=walg /tmp/wal-g /usr/local/bin/

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    /tmp/*.deb \
    # Needed for anything using libcurl
    # https://github.com/supabase/postgres/issues/573
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* /tmp/*

# Initialise configs
COPY --chown=postgres:postgres ansible/files/postgresql_config/postgresql.conf.j2 /etc/postgresql/postgresql.conf
COPY --chown=postgres:postgres ansible/files/postgresql_config/pg_hba.conf.j2 /etc/postgresql/pg_hba.conf
COPY --chown=postgres:postgres ansible/files/postgresql_config/pg_ident.conf.j2 /etc/postgresql/pg_ident.conf
COPY --chown=postgres:postgres ansible/files/postgresql_config/postgresql-stdout-log.conf /etc/postgresql/logging.conf
COPY --chown=postgres:postgres ansible/files/postgresql_config/supautils.conf.j2 /etc/postgresql-custom/supautils.conf
COPY --chown=postgres:postgres ansible/files/postgresql_extension_custom_scripts /etc/postgresql-custom/extension-custom-scripts
COPY --chown=postgres:postgres ansible/files/pgsodium_getkey_urandom.sh.j2 /usr/lib/postgresql/${postgresql_major}/bin/pgsodium_getkey.sh
COPY --chown=postgres:postgres ansible/files/postgresql_config/custom_read_replica.conf.j2 /etc/postgresql-custom/read-replica.conf
COPY --chown=postgres:postgres ansible/files/postgresql_config/custom_walg.conf.j2 /etc/postgresql-custom/wal-g.conf
COPY --chown=postgres:postgres ansible/files/walg_helper_scripts/wal_fetch.sh /home/postgres/wal_fetch.sh
COPY ansible/files/walg_helper_scripts/wal_change_ownership.sh /root/wal_change_ownership.sh

RUN sed -i \
    -e "s|#unix_socket_directories = '/tmp'|unix_socket_directories = '/var/run/postgresql'|g" \
    -e "s|#session_preload_libraries = ''|session_preload_libraries = 'supautils'|g" \
    -e "s|#include = '/etc/postgresql-custom/supautils.conf'|include = '/etc/postgresql-custom/supautils.conf'|g" \
    -e "s|#include = '/etc/postgresql-custom/wal-g.conf'|include = '/etc/postgresql-custom/wal-g.conf'|g" /etc/postgresql/postgresql.conf && \
    echo "pljava.libjvm_location = '/usr/lib/jvm/java-11-openjdk-${TARGETARCH}/lib/server/libjvm.so'" >> /etc/postgresql/postgresql.conf && \
    echo "pgsodium.getkey_script= '/usr/lib/postgresql/${postgresql_major}/bin/pgsodium_getkey.sh'" >> /etc/postgresql/postgresql.conf && \
    useradd --create-home --shell /bin/bash wal-g -G postgres && \
    mkdir -p /etc/postgresql-custom && \
    chown postgres:postgres /etc/postgresql-custom

# Include schema migrations
COPY migrations/db /docker-entrypoint-initdb.d/
COPY ansible/files/pgbouncer_config/pgbouncer_auth_schema.sql /docker-entrypoint-initdb.d/init-scripts/00-schema.sql
COPY ansible/files/stat_extension.sql /docker-entrypoint-initdb.d/migrations/00-extension.sql

# Add upstream entrypoint script
COPY --from=gosu /usr/local/bin/gosu /usr/local/bin/gosu
ADD --chmod=0755 \
    https://github.com/docker-library/postgres/raw/master/15/bullseye/docker-entrypoint.sh \
    /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]

HEALTHCHECK --interval=2s --timeout=2s --retries=10 CMD pg_isready -U postgres -h localhost
STOPSIGNAL SIGINT
EXPOSE 5432

ENV POSTGRES_HOST=/var/run/postgresql
CMD ["postgres", "-D", "/etc/postgresql"]

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
