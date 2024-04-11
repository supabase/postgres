FROM nixos/nix

# Enable flakes
RUN echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

USER $USER

RUN mkdir -p /workspace

COPY ./ /workspace

RUN chown -R $USER:$USER /workspace


