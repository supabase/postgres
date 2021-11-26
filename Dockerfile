ARG PLATFORM
ARG VERSION

FROM --platform=$PLATFORM postgres:$VERSION

# install dependencies
RUN apt update && apt install --yes ansible

COPY ansible/ /tmp/ansible/
RUN cd /tmp/ansible && ansible-playbook playbook-docker.yml
RUN rm -rf /tmp/*

ENV LANGUAGE=en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8