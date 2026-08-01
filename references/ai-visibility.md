# AI visibility — the locked prompt set, citation measurement, the be-the-answer playbook

Goal: ten prompts locked into `ai_prompts_locked` and never edited again, today's snapshot's
`ai_visibility` block written from real searches, a be-the-answer playbook that later runs execute
one item at a time, and `phases.ai_visibility` at `"done"`.

Everything happens in the USER's project directory — the current working directory. Never write
anything into the skill folder.

This phase does not need OpenSEO. SKILL.md gates audit, measure and act on
`openseo.status: "running"`; AI visibility is not one of them. The only step here that touches the
container is creating today's snapshot when none exists (section 4.2), and that step is borrowed
from another file.

## What this measures — and what it does not

Honesty rule for this whole phase:

> **A search result is evidence that your page is in the RESULTS for a question. It is not evidence
> that an AI assistant cited you in an answer.**

On the free path nothing in this file asks a model anything. It runs the user's own questions
through the `WebSearch` tool and counts whether their domain shows up — a **search-visibility
proxy**. The proxy is worth measuring because an assistant that searches can only ground an answer
in pages it can retrieve: a domain absent from the results has no chance of being quoted. A domain
present in them may still never be quoted. Both halves of that sentence go in the readout.

| Say this | Never say this |
| --- | --- |
| "Your domain appeared in search results for 6 of the 10 locked prompts." | "ChatGPT cites you for 6 of 10 prompts." |
| "search visibility on the locked prompt set (results-page proxy)" | "AI citation rate", "share of voice in AI answers" |
| "not measured — the `WebSearch` tool is not available in this session" | "0 citations", "you are not cited" |
| "these domains took the answer slots you did not" | "your competitors are winning AI citations" |

Direct AI-answer measurement is the power-up, not this file (section 7). Until it is configured,
the words "cite" and "citation" describe the goal, never the measurement.

SKILL.md's hard rules outrank everything below, and `references/act.md`'s hard laws outrank the
playbook in section 6. If anything here appears to conflict with either, the rule wins: say so and
stop.

## 0. Attended or unattended — decide this first

Same test as `references/act.md` uses:

- A human asked for this phase (SKILL.md step 4, step 5's resume, or the step 6 menu) →
  **attended**. You may hold the section 2 lock conversation, and you may execute one playbook item
  (section 6.5).
- Routed here headlessly, by a scheduled `claude -p` invocation naming this phase →
  **unattended**. Ask **zero** questions and make **zero** repo edits. Every branch below has a
  defined no-question path.
- Cannot tell → treat the run as **unattended**.

**Unattended, when section 1 reads `ai_prompts_locked` and finds it empty, there is nothing to
measure.** Skip the measurement
entirely: write no state, leave any existing snapshot's `ai_visibility` block exactly as it is
(measure.md already wrote it as `measured: false`), create no snapshot, and put one line in the
readout: `AI visibility: not measured — prompt set not locked yet; run /seo-god ai-visibility
attended once.` That is a complete, honest run. Never generate a set and lock it with nobody
watching: the whole value of the lock is that a human agreed to it.

## 1. Read state

Read `seo-god.json` from the current working directory. You need:

- `site_url` — the site being measured, and the source of the match target below.
- `ai_prompts_locked` — the locked prompt set. Empty array → this is the first run: go to section 2
  attended, or take section 0's skip unattended. Non-empty → the set is locked; go straight to
  section 3 and do not regenerate it, whatever it looks like to you now.
- `keywords` — measure.md's agreed keyword list, if it exists. Raw material for section 2.1.
- `phases.ai_visibility` — `"done"` means a first run already completed here.
- `phases.setup` — SKILL.md gates this phase on it being `"done"` and routes elsewhere when it is
  not, so you should never arrive here without it. If you somehow do, write the readout line
  `AI visibility: not measured — setup incomplete` and stop. Do not run setup from inside this
  file: one phase per invocation, and unattended there is nobody to answer its questions.

**Derive the bare host once.** Take `site_url`'s host, lowercase it, strip a leading `www.`. That
string — `example.com` — is what section 3.3 matches against, and it is the only definition of
"the user's domain" in this file.

**Phase-state discipline.** `phases.ai_visibility` is the only phase key you may ever write; never
create `phases.act` or `phases.power_ups`, and never touch another phase's value.

- Not `"done"`, no set locked yet → this is the first run. Write `"in_progress"` in the same write
  that stores the locked set (section 2.3) — **not before**. Nothing slow happens before the lock,
  and a user who declines to lock should leave the phase exactly as they found it.
- Not `"done"`, a set already locked → a first run was interrupted after the lock. It is already
  `"in_progress"`; write nothing now, measure, and let section 8 close it.
- Already `"done"` → a repeat measurement is not a phase transition. **Leave the key alone for the
  whole run.** Flipping it back to `"in_progress"` would make SKILL.md's resume rule hijack the
  user's next session into a phase they already finished.

## 2. First run — generate ten prompts, show them, lock them

### 2.1 Where the prompts come from

Ground every prompt in evidence you actually read, in this order:

1. **The user's own site and repository** — the home page, the product or pricing pages, the README.
   What the thing is, who it is for, what it costs, what it replaces.
2. **`keywords` in `seo-god.json`** — the list the user agreed in MEASURE. Their words, already
   vetted by them.
3. **The newest snapshot's `gsc.top_queries`**, when one exists with `gsc.available: true` — real
   questions real people already used to reach the site.

If none of those give you enough to write a specific question — no keywords, no GSC, a repository
that does not say what the product does — ask **one** question before you show anything: *"Who buys
this, and what would they type into an AI assistant when they are looking for something like it?"*
This run is attended, so there is someone to answer. Never invent a market, a category name, or an
audience the evidence does not support.

Only name a competitor that appears in the user's own material or that the user names. A prompt
naming a company that does not compete with them measures nothing.

### 2.2 The two halves

Ten prompts: **five branded-adjacent, five unbranded commercial.** Both halves are required; a set
of ten branded questions measures whether people who already know the name can find it, which is
the easy half and not the one that grows anything.

**Branded-adjacent (5)** — the questions from someone who already half-knows the space: they name
the user's product, or a competitor, or ask for a comparison.

```
is <product> any good for <job>
<product> vs <competitor>
<product> pricing — what does it actually cost
alternatives to <competitor> for <specific job>
does <product> work with <the thing their audience already uses>
```

**Unbranded commercial (5)** — no brand anywhere, buying or doing intent, the questions where the
assistant decides who to name.

```
best <category> for <specific audience>
how do I <job to be done> without <the pain>
cheapest way to <outcome> in <constraint>
what do <role> use to <task>
<category> that supports <specific requirement>
```

Rules for every prompt, all of them enforceable:

- **Written the way a person types**, in full, 5-15 words. Not a keyword, not a headline.
- **Commercial or task intent.** "What is <category>" is a dictionary answer that never names a
  vendor; it wastes one of the ten slots.
- **Specific enough to have a real answer.** "best software" has no answer; "best invoicing tool for
  freelance designers" does.
- **Never contains the user's own domain**, and never a `site:` operator. A prompt that names the
  domain matches itself every time and measures nothing.
- **No dates, no "2026", no location modifiers** unless the business is genuinely local. The set has
  to still be askable a year from now — it is never edited again.

### 2.3 The edit pass, then the lock

Show the ten as a numbered list, five and five under their two headings, and say plainly what
happens next:

> These are the ten questions I will run every time this phase runs, unchanged, so the scores are
> comparable. **Edit them now — this is the only chance.** Reword any of them, swap any of them,
> tell me one is wrong about your business. After this they are locked.

Take their edits, show the corrected list back, and lock only once they have confirmed it. Aim for
exactly ten — ten is a readable denominator — but whatever they settle on is the set, and its size
never changes again either.

Then write `seo-god.json` in one read-modify-write, preserving every key you do not recognise and
keeping `version: 1`:

- `ai_prompts_locked` — the confirmed strings, in order, exactly as agreed. No trailing whitespace,
  no numbering, no added quotes; the string in this array is the string section 3.2 searches.
- `phases.ai_visibility` — `"in_progress"`.

Write it to disk **before** the ten searches. They are the slow part, and an interrupted run must
resume with the set already locked rather than re-opening a settled conversation.

If the user does not want to lock a set at all: write nothing, leave `phases.ai_visibility` as you
found it, say the phase is available whenever they want it, and stop. That is a complete run too.

### 2.4 After the lock — refusing edits, and what a reset costs

**The locked set is never edited again.** Not to fix a typo, not to add a prompt that looks
obviously better, not because the product changed. Comparability is the entire point: a score
against a changed set is a different metric wearing the old metric's name.

SKILL.md's writing-state rule — never remove or rewrite `ai_prompts_locked` entries — binds **you**.
You never touch the array on your own initiative, in any phase, for any reason.

When the user asks for an edit, refuse in one paragraph and explain the cost rather than the rule:
changing even one prompt resets the baseline, because today's 6-of-10 and last month's 4-of-10 stop
being the same measurement. Offer the alternative that usually solves it: keep the set, and put the
new question on the playbook (section 6) as a page to build — which is what a prompt they wish they
had measured usually means.

**If they still insist, that is a new baseline, not an edit.** Then:

1. Replace `ai_prompts_locked` with the new set, in one read-modify-write, preserving every other
   key. This is the only path in the entire skill that rewrites that array, and only a user's
   explicit, repeated instruction opens it.
2. Empty the history note in the readout. Today's numbers stand alone; report no trend, no delta,
   no comparison against any earlier snapshot.
3. Write this line into the readout, verbatim and greppable, because it is the only durable record
   that the metric changed:

   ```
   AI visibility baseline reset — prompt set replaced on <YYYY-MM-DD>; scores before this date are not comparable.
   ```

Section 5 reads that line back before it draws any trend.

## 3. Measure — one `WebSearch` call per locked prompt

### 3.1 Before the first search

**Check the `WebSearch` tool is actually available in this session.** It is a permissioned tool and
it is not always there.

Not available — absent from your tools, or the environment denies it → **stop the measurement.**
`ai_visibility.measured` stays `false`, and the readout names the missing tool:
`AI visibility: not measured — the WebSearch tool is not available in this session.` Leave today's
snapshot block exactly as measure.md wrote it, and do not create a snapshot merely to record a
non-measurement. Then continue to section 6 and report the playbook, which needs no searches.

Three things that are never substitutes, in order of how tempting they are:

- **Your own knowledge.** You may know roughly who ranks for a question. That is not a measurement,
  it is a memory of a training corpus, and writing it into a snapshot poisons every future diff.
- **Fetching a search engine yourself.** SKILL.md's hard rules forbid SERP scraping of Google
  anywhere in this skill. No curl, no WebFetch, no headless browser, no "just this once".
- **A different search tool** that happens to be in the session. A different index is a different
  measurement, and it silently breaks comparability with every earlier run. If `WebSearch` is
  missing, the honest answer is `measured: false`.

### 3.2 The searches

For each locked prompt, in order, **one `WebSearch` call with the prompt string verbatim as the
query.**

- Do not reword it, expand it, translate it, or add the brand, the domain, a `site:` filter, a year
  or a location. The locked string is the measurement instrument; changing it breaks the instrument.
- One call per prompt. Do not batch several prompts into one query and do not split one prompt into
  several.
- A call that errors or times out gets **at most one retry**. If it fails twice, that prompt is not
  `ok` — record which prompt failed and why, and move on.

Keep, per prompt: whether the call succeeded, and every result host you saw.

### 3.3 Scoring — what each number in the block means

**`prompts_ok`** — how many of the searches actually succeeded and returned results. Not how many
you sent. A failed search is not a "not cited": it is a question nobody asked.

**`cited`** — how many prompts had **at least one** result carrying the user's domain. It counts
prompts, not URLs: three pages of theirs in one result set is still one prompt. So `cited` can never
exceed `prompts_ok`.

The domain match, exactly:

- A result matches when its URL's host, lowercased and stripped of a leading `www.`, either **equals**
  the bare host or **ends with `"." + bare host`**. Subdomains count: `docs.example.com` is a hit.
- The same rule applies to a domain written out in a result's title or snippet text.
- **Never substring-match.** `notexample.com` contains `example.com` and is a different company; the
  leading-dot rule is what keeps it out.
- The brand **name** with no domain anywhere is not a hit. You may mention it in the readout prose
  ("named without a link in 2 prompts") — it never moves the number.

**`competitors`** — `{ "<host>": <count> }`, where count is **how many prompts that host appeared
in**. Build it from every third-party host you saw, normalised by the same rule (lowercased, `www.`
stripped, subdomains folded into the registrable host), excluding the user's own domain. Keep the
**top 10 by count, ties broken alphabetically** — sort before capping, so the same results always
produce the same ten and tomorrow's diff cannot invent a newcomer out of truncation. Say in the
readout when more were seen than kept.

One honesty note that belongs with this key every time it is reported: this list is *the domains
that took the answer slots*, which includes directories, marketplaces, forums and publishers. Do not
present a review site as the user's business competitor.

**Never fake a clean zero.** If four searches failed, the score is `cited` out of **six**, and the
readout says which four failed. `0` out of `10` when only six ran is the exact lie this phase and
`references/measure.md` both exist to prevent.

## 4. Write the snapshot block

**Skip this entire section when section 3 did not measure** — no `WebSearch` tool, or the
unattended skip in section 0. A non-measurement writes nothing anywhere: it is reported in the
readout and that is all.

### 4.1 Read, modify, write — you own one block and nothing else

The snapshot lives at:

```
dist/seo/snapshots/<YYYY-MM-DD>.json
```

`<YYYY-MM-DD>` is today's **local** date. Apply the gitignore guard from `references/audit.md`
section 7 — the `git check-ignore -q dist/seo` check gated behind "this project uses git", falling
back to `seo/snapshots/…` at the repository root, with exit **128** (no repository) meaning "not
ignored, use the `dist/` path". Resolve it **once** and use the same answer for the readout in
section 5, or the two halves of this run land in different directories.

Today's file exists → **read it, replace only `ai_visibility`, write the whole object back** with
your Write tool. Never shell redirection: quoting differs between PowerShell and POSIX shells and a
mangled snapshot is a silently corrupted history.

```json
"ai_visibility": { "measured": true, "prompts_ok": 10, "cited": 6, "competitors": { "competitor-one.com": 7, "a-directory.com": 4 } }
```

Four keys, exactly these names, no others. `measured` is `true` only when the searches actually ran
— `prompts_ok` may be less than the set size and `measured` is still `true`; the two facts are
different, which is why there are two fields.

**Everything else in that file belongs to `references/measure.md`.** `crawl`, `ranks`, `gsc`,
`date`, `source`, `site` — you read them if you like and you rewrite none of them, not even to
"correct" one. Preserve every key you do not recognise, including keys added by a later version.
Measure's own section 5.5 does the mirror of this for you: it preserves an `ai_visibility` block
whose `measured` is `true` instead of resetting it to defaults.

A second measurement on the same day overwrites your block with the newer numbers — it is the same
day's measurement, not an addition — and the readout says it replaced an earlier one.

### 4.2 When today's snapshot does not exist

Create it by following `references/measure.md` **sections 5.1 through 5.5 exactly as written** —
its call pattern, its truncation rules, its issue-type vocabulary — then update your block in the
file it produced. Every request that procedure makes is governed by the shell rule in
`references/setup.md` step 5 (`curl.exe` on Windows PowerShell, whole command on one line, `@file`
JSON bodies); this file ships no commands of its own.

Three parts of measure.md are **not** yours to run, exactly as `references/act.md` section 1.3 says:
section 3's interactive Search Console walkthrough (read `gsc.connected` as it stands and let 5.4 do
the rest), section 4's keyword agreement (an absent or empty `keywords` means `"ranks": []`), and
the `phases.measure` writes in its sections 1 and 7. Borrow the procedure; leave that phase key
exactly as you found it.

**Three more of its branches would stop an unattended run to ask a question**, and `references/act.md`
section 1.3 has already amended all three for exactly this situation: the `maxPages` heuristic when
5.2 needs a fresh crawl, a 10-minute stall counting as "cannot complete", and the no-completed-crawl
rule. Apply its amendments as written. Do not invent different ones, and do not ask.

**If measure.md's rules forbid a snapshot today, write none — and measure anyway.** Its section 5.2
allows a `crawl` block only from a real completed audit, and there is no `available` flag to say
otherwise, so a snapshot written without one would be a claim about the site nobody checked. When
OpenSEO is unreachable, when no completed crawl can be obtained, or when a fresh crawl cannot
complete:

- Your searches still run. They do not need OpenSEO and they are still real.
- Write **no** snapshot file, and never add your block to a *previous* day's snapshot.
- The readout carries today's numbers in full, plus the failure verbatim, plus one line saying the
  snapshot was not written because the crawl could not complete — so tomorrow's run sees a gap in
  the history rather than a fabricated day.

## 5. The readout

Append a dated section to `dist/seo/readouts/<YYYY-MM-DD>.md` (or the `seo/readouts/` fallback from
the same resolution as 4.1). Read the file first if it exists and append — `references/act.md`
writes its daily section into the same file, and a second write on the same day adds a section, it
never overwrites one. Write it with your Write tool, never with shell redirection.

**At most 12 lines including the heading.** Never drop a "not measured" line to make the cap; drop
optional detail instead.

```
## 2026-08-01 09:20 — AI visibility

Search visibility on the locked 10-prompt set (results-page proxy, not AI-answer citation)
Score: your domain appeared in results for 6 of the 10 prompts that ran (all 10 searches succeeded)
Trend: 6/10 vs 4/10 on 2026-07-25 (+2)
Absent from results: "best invoicing tool for freelance designers"; "how do I chase an unpaid invoice"
Answer slots taken by: competitor-one.com (7 prompts), a-directory.com (4), a-forum.com (3)
Snapshot: dist/seo/snapshots/2026-08-01.json (ai_visibility block updated)
Playbook: 4 items, next = answer-first page for "how do I chase an unpaid invoice"
```

The trend line, built honestly:

1. Find the newest snapshot in the snapshots directory whose `date` is **before** today's and whose
   `ai_visibility.measured` is `true`.
2. **Check for a baseline reset first.** Search the readouts directory for the literal string
   `AI visibility baseline reset`. If such a line exists with a date **after** that snapshot's date,
   the snapshot measured a different prompt set: it is not comparable. The line reads
   *"No comparable history — the prompt set was reset on `<date>`."*
3. No earlier measured snapshot → *"First measurement — no earlier run to compare against."* Report
   today's absolute numbers and compute no delta.
4. Different `prompts_ok` on the two sides → report both fractions and say the two runs asked
   different numbers of questions. Do not convert either to a percentage and subtract.
5. Cannot read the readouts directory at all → report today's numbers alone and say the history was
   not verified.

Also in the readout, in one line each and only when they apply: which prompts failed to search;
that more than ten competitor domains were seen and ten were kept; that this replaced an earlier
measurement today; that no snapshot was written and why.

## 6. The be-the-answer playbook

Four items. They are the work; the score is only the instrument. Run them **in order, at most one
per run** — the whole skill moves at one meaningful change a day on purpose.

There is no state key for playbook progress, deliberately: the record is the readouts. Read the
recent files in the readouts directory to see which items earlier runs recorded as done, and take
the first that none of them does. An item you cannot confirm from a readout is not done.

Every item below inherits `references/act.md`'s hard laws, and two of them are the ones this
playbook strains hardest against:

- **Hard law 1 — no fabricated claims, stats or reviews.** Every factual sentence traces to the
  user's own site, repository or product.
- **Hard law 2 — no doorway pages.** Ten locked prompts are a keyword list. Generating a page per
  prompt is precisely the near-identical page set that law forbids, and it is the single most
  likely way for this phase to damage a site.

### 6.1 Answer-first pages for the prompts nobody found you for

- **What.** For a locked prompt where the domain did not appear, one page that answers that prompt
  outright. Shape and word counts come from `references/act.md` section 5: H1 in the words of the
  question, a 40-70 word TL;DR as the first content element, numbered steps, question-shaped FAQs,
  one link out and one link in. Follow it there; it is not restated here.
- **Which prompt comes from this run's results.** The snapshot stores counts, not per-prompt
  outcomes, so a run that did not measure cannot choose one: report this item as pending and move to
  6.2 rather than guessing which prompt is missing you.
- **First check whether a page already covers the intent.** If one does, improving it is act.md
  section 4's four moves (title, TL;DR, FAQs, inbound internal links) and not a new page. This is
  the more common correct answer, and it is the one that does not risk law 2.
- **Why.** An assistant that searches can only ground an answer in a page that exists and states
  the answer near the top. A page that buries its answer under a pitch gets retrieved and not
  quoted.
- **Cap.** One new page per run, maximum — act.md hard law 3. If today's readout already records a
  new page from any seo-god run, this run writes none.
- **How to verify.** The build gate exits 0; the page renders at its URL; an existing relevant page
  links to it, so tomorrow's crawl does not report an `orphan-page`. Then the real check: the locked
  prompt is the test, and the next run's search for that exact string either finds it or does not.
  That result, not your opinion of the page, is the verification.

### 6.2 One name, spelled one way, everywhere

- **What.** One product name, one canonical one-line description, identical in `<title>`, the H1,
  the meta description, the footer, the `Organization` / `WebSite` structured data if the site emits
  any, the README, and every external profile.
- **Why.** Retrieval and entity association key on strings. "Acme Kit" and "AcmeKit" split the
  evidence for one company in half, and the weaker half loses.
- **How to verify.** Grep the working tree for each variant and list the files that disagree; check
  page titles in the crawl (`get_audit_pages` rows carry `title`) for the same variants. Verified
  when one spelling remains and the gate is green.
- **Do not rename the product.** This item makes the existing name consistent. Choosing a different
  name is the user's decision and never yours.

### 6.3 Directory and profile presence — owner-driven, never automated

- **What.** A short list of the places the user's category is actually looked up — the registries,
  marketplaces, review sites and industry directories that appeared as competitor domains in
  section 3.3 are the evidence-backed shortlist — plus the exact copy to paste: name, one-line
  description, category, URL, all matching 6.2 word for word.
- **You never submit anything.** No account creation, no form filling, no posting, no emailing, no
  review solicitation drafted in someone else's name. SKILL.md's hard rules forbid auto-posting and
  fake reviews, and this is the item where that pressure appears. You produce the list and the copy;
  the user submits it.
- **Why.** These profiles are pages that carry a name-and-description pair engines and assistants
  read as corroboration of who the user is — and they frequently outrank the user's own site for
  their own category.
- **How to verify.** The user pastes back each live profile URL; check it resolves and carries the
  same name and one-liner. Never record a profile as done because you drafted its copy.

### 6.4 One linkable data asset

- **What.** One page carrying a number nobody else has: the user's own measurements, their own
  product's aggregate data, a test they actually ran — published with the method stated and dated.
- **Why.** It is the thing other pages link to without being asked, and the thing an answer quotes
  by name. It is the only item here that compounds.
- **Truth, harder than anywhere else in this skill.** Hard law 1 applies with no exception: an
  invented statistic on a page built specifically to be cited is the worst failure available in this
  file. Real data, or no asset. If the honest version of the number is small, publish the small one.
- **How to verify.** The page exists and is linked internally from a relevant page; the number is
  reproducible from something in the user's own repository or product; later, a search for its exact
  title shows whether anything else has picked it up.

### 6.5 Executing an item

**Attended runs only.** An unattended run records which item is next and edits nothing — page
writes belong behind a build gate with somebody to answer for them.

When you execute one:

- Take **one** item, the first not yet done, and stop there.
- Repo edits follow `references/act.md` section 2 exactly: `build_cmd` from `seo-god.json` gates
  them; `"none"` means every edit is reported as **edited, unverified**; absent means ask once as
  `references/audit.md` section 2 asks, then store it. Run the gate once on the untouched tree
  first, and use audit.md's fix loop — its per-batch snapshot-and-created lists, its three-attempt
  cap, its restore — as the editing discipline. None of it is restated here.
- Record in the readout what you did, which locked prompt it was aimed at, and how it will be
  verified. Never mark an item done because you started it.

## 7. The upgrade — direct model probing

With LLM API keys configured (`references/power-ups.md`), probing stops being a proxy: each locked
prompt is asked of each model directly, and the score becomes real answer-citation measurement
across several models rather than a results-page count. The prompt set does not change — which is
exactly why locking it today makes that upgrade comparable to today. No key handling belongs in
this file.

## 8. Finish

Update `seo-god.json` — read, modify, write the whole object, preserving every key you do not
recognise, keeping `version: 1`:

- `ai_prompts_locked` — written once, in section 2.3, and thereafter only by a user-ordered baseline
  reset (2.4). Never edited by you.
- `phases.ai_visibility` — `"done"` when the key was not already `"done"`, a set is locked, and a
  measurement completed in this run. **Untouched** when it was already `"done"`, and untouched when
  no set was locked — including the unattended skip in section 0 and the declined lock in 2.3.
  A run that measured nothing never completes the phase.
- Nothing else. No `phases.act`, no `phases.power_ups`, no new keys.

Write it to disk immediately. Then give the user the readout you just wrote, and point at what is
next: the first playbook item, or ACT — the daily loop — if the item you just did was the last one.

### The degrade table — what a run does when something is missing

| Missing | What this phase still does | What the readout must say |
| --- | --- | --- |
| `WebSearch` tool unavailable | no measurement; playbook still reported | `AI visibility: not measured — the WebSearch tool is not available in this session` |
| `ai_prompts_locked` empty, unattended | nothing; no state written, no snapshot created | `AI visibility: not measured — prompt set not locked yet; run /seo-god ai-visibility attended once` |
| user declines to lock a set, attended | nothing; phase key left as found | the phase is available whenever they want it |
| some searches failed | scores over `prompts_ok`, never over the set size | `cited` of `prompts_ok`, and which prompts failed |
| OpenSEO unreachable / no completed crawl, today's snapshot absent | measures anyway; writes **no** snapshot | today's numbers, the failure verbatim, and that no snapshot was written |
| no earlier measured snapshot | today's numbers alone | `First measurement — no earlier run to compare against` |
| baseline was reset since the last snapshot | today's numbers alone | `No comparable history — the prompt set was reset on <date>` |
| `build_cmd` absent or run is unattended | measurement and readout only, zero repo edits | which playbook item is next, and that nothing was edited |

Every row is a complete, honest run. None of them is a reason to refuse, and none of them is a
reason to fill the gap with a number.
