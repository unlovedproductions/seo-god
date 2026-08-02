# Power-ups — DataForSEO, LLM keys, Telegram digest

Three optional add-ons: real keyword and backlink data, direct model probing for AI visibility, and
a daily digest on the user's phone. Each is independent, each is offered **only when the user would
benefit from it**, and **the free path is complete without all three**. Nothing in
`references/setup.md`, `audit.md`, `measure.md`, `act.md`, `ai-visibility.md` or `schedule.md`
requires anything here.

Everything happens in the USER's project directory — the current working directory. Never write
anything into the skill folder, and never edit the runner scripts that ship in it: section 3 edits
the user's own copy, exactly as `references/schedule.md` section 2.1 describes.

This file writes `power_ups.*` in `seo-god.json` and nothing else (section 4).

## 0. The rules that outrank this file

### 0.1 Three of SKILL.md's hard rules, quoted

Paraphrasing them is how they get lost:

> - Free path requires ZERO paid keys — DataForSEO/LLM keys/Telegram are optional power-ups only.
> - Any paid API path must be budget-capped BEFORE the first call (per-run cap + balance floor + ledger).
> - Secrets live in `.seo-god/secrets.env`, gitignored at creation, never printed, never committed.

Three consequences that apply to every section below, and to nothing else in this skill as sharply:

- **No uncapped loop may EVER call a paid endpoint.** Not "usually", not "unless the list is short".
  Every paid call site in this file is bounded before it runs, and the bound is checked between calls.
- **The skill never spends the user's money on its own initiative and never buys anything.** It does
  not top up a balance, does not upgrade a plan, does not raise a cap, and does not "borrow" against
  one. Only the user changes a cap, and only in the file they own.
- **You never need to read a secret to use it.** Every command below reads the value out of
  `.seo-god/secrets.env` inside the shell. Do not `cat`, `Read`, or echo that file, and never print a
  key, token, or password back to the user — not to confirm it, not truncated, not "just the last
  four".

### 0.2 Secrets mechanics: pointers, not a second copy

`.seo-god/secrets.env` and its Compose wiring already have exactly one owner each. Follow them; do
not restate or re-invent them here:

- **The file, and the `env_file:` wiring** — `references/measure.md` section 3.4 steps 1-5: one
  `KEY=value` per line, no quotes, no `export`, file ends with a newline; appends write a leading
  blank line so they cannot splice onto an unterminated last line; **if the compose file already has
  an `env_file:` key, leave it alone** (a second one is a duplicate mapping key and Compose then
  refuses to parse the file at all, which takes the container down); create the file *before* adding
  the key; recreate the container afterwards, because editing the file alone changes nothing.
- **Surviving a setup re-run** — `references/setup.md` step 3's preservation clause: SKILL.md routes
  back to setup whenever `openseo.status` is not `"running"`, and setup rewrites the compose file
  verbatim *except* for an existing `env_file:` key. If that line ever disappears, everything that
  depends on the container's environment goes dark silently.
- **The gitignore guard** — `.seo-god/` must be in the project `.gitignore` before you write anything
  into it. Setup put it there; check, and add the line if it is missing.
- **The shell rule** — `references/setup.md` step 5 governs every request in this file: on Windows
  PowerShell call `curl.exe`, keep the whole command on one line, and never inline a JSON body —
  write it to a file and pass `-d "@thatfile"`.

### 0.3 Reading and writing one value, in both shells

One mechanism, used by all three power-ups. It reads the **last** matching line, which is how
Compose and dotenv resolve duplicates:

```
# macOS, Linux, Git Bash
sg_secret() { sed -n "s/^$1=//p" .seo-god/secrets.env 2>/dev/null | tail -n1; }
D4S_KEY="$(sg_secret DATAFORSEO_API_KEY)" || D4S_KEY=""
```

```
# Windows PowerShell (one line each)
function Get-SgSecret([string]$Name) { $m = Select-String -Path .seo-god/secrets.env -Pattern "^$Name=" -ErrorAction SilentlyContinue | Select-Object -Last 1; if ($m) { $m.Line.Substring($Name.Length + 1) } else { '' } }
$d4sKey = Get-SgSecret DATAFORSEO_API_KEY
```

Both are shell functions, and a shell does not survive between tool calls: define the one you need
in the same command that uses it.

Adding a value:

- **The file does not exist yet** → create it with your Write tool, one `KEY=value` line, ending with
  a newline — the same way `references/measure.md` section 3.4 step 1 takes the Google client secret.
- **It exists** → append in the shell, so the other secrets in it never enter this session:

  ```
  # macOS, Linux, Git Bash — %s=%s keeps the name and the value separate arguments
  printf '\n%s=%s\n' DATAFORSEO_API_KEY "<the value>" >> .seo-god/secrets.env
  ```

  ```
  # Windows PowerShell (one line) — the leading "" is the blank-line splice guard
  $k = 'DATAFORSEO_API_KEY'; Add-Content -Path .seo-god/secrets.env -Value @("", "$k=<the value>")
  ```

Removing a value — a filter, so removing one secret never reads the others into the session:

```
# macOS, Linux, Git Bash — the braces keep a file whose ONLY line was that key from aborting the write
K=DATAFORSEO_API_KEY
{ grep -v "^$K=" .seo-god/secrets.env || true; } > .seo-god/secrets.env.tmp
mv .seo-god/secrets.env.tmp .seo-god/secrets.env
```

```
# Windows PowerShell (one line) — @() forces an array (on a one-line file a bare Get-Content returns a string and -notmatch answers True), and WriteAllLines keeps it UTF-8 with no BOM, which Compose needs
$k = 'DATAFORSEO_API_KEY'; $p = (Resolve-Path .seo-god/secrets.env).Path; [System.IO.File]::WriteAllLines($p, (@(Get-Content -LiteralPath $p) -notmatch "^$k="), (New-Object System.Text.UTF8Encoding $false))
```

Then recreate the container if the file was wired into it. Never leave a key line with an empty
value — an empty `Authorization: Basic` header is a 401 that looks like a wrong password, and an empty
bot token is a 404 (section 3.2).

> **Why these snippets assemble the line from a name and a value instead of writing it out
> literally**: `scripts/skill-lint.mjs` fails the build on the literal pattern of a key name
> immediately followed by `=` and a value, because that pattern is exactly how a real operator key
> leaks into a public repo. Do not "simplify" them back.

### 0.4 Offer discipline — when to bring these up, and when not to

Contextual offers only. Name the trigger moment, say what it costs, say what stays true without it,
and take a "no" as final for the session.

| The moment | Offer | The shape of the one line |
| --- | --- | --- |
| `references/measure.md` section 4 just said tracked positions are **not measured**, or the user asks what position they rank at | DataForSEO | Real positions need a paid data source; DataForSEO is the one OpenSEO uses, capped at a per-run budget you set |
| `references/act.md` cannot order quick wins, or a content-gap decision needs real search volume | DataForSEO | Volume and difficulty for the whole tracked list is one capped call |
| The user asks about backlinks or referring domains — nothing on the free path measures them | DataForSEO | One capped call per domain gives counts and first-seen dates |
| The user disputes the proxy: *"but does ChatGPT actually name me?"* | LLM keys | The free score counts search results; a model key asks the models themselves, on the same locked prompts |
| `references/ai-visibility.md` has a locked set and at least one measured day | LLM keys | Same ten prompts, so the upgrade is comparable to what you already have |
| A schedule was just installed and the user asks how they will know it ran | Telegram | The runner can send the day's readout to your phone when a run **completes**; the token stays in the gitignored secrets file |
| SKILL.md's missed-run warning just fired | Telegram | A message every morning is what makes a morning **without** one worth noticing — the digest never reports a failure itself, so SKILL.md's 48h warning stays the failure signal |

Never: offer during `references/setup.md`; offer a paid key as the fix for something with a free fix;
offer twice in one session after a no; bundle two power-ups into one question; or make any phase
wait on an answer. A power-up the user declined is not a degraded install — it is the documented
default.

## 1. DataForSEO — real volume, difficulty and backlinks, hard-capped

Paid, prepaid, and the only power-up that can spend money on its own if you are careless. Read
section 1.4 before the first call, every time.

### 1.1 What the key actually enables self-hosted — verified, not marketed

Verified against the OpenSEO source at the version this skill targets (paths are relative to
OpenSEO's repository). Read this table to the user before they pay for anything, because two of its
rows are the opposite of what the dashboard implies.

| Adding the key… | Reality |
| --- | --- |
| …lets **this skill** read volume, difficulty and backlink summaries | Yes — section 1.5, and only under the section 1.4 guard |
| …lets the **user** create a rank tracker and run a check from the dashboard | Yes, and only from the dashboard: `get_rank_tracker` is the sole rank-tracking MCP tool and it is read-only ("Uses no credits… To trigger a new check, use the dashboard" — `src/server/mcp/tools/get-rank-tracker.ts`). No MCP tool creates a tracker, adds tracked keywords, or triggers a check |
| …makes rank checks run **automatically** on a schedule | **No.** OpenSEO's only cron work is the Cloudflare Workers `scheduled()` export (`src/server.ts`, `*/15 * * * *` in `wrangler.jsonc`), and the Docker image never invokes it — `docker-entrypoint.sh` ends in `vite preview`, a plain Node server with no cron daemon, no supervisor and no `setInterval` fallback. Their own boot log says it: `Rank-tracking schedules do not run in Docker mode — trigger checks from the Rank Tracking page.` (`src/lib/selfhost-preflight.ts`) |
| …means a tracker showing "Weekly" will check weekly | **No.** A new tracker defaults to a weekly interval with a real next-check timestamp (`src/db/app.schema.ts`), and in Docker that timestamp never fires. Say this out loud when the user creates one, or they will trust a schedule that does not exist |
| …caps spending somehow inside OpenSEO | **No.** OpenSEO's metering is hosted-mode only: in `local_noauth` the metering wrapper short-circuits and calls just execute (`src/server/lib/dataforseo/client.ts`) — no pre-call balance check, no spend record, no cap. Self-hosted, the only backstop is the prepaid balance |

Two spend paths inside OpenSEO the user will not expect, both worth naming before they wire the key
into the container:

- **Opening a project dashboard page can spend money.** When its backlink snapshot is missing or more
  than a day old, the page fires `backlinks/summary/live` by itself
  (`src/client/features/dashboard/DashboardPage.tsx` → `refreshDashboardBacklinkSnapshot`). Browsing
  costs, not just clicking Check Now.
- **Adding keywords to an existing tracker triggers a check immediately** — plus a keyword-metrics
  refresh — with no separate confirmation (`src/serverFunctions/rank-tracking.ts`).

So there are two levels, and the user chooses:

| | Level 1 — file only (check it is available — below) | Level 2 — file + container |
| --- | --- | --- |
| What you do | write the key into `.seo-god/secrets.env` | Level 1, plus the `env_file:` wiring and a container recreate (`references/measure.md` section 3.4 steps 3-4) |
| This skill's capped reads (1.5) | work | work |
| OpenSEO rank tracker, domain overview, backlink tools | stay unavailable; `checks.dataforseo` stays `warn` | live |
| Can browsing the dashboard spend money | no | **yes** — the visit-triggered call above |
| Spend the section 1.4 ledger can see | all of it | only this skill's own calls |

**Check whether Level 1 is even available on this project, BEFORE you promise it.** The two levels are
separable only while the container is *not* pointed at this file — and `references/measure.md` section
3.4 step 3 wires `env_file: - secrets.env` into `.seo-god/docker-compose.yml` for Google Search
Console, which is the SAME file this key goes into. So read `.seo-god/docker-compose.yml` first:

- **No `env_file:` key** → Level 1 is real. Proceed, and say that connecting GSC later promotes this
  project to Level 2 by itself, which is this paragraph again.
- **`env_file:` present** → **Level 1 does not exist here.** Say it plainly: the key reaches OpenSEO
  at the container's next recreate — a GSC re-verification, a setup re-run, an `up -d` after a
  reboot — `checks.dataforseo` flips from `warn` to `ok`, and from then on opening a project dashboard
  page can spend money with nothing inside OpenSEO capping it. Then make the user choose
  **explicitly**: accept Level 2 with those consequences, or skip the power-up. Do not write the key
  on a shrug, and **never delete the `env_file:` line to force Level 1** — that takes Search Console
  down silently, and adding it back later as a second key takes the whole container down
  (section 0.2).

**Default to Level 1 wherever it exists.** Go to Level 2 only when the user has said they want real
rank positions or OpenSEO's own paid screens, and only after they have heard the "browsing costs
money" line. Level 2's uncapped surface is the user's dashboard, driven by their clicks — this skill
still never calls a paid OpenSEO MCP tool (`references/measure.md` section 2 keeps
`get_domain_overview` off-limits for exactly this reason), and an unattended run never triggers one.

Once a tracker exists and the user has run a check, `references/measure.md` section 5.3 picks the
stored positions up for free on the next run — reading a tracker costs nothing; checking it costs.

None of this is SERP scraping, and the hard rule against it does not bend here: this skill never
requests a Google results page, and OpenSEO's rank checks go through DataForSEO's licensed SERP API,
triggered by the user in their own dashboard. No curl, no WebFetch, no headless browser, no "just
this once" — with or without a key.

### 1.2 Sign up and build the key

1. They create an account at https://dataforseo.com/ and open the API-credentials page in their
   dashboard. **The API password is not the dashboard sign-in password** — take both the login (their
   account email) and the API password from that page. If the sign-in password gets pasted instead,
   the first call returns HTTP 401, and that is the fix.
2. They fund it. OpenSEO's own documentation states new accounts include $1 of free credit and that
   the minimum top-up is $50 — quote it as their figure and let the user confirm the current numbers
   on the billing page rather than promising a price. $1 of credit is enough to prove the key works
   and to run section 1.5 many times over.
3. The key is `base64("login:password")` — the colon-joined pair, encoded, with no trailing newline.
   OpenSEO does **not** encode anything for you: it interpolates the value straight after `Basic `
   (`src/server/lib/dataforseo/core.ts`), and its own validator just checks that the value decodes to
   something containing a colon (`src/shared/selfhost-checks.ts`).

   ```
   # macOS, Linux, Git Bash
   printf '%s' 'login:password' | base64 | tr -d '\n'
   ```

   ```
   # Windows PowerShell (one line)
   [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('login:password'))
   ```

   `tr -d '\n'` is not decoration: some `base64` builds wrap long output, and a newline inside an
   `Authorization` header is a 401 with no useful message.

   If the user would rather their password never enter this session, give them the one-liner to run
   in their own terminal and have them paste only the encoded result. It is the same value.

4. Store it as `DATAFORSEO_API_KEY` using section 0.3. Nothing goes in `seo-god.json`.

### 1.3 Verify the key with a free call — not from the health endpoint

`checks.dataforseo` reports **presence and shape only, and never makes a live call**. Its exact
states (`src/lib/selfhost-preflight.ts`): unset → `warn`, detail beginning `Not set — all SEO data
features will be unavailable until it is.`; set but not decodable to `login:password` → `warn`,
detail beginning `Set, but does not decode as base64 of login:password.`; set and decodable → `ok`,
detail `Set`. A key that is well-formed and wrong reads as `ok` there. Missing is `warn`, never
`error`, so the overall `status` stays `"ok"` either way — `references/setup.md` step 5 already says
so, and it is still the intended free-path state.

The real test is one free, unmetered call (this is also the balance floor in section 1.4, so you get
both from the same request):

```
curl -s -m 90 -H "Authorization: Basic $D4S_KEY" https://api.dataforseo.com/v3/appendix/user_data
```

- `tasks[0].result[0].money.balance` → the spendable balance in USD. `login` comes back too; it is a
  cheap confirmation the credentials belong to the account the user thinks they do.
- HTTP 401 → wrong credentials or the dashboard password. Fix and retry; make no other call.
- `status_code` other than `20000` at the response or task level → report it verbatim and stop.

Never put the key in the command text. `$D4S_KEY` / `$d4sKey` comes from section 0.3.

### 1.4 The budget guard — mandatory, and it runs BEFORE the first paid call

This is the section that makes the whole power-up permissible. If any step here cannot be completed,
make **no paid call at all** and say why.

**1. The cap.** `SEO_GOD_D4S_BUDGET_USD` is the per-run ceiling in USD. Precedence: a process
environment variable of that name (one run), else the same name in `.seo-god/secrets.env` (durable —
it is not a secret, it just lives with them; OpenSEO ignores it), else **`0.50`**. A value that does
not parse as a positive number is treated as `0`, and `0` means no paid call is made. The user is the
only one who changes it — never raise it yourself, not even when a readout would look better.

**2. The balance floor.** Call `appendix/user_data` (1.3) first, every run. Below **`$2.00`**, disable
the entire paid plane for the run, tell the user the balance and that they can top up at their
dashboard, and make no paid call. A balance call that fails — network, 401, malformed reply — disables
it too: this fails closed, because "I could not check" is not "it is fine".

**3. The accumulator.** Start at `spent = 0`. After every response, add the sum of `tasks[].cost` to
it. The response also carries a top-level `cost` for the whole call; the two agree, and if they ever
disagree take the larger. A task that failed can still carry a cost — add it anyway.

`spent` lives in your working memory for the length of the run: there is no on-disk counter, and step
5 writes the total once, at the end. **An interrupted run therefore records nothing** — the money was
spent and the ledger will not show it. That is accepted rather than fixed: a write per call would make
an advisory file into a second source of truth, and the balance floor already catches the drift on the
next run, because it reads the real balance from DataForSEO rather than from this file.

**4. The stop rule.** Before each call, if `spent >= cap`, **stop making paid calls for the rest of
the run.** Do not shrink the request and try again, do not "finish the last one", do not wait and
retry. Then finish the readout honestly: report what you did get, and name what you skipped and why
("backlink summaries for 3 of 5 competitors skipped — per-run budget reached at $0.50"). A truthful
partial readout is the intended outcome of a cap being hit; a complete readout that quietly overspent
is a bug.

**The cap stops the NEXT call; it cannot un-spend the current one.** A call already sent completes and
its cost is added, so a run can end a little over the cap — plan for `cap + the cost of one call`, and
choose the cap on that basis instead of expecting a ceiling exact to the cent.

**5. The ledger.** Append one entry per run that made at least one paid call to `.seo-god/spend.json`,
creating the file if it is absent. Write it with your Write tool as a read-modify-write, never with
shell redirection:

```json
{
  "runs": [{ "date": "2026-08-01", "spent": 0.0142, "balance": 41.18 }],
  "by_month": { "2026-08": 0.0142 }
}
```

`date` is today's local date, `spent` is the accumulator, `balance` is what the pre-flight read
(`null` if it could not be read). Recompute `by_month` from `runs` on every write — never increment
it — so a hand-deleted run cannot leave a phantom total behind. A run that made no paid call appends
nothing. `.seo-god/` is gitignored, so this ledger is local and a fresh clone starts empty: the cap
that actually binds is per-run, the monthly figure is information.

If the file exists but **will not parse** — truncated, hand-edited — treat it exactly as absent: start
a fresh file with today's entry, and name the filename and the parse error in the readout, so a
corruption that keeps recurring is visible rather than quietly overwritten every day. Never guess at
the entries you could not read.

**6. The never list.** No `while` loop, no "until the list is done", no recursive retry around a paid
call. One retry, only on a network error or a 5xx, and its cost counts too. Never call a paid endpoint
from inside a loop whose length you have not bounded and checked against the cap first. Never call one
at all when the user has not enabled this power-up in this project.

### 1.5 The three endpoints

Base `https://api.dataforseo.com`, header `Authorization: Basic <key>` from section 0.3, bodies are
**JSON arrays of task objects** written to a scratch file and sent with `-d "@file"` per the shell
rule in section 0.2 (`.seo-god/d4s-body.json` is fine — it holds keywords, not secrets). Use the
project's own market: take `locationCode` and `languageCode` from `list_projects`
(`references/setup.md` step 6; the default is `2840` / `"en"`).

**Every call carries a 90-second timeout** — `-m 90`, or `-TimeoutSec 90` if you reach for
`Invoke-RestMethod` — matching the ceiling our production client uses. A `/live` endpoint that has not
answered in 90 seconds is not going to, and an unbounded curl inside a scheduled run is how a two-hour
execution limit gets spent on one socket.

**1. Search volume and CPC** — `POST /v3/keywords_data/google_ads/search_volume/live`

```json
[{ "keywords": ["first keyword", "second keyword"], "location_code": 2840, "language_code": "en" }]
```

`tasks[0].result` is a **flat array** of rows: `{keyword, search_volume, cpc, competition_index}` —
there is no `items` wrapper here, unlike the next one. Up to 1000 keywords per call and flat-priced
per request, so **one call prices the entire tracked list**. Never loop it per keyword.

**2. Keyword difficulty** — `POST /v3/dataforseo_labs/google/bulk_keyword_difficulty/live`

Same body shape. The rows are one level deeper: `tasks[0].result[0].items`, each
`{keyword, keyword_difficulty}`. Same 1000-per-call batching, same one-call rule.

**3. Backlink summary** — `POST /v3/backlinks/summary/live`

```json
[{ "target": "example.com", "include_subdomains": true, "exclude_internal_backlinks": true, "backlinks_status_type": "live", "rank_scale": "one_hundred" }]
```

**ONE task per call — loop targets serially**, checking the cap between calls and pausing briefly
(half a second is plenty) between them. This is the one endpoint in the set whose cost scales with a
list you might be tempted to grow, so bound the list before you start: the user's own domain, plus at
most the top few competitor hosts from `ai_visibility.competitors`. `tasks[0].result[0]` carries
`{target, rank, backlinks, referring_domains, referring_main_domains, referring_domains_nofollow,
broken_backlinks, first_seen}`. `rank` under `rank_scale: "one_hundred"` is DataForSEO's own 0-100
domain-strength number — label it as such, and never present it as another vendor's DR score.

Response handling for all three: `status_code` `20000` means ok at both the response and the task
level; anything else is reported verbatim, not retried in a loop. Costs go through section 1.4 step 3
before you read any row.

### 1.6 Reporting paid data honestly

- **Label the source and the day.** "search volume 2,400/mo (DataForSEO, 2026-08-01)" — never an
  unattributed number, because the free path cannot produce it and a later reader must know which
  numbers cost money.
- **The snapshot schema does not grow.** `references/measure.md` section 5.5's shape is a fixed
  contract; paid figures do not get new keys in it. They belong in the readout, dated and labelled.
  The one paid number that does reach a snapshot arrives through the existing schema:
  `ranks[].position` stops being `null` once the user's own tracker has results, read for free by
  that file's section 5.3.
- **One mandated readout line whenever a paid call happened**, in `references/act.md`'s style:
  `DataForSEO: 4 calls, $0.0142 of the $0.50 per-run cap (balance $41.18)`. When the cap stopped the
  run, that line says so and names what was skipped. When the balance floor disabled the plane, the
  line is `DataForSEO: disabled — balance $1.40 below the $2.00 floor; nothing was called`.
- **Data honesty does not soften here.** A number you did not buy is not measured, not zero.

### 1.7 Turning it off

Remove the key line from `.seo-god/secrets.env` with section 0.3's filter; if it was wired into the
container, recreate it and
confirm `checks.dataforseo` is back to `warn`. Set `power_ups.dataforseo` to `false` (section 4).
Leave `.seo-god/spend.json` alone — it is the record of what was spent. Everything that used paid
numbers returns to "not measured", which is the free path working as designed.

## 2. LLM keys — direct model probing for AI visibility

`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY` — any one is enough, and this power-up
upgrades exactly one thing: `references/ai-visibility.md`'s measurement stops being a search-results
proxy and starts asking models directly, on the same locked prompts.

These keys are read by **this skill**, not by OpenSEO. OpenSEO's own `checks.ai` entry is about
`OPENROUTER_API_KEY` and its in-app agent (`src/lib/selfhost-preflight.ts`); nothing in it reads
these three names, so storing them in `.seo-god/secrets.env` cannot make the container spend money,
and no container recreate is needed.

### 2.1 The contract you may not break

`references/ai-visibility.md` owns the measurement. This power-up changes the **evidence**, never the
bookkeeping:

- **The same locked prompt set.** `ai_prompts_locked`, unedited, in order. That is the whole reason
  the set is locked: today's proxy number and tomorrow's direct number ask the same questions. Never
  reword a prompt for a model, never add the brand or the domain, never translate.
- **`prompts_ok` still counts prompts** — how many of the locked prompts got an answer back from at
  least one configured model. Never a count of queries. A model that returns an empty or unhelpful
  answer still returned: that prompt is `ok`.
- **`cited` still counts prompts, and can never exceed `prompts_ok`** — how many prompts had the
  user's domain in the model's answer. Three mentions in one answer is still one prompt.
- **`competitors` is counted exactly as before** — `{host: number of prompts that host appeared in}`,
  keyed by the bare host lowercased with a leading `www.` stripped, the user's own domain excluded,
  top 10 by count with ties broken alphabetically, sorted before capping. In direct mode its evidence
  is the same as `cited`'s: **third-party domains named in the model's answer**, as a bare host or
  inside a URL, counted **once per prompt** however many times they appear in it. A bare brand name
  with no domain counts for nobody — the same rule as `ai-visibility.md` section 3.3 — so a model that
  says "use Acme" without a domain adds nothing to any key. Do not fold subdomains together; that
  file's reasoning holds here too.
- **The snapshot block keeps its four keys and no others** — `measured`, `prompts_ok`, `cited`,
  `competitors` (`ai-visibility.md` section 4.1). **Do not add a `mode` key.** The mode lives in the
  readout, for the same reason the branded/unbranded split does: the snapshot has no room for it, so
  the readout line is the only record.
- Everything else in that file still applies unchanged: the attended/unattended fork, the
  unattended-with-no-locked-set skip, one retry per failed query, `prompts_ok` of zero writing no
  block at all, and the playbook.

### 2.2 What each mode measures — the words that stay true

| Mode (label in section 2.5) | Say this | Never say this |
| --- | --- | --- |
| Free `WebSearch` proxy — *no label* | "appeared in search results for 6 of 10 prompts (results-page proxy)" | "ChatGPT cites you for 6 of 10" |
| Direct, no browsing — `[mode: direct-model]` | "named in the model's own answer for 6 of 10 prompts — what the model already believes, not a live citation" | "cited by ChatGPT", "share of voice in AI answers" |
| Direct, browsing enabled — `[mode: direct-model+browsing]` | "named in the model's answer for 6 of 10 prompts, with the model's own search enabled" | "6 of 10 AI citations" |

The domain match is mechanical, and one line of it differs from the proxy on purpose: **in a model's
answer, naming the domain IS the appearance**, so `example.com` in the answer text counts, and so does
a URL whose host equals the bare host or ends with `"." + bare host`. What still never counts is the
brand **name** alone with no domain, and substring matches are still forbidden — `notexample.com` is a
different company. Mention a name-only appearance in the prose if you like; it never moves the number.

Because that rule differs from the proxy's "result URLs only", a proxy day and a direct day are two
instruments. That is what the mode label in section 2.5 is for, and why a cross-mode delta is never
reported as movement.

### 2.3 Store the keys, pick the models, keep the configuration still

Store whichever keys the user has, by their standard names, using section 0.3. Then agree two things
and write them into the readout every day, because both are part of the instrument:

- **Which models.** Ask; default to each provider's current small/cheap tier. Do not hardcode a model
  id from memory — model ids get retired, and a silent substitution changes the measurement.
- **Browsing off, unless the user insists.** A plain completion measures what the model has absorbed
  about the user's site; a search-enabled model measures retrieval. Both are legitimate; **switching
  between them between runs is not**. Whatever they choose, it stays fixed, and the readout says
  which it was.

Request shapes, current at the time of writing — read the provider's own reference before assuming a
field, and never put a key in the command text (section 0.3):

- OpenAI — `POST https://api.openai.com/v1/chat/completions`, header `Authorization: Bearer <key>`
- Anthropic — `POST https://api.anthropic.com/v1/messages`, headers `x-api-key: <key>` and
  `anthropic-version: 2023-06-01`
- Gemini — `POST https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent`,
  header `x-goog-api-key: <key>`

JSON bodies go to a scratch file and are sent with `-d "@file"` (section 0.2's shell rule). Keep the
answer short — a few hundred tokens is plenty when all you need is presence — and send the locked
prompt as the entire user message, with no system prompt steering it toward or away from the domain.

### 2.4 The pass, and its cap

**A pass is exactly `len(ai_prompts_locked) × len(configured models)` queries, and at most one pass
per day.** Ten prompts and three models is thirty queries; there is no branch that makes it more. One
retry per query, only on a network error or a 5xx, per `ai-visibility.md` section 3.2 — no other
retries, no reworded second attempt, no loop.

If today's readout already carries a direct-mode `Score:` line, the pass already ran: report those
numbers, say they are today's, and do not probe again unless the user explicitly asks for a second
pass — in which case it replaces the first and the readout says so (`ai-visibility.md` section
4.1's same-day rule).

How the hard rule's three parts land here, stated plainly rather than quietly skipped:

| Hard-rule part | Here |
| --- | --- |
| per-run cap | the deterministic query count above — a bound the loop cannot exceed, checked before the first call |
| balance floor | **not available** — none of the three providers exposes a balance endpoint. The bound stands in for it, and the user should set a **provider-side spend limit** in their own account. That is the only cap that binds a key they hold, and it takes a minute |
| ledger | the readout's `Models:` line, which records the models, the mode and the query count for the day. `.seo-god/spend.json` stays DataForSEO-only, so its `spent` figure never mixes two currencies of truth |

Cost, honestly: thirty short completions on small models is cents at current prices, and prices are
the provider's to change. Tell the user the query count and let them price it — do not quote a dollar
figure from memory.

### 2.5 The readout — the mode label, added compatibly

`references/ai-visibility.md` section 5 owns the readout. Direct mode adds a label to two existing
lines and one new mandated line; it changes nothing else, and it must not disturb the greppable
conventions that file depends on (`Split:` as the only record of the halves,
`AI visibility baseline reset` as the reset marker, the playbook records).

```
## 2026-08-01 09:20 — AI visibility

Direct model answers on the locked 10-prompt set (model-answer presence, not a live citation)
Score: your domain was named in 6 of the 10 prompts that returned  [mode: direct-model]
Split: branded-adjacent 4/5, unbranded commercial 2/5  [mode: direct-model]
Models: openai/<model-id>, anthropic/<model-id> — no browsing, 30 queries, 1 pass
Trend: 6/10 vs 4/10 on 2026-07-25 — measured differently (that day was the search-results proxy)
Answer slots taken by: competitor-one.com (7 prompts), a-directory.com (4)
Snapshot: dist/seo/snapshots/2026-08-01.json (ai_visibility block updated)
```

**The modes and their label literals are pinned — these three, and nothing else:**

| Mode | Label on the `Score:` and `Split:` lines |
| --- | --- |
| free `WebSearch` proxy (`ai-visibility.md` section 3) | **none** — the proxy writes no label, and absence is its marker; every readout written before this power-up existed has none |
| direct probing, browsing and tools off | `[mode: direct-model]` |
| direct probing, the provider's own search enabled | `[mode: direct-model+browsing]` |

Never invent a fourth, never write `[mode: search-proxy]`, never abbreviate or re-space one. The
trend's same-mode test is **exact equality of that bracketed literal**, with both-absent counting as
equal; anything else — one present and one absent, or two different literals — is a different mode.

- The label is a **suffix**: `Score:` and `Split:` still begin the line and still carry the same
  numbers in the same order, so that file's section 5 `Split:`-line rule keeps working unchanged.
- `Models:` is a **mandated** line under this power-up, and that file's section 5 tiebreak governs
  it: mandated lines are never dropped to hit the 12-line cap, merge before you drop, and go over the
  cap rather than lose a fact.
- The trend line gains one rule on top of the six in that file's section 5. Read the comparison
  day's mode from the `[mode: …]` suffix on its `Score:` line. **Absent means that day was the
  proxy** — the direct path always writes the label, so a readout without one predates it. Then:
  - **Different mode** → report both fractions and say they were measured differently. Never present
    the difference as movement, never average them, and never relabel the older number.
  - **Same mode, different model set** → report the delta and name the model change in the same line.
  - **Same mode, same models** → an ordinary trend, per `ai-visibility.md` section 5.
  - **No readout for the comparison day** → the mode is unknown; say so instead of assuming.
- A proxy day is never rewritten to look like a direct day, and the first direct day is not a baseline
  reset: the prompt set did not change, so `ai_prompts_locked` is untouched and the reset marker is
  not written.

### 2.6 When a key is present but the pass cannot run

| Situation | What happens | What the readout says |
| --- | --- | --- |
| no set locked yet | no probing at all — a direct pass on an unlocked set is unmeasurable and it would burn the money the lock exists to make meaningful | `ai-visibility.md` section 0's line, unchanged |
| every query failed | no score, no snapshot block, `measured` stays `false` | how many were attempted, that all failed, the error verbatim |
| one provider is down | the pass still counts prompts across the models that answered | which provider failed, and on how many prompts |
| a key is present but rejected (401) | that provider is not configured; if none answers, this is the every-query-failed row | which provider rejected the key |
| the user removed the keys | back to the free proxy, `WebSearch` and all | no mode label is written — absence is how a proxy day is recognised, and the trend says the modes differ |

### 2.7 Turning it off

Remove the key lines from `.seo-god/secrets.env` (section 0.3's filter, once per name) and set
`power_ups.llm_keys` to `false`. The next run measures the proxy again and writes no label, which is
how a proxy day is recognised. Locked prompts, snapshots and readouts stay exactly as they are —
nothing is rewritten, and the mode labels are what keep the history readable.

## 3. Telegram digest — the daily run on the user's phone

Outbound only: the runner sends one plain-text message at the end of a daily run. This skill never
reads commands from Telegram, because receiving would mean polling, and polling is the one thing
section 3.2's warning forbids sharing.

**The digest only fires on runs that COMPLETE, and that is the whole of what it promises.** The block
sits on the runner's success path, past every failure exit — a `claude` that exits non-zero, a missing
CLI, a hard kill, a machine that was off — so none of those sends anything. Say it in those words when
you offer it: **no message means the run did not finish**, and SKILL.md's 48h missed-run warning
(`references/schedule.md` section 3) remains the only failure signal. Do not move the block into a
trap or a `finally` to "fix" this: those live in the runner this skill ships, and section 3.3 edits
the user's copy only. The one piece of bad news the digest does carry is a run that finished
**degraded** — the marker it quotes says so itself, e.g. `completed (openseo unreachable)`.

**Prerequisite: the OS-native schedule from `references/schedule.md` section 2.** The digest is
appended to the project's copy of the runner, so it needs a runner to exist. On the cloud-routine
path (section 4 of that file) there is no runner and **no token may go into a routine prompt or a
schedule definition** — that path's output channel is the committed readout. With
`schedule.mode: "none"` there is nothing to append to either; the manual send in section 3.4 still
works.

### 3.1 Create the bot, store the token

1. The user opens Telegram, messages **@BotFather**, sends `/newbot`, gives a display name and a
   username ending in `bot`. BotFather replies with the token: digits, a colon, then a long opaque
   string. **It is a full bot credential** — anyone holding it can send as that bot.
2. Store it as `TELEGRAM_BOT_TOKEN` using section 0.3. Never echo it back, never put it in
   `seo-god.json`, never in a commit, never in a scheduler entry.
3. If it ever leaks: `/revoke` in BotFather invalidates it and issues a new one. Store the new one the
   same way.

### 3.2 Capture the chat id — exactly one `getUpdates` call

The user must message the bot first; a bot cannot open a conversation. Ask them to open their bot
(`t.me/<the bot's username>`) and send anything — "hi" is fine. Then, once:

```
# macOS, Linux, Git Bash — the helper is section 0.3's, defined here because a shell does not survive between calls
sg_secret() { sed -n "s/^$1=//p" .seo-god/secrets.env 2>/dev/null | tail -n1; }
curl -s -m 20 "https://api.telegram.org/bot$(sg_secret TELEGRAM_BOT_TOKEN)/getUpdates"
```

```
# Windows PowerShell — define Get-SgSecret from section 0.3 in the SAME command, then this one line
curl.exe -s -m 20 "https://api.telegram.org/bot$(Get-SgSecret TELEGRAM_BOT_TOKEN)/getUpdates"
```

A GET with no body, so section 0.2's `@file` rule has nothing to apply to.

Read `result[<the last entry>].message.chat.id` and, before storing it, check
`message.chat.type` is `"private"` and the `username` or `first_name` is the user's. A bot username is
guessable, and picking up a stranger's message would send the user's SEO readouts to the stranger.
Store the value as `TELEGRAM_CHAT_ID` (section 0.3). For a DM it is their own numeric id; it is not a
secret, but it lives with the token so the runner reads both from one file.

Empty `result` → they have not sent the message yet, or something else already consumed the queue. Ask
them to send another and make **one** more call. Still empty → stop. Do not poll in a loop.

A reply of `{"ok":false,"error_code":404,…}` → the token read back **empty**, so the URL was
`…/bot/getUpdates` with nothing between `bot` and the slash. That is a `secrets.env` problem, not a
network one: check the name on the line and that the value is not blank. `401 Unauthorized` is the
other shape — a token that is present and wrong, or one revoked in BotFather.

> **WARNING —**
> **if any other tool polls this bot's getUpdates, stop using getUpdates here — one poller only.**

Telegram hands each update to whoever confirms it first, so two pollers each see an arbitrary half of
the traffic and the other tool starts losing messages. If the user already runs anything on this
token, or a webhook is set (`getUpdates` then answers **409 Conflict**), do not poll it: make a second
bot for the digest — they are free — or take the chat id from the tool that already polls. Once the
chat id is stored, nothing in this skill ever calls `getUpdates` again; the digest only sends.

### 3.3 Insert the digest into the PROJECT copy of the runner

Edit `<project>/scripts/daily-run.sh` or `<project>/scripts/daily-run.ps1` — **the user's copy**. The
runner in the skill folder is never edited — `references/schedule.md` opens with that rule. Both
blocks read the two values at run time and send nothing when either is missing, so the runner stays
valid and correct for someone who never enabled this power-up — which is also why no value is ever
inlined: that copy is an ordinary repo file and committing it is expected.

**`daily-run.sh` — append at the very end of the file**, after the final `note` call:

```bash

# --- seo-god telegram digest (references/power-ups.md section 3.3) — safe to delete ---
# Reads TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID from .seo-god/secrets.env at run time and
# sends nothing when either is absent. EVERY assignment, command substitution and command
# below is guarded on purpose: this script runs under `set -e` with an ERR trap that
# rewrites the run marker, so one unguarded failure here would record a run that actually
# SUCCEEDED as ok:false.
sg_secret() { sed -n "s/^$1=//p" .seo-god/secrets.env 2>/dev/null | tail -n1; }
TG_TOKEN="$(sg_secret TELEGRAM_BOT_TOKEN)" || TG_TOKEN=""
TG_CHAT="$(sg_secret TELEGRAM_CHAT_ID)" || TG_CHAT=""
if [ -n "$TG_TOKEN" ] && [ -n "$TG_CHAT" ] && command -v curl >/dev/null 2>&1; then
  TG_DAY="$(date +%Y-%m-%d)" || TG_DAY="unknown date"
  TG_BODY="$(cat "$MARKER" 2>/dev/null || echo 'no run marker')"
  for TG_DIR in dist/seo/readouts seo/readouts; do
    if [ -f "$TG_DIR/$TG_DAY.md" ]; then
      TG_BODY="$TG_BODY
$(head -c 3000 "$TG_DIR/$TG_DAY.md" || true)"
      break
    fi
  done
  curl -fsS -m 20 -o /dev/null -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
    --data-urlencode "chat_id=$TG_CHAT" --data-urlencode "text=seo-god $TG_DAY
$TG_BODY" || true
fi
# --- end seo-god telegram digest ---
```

**`daily-run.ps1` — insert immediately BEFORE the final `exit 0`**, after the `Write-Marker` calls
that end the `try` block. Not at the end of the file: that `exit 0` fires first, so anything after
the `finally` block is unreachable and a digest appended there would never run once.

```powershell
  # --- seo-god telegram digest (references/power-ups.md section 3.3) — safe to delete ---
  # Reads TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID from .seo-god\secrets.env at run time and
  # sends nothing when either is absent. The try/catch is load-bearing: this script sets
  # $ErrorActionPreference = 'Stop' and traps terminating errors into an ok:false marker,
  # so an unguarded failed send would record a successful run as a failed one.
  try {
    $tgFile = Join-Path (Join-Path $root '.seo-god') 'secrets.env'
    $tg = @{}
    if (Test-Path -LiteralPath $tgFile -PathType Leaf) {
      foreach ($tgLine in (Get-Content -LiteralPath $tgFile)) {
        $tgEq = $tgLine.IndexOf('=')
        if ($tgEq -gt 0 -and -not $tgLine.StartsWith('#')) {
          $tg[$tgLine.Substring(0, $tgEq).Trim()] = $tgLine.Substring($tgEq + 1).Trim()
        }
      }
    }
    if ($tg['TELEGRAM_BOT_TOKEN'] -and $tg['TELEGRAM_CHAT_ID']) {
      $tgDay = [DateTime]::Now.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
      $tgBody = 'no run marker'
      if (Test-Path -LiteralPath $marker -PathType Leaf) {
        $tgBody = (Get-Content -LiteralPath $marker -Raw)
      }
      foreach ($tgDir in @('dist\seo\readouts', 'seo\readouts')) {
        $tgReadout = Join-Path (Join-Path $root $tgDir) "$tgDay.md"
        if (Test-Path -LiteralPath $tgReadout -PathType Leaf) {
          $tgText = (Get-Content -LiteralPath $tgReadout -Raw)
          if ($tgText.Length -gt 3000) { $tgText = $tgText.Substring(0, 3000) }
          $tgBody = "$tgBody`n$tgText"
          break
        }
      }
      Invoke-RestMethod -Method Post -TimeoutSec 20 -Uri ('https://api.telegram.org/bot' + $tg['TELEGRAM_BOT_TOKEN'] + '/sendMessage') -Body @{ chat_id = $tg['TELEGRAM_CHAT_ID']; text = "seo-god $tgDay`n$tgBody" } | Out-Null
    }
  } catch {
    [Console]::Error.WriteLine("seo-god: telegram digest failed - $($_.Exception.Message)")
  }
  # --- end seo-god telegram digest ---
```

Seven details in those blocks that are not style:

- **Every assignment and substitution in the sh block is guarded, and that is load-bearing.** Walk it:
  the two `sg_secret` reads end in `|| TG_…=""`; `date` ends in `|| TG_DAY="unknown date"`; the `cat`
  guards itself with an inner `|| echo`; the `head` inside the readout substitution ends in
  `|| true`; the `curl` ends in `|| true`. Under `set -e` plus the runner's ERR trap, **any one of
  those failing unguarded rewrites a successful run's marker to `ok:false`** — an unreadable readout
  file is enough to do it. If you add a line here, guard it.
- **`$MARKER` / `$marker` and `$root` are the runner's own variables.** The block only works inside
  that script, at that position, which is the point: the digest reports the marker the runner just
  wrote. It also means the block cannot be lifted elsewhere unchanged — under `set -u` an unset
  `MARKER` would itself trip the trap.
- **The digest goes after the marker, never before.** The message's whole value is saying which
  outcome was recorded.
- **`Invoke-RestMethod` rather than `curl.exe` on Windows** — deliberately, and consistent with the
  rest of the runner. The body is form-encoded, so there is no JSON to quote, and the `@file` rule in
  section 0.2 has nothing to apply to.
- **No `parse_mode`.** The readout is Markdown and Telegram rejects unbalanced markup with a 400. Plain
  text always sends.
- **The truncation is 3000 BYTES in sh (`head -c`) and 3000 CHARACTERS in PowerShell
  (`Substring`)** — each shell's natural unit, left different on purpose rather than papered over.
  Both stay inside Telegram's 4096-character limit with room for the marker line, and the byte cut can
  split a multibyte character at the boundary, which is harmless in a plain-text digest.
- **`InvariantCulture` on the ps1 date** — the same bug class the runner's own `Write-Marker` comment
  names: under a culture whose calendar is not Gregorian, `yyyy-MM-dd` renders a different year, and
  the readout filename would then never match.

### 3.4 Test it, and know what a dry run does not test

`SEO_GOD_DRY_RUN=1` exits before the end of both runners, so **it never reaches the digest block**.
Test the send on its own instead — same read-from-file pattern, no values inlined:

```
# macOS, Linux, Git Bash — from the project root; the helper is section 0.3's
sg_secret() { sed -n "s/^$1=//p" .seo-god/secrets.env 2>/dev/null | tail -n1; }
curl -sS -m 20 -X POST "https://api.telegram.org/bot$(sg_secret TELEGRAM_BOT_TOKEN)/sendMessage" --data-urlencode "chat_id=$(sg_secret TELEGRAM_CHAT_ID)" --data-urlencode "text=seo-god test"
```

```
# Windows PowerShell — from the project root; define Get-SgSecret from section 0.3 in the same command
Invoke-RestMethod -Method Post -TimeoutSec 20 -Uri ('https://api.telegram.org/bot' + (Get-SgSecret TELEGRAM_BOT_TOKEN) + '/sendMessage') -Body @{ chat_id = (Get-SgSecret TELEGRAM_CHAT_ID); text = 'seo-god test' }
```

The reply prints — there is no `-o /dev/null` here on purpose, because `"ok":true` in it is half the
test and the user confirming the message arrived is the other half. Read the reply; do not infer it
from a zero exit. `chat not found` means the chat id is wrong or they blocked the bot;
`401 Unauthorized` means the token is wrong or revoked; `error_code 404` means the token read back
empty (section 3.2). The first real digest is tomorrow's run.

### 3.5 Re-installing the schedule deletes this block — check for it afterwards

Both installers copy the skill's runner over the project's copy **unconditionally**
(`Copy-Item -Force` and `cp`), so any re-run of `install-schedule` — a time change, a reinstall after
moving the project — silently removes the digest. It is the one edit in this skill that a supported
action can undo, so after any schedule change, look for the marker comment and re-append if it is
gone:

```
grep -n 'seo-god telegram digest' scripts/daily-run.sh
```

```
Select-String -Path scripts\daily-run.ps1 -Pattern 'seo-god telegram digest'
```

No match, `power_ups.telegram` still `true`, and no digest arriving are the same fact seen three ways.

### 3.6 Turning it off

Delete the block between its two marker comments (or let a schedule re-install remove it), remove
`TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` from `.seo-god/secrets.env` (section 0.3's filter), and set
`power_ups.telegram` to `false`. Optionally `/deletebot` in BotFather. The runner is valid and
complete either way — that is what the absent-variable guard is for.

## 4. Write state

Update `seo-god.json` — read, modify, write the whole object, preserving every key you do not
recognise, keeping `version: 1`:

- `power_ups.dataforseo` — `true` once the key is stored and `appendix/user_data` returned a balance.
- `power_ups.llm_keys` — `true` once at least one provider key is stored and answered a probe.
- `power_ups.telegram` — `true` once a test message actually arrived and the digest block is in the
  project's runner.
- `false` when the user removes that power-up. Nothing else, ever: no new top-level keys, no
  `phases.power_ups` (`power-ups` is not a phase and has no entry in `phases`), no phase value
  touched, and **no key, token, password or chat id in this file** — it is committed to the user's
  repository.

**Set a flag only after the verification that backs it.** A `true` written on the strength of a
pasted string is the same mistake as `gsc.connected` written from a screenshot.

**Every consumer treats the file as the truth and the flag as a hint.** If a flag is `true` and the
value is missing from `.seo-god/secrets.env` — a recreated file, a fresh clone, a manual edit — do the
free path, say plainly that the power-up is recorded in state but its key is not present, and let the
user decide whether to re-add it or flip the flag. Never fail a run over a stale flag, and never
invent a number because state claimed a key existed.

Write the file to disk immediately, then return to SKILL.md.

## 5. Hand back

Tell the user, briefly:

- Which power-up is now on, and the one thing it changed — real positions and volume, direct model
  answers, or a message on their phone.
- **For DataForSEO**: the per-run cap in force and where to change it, the balance floor, where the
  ledger lives, and — if they chose Level 2 — that opening a project dashboard page can itself spend
  money and that no cap inside OpenSEO will stop it.
- **For LLM keys**: the models and mode recorded today, that the numbers from here on are labelled
  `[mode: direct-model]` and are not comparable to the proxy days as a trend, and that a provider-side
  spend limit is worth the minute it takes.
- **For Telegram**: that the digest starts with the next scheduled run, that **no message means the
  run did not finish** — the digest never reports a failure, SKILL.md's 48h warning does — and that
  re-installing the schedule removes the block (section 3.5).
- That every one of them is reversible in a minute, and that the free path keeps working if they turn
  it off.
