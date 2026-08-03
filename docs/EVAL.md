# EVAL — description triggering

**Date:** 2026-08-01 · **Skill:** seo-god · **Scope:** frontmatter `description:` only

Whether this skill ever runs is decided by one thing: the `description` line. Claude sees the
name plus that line in its available-skills list and picks from it. So the line gets measured
like any other piece of the system rather than argued about, and this file is the measurement.

---

## 1. Method

Automated, not a hand-waved judgement. `skill-creator`'s description-optimization method:
20 realistic queries (10 that must trigger, 10 near-misses that must not), each run repeatedly
through a real `claude -p` session, scored on whether the skill actually fired.

**Where this run departs from upstream** — every departure recorded, so the numbers below can be
read for exactly what they are. The first two were forced by the environment, the next two by this
task's bounds and by what the measurements turned out to show, and the last two are steps upstream
takes that simply did not happen here:

1. **The harness is a port, not the shipped script.** `skill-creator/scripts/run_eval.py` cannot
   run on Windows: it calls `select.select()` on a subprocess pipe, and Windows `select` accepts
   only sockets (`OSError` WinError 10093, reproduced before porting). The port keeps the method
   identical — `claude -p --output-format stream-json --verbose --include-partial-messages`,
   trigger detection from `content_block_start` / `input_json_delta` events, N runs per query, a
   0.5 trigger-rate threshold — and swaps the pipe reader for a thread and a queue.
   `improve_description.py` and `split_eval_set()` are select-free and were used **unmodified**.
2. **Candidates were tested on the real installed skill, not a throwaway command file.** Upstream
   registers the candidate description as a temp command in `.claude/commands/` and looks for that
   unique name. Unusable here: seo-god is installed globally, so it would also appear in the
   skills list with a *different* description, Claude would face two near-duplicate entries, and
   picking the real one would score as a miss. Instead each candidate was written into `SKILL.md`'s
   description line, measured, and the original restored in a `finally` block. That measures what a
   user actually experiences.
3. **The winner was not selected by held-out test score alone.** Upstream `run_loop` returns
   `best_description` chosen by test score, specifically to avoid overfitting to train. That rule
   could not discriminate here: C2, C3 and C4 all tied at 8/8 on test. It would also have been
   contaminated, because the exclusion clause was authored with knowledge of N4, which sits in the
   test half. Selection therefore used the full 20 plus per-query reasoning. §4 keeps the full
   explanation, since this is the one deviation that could flatter the result.
4. **One improver call plus three hand-authored variants, not `run_loop`'s iteration loop.**
   Upstream loops up to five automated iterations, each re-proposing from the previous scores.
   Here `improve_description.py` ran once on the train split — and its output could not ship
   (literal double quotes break a one-line YAML scalar) and broke two of the skill's own
   constraints, so the three tested candidates were hand-authored from its insight plus the
   measured per-query evidence. The automated loop also cannot honour this task's bounds, which
   permit edits to the description line and nothing else.
5. **Upstream's user sign-off on the eval set did not happen.** Step 2 of the method puts the eval
   set in front of the *user* through an HTML review page before any optimization runs, on the
   reasoning that bad queries produce a bad description. That review never took place: all 20
   queries have a single author, which §4 records as a limit on the result rather than a detail.
6. **`--model` was never passed.** Upstream's guidance is to run the triggering test on the model
   powering the session, so the measurement matches what the user actually experiences. The harness
   passed no `--model`, so every run took the CLI default instead. The note under the conditions
   table records what that resolved to and what it costs; §5 item 6 carries the fix.

**Conditions, held constant across all four descriptions:**

| | |
| --- | --- |
| Runs per query | 3 (60 `claude -p` invocations per description, 240 total) |
| Trigger threshold | a query passes if it fires ≥ 50% of its runs (upstream default) |
| Model | **`claude-fable-5`** — see the note below |
| CLI | `claude` 2.1.220 |
| Per-query timeout | **150s** (upstream default is 30s) |
| Trigger rule | upstream's: a run counts only if the **first** tool call is `Skill`/`Read` naming seo-god |
| cwd | one fixed empty scratch dir |
| Side effects | none — the subprocess is killed at `content_block_start`, before any tool executes |

**On the model, stated with the uncertainty it deserves.** The harness passed no `--model`, so every
run used whatever the `claude` CLI resolves as its default. That default was recovered as
`claude-fable-5` by re-querying the same CLI, in the same directory, with the same environment,
minutes after the last run — **the 240 runs themselves did not log it**, so this is strong
circumstantial evidence rather than a recording. Note the mismatch it exposes: skill-creator's
method says to pass the model powering the current session, and the orchestrating session was
`claude-opus-5`. It was not passed, so these numbers describe triggering under `claude-fable-5`.
Triggering is a model-level judgement, so a different model can plausibly score differently — treat
the table in §2 as measured on `claude-fable-5`, not as model-independent.

**On the timeout.** 30s is not survivable here: a Windows `claude` CLI cold start plus a full model
turn regularly exceeds it, so a 30s ceiling would have manufactured non-triggers wholesale. 150s
was picked to sit clear of that, and it nearly did — exactly one run of 240 still hit the ceiling
(§4).

Read the trigger-rule and cwd rows as limits on the result. First-tool-use is conservative: a skill
invoked after one exploratory `Glob` scores as a miss. And an empty cwd is not a website repo, which
probably depresses the repo-shaped positives — a real user runs this inside their project.

---

## 2. Result

Four descriptions measured. **C4 shipped.**

| | all 20 | train 12 | held-out 8 | recall (runs) | false positives | precision |
| --- | --- | --- | --- | --- | --- | --- |
| **baseline** (pre-existing) | 18/20 | 11/12 | 7/8 | 26/30 | 2/30 | 93% |
| C2 (skill-creator's rewrite, constrained) | 18/20 | 10/12 | 8/8 | 27/30 | 3/30 | 90% |
| C3 (minimal intent-framed rewrite) | 17/20 | 9/12 | 8/8 | 25/30 | 2/30 | 93% |
| **C4 — shipped** | **19/20** | **11/12** | **8/8** | 26/30 | **0/30** | **100%** |

C4 dominates: it is the only candidate that fixes a failure without breaking something else.

### Per-query, all four (`n/3` triggers; `*` = query failed)

| id | split | should fire | baseline | C2 | C3 | C4 |
| --- | --- | --- | --- | --- | --- | --- |
| P1 `improve my SEO` | train | yes | 3/3 | 3/3 | 3/3 | 3/3 |
| P2 `why am I not ranking` | train | yes | 0/3 * | 0/3 * | 0/3 * | **0/3 *** |
| P3 `SEO audit` | test | yes | 3/3 | 3/3 | 3/3 | 3/3 |
| P4 `set up SEO monitoring` | test | yes | 3/3 | 3/3 | 3/3 | 3/3 |
| P5 `get cited by ChatGPT` | train | yes | 2/3 | 3/3 | 1/3 * | 2/3 |
| P6 `/seo-god` | train | yes | 3/3 | 3/3 | 3/3 | 3/3 |
| P7 indexing problem, never says "SEO" | train | yes | 3/3 | 3/3 | 3/3 | 3/3 |
| P8 AI visibility, phrased as LLM recommendation | test | yes | 3/3 | 3/3 | 3/3 | 3/3 |
| P9 schedule the loop + digest | test | yes | 3/3 | 3/3 | 3/3 | 3/3 |
| P10 local crawl + repo fixes, names Ahrefs | train | yes | 3/3 | 3/3 | 3/3 | 3/3 |
| N1 "review this PR" (control) | train | no | 0/3 | 0/3 | 0/3 | 0/3 |
| N2 "write a blog post" (control) | train | no | 0/3 | 0/3 | 0/3 | 0/3 |
| N3 "fix my docker compose" (control) | test | no | 0/3 | 0/3 | 0/3 | 0/3 |
| N4 competitor data pull, own site untouched | test | no | 2/3 * | 0/3 | 0/3 | **0/3** |
| N5 paid search / Google Ads | test | no | 0/3 | 0/3 | 0/3 | 0/3 |
| N6 Core Web Vitals as a perf task | test | no | 0/3 | 0/3 | 0/3 | 0/3 |
| N7 social reach drop | train | no | 0/3 | 0/3 | 0/3 | 0/3 |
| N8 Chrome Web Store listing search | train | no | 0/3 | 0/3 | 0/3 | 0/3 |
| N9 GA4-vs-Search-Console tag bug | train | no | 0/3 | 3/3 * | 2/3 * | 0/3 |
| N10 internal (Algolia) site search | train | no | 0/3 | 0/3 | 0/3 | 0/3 |

### Target trigger phrases from the design

| phrase | verdict |
| --- | --- |
| "improve my SEO" | **hit** 3/3 |
| "SEO audit" | **hit** 3/3 (phrase was missing from the baseline's quoted list; C4 adds it) |
| "why am I not ranking" | **miss** 0/3 — see §3 |
| "set up SEO monitoring" | **hit** 3/3 |
| "get cited by ChatGPT" | **hit** 2/3 (passes threshold; high variance, see §4) |
| "/seo-god" | **hit** 3/3 — the always-trigger clause holds |

Negative controls all clean, and they routed sensibly rather than merely failing to fire:
"review this PR" → `review`, "fix my docker compose" and the GA4 tag bug →
`superpowers:systematic-debugging`, the LCP profile → `chrome-devtools-mcp`; "write a blog post" and
the reels drop each went to a writing skill and a video-analytics skill installed on the test
machine. Not-triggering here is the right answer arriving, not a gap.

---

## 3. What changed, and why each edit earned its place

C4 is the baseline plus three deltas. Nothing else moved.

1. **`'SEO audit'` added to the quoted trigger list.** It is a stated design target phrase and was
   the one missing from the list. No measured gain (P3 already fired 3/3 off "audits and fixes"),
   and no measured risk. Coverage of a documented requirement.
2. **"makes AI engines cite you" → "works to get ChatGPT and other AI engines citing you".**
   `references/ai-visibility.md` is explicit that "the words *cite* and *citation* describe the
   goal, never the measurement" — the free path measures search visibility on a locked prompt set
   as a *proxy* for citation. "Makes ... cite you" asserts the outcome; "works to get ... citing
   you" states the goal, which is what the skill can honestly claim. Naming ChatGPT inside the
   capability clause is deliberate: the one candidate that dropped it (C3) saw P5 fall to 1/3.
3. **"Not for competitor-only data pulls that leave your own site untouched." added.** This is the
   only edit with a clean measured win: N4 went 2/3 → 0/3, which is the whole of the precision
   gain from 93% to 100%. "For your own website" alone did not hold the line against N4 — the
   competitor keyword pull, whose text is in A.2 verbatim rather than paraphrased here.

### What was rejected, and why

`skill-creator`'s improver (`improve_description.py`, run unmodified on the train split) proposed a
full intent-framed rewrite. Three findings came out of testing it:

- **It could not ship as written.** It contained literal double quotes (`"SEO"`), which breaks a
  one-line double-quoted YAML scalar — verified, `yaml.safe_load` raises `ParserError`. It also
  dropped own-site scoping to the second sentence and kept the non-goal-framed "making ChatGPT
  ... cite the site". C2 is its central idea re-expressed within those constraints.
- **Broadening diagnosis coverage costs precision, reproducibly.** Both broader candidates pulled
  in N9, the GA4-vs-Search-Console tag bug (C2 3/3, C3 2/3, from a clean 0/3). Two structurally
  different rewrites making the same mistake is a tradeoff, not noise: language wide enough to
  catch "traffic dropped" is wide enough to catch "analytics says traffic dropped", which is a
  debugging job. That is why C4 does **not** add ranking-drop or traffic-drop language.
- **The imperative-first advice did not win here.** `improve_description.py` states it as
  `"Use this skill for" rather than "this skill does"`. C2 followed it and scored no better than the noun-phrase
  baseline (18/20), while C3 scored worse (17/20). Worth a retest at higher n before acting on it.

---

## 4. Honest caveats

- **P2 is not a description problem, and no description fixed it.** "why am I not ranking for
  'quiz solver extension' anymore ..." fired 0/3 under *all four* descriptions, including C2,
  which spelled the intent out ("any why-am-I-not-ranking or traffic-drop question, even when they
  never say 'SEO'"). The failure modes are identical throughout: a text-only answer from knowledge
  (2 runs) or a `Glob` first (1 run). skill-creator's own guidance names this — Claude skips skills
  for questions it thinks it can answer directly — and the empty-cwd condition makes it worse,
  since there is no site there to inspect. Treat 0/3 as "not yet measured properly", not as a
  known defect. See the §5 recommendation.
- **Held-out scores for the exclusion clause are in-sample.** The stratified 60/40 split (upstream
  `split_eval_set`, seed 42) put N4 in the **test** half. The improver never saw it — but the
  author of the exclusion clause did, after reading the full baseline. So C2/C3/C4's 8/8 test score
  is not a clean generalization estimate for that clause. Selection therefore used the full 20 plus
  per-query reasoning, not the test score alone.
- **n=3 is thin for single-query deltas.** P5 read 2/3, 3/3, 1/3, 2/3 across four descriptions with
  no coherent story. One-run differences on one query are noise; only the reproduced N9 regression
  and the reproduced N4 fix are treated as signal here.
- **One run was a timeout.** Baseline N9 run 3 hit the 150s ceiling and was scored as a non-trigger.
  It did not change that query's verdict.
- **Twenty queries, one author.** Enough to catch a 2/30 false-positive rate and a systematic
  precision tradeoff. Not enough to certify a 100% precision claim in the wild.

---

## 5. Recommendations for the ledger — NOT implemented here

This pass was bounded to the description line and this file. The following came out of the method
and are logged rather than acted on:

1. **Re-measure P2 inside a real website repo.** The one unresolved positive miss is confounded by
   an empty cwd and by first-tool-use scoring. Re-run those queries with the cwd set to an actual
   site (and consider crediting a `Skill` call that arrives after one exploratory tool call) before
   anyone concludes the description is at fault. If it still misses at n=10, the lever is the
   README's suggested phrasing, not the description.
2. **Decide N9's scope deliberately.** "GA4 shows 0 organic sessions but Search Console still shows
   clicks" is a genuine boundary case. It is currently, and correctly, someone else's job. If the
   design later wants seo-god to own Search Console data-quality debugging, that is a scope
   decision for `references/measure.md` — not a description tweak.
3. **Test the exclusion clause against implicit-intent competitor phrasing.** N4 says "don't touch
   our site" out loud, which is the easy shape. The untested shape is the one where the user's own
   site never appears in the sentence at all — "pull quizlet's backlink profile so I know what to
   chase" — where the clause has no explicit cue to catch and the implied next step *is* work on
   their own site. Future-eval material; the clause's measured 0/3 does not cover it.
4. **Run a capability benchmark, not just a triggering one.** skill-creator's main loop
   (with-skill vs. baseline runs, graded assertions, `benchmark.json`, the eval viewer) measures
   whether the skill *does the job well*, which this pass did not touch at all. It needs a
   throwaway site and a live OpenSEO container. That is the highest-value remaining eval.
5. **Contribute the Windows fix upstream.** `run_eval.py`'s `select.select()` on a pipe makes
   skill-creator's whole eval loop unrunnable on Windows. A thread-and-queue reader fixes it
   without changing the method, as the port here demonstrates.
6. **Re-run the winner under `claude-opus-5` before treating these numbers as transferable, and
   always pass `--model`.** Every figure in §2 was measured on `claude-fable-5`, the CLI default,
   because no `--model` was passed — while the session skill-creator's method points at was
   `claude-opus-5`. Whether a description triggers is a model-level judgement, so 19/20 at 100%
   precision is a result *for `claude-fable-5`*, not a property of the description. Re-running C4 alone
   over the same 20 queries at n=3 settles it for about 60 invocations; folding it into item 1's
   re-measurement costs almost nothing extra. The standing fix is smaller and matters more: pass
   `--model` explicitly on every future run and record the resolved ID **with** the scores, so the
   next person is not reconstructing it after the fact the way §1 had to.

---

## Appendix A — the eval set, verbatim

Every query below is reproduced exactly as the harness sent it to `claude -p`, generated
straight from the JSON the harness read rather than retyped, so it cannot drift from what
actually ran. One deliberate exception: the site host name in **P1** was a real domain and has
been replaced with `example-ext.com`. Nothing else was touched, and a host name has no bearing
on whether the query triggers the skill. Lowercase, missing apostrophes and casual phrasing are deliberate: these are
meant to read like something a real user types, not like test fixtures. `split` is the
stratified 60/40 assignment from upstream `split_eval_set(holdout=0.4, seed=42)`; the
improver only ever saw the train half.

### A.1 — must trigger (10)

**P1** — improve my SEO  
split: train · triggers: base 3/3 · c2 3/3 · c3 3/3 · c4 3/3

> i run a small chrome extension site (example-ext.com) and honestly my google traffic has been flat for like 4 months. can you help me improve my seo? and i mean actually go through the site and fix things, not hand me another checklist

**P2** — why am I not ranking  
split: train · triggers: base 0/3 · c2 0/3 · c3 0/3 · c4 0/3

> why am i not ranking for 'quiz solver extension' anymore? we have a page for it at /solve-quizzes and it used to sit around position 15, now i cant find us in the first 5 pages at all

**P3** — SEO audit  
split: **test** · triggers: base 3/3 · c2 3/3 · c3 3/3 · c4 3/3

> can you run a proper seo audit on my next.js site - broken links, missing meta descriptions, duplicate title tags, orphan pages, the whole lot. the repo is this directory

**P4** — set up SEO monitoring  
split: **test** · triggers: base 3/3 · c2 3/3 · c3 3/3 · c4 3/3

> i want to set up seo monitoring so something tells me when a ranking drops instead of me finding out three weeks later. ideally it just runs itself every morning

**P5** — get cited by ChatGPT  
split: train · triggers: base 2/3 · c2 3/3 · c3 1/3 · c4 2/3

> how do i get cited by chatgpt when someone asks it for tools to solve online quizzes? right now it names three competitors and never mentions us once

**P6** — /seo-god (always-trigger)  
split: train · triggers: base 3/3 · c2 3/3 · c3 3/3 · c4 3/3

> /seo-god

**P7** — coverage: technical indexing, word 'SEO' never used  
split: train · triggers: base 3/3 · c2 3/3 · c3 3/3 · c4 3/3

> search console is telling me 41 of my pages are 'Crawled - currently not indexed' and i genuinely dont know what that means or what im supposed to do about it. its a next app on vercel

**P8** — coverage: AI visibility, phrased as LLM recommendation  
split: **test** · triggers: base 3/3 · c2 3/3 · c3 3/3 · c4 3/3

> perplexity and claude both recommend my competitor whenever someone asks about my category. what do i actually have to change on the site so the LLMs start picking us up too

**P9** — coverage: schedule the loop + digest  
split: **test** · triggers: base 3/3 · c2 3/3 · c3 3/3 · c4 3/3

> can you make the whole ranking-check-and-fix loop run itself every day around 5am and telegram me a short digest? i keep forgetting to look

**P10** — coverage: local crawl + repo fixes, names a paid competitor  
split: train · triggers: base 3/3 · c2 3/3 · c3 3/3 · c4 3/3

> i want something that crawls my own site locally, works out which on-page problems actually matter, and then opens the files and fixes the titles itself. is that a thing or do i just have to pay for ahrefs

### A.2 — must NOT trigger (10)

The first three are the plain negative controls. The remaining seven are near-misses, which are
the ones that carry the information: each shares vocabulary or intent with the skill while needing
something else. A negative control that is obviously irrelevant tests nothing.

**N1** — negative control (brief): review this PR  
split: train · triggers: base 0/3 · c2 0/3 · c3 0/3 · c4 0/3

> review this PR before i merge it - branch is feat/semester-pass, it touches the stripe webhook and i want a second pair of eyes on the entitlement downgrade logic

**N2** — negative control (brief): write a blog post  
split: train · triggers: base 0/3 · c2 0/3 · c3 0/3 · c4 0/3

> write a blog post about why chrome extensions get rejected from the web store. around 1200 words, our usual voice, its going in the /blog section

**N3** — negative control (brief): fix my docker compose  
split: **test** · triggers: base 0/3 · c2 0/3 · c3 0/3 · c4 0/3

> fix my docker compose - the postgres service keeps restarting and the app container cant resolve 'db' as a hostname. file is ./docker-compose.yml

**N4** — near-miss: competitor data lookup, not own-site loop  
split: **test** · triggers: base 2/3 · c2 0/3 · c3 0/3 · c4 0/3

> pull the domain rating and top 50 organic keywords for quizlet.com out of ahrefs so i can see what theyre ranking for. just the numbers, dont touch our site

**N5** — near-miss: paid search, not organic  
split: **test** · triggers: base 0/3 · c2 0/3 · c3 0/3 · c4 0/3

> our google ads CPC has basically doubled this month on the 'quiz answers' ad group. can you look at the campaign and tell me which ad groups to pause

**N6** — near-miss: Core Web Vitals as a perf task  
split: **test** · triggers: base 0/3 · c2 0/3 · c3 0/3 · c4 0/3

> lighthouse says LCP is 4.2s on mobile for the homepage. can you profile it in devtools and fix whatever the biggest offender is

**N7** — near-miss: social reach, 'not getting found'  
split: train · triggers: base 0/3 · c2 0/3 · c3 0/3 · c4 0/3

> my instagram reels arent getting reach anymore. can you look at the last 10 and work out what changed

**N8** — near-miss: store search ranking, not web search  
split: train · triggers: base 0/3 · c2 0/3 · c3 0/3 · c4 0/3

> our chrome web store listing doesnt show up when people search 'quiz helper' inside the store. can you rewrite the listing title and description so it ranks better in CWS search

**N9** — near-miss: analytics plumbing bug, mentions Search Console  
split: train · triggers: base 0/3 · c2 3/3 · c3 2/3 · c4 0/3

> GA4 has been showing 0 organic sessions for the last 4 days but search console still shows clicks coming in. is the gtag broken or is this a data delay thing

**N10** — near-miss: internal site search index  
split: train · triggers: base 0/3 · c2 0/3 · c3 0/3 · c4 0/3

> our docs site search (algolia) returns nothing for 'canvas quizzes' even though that page definitely exists. can you check the index config

### A.3 — the four descriptions measured

Two of the four are recoverable from the repo and are pointed at rather than duplicated, so there
is no second copy to fall out of date. The two candidates that lost were never written to disk
permanently, so a re-measurement could not re-author them from prose — they are reproduced here in
full. All four strings are exactly what sat on the `description:` line while that column of §2 was
being measured, read back off disk by the harness rather than copied from a draft.

**baseline** — `git show c27321a:SKILL.md` (equivalently, the `-` side of `git show a12b37d -- SKILL.md`).

**C4, shipped** — the live `description:` line in `SKILL.md`.

**C2** — skill-creator's rewrite, re-expressed within the skill's own constraints (756 chars):

```
Use for ANY task about making the user's OWN website more visible in Google and in AI answers — improving it, diagnosing it, or automating it. Diagnosis counts as much as setup: someone asking why a page or keyword stopped ranking, slipped position, or vanished from search belongs here even when they never say 'SEO'. Covers auditing and fixing their site with OpenSEO, rankings + Google Search Console measurement, working to get ChatGPT and other AI engines citing them, and scheduling the whole loop to run daily. Trigger on 'improve my SEO', 'SEO audit', any why-am-I-not-ranking or traffic-drop question, 'set up SEO monitoring', 'get cited by ChatGPT' — and always on /seo-god. Not for competitor-only data pulls that leave their own site untouched.
```

**C3** — minimal intent-framed rewrite (541 chars):

```
Agentic SEO operator for the user's own website: audits and fixes their site with OpenSEO, measures rankings + Google Search Console, works to get AI engines citing them, and schedules the whole loop daily. Use for ANY 'improve my SEO', 'SEO audit', 'set up SEO monitoring', or 'get cited by ChatGPT' request, and for any question about why a page stopped ranking, slipped position, or lost organic traffic — even when the user never says 'SEO'. Always use on /seo-god. Not for competitor-only data pulls that leave their own site untouched.
```
