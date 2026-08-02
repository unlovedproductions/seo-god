# Audit — crawl, triage by impact, verified fixes

Goal: OpenSEO crawls the user's site, you triage every issue in the fixed priority order below,
you FIX the ones that live in their repository behind their own build gate, you write everything
you cannot fix into a punch list, and `phases.audit` ends at `"done"`.

Everything happens in the USER's project directory — the current working directory. Never edit
anything inside the skill folder.

Honesty rule for this whole phase:

> **Never mark an issue fixed without the build/typecheck gate passing.**

Not "it looks right", not "the edit applied cleanly". The gate exits 0, or the issue is not fixed.
This rule also runs downhill: an issue you did not touch is not fixed, a page the crawler could not
read is not clean, and a count you did not verify does not go in the summary.

## 1. Read state, resolve the project

Read `seo-god.json` from the current working directory. You need two values from it:

- `site_url` — the site to crawl.
- `openseo.url` — the base URL of the running container (it includes the port; do not assume 3001).

Set `phases.audit` to `"in_progress"` and write the file to disk now, preserving every key you do
not recognise. Doing it before the slow steps is what makes an interrupted audit resumable.

**Loop-breaker — check the host before you resolve anything.** If `site_url`'s host fails
`references/setup.md` section 2's public-reachability rule — `localhost`, an IP literal, a
`.local` / `.localhost` / `.internal` / `.test` / `.example`-class suffix, or any host with no
public suffix — say so and stop here, with setup's own two options: a public tunnel or a deployed
domain. Do **not** route back to `references/setup.md` for this: that file refuses the same host, so
routing back is an infinite loop with no error the user can act on.

Setup deliberately does not store the OpenSEO project id, so resolve it every run: call
`list_projects` (call pattern in section 3) and match the host of `site_url` against each project's
`domain`. No match means setup did not finish — go back to `references/setup.md`. Every audit tool
takes `projectId` and it is **required**; there is no "default project".

## 2. Get the build command — ask once, store as `build_cmd`

If `seo-god.json` already has a non-empty `build_cmd`, use it and do not ask again.

Otherwise ask, once: *"What single command builds or typechecks this project? I will run it after
every batch of fixes and treat a non-zero exit as 'not fixed'."* Give them the shape of a good
answer without guessing their stack — `npm run build`, `npx tsc --noEmit && npx eslint .`,
`pnpm build`, `hugo --minify`, `bundle exec jekyll build`, `cargo build`, `make build`. It must
exit non-zero when something is wrong; a command that always succeeds is not a gate.

**Run it once on the untouched tree before you edit anything.** A gate that is already red can
never prove anything, and you must know that a failure was pre-existing rather than yours. If it
fails on the clean tree, show the user the output and ask for a command that passes as-is, or for
permission to stop; do not start editing behind a broken gate.

Store the working command as `build_cmd` in `seo-god.json` (read, modify, write the whole object).

**If the project genuinely has no build or check step at all** — hand-written HTML, no toolchain —
ask for the closest thing they do run before shipping (a linter, a site generator, a validator).
Only if there is truly nothing, store `build_cmd: "none"`. Then there is no gate, so you do not get
to say "fixed": every edit is reported as **edited, unverified**, listed separately in the section 8
summary, and the summary states plainly that no build gate existed. Do not invent a substitute gate
and do not let the absence of one quietly become a pass.

## 3. The OpenSEO call pattern

OpenSEO's MCP server is stateless JSON-RPC over a single `POST <openseo.url>/mcp`. Under
`local_noauth` there is no token and no `initialize` handshake.

**Shell rule — read the shell rule in `references/setup.md` step 5 before your first request**
(`curl.exe` on Windows PowerShell, one line, `@file` JSON bodies). It governs every curl below.

Use this two-step form for every call, on every OS — it is the only form that arrives
byte-identical everywhere:

1. Write the JSON body to `.seo-god/mcp-body.json` with your Write tool. (`.seo-god/` must already
   be gitignored — setup does that; confirm the line is in `.gitignore` before writing into it.)
2. Send it:

```
curl -s -X POST <openseo.url>/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d "@.seo-god/mcp-body.json"
```

Only the body changes from call to call. Bodies are
`{"jsonrpc":"2.0","id":<n>,"method":"tools/call","params":{"name":"<tool>","arguments":{...}}}`.

**Discover the toolset first.** Send the discovery call — body
`{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}` — and read the names back. This
version of the skill is written against these five, which are registered by OpenSEO's MCP server:

| Tool | What it does | Key arguments |
| --- | --- | --- |
| `list_projects` | the registered projects, to resolve `projectId` (section 1) | none |
| `run_site_audit` | starts a crawl, returns immediately | `projectId`*, `url`*, `maxPages`, `runLighthouse` |
| `get_audit_status` | progress of a crawl | `projectId`*, `auditId` |
| `get_audit_issues` | the prioritized issue report | `projectId`*, `auditId`, `severity`, `issueType`, `limit` |
| `get_audit_pages` | per-page crawl facts | `projectId`*, `auditId`, `fetchClass`, `statusCode`, `urlContains`, `limit` |

`*` required. Omitting `auditId` means "the project's most recent audit". If `tools/list` does not
return one of these names, the user is on a different OpenSEO build: use the crawl/audit tools it
actually lists, read their `description` and `inputSchema` for the arguments, and say in your
summary which tools you used instead. Never call a name you have not seen in `tools/list`.

## 4. Crawl the site

Call `run_site_audit` with `projectId`, `url` set to `site_url`, and `maxPages` chosen for the site
— the default is 50, which is a sample, not an audit. Ask the user roughly how many pages the site
has and pass a `maxPages` that covers it (allowed range 10-10000; a self-hosted install is not
limited to the hosted free tier's 50). Leave `runLighthouse` at its default `true` — it is what
produces the performance data behind priority class 5.

Read `result.structuredContent.auditId` from the reply and keep it; pass it explicitly to every
later call so a concurrent audit cannot change what you are reading.

**If the reply has no `auditId`**, the audit did not start. OpenSEO returns a plain text message in
that case (for example "Audit capacity reached for this account") — report it verbatim, leave
`phases.audit` at `"in_progress"`, and stop. Do not poll for an audit that does not exist.

One of those replies is the bare token `CRAWL_TARGET_BLOCKED`. It reads like an internal error and
is not one: OpenSEO's crawler refused the target because it is not publicly reachable — loopback, a
private IP, or a private-use suffix. Decode it for the user instead of echoing the token, and give
them the two options from `references/setup.md` section 2 (a public tunnel, or a deployed domain).
Do not retry and do not route back into setup: nothing changes until the target does.

Then poll `get_audit_status` every 10 seconds. `result.structuredContent.status` carries `status`,
`currentPhase`, `pagesCrawled`, `pagesTotal` and the Lighthouse counters. `status` is exactly one of:

- `"running"` — keep polling. Report progress to the user roughly every minute; a real crawl takes
  minutes, and page count is the honest signal of how long is left.
- `"completed"` — the crawl finished, which is not the same as the crawl having read anything. Apply
  the not-an-audit check below, then go to section 5.
- `"failed"` — report the status verbatim, leave `phases.audit` at `"in_progress"`, and stop.

If `pagesCrawled` stops advancing for 10 minutes while `status` is still `"running"`, say so and ask
the user whether to keep waiting; do not silently spin.

**A crawl that fetched nothing is not an audit.** After `"completed"`, call `get_audit_pages` for
this audit before you read a single issue. If `pagesCrawled` is 0, or **every** returned page has
`fetchClass: "error"`, the crawler reached nothing — that is an absence of evidence, not evidence of
a clean site. Report it in the same words section 5 uses for blocked pages (those pages were not
audited), leave `phases.audit` at `"in_progress"`, write **no** snapshot, and stop. Never report "no
issues found" from this state: `references/measure.md` section 5.2 would persist `crawl.pages: 1,
issues: []` into the permanent snapshot history, and the next day's diff would then report every
genuine issue as resolved. This is not an exotic case — a DNS negative cache produced exactly it
(one page, `statusCode: 0`, `fetchClass: "error"`, 0.4 seconds) on the first end-to-end run.

**Lighthouse counters — `lighthouseFailed > 0` means that many pages have no performance data at
all.** The status carries `lighthouseTotal`, `lighthouseCompleted` and `lighthouseFailed`. Pages
whose Lighthouse run failed were not measured, exactly as blocked pages were not audited: "no
performance issues" and "performance was never measured" are different statements, and only the
second is true for them. Carry the counts into section 8. If `lighthouseCompleted` is 0, priority
class 5 has no data behind it at all — say so rather than reporting the class clean.

## 5. Read the issues

Call `get_audit_issues` with `projectId` and your `auditId`. The reply gives you two things:

- `result.structuredContent.summary` — `{ issueType, title, severity, count }` per type, **complete
  counts for the whole audit — but only on an UNFILTERED call.** `summary` is computed over whatever
  rows the call selected, so a call with `severity` or `issueType` set summarises only that slice.
  Take your totals from an unfiltered call, and never report a filtered `summary` as the audit total.
- `result.structuredContent.issues` — the rows: `{ severity, issueType, title, url, details,
  howToFix }`. `severity` is `"critical"`, `"warning"` or `"info"`. `details` is issue-specific;
  read it, do not assume its shape. `howToFix` is OpenSEO's own remediation text for that issue
  type — follow it rather than inventing your own fix.

**The rows are truncated, the summary is not.** `limit` defaults to 200 and caps at 1000, and the
rows are sorted severity-first so truncation drops `info` before `critical`. **There is no offset or
cursor** — you cannot page. To get more rows of one type, re-call with `issueType` set to that single
type, which re-queries and gives you up to `limit` rows of just that type. A type with more than 1000
occurrences cannot be fully enumerated: work the rows you have and take the count from `summary`.
Never report a count from the row array.

Call `get_audit_pages` when you need the current state of a page you are about to edit: it returns
status code, title, description, word count, indexability, crawl depth and link counts per URL.
You cannot write a replacement title without seeing the one that is there.

**`get_audit_pages` truncates the same way** — `limit` defaults to **100** (max 1000) — but it also
returns `result.structuredContent.total`, the true number of matching pages. Take every page count
from `total`, never from the length of the returned `pages` array.

**Pages the crawler could not read are not clean pages.** `get_audit_pages` with
`fetchClass: "blocked"` lists pages that answered with a bot challenge or an access denial, and
they also appear as `blocked-page` issues. They were not audited. Read the blocked count from that
call's `total` — with the default limit of 100 the array will under-report any site blocking more
than 100 pages, which is exactly the site you most need an honest number for. Say so in the summary,
count them separately from passes, and put them on the punch list with the `howToFix` text OpenSEO
returns (it names allowlisting the audit crawler's user agent in the WAF).

### Identify the money pages before you sort

Class 1 is about breakage **on money pages**, so you need to know which those are. Ask the user
once: *"Which pages actually make you money — pricing, signup, checkout, your top product or
service pages?"* If they do not want to answer, fall back to OpenSEO's own data: the pages at crawl
depth 0-1 with the most internal links pointing at them, from `get_audit_pages`. **State which of
the two you used.** Never label a page a money page on a hunch and never present the link-graph
proxy as if the user had confirmed it.

## 6. Triage in this order, then fix

Work the classes strictly in order. Finish class 1 across the whole site before starting class 2 —
do not interleave, and do not skip ahead to something easier. Within a class, order by severity
(`critical`, then `warning`, then `info`), then by whether the URL is a money page, then by count.

**1. Broken links / 4xx on money pages** — `broken-internal-link`, `broken-page` (4xx),
`server-error` (5xx), `redirect-loop`. Every one of these on a money page comes before everything
else in this file.

**2. Missing or duplicate titles + metas** — `missing-title`, `duplicate-title`,
`missing-meta-description`, `duplicate-meta-description`, then the length problems
`title-too-long`, `title-too-short`, `meta-description-too-long`, `meta-description-too-short`.

**3. Uncrawlable / noindex mistakes** — `noindex-page`, `blocked-page`, `canonical-conflict`,
`canonicalized-page`, `redirect-chain`, `orphan-page`, `no-outgoing-links`, `deep-page`. A
`noindex` that the user put there on purpose is not a mistake: check whether the page is one they
would ever want ranked before you remove anything, and ask if it is not obvious.

**4. Thin content** — `thin-content`, `duplicate-content`, `missing-h1`, `multiple-h1`,
`heading-order-skip`, `images-missing-alt`.

**5. Slow pages** — `slow-response` plus the Lighthouse performance findings from the crawl. Most
of this class is server, hosting or asset-pipeline work and lands on the punch list; fix only what
is genuinely in the repository (an unoptimised bundled image, a render-blocking tag in a template).

### Repo-fixable or punch list — decide by finding the source

An issue is repo-fixable only when you can point at the file that produces it. Take a literal
string from the audit row — the exact current title, the broken `href`, the URL path — and grep the
working tree for it. Follow it to the template, component, layout, config or content file that
emits it.

- **You found it** → fix it there.
- **You cannot find it** → it is not repo-fixable. Punch list. Do not guess at a plausible file,
  and do not create a new file hoping it overrides something.

Things that are structurally not repo-fixable, even when a file in the repo mentions them: server
and CDN configuration (redirects, headers, TTFB, 5xx origin errors), WAF and bot-protection rules,
DNS, pages authored in a hosted CMS, and third-party embeds. These go on the punch list with an
exact instruction, not a vague one.

### Before the first edit: establish the undo

You are about to change files behind a gate that can fail, so an undo has to exist before the first
edit, not after the first failure.

- **If the project uses git:** run `git status --porcelain`. If any file you are about to touch
  already has uncommitted changes, stop and get the user's explicit go-ahead first — those are
  their edits, not yours, and a restore would destroy them. A clean tree, or their go-ahead, is the
  precondition for editing.
- **If there is no git:** say so once, plainly — the per-batch snapshots below are the only undo
  that will exist for this run.
- **Capture a run stamp now** — the current **local** date-time as `YYYY-MM-DD-HHMM`. Local, not
  UTC, and the same clock the punch list uses in section 7: mixing the two splits one run's
  artifacts across two dates on any machine at a UTC offset. Every backup path in this
  run uses it, and every restore reads from it. Capture it once and reuse it: without it, a later
  run's batch 3 would overwrite this run's batch 3 backup and restore the wrong files.

### The fix loop

1. **Select.** Take ONE issue type within the current class — for example every `missing-title` — and
   choose up to about ten related occurrences to fix. One template usually fixes many rows at once.
   Selection only; do not edit anything yet.
2. **Snapshot, and record two lists.** For batch `<n>`, before any edit:
   - **Snapshotted** — every file that already exists and that you are about to change. Copy each to
     `.seo-god/backup/<run-stamp>/batch-<n>/<original-relative-path>`, preserving the relative path
     so restore is an unambiguous copy-back.
   - **Created** — every file that does not exist yet and that this batch will add. These have no
     snapshot; the list itself is what makes them undoable.

   Do the copy with your own file tools: **Read** the file and **Write** it to the backup path. Write
   creates missing parent directories, so a nested path like `src/app/blog/layout.tsx` works with no
   `mkdir` step and no shell branching between OSes — a shell copy is the wrong tool here (on Windows
   `Copy-Item` fails when the parent directory does not exist, and it fails quietly enough to leave
   you thinking you have an undo you do not have). **Verify each backup file exists before the first
   Edit of the batch.** A snapshot you did not confirm is not an undo.

   If the batch grows mid-way, add the new file to the right list — and snapshot it if it exists —
   *before* you touch it, never afterwards.
3. **Edit**, then run `build_cmd`.
4. Exit 0 → the batch is done. Record each issue as fixed, with its `issueType`, URL, and the files
   you changed.
5. Non-zero → the batch is **not** done. Read the output, fix the cause, run it again. **Give this at
   most three attempts.** After a third failed gate, stop trying to fix forward: restore, and put that
   issue type on the punch list with the build error as the reason — an issue that fights the gate
   three times is telling you it is not a mechanical fix.
6. **Restore = both lists, this batch only, this run's stamp only:**
   - **delete** every file on the batch's *created* list — your file tools cannot delete, so this
     is the one step that needs the shell: `rm` on macOS, Linux and Git Bash, `Remove-Item` on
     Windows PowerShell. Then confirm each one is gone with your file tools, and remove any
     directory the batch created once it is empty — then
   - **copy back** every file on its *snapshotted* list from
     `.seo-god/backup/<run-stamp>/batch-<n>/`.

   Done in that order the tree is pre-batch by construction. Copy-back alone is not a restore: it
   never removes a file the batch added, and a leftover new file can keep the build red or, worse,
   leave a stray page live on the site.
7. Then run `build_cmd` once more to confirm the tree is green again, and drop **only this batch's**
   issues from the fixed ledger.
8. **If `build_cmd` is still red after a correct restore, stop the phase.** Do not start another
   batch and do not paper over it. Report: exactly which files you deleted and restored, and the
   persisting error verbatim. Compare it against the clean-tree baseline — the `build_cmd` run on the
   untouched tree from section 2, before any edits. That is the reference point, and a break that
   survives a correct restore is very likely pre-existing rather than yours; say which you believe it
   is and why. Put the batch's issue type on
   the punch list, leave `phases.audit` at `"in_progress"` — **do not set it to `"done"`** — and
   claim nothing from that batch as fixed. Never exit this branch silently.

**Never restore with `git checkout -- <files>`.** That reverts to the last commit, not to the start
of this batch — so a red batch 3 touching a file that batch 1 already fixed and verified would
silently undo batch 1's work while the ledger still counts it as fixed. That is the honesty rule
broken by the tool meant to protect it. The two-list restore above cannot do this: it only ever
touches files this batch listed, so earlier batches survive by construction — and it works
identically in a project with no git at all.

Never leave the tree broken to move faster, and never count a restored batch as fixed. `.seo-god/`
is gitignored, so the snapshots never enter the user's repository; they are scratch for this run.

Rules for the edits themselves: change only what the issue requires; do not reformat surrounding
code, rename things, or "improve" anything you were not sent to fix. Write real titles and
descriptions from the page's actual content — read the page source before you write its title. Do
not commit the user's repository unless they ask; when the phase ends, show them the changed files
(section 8) so they can review and commit it themselves.

## 7. Write the punch list

Everything you did not fix goes in one file the user can act on or hand to whoever administers
their server or CMS:

```
dist/seo/audit-punchlist-<YYYY-MM-DD>.md
```

`<YYYY-MM-DD>` is today's **local** date — the same clock as section 6's run stamp, so one run's
artifacts always carry one date.

This lives in their repository on purpose — it is a durable deliverable, not session scratch, and
`.seo-god/` is never committed. Two guards, both required:

- **Write it last, after your final `build_cmd` run.** Some build commands wipe `dist/` before
  rebuilding, and that would delete the punch list you just wrote.
- **Check it is not ignored — only if the project uses git.** `git check-ignore -q dist/seo` exits 0
  when `dist/` is gitignored, which is common; if it is, write to
  `seo/audit-punchlist-<YYYY-MM-DD>.md` at the repository root instead and tell the user why. A punch
  list that git silently drops is worse than no punch list. Outside a repository this command exits
  **128**, which is not "ignored" — with no git, skip the check and use the `dist/seo/` path directly.
  Do not read a 128 as a signal to relocate.

Order the items by the same five classes. Each item carries: the `issueType` and the affected
URL(s), what breaks because of it, the exact change to make (start from OpenSEO's `howToFix` text),
and who has to make it — server admin, CMS editor, hosting provider. An item that says "improve
performance" is not a punch list item; "TTFB on /pricing is 1.9s, from `slow-response` — enable
caching at the origin or move it off the shared tier" is.

Nothing that you could have fixed in the repo goes on this list to avoid the work, and nothing on
this list goes into the fixed count.

## 8. Finish

You only reach this section by finishing the triage. If the fix loop stopped you on a still-red
gate after a restore, that branch owns the ending: `phases.audit` stays `"in_progress"` and nothing
below applies.

Set `phases.audit` to `"done"` in `seo-god.json` — read, modify, write the whole object, preserving
every key you do not recognise, keeping `version: 1` — and write it to disk immediately.

Then give the user a short summary, in this order and with no embellishment:

- Pages crawled, and how many were **blocked** and therefore not audited.
- **Performance: not assessed — N of M Lighthouse runs failed** — whenever `lighthouseFailed > 0`.
  Drop the line only when every Lighthouse run completed.
- Total issues found, from `summary`.
- **Fixed: N** — broken down by the five classes. Every one of these passed `build_cmd`.
- **Punted: M** — with the punch list path.
- Anything you could not fix and could not punt cleanly, named.
- The changed files, uncommitted, for them to review: `git status --short` when the project uses git
  — it lists untracked files too, so the punch list you just wrote shows up, which `git diff --stat`
  would miss. With no git, list the files from your fixed ledger instead.
- When `build_cmd` is `"none"`: the edited-but-unverified list, and the plain statement that no
  build gate existed for this run.

If fixed plus punted does not equal the total, say so and explain the gap rather than rounding it
away. Then point at what is next: MEASURE.
