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

**What ran, and the two places it deviates from upstream** — both forced, both recorded so the
numbers below can be read for exactly what they are:

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

**Conditions, held constant across all four descriptions:**

| | |
| --- | --- |
| Runs per query | 3 (60 `claude -p` invocations per description, 240 total) |
| Trigger threshold | a query passes if it fires ≥ 50% of its runs (upstream default) |
| Model | the session default, i.e. what the user gets |
| Trigger rule | upstream's: a run counts only if the **first** tool call is `Skill`/`Read` naming seo-god |
| cwd | one fixed empty scratch dir |
| Side effects | none — the subprocess is killed at `content_block_start`, before any tool executes |

Read those last two rows as limits on the result. First-tool-use is conservative: a skill invoked
after one exploratory `Glob` scores as a miss. And an empty cwd is not a website repo, which
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
"review this PR" → `review`, "write a blog post" → `aria-voice`, "fix my docker compose" and the
GA4 tag bug → `superpowers:systematic-debugging`, the LCP profile → `chrome-devtools-mcp`, the
reels drop → `virality-review`. Not-triggering here is the right answer arriving, not a gap.

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
   gain from 93% to 100%. "For your own website" alone did not hold the line against "pull
   quizlet.com's keywords out of Ahrefs, don't touch our site".

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
- **The imperative-first advice did not win here.** `improve_description.py` prefers "Use this
  skill for ..." over a noun phrase. C2 followed it and scored no better than the noun-phrase
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
3. **Run a capability benchmark, not just a triggering one.** skill-creator's main loop
   (with-skill vs. baseline runs, graded assertions, `benchmark.json`, the eval viewer) measures
   whether the skill *does the job well*, which this pass did not touch at all. It needs a
   throwaway site and a live OpenSEO container. That is the highest-value remaining eval.
4. **Contribute the Windows fix upstream.** `run_eval.py`'s `select.select()` on a pipe makes
   skill-creator's whole eval loop unrunnable on Windows. A thread-and-queue reader fixes it
   without changing the method, as the port here demonstrates.
