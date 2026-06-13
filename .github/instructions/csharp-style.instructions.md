---
applyTo: "**/*.cs,**/*.csx,**/*.csproj,**/*.razor,**/*.razor.cs,**/*.cshtml,**/*.aspx"
---

# C# / .NET Code Style Instructions

> **Scope:** loaded on C# / Razor / project files. Contains naming conventions, formatting, member ordering, expression/block preferences, using directives, redundant qualifiers. Siblings: `csharp.instructions.md`, `csharp-runtime.instructions.md`, `csharp-smells.instructions.md`.

---
## C# / .NET Code Style

### Naming Conventions (Microsoft .NET Guidelines)

- **Interfaces:** prefix with `I`, PascalCase (`IUserRepository`).
- **Types** (classes, structs, enums): PascalCase (`UserRepositoryBase`).
- **Public/Internal/Protected members** (properties, methods, events): PascalCase (`GetUser`).
- **Private instance fields:** `_camelCase` (`_logger`, `_cache`).
- **Private static fields:** `s_camelCase` (`s_defaultOptions`).
- **Thread-static fields:** `t_camelCase`.
- **Const fields (class-level):** PascalCase (`DefaultTimeout`).
- **Public/Internal fields:** PascalCase (`CustomerDetails`) - but prefer properties over public fields.
- **Protected fields:** avoid; use protected properties to maintain encapsulation for derived classes.
- **Parameters and local variables:** camelCase (`userRecord`, `returnValue`). **Locals must not share an identifier with the type name (any casing variant).** `var Filter = new Filter(...)` is forbidden - the local shadows the type token, makes assertions like `Filter.IsX` ambiguous (type access vs instance member), and reads as a copy-paste oversight on review. Use a distinguishing name (`filter`, `appliedFilter`, `sut`). Same rule applies when the same scope already has a different-typed lowercase `filter` - rename the other local (e.g., `savedFilter` for the `SavedFilter` input) to free `filter` for the type-under-test. Caught deterministically by `post-code-change.md` step 2.5.
- **Local constants:** camelCase, same as local variables (`maxRetryCount`).
- **Type parameters:** prefix with `T`, PascalCase (`TResult`).
- **Abbreviations:**
  - Two-letter acronyms: UPPERCASE (`IO`, `ID`, `DB`).
  - Three+ letter acronyms: PascalCase (`Xml`, `Json`, `Html`).
  - In camelCase context: `userId`, `xmlParser`, `htmlContent`.

### Type Suffix Conventions

Type suffixes carry semantic weight. Pick a suffix only when it conveys information the bare type name cannot - default to no suffix (BCL precedent: `DateTime`, `Uri`, `Stopwatch`). Standard .NET framework suffixes (`Exception`, `Attribute`, `EventArgs`, `EventHandler`, `Async`) remain mandatory per Microsoft Framework Design Guidelines.

- **`Model` suffix:** reserved for *schema/template* types - definitions of what data looks like (provider message templates, DTO shape definitions, ORM entity templates). Runtime/domain types drop the suffix. Examples: `EventModel`/`MessageModel` keep it (they ARE provider message-template definitions); `ResolvedRecord` (was `ResolvedRecordModel`) drops it (runtime carrier of a resolved event). `Model` is otherwise an MVC convention (`*ViewModel`/`*PageModel`), not a general naming rule. **Review action:** when a `*Model` type is found whose role is runtime state, behavior, or carrying resolved/derived data (not describing data shape), surface a rename suggestion as part of the review - do not let the suffix slip into runtime types unchallenged.

### Code Formatting

- 4 spaces for indentation (no tabs).
- File-scoped namespaces.
- Opening braces on new lines (Allman style).
- Use `var` only when the type is evident from a **non-constructor** right-hand side (LINQ, casts, expressions). For object instantiation use `Type x = new()` - never `var x = new Type()` (RHS type is redundant) or `Type x = new Type()` (type-on-both-sides). The LHS type doubles as documentation; target-typed `new()` drops the redundant repeat.
- Use collection expressions (`[]`) over `new List<T>()` / `new T[0]` / `Array.Empty<T>()` / `Enumerable.Empty<T>()`. Prefer `List<X> items = [];` and `int[] empty = [];` (target-typed; same LHS-as-documentation rationale as above).
- **Prefer the C# 14 `extension(receiver)` block syntax** over the conventional `this`-parameter style for new extension methods. The block form groups related extensions on the same receiver, makes the receiver name reusable across multiple methods, and aligns with future-direction extension features (extension properties, extension constructors). Convert conventional `this`-style extensions to the block form when touching the file for another reason; do not sweep untouched files purely for the conversion.
  ```csharp
  // Preferred
  internal static class FooExtensions
  {
      extension(IServiceCollection services)
      {
          public IServiceCollection AddX() { services.AddSingleton<...>(); return services; }
          public IServiceCollection AddY() { services.AddSingleton<...>(); return services; }
      }
  }

  // Legacy (acceptable for untouched files, but convert when touched)
  internal static class FooExtensions
  {
      public static IServiceCollection AddX(this IServiceCollection services) { ... }
      public static IServiceCollection AddY(this IServiceCollection services) { ... }
  }
  ```
  Visibility: the wrapping class must be `public` if any consumer outside the declaring assembly calls the extension; the `extension(...)` block's methods must each declare their own access modifier (typically `public`). Bot reviewers that flag the block syntax as "inconsistent with the conventional style elsewhere" are pre-empted by this project preference - dismiss the finding and (when in scope) convert the conventional file rather than reverting the block-syntax file.
- Use expression-bodied members when applicable (methods, properties, accessors, constructors, local functions).
- Require braces for `if`, `for`, `foreach`, `while` statements.
- No `this.` qualification unless necessary.
- Use language keywords over BCL types (`string` not `String`).
- Modifier order: `public, private, protected, internal, file, static, extern, new, virtual, abstract, sealed, override, readonly, unsafe, required, volatile, async`.
- Max 1 blank line between declarations and inside code blocks.
- Place `while` on a new line in `do-while` statements.
- Insert a final newline in every file.
- Namespace must match folder structure.

### Member Ordering (StyleCop Layout) - mandatory pre-commit

Source: ReSharper StyleCop Layout (priority 150), applied via the user's `Joe: Apply file layout` cleanup profile (`CSReorderTypeMembers` + `CSOptimizeUsings` enabled - sorts/prunes usings as a side effect; no other formatting touched). Invoke: `jb cleanupcode --settings="<path>\ReSharper.DotSettings" --profile="Joe: Apply file layout" --include="<files>" --no-build <solution>` (`JetBrains.ReSharper.GlobalTools` global tool provides `jb`).

**Kind order** (top-to-bottom): Constants → Static fields → Instance fields → Constructors/destructors → Delegates → Events → Enums → Interfaces → Properties → Indexers → Methods → Operators → Nested structs → Nested classes. For Events / Properties / Indexers / Methods: Public group first, then Interface-impl group, then Other group.

**Sort within entry:**

- Public events / properties / indexers / methods: Static → Name.
- Interface-impl events / properties / indexers / methods: ImmediateInterface → Name.
- Other events / properties / indexers / methods + Constants / Fields / Enums / Interfaces / Delegates / Operators: Access (Internal → ProtectedInternal → Protected → Private) → Static (where applicable) → Readonly (fields only) → Name.
- Constructors / destructors: Static → Kind (Constructor → Destructor) → Access. *No name sort.*
- Nested structs / nested classes: Static → Access → Name.

**Mandatory rename hygiene:** Every rename shifts the member's alphabetical position within its (kind, access, static) bucket. Re-run `Joe: Apply file layout` on touched files before staging, OR move manually. Reviewers (human and bot) flag out-of-position members on sight - most common rename-PR round-N comment. Self-check when the tool is unavailable: list members per access bucket and confirm alphabetical.

### Expression Preferences

- Prefer pattern matching over `as`/`is` with null checks.
- Prefer null propagation (`?.`) and coalesce (`??`) operators.
- Prefer object/collection initializers.
- Prefer conditional expressions for simple assignments/returns.
- Prefer switch expressions over switch statements.
- Prefer the `not` pattern (e.g., `is not null`).
- Prefer extended property patterns.
- Prefer `is null` over `ReferenceEquals`.
- Prefer explicit tuple names over `Item1`, `Item2`.
- Prefer inferred tuple and anonymous type member names.
- Prefer simplified boolean expressions.
- Prefer simplified interpolation.
- Prefer auto-properties.
- Prefer compound assignment (`+=`, `-=`, etc.).
- Prefer index operator (`^1`) and range operator (`..`).
- Prefer local functions over anonymous functions.
- Prefer method group conversion.
- Prefer simple `default` expression (`default` not `default(T)`).
- Prefer deconstructed variable declarations.
- Prefer target-typed `new()` when type is evident - `Type x = new()` over `var x = new Type()` (see Code Formatting above).
- Prefer inline variable declarations (`out var`).
- Prefer tuple swap.
- Prefer UTF-8 string literals where applicable.
- Prefer throw expressions.
- Use `nameof(X)` over hardcoded identifier strings (log/trace/exception messages, attribute args, debug output) - survives renames; mandatory for any type/member/parameter/namespace name appearing in a string literal.
- Use discards for unused values.

### Code Block Preferences

- Prefer simple `using` statements (without braces) when possible.
- Prefer top-level statements for `Program.cs`.
- Prefer static local functions when not capturing variables.
- Use the conditional delegate call (`?.Invoke()`).

### Field, Parameter, and Modifier Preferences

- Mark fields as `readonly` when possible.
- Treat unused parameters as warnings (do not silently leave them).
- Always specify accessibility modifiers (except for interface members).

### Parentheses

- Use parentheses for clarity in arithmetic, binary, and relational operators.
- Omit parentheses only when obviously unnecessary.

### Using Directives

- Place `using` directives **outside** the namespace.
- Don't separate import groups.
- Don't prioritize System directives first.
- **A file MUST NOT `using` its own declared namespace.** Self-namespace imports (`using Acme.Feature.Parsing;` inside a file declared `namespace Acme.Feature.Parsing;`) are redundant and a smell - they read as "the author was unsure where the type lives" and reviewers always flag them. The compiler resolves same-namespace types without any `using`. IDE0005 catches this when `EnforceCodeStyleInBuild` is on; for repos without that, `post-code-change.md` step 2.5 includes a grep check: `rg '^using ([\w.]+);' <file.cs>` cross-referenced against the file's `namespace X;` declaration.
- **When sorting / removing usings, the formatter must respect the repo's `.editorconfig` AND any ReSharper `.DotSettings` overrides.** Specifically, honor `dotnet_separate_import_directive_groups`, `dotnet_sort_system_directives_first`, and `csharp_using_directive_placement`. Use `dotnet format` (which honors `.editorconfig` natively) or ReSharper / Rider cleanup with the solution's settings. Do NOT use a tool that defaults to "System first" sorting and ignores `.editorconfig` - it produces a churn diff that fights the project convention. If you cannot determine which tool is in use, do NOT bulk-resort usings; only remove the genuinely unused entries and leave the order alone. The same rule applies to manual edits: never re-order existing using lines just because one block "looks tidier" - the convention is whatever the project's `.editorconfig` says, period.
- **Pre-commit cleanup is whole-solution scope, not just the diff's touched files.** A file move, namespace change, or rename refactor leaves stale `using` directives and over-qualified type references in *consumer* files that the diff doesn't list. The post-code-change hygiene step (`post-code-change.md` step 1) runs `dotnet format style <slnx-or-csproj> --no-restore --severity warn --diagnostics IDE0001 IDE0002 IDE0005 IDE0065` over the whole solution, then `--verify-no-changes` to confirm. Restrict to the using/qualifier diagnostics - a blanket `dotnet format --severity info` triggers unrelated style fixers (collection initializers, expression preferences, member ordering) and produces a churn diff. If `.editorconfig` has these diagnostics at default `silent` severity AND the project lacks `<EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>`, IDE0005 in particular is silent and the cleanup is a no-op - temporarily append `dotnet_diagnostic.IDE000{1,2,5,65}.severity = warning` to `.editorconfig` for the cleanup pass, then restore the original. Propose the permanent fix (severity entries or `EnforceCodeStyleInBuild`) to the user when the workaround fires twice on the same repo.

### Redundant Qualifiers

- **Prefer the shortest unambiguous prefix.** A fully-qualified `Acme.UI.Store.SomeTable.CloseAllAction` should be simplified to `SomeTable.CloseAllAction` when `Acme.UI.Store.SomeTable` (or a parent) is in scope via a `using` directive or sibling-namespace lookup. The compiler resolves short-prefixed names through name lookup that walks up the namespace hierarchy from the file's own namespace, so a sibling-namespace short prefix is enough for disambiguation in collision cases - full qualification is noise. The IDE0001 (Simplify name) diagnostic catches this; running `dotnet format` per the using-directive rule above fixes it automatically.
- **Reserve full qualification for genuine name-collision-with-no-shorter-form cases** (rare in practice - usually a parent namespace import resolves the collision with one extra prefix segment, not the full path).

