{
  mappers = [
    {
      filter = {
        and_filter = {
          filters = [
            {
              status_code_filter = {
                comparison = {
                  value = {
                    default_value = 403;
                    runtime_key = "unused";
                  };
                };
              };
            }
            {
              header_filter = {
                header = {
                  name = ":path";
                  string_match = {
                    prefix = "/customer/v1/privileged/";
                  };
                };
              };
            }
          ];
        };
      };
      status_code = 401;
      body = {
        inline_string = "Unauthorized";
      };
      headers_to_add = [
        {
          header = {
            key = "WWW-Authenticate";
            value = "Basic realm=\"Unknown\"";
          };
        }
      ];
    }
    {
      filter = {
        and_filter = {
          filters = [
            {
              status_code_filter = {
                comparison = {
                  value = {
                    default_value = 403;
                    runtime_key = "unused";
                  };
                };
              };
            }
            {
              header_filter = {
                header = {
                  name = ":path";
                  string_match = {
                    prefix = "/metrics/aggregated";
                  };
                  invert_match = true;
                };
              };
            }
          ];
        };
      };
      status_code = 401;
      headers_to_add = [
        {
          header = {
            key = "x-sb-error-code";
            value = "%RESPONSE_CODE_DETAILS%";
          };
        }
      ];
      body_format_override = {
        json_format = {
          message = "`apikey` request header or query parameter is either missing or invalid. Double check your Supabase `anon` or `service_role` API key.";
          hint = "%RESPONSE_CODE_DETAILS%";
        };
        json_format_options = {
          sort_properties = false;
        };
      };
    }
  ];
}
