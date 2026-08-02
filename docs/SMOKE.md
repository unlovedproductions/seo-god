# End-to-end smoke test — 2026-08-01

A single operator ran the skill the way a first-time user would: open `SKILL.md`, follow it
literally from a project directory, answer its questions, and let it drive real Docker and a real
crawl. Setup and audit were run attended (a human reading the files and executing them step by
step). The daily loop and the missed-run check were run as real headless `claude -p` invocations —
no human in the loop, which is the only honest way to test a property that only matters when nobody
is watching.

The deviations below are the point of this document. Where an instruction and reality disagree, the
instruction is quoted verbatim and what actually happened is recorded next to it.

> [!NOTE]
> **This is a point-in-time record, not a description of the current skill.** Every measurement,
> quotation and line number below was taken against commit `b61c42e`, and nothing was edited in
> response *at the time*. The findings were then triaged in a whole-branch review and a single fix
> wave landed on top. Each finding therefore carries its status inline — **FIXED in the final review
> wave** or **OPEN — v1.1** — and the backlog at the end lists only what is still open. Read a
> finding's marker before you read its present tense.

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

**Authorized deviations from the test plan** (operator safety and local tooling, not skill defects):

- The fixture container ran under compose project `seo-god-smoke` rather than the file's `seo-god`,
  on host port 3005, to keep it provably separate from an unrelated production OpenSEO already
  running on this machine.
- Headless runs were capped at `--max-turns 60` rather than the shipped runner's 80 (not binding —
  the longest run used 43).
- The fixture was served with `python -m http.server 8080` instead of `npx serve -l 8080`. `serve`
  defaults to `cleanUrls: true`, which 301-redirects `/about.html` → `/about`; that would have
  layered redirect noise over the seeded broken-link defect and changed what the crawler saw.
  `http.server` serves paths literally, so the two seeded defects stay the only seeded findings.
- **The daily runs invoked `claude -p` directly, not through `scripts/daily-run.ps1`.** The wrapper
  was deliberately bypassed so that stage 3 tests the *skill flow* rather than the wrapper. This
  matters for one finding: `.seo-god/last-run.json` is the wrapper's file to write
  (`act.md` §7), and the wrapper never ran — so the marker writes recorded in F3 came from the skill
  flow itself, not from `daily-run.ps1`.

## Stage results

| Stage | Verdict |
| --- | --- |
| 1. Fixture | PASS |
| 2a. SETUP, attended | PASS with deviations — completed only after a manual workaround (F4) |
| 2b. AUDIT, attended | PASS with deviations — both seeded defects found, triaged and fixed |
| 3. Daily loop, real `claude -p "/seo-god daily"` | **FAIL** — zero-question property held, the contract did not (F1, F2, F3) |
| 4. Missed-run warning, real `claude -p "/seo-god"` | PASS, verbatim |
| 5. Teardown | PASS |

## Crawl ledger

Three crawls ran, and the findings below cite different ones. Reconciled here so no number is
orphaned:

| | `auditId` | Result | Cited by |
| --- | --- | --- | --- |
| **A** | `3fceb5ef-8ced-482a-be7a-c8a6312be87a` | `status: "completed"` in 0.4 s, `pagesCrawled: 1`, `lighthouseTotal: 0`; the one page was `statusCode: 0, fetchClass: "error"` — the crawler runtime had negative-cached DNS for a hostname created seconds earlier | F8 |
| **B** | `f64c69a6-a892-4930-9712-887bc16c320a` | the real audit — `pagesCrawled: 7`, `pagesTotal: 7`, `lighthouseTotal: 12, lighthouseCompleted: 0, lighthouseFailed: 12`; **10 issue rows across 6 types**, including both seeded defects | F7, and the seeded-defect result |
| **C** | `1c7b81b9-7c37-4c6a-a67c-88326116fdfb` | post-fix re-crawl — all 10 of B's rows cleared, one new `info` row (`canonicalized-page`, the expected consequence of the canonical tag added to consolidate B's duplicates) | F9, F10 |

Two clarifications on B's counts, since they look inconsistent at a glance. Seven pages from a
five-page fixture is correct: `/`, `/index.html`, `/about.html`, `/menu.html`, `/locations.html`,
`/contact.html` and the deliberately-absent `/missing.html`. And 12 Lighthouse runs over 7 pages is
what the API reported; the tool describes the pass as "up to 10 representative pages" and the
multiplier is not documented, so the figure is recorded as observed and not explained.

## Stage 4 evidence — the missed-run warning

Evidence source: **the original stage-4 run**, not a re-run. Its artifacts were all still on disk
when this section was written — the planted state file, the planted marker, and the captured
`--output-format json` result — so everything below is quoted rather than reconstructed.

Planted state, in the fixture's `seo-god.json`:

```json
"phases": { "setup": "done", "audit": "done", "measure": "pending", "ai_visibility": "pending", "schedule": "pending" },
"schedule": { "mode": "os", "time_local": "05:00", "marker": ".seo-god/last-run.json" },
```

Planted marker, at the default `.seo-god/last-run.json`, with `ts` backdated three days (the run
fired at 2026-08-02T02:48Z, so the marker was ~72 h old — well past `SKILL.md` §2's 48 h window)
while deliberately leaving `ok: true`, so that the age branch is what fires and not the `ok: false`
branch:

```json
{"ts":"2026-07-30T02:45:00Z","ok":true,"notes":"Degraded run 2 of 2026-08-01 (act.md unreadable, network/OpenSEO unapproved, no GSC). Regression re-check of all 5 pages + robots + sitemap: clean, run-1 fixes verified intact. No edits made. Readout: dist/seo/daily-2026-08-01-run2.md"}
```

The command, from the fixture directory:

```
claude -p "/seo-god" --permission-mode acceptEdits --max-turns 15 --output-format json
```

Result: exit 0, `is_error: false`, 8 turns. The first two lines of the output, verbatim:

```
A scheduled run appears to have been missed (last run: 2026-07-30T02:45:00Z).

The marker at `.seo-god/last-run.json` reports `ok: true`, but it's ~72 hours old — past the
48-hour freshness window.
```

`SKILL.md` §2 specifies that string as a template:

> Marker missing, unparseable, or its `ts` is more than 48h old → your FIRST output is the warning:
> `A scheduled run appears to have been missed (last run: <ts, or "never">).`

The first line matches the template exactly, with the planted `ts` substituted. The run then did the
other three things §2 asks for: it continued rather than stopping ("The warning prefixes the turn;
it never ends it"), it rendered the §6 phase menu in the documented layout, and it carried the two
recovery options — run the daily loop now, re-check the schedule — into that menu as the recommended
actions instead of asking a blocking question. It also spotted, unprompted, that `schedule.mode` was
`"os"` while `phases.schedule` was still `"pending"`, which is an inconsistency this test created.

Not covered by this stage: the `"ok": false` branch, which §2 says should produce the same warning
"plus quote its `notes` verbatim". The marker was planted with `ok: true` on purpose to isolate the
age trigger, so that branch remains untested.

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
  `{"3001/tcp":[{"HostIp":"127.0.0.1","HostPort":"3005"}]}`). The instruction is right, and so is
  its trigger; the exposure is the retry and the missing ownership check (F5).
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
- **`SKILL.md` §2's missed-run check** — stage 4, verbatim, first line, before anything else; full
  evidence chain in the section above.
- **`references/act.md` §7's "Write **no** phase state"** — `seo-god.json` was byte-identical after
  both unattended runs.
- **The data-honesty rules survived everything.** Both degraded unattended runs named every missing
  input in the words the skill asks for, and both refused to write a new page without demand data.
  That behaviour comes from `SKILL.md`, which is the one file an unattended run can always read.

## Deviations found

### F1 — CRITICAL. An unattended run cannot read the phase files at all

**Status: FIXED in 6cdb52c (final review wave).**

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

**Status: FIXED in 6cdb52c (final review wave).**

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

Sharpest detail: this machine's own `~/.claude/settings.json` carries a **more permissive default
mode** than the runner asks for, and the shipped `--permission-mode acceptEdits` flag **overrode
that default** and created the wall. The same user running `/seo-god act` interactively sees
everything work; their scheduled run cannot.

F1 and F2 are independent walls. Fixing only F1 would still leave the loop unable to crawl.

### F3 — HIGH. What the daily runs actually produced

**Status: OPEN — v1.1.**

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

**Status: FIXED in 6cdb52c (final review wave).**

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

### F5 — HIGH. Nothing checks that the thing answering the port is the container the skill started

**Status: FIXED in 6cdb52c (final review wave).**

**The severity lives in an unconditional gap, reachable by following the file exactly as written.**
Setup never verifies ownership of the port it polls. Relocate to 3005 because §4 told you to, then
copy §5's readiness poll and §6's registration calls as they are printed — all of which still say
`3001` (F6) — and on this machine you get **200 from a completely different OpenSEO install**,
verified live. §5's documented ready-response shape matches that stranger's response exactly, so the
readiness check passes and §6 registers the user's site inside someone else's instance. No deviation
from the file is required to reach that; the two findings compound, and this is the leg that carries
HIGH.

The one available discriminator was visible but unnamed: the foreign install answered
`"dataforseo":{"status":"ok","detail":"Set"}`, whereas §5 documents the free path as `"warn"` /
"Not set" — the file presents that as a benign expectation, never as an identity check.

**The trigger itself is right**, and that is worth stating plainly. `references/setup.md` §4:

> If `up` fails with `Bind for 127.0.0.1:3001 failed: port is already allocated`, another process
> owns that port: return to step 3, choose a different host port, rewrite the file, retry.

Docker 29.6.2 printed that string character for character, and the first conflicted `up -d`
**exits 1**. Both signals an agent could key on — the message and the exit code — are correct on the
first attempt.

> **Correction to an earlier draft of this document.** The first run of this test measured the exit
> code through a pipe (`docker compose … up -d 2>&1 | tail -20; echo $?`), which reports *`tail`'s*
> exit code, not Compose's, and recorded "exited 0". That was a measurement error, not a Compose
> behaviour, and the claim is retracted.

**A secondary mechanism reaches the same place, but only off-script.** Re-measured cleanly in a
separate throwaway compose project:

```
FIRST_UP_EXIT=1
  Error response from daemon: failed to set up container networking: driver failed programming
  external connectivity on endpoint … Bind for 127.0.0.1:3001 failed: port is already allocated

SECOND_UP_EXIT=0
  Container seo-god-smoke-exitcheck-probe-1 Starting
  Container seo-god-smoke-exitcheck-probe-1 Started
  {"3001/tcp":[]} state=running
```

A second identical `up -d` — issued *before* rewriting the port — reports `Started`, **exits 0**,
and leaves the container running with an empty port binding: running, and unreachable from the host.
That then feeds the same 3001 poll described above. This one requires deviating from §4's
rewrite-then-retry order, so it is a lesser leg than the ownership gap; it is recorded because
retrying a transient-looking Docker failure before editing anything is an ordinary reflex, and §4
gives the order — rewrite, then retry — but never warns that a bare retry succeeds misleadingly.

One provenance note on that evidence: the two exit codes and the transcript above come from an
`alpine` probe container in the throwaway project, **not** from the `open-seo` image — it was chosen
precisely because the behaviour under test is Compose's and the daemon's, not the application's. The
empty binding itself was independently observed on the real image during the live smoke —
`docker inspect seo-god-smoke-open-seo-1` returned `{"3001/tcp":[]}` with `State=running` — so that
half of the mechanism is confirmed on both. Only the exit codes are alpine-only, and only the exit
code was ever mis-measured.

### F6 — MEDIUM. After relocating the port, every literal command in the file still says 3001

**Status: FIXED in 6cdb52c (final review wave).**

§3 carries the relocation in one sentence — "use the new port in every command below and in
`openseo.url`" — while §5's poll block, §6's three curl blocks, §6's `/p/<id>` confirmation URL and
§6's dashboard-fallback URL all still print `3001`. On exactly the machine where relocation is
needed, something else owns 3001, so copying any of those blocks verbatim targets the wrong install.
This compounds F5 rather than being independent of it.

Related, in `SKILL.md`: the documented default state shape seeds
`"openseo": { "url": "http://localhost:3001", … }`, while `setup.md` §5 forbids that host outright —
"Use `127.0.0.1`, not `localhost`" — with a worked example of `localhost:3001` returning another
application's HTML. The seed value contradicts the rule that exists to prevent it.

### F7 — MEDIUM. Nothing tells you to check whether Lighthouse ran

**Status: FIXED in 6cdb52c (final review wave).**

On crawl B, `get_audit_status` returned `lighthouseTotal: 12, lighthouseCompleted: 0,
lighthouseFailed: 12`. All twelve Lighthouse runs failed, so triage class 5 had zero data.

`audit.md` §4 lists "the Lighthouse counters" as fields on the status object and says nothing more.
§6 class 5 says "plus the Lighthouse performance findings from the crawl". §8's summary shape has no
line for performance-not-assessed. The file states the equivalent rule for blocked pages —

> **Pages the crawler could not read are not clean pages.**

— and never extends it to a Lighthouse pass that produced nothing. Without that line, "no
performance issues found" and "performance was never measured" are indistinguishable in the summary.

### F8 — MEDIUM. A crawl that fetched nothing still reports `status: "completed"`

**Status: FIXED in 6cdb52c (final review wave).**

Crawl A — the first against a reachable public URL — returned an `auditId`, and `get_audit_status`
reported:

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

**Status: OPEN — v1.1.**

`audit.md` §2 handles the no-toolchain case honestly:

> Only if there is truly nothing, store `build_cmd: "none"`. Then there is no gate, so you do not get
> to say "fixed": every edit is reported as **edited, unverified** […]

That is the right call and it was followed. But the projects that produce `"none"` are hand-written
static sites — precisely the ones where OpenSEO can re-crawl in about ten seconds and prove the fix.
Re-crawling by hand after the fixes — crawl C, about ten seconds — cleared all ten of crawl B's
rows, leaving one expected new `info` row (`canonicalized-page`, a direct result of the canonical
tag added to consolidate B's duplicates). Neither `audit.md` §2 nor `act.md`'s degrade row
(`build_cmd` is `"none"` → edits, never verified) mentions the re-crawl as a substitute gate.

### F10 — LOW. Fixing a broken link makes the 404 disappear from the report without being fixed

**Status: OPEN — v1.1.**

After the only internal link to `/missing.html` was removed, the next crawl never discovered that
URL, so the `broken-page` issue vanished from `summary` — while the 404 is still live and still on
the punch list awaiting a host-level 301. `measure.md` §6's regression diff, which `act.md` §1.4
consumes, would read that as an issue resolved. Nothing in `audit.md` §7 or `act.md` warns that a
punch-list item can silently stop appearing in later crawls.

### F11 — LOW. "One issue type per batch" has no answer when one edit clears two types

**Status: OPEN — v1.1.**

`audit.md` §6, fix loop step 1:

> **Select.** Take ONE issue type within the current class […]

A single `<link rel="canonical">` in `index.html` cleared both `duplicate-content` (2 rows) and
`duplicate-meta-description` (2 rows). Following the letter means opening a second batch that
snapshots and "edits" a file for a change already made.

### F12 — LOW. Local vs UTC date is specified in one file and not the other

**Status: FIXED in 6cdb52c (final review wave).**

`act.md` §1.2 is explicit: "`<YYYY-MM-DD>` is today's **local** date". `audit.md` §7's punch-list
path `dist/seo/audit-punchlist-<YYYY-MM-DD>.md` and §6's run stamp `YYYY-MM-DD-HHMM` say neither.
This machine is UTC-7, so for seven hours a day a punch list stamped UTC and a readout stamped local
carry different dates for the same run, and `.seo-god/backup/<run-stamp>/` — whose whole purpose is
that a later run must not collide with this one — inherits the ambiguity.

## What this report changed, and what is still open

**Closed by the final review wave** — F1, F2, F4, F5, F6, F7, F8 and F12. In summary: the runners
now take a `--skill-dir` / `-SkillDir` argument that both installers write into the scheduler entry
and that becomes `--add-dir`, so the unattended run can read its phase files, and the dry run proves
`references/act.md` is readable rather than only that the CLI is on PATH (F1); `SKILL.md` declares
an `allowed-tools` grant for `curl` and read-only `git`, mirrored into `--allowedTools` in both
runners, with the permission-override stated out loud and a consented user-scope allow entry for the
build gate (F2); `setup.md` §2 validates public reachability at the question and `audit.md` /
`measure.md` §1 break the loop instead of routing back into a setup step that refuses the same host,
with `CRAWL_TARGET_BLOCKED` decoded (F4); §5 derives the host binding from
`docker compose -p seo-god … port open-seo 3001` and treats an empty binding as a hard failure, which
is also what makes the answering instance provably ours (F5); every remaining literal `3001` in §5
and §6 is parameterised and `SKILL.md`'s seed is `127.0.0.1` (F6); and `lighthouseFailed > 0`,
zero-page and all-`fetchClass: "error"` crawls are now reported as missing data — with no snapshot
written — in `audit.md`, `measure.md` and `act.md`'s degrade table (F7, F8), with the punch-list and
run-stamp dates pinned to local (F12).

**Still open — the v1.1 backlog.** Ordered by what would break a real user first. Each needs a
design decision rather than a clause, which is why none of them landed in the wave:

1. **Offer the re-crawl as the gate when `build_cmd` is `"none"`.** A free verification exists and
   the file gives up on it. (F9)
2. **Warn that punch-list items can vanish from later crawls** without being fixed, and say how the
   diff should treat that — it needs a diff-semantics decision. (F10)
3. **Say what to do when one edit clears two issue types.** Cosmetic inefficiency today; no wrong
   output. (F11)
4. **The degraded-run behaviour recorded in F3** — what the daily runs actually produced under the
   F1/F2 walls — should be re-measured end to end now those walls are gone. This report's stage 3
   verdict predates the fix. (F3)

## Teardown verification

The fixture instance ran under its own compose project and volume throughout, and was removed with
`docker compose -p seo-god-smoke -f .seo-god/docker-compose.yml down -v`. After teardown: zero
containers, zero volumes and zero networks matching `seo-god-smoke`. The fixture web server and the
cloudflared tunnel were both stopped (`localhost:8080` → connection refused; the tunnel hostname →
502 with no origin).

An unrelated production OpenSEO was running on this machine on `127.0.0.1:3001` for the whole test.
It was never stopped, restarted or modified:

| | before | after | after re-measurement |
| --- | --- | --- | --- |
| checked at | 2026-08-02T02:09:48Z | 2026-08-02T02:49:59Z | 2026-08-02T03:06:04Z |
| `GET /api/health` | 200 | 200 | 200 |
| container id | `b67816ab655c…` | `b67816ab655c…` | — |
| `State.StartedAt` | 2026-08-01T14:07:38.796409818Z | 2026-08-01T14:07:38.796409818Z | 2026-08-01T14:07:38.796409818Z |
| `RestartCount` | 0 | 0 | 0 |
| data volume | `open-seo_open_seo_data` | `open-seo_open_seo_data` | — |

Uptime unbroken, restart count unchanged, volume intact.

The third column covers a follow-up: the F5 exit-code re-measurement needed a second throwaway
compose project (`seo-god-smoke-exitcheck`, a neutral `alpine` container whose only job was to fail
to bind 3001). It never bound the port, was removed with `down -v`, and left zero containers,
volumes and networks behind. Production was re-checked afterwards — same `StartedAt`, restart count
still 0, health still 200.

The skill repository was not edited during the test: `git status --short` stayed empty and `HEAD`
stayed at `b61c42e` until this file was added. Three headless transcripts were audited afterwards
for path escapes — no `Write` or `Edit` outside the fixture directory, and no `docker`, no
destructive shell, and no request to port 3001 was attempted by any of them. The two reads that did
target a path outside the fixture (`references/act.md`) were blocked by the harness, which is F1.
