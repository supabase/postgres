ARG PLATFORM
ARG VERSION

FROM --platform=$PLATFORM postgres:$VERSION

COPY ansible/ /tmp/ansible/

RUN apt update && \
    apt install -y ansible && \
    cd /tmp/ansible && \
    ansible-playbook playbook-docker.yml && \
    apt -y update && \
    apt -y upgrade && \
    apt -y autoremove && \
    apt -y autoclean && \
    apt install -y default-jdk-headless && \
    rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/* 

ENV LANGUAGE=en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8