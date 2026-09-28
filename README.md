# Palacioc 

> Conversational Mind Palace Language Learning Tool

This is under active construction. More information will be available.

## Local Development

Requirements: [Zig 0.16.0](https://ziglang.org/download/) and Docker (with Compose).

### Database

```sh
docker compose -f dev/docker-compose.yaml up -d postgres
```

Postgres listens on `127.0.0.1:5432` (user/db `palacio`). Credentials can be
overridden with `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` and
`POSTGRES_PORT` in `dev/.env`. `src/sql/schema.sql` is applied only when the
data volume is first created; to reset the database and re-apply it:

```sh
docker compose -f dev/docker-compose.yaml down -v
```

### Build, Run, Test

```sh
zig build          # build into zig-out/
zig build run      # build and run the server
zig build test     # run unit tests
```

No local Zig? Use the toolchain container instead:

```sh
docker compose -f dev/docker-compose.yaml run --rm zig zig build test
```

### Server Image

```sh
docker build -f dev/Dockerfile -t palacioc-server .
```

The toolchain, dependency fetch and build are all stages of `dev/Dockerfile`,
so a single build produces everything. After the first (online) build, the
cached layers let source changes rebuild offline.
