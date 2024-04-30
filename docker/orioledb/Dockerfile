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
ARG pg_net_release=0.7.1
ARG rum_release=1.3.13
ARG pg_hashids_release=cd0e1b31d52b394a0df64079406a14a4f7387cd6
ARG libsodium_release=1.0.18
ARG pgsodium_release=3.1.6
ARG pg_graphql_release=1.5.1
ARG pg_stat_monitor_release=1.1.1
ARG pg_jsonschema_release=0.2.0
ARG pg_repack_release=1.4.8
ARG vault_release=0.2.8
ARG groonga_release=12.0.8
ARG pgroonga_release=2.4.0
ARG wrappers_release=0.2.0
ARG hypopg_release=1.3.1
ARG pgvector_release=0.4.0
ARG pg_tle_release=1.3.2
ARG index_advisor_release=0.2.0
ARG supautils_release=2.2.0
ARG wal_g_release=2.0.1

####################
# Install postgres
####################
FROM orioledb/orioledb:latest-pg${postgresql_major}-ubuntu as base
# Redeclare args for use in subsequent stages
ARG TARGETARCH
ARG postgresql_major

ENV PATH=$PATH:/usr/lib/postgresql/${postgresql_major}/bin
ENV PGDATA=/var/lib/postgresql/data

# Make the "en_US.UTF-8" locale so postgres will be utf-8 enabled by default
# RUN localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LC_CTYPE=C.UTF-8
ENV LC_COLLATE=C

FROM base as builder
# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
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

FROM builder as rust-toolchain
ENV PATH=/root/.cargo/bin:$PATH
RUN apt-get update && apt-get install -y --no-install-recommends curl pkg-config && \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal --default-toolchain stable && \
    rustup --version && \
    rustc --version && \
    cargo --version

RUN cargo install cargo-pgrx --version 0.10.2 --locked
RUN cargo pgrx init --pg${postgresql_major} $(which pg_config)

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
# error: redefinition of typedef 'snapshot_hook_type' is a C11 feature [-Werror,-Wtypedef-redefinition]
RUN sed -i -e "s|-std=c99|-std=c11|g" Makefile
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
# error: too few arguments to function ‘table_tuple_update’
# error: too few arguments to function ‘table_tuple_delete’
RUN sed -i \
    -e "1981s|);|, NULL);|g" \
    -e "2567s|);|, NULL);|g" \
    ../src/nodes/hypertable_modify.c
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
RUN sed -i \
    # error: typedef redefinition with different types ('struct SortTuple' vs 'struct SortTuple')
    -e "183s|^|// |g" \
    -e "184s|^|// |g" \
    -e "185s|^|// |g" \
    -e "186s|^|// |g" \
    -e "187s|^|// |g" \
    -e "188s|^|// |g" \
    -e "189s|^|// |g" \
    # error: static declaration of 'tuplesort_begin_common' follows non-static declaration
    -e "621s|static ||g" \
    # error: static declaration of 'tuplesort_begin_common' follows non-static declaration
    -e "846s|static ||g" \
    # error: static declaration of 'tuplesort_gettuple_common' follows non-static declaration
    -e "2308s|static ||g" \
    src/tuplesort15.c
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
FROM rust-toolchain as pg_graphql-source
# Download and extract
ARG pg_graphql_release
ARG pg_graphql_release_checksum
ADD --checksum=${pg_graphql_release_checksum} \
    "https://github.com/supabase/pg_graphql/archive/refs/tags/v${pg_graphql_release}.tar.gz" \
    /tmp/pg_graphql.tar.gz
RUN tar -xvf /tmp/pg_graphql.tar.gz -C /tmp && \
    rm -rf /tmp/pg_graphql.tar.gz
WORKDIR /tmp/pg_graphql-${pg_graphql_release}
RUN cargo pgrx package --no-default-features --features pg${postgresql_major}

# Create installable package
RUN mkdir archive
RUN cp target/release/pg_graphql-pg${postgresql_major}/usr/local/share/postgresql/extension/pg_graphql* archive
RUN cp target/release/pg_graphql-pg${postgresql_major}/usr/local/lib/postgresql/pg_graphql.so archive

# name of the package directory before packaging
ENV package_dir=pg_graphql-v${pg_graphql_release}-pg${postgresql_major}-${TARGETARCH}-linux-gnu

## Copy files into directory structure
RUN mkdir -p ${package_dir}/usr/lib/postgresql/lib
RUN mkdir -p ${package_dir}/var/lib/postgresql/extension
RUN cp archive/*.so ${package_dir}/usr/lib/postgresql/lib
RUN cp archive/*.control ${package_dir}/var/lib/postgresql/extension
RUN cp archive/*.sql ${package_dir}/var/lib/postgresql/extension

# symlinks to Copy files into directory structure
RUN mkdir -p ${package_dir}/usr/local/lib/postgresql
WORKDIR ${package_dir}/usr/local/lib/postgresql
RUN cp -s ../../../lib/postgresql/lib/*.so .
WORKDIR ../../../../..

RUN mkdir -p ${package_dir}/usr/local/share/postgresql/extension
WORKDIR ${package_dir}/usr/local/share/postgresql/extension
RUN cp -s ../../../../../var/lib/postgresql/extension/pg_graphql.control .
RUN cp -s ../../../../../var/lib/postgresql/extension/pg_graphql*.sql .
WORKDIR ../../../../../..

RUN mkdir -p ${package_dir}/DEBIAN
RUN touch ${package_dir}/DEBIAN/control
RUN echo 'Package: pg-graphql' >> ${package_dir}/DEBIAN/control
RUN echo 'Version:' ${pg_graphql_release} >> ${package_dir}/DEBIAN/control
RUN echo "Architecture: ${TARGETARCH}" >> ${package_dir}/DEBIAN/control
RUN echo 'Maintainer: supabase' >> ${package_dir}/DEBIAN/control
RUN echo 'Description: A PostgreSQL extension' >> ${package_dir}/DEBIAN/control

# Create deb package
RUN chown -R root:root ${package_dir}
RUN chmod -R 00755 ${package_dir}
RUN dpkg-deb --build --root-owner-group ${package_dir}
RUN cp ./*.deb /tmp/pg_graphql.deb

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
# 21-auto_explain.yml
####################

####################
# 22-pg_jsonschema.yml
####################
FROM rust-toolchain as pg_jsonschema-source
# Download and extract
ARG pg_jsonschema_release
ARG pg_jsonschema_release_checksum
ADD --checksum=${pg_jsonschema_release_checksum} \
    "https://github.com/supabase/pg_jsonschema/archive/refs/tags/v${pg_jsonschema_release}.tar.gz" \
    /tmp/pg_jsonschema.tar.gz
RUN tar -xvf /tmp/pg_jsonschema.tar.gz -C /tmp && \
    rm -rf /tmp/pg_jsonschema.tar.gz
WORKDIR /tmp/pg_jsonschema-${pg_jsonschema_release}
RUN cargo pgrx package --no-default-features --features pg${postgresql_major}

# Create installable package
RUN mkdir archive
RUN cp target/release/pg_jsonschema-pg${postgresql_major}/usr/local/share/postgresql/extension/pg_jsonschema* archive
RUN cp target/release/pg_jsonschema-pg${postgresql_major}/usr/local/lib/postgresql/pg_jsonschema.so archive

# name of the package directory before packaging
ENV package_dir=pg_jsonschema-v${pg_jsonschema_release}-pg${postgresql_major}-${TARGETARCH}-linux-gnu

## Copy files into directory structure
RUN mkdir -p ${package_dir}/usr/lib/postgresql/lib
RUN mkdir -p ${package_dir}/var/lib/postgresql/extension
RUN cp archive/*.so ${package_dir}/usr/lib/postgresql/lib
RUN cp archive/*.control ${package_dir}/var/lib/postgresql/extension
RUN cp archive/*.sql ${package_dir}/var/lib/postgresql/extension

# symlinks to Copy files into directory structure
RUN mkdir -p ${package_dir}/usr/local/lib/postgresql
WORKDIR ${package_dir}/usr/local/lib/postgresql
RUN cp -s ../../../lib/postgresql/lib/*.so .
WORKDIR ../../../../..

RUN mkdir -p ${package_dir}/usr/local/share/postgresql/extension
WORKDIR ${package_dir}/usr/local/share/postgresql/extension

RUN cp -s ../../../../../var/lib/postgresql/extension/pg_jsonschema.control .
RUN cp -s ../../../../../var/lib/postgresql/extension/pg_jsonschema*.sql .
WORKDIR ../../../../../..

RUN mkdir -p ${package_dir}/DEBIAN
RUN touch ${package_dir}/DEBIAN/control
RUN echo 'Package: pg-jsonschema' >> ${package_dir}/DEBIAN/control
RUN echo 'Version:' ${pg_jsonschema_release} >> ${package_dir}/DEBIAN/control
RUN echo "Architecture: ${TARGETARCH}" >> ${package_dir}/DEBIAN/control
RUN echo 'Maintainer: supabase' >> ${package_dir}/DEBIAN/control
RUN echo 'Description: A PostgreSQL extension' >> ${package_dir}/DEBIAN/control

# Create deb package
RUN chown -R root:root ${package_dir}
RUN chmod -R 00755 ${package_dir}
RUN dpkg-deb --build --root-owner-group ${package_dir}
RUN cp ./*.deb /tmp/pg_jsonschema.deb

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

####################
# 25-wrappers.yml
####################
FROM rust-toolchain as wrappers-source
# Required by wrappers 0.2.0
RUN cargo install cargo-pgrx --version 0.11.0 --locked
RUN cargo pgrx init --pg${postgresql_major} $(which pg_config)
# Download and extract
ARG wrappers_release
ARG wrappers_release_checksum
ADD --checksum=${wrappers_release_checksum} \
    "https://github.com/supabase/wrappers/archive/refs/tags/v${wrappers_release}.tar.gz" \
    /tmp/wrappers.tar.gz
RUN tar -xvf /tmp/wrappers.tar.gz -C /tmp && \
    rm -rf /tmp/wrappers.tar.gz
WORKDIR /tmp/wrappers-${wrappers_release}/wrappers
RUN cargo pgrx package --no-default-features --features pg${postgresql_major},all_fdws

ENV extension_dir=target/release/wrappers-pg${postgresql_major}/usr/local/share/postgresql/extension

# copy schema file to version update sql files
# Note: some version numbers may be skipped
RUN cp ${extension_dir}/wrappers--${wrappers_release}.sql ${extension_dir}/wrappers--0.1.6--${wrappers_release}.sql
RUN cp ${extension_dir}/wrappers--${wrappers_release}.sql ${extension_dir}/wrappers--0.1.7--${wrappers_release}.sql
RUN cp ${extension_dir}/wrappers--${wrappers_release}.sql ${extension_dir}/wrappers--0.1.8--${wrappers_release}.sql
RUN cp ${extension_dir}/wrappers--${wrappers_release}.sql ${extension_dir}/wrappers--0.1.9--${wrappers_release}.sql
RUN cp ${extension_dir}/wrappers--${wrappers_release}.sql ${extension_dir}/wrappers--0.1.10--${wrappers_release}.sql
RUN cp ${extension_dir}/wrappers--${wrappers_release}.sql ${extension_dir}/wrappers--0.1.11--${wrappers_release}.sql
RUN cp ${extension_dir}/wrappers--${wrappers_release}.sql ${extension_dir}/wrappers--0.1.14--${wrappers_release}.sql
RUN cp ${extension_dir}/wrappers--${wrappers_release}.sql ${extension_dir}/wrappers--0.1.15--${wrappers_release}.sql
RUN cp ${extension_dir}/wrappers--${wrappers_release}.sql ${extension_dir}/wrappers--0.1.16--${wrappers_release}.sql
RUN cp ${extension_dir}/wrappers--${wrappers_release}.sql ${extension_dir}/wrappers--0.1.17--${wrappers_release}.sql
RUN cp ${extension_dir}/wrappers--${wrappers_release}.sql ${extension_dir}/wrappers--0.1.18--${wrappers_release}.sql

# Create installable package
RUN mkdir archive
RUN cp target/release/wrappers-pg${postgresql_major}/usr/local/share/postgresql/extension/wrappers* archive
RUN cp target/release/wrappers-pg${postgresql_major}/usr/local/lib/postgresql/wrappers-${wrappers_release}.so archive

# name of the package directory before packaging
ENV package_dir=wrappers-v${wrappers_release}-pg${postgresql_major}-${TARGETARCH}-linux-gnu

## Copy files into directory structure
RUN mkdir -p ${package_dir}/usr/lib/postgresql/lib
RUN mkdir -p ${package_dir}/var/lib/postgresql/extension
RUN cp archive/*.so ${package_dir}/usr/lib/postgresql/lib
RUN cp archive/*.control ${package_dir}/var/lib/postgresql/extension
RUN cp archive/*.sql ${package_dir}/var/lib/postgresql/extension

# symlinks to Copy files into directory structure
RUN mkdir -p ${package_dir}/usr/local/lib/postgresql
WORKDIR ${package_dir}/usr/local/lib/postgresql
RUN cp -s ../../../lib/postgresql/lib/*.so .
WORKDIR ../../../../..

RUN mkdir -p ${package_dir}/usr/local/share/postgresql/extension
WORKDIR ${package_dir}/usr/local/share/postgresql/extension

RUN cp -s ../../../../../var/lib/postgresql/extension/wrappers.control .
RUN cp -s ../../../../../var/lib/postgresql/extension/wrappers*.sql .
WORKDIR ../../../../../..

RUN mkdir -p ${package_dir}/DEBIAN
RUN touch ${package_dir}/DEBIAN/control
RUN echo 'Package: wrappers' >> ${package_dir}/DEBIAN/control
RUN echo 'Version:' ${wrappers_release} >> ${package_dir}/DEBIAN/control
RUN echo "Architecture: ${TARGETARCH}" >> ${package_dir}/DEBIAN/control
RUN echo 'Maintainer: supabase' >> ${package_dir}/DEBIAN/control
RUN echo 'Description: A PostgreSQL extension' >> ${package_dir}/DEBIAN/control

# Create deb package
RUN chown -R root:root ${package_dir}
RUN chmod -R 00755 ${package_dir}
RUN dpkg-deb --build --root-owner-group ${package_dir}
RUN cp ./*.deb /tmp/wrappers.deb

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
# error: the clang compiler does not support '-march=native'
RUN sed -i -e "s|-march=native||g" Makefile
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
FROM ccache as supautils-source
ARG supautils_release
ARG supautils_release_checksum
ADD --checksum=${supautils_release_checksum} \
    "https://github.com/supabase/supautils/archive/refs/tags/v${supautils_release}.tar.gz" \
    /tmp/supautils.tar.gz
RUN tar -xvf /tmp/supautils.tar.gz -C /tmp && \
    rm -rf /tmp/supautils.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libicu-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/supautils-${supautils_release}
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --nodoc

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
COPY --from=pg_graphql-source /tmp/*.deb /tmp/
COPY --from=pg_stat_monitor-source /tmp/*.deb /tmp/
COPY --from=pg_jsonschema-source /tmp/*.deb /tmp/
COPY --from=vault-source /tmp/*.deb /tmp/
COPY --from=pgroonga-source /tmp/*.deb /tmp/
COPY --from=wrappers-source /tmp/*.deb /tmp/
COPY --from=hypopg-source /tmp/*.deb /tmp/
COPY --from=pg_repack-source /tmp/*.deb /tmp/
COPY --from=pgvector-source /tmp/*.deb /tmp/
COPY --from=pg_tle-source /tmp/*.deb /tmp/
COPY --from=index_advisor /tmp/*.deb /tmp/
COPY --from=supautils-source /tmp/*.deb /tmp/

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
    -e "s|shared_preload_libraries = '\(.*\)'|shared_preload_libraries = '\1, orioledb'|g" \
    -e "s|#max_wal_size = 1GB|max_wal_size = 8GB|g" \
    -e "s|#include = '/etc/postgresql-custom/supautils.conf'|include = '/etc/postgresql-custom/supautils.conf'|g" \
    -e "s|#include = '/etc/postgresql-custom/wal-g.conf'|include = '/etc/postgresql-custom/wal-g.conf'|g" /etc/postgresql/postgresql.conf && \
    echo "cron.database_name = 'postgres'" >> /etc/postgresql/postgresql.conf && \
    echo "pljava.libjvm_location = '/usr/lib/jvm/java-11-openjdk-${TARGETARCH}/lib/server/libjvm.so'" >> /etc/postgresql/postgresql.conf && \
    echo "pgsodium.getkey_script= '/usr/lib/postgresql/${postgresql_major}/bin/pgsodium_getkey.sh'" >> /etc/postgresql/postgresql.conf && \
    echo 'auto_explain.log_min_duration = 10s' >> /etc/postgresql/postgresql.conf && \
    echo "orioledb.main_buffers = 1GB" >> /etc/postgresql/postgresql.conf && \
    echo "orioledb.undo_buffers = 256MB" >> /etc/postgresql/postgresql.conf && \
    useradd --create-home --shell /bin/bash wal-g -G postgres && \
    mkdir -p /etc/postgresql-custom && \
    chown postgres:postgres /etc/postgresql-custom

# Include schema migrations
COPY migrations/db /docker-entrypoint-initdb.d/
COPY ansible/files/pgbouncer_config/pgbouncer_auth_schema.sql /docker-entrypoint-initdb.d/init-scripts/00-schema.sql
COPY ansible/files/stat_extension.sql /docker-entrypoint-initdb.d/migrations/00-extension.sql

# Patch upstream entrypoint script
RUN sed -i \
    -e "s|su-exec|gosu|g" \
    -e "s|PGHOST= PGHOSTADDR=|PGHOST=\$POSTGRES_HOST|g" \
    /usr/local/bin/docker-entrypoint.sh && \
    mv /usr/local/bin/docker-entrypoint.sh /usr/local/bin/orioledb-entrypoint.sh

COPY docker/orioledb/entrypoint.sh /usr/local/bin/docker-entrypoint.sh

HEALTHCHECK --interval=2s --timeout=2s --retries=10 CMD pg_isready -U postgres -h localhost
STOPSIGNAL SIGINT
EXPOSE 5432

ENV POSTGRES_HOST=/var/run/postgresql
CMD ["postgres", "-D", "/etc/postgresql"]
