---
applyTo: "**/*.cpp,**/*.h,**/*.hpp,**/*.cc,**/*.cxx,**/*.c"
---

<!-- CopilotInstructions: SENTINEL cpp -->

# C++ Instructions

> **Scope:** loaded automatically when the working set contains C/C++ source or header files. Extends the always-loaded `AGENTS.md` core.

---

## C++ Code Style

### Naming Conventions (Microsoft C++ Guidelines)

- **Classes and structs:** PascalCase (`UserRepository`, `CustomerData`).
- **Interfaces:** prefix with `I`, PascalCase (`IRequestHandler`).
- **Functions and methods:** PascalCase (`ProcessRequest`, `GetValue`).
- **Public member variables:** PascalCase (`CustomerId`, `CustomerName`).
- **Private/protected member variables:** `m_` prefix with camelCase (`m_requestCount`, `m_isInitialized`).
- **Static member variables:** `s_` prefix with camelCase (`s_instanceCount`).
- **Global variables:** `g_` prefix with camelCase (`g_configuration`).
- **Constants and macros:** SCREAMING_SNAKE_CASE (`MAX_BUFFER_SIZE`, `DEFAULT_TIMEOUT`).
- **Enums:** PascalCase for type, PascalCase for values (`enum class LogLevel { Info, Warning, Error }`).
- **Namespaces:** PascalCase (`MyApp::Core`).
- **Template parameters:** prefix with `T`, PascalCase (`TResult`, `TAllocator`).
- **Parameters and local variables:** camelCase (`userRecord`, `bufferSize`).
- **Typedefs and using aliases:** PascalCase (`using RequestList = std::vector<Request>`).

### Code Formatting

- 4 spaces for indentation (no tabs).
- Opening braces on new lines (Allman style).
- Require braces for `if`, `for`, `while`, `do-while` statements.
- Use `#pragma once` for header guards.
- Sort `#include` directives: standard library first, then third-party, then project headers.
- Use `nullptr` instead of `NULL` or `0`.
- Use `auto` when type is evident from initialization.
- Prefer `enum class` over plain `enum`.
- Use `const` and `constexpr` where applicable.
- Max 1 blank line between declarations.
- Insert a final newline in every file.

### Member Ordering

1. Public types (nested classes, enums, typedefs)
2. Public static members
3. Public constructors and destructor
4. Public methods
5. Public member variables (prefer accessors)
6. Protected members (same order as public)
7. Private members (same order as public)
