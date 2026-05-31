# Cross-file bug investigation — Lane catalog

Lane definitions for `cross-file-bug-investigation.md`. Each lane defines a specialized review focus that a panel reviewer can be assigned (round-robin lane-to-slot mapping; doubled-up per-slot when `lanes_selected > reviewers`).

## Per-lane schema

Each lane entry follows this exact section structure:

- `### <Lane name>`
- **Slug**: machine-readable identifier
- **Primary focus**: bullet list of what the reviewer hunts for (3-7 bullets)
- **May overlap with**: sibling lanes; defer-to clarifications when overlap exists
- **Triggering symptoms** (auto-select): which intake-Q2 symptoms auto-select this lane
- **Reviewer prompt clause** (≤200 words): the paragraph injected into the multi-model-review.md sub-agent prompt template for this lane
- **Cross-references**: AGENTS.md sections + sibling playbooks the lane draws from

## Lanes

### Cross-file data flow

- **Slug**: `cross-file-data-flow`
- **Primary focus**:
  - Argument threading across N call layers (parameter shadowing per §3.6)
  - State predicates spanning multiple types (§3.7)
  - Sibling-producer parity (§3.10 — multiple producers emit the same record/DTO type)
  - Shared-property defaults (settable property with invalid sentinel default + downstream branch)
  - Cross-orchestrator missing-loop-CT-checks
- **May overlap with**:
  - `contracts-and-state` — for state predicate COMPLETENESS checks (defer to contracts)
  - `recurring-smells-and-hygiene` — for §3.10-catalog smell pattern matching when broader than data flow
- **Triggering symptoms** (auto-select): `behavior-bug`, `crash`, `race-or-deadlock`, `memory-or-leak`, `security-or-trust`, `unclear-behavior`. **Default-on for ALL investigations** (namesake of the playbook).
- **Reviewer prompt clause**:

  > You are hunting cross-file data-flow bugs. Look for: arguments that change meaning across call layers (a parameter named `x` at the top means one thing, the same name at the bottom means another); state predicates that span multiple types where a contributing field is missing; settable properties on shared record/DTO types where one producer stamps the field and another doesn't (invalid sentinel defaults); orchestrator-layer loops that forget to check the loop CT inside the body; data-flow paths where a value is computed correctly but propagated incorrectly (off-by-one in indexing, wrong dictionary key derivation, etc.). For every claim, cite each implicated file independently (e.g., a finding about field-X-missing-in-producer-2 needs citations to producer-1 setting it AND producer-2 not setting it AND the consumer branching on it). Severity blocking when the bug causes wrong output or wrong control flow; major when it can cause wrong output under specific runtime conditions; minor when it's a hygiene problem with no observable runtime impact.

- **Cross-references**: AGENTS §3.6 (Defaults and Consistency — parameter consistency), §3.7 (state predicates), §3.10 (sibling-producer parity, status-enum collapse), `multi-model-review.md` (target-type `bug-investigation`).

### Concurrency and races

- **Slug**: `concurrency-and-races`
- **Primary focus**:
  - Async ordering bugs (await missed; fire-and-forget; ContinueWith chained incorrectly)
  - Cancellation token propagation (CT not threaded through all awaits; loop-CT-checks)
  - Lock-ordering (consistent acquisition order across all writers; deadlock risk)
  - TOCTOU (time-of-check vs time-of-use) patterns
  - Idempotency guards on shared state (§3.8)
  - Double-dispatch / double-handler issues
- **May overlap with**:
  - `lifecycle-and-resources` — for idempotency-first ref handoff during disposal (defer to lifecycle)
  - `cross-file-data-flow` — for missing-loop-CT-checks at orchestrator layer (defer to cross-file-data-flow for orchestrator; keep for awaiter layer)
- **Triggering symptoms** (auto-select): `crash`, `race-or-deadlock`.
- **Reviewer prompt clause**:

  > You are hunting concurrency and race bugs. Look for: async methods missing await; cancellation tokens not threaded through every awaitable in the chain; loop bodies that await without re-checking the loop CT; lock acquisition order that varies between writers (deadlock risk); TOCTOU patterns (check-then-act with a window for state to change); `seen.Add(x)` / `_processed[id] = true` before the work succeeds (idempotency violation per §3.8); event handlers / message dispatchers that can fire the same logical event twice. For every claim, cite ALL participating files (producer, consumer, sync primitive). Severity blocking when reproduction-confirmed deadlock or wrong-state corruption is possible; major when the race is theoretically possible but rare; minor when only style.

- **Cross-references**: AGENTS §3.8 (Defer state mutations until after success), §3.10 (idempotency / multi-dispatcher guards).

### Error handling and failures

- **Slug**: `error-handling-and-failures`
- **Primary focus**:
  - Swallowed exceptions (catch without rethrow / log / surface)
  - Fallback gaps (try-fallback-path with no terminal handler when fallback also fails)
  - Error-state-on-success (success path doesn't clear prior error fields per §3.8)
  - Log-vs-behavior mismatch (§3.10 — log says "Falling back" but guard suppresses fallback)
  - Exception-message hygiene (§3.10 — empty message after parameter removal)
- **May overlap with**:
  - `lifecycle-and-resources` — for disposal-in-catch patterns (defer to lifecycle)
- **Triggering symptoms** (auto-select): `crash`, `behavior-bug`.
- **Reviewer prompt clause**:

  > You are hunting error-handling and failure-path bugs. Look for: catch blocks that swallow exceptions (empty body, log-only without rethrow, generic-Exception swallow); fallback paths where the fallback itself can throw with no terminal handler; success paths that don't clear stale error state from prior runs; log messages that say "doing X" when guards prevent X from happening; exception messages reduced to `string.Empty` after a parameter removal (per §3.10); validation methods that return false silently when the caller treats false as "valid"; retry loops that retry indefinitely without backoff or max-attempts cap. For every claim, cite ALL participating files (throw site, catch site, caller, downstream consumer). Severity blocking when a real exception class will be silently dropped; major when error-vs-success state ambiguity exists; minor when only log text is misleading.

- **Cross-references**: AGENTS §3.8 (defer state mutations / error-state-on-success), §3.10 (log-vs-behavior mismatch / exception-message hygiene).

### Lifecycle and resources

- **Slug**: `lifecycle-and-resources`
- **Primary focus**:
  - Disposal ordering (IDisposable / IAsyncDisposable / using / finally)
  - Registration ordering (interop registration before native call; subscription before publish)
  - Idempotency-first ref handoff (§3.8 — assign long-lived ref BEFORE early-return guard)
  - AbortController pairing (JS/TS — every fetch has a controller; controller.abort() on cleanup)
  - DotNetObjectReference disposal (Blazor JS interop)
  - Native handle release (Win32 / P/Invoke / unmanaged resources)
- **May overlap with**:
  - `concurrency-and-races` — for idempotency guards on shared state (defer to concurrency)
- **Triggering symptoms** (auto-select): `crash`, `memory-or-leak`.
- **Reviewer prompt clause**:

  > You are hunting lifecycle and resource-management bugs. Look for: IDisposable/IAsyncDisposable types that aren't disposed (no using, no try/finally); ref-handoff in early-return paths where the second caller sees null and the first caller's ref leaks; subscriptions made before the publisher is fully constructed (race-on-init); JS interop where fetch happens without an AbortController paired for cleanup; Blazor components that hold DotNetObjectReference without disposing it on OnDispose; native handles (Win32 HANDLE, file descriptors, GDI objects) released only on the happy path; finalizers that depend on managed state. For every claim, cite ALL participating files (allocation site, disposal site, exception path, parallel construction site). Severity blocking when a real resource leak or use-after-free is possible; major when leak is bounded but not zero; minor when only style.

- **Cross-references**: AGENTS §3.8 (idempotency-first ref handoff), C#/Blazor instructions (IAsyncDisposable, AbortController pairing).

### Contracts and state

- **Slug**: `contracts-and-state`
- **Primary focus**:
  - Interface vs impl disagreement (impl behavior differs from interface contract / xmldoc)
  - Status-enum collapse (§3.10 — one enum value used for multiple semantic outcomes)
  - State predicate completeness (§3.7 — every member enumerated in the predicate)
  - Match-equality uniqueness (§3.7 — could two domain-distinct objects compare equal?)
  - Parameter consistency across interface chain (§3.6 — same name, same meaning, all layers)
- **May overlap with**:
  - `cross-file-data-flow` — for state predicate FIELD-coverage (defer to cross-file-data-flow for which fields; keep for completeness)
- **Triggering symptoms** (auto-select): `behavior-bug`, `unclear-behavior`.
- **Reviewer prompt clause**:

  > You are hunting contract and state-predicate bugs. Look for: interface members where the impl returns different conditions than the xmldoc claims; status enums where the same value (e.g., `Loaded`) is returned from N distinct outcomes that callers might branch on differently (§3.10); state predicates (IsEmpty, IsDefault, Equals) that miss a contributing member; match-equality predicates where two domain-distinct objects compare equal in the broadest realistic context; parameters that change meaning across the call chain (interface says X, impl interprets X differently). For every claim, cite ALL participating files (interface declaration, impl, every consumer that branches on the value, every sibling impl that might disagree). Severity blocking when a real consumer is broken by the contract mismatch; major when a future consumer could be broken; minor when only style.

- **Cross-references**: AGENTS §3.6 (parameter consistency), §3.7 (state predicates / match-equality uniqueness), §3.10 (status-enum collapse).

### Security and surface

- **Slug**: `security-and-surface`
- **Primary focus**:
  - Authentication / authorization gaps (token check missing on a path)
  - Input validation (untrusted input flowing to a sensitive sink without check)
  - Native interop return-value validation (P/Invoke / LoadLibrary returning NULL not checked)
  - LoadLibraryEx DLL planting (csharp — load order / rooted path / search-path manipulation)
  - Unsafe deserialization (BinaryFormatter / typename-driven deserializers)
  - Cross-references LPA for visibility-axis concerns (does NOT duplicate the 6 LPA axes)
- **May overlap with**:
  - `least-privilege-audit.md` — full 6-axis visibility/mutability sweep (refer user out)
- **Triggering symptoms** (auto-select): `security-or-trust`.
- **Reviewer prompt clause**:

  > You are hunting security and surface-area bugs. Look for: authentication checks present on most paths but missing on one; input validation that catches some inputs but not others (encoding bypass, path traversal, SQL injection); native interop calls whose return values aren't checked (LoadLibrary returning NULL, P/Invoke returning a failure code that's ignored); LoadLibraryEx calls without absolute path + appropriate search flags (DLL planting risk per the csharp instructions); deserializers that accept arbitrary type names; secrets in logs / exception messages / telemetry. For every claim, cite ALL participating files (entry point, validation site or absence, sink, audit log if any). Severity blocking when a real exploit is possible; major when the issue weakens defense-in-depth; minor when only audit/logging hygiene. Do NOT duplicate `least-privilege-audit.md`'s 6-axis visibility sweep; recommend that playbook for visibility-only concerns.

- **Cross-references**: csharp instructions (native interop return-value validation, LoadLibraryEx DLL planting), `least-privilege-audit.md` (cross-ref only; no duplication).

### DB and persistence

- **Slug**: `db-and-persistence`
- **Primary focus**:
  - DB transaction boundaries (commit before all writes complete; rollback path missing)
  - Isolation levels (read-committed vs snapshot; lock escalation)
  - EF change-tracking (entities tracked across context boundaries; detached-then-modified)
  - N+1 query patterns (loop with per-iteration query)
  - Optimistic-concurrency stamps (rowversion / etag drift)
  - Repository contract leaks (IQueryable escaping the repository; lazy-load surprise)
  - File format versioning (header stamp / migration path)
  - Blob etag / lease races (read-modify-write without compare-and-swap)
  - Queue idempotency keys (message replay handling)
  - Schema migration safety on durable artifacts
- **May overlap with**:
  - `concurrency-and-races` — for general TOCTOU outside DB (defer to concurrency)
- **Triggering symptoms** (auto-select): `performance-degradation` (when user insists on bug-hunt vs benchmark route).
- **Reviewer prompt clause**:

  > You are hunting DB and persistence bugs. Look for: SaveChanges/Commit calls that fire before all dependent writes complete; transactions opened but not closed on exception paths; isolation levels that allow phantom reads when the code assumes serializable; EF entities passed across DbContext boundaries (detached-then-modified); loops that issue a query per iteration (N+1); optimistic concurrency stamps (rowversion / Etag) that aren't compared on update; IQueryable escaping repository abstractions; durable file formats without version stamps or migration path; blob writes without etag compare-and-swap; queue handlers without idempotency keys. For every claim, cite ALL participating files (entity definition, repository, consumer, schema/migration). Severity blocking when a real data-loss or wrong-data scenario is possible; major when concurrency anomaly is possible under load; minor when only style.

- **Cross-references**: AGENTS §3.7 (state predicates can apply to entity equality), framework-specific (EF / Dapper / NHibernate / etc. — match the repo).

### Build and generated

- **Slug**: `build-and-generated`
- **Primary focus**:
  - Build-system bugs with cross-file impact (msbuild item-group regressions, Conditional-PackageReference misfires)
  - GitHub Actions / Azure Pipelines YAML semantics (matrix expansion, fail-fast, secret scoping)
  - T4 / Roslyn source generators producing wrong code from valid input
  - OpenAPI / Swagger generated clients with contract drift from server
  - gRPC stubs / protobuf generated types with version skew
  - Generated code consumed by ≥2 callsites where the generator's input changed
- **May overlap with**:
  - `code-review` (sub-agent) for single-file generated-code review (refer user out)
- **Triggering symptoms** (auto-select): none — explicit user pick only (no symptom auto-selects this lane).
- **Reviewer prompt clause**:

  > You are hunting build-system and generated-code bugs. Look for: msbuild item-groups that exclude/include the wrong files after a refactor; Conditional-PackageReference / ItemGroup conditions that silently misfire on certain build configurations; GitHub Actions YAML where matrix variables expand differently than the author intended; T4 / Roslyn source generators emitting code that compiles but is semantically wrong; OpenAPI clients whose contract has drifted from the server's actual response shape; gRPC / protobuf generated types with field-number reuse or version mismatch; generated code consumed by multiple call sites where the generator's input has changed without all consumers regenerating. For every claim, cite ALL participating files (generator input, generator output, every consumer, CI config if applicable). Severity blocking when build is wrong or runtime is wrong; major when behavior differs across environments; minor when only style. Defer single-file generated-code review to the `code-review` sub-agent.

- **Cross-references**: csharp instructions (csproj item-group conventions), framework-specific (Roslyn generators, OpenAPI tooling).

### Recurring smells and hygiene

- **Slug**: `recurring-smells-and-hygiene`
- **Primary focus**:
  - The full §3.10 catalog applied with cross-file scope
  - Constants-single-source-of-truth violations (literal duplication across files)
  - Sibling-constant consistency (group of related constants with one outlier)
  - Test specificity (Arg.Any when the test's purpose is verifying what was passed)
  - Dead branches inside loops with redundant termination conditions
  - Sibling-producer parity (§3.10 — already in cross-file-data-flow; here for broader smell pattern)
  - Status-enum collapse (§3.10 — already in contracts-and-state; here for broader smell pattern)
- **May overlap with**:
  - `cross-file-data-flow` — for sibling-producer parity (defer to cross-file-data-flow)
  - `contracts-and-state` — for status-enum collapse (defer to contracts-and-state)
- **Triggering symptoms** (auto-select): none — explicit user pick only (NOT auto-defaulted at ≥3 files; opt-in only).
- **Reviewer prompt clause**:

  > You are hunting recurring code smells from the §3.10 catalog with cross-file scope. Look for: literal values duplicated across files that should be a named constant (drift risk); groups of related constants where one has different formatting/punctuation/casing/units; tests using Arg.Any / It.IsAny when the test's purpose is verifying what was passed; dead branches inside loops where the loop's own condition already excludes the state; method bodies whose doc-summary terminology hasn't been updated after the helper's scope widened; helper methods that hardcode a parameter the caller threads through (asymmetric semantics). For every claim, cite ALL participating files (e.g., a constant-drift finding needs each duplicate site cited). Severity blocking when a real divergence is observable; major when divergence is latent and one-edit-away; minor when only style. Defer per-finding overlap with cross-file-data-flow (sibling-producer parity) and contracts-and-state (status-enum collapse) to those lanes.

- **Cross-references**: AGENTS §3.10 (Recurring code smells from past PR reviews).

## Lane-symptom auto-select truth table

| Symptom | Auto-selected lanes |
|---|---|
| `behavior-bug` | `cross-file-data-flow` + `contracts-and-state` + `error-handling-and-failures` |
| `crash` | `cross-file-data-flow` + `error-handling-and-failures` + `lifecycle-and-resources` + `concurrency-and-races` |
| `race-or-deadlock` | `cross-file-data-flow` + `concurrency-and-races` |
| `memory-or-leak` | `cross-file-data-flow` + `lifecycle-and-resources` |
| `security-or-trust` | `cross-file-data-flow` + `security-and-surface` |
| `performance-degradation` | (intake first offers route to `performance-comparison.md`; if user insists on bug-hunt: `cross-file-data-flow` + `db-and-persistence`) |
| `unclear-behavior` | `cross-file-data-flow` + `contracts-and-state` |
| `other` | user-driven; default `cross-file-data-flow` only |

`build-and-generated` and `recurring-smells-and-hygiene` are explicit-user-pick only — no symptom auto-selects these two.

## Notes for lane authors (when adding a 10th+ lane in future cycles)

1. Pick a slug that doesn't overlap a sibling lane's slug.
2. Document `May overlap with` BEFORE writing the prompt clause — if the overlap is large enough to confuse reviewers, consolidate instead of adding a new lane.
3. Keep prompt clause ≤ 200 words. Reviewers receive multiple lane clauses (round-robin doubled-up); long clauses dilute focus.
4. Auto-selecting from a symptom is a strong commitment — `cross-file-data-flow` is the only default-on lane. Add a new auto-selection only if the lane is essential for the symptom (not just useful).
5. Cross-reference AGENTS sections + sibling playbooks; do NOT inline content from those sources (cite + defer).
