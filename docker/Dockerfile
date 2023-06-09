ARG ubuntu_release=focal
FROM ubuntu:${ubuntu_release} as base

ARG ubuntu_release
ARG postgresql_major=15
ARG postgresql_release=${postgresql_major}.1

FROM base as pg-source

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gnupg \
    dpkg-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Add Postgres PPA
ARG postgresql_gpg_key=B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys "${postgresql_gpg_key}" && \
    echo "deb https://apt-archive.postgresql.org/pub/repos/apt ${ubuntu_release}-pgdg-archive main" > /etc/apt/sources.list.d/pgdg.list && \
    echo "deb-src https://apt-archive.postgresql.org/pub/repos/apt ${ubuntu_release}-pgdg-archive main" > /etc/apt/sources.list.d/pgdg.list

# Create local PPA
WORKDIR /tmp/build
RUN echo "deb [ trusted=yes ] file:///tmp/build ./" > /etc/apt/sources.list.d/temp.list && \
    dpkg-scanpackages . > Packages && \
    apt-get -o Acquire::GzipIndexes=false update

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONDONTWRITEBYTECODE=1
ENV DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)"

# Configure processor optimised build
ARG CPPFLAGS="-mcpu=neoverse-n1"
ENV DEB_CPPFLAGS_APPEND="${CPPFLAGS} -fsigned-char"

RUN apt-get build-dep -y postgresql-common pgdg-keyring && \
    apt-get source --compile postgresql-common pgdg-keyring && \
    dpkg-scanpackages . > Packages && \
    apt-get -o Acquire::GzipIndexes=false update

RUN apt-get build-dep -y "postgresql-${postgresql_major}=${postgresql_release}-1.pgdg20.04+1" && \
    apt-get source --compile "postgresql-${postgresql_major}=${postgresql_release}-1.pgdg20.04+1" && \
    dpkg-scanpackages . > Packages && \
    apt-get -o Acquire::GzipIndexes=false update

# Remove source directories
RUN rm -rf /tmp/build/*/

FROM base as pg

# Inherit args from base stage
ARG postgresql_major
ARG postgresql_release

COPY --from=pg-source /tmp/build /tmp/build

ENV DEBIAN_FRONTEND=noninteractive
RUN echo "deb [ trusted=yes ] file:///tmp/build ./" > /etc/apt/sources.list.d/temp.list && \
    apt-get -o Acquire::GzipIndexes=false update && \
    apt-get install -y --no-install-recommends postgresql-common && \
    sed -ri 's/#(create_main_cluster) .*$/\1 = false/' /etc/postgresql-common/createcluster.conf && \
    apt-get install -y --no-install-recommends "postgresql-${postgresql_major}=${postgresql_release}-1.pgdg20.04+1" && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /tmp/build /etc/apt/sources.list.d/temp.list

ENV PATH $PATH:/usr/lib/postgresql/${postgresql_major}/bin

FROM scratch as pg-deb

COPY --from=pg-source /tmp/build /tmp