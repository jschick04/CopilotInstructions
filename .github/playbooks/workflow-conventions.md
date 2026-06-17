# Workflow conventions

<!-- read-receipt-token: e6fabcfc -->

## Ask-first principle for all playbooks

Every playbook file under `.github/playbooks/` has an Intake Questions section as its first executable block. When entering a playbook, the agent's FIRST action is to view that file and run intake. Use `ask_user` when available; otherwise ask in chat. **Bundle independent questions in one prompt; ask sequentially only when a later question depends on the prior answer.** The agent does NOT produce playbook output, write to artifacts, or take downstream actions until intake is complete (or the user has explicitly skipped a specific step - see User-skip policy below).

**Phase triggers vs domain triggers - different semantics.**

- **Phase triggers** (the code-change phases in the router: pre-implementation, post-code-change, pre-commit, pre-PR-push, post-pr-review) are **mandatory** when their condition holds. The agent enters the phase and fetches the playbook. The user may skip a step within the phase only via the User-skip policy (with warning + recording + safety-critical re-confirmation). The agent does NOT ask "do you want to run this phase?" - it just enters.
- **Domain / documentation triggers** (design-spec, ADO task planning, codebase-architecture-audit, scope-planning, multi-model-review, etc.) are **offered** via `ask_user` because they're optional per-ask. Detection of a domain / documentation trigger never auto-fires the playbook - the agent always confirms first (substituting the matched playbook slug - *"this looks like a `<playbook-slug>` ask - want me to run that playbook?"*; not always "design-spec") and waits. If the user declines, the agent answers normally without the playbook.

## Intake pre-fill rule

If the user opens with structured detail that maps to intake questions (e.g. *"design-spec for the X service, current-state mode, audience=team"*), pre-fill those answers and ask only the unfilled questions.

**Confirm any pre-filled value that maps to an overloaded term** before using it: *"team"*, *"owner"*, *"audience"*, *"scope"*, *"destination"*, and similar are tentative and must be re-confirmed if they affect output structure. Exact `key=value` syntax (e.g. `audience=team`) may pre-fill directly without re-confirming. Never infer IDs, owners, linked work items, or output destinations from bare phrases.

## Trigger detection - strong vs weak

Per-playbook trigger phrases are listed in the workflow router table in `AGENTS.md`. The discriminator between strong and weak is **semantic, not phrase-based**:

- **Strong triggers** - user is asking for a **durable artifact** (spec, survey, design doc, architecture write-up, current-state document, ADO work item, deliverable list) OR a **named on-demand workflow** (audit, planning lens, prototype scaffold, panel review - `codebase-architecture-audit`, `scope-planning`, `multi-model-review`, etc.; see `.github/playbooks/manifest.yaml` for the catalogue). Agent immediately offers the matched playbook via `ask_user` (substitute the slug - *"this looks like a `<playbook-slug>` ask - want me to run that playbook?"*; not always "design-spec"). If the user declines, do not re-offer in the same thread unless the ask materially changes.
- **Weak triggers** - user is asking an **exploratory factual question** without requesting a document: *"how does X work"*, *"what do we have in prod for X"* (asked casually, not as "document what we have in prod"), *"summarize"*, *"give me the gist"*. Agent does NOT block. Optionally adds a single non-blocking sentence in its normal response: *"I can answer directly, or run the design-spec playbook for a more formal write-up - which do you prefer?"*. Decline-then-no-retry rule still applies.

**Disambiguation rule for ambiguous phrasing.** When the same phrase could go either way (e.g. *"what do we have in prod for X"*), default to weak (answer directly + offer non-blocking) rather than strong (block with `ask_user`). Strong triggers should require a clear artifact-request signal:

- **Verb forms that imply written output:** *"write"*, *"draft"*, *"document"*, *"design"*, *"plan"*, *"architect"*, *"survey"*.
- **Artifact nouns:** *"spec"*, *"doc"*, *"survey"*, *"task"*, *"work item"*, *"deliverables"*, *"design change request"*.
- **Hortative-drafting forms paired with an artifact-shaped noun:** *"should be ..."*, *"should look like ..."*, *"what should the Y look like"*, *"what would the X (spec / API / contract / schema / acceptance criteria / surface) be"*. These imply the user wants you to *propose* a durable artifact. Strong even without a verb from the list above. **Filter:** strong only when the requested object is artifact-shaped (spec / API / contract / schema / surface / work item / criteria); pure factual hypotheticals like *"what would the cost be"*, *"what would the latency be"*, *"what would the result of this query be"* are exploratory analysis and stay weak.
- **Bare verbs *"review"* / *"audit"* are NOT strong on their own** - *"review the auth flow"* and *"audit my changes"* are analytical asks, not artifact requests. They become strong only when paired with an artifact noun: *"architect review of"*, *"audit report"*, *"review document for"*. Bare *"review"* / *"audit"* without a paired artifact noun fall into the ambiguous artifact-adjacent category below.

**Ambiguous artifact-adjacent - third category for phrasings that imply an artifact without naming one.** Phrases like *"can you draw up something on X"*, *"put together notes on X"*, *"outline the architecture for X"*, *"give me a write-up on X"*, *"I want a spec-ish thing for Y"*, bare *"review the auth flow"* / *"audit my changes"* don't include a clear artifact noun (`spec`/`doc`/`survey`) but the verb implies the user might want something durable. **Do not silently default to weak** (which would answer directly when the user wanted a doc) **and do not silently default to strong** (which would over-block, and would also pick the wrong playbook if the user actually wanted ADO planning). Instead, ask one short clarifying `ask_user` question that separates *format* from *playbook*:

> *"Do you want a quick chat answer, or a durable artifact? If artifact: the design-spec playbook (system / architecture write-up), the ADO task-planning playbook (work-item content), or another format you have in mind?"*

Then proceed accordingly. Do not run intake until the user picks. The decline-then-no-retry rule still applies after the choice. Defer destination/intake details until the chosen playbook's intake step.

## User-skip policy

The user may explicitly skip any playbook step or entire phase. When they do:

1. The agent must warn about the consequence in one sentence (e.g. *"Skipping the pre-PR-push sweep means I cannot certify the branch as review-ready under this repo's workflow."*).
2. The agent records the skip in **session todos** as the canonical mechanism. Concrete recording rules - designed so a resumed session can read the evidence back unambiguously:
   - **Required columns:** `id`, `title`, `description`, `status`. Many `todos` schemas reject inserts missing `title` - always populate it.
   - **`id`** = `skip-<phase>-<short-desc>-<yyyymmddHHMMSS>`. The timestamp suffix is mandatory because the same phase may be skipped more than once in a session (e.g. *"skip multi-model on this commit"* + *"skip multi-model on a follow-up commit"*) and a fixed ID would silently overwrite or fail to insert.
   - **`title`** = `Skipped <phase>: <short-desc>`.
   - **`description`** = the skipped phase or step name, the user's stated reason, and the time. Be explicit so a resumed-session reader can decide whether to re-run.
   - **`status`** = `'done'`.
   - **Schema bootstrapping:** if SQL is available but the `todos` table doesn't exist yet in this session, create it with a minimal schema (`id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT, status TEXT DEFAULT 'pending'`) before inserting.
   - **Fallback when SQL is entirely unavailable:** write the skip evidence to `<copilot-session-state>/<session-id>/files/skips.md` with the same field set (id / title / description / status / time) AND surface the skip in the chat summary so the user has a paper trail.
   - **Fallback when even the session-state path can't be resolved:** surface the situation in chat and require the user to explicitly re-acknowledge the skip on each subsequent assistant turn until evidence can be recorded. Do NOT silently proceed.
   - **Hard stop when ALL recording paths fail:** if SQL is unavailable, the session-state path cannot be resolved, AND there is no usable chat surface for per-turn re-acknowledgement (e.g. headless / non-interactive CI contexts), **halt the phase and do not certify readiness**. The skip cannot be evidenced, so the workflow cannot proceed. Surface a non-zero exit / failure signal to the runtime if one is available.
3. The agent must NOT later claim the full workflow completed - the "ready to push" / "ready to commit" / "all phases done" message must explicitly enumerate which phases were skipped (read the recorded skips back; do not rely on memory).
4. **If recorded skip evidence is missing or incomplete in a later session** (resumed work, agent handoff), treat the relevant phase as **not proven** and conservatively re-run the required checks or ask the user to explicitly accept a skip. Do not infer success from absence of evidence.
5. **Safety-critical skips** require explicit user re-confirmation before proceeding. Specifically:
   - Skipping the multi-model reviewer panel for any non-trivial change (defined: more than a single-line typo / single-property rename / single config-key value tweak).
   - Skipping pre-PR-push branch-wide sweep for any push intended for review (PR-opening, request-for-review, push to a shared branch others may pull from).
   - Skipping verification-of-fix when the change is justified by a perf metric, bug repro, or security claim.
   - Skipping the pre-implementation multi-model panel on changes touching any safety-critical class (below).
   **Safety-critical classes (canonical list; includes but is not limited to):** concurrency; security; cryptography; native interop; payment or financial logic; authentication; authorization; shared global state; data integrity / schema / data migration; destructive or irreversible operations (deletion, bulk update, purge); permissions / access control / ACLs; secrets / credentials; privacy / PII; release / deployment / CI infrastructure; governance / instruction-set artifacts. This is the single canonical safety-critical definition referenced across the instruction set (e.g. AGENTS.md §1, the lite-profile trivial fast-path); extend it HERE, not in copies.
   When in doubt about whether a class of work is safety-critical, default to "yes - re-confirm" (fail closed: if classification is uncertain, treat the change as safety-critical).

## In-session self-audit - forget-class reminder (NOT a gate)

For any session that will make code or governance changes, the agent MAY register a recurring self-audit schedule (~4 min) that runs `git status --porcelain` and, if there are edits without a live-transcript `PANEL CONVERGED` / `PRE-EDIT SENTINEL` block for the current change (a block present only in a summary counts as absent), STOPs and re-establishes it from durable §2B evidence or re-runs the panel before any further edits or commit. Re-arm this schedule whenever such a session resumes from a summary, independent of current tree state (the next-commit case starts with a clean tree). Prompt template:

> SELF-AUDIT panel-evidence tripwire. Run `git -C <repo> status --porcelain`. If it shows any modified/added/staged file AND no real `PANEL CONVERGED` / `PRE-EDIT SENTINEL` block is present in your current live transcript for the change those files represent (a block present only in a summary counts as absent): STOP, tell the user the pre-implementation panel's live-transcript proof is missing (possibly lost to summarization, not necessarily skipped), and re-establish it from durable §2B evidence or re-run the panel before any further edits or commit. If a panel IS on record, reply `self-audit: panel on record` and continue. Never take destructive action. Stop the schedule once the change ships.

**Honest ceiling:** this is a REMINDER, not a gate. The schedule *firing* is momentum-independent (the runtime delivers it on a timer), but *honoring* the STOP is the same prose-class discipline. It helps the FORGET-class failure (an honest agent distracted by momentum) and does NOT address the RATIONALIZE-class failure (an agent that rationalized "task approval = panel approval" will dismiss the STOP with the same rationalization) - that is the PRE-EDIT SENTINEL's job (AGENTS.md). The git-time pre-row gate remains the only mechanical backstop. The post-compaction predicate (a summary-only block counts as absent) closes the inherited-all-clear false-negative, but re-arming on resume is itself a skippable prose step - FORGET-class defense-in-depth, not a RATIONALIZE fix.
