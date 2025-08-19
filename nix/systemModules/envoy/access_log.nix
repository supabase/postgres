[
  {
    name = "envoy.access_loggers.stdout";
    filter = {
      status_code_filter = {
        comparison = {
          op = "GE";
          value = {
            default_value = 400;
            runtime_key = "unused";
          };
        };
      };
    };
    typed_config = {
      "@type" = "type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog";
    };
  }
]
