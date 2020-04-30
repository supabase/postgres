FROM postgres:12

# install postgis
ENV POSTGIS_MAJOR 3
ENV POSTGIS_VERSION 3.0.0+dfsg-2~exp1.pgdg100+1
RUN apt-get update \
      && apt-cache showpkg postgresql-$PG_MAJOR-postgis-$POSTGIS_MAJOR \
      && apt-get install -y --no-install-recommends \
           postgresql-$PG_MAJOR-postgis-$POSTGIS_MAJOR \
           postgresql-$PG_MAJOR-postgis-$POSTGIS_MAJOR-scripts \
      && apt-get install software-properties-common -y \
      && apt-get install git -y \
      && apt-get install build-essential -y \
      && rm -rf /var/lib/apt/lists/*

# install pgtap
ENV PGTAP_VERSION v1.1.0
RUN git clone git://github.com/theory/pgtap.git \
    && cd pgtap && git checkout tags/$PGTAP_VERSION \
    && make install

RUN mkdir -p /docker-entrypoint-initdb.d
ADD ./mnt /docker-entrypoint-initdb.d/