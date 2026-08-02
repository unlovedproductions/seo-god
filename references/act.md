# Act — the daily loop: regressions, quick wins, one page

Goal: read today's measurements, fix what regressed, improve two or three pages that already
almost rank, add at most one page the data actually asks for, and leave a dated readout behind.
Small and verified, every day — that is the whole method.

`act` is not a phase. It writes **no** phase state: there is no `phases.act`, and it never sets
`phases.audit` or `phases.measure` itself. The one key it may ever add to `seo-god.json` is
`build_cmd`, and only on the attended path (section 2) — that is a stored answer to a question,
not phase state.

Everything happens in the USER's project directory — the current working directory. Never edit
anything inside the skill folder. `.seo-god/` must already be gitignored before anything is
written into it; confirm the line is in the project `.gitignore` first.

Order of operations, every run, in this order: **inputs → may we edit? → regressions → quick wins
→ content gap → readout.** Never reorder it. A quick win is worth nothing on a site that broke
yesterday, and a new page is worth nothing on a site with a broken one.

## The hard laws — they outrank everything else in this file

1. **No fabricated claims, stats, or reviews on generated pages.** No invented numbers, prices,
   benchmarks, dates, customer counts, quotes or testimonials — not as placeholders, not as
   "examples", not rounded from a guess. Every factual sentence you publish must trace to the
   user's own site, repository, or product. If answering a query truthfully would require a fact
   you do not have, you do not publish the page.
2. **No doorway pages.** A doorway page exists to catch a query and shunt the reader somewhere
   else, or is one of a set of near-identical pages differing only by a keyword, city, or product
   name. If a page would differ from an existing page only in its keywords, improve the existing
   page instead. Never generate a page set from a keyword list.
3. **One new page per run, maximum.** This loop ships at most one new page per run even when ten
   gaps look obvious. The nine others are tomorrow's runs. A daily loop that publishes in bulk is
   the thing every search engine is built to catch.
4. **Never invent data the snapshot does not contain.** Report only fields the snapshot actually
   carries, per its source. `null` positions and `available:false` / `measured:false` flags mean
   **not measured** — never zero, never "unranked", never a large placeholder number. A number you
   did not read out of a file does not go in the readout.

If anything below appears to conflict with a law, the law wins. Say so in the readout and stop.
SKILL.md's hard rules outrank even these.

## Attended or unattended — decide this first, it changes several branches

- Routed here by **SKILL.md step 3** (the `daily` argument, i.e. `claude -p "/seo-god daily"`) →
  **unattended**. Nobody is watching. Ask **zero** questions: every branch in this file has a
  defined no-question path, and taking it is the correct behaviour, not a failure.
- Routed here by SKILL.md step 4 or the step 6 menu (a human asked for `act`) → **attended**. You
  may ask at most the two questions section 2 defines — the `build_cmd` question, and audit.md
  section 2's follow-up when the gate is already red on the untouched tree. Nothing else in this
  file asks anything.
- Cannot tell → treat the run as **unattended**.

**A `claude -p` invocation is never attended, whichever step routed you.** Attended means an
interactive session with a human who can answer — not merely that the request named a phase. A
headless `claude -p "/seo-god act"` arrives through SKILL.md step 4 and is still unattended.

Degrade, never refuse. Missing OpenSEO, missing GSC, missing build gate: do what the available
data supports, name exactly what was missing in the readout, and fabricate none of the rest.

## 1. Inputs — state, today's snapshot, the diff

### 1.1 State

Read `seo-god.json` from the current working directory. You need `site_url`, `openseo.url` (use
that address, never a hardcoded `localhost`), `build_cmd` (may be absent), `gsc.connected`,
`keywords`, `phases.setup` and `openseo.status`. Treat `openseo.status` as a hint only — 1.3
asks the container itself, because a container that died overnight leaves `"running"` in state
and a stale flag is not a reason to refuse a run.

- **File missing, unparseable, or `version` is not `1`** → do not guess and do not overwrite it.
  Unattended: write the readout saying exactly that and stop. Attended: hand back to SKILL.md.
- **`phases.setup` is not `"done"`** → there is nothing measured to act on. Write the readout
  saying setup is incomplete, and stop. Do not run setup from here; one phase per invocation.

### 1.2 Resolve the two output directories once

```
dist/seo/snapshots/<YYYY-MM-DD>.json      today's snapshot (measure.md's contract)
dist/seo/readouts/<YYYY-MM-DD>.md         this run's readout
```

`<YYYY-MM-DD>` is today's **local** date — the day a scheduled run fires. Apply the gitignore
guard from `references/audit.md` section 7: when the project uses git and `git check-ignore -q
dist/seo` exits 0, both paths move to the repository root as `seo/snapshots/…` and
`seo/readouts/…`. Outside a repository that command exits **128**, which is not "ignored" — with
no git, skip the check and use the `dist/seo/` paths. Resolve this **once** and use the same
answer for reading the snapshot and writing the readout; measure.md resolved it the same way, so
a different answer here means you are reading the wrong history.

### 1.3 Today's snapshot

- **Today's file exists** → use it. (It may have been written by a MEASURE run earlier today.)
- **Missing, and OpenSEO answers** → capture it now. Ask the container first: a single request to
  `<openseo.url>/api/health`, expecting 200. The shell rule in `references/setup.md` step 5 governs
  that request and every request under it — `curl.exe` on Windows PowerShell, the whole command on
  one line, `NUL` in place of `/dev/null` — and no request in this loop ever inlines JSON into a
  curl command. On a 200, write today's snapshot by following `references/measure.md` **sections
  5.1 through 5.5 exactly as written**: its call pattern, its truncation rules, its issue-type
  vocabulary.

  Three parts of that file are **not** yours to run: section 3 (the interactive Search Console
  walkthrough — read `gsc.connected` as it stands and let 5.4 do the rest), section 4 (the
  keyword agreement — an absent or empty `keywords` means `"ranks": []`, and the readout says
  plainly that nothing is tracked), and the `phases.measure` writes in sections 1 and 7. Leaving
  `phases.measure` at `"in_progress"` would make SKILL.md's resume rule hijack the user's next
  interactive session into a MEASURE resume it never asked for. Borrow the procedure; leave the
  phase key exactly as you found it.

  Three of its branches would otherwise stop an unattended run:

  - **5.2 has to run a fresh crawl** — `references/audit.md` section 4 asks the user how many
    pages the site has, and on the daily path nobody answers: take the newest snapshot's
    `crawl.pages`, pass roughly double it as `maxPages` (clamped to the tool's allowed 10-10000),
    and with no previous snapshot pass 500 — then say in the readout which number you used and why.
  - **The crawl stalls** — audit.md section 4 asks the user whether to keep waiting when
    `pagesCrawled` stops advancing for 10 minutes while `status` is still `"running"`. Unattended,
    that stall **is** "cannot complete": stop polling, write no snapshot, degrade to the newest
    snapshot on disk exactly as the unreachable branch below does, and name the stall and the page
    count it reached in the readout. Do not keep waiting, and do not spin.
  - **5.2 cannot get a completed crawl at all** — its rule stands, write no snapshot, and this
    loop falls through to the degrade below exactly as if OpenSEO were unreachable.

  **None of the three ends the run.** measure.md stops its own phase on these branches; this loop
  does not stop, it degrades — it always reaches section 6 and writes a readout. A run that ends
  with no readout at all is indistinguishable from a scheduler that never fired, which is the one
  failure the missed-run check in SKILL.md cannot tell you anything useful about.
- **Missing, and OpenSEO is unreachable** → degrade. Fall back to the newest snapshot on disk,
  and treat everything after its `date` as unknown. The readout names the failure verbatim and
  the snapshot's date, and never presents a stale file as today's.
- **No snapshot on disk at all** → there is nothing measured to act on. Make no edits. Write the
  readout saying exactly that, and point at MEASURE. This is a complete, honest run.

### 1.4 The diff

`references/measure.md` section 6 **defines** the review: regressions first (rank drops, new
error-severity issues, GSC clicks week over week), then quick wins in positions 4-15 with their
source-split fields, then new queries. Run it against today's snapshot and the newest snapshot
whose `date` is before today's, and consume what it reports.

Do not restate, re-derive or re-tune its thresholds here — one definition, in one file. Two
things travel with the report and must survive into everything below:

- Every "not measured" line stays "not measured", in those words, all the way to the readout.
- When you degraded in 1.3, the comparison is between two past snapshots. Label it with **both**
  dates and the word `stale`. A stale diff reported as today's is the lie this whole loop exists
  to avoid.

## 2. May this run edit the repo?

Editing is gated on `build_cmd` in `seo-god.json`. `references/audit.md` section 2 owns the rules;
this section only says what a daily run does with each answer.

- **`build_cmd` present and non-empty** → edits allowed, gated by it.
- **`build_cmd` is `"none"`** → edits allowed, but you never get to say "fixed". Every edit is
  reported as **edited, unverified**, and the readout states plainly that no build gate exists.
  Do not invent a substitute gate.
- **`build_cmd` absent, attended run** → ask once, exactly as audit.md section 2 asks, run it on
  the untouched tree, store it in `seo-god.json` (read, modify, write the whole object, preserving
  every key you do not recognise, keeping `version: 1`), then proceed.
- **`build_cmd` absent, unattended run** → **skip every repo edit this run.** No regression fixes,
  no quick-win edits, no new page. Do the read-only half — snapshot, diff, readout — and make it
  the readout's first line after the heading: `Repo edits skipped: no build_cmd in seo-god.json
  and nobody to ask. Run /seo-god once to set it.` Never edit behind an imagined gate, and never
  guess a build command from the presence of a `package.json`.

**Run `build_cmd` once on the untouched tree before the first edit of the run.** A gate that is
already red can never prove anything. If it fails on the clean tree: unattended, make no edits
this run and put the failure verbatim in the readout as pre-existing; attended, show the user the
output and follow audit.md section 2.

**Establish the undo before the first edit**, per audit.md's "Before the first edit" subsection —
the `git status --porcelain` precondition, the plain statement when there is no git, and the run
stamp captured once and reused by every backup path in this run. One amendment for the unattended
path, where audit.md's "get the user's explicit go-ahead" has nobody to ask: **a file that already
has uncommitted changes is skipped, not touched.** Drop that item from the run and name the file
in the readout. Their in-flight edits are never yours to restore over.

Then **edit exactly per audit.md's fix loop, items 1-8.** Each line below is a pointer to the item
you must go and read, quoted by its opening words — not a summary to work from:

1. *"Select."* — one issue type, or one page, per batch.
2. *"Snapshot, and record two lists."* — snapshotted and created, under
   `.seo-god/backup/<run-stamp>/batch-<n>/`, verified before the batch's first edit.
3. *"Edit, then run `build_cmd`."*
4. *"Exit 0 → the batch is done."* — record each issue with its `issueType`, URL and files changed.
5. *"Non-zero → the batch is not done."* — including its three-attempt cap.
6. *"Restore = both lists, this batch only, this run's stamp only."*
7. *"Then run `build_cmd` once more"* — confirm green, and drop only that batch from the ledger.
8. *"If `build_cmd` is still red after a correct restore, stop the phase."*

That file is the editing discipline for this loop; it is not restated here and it is not
reinvented here. If its item 8 stops you on a still-red gate, **the run ends there**: no quick
wins, no new page, and the readout carries the files you deleted and restored plus the persisting
error verbatim. Item 8 also leaves `phases.audit` at `"in_progress"` — that clause belongs to the
AUDIT phase and not to this one. A daily run still writes no phase state, ever.

Two standing rules for every edit below: change only what the item requires, and **never commit
the user's repository.** The readout lists the changed files; committing is theirs.

## 3. Regressions first

Work the regression section of the diff, in the order measure.md section 6 reports it. Nothing in
sections 4 or 5 starts until this section is finished or honestly stopped.

**New error-severity crawl issues.** Each carries OpenSEO's hyphenated `type` verbatim —
`missing-title`, `broken-internal-link`, `server-error`, `blocked-page`, `redirect-loop`,
`noindex-page`, `thin-content` and the rest — and the URLs that newly appeared. Match those
strings literally, hyphens included. Triage and fix them exactly as `references/audit.md` section
6 does: its five classes in order, its repo-fixable test (take a literal string from the row — the
current title, the broken `href`, the URL path — grep the working tree, follow it to the file that
emits it), and its list of things that are structurally not repo-fixable (server and CDN config,
WAF rules, DNS, hosted-CMS pages, third-party embeds).

Class 1 orders by money page, and audit.md section 5 asks the user which those are. On the daily
path nobody answers, so take its own documented fallback — the pages at crawl depth 0-1 with the
most internal links pointing at them — and say in the readout that the ranking is the link-graph
proxy, not the user's answer. Never label a page a money page on a hunch.

Class 3 carries the same trap: audit.md tells you to ask when it is not obvious whether a
`noindex-page` is a mistake or deliberate. Unattended there is nobody to ask, so **an ambiguous or
long-standing `noindex` is never removed.** Report it in the readout with its URL and leave it
alone. Only a `noindex` that today's diff shows as newly appeared on a page the site clearly wants
ranked is a regression you may act on. De-indexing a page the user deliberately hid — a staging
route, a thank-you page, a paid-only area — is the most expensive mistake in this file, and it is
invisible until traffic arrives somewhere it should not.

- **Found the source** → fix it there, in a batch, behind the gate.
- **Not found, or not repo-fixable** → it is not this loop's to fix. Name it in the readout with
  its type and URL. Do not guess at a plausible file and do not create a file hoping it overrides
  something. The durable punch list belongs to the AUDIT phase; do not rewrite it from here.
- **The repo already carries the fix** → the crawl predates it. Record "already fixed in the
  repo, awaiting re-crawl" and edit nothing. Read the current source before every edit; a snapshot
  is a photograph of the site, not of the working tree.
- **The current value looks deliberate and different from the snapshot's** → a human changed it
  after the crawl. Leave it alone and say so.

**Rank drops.** On the free path every `ranks[].position` is `null`, so this line reads *"Rank
movement: not measured — no rank tracker configured"* and there is nothing to act on. Where a
tracker did measure a real drop, act only on what the data shows: check the losing URL in today's
crawl for an error-severity issue, a `noindex-page`, a `redirect-chain`, a `blocked-page` or a
4xx, and fix that. If the page is clean in the data, say the drop is unexplained by the data. You
have no ranking-algorithm evidence and you never narrate one.

**GSC clicks down week over week.** No edit fixes this directly. Report it with the numbers from
the diff, and check whether new error-severity issues on the highest-impression pages line up
with it. If they do not, say the cause is not visible in this data rather than assigning one.

## 4. Quick wins — two to three pages, positions 4 to 15

The diff's quick-wins list is already sorted and already source-split. Take the top **two or
three** rows and stop; a fourth quick win is tomorrow's run.

**Report only the fields the row's source has.** GSC-sourced rows carry `query`, `position`,
`impressions` and the ranking page. Rank-tracker rows carry `keyword`, `position` and `url` and
**no impressions** — that field does not exist in `ranks[]`, so it is never printed, never
estimated, and never borrowed from the other source.

For each chosen row, **improve the page that row names** — the GSC ranking page, or the tracker
row's `url`. Never a new page, never a near-duplicate: a page in position 4-15 already has the
ranking, and splitting it across two pages is how you lose it. If you cannot find that page's
source in the repository, skip the row, say so, and take the next one.

Four moves per page, all four in one batch, gated:

1. **Title, keyword-led.** Read the current title from the source (or from `get_audit_pages`)
   before you touch it. Put the words the person actually searched at the front, keep it truthful
   and readable, keep it near 60 characters, and change nothing else about the page's head.
2. **A 40-70 word TL;DR answer block at the top.** First content element after the H1, before any
   preamble, marketing or table of contents. Its first sentence answers the query outright; the
   rest qualifies it. Count the words — under 40 is not an answer, over 70 is not a TL;DR. Every
   fact in it comes from the page or the repository (hard law 1).
3. **Question-shaped FAQ entries.** Two to four, each heading phrased as the question a person
   types, each answer two to four sentences, every answer drawn from what the page already
   documents. If the site already emits FAQ structured data, add to that mechanism rather than
   hand-rolling a second one — and never mark up an answer that is not visible on the page.
4. **Internal links from related pages.** One to three links **from** existing pages that
   genuinely cover the topic **to** this page — the direction matters; this is about the target
   page's inbound links. Anchor text is the words a reader would use, placed inside body copy.
   Never add a link from an unrelated page, and never create a page of links: that is hard law 2.

Record, per page: the query or keyword, its position, its impressions **when the source is GSC**,
the URL, and which of the four moves you made.

## 5. Content gaps — at most one new page

A new page is the last thing this loop does and the easiest one to get wrong. Three tests, all of
which must pass, or you write nothing:

1. **The demand is in the data.** A `gsc.top_queries` row with impressions the site has no page
   for, a row from the diff's new-queries section, or a tracked keyword whose intent no existing
   page covers. You will quote this row in the readout, so it must be a row you actually read.
2. **No existing page covers it.** Check the crawl's pages and the repository. If one does, that
   is a quick win (section 4) and not a new page — hard law 2.
3. **You can answer it truthfully.** From the user's own site, repository and product. If the
   honest answer needs a number, price, benchmark, date or testimonial you do not have, **do not
   write the page**; say so in the readout and move on. Hard law 1 is not negotiable for content
   that will be published under the user's name.

**No demand data means no new page.** With `gsc.available: false` and every `ranks[].position`
`null`, this loop has no evidence of what anyone searches for — the readout line is *"No new
page: no demand data (GSC not measured, no rank tracker)"* and the run ends after section 4.
Inventing a topic here is exactly the failure hard law 4 names.

The page, when all three tests pass — answer-first, in this order:

- **H1**: the question or topic in the words the data showed, not a slogan.
- **TL;DR**: 40-70 words answering it immediately, same rules as section 4 move 2.
- **Numbered steps**: the actual procedure, in order, each step something a reader can do.
- **FAQs**: question-shaped, same rules as section 4 move 3.
- **Links both ways**: one link out to the most relevant existing page, and one link in from a
  relevant existing page — a page nothing links to is an `orphan-page` in tomorrow's crawl.

Put it where the site's other content lives and follow that stack's conventions exactly — same
directory, same front matter or route file, same sitemap and navigation registration. A page the
site does not know how to render is not a page: if you cannot work out from the repository how
this site publishes content, write nothing and say so in the readout rather than leaving a stray
file behind. It is a **created** file, so it goes on the batch's created list in audit.md's fix
loop and is deleted by that item's restore if the batch fails its gate.

One page. Not one plus a variant, not one per keyword. If two gaps look worth it, the second is
tomorrow's — hard law 3.

## 6. The readout

Append a dated section to `dist/seo/readouts/<YYYY-MM-DD>.md` (or the `seo/readouts/` fallback
resolved in 1.2). Read the file first if it exists and append — a second run on the same day adds
a section, it does not overwrite the first. Write it with your Write tool, never with shell
redirection: quoting differs between PowerShell and POSIX shells and a mangled readout is a
silently corrupted record.

**Write it after your final `build_cmd` run.** Some build commands wipe `dist/` before rebuilding,
and that would delete the readout you just wrote (audit.md section 7).

**At most 15 lines including the heading.** What was done, why, the numbers, what is next. Drop
lines that do not apply — but never drop a "not measured" line, because that is the line a reader
would otherwise fill in with an assumption. When the lines you must write will not fit in 15,
merge the "not measured" lines into one and drop optional ones; never drop a not-measured fact to
make the cap. If merging still does not fit, **go over 15 lines rather than lose a fact** — the cap
is a discipline, the honesty rule is not negotiable. Shape:

```
## 2026-08-01 05:12 — daily loop

Snapshot: dist/seo/snapshots/2026-08-01.json (captured this run) · diff vs 2026-07-31
Regressions: 2 — server-error /pricing (fixed, gate passed); missing-title /blog/x (not repo-fixable: CMS)
Rank movement: not measured — no rank tracker configured
GSC: 412 clicks / 9,830 impressions (28 days, window ends ~3 days back)
Quick wins: "how to cancel" pos 7, 1,240 impr -> /help/cancel (title, TL;DR, 3 FAQs, 2 inbound links)
Quick wins: "refund policy" pos 11, 640 impr -> /help/refunds (title, TL;DR)
New page: /guides/refund-timeline — evidence: GSC query "how long do refunds take", 880 impr, pos 14
Gate: npm run build, exit 0 · 6 files changed, uncommitted
Next: connect Search Console for query data, or re-crawl to confirm the /pricing fix
```

Rules the shape does not carry on its own: quote the evidence row for a new page verbatim from
the snapshot; report a count only if you read it out of a file; say **edited, unverified** for
every edit made under `build_cmd: "none"`, with the plain statement that no build gate existed;
and name every input that was missing, in one line each, using the wording in the table below.

**A run with nothing to do is a successful run.** No regressions, nothing in positions 4-15, no
demand data for a page — write the readout saying so and stop. Never invent an edit to make the
readout look busy; a manufactured change is a real risk taken against a real site.

## 7. Finish

- Write **no** phase state. There is no `phases.act`, and this loop never sets `phases.audit` or
  `phases.measure` — not directly, and not as a side effect of borrowing measure.md's procedure.
- Do not commit. The readout lists the changed files for the user to review.
- The run marker `.seo-god/last-run.json` belongs to the daily runner in
  `references/schedule.md`; this file does not write it.
- Unattended runs end here, silently, with the readout as the only output. Attended runs print
  the same readout to the user and point at whichever phase the "next" line named.

### The degrade table — what an unattended run does when something is missing

| Missing | What the loop still does | What the readout must say |
| --- | --- | --- |
| `phases.setup` not `"done"` | readout only, no edits | setup incomplete, run `/seo-god` |
| OpenSEO unreachable, today's snapshot absent | acts on the newest snapshot on disk | the failure verbatim, that snapshot's date, and `stale` on the diff |
| crawl stalls — no progress for 10 minutes | stops polling, writes no snapshot, acts on the newest on disk | the stall, the page count it reached, and `stale` on the diff |
| no snapshot on disk at all | readout only, no edits | nothing measured to act on; run MEASURE |
| `build_cmd` absent, unattended | snapshot + diff + readout, zero edits | repo edits skipped, no `build_cmd`, nobody to ask |
| `build_cmd` is `"none"` | edits, never verified | **edited, unverified** — no build gate existed |
| `build_cmd` red on the untouched tree | no edits this run | the error verbatim, marked pre-existing |
| `build_cmd` present but the harness denied running it | no edits this run | `Gate not run: the build command is not permitted in an unattended session — see references/schedule.md §2.1` |
| crawl completed but fetched nothing — 0 pages, or every page `fetchClass: "error"` | no snapshot, no edits; acts on the newest snapshot on disk | that the crawl reached no pages so nothing was audited, that snapshot's date, and `stale` on the diff |
| a file to edit has uncommitted changes | skips that item | which file, and that it was left to the user |
| `gsc.available: false` | crawl regressions; quick wins and page evidence from tracker rows only | `GSC: not measured` |
| `gsc.available: false` **and** every `ranks[].position` `null` | no quick wins and **no new page** — no demand data exists at all | `No new page: no demand data (GSC not measured, no rank tracker)` |
| every `ranks[].position` is `null` | no rank-drop regressions | `Rank movement: not measured — no rank tracker configured` |
| `ai_visibility.measured: false` | nothing — it belongs to `references/ai-visibility.md` | `AI visibility: not measured`, if mentioned at all |

Every cell above is a complete, honest run. None of them is a reason to refuse, and none of them
is a reason to fill the gap with a number.
