---
applyTo: "**/*.csproj,**/*.targets,**/*.props,**/*.vcxproj,**/*.vcxproj.filters,**/Directory.Build.props,**/Directory.Build.targets,**/Directory.Packages.props"
---

# MSBuild Instructions

> **Scope:** loaded automatically when the working set contains MSBuild project files (`*.csproj`, `*.vcxproj`), targets files, props files, or `Directory.Build.*` / `Directory.Packages.props` infrastructure files. Language-agnostic; complements `csharp.instructions.md` (C# / .NET-specific csproj patterns) and `cpp.instructions.md` (vcxproj toolset / SDK pinning rules).

---

## MSBuild property functions — string-literal escaping

MSBuild parses `$(Property.Method('arg'))` syntax to invoke .NET `String` / `Path` / `IO` methods on a property value. The `'arg'` literal flows through MSBuild's property-expansion AND through the .NET method's parameter parsing — both layers may re-interpret backslashes, quotes, and other special characters depending on MSBuild version, project SDK, and quoting context.

- **A literal backslash in a property-function argument needs `'\\'` (escaped backslash).** `$(Path.TrimEnd('\'))` is silently MSBuild-incorrect — the parser may consume the `\` as an escape character, leaving the `TrimEnd` argument empty or throwing a confusing argument exception. Use `$(Path.TrimEnd('\\'))` for a single backslash, OR (preferred) avoid the issue entirely by defining the source property without the trailing separator so no `TrimEnd` is needed.
- **Path concatenation — prefer `$(Var)\subpath` over `$(Var.TrimEnd('\\'))\subpath`.** Define `<MyDir>$(BaseDir)foo</MyDir>` without a trailing separator, then concatenate `$(MyDir)\file.ext`; this sidesteps the escaping question entirely. The only time `TrimEnd('\\')` is genuinely needed is when the input comes from outside (e.g., `$(MSBuildProjectDirectory)`, `$([System.IO.Path]::GetFullPath(...))`, or an `<Exec>` capture) and may or may not have a trailing separator.
- **Audit lens — single-quoted single backslash:** `rg "\.\w+\('[^']*\\[^\\]" *.csproj *.vcxproj *.targets *.props` flags every property-function arg containing an unpaired backslash. Each match needs review.

---

## `<Exec>` output capture — `ConsoleToMSBuild` trim required

The `<Exec ConsoleToMSBuild="true">` task captures the called process's stdout (and stderr, by default) verbatim — INCLUDING the trailing newline (`\r\n` on Windows, `\n` on Linux/macOS) the process appended. Downstream consumers that compare against an exact value, build a path, or call `Exists(...)` see a string with a trailing newline and silently misbehave: paths "don't exist", string comparisons fail, `<Copy>` source-doesn't-exist errors, registry lookups return null.

- **Always trim `ConsoleOutput` before use.** Canonical pattern:
  ```xml
  <Exec Command="vswhere -latest -property installationPath"
        ConsoleToMSBuild="true">
    <Output TaskParameter="ConsoleOutput" PropertyName="VsInstallPath" />
  </Exec>
  <PropertyGroup>
    <VsInstallPath>$(VsInstallPath.Trim())</VsInstallPath>
  </PropertyGroup>
  ```
  The `.Trim()` happens in a *separate* `<PropertyGroup>` after the `<Exec>` because property-function evaluation inside the `<Output>` element's `PropertyName` attribute is not supported by MSBuild.
- **Audit lens:** `rg "ConsoleToMSBuild=\"true\"" *.csproj *.vcxproj *.targets *.props` — every match should be followed (within the same target body) by a `<PropertyGroup>` that does `$(CapturedVar.Trim())`. Missing trim is a bug regardless of whether the downstream `<Exec>` / `<Copy>` / `Exists()` happens to tolerate the trailing newline today; the failure surfaces the moment someone uses the captured value in a strict comparison.

---

## Locked-down build environments — no implicit internet fetch

Many enterprise / pipeline environments (1ES, Azure DevOps managed agents, internal-mirror NuGet feeds, air-gapped builds) block direct egress to public CDNs (`dist.nuget.org`, `download.microsoft.com`, GitHub Releases, raw GitHub content URLs). Build scripts that fetch tooling at build time — `nuget.exe`, `dotnet-coverage`, `dotnet-format`, `cake`, custom CLI tools, vcpkg, etc. — MUST have a non-internet fallback or the pipeline silently breaks the first time it runs in the locked-down env. The breakage is invariably attributed to "flaky network" before someone finally checks the egress allowlist.

- **Pattern: discover-on-PATH first, fallback to download as last resort.** Wrap tool acquisition in conditional MSBuild logic so the same target works locally (dev box where `nuget.exe` may not be installed) AND in the locked-down pipeline (where the tool is installed system-wide by a previous pipeline step):
  ```xml
  <Target Name="EnsureNugetExe" Condition="'$(NugetExePath)' == ''">
    <!-- Step 1: try PATH discovery (works in locked-down envs that install tools system-wide via a pipeline task) -->
    <Exec Command="where nuget.exe"
          ConsoleToMSBuild="true"
          ContinueOnError="true"
          IgnoreStandardErrorWarningFormat="true">
      <Output TaskParameter="ConsoleOutput" PropertyName="WhereOutput" />
      <Output TaskParameter="ExitCode" PropertyName="WhereExitCode" />
    </Exec>
    <PropertyGroup>
    <!-- `where` prints one match per line (newline-separated, NOT semicolon-separated).
         Use Regex.Match to extract the first line; never `Split(';')` — that returns the
         entire multi-line blob unchanged when no `;` is present, and Exists() then fails. -->
    <NugetExePath Condition="'$(WhereExitCode)' == '0'">$([System.Text.RegularExpressions.Regex]::Match($(WhereOutput), '^[^\r\n]+').Value)</NugetExePath>
  </PropertyGroup>
  <!-- Step 2: fallback download for dev convenience. Will fail in egress-blocked envs, which is correct: -->
  <!-- the pipeline owner is responsible for provisioning nuget.exe via NuGetToolInstaller@1 or equivalent. -->
  <DownloadFile Condition="'$(NugetExePath)' == ''"
                SourceUrl="https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
                DestinationFolder="$(IntermediateOutputPath)">
    <Output TaskParameter="DownloadedFile" PropertyName="NugetExePath" />
  </DownloadFile>
</Target>
```
- **`where <tool>` output is newline-delimited, not semicolon-delimited.** Common bug pattern: `$(WhereOutput.Split(';')[0])` treats the multi-line output as if it were `PATH`-style. There are no semicolons in `where`'s output — the split is a no-op and `[0]` returns the entire multi-line blob, which then fails `Exists(...)` checks downstream. Use `[System.Text.RegularExpressions.Regex]::Match($(WhereOutput), '^[^\r\n]+').Value` to extract just the first line. (Confusingly, `where` exists to search `PATH`, but its OUTPUT is not `PATH`-shaped — easy to mix the two up.)
- **Honor `$(RestoreConfigFile)`** — when callers pass `dotnet publish --configfile internal-mirror.config`, MSBuild propagates the path into `$(RestoreConfigFile)`. Custom restore targets that shell out to `nuget.exe` should forward the configfile:
  ```xml
  <Exec Command="&quot;$(NugetExePath)&quot; restore packages.config -ConfigFile &quot;$(RestoreConfigFile)&quot;"
        Condition="'$(RestoreConfigFile)' != ''" />
  <Exec Command="&quot;$(NugetExePath)&quot; restore packages.config"
        Condition="'$(RestoreConfigFile)' == ''" />
  ```
  Without forwarding, restore falls back to the system-default NuGet config (typically `%APPDATA%\NuGet\NuGet.Config`) which references public `nuget.org` and fails in locked-down envs even though the parent `dotnet publish` was correctly configured.
- **For NuGet tool acquisition in ADO pipelines specifically:** the `NuGetToolInstaller@1` task puts a current `nuget.exe` on PATH and is the canonical way to satisfy the discover-on-PATH branch above. Pair it with the discover-first pattern in MSBuild so the same csproj works locally (where dev may have nuget.exe on PATH or the fallback download runs) AND in ADO (where the installer task provisions it before the build target fires).
- **Audit lens:** `rg "DownloadFile|Invoke-WebRequest|wget|curl" *.csproj *.targets *.props eng/*.ps1` — every match should be guarded by a PATH-discovery / cached-binary check first, OR have an immediately-preceding XML comment documenting why unconditional internet fetch is acceptable for this specific script (e.g., a developer-only `eng/install-x.ps1` that's never invoked from CI).

---

## Cross-VS-version portability (C++ projects)

See `cpp.instructions.md` *vcxproj configuration* for the toolset / SDK pinning rules — `$(DefaultPlatformToolset)` over hardcoded `v14X`, bare `10.0` over a pinned Windows SDK build number. The same rules apply to any `.vcxproj` / `.props` / `.targets` files that reference toolset or SDK versions.

---

## `<PackageReference>` + `Directory.Packages.props` (Central Package Management)

When the repo uses CPM (`<ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>` in `Directory.Packages.props`):

- **`<PackageReference>` in csproj files must NOT carry a `Version` attribute.** The version is owned by `Directory.Packages.props` as `<PackageVersion Include="X" Version="Y" />`. A `Version=` on a `PackageReference` either errors (newer NuGet) or silently bypasses CPM (older NuGet), defeating the entire point of centralization.
- **Adding a new dependency requires TWO files: the consuming csproj's `<PackageReference Include="X" />` AND `Directory.Packages.props`'s `<PackageVersion Include="X" Version="Y" />`.** Forgetting the props-file entry produces a build error pointing at the csproj line, which is the right line to add the `<PackageReference>` to but the wrong file to fix the missing version on — readers misdiagnose.
- **Audit lens:** `rg "<PackageReference Include=" *.csproj | rg -v "/>"` — multi-line PackageReference declarations (with `<Version>` child elements) are stragglers from a pre-CPM era and should be flattened to single-line + the version moved to props.
