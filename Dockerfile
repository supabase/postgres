ARG VERSION

FROM postgres:$VERSION

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

CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]
