# Palacioc 

> Conversational Mind Palace Language Learning Tool

Write "model" conversations in a language you know, then translate each message
1-to-1 into a target language (a message can have several alternative
translations). Conversations branch: a message can have several replies, so a
conversation is a tree whose *routes* are root-to-leaf paths, added over time.
The goal is comprehensible input built from vocabulary you generate.

## Stack

Zig 0.16.0, [httpz](https://github.com/karlseguin/http.zig),
[pg.zig](https://github.com/karlseguin/pg.zig) (Postgres), and
[zmpl](https://github.com/jetzig-framework/zmpl) templates with
[htmx](https://htmx.org) (vendored, embedded in the binary). No auth, single tenant.

```
src/cmd/server     entrypoint
src/internal       routes/ (JSON api + router), web/ (HTMX handlers, forms, views), types/ (DB access), config/
src/pkg/contract   typed request-input helper
src/sql/schema.sql schema (conversation, message, translation)
html/              zmpl templates, static/app.css, static/htmx
dev/               docker-compose, Dockerfile, bruno/ collection
third_party/zmpl   vendored zmpl (see below)
```

Messages form a tree through `message.parent_message_id` (NULL = root; several
roots allowed). Routes come from a recursive CTE; deleting a message deletes its
subtree and translations. Languages are short BCP 47-style codes (`en`, `pt-BR`).

### Vendored zmpl

`third_party/zmpl` is jetzig-framework/zmpl pinned at `0cb5ef8` plus a one-line
Zig 0.16 fix (the manifest writer was not flushed, truncating the generated
manifest). See `third_party/zmpl/PATCHES.md`; drop the copy once upstream flushes.

## Local Development

Requirements: [Zig 0.16.0](https://ziglang.org/download/) and Docker (with Compose).

### Database

```sh
docker compose -f dev/docker-compose.yaml up -d postgres
```

Postgres listens on `127.0.0.1:5432` (user/db `palacioc`). Credentials can be
overridden with `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` and
`POSTGRES_PORT` in `dev/.env`. `src/sql/schema.sql` is applied only when the
data volume is first created (the rewrite changed the schema, so existing volumes
need `down -v`); to reset the database and re-apply it:

```sh
docker compose -f dev/docker-compose.yaml down -v
```

### Build, Run, Test

```sh
zig build          # build into zig-out/
zig build run      # build and run the server
zig build test     # run unit tests
```

The server reads `PALACIOC_DB_CONNECTION_URI` (default
`postgres://postgres:postgres@localhost:5432/postgres`), `PALACIOC_LISTEN_PORT`
(8080), `PALACIOC_LISTEN_ALL_INTERFACES` (`true`), `PALACIOC_DB_CONNECTION_POOL_SIZE`
and `PALACIOC_DB_FAIL_ON_CONNECTION`. For the dev database:

```sh
PALACIOC_DB_CONNECTION_URI=postgres://palacioc:hairy-horse-password-123@127.0.0.1:5432/palacioc zig build run
```

Then open <http://localhost:8080/>. The integration tests (one per API group) run
against a real database and are skipped unless `PALACIOC_TEST_DB_URI` is set to
the same kind of URI.

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

## UI

`GET /` lists/searches/creates conversations; `GET /ui/conversation/:id` shows
the tree. Click a message for its panel: add a translation, add a new message
(new branch), edit, delete, show route. Full-page loads render `html/layout.zmpl`;
htmx requests (`HX-Request: true`) get fragments. Everything else is under `/ui/...`.

## JSON API

Responses are JSON; request bodies are form-urlencoded. Errors are `{"err": msg}`
(400 bad input, 404 missing, 503 no database, 500 otherwise). Timestamps are
microseconds since the Unix epoch. A Bruno collection is in `dev/bruno/`.

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/health` | |
| GET | `/api/conversation/search?s=&p=&l=` | title substring `s`, offset `p`, limit `l` (max 100) |
| POST | `/api/conversation` | `title`, `description`, `source_language` (en), optional `initial_message` + `initial_message_role` |
| GET / PUT / DELETE | `/api/conversation/:id` | PUT takes any of `title`, `description`, `source_language` |
| GET | `/api/conversation/:id/tree` | nested messages with translations |
| POST | `/api/message` | `content`, `role` (person), and `parent_message_id` (child) or `conversation_id` (root) |
| GET / PUT / DELETE | `/api/message/:id` | PUT takes `content`, `role`; DELETE removes the subtree |
| GET | `/api/message/:id/route` | root-to-message path with translations |
| GET | `/api/message/:id/translations` | |
| POST | `/api/translation` | `message_id`, `language`, `content` |
| PUT / DELETE | `/api/translation/:id` | PUT takes `language`, `content` |
