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

**The site must be publicly reachable, and this is where you check it.** The site has to resolve
publicly to a public IP, because OpenSEO's crawler blocks private and loopback targets and there is
no environment override. Reject at the ask:

- `localhost`, and any host ending `.local`, `.localhost`, `.localdomain`, `.internal`,
  `.home.arpa`, `.test`, `.example` or `.invalid`
- any IP literal, v4 or v6, loopback or not
- any host with no public suffix — a bare `mysite`, a single-label intranet name

A public domain that resolves to a private IP fails the same way, just later. If the site is
local-only there are two real options — offer both, and do not continue until one is in place:

- **A public tunnel.** A `cloudflared` quick tunnel is what unblocked end-to-end testing: it hands
  back a public `https://<random>.trycloudflare.com` pointing at the local port. Use that as
  `site_url`.
- **A deployed staging or production domain.** Point the skill at the deployed site instead.

Do not accept a local URL and press on. It does not fail here — it fails twice later, once as
`Enter a valid domain, like acme.com.` from `create_project` and once as a bare
`CRAWL_TARGET_BLOCKED` from the crawler, neither of which names the real cause.

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

**One exception to "exactly this content": if `.seo-god/docker-compose.yml` already exists and its
`open-seo` service carries an `env_file:` key, keep that key and its list in the rewrite.** The
MEASURE phase adds it to point at `.seo-god/secrets.env` for Google Search Console, and SKILL.md
routes back here whenever `openseo.status` is not `"running"` — so a verbatim rewrite would silently
delete the user's GSC configuration and the container would come back up with Search Console dark
and no error anywhere. It is the one line in this file that is user state rather than skill state.
Nothing else in an existing file is preserved: rewrite the rest exactly as above.

Every other line is load-bearing — do not "simplify" it:

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
- no `env_file:` **when you are writing this file for the first time** — OpenSEO's own repository
  compose file reads a `.env` and Compose errors out when that file is absent, so this one is
  self-contained on purpose. MEASURE may add one later, pointing at a secrets file it creates
  first; that is the exception above. Preserve it, never add one here yourself.
- no API keys — with `DATAFORSEO_API_KEY` unset the startup preflight logs a `[warn]` and the app
  boots and serves normally. Paid keys stay an optional power-up.

If port 3001 is already in use, change **only** the host side (the left number):
`ports: ["127.0.0.1:3005:3001"]`. Leave the container side and `PORT=3001` alone, and use the new
port in every command below and in `openseo.url`.

That host port is what steps 5 and 6 call **`<port>`** — 3001 by default, whatever you chose here
if you changed it — and **`<openseo.url>`** means `http://127.0.0.1:<port>`. Do not hardcode either:
step 5 derives them from Compose, because on the one machine where the port had to move, assuming
3001 is how you end up talking to somebody else's install.

## 4. Boot it

```
docker compose -p seo-god -f .seo-god/docker-compose.yml pull
docker compose -p seo-god -f .seo-god/docker-compose.yml up -d
```

Pull as its own step: the first download is large, and keeping it outside `up` keeps the readiness
window in step 5 meaningful. Always pass both `-p seo-god` and `-f`, in that order, in every
Compose command — the project name is what lets later phases address this same container.

If `pull` fails — no network, GHCR unreachable, a manifest or authentication error — report the
error verbatim, set `openseo.status` to `"error"`, leave `phases.setup` at `"in_progress"`, and
stop. Do not run `up -d`: there is no image to start, and the failure the user needs to see is the
pull error, not a second confusing one.

If `up` fails with `Bind for 127.0.0.1:3001 failed: port is already allocated`, another process
owns that port: return to step 3, choose a different host port, rewrite the file, **then** retry —
in that order, and the retry only ever comes after the rewrite. A bare second `up -d` against the
unchanged file exits 0 and leaves a running container with no host binding at all: it reads as
success, and step 5 then has nothing of ours to poll.

## 5. Wait for it to answer

**Resolve the address from our own Compose project first — never assume the port.** Ask Compose
what it actually published:

```
docker compose -p seo-god -f .seo-god/docker-compose.yml port open-seo 3001
```

`port` prints the public host binding for a container port; the trailing `3001` is the **container**
side, which never changes. A healthy answer looks like `127.0.0.1:3005`. The number it prints is
`<port>`, and `<openseo.url>` is `http://127.0.0.1:<port>`. Use them in every command in this step
and step 6, and record `openseo.url` from them in step 7. This is also the only thing that makes the
instance you poll *ours*: `-p seo-god` addresses the project this setup started, so a stranger's
OpenSEO on a port we guessed can no longer answer the readiness check and collect the user's site.

**Empty or absent output is a hard failure — not something to retry.** It means the container is
running with no host binding, which is exactly what a bare `up -d` retry leaves behind (step 4).
Do not poll and do not retry-and-hope: run `... down`, fix the host port in step 3, `up -d` again,
and come back here.

Poll `<openseo.url>/api/health` every 3 seconds until it returns HTTP 200, for up to 90 seconds:

```
curl -s -o /dev/null -w "%{http_code}" <openseo.url>/api/health
```

**Shell rule — applies to every curl command in this file, here and in step 6.** Check which shell
you are in before the first request:

- macOS, Linux, Git Bash: use the commands exactly as written; `\` line continuations are fine.
- Windows PowerShell: call **`curl.exe`**, never bare `curl` (in Windows PowerShell 5.1 `curl` is
  an alias for `Invoke-WebRequest`, which rejects these flags), put the **whole command on one
  line** (a POSIX `\` continuation is a PowerShell parse error), and use `NUL` in place of
  `/dev/null`. The poll above becomes:
  `curl.exe -s -o NUL -w "%{http_code}" <openseo.url>/api/health`
- Windows PowerShell, any request with a **JSON body** (all of step 6): do not inline the JSON.
  Write it to a file and pass `-d "@thatfile"` — see the worked example in step 6. Verified:
  PowerShell 5.1 silently strips the inner quotes out of a single-quoted JSON argument (curl then
  receives `{jsonrpc:2.0,...}` and the call fails), while the backslash-escaped form that fixes 5.1
  breaks on PowerShell 7, which passes the backslashes through literally. The `@file` form is the
  only one that arrives byte-identical on both.

Use `127.0.0.1`, not `localhost`. The compose file publishes on IPv4 loopback, and on some machines
`localhost` resolves to IPv6 `::1` first — where either nothing listens or, worse, an unrelated
local dev server answers and you conclude the wrong thing. (Seen in testing: `localhost:<port>`
returned a different application's HTML while OpenSEO answered correctly on `127.0.0.1:<port>`.)

Expect roughly 45-60 seconds from `up -d` to the first 200 once the image is pulled — the container
builds the app on first start, which upstream documents as 1-2 minutes. Every container recreate
rebuilds; that is normal and the data volume is untouched.

If 90 seconds pass without a 200, do not declare failure yet — look:

```
docker compose -p seo-god -f .seo-god/docker-compose.yml logs --tail 40
```

- `Building client + server...` → still building. Keep polling, hard cap 5 minutes. If that cap
  passes with still no 200, treat it as a failure on the same protocol as the exited case below:
  report the last log lines verbatim, set `openseo.status` to `"error"`, leave `phases.setup` at
  `"in_progress"`, and stop.
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

The shell rule from step 5 governs every command below. The blocks are written for macOS, Linux and
Git Bash; on Windows PowerShell use `curl.exe`, one line, with the JSON body in a file.

First list what already exists, so a re-run does not create a duplicate:

```
curl -s -X POST <openseo.url>/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_projects","arguments":{}}}'
```

The same call on Windows PowerShell — write the body to a scratch file, then one line. This is the
pattern for every request in this step; adapt the payload and reuse it:

```
'{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_projects","arguments":{}}}' | Set-Content -Path .seo-god\mcp-body.json -Encoding ascii
curl.exe -s -X POST <openseo.url>/mcp -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -d "@.seo-god/mcp-body.json"
```

The reply's `result.structuredContent.projects` is an array of
`{ id, name, domain, locationCode, languageCode, url }` — `domain` is the bare host OpenSEO stored
(`example.com`), and `result.content[0].text` carries the same list as one human-readable string.
Compare the site's host against each `domain`: on a match, reuse that project's `id` and skip the
create. An empty array (`"Projects (0)"`) means nothing is registered yet.

Otherwise create one. `name` is the only required argument; `domain` is optional but you should
always send it, because it sets the default target for the domain, backlink and rank tools. Pass
`site_url` straight through as `domain` — OpenSEO normalizes it to the bare registrable host
(`https://www.example.com/blog` becomes `example.com`):

```
curl -s -X POST <openseo.url>/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"create_project","arguments":{"name":"example.com","domain":"https://example.com"}}}'
```

The reply carries `result.structuredContent.project` with `id`, `name`, `domain`, `locationCode`,
`languageCode` and `url`. Confirm the project page answers: `<openseo.url>/p/<id>` → 200.

The default market is `locationCode: 2840` / `languageCode: "en"` (United States / English). If the
user's audience is elsewhere, tell them they can change the project's market in the dashboard —
do not guess it for them.

Do not store the project id in `seo-god.json`; the state schema in SKILL.md does not carry one.
Later phases resolve it by calling `list_projects` and matching the site's host.

**If the MCP call fails for any reason**, fall back to the dashboard: ask the user to open
`<openseo.url>/projects` and add the site there, then re-run the `list_projects` call above
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
