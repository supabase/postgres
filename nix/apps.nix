{ ... }:
{
  perSystem =
    { self', ... }:
    let
      mkApp = attrName: binName: {
        type = "app";
        program = "${self'.packages."${attrName}"}/bin/${binName}";
      };
    in
    {
      # Apps is a list of names of things that can be executed with 'nix run';
      # these are distinct from the things that can be built with 'nix build',
      # so they need to be listed here too.
      apps = {
        start-server = mkApp "start-server" "start-postgres-server";
        start-client = mkApp "start-client" "start-postgres-client";
        start-replica = mkApp "start-replica" "start-postgres-replica";
        # migrate-postgres = mkApp "migrate-tool" "migrate-postgres";
        # sync-exts-versions = mkApp "sync-exts-versions" "sync-exts-versions";
        pg-restore = mkApp "pg-restore" "pg-restore";
        local-infra-bootstrap = mkApp "local-infra-bootstrap" "local-infra-bootstrap";
        dbmate-tool = mkApp "dbmate-tool" "dbmate-tool";
        update-readme = mkApp "update-readme" "update-readme";
        show-commands = mkApp "show-commands" "show-commands";
        build-test-ami = mkApp "build-test-ami" "build-test-ami";
        run-testinfra = mkApp "run-testinfra" "run-testinfra";
        cleanup-ami = mkApp "cleanup-ami" "cleanup-ami";
        trigger-nix-build = mkApp "trigger-nix-build" "trigger-nix-build";
      };
    };
}
