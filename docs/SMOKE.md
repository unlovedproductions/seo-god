# End-to-end smoke test — 2026-08-01

A single operator ran the skill the way a first-time user would: open `SKILL.md`, follow it
literally from a project directory, answer its questions, and let it drive real Docker and a real
crawl. Setup and audit were run attended (a human reading the files and executing them step by
step). The daily loop and the missed-run check were run as real headless `claude -p` invocations —
no human in the loop, which is the only honest way to test a property that only matters when nobody
is watching.

The deviations below are the point of this document. Where an instruction and reality disagree, the
instruction is quoted verbatim and what actually happened is recorded next to it. Nothing in the
skill was edited in response; every item lands in the v1.1 backlog at the end.

## Environment

| | |
| --- | --- |
| OS | Windows 11 Pro 10.0.26200 |
| Shell | Git Bash (the file's "macOS, Linux, Git Bash" branch) |
| Docker | 29.6.2, build dfc4efb |
| Compose | v5.3.1 |
| git | 2.49.0.windows.1 |
| node / python | v22.14.0 / 3.11.9 |
| Claude Code | 2.1.220 |
| Model | claude-opus-5 |
| OpenSEO | 0.1.3, `ghcr.io/every-app/open-seo:latest` |
| Skill under test | commit `b61c42e`, unmodified throughout |

**Fixture** — five interlinked hand-written HTML pages (a small coffee roastery), `git init`, no
`package.json`, served by `python -m http.server 8080`. Exactly two defects were seeded:
`index.html` with no `<title>`, and `about.html` carrying one broken internal link to
`/missing.html`. No paid keys, no Search Console, no power-ups at any point.

**Authorized deviations from the test plan** (operator safety, not skill defects): the fixture
container ran under compose project `seo-god-smoke` rather than the file's `seo-god`, on host port
3005, to keep it provably separate from an unrelated production OpenSEO already running on this
machine; headless runs were capped at `--max-turns 60` rather than the shipped runner's 80 (not
binding — the longest run used 43).

## Stage results

| Stage | Verdict |
| --- | --- |
| 1. Fixture | PASS |
| 2a. SETUP, attended | PASS with deviations — completed only after a manual workaround (F4) |
| 2b. AUDIT, attended | PASS with deviations — both seeded defects found, triaged and fixed |
| 3. Daily loop, real `claude -p "/seo-god daily"` | **FAIL** — zero-question property held, the contract did not (F1, F2, F3) |
| 4. Missed-run warning, real `claude -p "/seo-god"` | PASS, verbatim |
| 5. Teardown | PASS |

## What worked exactly as written

Worth recording, because the failures below are easier to fix than they would be if the whole file
were wrong:

- **`references/setup.md` §1, §5, §8.** Prerequisite checks, the health-JSON description (`status`,
  `version`, `authMode` and a `checks` map over `auth`/`dataforseo`/`gsc`/`ai`/`database`), and the
  free-path expectation that `checks.dataforseo.status` is `"warn"` ("Not set") all matched byte for
  byte. The Docker-cron warning box quotes a startup log line verbatim — `[info] Scheduled checks:
  Rank-tracking schedules do not run in Docker mode — trigger checks from the Rank Tracking page.` —
  and it appeared at log line 8, exactly as quoted.
- **The port-relocation procedure.** Rewriting only the host side of the port mapping and re-running
  `up -d` recreated the container cleanly (`Recreate` → `Recreated` → `Started`, bindings
  `{"3001/tcp":[{"HostIp":"127.0.0.1","HostPort":"3005"}]}`). The instruction is right; only its
  trigger is unreliable (F5).
- **`references/audit.md` §3's tool table.** All five named tools exist. Every documented argument,
  default and cap matched the live `inputSchema`: issues `limit` default 200 / max 1000, pages
  `limit` default 100 / max 1000, `maxPages` default 50 with range 10-10000, `runLighthouse` default
  `true`, `get_audit_pages.total`, the `summary` vs `issues` shapes, `severity` vocabulary, and an
  `issueType` enum whose 27 values are fully covered by the file's five triage classes. `howToFix`
  came back populated and genuinely actionable on every row.
- **`references/audit.md` §7's gitignore guard.** `git check-ignore -q dist/seo` exited 1, so
  `dist/seo/` was used — exactly the documented branch, including the note that 128 means "no repo"
  rather than "ignored".
- **Both seeded defects were found**, as `critical`, on the first good crawl:
  `missing-title` on `/` and `/index.html`; `broken-internal-link` on `/about.html` with
  `details: {"targetUrl":".../missing.html","targetStatus":404}`.
- **`SKILL.md` §2's missed-run check** — stage 4, verbatim, first line, before anything else.
- **`references/act.md` §7's "Write **no** phase state"** — `seo-god.json` was byte-identical after
  both unattended runs.
- **The data-honesty rules survived everything.** Both degraded unattended runs named every missing
  input in the words the skill asks for, and both refused to write a new page without demand data.
  That behaviour comes from `SKILL.md`, which is the one file an unattended run can always read.

## Deviations found

### F1 — CRITICAL. An unattended run cannot read the phase files at all

`SKILL.md`:

> Phase instructions live in `references/`. Load one at a time; never preload them all.

> **Argument `daily`** — the scheduled runner invokes `claude -p "/seo-god daily"`. Read
> `references/act.md`, run the daily loop, stop here.

`scripts/daily-run.ps1:122` ships that invocation:

```
& claude -p '/seo-god daily' --permission-mode acceptEdits --max-turns 80
```

What actually happened, verbatim from the run transcript:

```
Claude requested permissions to read from <home>\.claude\skills\seo-god\references\act.md,
but you haven't granted it yet.
```

```
cat in '<home>/.claude/skills/seo-god/references/act.md' was blocked. For security, Claude
Code may only concatenate files from the allowed working directories for this session: '<project dir>'
```

The working directory of a scheduled run is the user's project. `~/.claude/skills/` is not in it, so
reading a phase file needs a permission grant, and an unattended run has nobody to grant it. Both
daily runs therefore executed with `SKILL.md` only — the orchestrator's one-paragraph summary of the
loop — and never saw `act.md`. The retry with `cat` was blocked too, so this is not a Read-tool
quirk.

Everything unique to `act.md` was silently lost: its output paths, its 15-line readout cap, its
same-day append rule, its "do not write the marker" rule, and its degrade table. F3 is the damage
list.

### F2 — CRITICAL. An unattended run cannot make any network or git call either

`references/act.md` §1.3:

> **Missing, and OpenSEO answers** → capture it now. Ask the container first: a single request to
> `<openseo.url>/api/health`, expecting 200.

Verbatim from the transcript:

```
This Bash command contains multiple operations. The following parts require approval:
curl -sS -m 5 -o /dev/null -w "openseo_root:%{http_code}\n" http://127.0.0.1:3005/,
curl -sS -m 8 -o /dev/null -w "site_root:%{http_code}\n" https://<fixture>/
```

```
This Bash command contains multiple operations. The following parts require approval:
git -C "<project>" status --porcelain, git -C "<project>" diff --stat
```

`--permission-mode acceptEdits` auto-approves file edits and nothing else. Every `curl` and every
`git` call the loop needs was denied non-interactively. So the daily loop can never reach OpenSEO,
never capture a snapshot, and never read `git status` — which is also the input to the degrade
table's "a file to edit has uncommitted changes" row.

Sharpest detail: this machine's own `~/.claude/settings.json` sets `defaultMode:
bypassPermissions`. The shipped `--permission-mode acceptEdits` flag **overrode the user's more
permissive default** and created the wall. The same user running `/seo-god act` interactively sees
everything work; their scheduled run cannot.

F1 and F2 are independent walls. Fixing only F1 would still leave the loop unable to crawl.

### F3 — HIGH. What the daily runs actually produced

Direct consequences of F1. Recorded separately because each is independently checkable.

| `references/act.md` says | The real run did |
| --- | --- |
| `dist/seo/snapshots/<YYYY-MM-DD>.json` (§1.2) | no `dist/seo/snapshots/` directory was created at all — **no snapshot exists** |
| `dist/seo/readouts/<YYYY-MM-DD>.md` (§1.2, §6) | `dist/seo/daily-2026-08-01.md`, then `dist/seo/daily-2026-08-01-run2.md` — no `readouts/` directory |
| "**At most 15 lines including the heading.**" (§6) | 62 lines |
| "Read the file first if it exists and append — a second run on the same day adds a section, it does not overwrite the first." (§6) | run 2 wrote a new `-run2.md` file instead. No data was lost, but the contract broke |
| "The run marker `.seo-god/last-run.json` belongs to the daily runner in `references/schedule.md`; this file does not write it." (§7) | both runs wrote `.seo-god/last-run.json` themselves |
| degrade table: "a file to edit has uncommitted changes → skips that item" | run 1 edited `about.html`, `index.html` and `contact.html`, all three of which carried uncommitted changes from the audit |
| `references/schedule.md` §2.5: "The first real proof is tomorrow's readout in `dist/seo/readouts/`" | that directory will never exist under the shipped invocation |

The zero-question property itself **passed**: three headless runs, `is_error: false`, exit 0, 43 /
27 / 8 turns, none stalled on a question. The runs were also honest about their own degradation —
they just were not the runs `act.md` specifies.

### F4 — CRITICAL for anyone whose site is not already public. OpenSEO refuses non-public targets, and neither phase file says so

`references/setup.md` §2 is the only gate on the URL:

> Require a scheme and a host (`https://example.com`). Reject examples and placeholders.

`http://localhost:3000` passes that rule. It then fails twice:

**Registration.** `create_project` returned, verbatim: `Enter a valid domain, like acme.com.` with
`isError: true`. Rejected: `localhost`, `http://localhost:8080`, `host.docker.internal`,
`http://host.docker.internal`, `http://host.docker.internal:8080`, `harborkettle.test`. Accepted:
`harborkettle.coffee`, `host.docker.internal.com`, `<sub>.trycloudflare.com`. The validator wants a
public suffix; `.test` and `.internal` are not enough. §6's fallback — "fall back to the dashboard:
ask the user to open `http://127.0.0.1:3001/projects` and add the site there" — hits the same
server-side validator, so there is no working path for a local site anywhere in the file.

**Crawling.** `run_site_audit` on `http://host.docker.internal:8080` returned the bare token
`CRAWL_TARGET_BLOCKED`. The cause is OpenSEO's SSRF policy in
`src/server/lib/audit/url-policy.ts`: it blocks `localhost`, the suffixes `.localhost`, `.local`,
`.localdomain`, `.internal`, `.home.arpa`, every private and loopback IP literal, and any hostname
that DNS-resolves to a private address. There is no environment override.

`references/audit.md` §4 handles the shape of this correctly —

> **If the reply has no `auditId`**, the audit did not start. […] report it verbatim, leave
> `phases.audit` at `"in_progress"`, and stop.

— and a fresh Claude following it stops there, correctly and uselessly. Nothing in the skill decodes
`CRAWL_TARGET_BLOCKED` or warns, in setup, that the site must resolve publicly to a public IP.

**Manual intervention required to finish this smoke:** a `cloudflared` quick tunnel was raised to
give the fixture a public `https://…trycloudflare.com` URL. With that, registration and crawling
both worked immediately, and `list_projects` stored the full host — so `audit.md` §1's "match the
host of `site_url` against each project's `domain`" resolution works fine for public sites.

For the local case it does not, and it fails into a loop: the project domain can never equal the
`site_url` host, so §1's "No match means setup did not finish — go back to `references/setup.md`"
sends the agent back to a setup step that will refuse the same domain again.

### F5 — HIGH. The port-conflict branch is keyed on a failure that exits 0, and its failure mode is talking to a stranger's container

`references/setup.md` §4:

> If `up` fails with `Bind for 127.0.0.1:3001 failed: port is already allocated`, another process
> owns that port: return to step 3, choose a different host port, rewrite the file, retry.

The error string is exactly right — Docker 29.6.2 printed it character for character. Everything
around it is not:

1. `docker compose up -d` **exited 0** while printing that error. An agent that checks exit status —
   the natural habit, and the one this skill's honesty rules encourage — concludes the boot
   succeeded.
2. A second identical `up -d` printed `Container seo-god-smoke-open-seo-1 Started`, exited 0, and
   left the container **running with an empty port binding**: `docker inspect` reported
   `{"3001/tcp":[]}`. Running, healthy, and unreachable from the host.
3. §5 then polls `http://127.0.0.1:3001/api/health` — and on this machine that returned **200 from a
   completely different OpenSEO install**, verified while the skill's own container had no host
   binding at all. §5's documented ready-response shape matches that stranger's response, so the
   check passes and §6 proceeds to register the user's site inside someone else's instance.

Nothing in `setup.md` ever verifies that the process answering the chosen port is the container it
just started. The one available discriminator was visible but unnamed: the foreign install answered
`"dataforseo":{"status":"ok","detail":"Set"}`, whereas §5 documents the free path as `"warn"` /
"Not set" — the file presents that as a benign expectation, never as an identity check.

### F6 — MEDIUM. After relocating the port, every literal command in the file still says 3001

§3 carries the relocation in one sentence — "use the new port in every command below and in
`openseo.url`" — while §5's poll block, §6's three curl blocks, §6's dashboard-fallback URL and §8's
three restart/stop commands all still print `3001`. On exactly the machine where relocation is
needed, something else owns 3001, so copying any of those blocks verbatim targets the wrong install.
This compounds F5 rather than being independent of it.

Related, in `SKILL.md`: the documented default state shape seeds
`"openseo": { "url": "http://localhost:3001", … }`, while `setup.md` §5 forbids that host outright —
"Use `127.0.0.1`, not `localhost`" — with a worked example of `localhost:3001` returning another
application's HTML. The seed value contradicts the rule that exists to prevent it.

### F7 — MEDIUM. Nothing tells you to check whether Lighthouse ran

`get_audit_status` returned `lighthouseTotal: 12, lighthouseCompleted: 0, lighthouseFailed: 12`. All
twelve Lighthouse runs failed, so triage class 5 had zero data.

`audit.md` §4 lists "the Lighthouse counters" as fields on the status object and says nothing more.
§6 class 5 says "plus the Lighthouse performance findings from the crawl". §8's summary shape has no
line for performance-not-assessed. The file states the equivalent rule for blocked pages —

> **Pages the crawler could not read are not clean pages.**

— and never extends it to a Lighthouse pass that produced nothing. Without that line, "no
performance issues found" and "performance was never measured" are indistinguishable in the summary.

### F8 — MEDIUM. A crawl that fetched nothing still reports `status: "completed"`

The first good-URL crawl returned an `auditId`, and `get_audit_status` reported:

```
"status":"completed","pagesCrawled":1,"pagesTotal":1,"lighthouseTotal":0
```

in 0.4 seconds. `get_audit_pages` showed why: the one page was `statusCode: 0`, `fetchClass:
"error"`, `responseTimeMs: 3` — the crawler's runtime had negative-cached DNS for a hostname created
seconds earlier. Container logs carried `Failed to crawl …: Error: internal error` and `DNS lookup
failed`.

`audit.md` §4 gives three branches for `status`: `"running"`, `"completed"`, `"failed"`. This was
`completed`. Following the file, §5 reads an empty issue list and §8 reports a site with no
problems. The blocked-page guard in §5 covers `fetchClass: "blocked"` only; there is no rule that a
completed crawl whose pages are all `fetchClass: "error"` is not an audit. Re-running once DNS was
warm produced 7 pages and the full issue set.

### F9 — MEDIUM. `build_cmd: "none"` gives up on verification when a free one is available

`audit.md` §2 handles the no-toolchain case honestly:

> Only if there is truly nothing, store `build_cmd: "none"`. Then there is no gate, so you do not get
> to say "fixed": every edit is reported as **edited, unverified** […]

That is the right call and it was followed. But the projects that produce `"none"` are hand-written
static sites — precisely the ones where OpenSEO can re-crawl in about ten seconds and prove the fix.
Re-crawling by hand after the fixes cleared all ten issues, leaving one expected new `info` row
(`canonicalized-page`, a direct result of the canonical tag added to consolidate the duplicates).
Neither `audit.md` §2 nor `act.md`'s degrade row (`build_cmd` is `"none"` → edits, never verified)
mentions the re-crawl as a substitute gate.

### F10 — LOW. Fixing a broken link makes the 404 disappear from the report without being fixed

After the only internal link to `/missing.html` was removed, the next crawl never discovered that
URL, so the `broken-page` issue vanished from `summary` — while the 404 is still live and still on
the punch list awaiting a host-level 301. `measure.md` §6's regression diff, which `act.md` §1.4
consumes, would read that as an issue resolved. Nothing in `audit.md` §7 or `act.md` warns that a
punch-list item can silently stop appearing in later crawls.

### F11 — LOW. "One issue type per batch" has no answer when one edit clears two types

`audit.md` §6, fix loop step 1:

> **Select.** Take ONE issue type within the current class […]

A single `<link rel="canonical">` in `index.html` cleared both `duplicate-content` (2 rows) and
`duplicate-meta-description` (2 rows). Following the letter means opening a second batch that
snapshots and "edits" a file for a change already made.

### F12 — LOW. Local vs UTC date is specified in one file and not the other

`act.md` §1.2 is explicit: "`<YYYY-MM-DD>` is today's **local** date". `audit.md` §7's punch-list
path `dist/seo/audit-punchlist-<YYYY-MM-DD>.md` and §6's run stamp `YYYY-MM-DD-HHMM` say neither.
This machine is UTC-7, so for seven hours a day a punch list stamped UTC and a readout stamped local
carry different dates for the same run, and `.seo-god/backup/<run-stamp>/` — whose whole purpose is
that a later run must not collide with this one — inherits the ambiguity.

## v1.1 backlog

Ordered by what would break a real user first.

1. **Make the unattended path able to read its own phase files.** Ship the scheduled invocation with
   the skill directory readable (an `--add-dir`, a settings entry created by `schedule.md`, or
   inlining the daily loop into `SKILL.md`), and have `schedule.md`'s dry run actually prove a phase
   file is reachable rather than only that the CLI is on PATH. (F1)
2. **Give the scheduled run the permissions its own instructions require**, or state plainly in
   `schedule.md` that a daily run under `acceptEdits` cannot reach OpenSEO and will always degrade.
   Note explicitly that the flag overrides a more permissive user default. (F2)
3. **`setup.md` §2 must state the target has to resolve publicly to a public IP**, name
   `CRAWL_TARGET_BLOCKED` and the `Enter a valid domain, like acme.com.` rejection, and offer the
   tunnel workaround for local sites — or refuse local URLs at the question instead of three steps
   later. Fix `audit.md` §1's resolution rule so it cannot loop back into a setup step that will
   refuse the same domain. (F4)
4. **Do not trust `docker compose up -d`'s exit code**, and add an ownership check after the first
   200: confirm the responder is the container this project just started (compare
   `docker compose -p … ps` port bindings against the polled port) before registering anything.
   (F5)
5. **Parameterise the port** through §5, §6 and §8 instead of relocating in prose, and change
   `SKILL.md`'s default `openseo.url` seed off `localhost`. (F6)
6. **Treat `lighthouseFailed > 0` and `fetchClass: "error"` as missing data**, with the same words
   the file already uses for blocked pages, and give §8's summary a not-assessed line. (F7, F8)
7. **Offer the re-crawl as the gate when `build_cmd` is `"none"`.** (F9)
8. **Warn that punch-list items can vanish from later crawls** without being fixed, and say how the
   diff should treat that. (F10)
9. **Say what to do when one edit clears two issue types**, and pin local-vs-UTC dates in `audit.md`
   the way `act.md` already does. (F11, F12)

## Teardown verification

The fixture instance ran under its own compose project and volume throughout, and was removed with
`docker compose -p seo-god-smoke -f .seo-god/docker-compose.yml down -v`. After teardown: zero
containers, zero volumes and zero networks matching `seo-god-smoke`. The fixture web server and the
cloudflared tunnel were both stopped (`localhost:8080` → connection refused; the tunnel hostname →
502 with no origin).

An unrelated production OpenSEO was running on this machine on `127.0.0.1:3001` for the whole test.
It was never stopped, restarted or modified:

| | before | after |
| --- | --- | --- |
| checked at | 2026-08-02T02:09:48Z | 2026-08-02T02:49:59Z |
| `GET /api/health` | 200 | 200 |
| container id | `b67816ab655c…` | `b67816ab655c…` |
| `State.StartedAt` | 2026-08-01T14:07:38.796409818Z | 2026-08-01T14:07:38.796409818Z |
| `RestartCount` | 0 | 0 |
| data volume | `open-seo_open_seo_data` | `open-seo_open_seo_data` |

Uptime unbroken, restart count unchanged, volume intact.

The skill repository was not edited during the test: `git status --short` stayed empty and `HEAD`
stayed at `b61c42e` until this file was added. Three headless transcripts were audited afterwards
for path escapes — no `Write` or `Edit` outside the fixture directory, and no `docker`, no
destructive shell, and no request to port 3001 was attempted by any of them. The two reads that did
target a path outside the fixture (`references/act.md`) were blocked by the harness, which is F1.
