{
  config = {
    name = "admin_api";
    load_assignment = {
      cluster_name = "admin_api";
      endpoints = [
        {
          lb_endpoints = [
            {
              endpoint = {
                address = {
                  socket_address = {
                    address = "127.0.0.1";
                    port_value = 8085;
                  };
                };
              };
            }
          ];
        }
      ];
    };
    circuit_breakers = {
      thresholds = [
        {
          priority = "DEFAULT";
          max_connections = 10000;
          max_pending_requests = 10000;
          max_requests = 10000;
          retry_budget = {
            budget_percent = {
              value = 100;
            };
            min_retry_concurrency = 100;
          };
        }
      ];
    };
  };
  routes = [
    {
      match = {
        prefix = "/admin/v1/";
      };
      request_headers_to_remove = [ "sb-opk" ];
      route = {
        cluster = "admin_api";
        prefix_rewrite = "/";
        timeout = "600s";
      };
    }
    {
      match = {
        prefix = "/customer/v1/privileged/";
      };
      request_headers_to_remove = [ "sb-opk" ];
      route = {
        cluster = "admin_api";
        prefix_rewrite = "/privileged/";
      };
      typed_per_filter_config = {
        "envoy.filters.http.rbac" = {
          "@type" = "type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBACPerRoute";
          rbac = {
            rules = {
              action = "DENY";
              policies = {
                basic_auth = {
                  permissions = [ { any = true; } ];
                  principals = [
                    {
                      header = {
                        name = "authorization";
                        invert_match = true;
                        string_match = {
                          exact = "Basic c2VydmljZV9yb2xlOnNlcnZpY2Vfa2V5";
                        };
                        treat_missing_header_as_empty = true;
                      };
                    }
                  ];
                };
              };
            };
          };
        };
      };
    }
    {
      match = {
        prefix = "/metrics/aggregated";
      };
      request_headers_to_remove = [ "sb-opk" ];
      route = {
        cluster = "admin_api";
        prefix_rewrite = "/supabase-internal/metrics";
      };
      typed_per_filter_config = {
        "envoy.filters.http.rbac" = {
          "@type" = "type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBACPerRoute";
          rbac = {
            rules = {
              action = "DENY";
              policies = {
                not_private_ip = {
                  permissions = [ { any = true; } ];
                  principals = [
                    {
                      not_id = {
                        direct_remote_ip = {
                          address_prefix = "10.0.0.0";
                          prefix_len = 8;
                        };
                      };
                    }
                  ];
                };
              };
            };
          };
        };
      };
    }
  ];
}
