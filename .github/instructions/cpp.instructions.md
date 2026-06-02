---
applyTo: "**/*.cpp,**/*.h,**/*.hpp,**/*.cc,**/*.cxx,**/*.c"
---

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

---

## Defensive COM patterns

Apply when implementing COM interface methods — typically classes deriving from `winrt::implements<...>`, `Microsoft::WRL::RuntimeClass<...>`, or hand-rolled `IUnknown` subclasses. Includes shell-extension interfaces (`IExplorerCommand`, `IShellExtInit`, `IContextMenu`, `IThumbnailProvider`, `IPropertyHandler`), MTP/Property handlers, `IClassFactory`, `IDispatch` implementations, and any `STDMETHODIMP` / `IFACEMETHODIMP` you author.

- **Validate `[out]` pointers on entry — every IFACEMETHODIMP / STDMETHODIMP / `winrt::hresult Method(...)` that takes an out pointer MUST `RETURN_HR_IF_NULL(E_POINTER, outParam)` (WIL macro from `wil/result_macros.h`, typically already in your `pch.h` transitively via `wil/win32_helpers.h`) — or its hand-rolled equivalent `if (!outParam) return E_POINTER;` — at the top of the method, BEFORE any other work.** Callers in the COM marshaller, downstream shell host, or another component will pass `nullptr` for an out parameter to probe behaviour or as a bug; the method that proceeds to `*outParam = value;` without the check crashes the host process. The contract is universal: every COM out parameter is implicitly nullable from the callee's perspective even when the IDL marks it `[out, retval]`. Copilot reviewer flags missing checks per-method on sight; expect one comment per unguarded out parameter.
- **Initialize `[out]` pointers immediately after the null check** so callers that ignore the HRESULT but read the out parameter see a documented sentinel (typically `nullptr` for `**` outputs, `0`/`false`/`{}` for `*` outputs) instead of garbage. The standard two-line entry pattern:
  ```cpp
  IFACEMETHODIMP MyCommand::GetTitle(IShellItemArray*, LPWSTR* ppName) noexcept override
  {
      RETURN_HR_IF_NULL(E_POINTER, ppName);
      *ppName = nullptr;
      return SHStrDupW(L"Open with EventLogExpert", ppName);
  }
  ```
  Even on failure paths inside the method, callers expect the out parameter to be valid (i.e., they expect `nullptr`, not garbage left over from the stack).
- **`SHStrDupW` / `StringCchCopyExW` / similar callers MUST zero-init the out first.** `SHStrDupW(L"text", ppOut)` writes into `*ppOut` on success; on failure (allocation failure mid-call) it leaves the value undefined. Callers that branch on `SUCCEEDED(...)` then read the pointer get a wild value. The explicit `*ppName = nullptr;` BEFORE the `SHStrDupW` is load-bearing for the failure path — never skip it on the grounds that "the function will set it anyway."
- **`IFACEMETHODIMP` audit lens — checklist before every COM method ships:**
  1. Every `[out]` param has `RETURN_HR_IF_NULL(E_POINTER, <param>)` at line 1.
  2. Every `[out]` param is assigned a sentinel (`nullptr` / `0` / `{}`) before any other operation can fail.
  3. Every `[out, retval]` `**` (double-pointer) output receives `nullptr`, not `{}`.
  4. Every `[out]` `*` (single-pointer) output receives `0` / `false` / `{}` as appropriate to type.
  5. Every method is `noexcept` (or wrapped in `try { ... } CATCH_RETURN()`) — a C++ exception that escapes an IFACEMETHODIMP boundary triggers UB across the COM marshalling layer.
- **Why this matters more in shell extensions than in arbitrary COM:** the Explorer host loads your DLL in-process and calls every interface method via the marshaller's interception layer. A `*nullptr = value` deref crashes `explorer.exe`, which displays a "your shell extension is misbehaving" Watson dialog. Windows may then auto-disable the entry under `HKCU\Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked` with no telemetry path back to you. The cost of a missing null check is your extension getting silently disabled on user machines.

---

## vcxproj configuration

These rules apply to `*.vcxproj`, `*.vcxproj.filters`, `Directory.Build.props` covering C++ projects, and any custom MSBuild targets that drive native builds. See also `msbuild.instructions.md` for language-agnostic MSBuild rules (property functions, Exec output capture, locked-down build envs).

- **`<PlatformToolset>` — prefer `$(DefaultPlatformToolset)` over a hardcoded version.** Hardcoding `v143` / `v145` / a specific toolset version pins the project to one Visual Studio install: developers on a newer VS or CI runners with only the older toolset installed get a `MSB8020` / `error MSB8036` build failure (`The build tools for vNNN cannot be found`). `$(DefaultPlatformToolset)` resolves to whatever the current VS install ships, which is forward- and backward-portable across the supported VS range. Pin a specific toolset version ONLY when the project's binary contract genuinely requires it (e.g., interop with a third-party C++ component built against a specific toolchain). Document the rationale in an XML comment when you do.
- **`<WindowsTargetPlatformVersion>10.0</WindowsTargetPlatformVersion>` over a pinned `10.0.22621.0`** — same rationale. Pinning a Windows SDK version requires every developer machine and CI runner to have that exact SDK installed; the bare `10.0` lets VS pick the latest installed SDK and is the modern default.
- **Configurations × platforms must enumerate explicitly and consistently across sibling projects.** Every `<ProjectConfiguration>` entry in the `ProjectConfigurations` ItemGroup must exist for every `Configuration` × `Platform` cross product the project supports. Adding `arm64` to one project but not to a sibling shared library produces a confusing "no rule to make ARM64" build error at the consuming side. When you add a new platform to one `.vcxproj`, sweep all siblings.
- **Audit lens:** before checking in a `.vcxproj`, `rg "v14[0-9]|10\.0\.\d{5}" path/to/file.vcxproj` — every match is a candidate for replacement with the `$(DefaultPlatformToolset)` / bare `10.0` defaults unless an immediately-preceding XML comment documents the pin rationale.
