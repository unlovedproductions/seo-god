# Measure — Search Console, snapshots, regression-first diff

Goal: Google Search Console connected (or explicitly skipped), a tracked keyword list agreed with
the user, today's snapshot written to the user's repository, a regression-first diff against the
newest previous snapshot, and `phases.measure` at `"done"`.

Everything happens in the USER's project directory — the current working directory. Never write
anything into the skill folder.

Honesty rule for this whole phase:

> **A section you did not measure is reported as "not measured" — never as zero.**

The snapshot carries two flags for exactly this: `gsc.available` and `ai_visibility.measured`.
`false` means "nobody measured it", which is a different fact from "it measured zero", and every
readout must keep them different. A rank you did not check is `null`, not 0. A query set you could
not read is absent, not empty. If you ever find yourself writing a 0 because a call failed, stop —
that is the failure this phase exists to prevent.

## 1. Read state, resolve the project

Read `seo-god.json` from the current working directory:

- `site_url` — the site being measured.
- `openseo.url` — the base URL of the running container, port included. Never hardcode `localhost`
  or `127.0.0.1`; use whatever setup recorded, because that is the address that actually answered.
- `keywords` — the tracked keyword list, if a previous run of this phase stored one.

Set `phases.measure` to `"in_progress"` and write the file to disk now, preserving every key you do
not recognise. Doing it before the slow steps is what makes an interrupted measure resumable.

**Loop-breaker — check the host first.** If `site_url`'s host fails `references/setup.md` section 2's
public-reachability rule — `localhost`, an IP literal, a `.local` / `.localhost` / `.internal` /
`.test` / `.example`-class suffix, or any host with no public suffix — say so and stop here, with
setup's two options: a public tunnel or a deployed domain. Do **not** route back to
`references/setup.md` for this; it refuses the same host, and the round trip never terminates.

Resolve the OpenSEO project id every run — state does not store it. Call `list_projects` (call
pattern in section 2) and match the host of `site_url` against each project's `domain`. No match
means setup did not finish; go back to `references/setup.md`. Every tool below takes `projectId`
and it is **required**.

**If OpenSEO stops answering at any point in this phase** — a connection refused, a timeout, a
non-200 from `<openseo.url>/api/health` — stop where you are, on the same protocol section 5.2 uses
for a crawl that cannot complete: report the failure verbatim and which step it happened on, leave
`phases.measure` at `"in_progress"`, and **write no snapshot**. A partial snapshot is worse than
none, because tomorrow's diff will read it as measured fact. Never fill the missing sections from
the previous snapshot, from memory, or from an estimate. Point the user at `references/setup.md` to
get the container back up; the phase resumes from the start on the next run.

## 2. The OpenSEO call pattern

Identical to `references/audit.md` section 3: stateless JSON-RPC over a single
`POST <openseo.url>/mcp`, no token, no `initialize` handshake, body written to
`.seo-god/mcp-body.json` with your Write tool and sent with `-d "@.seo-god/mcp-body.json"`.

**Shell rule — read `references/setup.md` step 5 before your first request** (`curl.exe` on Windows
PowerShell, whole command on one line, `@file` JSON bodies). It governs every request in this file.
Never inline JSON into a curl command.

**Discover the toolset first**, exactly as audit does: send
`{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}` and read the names back. This file is
written against these tools, all registered by OpenSEO's MCP server:

| Tool | What this phase uses it for | Key arguments |
| --- | --- | --- |
| `list_projects` | resolve `projectId` (section 1) | none |
| `save_keywords` | seed the tracked keyword list | `projectId`*, `keywords`* (1-100), `tags`, `tagMode`, `locationCode`, `languageCode` |
| `list_saved_keywords` | read the list back | `projectId`*, `search`, `tags`, `limit` |
| `get_rank_tracker` | rank tracker configs and their latest positions | `projectId`*, `trackerId` |
| `get_search_console_performance` | clicks / impressions / position from GSC | `projectId`*, `dimensions`, `dateRange`, `startDate`, `endDate`, `filters`, `rowLimit`, `startRow`, `type`, `dataState` |
| `run_site_audit` | crawl the site when no completed audit exists (5.2) | `projectId`*, `url`*, `maxPages`, `runLighthouse` |
| `get_audit_status` | the latest audit's id, status and `completedAt` | `projectId`*, `auditId` |
| `get_audit_issues` | the issue report for the snapshot's `crawl.issues` | `projectId`*, `auditId`, `severity`, `issueType`, `limit` |
| `get_audit_pages` | the true crawled-page count | `projectId`*, `auditId`, `fetchClass`, `statusCode`, `urlContains`, `limit` |

`*` required. Omitting `auditId` or `trackerId` means "the most recent one" / "list them all". If
`tools/list` does not return one of these names, the user is on a different OpenSEO build: use the
tools it actually lists, read their `description` and `inputSchema` for the arguments, and say in
your summary which tools you used instead. **Never call a name you have not seen in `tools/list`.**

Two traps in these schemas:

- `list_saved_keywords`'s `limit` accepts **only** `50`, `100` or `250`. Any other number is a
  validation error, so do not pass the size of your keyword list.
- `get_domain_overview` looks like the right tool for a "site overview" and is not: it charges
  DataForSEO credits. This phase is on the free path, so the site overview comes from the audit
  data instead (section 5). Do not call it.

## 3. Connect Google Search Console

GSC is the only free source of first-party truth about how the site actually performs in Google:
real clicks, impressions and average position, per query and per page. Everything else in this
phase works without it — but the quick-wins and new-queries sections of the diff are mostly empty
without it, and this is the one setup step worth ten minutes.

Self-hosted OpenSEO cannot use a shared Google client — the user brings their own OAuth client.
That is three values (`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `BETTER_AUTH_SECRET`) and a
container recreate, and none of it is optional. Walk the user through it screen by screen; do not
summarise it as "set up OAuth".

### 3.0 Already connected? Re-verify before you touch anything

**Do this first, on every run, before you ask the user anything.** This phase runs again and again;
the second run must not undo the first.

Read `gsc.connected` from `seo-god.json`.

- **`false`** → nothing is set up. Ask: *"Connect Google Search Console now, or skip it for this
  run? It takes about ten minutes in the Google Cloud Console and needs a Search Console property
  you have already verified."* Connect → 3.1. Skip → 3.7.
- **`true`** → run the verification call in **3.6** right now, before anything else.
  - `ok: true` → GSC is live. **Skip 3.1 through 3.5 entirely**, leave `gsc.connected` at `true`,
    tell the user in one line that Search Console is already connected, and go to section 4. Do not
    ask the connect-or-skip question: there is nothing to connect, and an answer of "skip" here
    would disconnect a working integration. Do not re-run the OAuth walkthrough, and above all do
    not touch the compose file — a second `env_file:` key is a duplicate mapping key and Compose
    refuses to parse the file at all, which takes the container down.
  - `ok: false` → the connection existed and has stopped working: a revoked or expired grant, a
    property unbound in the dashboard, or a container recreated without the environment. Tell the
    user what `reason` came back, then re-enter the walkthrough at the step that reason points at
    (3.6 lists the mapping). Only now may `gsc.connected` become `false`.

### 3.1 Google Cloud project, and the Search Console API

1. They open https://console.cloud.google.com/ and either create a project or pick an existing one
   (the project picker is in the top bar, left of the search box).
2. They enable the **Google Search Console API** for that project:
   https://console.cloud.google.com/apis/library/searchconsole.googleapis.com → **Enable**. Check
   the project picker on that page shows the project they just chose — enabling the API on the
   wrong project is the quietest way to lose twenty minutes.

### 3.2 OAuth consent screen

**APIs & Services → OAuth consent screen**:

- User type **External**, unless every person who will connect is inside their Google Workspace
  organisation.
- Fill in app name, user support email, developer contact email. Nothing here is shown to anyone
  but them.
- While the app is in **Testing**, they add — under **Test users** — every Google account that will
  connect. An account that is not listed gets `access_denied` at sign-in, and Google's error page
  does not explain why.

They do not need to submit for verification. Testing mode is enough for personal or internal use.

### 3.3 OAuth client ID, and the redirect URI that must match exactly

**APIs & Services → Credentials → Create credentials → OAuth client ID**:

1. Application type: **Web application**.
2. Under **Authorized redirect URIs**, add the URI OpenSEO will send Google back to. OpenSEO builds
   it as **the origin the browser is on, plus `/api/gsc/oauth/callback`** — so it is decided by
   what the user types in the address bar, not by anything in state.

   Take the port from `openseo.url` and add **both** loopback forms, so either address works:

   ```
   http://localhost:<port>/api/gsc/oauth/callback
   http://127.0.0.1:<port>/api/gsc/oauth/callback
   ```

   With the default port that is `http://localhost:3001/api/gsc/oauth/callback` — the form
   OpenSEO's own self-hosting documentation names for local Docker. Scheme, host and port must
   match exactly and there is no trailing slash. If Google refuses to save one of the two lines,
   keep the one it accepts and remember that the user must browse to that exact origin in 3.5.

   If the user reaches OpenSEO through anything other than loopback — a reverse proxy, a tunnel, a
   LAN address — the redirect URI is *that* origin plus the same path, and it is the only one that
   will work.
3. Save, then copy the **Client ID** and the **Client secret** from the dialog.

### 3.4 Give OpenSEO the three values

Secrets go in `.seo-god/secrets.env`, which is inside the already-gitignored `.seo-god/` directory.
Before writing, make sure the project `.gitignore` contains `.seo-god/`; add the line if not — setup
put it there, and a missing line means the next commit ships the user's Google client secret. Never
put any of these values in `seo-god.json`, and never echo them back to the user.

1. Ask the user to paste the client ID and client secret. Write them with your Write tool to
   `.seo-god/secrets.env`, one `KEY=value` per line, **no quotes and no `export`** — Compose reads
   this file literally, so surrounding quotes become part of the value. **End the file with a
   newline**; step 2 appends to it:

   ```
   GOOGLE_CLIENT_ID=<the client ID they pasted>
   GOOGLE_CLIENT_SECRET=<the client secret they pasted>
   ```

2. Append a `BETTER_AUTH_SECRET` of at least 32 characters — it encrypts the stored OAuth tokens at
   rest, and Search Console stays disabled without it. Generate it straight into the file so it
   never appears in the transcript. Both forms write a **leading blank line** so the append can
   never concatenate onto an unterminated last line — a `GOOGLE_CLIENT_SECRET=…BETTER_AUTH_SECRET=…`
   splice corrupts both values, and Google then answers the OAuth exchange with `invalid_client`:

   - macOS, Linux, Git Bash:
     `printf '\nBETTER_AUTH_SECRET=%s\n' "$(openssl rand -base64 32)" >> .seo-god/secrets.env`
   - Windows PowerShell (one line):
     `$b=New-Object byte[] 32; [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); Add-Content -Path .seo-god/secrets.env -Value @("", "BETTER_AUTH_SECRET=" + [Convert]::ToBase64String($b))`

   Compose ignores blank lines in an env file, so the extra newline costs nothing. Afterwards check
   the file has exactly three `KEY=` lines — without ever printing their values.

3. Point the container at the file. **First look at `.seo-god/docker-compose.yml`: if it already
   has an `env_file:` key, leave it exactly as it is and go to step 4.** A second `env_file:` under
   the same service is a duplicate mapping key and Compose refuses to parse the file at all, which
   takes the container down. Only when the key is absent, add it to the `open-seo` service as a
   sibling of `environment:`:

   ```yaml
       env_file:
         - secrets.env
   ```

   The path is bare because Compose resolves `env_file` relative to the compose file's own
   directory — which is `.seo-god/`. Create `secrets.env` **before** adding this line: Compose
   errors out when an `env_file` is missing, and that error looks nothing like a GSC problem.

   One line to tell the user: `references/setup.md` step 3 rewrites this compose file verbatim, and
   SKILL.md routes back to setup whenever `openseo.status` is not `"running"`. That file now carries
   a clause preserving an existing `env_file:` line — but if the line ever disappears after a setup
   re-run, GSC goes dark silently and this is the first place to look.

4. Recreate the container so Compose reapplies the environment. Editing the file alone does not do
   it:

   ```
   docker compose -p seo-god -f .seo-god/docker-compose.yml up -d --force-recreate open-seo
   ```

   A recreate rebuilds the app (1-2 minutes, data volume untouched — see `references/setup.md`
   step 5), so poll `<openseo.url>/api/health` until it returns 200 again before continuing.

5. **Verify from the health endpoint, and read `detail`, not `status`.** `checks.gsc.status` is
   `"ok"` both when GSC is fully configured *and* when it is not configured at all — the two are
   only distinguishable by the text:

   - `checks.gsc.detail` is `"Configured"` → correct, continue.
   - `"Not configured (optional)…"` → the container did not receive the variables. The `env_file`
     line or the recreate did not take.
   - `"Only one of GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET is set…"` → a typo or a blank value.
   - `"…stays DISABLED until BETTER_AUTH_SECRET is at least 32 characters…"` → the generated
     secret did not land. Re-run step 2.

   Do not go to 3.5 until the detail reads `Configured`.

### 3.5 Authorise Google

The user opens OpenSEO in a browser at **the same origin they registered in 3.3** — if they
registered `http://localhost:3001` they must browse to `http://localhost:3001`, not `127.0.0.1`.
Ask them to confirm the OpenSEO dashboard loads there. If that address shows nothing or a different
application (some machines resolve `localhost` to IPv6 while the container is published on IPv4
loopback — `references/setup.md` step 5), they use the other form, and that other origin's callback
must be one of the URIs saved in 3.3.

Then, on the project's **Search performance** page (`<openseo.url>/p/<projectId>/search-performance`,
which hosts the connection card and the data; **Project settings → Search Console** and the project
dashboard show the same card):

1. **Connect with Google** → Google's account chooser → the account that owns the verified property
   → consent (read-only Search Console access).
2. Google returns them to OpenSEO and the card becomes a property picker. They select the Search
   Console property to bind to this project and save. The card then reads **Connected** with the
   property URL.

Troubleshooting, by the exact symptom:

- **`redirect_uri_mismatch`** — the origin in the address bar is not one of the URIs saved in 3.3.
  Read the address bar, add that exact origin plus `/api/gsc/oauth/callback`, and retry.
- **`access_denied`** — the Google account is not a test user on the consent screen (3.2).
- **`invalid_client`** — Google rejected the client ID or secret. Either the value was pasted
  wrong, or `.seo-god/secrets.env` has a spliced line because an append landed on a file with no
  trailing newline (3.4 step 2). Check the file has exactly three `KEY=` lines, fix it, and recreate
  the container.
- **"Google OAuth client not configured"** on the card — the container does not have all three
  values. Back to 3.4 step 5.
- **Connected, but the property list is empty** — that Google account has no verified property in
  Search Console. They verify the site at https://search.google.com/search-console first, then
  reconnect. This is a real blocker, not a warning: without a verified property there is no data.

### 3.6 Verify through the API, not the screenshot

The card saying "Connected" is the browser's opinion. Confirm the thing this phase actually depends
on — that the MCP tool can read data — with body:

```json
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_search_console_performance","arguments":{"projectId":"<projectId>","dimensions":["date"],"dateRange":"last_7_days"}}}
```

`result.structuredContent.ok` is `true` → connected. Set `gsc.connected` to `true` in
`seo-god.json` and continue.

`ok` is `false` → read `reason`: `"not_connected"` (the property binding did not save — redo 3.5),
`"gsc_oauth_not_configured"` (back to 3.4 step 5), `"api_error"` (the message is in the reply's
text; a revoked or expired grant needs a reconnect). Leave `gsc.connected` at `false` and treat the
rest of this phase as the skip path. **Never set `gsc.connected` to `true` on the strength of the
card alone.**

If you arrived here from 3.0's re-verification, return to 3.0's `ok: false` bullet instead of taking
the skip path — that branch owns the routing for an already-connected project.

### 3.7 If they skip

**This branch is reachable only from 3.0's `false` case or a failed re-verification.** A project
whose verification call just returned `ok: true` never lands here, whatever the user answers —
writing `gsc.connected: false` over a live connection would report a working integration as "not
measured" and throw away the setup they already did.

This is a supported path, not a degraded one. Leave `gsc.connected` at `false`, do not create
`.seo-god/secrets.env`, do not touch the compose file, and continue with sections 4-6 unchanged. Every snapshot then carries
`"gsc":{"available":false,"clicks28d":0,"impressions28d":0,"top_queries":[]}` — the zeros are
inert placeholders that satisfy the schema, and `available:false` is the only thing any consumer
may read. Say once, plainly, that clicks, impressions and query data are **not measured** until GSC
is connected, and that they can come back to this phase at any time.

## 4. The tracked keyword list

Aim for **10-30 keywords**. Fewer than ten is not a trend line; more than thirty is a list nobody
reviews. If `seo-god.json` already has a non-empty `keywords` array, show it and ask whether to
keep, add or remove — do not silently re-seed.

Ask the user first: *"Which searches should someone be typing to find you? Ten to thirty of them —
the ones where ranking would actually bring you customers."* Their own list beats anything you can
infer, because they know which terms convert.

To help them, propose candidates from the crawl. Omit `auditId` here — the audit id is not resolved
until section 5.2, and omitting it means "the project's most recent audit":

```json
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_audit_pages","arguments":{"projectId":"<projectId>","limit":1000}}}
```

If that call errors with **"No audits exist for this project yet"**, there is nothing to suggest
from: work from the user's own list and let section 5.2 deal with the missing crawl.

Each row carries `url`, `title`, `description`, `statusCode` and `h1Count`. Build candidates from
the **titles and URL paths** of the money pages and the top-level sections. Note the limit of what
this data is: the crawl stores how many H1s a page has, not their text, so if you want real H1s
read them from the page source in the repository. Never present a title as an H1.

Propose the candidates as a numbered list and let the user cut, edit and add. The final list is
theirs, not yours.

Save it to OpenSEO — free, no credits, idempotent, and it uses the project's own market so do not
pass `locationCode` or `languageCode` unless the user asks for a different one:

```json
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"save_keywords","arguments":{"projectId":"<projectId>","keywords":["first keyword","second keyword"]}}}
```

Then write the same list to `seo-god.json` as `keywords` (an array of strings, read-modify-write,
preserving every other key). The snapshot's `ranks` array is built from this list, so it has to
survive a session that ends here. If the user will not name any keywords, write `"keywords": []`,
write `"ranks": []` in every snapshot, and say plainly that nothing is being tracked — do not
invent a list on their behalf.

**What rank tracking can and cannot do on the free path.** OpenSEO's rank tracker takes positions
from DataForSEO, so running a check costs credits, and its MCP surface is read-only: `get_rank_tracker`
reads configs and stored results, and there is no tool that creates a tracker or triggers a check.
On the free path, therefore, tracked keywords have **no measured position** — `position` is `null`
in every snapshot, which is the honest value, and the diff reports rank movement as "not measured".
Say this to the user in one sentence rather than letting them discover it in the readout. Users who
want real positions add the DataForSEO power-up (`references/power-ups.md`, budget-capped before
the first call) and create the tracker on the project's **Rank tracking** page; this phase picks it
up automatically the next run.

## 5. Capture today's snapshot

### 5.1 Where it goes

```
dist/seo/snapshots/<YYYY-MM-DD>.json
```

`<YYYY-MM-DD>` is today's **local** date, matching the day a scheduled run fires. Apply the
gitignore guard from `references/audit.md` section 7 — the `git check-ignore` check gated behind
"this project uses git", falling back to `seo/snapshots/<YYYY-MM-DD>.json` at the repository root
when `dist/` is ignored. (Its write-last rule does not apply here; nothing in this phase runs a
build.) Resolve the directory **once** and use the same one for the write in 5.5 and the read in
section 6, or the diff will look in the wrong place tomorrow.

Write the file with your Write tool. Never build it with shell redirection: quoting rules differ
between PowerShell and POSIX shells and a mangled snapshot is a silently corrupted history.

### 5.2 Crawl — from a completed audit, never invented

The `crawl` block has no `available` flag, so it may only ever be written from a real completed
audit. Get the latest one:

```json
{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get_audit_status","arguments":{"projectId":"<projectId>"}}}
```

`result.structuredContent.status` carries `id`, `status`, `pagesCrawled`, `pagesTotal`, `startedAt`
and `completedAt`. Then:

- `status` is `"completed"` → use its `id` as `<auditId>`. Note `completedAt`; you report it later.
  **`"completed"` is not by itself a real crawl.** Apply `references/audit.md` section 4's
  not-an-audit rule before you use it: if `pagesCrawled` is 0, or `get_audit_pages` shows every page
  with `fetchClass: "error"`, the crawler read nothing — stop the phase here exactly as the
  cannot-complete branch below says, and **write no snapshot**. A `crawl` block of
  `pages: 1, issues: []` built from an all-error audit is a fabricated clean bill of health, and
  section 6's diff would report every real issue as resolved tomorrow.
- `status` is `"running"` → poll every 10 seconds until it completes, exactly as
  `references/audit.md` section 4 does.
- `status` is `"failed"`, or the call errors with **"No audits exist for this project yet"** → there
  is no crawl to report. Run one (free, no credits) with `run_site_audit` and poll it to completion,
  following `references/audit.md` section 4 for the arguments and every failure branch. If it cannot
  complete, **stop the phase here**: report why, leave `phases.measure` at `"in_progress"`, and write
  no snapshot at all. A snapshot with `"pages":0` and `"issues":[]` because the crawl never ran is
  the zero-fill this phase forbids.

Page count — take it from `total`, never from the length of the returned array:

```json
{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"get_audit_pages","arguments":{"projectId":"<projectId>","auditId":"<auditId>","limit":1}}}
```

`crawl.pages` = `result.structuredContent.total`.

Issues — one unfiltered call, `limit` at its maximum so the rows are as complete as the API allows:

```json
{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"get_audit_issues","arguments":{"projectId":"<projectId>","auditId":"<auditId>","limit":1000}}}
```

Build one `crawl.issues` entry per issue type present in `result.structuredContent.summary` (the
summary is complete for the whole audit; the rows are not):

- `type` — OpenSEO's `issueType`, copied verbatim and unaltered (`missing-title`, `blocked-page`,
  `broken-internal-link`, …). Both snapshots use the same vocabulary, which is what makes the diff
  meaningful.
- `severity` — mapped from OpenSEO's three levels into the snapshot's three:
  `critical` → `"error"`, `warning` → `"warn"`, `info` → `"info"`. Nothing else is a valid value.
- `urls` — the URLs for that type from the rows you received, deduplicated, **sorted
  lexicographically, and capped at 50**. Sort before capping: a deterministic cap means the same
  input always yields the same 50 URLs, so tomorrow's diff cannot invent a "new" URL out of
  truncation. When a type's `summary` count exceeds the URLs you kept, say so in the readout.

### 5.3 Ranks

Start from the `keywords` list. Look for a tracker:

```json
{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"get_rank_tracker","arguments":{"projectId":"<projectId>"}}}
```

`result.structuredContent.configs` empty → no tracker. Every keyword becomes
`{"keyword":"<the keyword>","position":null,"url":""}`. That is the free path, and it is correct.

A config exists → re-call with its `id` as `trackerId`. `result.structuredContent.results.rows`
carries one row per tracked keyword with `keyword`, `desktop` and `mobile`, each
`{position, previousPosition, rankingUrl, serpFeatures}`. For each keyword in your list:

- matched row → `position` = `desktop.position`, `url` = `desktop.rankingUrl` or `""` when null.
  **Use desktop consistently** and say so in the readout; silently switching device between runs
  manufactures rank changes that never happened.
- no matched row, or `desktop.position` is `null` → `position: null`, `url: ""`.

**Never fill `position` from a GSC average position.** They are different measurements — a SERP
rank versus a mean over impressions — and mixing them into one field destroys the meaning of both.
GSC positions belong in `gsc.top_queries`, where they are labelled as GSC.

### 5.4 GSC

`gsc.connected` false in state, or section 3.6 did not return `ok: true` → write
`"gsc":{"available":false,"clicks28d":0,"impressions28d":0,"top_queries":[]}` and skip to 5.5.

Connected → two calls.

**G1, the totals.** Per-date rows, so the sums are exact — summing per-*query* rows would
under-count, because Google withholds anonymised queries and the row list is capped:

```json
{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"get_search_console_performance","arguments":{"projectId":"<projectId>","dimensions":["date"],"dateRange":"last_28_days","type":"web"}}}
```

`clicks28d` = the sum of `clicks` over `result.structuredContent.rows`; `impressions28d` = the sum
of `impressions` — order does not matter for a sum. Keep the per-date rows in memory: section 6
uses them for the week-over-week check, and that one **does** depend on order. Each row's `keys[0]`
is the date, and like G2 these rows arrive **sorted by clicks descending, not by date**, so they
must be sorted by `keys[0]` before anything splits them into weeks.

**G2, the queries:**

```json
{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"get_search_console_performance","arguments":{"projectId":"<projectId>","dimensions":["query"],"dateRange":"last_28_days","rowLimit":1000,"type":"web"}}}
```

Rows arrive sorted by clicks descending. `top_queries` = the first **200** rows, each mapped to
`{"query": keys[0], "clicks": clicks, "impressions": impressions, "position": position}` with
`position` rounded to one decimal (GSC's own precision; rounding keeps the file from churning on
noise). `ctr` is dropped — it is `clicks / impressions`, which the snapshot already has.

Set `gsc.available` to `true` only when G1 and G2 both returned `ok: true`. If either failed, write
`available:false` with the inert zeros and report the failure verbatim; a half-read GSC is not a
measured GSC.

Two honesty notes for the readout: `dateRange: "last_28_days"` ends about three days back because
Google's data lags, so this window is not "the last 28 days including today"; and when G2's
`hasMore` is `true`, `top_queries` is the top 200 of more, never the complete query set.

### 5.5 Write it

Read `dist/seo/snapshots/<today>.json` first if it already exists — a second run on the same day is
a read-modify-write, not an overwrite. Carry forward every key you do not recognise, and **preserve
`ai_visibility` whenever its `measured` is `true`**: that section belongs to
`references/ai-visibility.md`, and clobbering another phase's measurement back to defaults is the
same lie as zero-filling your own. Only when no same-day file exists, or its `ai_visibility.measured`
is `false`, do you write the defaults below.

The shape is fixed. These key names are a contract other phases read; do not rename, add or drop
any of them:

```json
{
  "date": "2026-08-01",
  "source": "seo-god",
  "site": "https://example.com",
  "crawl": {
    "pages": 0,
    "issues": [
      { "type": "missing-title", "severity": "warn", "urls": ["https://example.com/a"] }
    ]
  },
  "ranks": [
    { "keyword": "example keyword", "position": null, "url": "" }
  ],
  "gsc": {
    "available": false,
    "clicks28d": 0,
    "impressions28d": 0,
    "top_queries": [
      { "query": "example query", "clicks": 0, "impressions": 0, "position": 0 }
    ]
  },
  "ai_visibility": { "measured": false, "prompts_ok": 0, "cited": 0, "competitors": {} }
}
```

- `date` — the same `<YYYY-MM-DD>` as the filename.
- `source` — always the literal `"seo-god"`.
- `site` — `site_url` from state, unchanged.
- `ai_visibility` — defaults exactly as above unless you are preserving a measured section.

## 6. The diff

Find the newest snapshot in the same directory whose `date` is **before** today's, by filename. Do
not reach into another directory, and do not use a file you wrote earlier today.

**No previous snapshot** → say exactly that: *"First snapshot — no previous run to compare
against."* Then report today's absolute numbers and stop. Do not compute a delta against zero, and
do not describe a first capture as an improvement or a decline.

Report the three sections **in this order, always, even when a section is empty**. Regressions
come first because a fix that broke something outranks every opportunity behind it.

### 1. Regressions

**Rank drops of 3 or more positions.** Match today's `ranks` against the previous snapshot's by
`keyword`. A regression is `today.position - previous.position >= 3` with **both** positions
non-null. If either is `null`, it is not a regression and not an improvement — it is unmeasured,
and it is counted in the "not measured" line, never in the drop list. When every position on either
side is `null`, the whole line reads: *"Rank movement: not measured — no rank tracker configured."*

**New error-severity issues.** Compare `crawl.issues` entries whose `severity` is `"error"`. New
means either the `type` is absent from the previous snapshot, or its entry lists a URL the previous
entry did not. Report type, severity and the newly-appearing URLs.

One guard: if you reused an existing audit in 5.2 rather than crawling in this session, and today's
`crawl` block is identical to the previous snapshot's, the correct line is *"not re-crawled since
<previous date>"* — **not** "no new issues". Two snapshots that share one audit cannot disagree,
and reporting that as a clean bill of health is a lie the user would act on.

**GSC clicks down 20% or more week over week.** With GSC connected, take it from G1's per-date rows
— **sort them by `keys[0]` first** (5.4: they arrive clicks-desc, not date-ordered, and splitting
them unsorted compares two arbitrary sets of dates). Then sum `clicks` over the most recent 7 dates,
sum the 7 dates before those, and flag when the recent week is at least 20% below. This is exact and
needs no previous file. If G1's rows are unavailable but both snapshots have `gsc.available: true`,
fall back to comparing `clicks28d` and say which comparison you used. If either snapshot has `gsc.available: false`, the line is *"GSC: not
measured"* — never "0 clicks", and never a percentage computed against a zero placeholder.

### 2. Quick wins — positions 4 to 15

Everything ranking in positions **4-15**: on page one's lower half or the top of page two, where a
better title, a real answer near the top, or an internal link can move it into the clicks.

Source in this order: tracked-keyword positions where a rank tracker measured them; otherwise GSC
query positions from `top_queries` where `4 <= position <= 15`.

**Report only the fields the source actually has.** A `ranks[]` row is `{keyword, position, url}`
and carries **no impressions** — for tracked-keyword entries report the keyword, its position and
its ranking URL, and nothing else. Impressions belong to GSC-sourced rows only, where
`top_queries[]` really measured them. Never carry a number across from the other source, and never
print `0` for a field the snapshot does not have.

- **GSC-sourced rows**: query, position, impressions, and the ranking page (a GSC call with
  `dimensions:["query","page"]` filtered to that query). Sort by impressions descending — the
  highest-impression near-misses are the cheapest traffic in the file.
- **Rank-tracker rows**: keyword, position, ranking URL. Sort by position ascending; impressions do
  not exist here, so they cannot order anything.

Neither source available → *"Quick wins: not measured — needs Search Console or a rank tracker."*
An empty list because nothing sits in that band is a different statement, and must read differently.

### 3. New queries

Queries in today's `gsc.top_queries` that are absent from the previous snapshot's. Report query,
clicks, impressions and position, highest impressions first. These are pages Google has started
showing for something new — the earliest signal that a fix or a new page worked.

Requires `gsc.available: true` on **both** snapshots; otherwise *"New queries: not measured"*. If
today's `hasMore` was true, add that new arrivals outside the top 200 are not visible here.

## 7. Finish

Update `seo-god.json` — read, modify, write the whole object, preserving every key you do not
recognise, keeping `version: 1`:

- `gsc.connected` — `true` whenever the 3.6 verification call returned `ok: true` in this run,
  whether it ran from 3.0 on an already-connected project or at the end of the walkthrough.
  `false` only after a verification that actually failed, or when GSC was never connected. Never
  write `false` because the user answered "skip" to a question 3.0 should not have asked.
- `keywords` — the agreed list from section 4.
- `phases.measure` — `"done"`.

Write it to disk immediately, then give the user a short summary, in this order:

- Where the snapshot was written, and whether it is the first one.
- GSC: connected (with the bound property) or not measured, in those words.
- The tracked keyword list size, and whether positions are measured or not measured.
- The crawl behind this snapshot: page count, and the audit's `completedAt` — plus whether it was
  reused or run fresh in this session, so a stale crawl is visible rather than implied.
- The diff, in the section order above, with every "not measured" line kept as such.
- Any truncation you hit: issue types whose `urls` were capped at 50, and GSC's `hasMore`.

Then point at what is next: ACT — the daily loop that reads this diff and fixes the regressions
first. If GSC was skipped, add one line that connecting it later re-runs this phase with real
clicks, impressions and query data.
