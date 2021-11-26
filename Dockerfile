ARG PLATFORM
ARG VERSION

FROM --platform=$PLATFORM postgres:$VERSION

# install dependencies
RUN apt update && apt install --yes ansible

COPY ansible/ ~/ansible/
RUN cd ~/ansible && ansible-playbook playbook-docker.yml

ENV LANGUAGE=en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8