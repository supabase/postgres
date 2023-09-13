# Supabase All-in-One

All Supabase backend services bundled in a single Docker image for quick local testing and edge deployment.

## Build

```bash
# cwd: repo root
docker build -f docker/all-in-one/Dockerfile -t supabase/all-in-one .
```

## Run

```bash
docker run --rm -it \
    -e POSTGRES_PASSWORD=postgres \
    -e JWT_SECRET=super-secret-jwt-token-with-at-least-32-characters-long \
    -e ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJhbm9uIiwKICAgICJpc3MiOiAic3VwYWJhc2UtZGVtbyIsCiAgICAiaWF0IjogMTY0MTc2OTIwMCwKICAgICJleHAiOiAxNzk5NTM1NjAwCn0.dc_X5iR_VP_qT0zsiyj_I_OZ2T9FtRU2BBNWN8Bu4GE \
    -e SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJzZXJ2aWNlX3JvbGUiLAogICAgImlzcyI6ICJzdXBhYmFzZS1kZW1vIiwKICAgICJpYXQiOiAxNjQxNzY5MjAwLAogICAgImV4cCI6IDE3OTk1MzU2MDAKfQ.DaYlNEoUrrEn2Ig7tqibS-PHK5vgusbcbo7X36XVt4Q \
    -e ADMIN_API_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic3VwYWJhc2VfYWRtaW4iLCJpc3MiOiJzdXBhYmFzZS1kZW1vIiwiaWF0IjoxNjQxNzY5MjAwLCJleHAiOjE3OTk1MzU2MDB9.Y9mSNVuTw2TdfryoaqM5wySvwQemGGWfSe9ixcklVfM \
    -e DATA_VOLUME_MOUNTPOINT=/data \
    -e MACHINE_TYPE=shared_cpu_1x_512m \
    -p 5432:5432 \
    -p 8000:8000 \
    supabase/all-in-one
```

Use bind mount to start from an existing physical backup: `-v $(pwd)/data:/var/lib/postgresql/data`

Alternatively, the container may be initialised using a payload tarball.

```bash
docker run --rm \
    -e POSTGRES_PASSWORD=postgres \
    -e INIT_PAYLOAD_PRESIGNED_URL=<init_payload_url> \
    -p 5432:5432 \
    -p 8000:8000 \
    -it supabase/all-in-one
```

## Test

```bash
curl -H "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJhbm9uIiwKICAgICJpc3MiOiAic3VwYWJhc2UtZGVtbyIsCiAgICAiaWF0IjogMTY0MTc2OTIwMCwKICAgICJleHAiOiAxNzk5NTM1NjAwCn0.dc_X5iR_VP_qT0zsiyj_I_OZ2T9FtRU2BBNWN8Bu4GE" \
    localhost:8000/rest/v1/ | jq
```

## TODO

- [x] optimise admin config
- [x] propagate shutdown signals
- [x] add http health checks
- [x] generate dynamic JWT
- [ ] ufw / nftables
- [x] log rotation
- [ ] egress metrics
- [x] vector
- [ ] apparmor
- [ ] wal-g
