FROM postgres:12

# install postgis
ENV POSTGIS_MAJOR 3
ENV POSTGIS_VERSION 3.0.0+dfsg-2~exp1.pgdg100+1
RUN apt-get update \
      && apt-cache showpkg postgresql-$PG_MAJOR-postgis-$POSTGIS_MAJOR \
      && apt-get install -y --no-install-recommends \
          postgresql-$PG_MAJOR-postgis-$POSTGIS_MAJOR \
          postgresql-$PG_MAJOR-postgis-$POSTGIS_MAJOR-scripts \
      && rm -rf /var/lib/apt/lists/* /var/tmp/*

# install pgtap
ENV PGTAP_VERSION=v1.1.0

RUN pgtapDependencies="git \
    ca-certificates \
    build-essential" \
    && apt-get update \
    && apt-get install -y --no-install-recommends ${pgtapDependencies} \
    && cd /tmp \
    && git clone git://github.com/theory/pgtap.git \
    && cd pgtap \
    && git checkout tags/$PGTAP_VERSION \
    && make install \
    && apt-get clean \
    && apt-get remove -y ${pgtapDependencies} \
    && apt-get autoremove -y \
    && rm -rf /tmp/pgtap /var/lib/apt/lists/* /var/tmp/*

# install plpython3
RUN apt-get update \ 
      && apt-get install postgresql-plpython3-12 -y

# install pgAudit
ENV PGAUDIT_VERSION=1.4.0

RUN pgAuditDependencies="git \
    ca-certificates \
    build-essential \
    postgresql-server-dev-$PG_MAJOR \
    libssl-dev \
    libkrb5-dev" \
    && apt-get update \
    && apt-get install -y --no-install-recommends ${pgAuditDependencies} \
    && cd /tmp \
    && git clone https://github.com/pgaudit/pgaudit.git \
    && cd pgaudit \
    && git checkout ${PGAUDIT_VERSION} \ 
    && make check USE_PGXS=1 \
    && make install USE_PGXS=1 \
    && apt-get clean \
    && apt-get remove -y ${pgAuditDependencies} \
    && apt-get autoremove -y \
    && rm -rf /tmp/pgaudit /var/lib/apt/lists/* /var/tmp/*

# install pgjwt
RUN pgjwtDependencies="git \
    ca-certificates \
    build-essential" \
    && apt-get update \
    && apt-get install -y --no-install-recommends ${pgjwtDependencies} \
    && cd /tmp \
    && git clone https://github.com/michelp/pgjwt.git \
    && cd pgjwt \
    && git checkout master \
    && make install \ 
    && apt-get clean \
    && apt-get remove -y ${pgtapDependencies} \
    && apt-get autoremove -y \
    && rm -rf /tmp/pgjwt /var/lib/apt/lists/* /var/tmp/*

# install pgsql-http
ENV PGSQL_HTTP_VERSION=v1.3.1

RUN pgsqlHttpDependencies="git \
    ca-certificates \
    build-essential \
    postgresql-server-dev-$PG_MAJOR" \
    && pgsqlHttpRuntimeDependencies="libcurl4-gnutls-dev" \
    && apt-get update \
    && apt-get install -y --no-install-recommends ${pgsqlHttpDependencies} ${pgsqlHttpRuntimeDependencies} \
    && cd /tmp \
    && git clone https://github.com/pramsey/pgsql-http.git \
    && cd pgsql-http \
    && git checkout ${PGSQL_HTTP_VERSION} \
    && make \ 
    && make install \
    && apt-get clean \
    && apt-get remove -y ${pgsqlHttpDependencies} \
    && apt-get autoremove -y \
    && rm -rf /tmp/pgsql-http /var/lib/apt/lists/* /var/tmp/*

# install plpgsql_check
ENV PLPGSQL_CHECK_VERSION=v1.11.3

RUN plpgsqlCheckDependencies="git \
    ca-certificates \
    build-essential \
    postgresql-server-dev-$PG_MAJOR" \
    && plpgsqlCheckRuntimeDependencies="libicu-dev" \
    && apt-get update \
    && apt-get install -y --no-install-recommends ${plpgsqlCheckDependencies} ${plpgsqlCheckRuntimeDependencies} \
    && cd /tmp \
    && git clone https://github.com/okbob/plpgsql_check.git \
    && cd plpgsql_check \
    && git checkout ${PLPGSQL_CHECK_VERSION} \
    && make clean \ 
    && make install \
    && apt-get clean \
    && apt-get remove -y ${pgsqlHttpDependencies} \
    && apt-get autoremove -y \
    && rm -rf /tmp/plpgsql_check /var/lib/apt/lists/* /var/tmp/*

# install plv8
ENV PLV8_VERSION=r3.0alpha

RUN plv8Dependencies="build-essential \
    ca-certificates \
    curl \
    git-core \
    python \
    gpp \
    cpp \
    pkg-config \
    apt-transport-https \
    cmake \
    libc++-dev \
    libc++abi-dev \
    postgresql-server-dev-$PG_MAJOR" \
  && plv8RuntimeDependencies="libc++1 \
    libtinfo5 \
    libc++abi1" \
  && apt-get update \
  && apt-get install -y --no-install-recommends ${plv8Dependencies} ${plv8RuntimeDependencies} \
  && mkdir -p /tmp/build \
  && cd /tmp/build \
  && git clone https://github.com/plv8/plv8.git \
  && cd plv8 \
  && git checkout ${PLV8_VERSION} \
  && make static \
  && make install \
  && rm -rf /root/.vpython_cipd_cache /root/.vpython-root \
  && apt-get clean \
  && apt-get remove -y ${plv8Dependencies} \
  && apt-get autoremove -y \
  && rm -rf /tmp/build /var/lib/apt/lists/* /var/tmp/*

# install pljava
ENV PLJAVA_VERSION=V1_5_5

RUN pljavaDependencies="git \
    ca-certificates \
    g++ \
    maven \
    postgresql-server-dev-$PG_MAJOR \
    libpq-dev \
    libecpg-dev \
    libkrb5-dev \
    default-jdk \
    libssl-dev" \
    && apt-get update \
    && apt-get install -y --no-install-recommends ${pljavaDependencies} \
    && cd /tmp \
    && git clone https://github.com/tada/pljava.git \
    && cd pljava \
    && git checkout ${PLJAVA_VERSION} \
    && mvn clean install \
    && java -jar pljava-packaging/target/pljava-pg12.3-amd64-Linux-gpp.jar \
    && apt-get clean \
    && apt-get remove -y ${pljavaDependencies} \
    && apt-get autoremove -y \
    && rm -rf ~/.m2 /tmp/pljava /var/lib/apt/lists/* /var/tmp/*

RUN apt-get update \
    && apt-get install -y --no-install-recommends default-jdk-headless \
    && rm -rf /var/lib/apt/lists/* /var/tmp/*

RUN mkdir -p /docker-entrypoint-initdb.d
ADD ./mnt /docker-entrypoint-initdb.d/