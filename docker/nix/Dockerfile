FROM nixpkgs/nix-flakes

USER $USER

RUN mkdir -p /workspace

COPY ./ /workspace

RUN chmod +x /workspace/docker/nix/build.sh

RUN chown -R $USER:$USER /workspace


