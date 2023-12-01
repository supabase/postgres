function envoy_on_request(request_handle)
    local authorization = request_handle:headers():get("authorization")

    if authorization and authorization:find("^[Bb][Aa][Ss][Ii][Cc] " .. request_handle:metadata():get("credentials")) then
        return
    end

    request_handle:respond({
        [":status"] = "401",
        ["WWW-Authenticate"] = "Basic realm=\"Unknown\""
    }, "Unauthorized")
end
