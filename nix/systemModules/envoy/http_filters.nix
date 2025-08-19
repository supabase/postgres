[
  {
    name = "envoy.filters.http.cors";
    typed_config = {
      "@type" = "type.googleapis.com/envoy.extensions.filters.http.cors.v3.Cors";
    };
  }
  {
    name = "envoy.filters.http.rbac";
    typed_config = {
      "@type" = "type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBAC";
      rules = {
        action = "DENY";
        policies = {
          api_key_missing = {
            permissions = [ { any = true; } ];
            principals = [
              {
                not_id = {
                  or_ids = {
                    ids = [
                      {
                        header = {
                          name = "apikey";
                          present_match = true;
                        };
                      }
                      {
                        header = {
                          name = ":path";
                          string_match = {
                            contains = "apikey=";
                          };
                        };
                      }
                    ];
                  };
                };
              }
            ];
          };
          api_key_not_valid = {
            permissions = [ { any = true; } ];
            principals = [
              {
                not_id = {
                  or_ids = {
                    ids = [
                      {
                        header = {
                          name = "apikey";
                          string_match = {
                            exact = "anon_key";
                          };
                        };
                      }
                      {
                        header = {
                          name = "apikey";
                          string_match = {
                            exact = "service_key";
                          };
                        };
                      }
                      {
                        header = {
                          name = "apikey";
                          string_match = {
                            exact = "supabase_admin_key";
                          };
                        };
                      }
                      {
                        header = {
                          name = ":path";
                          string_match = {
                            contains = "apikey=anon_key";
                          };
                        };
                      }
                      {
                        header = {
                          name = ":path";
                          string_match = {
                            contains = "apikey=service_key";
                          };
                        };
                      }
                      {
                        header = {
                          name = ":path";
                          string_match = {
                            contains = "apikey=supabase_admin_key";
                          };
                        };
                      }
                    ];
                  };
                };
              }
            ];
          };
        };
      };
    };
  }
  {
    name = "envoy.filters.http.lua";
    typed_config = {
      "@type" = "type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua";
      source_codes = {
        remove_apikey_and_empty_key_query_parameters = {
          inline_string = "function envoy_on_request(request_handle)\n  local path = request_handle:headers():get(\":path\")\n  request_handle\n    :headers()\n    :replace(\":path\", path:gsub(\"&=[^&]*\", \"\"):gsub(\"?=[^&]*$\", \"\"):gsub(\"?=[^&]*&\", \"?\"):gsub(\"&apikey=[^&]*\", \"\"):gsub(\"?apikey=[^&]*$\", \"\"):gsub(\"?apikey=[^&]*&\", \"?\"))\nend";
        };
        remove_empty_key_query_parameters = {
          inline_string = "function envoy_on_request(request_handle)\n  local path = request_handle:headers():get(\":path\")\n  request_handle\n    :headers()\n    :replace(\":path\", path:gsub(\"&=[^&]*\", \"\"):gsub(\"?=[^&]*$\", \"\"):gsub(\"?=[^&]*&\", \"?\"))\nend";
        };
      };
    };
  }
  {
    name = "envoy.filters.http.compressor.brotli";
    typed_config = {
      "@type" = "type.googleapis.com/envoy.extensions.filters.http.compressor.v3.Compressor";
      response_direction_config = {
        common_config = {
          min_content_length = 100;
          content_type = [
            "application/vnd.pgrst.object+json"
            "application/vnd.pgrst.array+json"
            "application/openapi+json"
            "application/geo+json"
            "text/csv"
            "application/vnd.pgrst.plan"
            "application/vnd.pgrst.object"
            "application/vnd.pgrst.array"
            "application/javascript"
            "application/json"
            "application/xhtml+xml"
            "image/svg+xml"
            "text/css"
            "text/html"
            "text/plain"
            "text/xml"
          ];
        };
        disable_on_etag_header = true;
      };
      request_direction_config = {
        common_config = {
          enabled = {
            default_value = false;
            runtime_key = "request_compressor_enabled";
          };
        };
      };
      compressor_library = {
        name = "text_optimized";
        typed_config = {
          "@type" = "type.googleapis.com/envoy.extensions.compression.brotli.compressor.v3.Brotli";
        };
      };
    };
  }
  {
    name = "envoy.filters.http.compressor.gzip";
    typed_config = {
      "@type" = "type.googleapis.com/envoy.extensions.filters.http.compressor.v3.Compressor";
      response_direction_config = {
        common_config = {
          min_content_length = 100;
          content_type = [
            "application/vnd.pgrst.object+json"
            "application/vnd.pgrst.array+json"
            "application/openapi+json"
            "application/geo+json"
            "text/csv"
            "application/vnd.pgrst.plan"
            "application/vnd.pgrst.object"
            "application/vnd.pgrst.array"
            "application/javascript"
            "application/json"
            "application/xhtml+xml"
            "image/svg+xml"
            "text/css"
            "text/html"
            "text/plain"
            "text/xml"
          ];
        };
        disable_on_etag_header = true;
      };
      request_direction_config = {
        common_config = {
          enabled = {
            default_value = false;
            runtime_key = "request_compressor_enabled";
          };
        };
      };
      compressor_library = {
        name = "text_optimized";
        typed_config = {
          "@type" = "type.googleapis.com/envoy.extensions.compression.gzip.compressor.v3.Gzip";
        };
      };
    };
  }
  {
    name = "envoy.filters.http.router";
    typed_config = {
      "@type" = "type.googleapis.com/envoy.extensions.filters.http.router.v3.Router";
      dynamic_stats = false;
    };
  }
]
