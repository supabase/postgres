{
  lib,
  nixosModulesPath,
  self,
  system,
  config,
  ...
}:
let
  cfg = config.supabase.services.envoy;
  services = [ (import ./admin_api.nix) ];
  mkFilters = services: [
    {
      name = "envoy.filters.network.http_connection_manager";
      typed_config = {
        "@type" =
          "type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager";
        access_log = import ./access_log.nix;
        generate_request_id = false;
        http_filters = import ./http_filters.nix;
        local_reply_config = import ./local_reply_config.nix;
        merge_slashes = true;
        route_config = import ./route_config.nix {
          inherit services;
        };
        stat_prefix = "ingress_http";
      };
    }
  ];
  filters = mkFilters services;
in
{
  imports = map (path: nixosModulesPath + path) [
    "/services/networking/envoy.nix"
  ];

  options = {
    supabase.services.envoy = {
      enable = lib.mkEnableOption "Envoy proxy";
      enableTLS = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether to enable TLS support in Envoy.
          If enabled, you must provide the TLS certificate and key files.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.envoy = {
      enable = true;
      package = self.packages.${system}.envoy-bin;
      # We don't validate the config at build time if TLS is enabled,
      # because it requires the TLS certificate and key files to be present.
      requireValidConfig = !cfg.enableTLS;
      settings = {
        node = {
          cluster = "cluster_0";
          id = "node_0";
        };
        stats_config = {
          stats_matcher = {
            reject_all = true;
          };
        };
        static_resources = {
          clusters = map (cluster: cluster.config) services;
          listeners = [
            {
              name = "http_listener";
              address = {
                socket_address = {
                  address = "::";
                  port_value = 80;
                  ipv4_compat = true;
                };
              };
              filter_chains = {
                inherit filters;
              };
            }
            (lib.mkIf cfg.enableTLS {
              name = "https_listener";
              address = {
                socket_address = {
                  address = "::";
                  port_value = 443;
                  ipv4_compat = true;
                };
              };
              filter_chains = {
                inherit filters;
                transport_socket = {
                  name = "envoy.transport_sockets.tls";
                  typed_config = {
                    "@type" = "type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.DownstreamTlsContext";
                    common_tls_context = {
                      tls_certificates = [
                        {
                          certificate_chain = {
                            filename = "/etc/envoy/fullChain.pem";
                          };
                          private_key = {
                            filename = "/etc/envoy/privKey.pem";
                          };
                        }
                      ];
                    };
                  };
                };
              };
            })
          ];
        };
      };
    };
    systemd.services.envoy = {
      wantedBy = lib.mkForce [
        "system-manager.target"
      ];
    };
  };
}
