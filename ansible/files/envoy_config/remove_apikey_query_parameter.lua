function envoy_on_request(request_handle)
  local path = request_handle:headers():get(":path")

  -- Remove `apikey` query parameter since PostgREST treats query parameters as conditions.
  request_handle
    :headers()
    :replace(":path", path:gsub("([&?])apikey=[^&]+&?", "%1"):gsub("&$", ""))

  -- Removes the x-sb-origin-protection-key as it can be inspected via PostgREST pre-request hook, etc.
  request_handle
    :headers()
    :replace("x-sb-origin-protection-key", "")
end
