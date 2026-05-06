---
applyTo: "**/*.ts,**/*.tsx,**/*.mts,**/*.cts,**/*.js,**/*.jsx,**/*.mjs,**/*.cjs"
---

<!-- CopilotInstructions: SENTINEL jsts -->

# JavaScript / TypeScript Instructions

> **Scope:** loaded automatically when the working set contains JS/TS source files. Extends the always-loaded `AGENTS.md` core.

---

## JavaScript / TypeScript Code Style

### Naming Conventions

- **Classes:** PascalCase (`UserRepository`, `DataProvider`).
- **Interfaces:** PascalCase, do **NOT** prefix with `I` (`RequestHandler`, `Config`).
- **Type aliases:** PascalCase (`UserList`, `CallbackFn`).
- **Enums:** PascalCase for type and values (`LogLevel.Info`).
- **Functions and methods:** camelCase (`processRequest`, `getValue`).
- **Properties and variables:** camelCase (`userCount`, `isEnabled`).
- **Constants:** SCREAMING_SNAKE_CASE for true constants, camelCase for `const` variables (`MAX_RETRIES` vs `const userName`).
- **Private members:** prefix with `_` (`_internalState`) or use `#` for true private fields.
- **Parameters:** camelCase (`userRecord`, `callbackFn`).
- **Type parameters:** prefix with `T`, PascalCase (`TResult`, `TItem`).
- **File names:** camelCase or kebab-case (`userRepository.ts` or `user-repository.ts`).
- **Abbreviations:** same as C# — two-letter uppercase, three+ letter PascalCase.

### Code Formatting

- 4 spaces for indentation (no tabs).
- Opening braces on the same line (K&R style).
- Require braces for `if`, `for`, `while` statements.
- Use single quotes for strings (or template literals).
- Always use semicolons.
- Use `const` by default, `let` when reassignment is needed, never `var`.
- Prefer arrow functions for callbacks.
- Use strict equality (`===` and `!==`).
- Max 1 blank line between declarations.
- Insert a final newline in every file.
- Max line length: 120 characters.

### Expression Preferences

- Prefer template literals over string concatenation.
- Prefer destructuring for objects and arrays.
- Prefer the spread operator over `Object.assign` or `Array.concat`.
- Prefer `async/await` over raw Promises.
- Prefer optional chaining (`?.`) and nullish coalescing (`??`).
- Prefer object shorthand properties.
- Prefer arrow functions for inline callbacks.
- Use `Array.map`, `filter`, `reduce` over manual loops when appropriate.

### Imports / Exports

- Use ES6 `import`/`export` syntax.
- Group imports: external packages first, then internal modules.
- Prefer named exports over default exports.
- Sort imports alphabetically within groups.
