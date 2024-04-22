FROM ubuntu:20.04

MAINTAINER Tom Ashley

ENV DEBIAN_FRONTEND noninteractive
ENV SALT_VERSION 3006.7

# Dependencies
RUN apt-get update \
    && apt-get install -y curl vim.tiny tree

# Install one-dir salt
RUN mkdir /etc/apt/keyrings \
    && curl -fsSL -o /etc/apt/keyrings/salt-archive-keyring-2023.gpg https://repo.saltproject.io/salt/py3/ubuntu/20.04/arm64/SALT-PROJECT-GPG-PUBKEY-2023.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/salt-archive-keyring-2023.gpg arch=arm64] https://repo.saltproject.io/salt/py3/ubuntu/20.04/arm64/latest focal main" | tee /etc/apt/sources.list.d/salt.list \
    && apt-get clean && apt-get update \
    && apt-get install -y salt-minion

ADD docker/etc/minion /etc/salt/minion
ADD docker/etc/grains /etc/salt/grains
ADD docker/etc/_grains /etc/salt/_grains

# Start minion only for now
ADD docker/start.sh /start.sh
CMD ["bash", "start.sh"]
