# syntax=docker/dockerfile:1.5-labs
ARG postgres_major=15
ARG postgres_minor=1

ARG sfcgal_release=1.3.10
ARG sfcgal_release_checksum=sha256:4e39b3b2adada6254a7bdba6d297bb28e1a9835a9f879b74f37e2dab70203232
ARG postgis_release=3.3.2
ARG postgis_release_checksum=sha256:9a2a219da005a1730a39d1959a1c7cec619b1efb009b65be80ffc25bad299068
ARG pgrouting_release=3.4.1
ARG pgrouting_release_checksum=sha256:a4e034efee8cf67582b67033d9c3ff714a09d8f5425339624879df50aff3f642
ARG pgtap_release=1.2.0
ARG pgtap_release_checksum=sha256:9c7c3de67ea41638e14f06da5da57bac6f5bd03fea05c165a0ec862205a5c052
ARG pg_cron_release=1.4.2
ARG pg_cron_release_checksum=sha256:3652722ea98d94d8e27bf5e708dd7359f55a818a43550d046c5064c98876f1a8
ARG pgaudit_release=1.7.0
ARG pgaudit_release_checksum=sha256:8f4a73e451c88c567e516e6cba7dc1e23bc91686bb6f1f77f8f3126d428a8bd8
ARG pgjwt_release=9742dab1b2f297ad3811120db7b21451bca2d3c9
ARG pgsql_http_release=1.5.0
ARG pgsql_http_release_checksum=sha256:43efc9e82afcd110f205b86b8d28d1355d39b6b134161e9661a33a1346818f5d
ARG plpgsql_check_release=2.2.5
ARG plpgsql_check_release_checksum=sha256:6c3a3c5faf3f9689425c6db8a6b20bf4cd5e7144a055e29538eae980c7232573
ARG pg_safeupdate_release=1.4
ARG pg_safeupdate_release_checksum=sha256:ff01d3d444d35924bd3d745c5695696292e2855042da4c30fe728fb3b6648122
ARG timescaledb_release=2.9.1
ARG timescaledb_release_checksum=sha256:883638f2e79d25ec88ee58f603f3c81c999b6364cb4c799919d363f04089b47b
ARG wal2json_release=2_5
ARG wal2json_release_checksum=sha256:b516653575541cf221b99cf3f8be9b6821f6dbcfc125675c85f35090f824f00e
ARG pljava_release=1.6.4
ARG pljava_release_checksum=sha256:5dc5a963365cbdeb786d0ad65b6310c4c5150ef8524e273bca4085c3fb0f056f
ARG plv8_release=3.1.5
ARG plv8_release_checksum=sha256:1e108d5df639e4c189e1c5bdfa2432a521c126ca89e7e5a969d46899ca7bf106
ARG pg_plan_filter_release=5081a7b5cb890876e67d8e7486b6a64c38c9a492
ARG pg_net_release=0.7.1
ARG pg_net_release_checksum=sha256:f403019fbffe5b3ec28816957ef81279dea1db5b008e3fb3bc39181a5e361940
ARG rum_release=1.3.13
ARG rum_release_checksum=sha256:6ab370532c965568df6210bd844ac6ba649f53055e48243525b0b7e5c4d69a7d
ARG pg_hashids_release=cd0e1b31d52b394a0df64079406a14a4f7387cd6
ARG libsodium_release=1.0.18
ARG libsodium_release_checksum=sha256:6f504490b342a4f8a4c4a02fc9b866cbef8622d5df4e5452b46be121e46636c1
ARG pgsodium_release=3.1.5
ARG pgsodium_release_checksum=sha256:bec847388a5db2a60ea9d991962ce27954d91b4c41cbcc7bd8e34472c69114d1
ARG pg_graphql_release=1.1.0
ARG pg_stat_monitor_release=1.1.1
ARG pg_stat_monitor_release_checksum=sha256:1756a02d5a6dd66b892d15920257c69a17a67d48d3d4e2f189b681b83001ec2a
ARG pg_jsonschema_release=0.1.4
ARG vault_release=0.2.9
ARG vault_release_checksum=sha256:1e813216395c59bb94c92be47ce8b70ba19ccc0efbcdb1fb14ed6d34a42c6cdb
ARG groonga_release=12.0.8
ARG groonga_release_checksum=sha256:7770c0ff6804ef4b47b015b15736cd973cffced977c20991b16b2daa4fea6eeb
ARG pgroonga_release=2.4.0
ARG pgroonga_release_checksum=sha256:5baaae0e7d81f8167e278e9a34c6ed56aece8b34f5ab98f228c64408093417b3
ARG wrappers_release=0.1.7
ARG hypopg_release=1.3.1
ARG hypopg_release_checksum=sha256:e7f01ee0259dc1713f318a108f987663d60f3041948c2ada57a94b469565ca8e
ARG pg_repack_release=1.4.8
ARG pg_repack_release_checksum=sha256:18b4d871c1abf78cf0b1b1fe6081d435d183a8dc5eb977576e7a47fe113dd4ec
ARG pgvector_release=0.4.0
ARG pgvector_release_checksum=sha256:b76cf84ddad452cc880a6c8c661d137ddd8679c000a16332f4f03ecf6e10bcc8

FROM postgres:$postgres_major.$postgres_minor as base
# Redeclare args for use in subsequent stages
ARG TARGETARCH
ARG postgres_major

FROM base as builder
# Install build dependencies
RUN apt-get update && apt-get install -y \
    postgresql-server-dev-${postgres_major} \
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
ARG sfcgal_release_checksum
ADD --checksum=${sfcgal_release_checksum} \
    "https://gitlab.com/Oslandia/SFCGAL/-/archive/v${sfcgal_release}/SFCGAL-v${sfcgal_release}.tar.gz" \
    /tmp/sfcgal.tar.gz
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
ARG postgis_release_checksum
ADD --checksum=${postgis_release_checksum} \
    "https://supabase-public-artifacts-bucket.s3.amazonaws.com/postgis-${postgis_release}.tar.gz" \
    /tmp/postgis.tar.gz
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
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --pakdir=/tmp --nodoc

####################
# 02-pgrouting.yml
####################
FROM builder as pgrouting
# Download and extract
ARG pgrouting_release
ARG pgrouting_release_checksum
ADD --checksum=${pgrouting_release_checksum} \
    "https://github.com/pgRouting/pgrouting/releases/download/v${pgrouting_release}/pgrouting-${pgrouting_release}.tar.gz" \
    /tmp/pgrouting.tar.gz
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
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --pakdir=/tmp --pkgname=pgrouting --pkgversion=${pgrouting_release} --nodoc

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
RUN checkinstall -D --install=no --fstrans=no --pakdir=/tmp --nodoc

####################
# 04-pg_cron.yml
####################
FROM builder as pg_cron
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
RUN make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --pakdir=/tmp --nodoc

####################
# 05-pgaudit.yml
####################
FROM builder as pgaudit
# Download and extract
ARG pgaudit_release
ARG pgaudit_release_checksum
ADD --checksum=${pgaudit_release_checksum} \
    "https://github.com/pgaudit/pgaudit/archive/refs/tags/${pgaudit_release}.tar.gz" \
    /tmp/pgaudit.tar.gz
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
RUN make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --pakdir=/tmp --nodoc

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
RUN checkinstall -D --install=no --fstrans=no --pakdir=/tmp --nodoc

####################
# 07-pgsql-http.yml
####################
FROM builder as pgsql-http
# Download and extract
ARG pgsql_http_release
ARG pgsql_http_release_checksum
ADD --checksum=${pgsql_http_release_checksum} \
    "https://github.com/pramsey/pgsql-http/archive/refs/tags/v${pgsql_http_release}.tar.gz" \
    /tmp/pgsql-http.tar.gz
RUN tar -xvf /tmp/pgsql-http.tar.gz -C /tmp && \
    rm -rf /tmp/pgsql-http.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y \
    libcurl4-gnutls-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/pgsql-http-${pgsql_http_release}
RUN make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --pakdir=/tmp --nodoc

####################
# 08-plpgsql_check.yml
####################
FROM builder as plpgsql_check
# Download and extract
ARG plpgsql_check_release
ARG plpgsql_check_release_checksum
ADD --checksum=${plpgsql_check_release_checksum} \
    "https://github.com/okbob/plpgsql_check/archive/refs/tags/v${plpgsql_check_release}.tar.gz" \
    /tmp/plpgsql_check.tar.gz
RUN tar -xvf /tmp/plpgsql_check.tar.gz -C /tmp && \
    rm -rf /tmp/plpgsql_check.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y \
    libicu-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/plpgsql_check-${plpgsql_check_release}
RUN make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --pakdir=/tmp --nodoc

####################
# 09-pg-safeupdate.yml
####################
FROM builder as pg-safeupdate
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
RUN make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --pakdir=/tmp --nodoc

####################
# 10-timescaledb.yml
####################
FROM builder as timescaledb
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
RUN make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --pakdir=/tmp --pkgname=timescaledb --pkgversion=${timescaledb_release} --nodoc

####################
# 11-wal2json.yml
####################
FROM builder as wal2json
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
RUN make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --pakdir=/tmp --pkgversion=${wal2json_release} --nodoc

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
RUN cp pljava-packaging/target/pljava-pg${postgres_major}.jar /tmp/

FROM builder as pljava
# Download pre-built packages
RUN apt-get update && apt-get install -y --download-only \
    default-jdk-headless \
    postgresql-${postgres_major}-pljava \
    && rm -rf /var/lib/apt/lists/*
RUN mv /var/cache/apt/archives/*.deb /tmp/

####################
# 13-plv8.yml
####################
FROM builder as plv8
# Download and extract
ARG plv8_release
ARG plv8_release_checksum
ADD --checksum=${plv8_release_checksum} \
    "https://github.com/plv8/plv8/archive/refs/tags/v${plv8_release}.tar.gz" \
    /tmp/plv8.tar.gz
RUN tar -xvf /tmp/plv8.tar.gz -C /tmp && \
    rm -rf /tmp/plv8.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y \
    ccache \
    pkg-config \
    ninja-build \
    clang \
    git \
    libtinfo5 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=public.ecr.aws/t3w2s2c9/postgres-buildcache:latest /ccache /ccache
# Build from source
WORKDIR /tmp/plv8-${plv8_release}
ENV DOCKER=1
ENV CCACHE_DIR=/ccache
ENV PATH=/usr/lib/ccache:$PATH
RUN make generate_upgrades
RUN make v8
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --pakdir=/tmp --nodoc

####################
# 14-pg_plan_filter.yml
####################
FROM builder as pg_plan_filter
# Download and extract
ARG pg_plan_filter_release
ADD "https://github.com/pgexperts/pg_plan_filter.git#${pg_plan_filter_release}" \
    /tmp/pg_plan_filter-${pg_plan_filter_release}
# Build from source
WORKDIR /tmp/pg_plan_filter-${pg_plan_filter_release}
RUN make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --pakdir=/tmp --nodoc

####################
# 15-pg_net.yml
####################
FROM builder as pg_net
# Download and extract
ARG pg_net_release
ARG pg_net_release_checksum
ADD --checksum=${pg_net_release_checksum} \
    "https://github.com/supabase/pg_net/archive/refs/tags/v${pg_net_release}.tar.gz" \
    /tmp/pg_net.tar.gz
RUN tar -xvf /tmp/pg_net.tar.gz -C /tmp && \
    rm -rf /tmp/pg_net.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y \
    libcurl4-gnutls-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/pg_net-${pg_net_release}
RUN make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --pakdir=/tmp --nodoc

####################
# 16-rum.yml
####################
FROM builder as rum
# Download and extract
ARG rum_release
ARG rum_release_checksum
ADD --checksum=${rum_release_checksum} \
    "https://github.com/postgrespro/rum/archive/refs/tags/${rum_release}.tar.gz" \
    /tmp/rum.tar.gz
RUN tar -xvf /tmp/rum.tar.gz -C /tmp && \
    rm -rf /tmp/rum.tar.gz
# Install build dependencies
RUN apt-get update && apt-get install -y \
    systemtap-sdt-dev \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/rum-${rum_release}
ENV USE_PGXS=1
RUN make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --pakdir=/tmp --nodoc

####################
# 17-pg_hashids.yml
####################
FROM builder as pg_hashids
# Download and extract
ARG pg_hashids_release
ADD "https://github.com/iCyberon/pg_hashids.git#${pg_hashids_release}" \
    /tmp/pg_hashids-${pg_hashids_release}
# Build from source
WORKDIR /tmp/pg_hashids-${pg_hashids_release}
RUN make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --pakdir=/tmp --nodoc

####################
# 18-pgsodium.yml
####################
FROM builder as libsodium
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
RUN make -j$(nproc)
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
RUN make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --pakdir=/tmp --nodoc
RUN apt-get update && apt-get install -y --download-only \
    libsodium23 \
    && rm -rf /var/lib/apt/lists/*
RUN mv /var/cache/apt/archives/*.deb /tmp/

####################
# 19-pg_graphql.yml
####################
FROM builder as pg_graphql
# Download package archive
ARG pg_graphql_release
ADD "https://github.com/supabase/pg_graphql/releases/download/v${pg_graphql_release}/pg_graphql-v${pg_graphql_release}-pg${postgres_major}-${TARGETARCH}-linux-gnu.deb" \
    /tmp/pg_graphql.deb

####################
# 20-pg_stat_monitor.yml
####################
FROM builder as pg_stat_monitor
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
RUN make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --pakdir=/tmp --nodoc

####################
# 21-auto_explain.yml
####################

####################
# 22-pg_jsonschema.yml
####################
FROM builder as pg_jsonschema
# Download package archive
ARG pg_jsonschema_release
ADD "https://github.com/supabase/pg_jsonschema/releases/download/v${pg_jsonschema_release}/pg_jsonschema-v${pg_jsonschema_release}-pg${postgres_major}-${TARGETARCH}-linux-gnu.deb" \
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
RUN checkinstall -D --install=no --fstrans=no --pakdir=/tmp --nodoc

####################
# 24-pgroonga.yml
####################
FROM builder as groonga
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
RUN make -j$(nproc)
RUN make install

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
RUN apt-get update && apt-get install -y \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*
# Build from source
WORKDIR /tmp/pgroonga-${pgroonga_release}
RUN make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --pakdir=/tmp --nodoc

FROM builder as pgroonga
# Download pre-built packages
ADD "https://packages.groonga.org/debian/groonga-apt-source-latest-bullseye.deb" /tmp/source.deb
RUN apt-get update && apt-get install -y \
    /tmp/source.deb \
    && rm -rf /var/lib/apt/lists/*
RUN rm /tmp/source.deb
RUN apt-get update && apt-get install -y --download-only \
    postgresql-${postgres_major}-pgdg-pgroonga \
    && rm -rf /var/lib/apt/lists/*
RUN mv /var/cache/apt/archives/*.deb /tmp/

####################
# 25-wrappers.yml
####################
FROM builder as wrappers
# Download package archive
ARG wrappers_release
ADD "https://github.com/supabase/wrappers/releases/download/v${wrappers_release}/wrappers-v${wrappers_release}-pg${postgres_major}-${TARGETARCH}-linux-gnu.deb" \
    /tmp/wrappers.deb

####################
# 26-hypopg.yml
####################
FROM builder as hypopg
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
RUN make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --pakdir=/tmp --nodoc

####################
# 27-pg_repack.yml
####################
FROM builder as pg_repack
ARG pg_repack_release
ARG pg_repack_release_checksum
ADD --checksum=${pg_repack_release_checksum} \
    "https://github.com/reorg/pg_repack/archive/refs/tags/ver_${pg_repack_release}.tar.gz" \
    /tmp/pg_repack.tar.gz
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
RUN make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --pakdir=/tmp --pkgversion=${pg_repack_release} --nodoc

####################
# 28-pgvector.yml
####################
FROM builder as pgvector
ARG pgvector_release
ARG pgvector_release_checksum
ADD --checksum=${pgvector_release_checksum} \
    "https://github.com/pgvector/pgvector/archive/refs/tags/v${pgvector_release}.tar.gz" \
    /tmp/pgvector.tar.gz
RUN tar -xvf /tmp/pgvector.tar.gz -C /tmp && \
    rm -rf /tmp/pgvector.tar.gz
# Build from source
WORKDIR /tmp/pgvector-${pgvector_release}
RUN make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --pakdir=/tmp --nodoc

####################
# Build final image
####################
FROM base as production

# tasks/docker/setup.yml
COPY files/postgresql_config/postgresql.conf.j2 /etc/postgresql/postgresql.conf
COPY files/postgresql_config/pg_hba.conf.j2 /etc/postgresql/pg_hba.conf
COPY files/postgresql_config/pg_ident.conf.j2 /etc/postgresql/pg_ident.conf

# tasks/setup-extensions.yml
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
COPY --from=pgsodium /tmp/*.deb /tmp/
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

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    /tmp/*.deb \
    && rm -rf /var/lib/apt/lists/* /tmp/*

# tasks/docker/finalize.yml
COPY --chown=postgres:postgres files/postgresql_config/postgresql-stdout-log.conf /etc/postgresql/logging.conf
COPY --chown=postgres:postgres files/pgsodium_getkey_urandom.sh.j2 /usr/lib/postgresql/${postgres_major}/bin/pgsodium_getkey.sh
COPY files/pgbouncer_config/pgbouncer_auth_schema.sql /docker-entrypoint-initdb.d/00-schema.sql
COPY files/stat_extension.sql /docker-entrypoint-initdb.d/01-extension.sql

RUN sed -i "s/#unix_socket_directories = '\/tmp'/unix_socket_directories = '\/var\/run\/postgresql'/g" /etc/postgresql/postgresql.conf && \
    echo "cron.database_name = 'postgres'" >> /etc/postgresql/postgresql.conf && \
    echo "pljava.libjvm_location = '/usr/lib/jvm/java-11-openjdk-${TARGETARCH}/lib/server/libjvm.so'" >> /etc/postgresql/postgresql.conf && \
    echo "pgsodium.getkey_script= '/usr/lib/postgresql/${postgres_major}/bin/pgsodium_getkey.sh'" >> /etc/postgresql/postgresql.conf && \
    echo 'auto_explain.log_min_duration = 10s' >> /etc/postgresql/postgresql.conf

ENV POSTGRES_HOST=/var/run/postgresql

HEALTHCHECK --interval=2s --timeout=2s --retries=10 CMD pg_isready -U postgres -h localhost
