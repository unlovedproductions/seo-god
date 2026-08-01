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

Setup deliberately does not store the OpenSEO project id, so resolve it every run: call
`list_projects` (call pattern in step 3) and match the host of `site_url` against each project's
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
to say "fixed": every edit is reported as **edited, unverified**, listed separately in the step 7
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
version of the skill is written against these four, which are registered by OpenSEO's MCP server:

| Tool | What it does | Key arguments |
| --- | --- | --- |
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

Then poll `get_audit_status` every 10 seconds. `result.structuredContent.status` carries `status`,
`currentPhase`, `pagesCrawled`, `pagesTotal` and the Lighthouse counters. `status` is exactly one of:

- `"running"` — keep polling. Report progress to the user roughly every minute; a real crawl takes
  minutes, and page count is the honest signal of how long is left.
- `"completed"` — go to step 5.
- `"failed"` — report the status verbatim, leave `phases.audit` at `"in_progress"`, and stop.

If `pagesCrawled` stops advancing for 10 minutes while `status` is still `"running"`, say so and ask
the user whether to keep waiting; do not silently spin.

## 5. Read the issues

Call `get_audit_issues` with `projectId` and your `auditId`. The reply gives you two things:

- `result.structuredContent.summary` — `{ issueType, title, severity, count }` per type, **complete
  counts for the whole audit**. These are your totals.
- `result.structuredContent.issues` — the rows: `{ severity, issueType, title, url, details,
  howToFix }`. `severity` is `"critical"`, `"warning"` or `"info"`. `details` is issue-specific;
  read it, do not assume its shape. `howToFix` is OpenSEO's own remediation text for that issue
  type — follow it rather than inventing your own fix.

**The rows are truncated, the summary is not.** `limit` defaults to 200 and caps at 1000, and the
rows are sorted severity-first so truncation drops `info` before `critical`. When `summary` shows
more of a type than you received rows for, re-call with `issueType` set to that one type to page
through the rest. Never report a count from the row array — take counts from `summary`.

Call `get_audit_pages` when you need the current state of a page you are about to edit: it returns
status code, title, description, word count, indexability, crawl depth and link counts per URL.
You cannot write a replacement title without seeing the one that is there.

**Pages the crawler could not read are not clean pages.** `get_audit_pages` with
`fetchClass: "blocked"` lists pages that answered with a bot challenge or an access denial, and
they also appear as `blocked-page` issues. They were not audited. Say so in the summary, count them
separately from passes, and put them on the punch list with the `howToFix` text OpenSEO returns
(it names allowlisting the audit crawler's user agent in the WAF).

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

### The fix loop

1. Take ONE issue type within the current class — for example every `missing-title` — and fix up to
   about ten related occurrences with the Edit tool. One template usually fixes many rows at once.
2. Run `build_cmd`.
3. Exit 0 → the batch is done. Record each issue as fixed, with its `issueType`, URL, and the files
   you changed.
4. Non-zero → the batch is **not** done. Read the output, fix the cause, and run it again. If you
   cannot get it green, revert exactly the files this batch touched (`git checkout -- <files>`),
   record those issues as not fixed and why, and move on. Never leave the tree broken to move
   faster, and never count a reverted batch as fixed.

Rules for the edits themselves: change only what the issue requires; do not reformat surrounding
code, rename things, or "improve" anything you were not sent to fix. Write real titles and
descriptions from the page's actual content — read the page source before you write its title. Do
not commit the user's repository unless they ask; when the phase ends, show them `git diff --stat`
so they can review and commit it themselves.

## 7. Write the punch list

Everything you did not fix goes in one file the user can act on or hand to whoever administers
their server or CMS:

```
dist/seo/audit-punchlist-<YYYY-MM-DD>.md
```

This lives in their repository on purpose — it is a durable deliverable, not session scratch, and
`.seo-god/` is never committed. Two guards, both required:

- **Write it last, after your final `build_cmd` run.** Some build commands wipe `dist/` before
  rebuilding, and that would delete the punch list you just wrote.
- **Check it is not ignored:** `git check-ignore -q dist/seo` succeeds (exit 0) when `dist/` is
  gitignored, which is common. If it is, write to `seo/audit-punchlist-<YYYY-MM-DD>.md` at the
  repository root instead and tell the user why. A punch list that git silently drops is worse than
  no punch list.

Order the items by the same five classes. Each item carries: the `issueType` and the affected
URL(s), what breaks because of it, the exact change to make (start from OpenSEO's `howToFix` text),
and who has to make it — server admin, CMS editor, hosting provider. An item that says "improve
performance" is not a punch list item; "TTFB on /pricing is 1.9s, from `slow-response` — enable
caching at the origin or move it off the shared tier" is.

Nothing that you could have fixed in the repo goes on this list to avoid the work, and nothing on
this list goes into the fixed count.

## 8. Finish

Set `phases.audit` to `"done"` in `seo-god.json` — read, modify, write the whole object, preserving
every key you do not recognise, keeping `version: 1` — and write it to disk immediately.

Then give the user a short summary, in this order and with no embellishment:

- Pages crawled, and how many were **blocked** and therefore not audited.
- Total issues found, from `summary`.
- **Fixed: N** — broken down by the five classes. Every one of these passed `build_cmd`.
- **Punted: M** — with the punch list path.
- Anything you could not fix and could not punt cleanly, named.
- `git diff --stat` of the changes, uncommitted, for them to review.
- When `build_cmd` is `"none"`: the edited-but-unverified list, and the plain statement that no
  build gate existed for this run.

If fixed plus punted does not equal the total, say so and explain the gap rather than rounding it
away. Then point at what is next: MEASURE.
