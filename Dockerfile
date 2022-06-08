ARG VERSION

FROM postgres:$VERSION

COPY ansible/ /tmp/ansible/

ENV DEBIAN_FRONTEND noninteractive

RUN mkdir -p /etc/postgresql-custom && \
    touch /etc/postgresql-custom/generated-optimizations.conf && \
    touch /etc/postgresql-custom/custom-overrides.conf

RUN apt-get update && \
    apt-get install -y ansible && \
    cd /tmp/ansible && \
    ansible-playbook playbook-docker.yml && \
    apt-get -y update && \
    apt-get -y upgrade && \
    apt-get -y autoremove && \
    apt-get -y autoclean && \
    apt-get install -y default-jdk-headless locales && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen && \
    rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*

ENV LANGUAGE en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8

CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]
