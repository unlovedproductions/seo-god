# Setup — OpenSEO boot and site registration

Goal: OpenSEO running locally in Docker, the user's site registered as a project, and
`seo-god.json` written with `openseo.status: "running"` and `phases.setup: "done"`.

Everything below happens in the USER's project directory — the current working directory. Never
install anything into the skill folder.

Verified against OpenSEO `0.1.3`, image `ghcr.io/every-app/open-seo:latest`, published multi-arch
for `linux/amd64` and `linux/arm64` (Apple Silicon included). Nothing is built from source and no
repository needs cloning.

> **WARNING — OpenSEO's built-in cron does NOT fire inside Docker. The SCHEDULE phase drives it
> from your OS scheduler instead.**
>
> The container states this itself at startup:
> `[info] Scheduled checks: Rank-tracking schedules do not run in Docker mode — trigger checks
> from the Rank Tracking page.`
>
> Anything that must happen on a timer — rank checks, crawls, the daily loop — is triggered from
> outside the container. Never promise the user recurring anything until `references/schedule.md`
> has run.

## 1. Prerequisites

```
docker --version
docker compose version
git --version
```

- **`docker` missing, or `docker compose version` fails** → stop and ask the user to install it,
  then re-run `/seo-god`. Compose must be the v2 subcommand (`docker compose`), not the legacy
  `docker-compose` binary. Install links:
  - macOS — https://docs.docker.com/desktop/install/mac-install/
  - Windows — https://docs.docker.com/desktop/install/windows-install/
  - Linux — https://docs.docker.com/engine/install/ (Docker Engine already ships Compose v2)
- **Docker installed but not running** — commands fail with "cannot connect to the Docker daemon"
  (or a named-pipe error on Windows) → ask the user to start Docker Desktop, or
  `sudo systemctl start docker` on Linux, then re-run. Do not continue.
- **`git` missing** → not fatal here, but say so plainly: the AUDIT and ACT phases edit files in
  the user's repository, and `seo-god.json` is meant to be committed. Point at
  https://git-scm.com/downloads and continue.

## 2. Ask for the site URL

Ask: *"What is the full URL of the site you want to work on?"*

Require a scheme and a host (`https://example.com`). Reject examples and placeholders. Read the
value back for confirmation before using it. This becomes `site_url`.

Create `seo-god.json` now, in the project root, using the version 1 shape defined in SKILL.md:
`site_url` filled in, `phases.setup` set to `"in_progress"`, everything else at its documented
default. Writing it here — before the slow steps — is what makes an interrupted setup resumable.

## 3. Write the compose file

`.seo-god/` must be gitignored before anything is written into it: check the project `.gitignore`
for a `.seo-god/` line and add it if missing.

Write `.seo-god/docker-compose.yml` with exactly this content:

```yaml
services:
  open-seo:
    image: ghcr.io/every-app/open-seo:latest
    ports: ["127.0.0.1:3001:3001"]
    environment:
      - AUTH_MODE=local_noauth
      - CLOUDFLARE_INCLUDE_PROCESS_ENV=true
      - PORT=3001
    volumes:
      - openseo-data:/app/.wrangler
    restart: unless-stopped
volumes:
  openseo-data:
```

Every line is load-bearing — do not "simplify" it:

- `127.0.0.1:` in the port mapping — `local_noauth` means the dashboard has **no authentication at
  all**. A bare `3001:3001` publishes it on every interface, i.e. to the whole local network. Keep
  the loopback bind unless the user explicitly puts their own authenticated proxy in front.
- `AUTH_MODE=local_noauth` — the only auth mode that works for a local Docker install. Any other
  value requires Cloudflare Access or hosted OAuth credentials, and the container's startup
  preflight exits with `[FAIL]` instead of booting.
- `CLOUDFLARE_INCLUDE_PROCESS_ENV=true` — required for local Docker self-hosting so Compose's
  environment reaches the app's runtime bindings.
- `openseo-data:/app/.wrangler` — the application database lives at `/app/.wrangler`. A volume
  mounted anywhere else (`/data`, for instance) persists **nothing**: the container starts fine,
  then every recreate silently comes back with an empty database and no projects.
- no `env_file:` — OpenSEO's own repository compose file reads a `.env` and Compose errors out when
  that file is absent. This one is self-contained on purpose.
- no API keys — with `DATAFORSEO_API_KEY` unset the startup preflight logs a `[warn]` and the app
  boots and serves normally. Paid keys stay an optional power-up.

If port 3001 is already in use, change **only** the host side (the left number):
`ports: ["127.0.0.1:3005:3001"]`. Leave the container side and `PORT=3001` alone, and use the new
port in every command below and in `openseo.url`.

## 4. Boot it

```
docker compose -p seo-god -f .seo-god/docker-compose.yml pull
docker compose -p seo-god -f .seo-god/docker-compose.yml up -d
```

Pull as its own step: the first download is large, and keeping it outside `up` keeps the readiness
window in step 5 meaningful. Always pass both `-p seo-god` and `-f`, in that order, in every
Compose command — the project name is what lets later phases address this same container.

If `up` fails with `Bind for 127.0.0.1:3001 failed: port is already allocated`, another process
owns that port: return to step 3, choose a different host port, rewrite the file, retry.

## 5. Wait for it to answer

Poll `http://127.0.0.1:3001/api/health` every 3 seconds until it returns HTTP 200, for up to 90
seconds.

Use `127.0.0.1`, not `localhost`. The compose file publishes on IPv4 loopback, and on some machines
`localhost` resolves to IPv6 `::1` first — where either nothing listens or, worse, an unrelated
local dev server answers and you conclude the wrong thing. (Seen in testing: `localhost:3001`
returned a different application's HTML while OpenSEO answered correctly on `127.0.0.1:3001`.)

Expect roughly 45-60 seconds from `up -d` to the first 200 once the image is pulled — the container
builds the app on first start, which upstream documents as 1-2 minutes. Every container recreate
rebuilds; that is normal and the data volume is untouched.

If 90 seconds pass without a 200, do not declare failure yet — look:

```
docker compose -p seo-god -f .seo-god/docker-compose.yml logs --tail 40
```

- `Building client + server...` → still building. Keep polling, hard cap 5 minutes.
- `[FAIL]` preflight lines → the container refuses to start; fix exactly what the line names
  (almost always `AUTH_MODE`) and retry from step 4.
- container exited or no such service → report the log verbatim, set `openseo.status` to `"error"`,
  leave `phases.setup` at `"in_progress"`, and stop. Do not continue to registration.

A ready response is JSON carrying `status`, `version`, `authMode` and a `checks` map with one entry
each for `auth`, `dataforseo`, `gsc`, `ai` and `database` — on a healthy free-path install,
`"status":"ok"`, `"authMode":"local_noauth"`, and `checks.database.status` `"ok"`.

`checks.dataforseo.status` is `"warn"` ("Not set") on the free path. Warnings do not change the
overall `status`, which stays `"ok"`; only a check in `"error"` flips it to `"issues"`. Report the
DataForSEO warning as a known, intended state — never as an error, and never as a reason to ask the
user for a paid key.

## 6. Register the user's site

OpenSEO exposes an MCP server at `POST /mcp` on the same port. Under `local_noauth` it needs no
token and no `initialize` handshake — it is stateless JSON-RPC over a single HTTP POST, so plain
curl is enough. Do not add an MCP server to the user's Claude config for this; a new MCP server
would not be usable until their next session anyway.

On Windows, call `curl.exe`, not `curl`: in Windows PowerShell 5.1 `curl` is an alias for
`Invoke-WebRequest` and these flags will fail. (PowerShell 7 has no such alias, and `curl.exe` is
correct in both.)

First list what already exists, so a re-run does not create a duplicate:

```
curl -s -X POST http://127.0.0.1:3001/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_projects","arguments":{}}}'
```

If a project already carries the site's host as its domain, reuse it and skip the create.

Otherwise create one. Pass `site_url` straight through as `domain` — OpenSEO normalizes it to the
bare registrable host (`https://www.example.com/blog` becomes `example.com`):

```
curl -s -X POST http://127.0.0.1:3001/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"create_project","arguments":{"name":"example.com","domain":"https://example.com"}}}'
```

The reply carries `result.structuredContent.project` with `id`, `name`, `domain`, `locationCode`,
`languageCode` and `url`. Confirm the project page answers: `http://127.0.0.1:3001/p/<id>` → 200.

The default market is `locationCode: 2840` / `languageCode: "en"` (United States / English). If the
user's audience is elsewhere, tell them they can change the project's market in the dashboard —
do not guess it for them.

Do not store the project id in `seo-god.json`; the state schema in SKILL.md does not carry one.
Later phases resolve it by calling `list_projects` and matching the site's host.

**If the MCP call fails for any reason**, fall back to the dashboard: ask the user to open
`http://127.0.0.1:3001/projects` and add the site there, then re-run the `list_projects` call above
to read the id back and confirm. Registration is not complete until a project actually exists.

## 7. Finish the state file

Update `seo-god.json` — read, modify, write the whole object, preserving every key you do not
recognise:

- `site_url` — the confirmed URL from step 2.
- `openseo.url` — the base URL that actually answered 200, including the port you used.
- `openseo.status` — `"running"`.
- `phases.setup` — `"done"`.

Write it to disk immediately, then return to SKILL.md.

## 8. Hand back

Tell the user, briefly and without embellishment:

- OpenSEO is running at the URL you recorded, bound to loopback only, no authentication in front of
  it — that is why it is not exposed beyond their machine.
- Which project was created or reused, and its market.
- That no paid keys are configured, that this is the intended free path, and that DataForSEO-backed
  numbers stay unavailable until they opt into the power-up.
- Restart/stop commands, so they are not stuck:
  `docker compose -p seo-god -f .seo-god/docker-compose.yml up -d` /
  `... down` (keeps data) / `... down -v` (deletes the database).
- What is next: AUDIT. And that scheduling is a separate phase, for the reason in the warning box
  at the top of this file.
