function envoy_on_request(request_handle)
  local path = request_handle:headers():get(":path")

  -- Remove `apikey` query parameter since PostgREST treats query parameters as conditions.
  request_handle
    :headers()
    :replace(":path", path:gsub("([&?])apikey=[^&]+&?", "%1"):gsub("&$", ""))
end
