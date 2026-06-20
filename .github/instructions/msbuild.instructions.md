---
applyTo: "**/*.csproj,**/*.targets,**/*.props,**/*.vcxproj,**/*.vcxproj.filters,**/Directory.Build.props,**/Directory.Build.targets,**/Directory.Packages.props"
---

# MSBuild Instructions

<!-- read-receipt-token: 5e460897 -->

> **Topic instruction file - not the whole ruleset.** The mandatory governed workflow (`AGENTS.md` §0 git-safety gates + §1 pre-implementation / post-code-change phase gates + the playbook router incl. `multi-model-review`) lives at the instruction-set repo root. If `AGENTS.md` is not already in your context this session, read it before editing.

> **Scope:** loaded automatically when the working set contains MSBuild project files (`*.csproj`, `*.vcxproj`), targets files, props files, or `Directory.Build.*` / `Directory.Packages.props` infrastructure files. Language-agnostic; complements `csharp.instructions.md` (C# / .NET-specific csproj patterns) and `cpp.instructions.md` (vcxproj toolset / SDK pinning rules).

---

## MSBuild property functions - string-literal escaping

MSBuild parses `$(Property.Method('arg'))` syntax to invoke .NET `String` / `Path` / `IO` methods on a property value. The `'arg'` literal flows through MSBuild's property-expansion AND through the .NET method's parameter parsing - both layers may re-interpret backslashes, quotes, and other special characters depending on MSBuild version, project SDK, and quoting context.

- **A literal backslash in a property-function argument needs `'\\'` (escaped backslash).** `$(Path.TrimEnd('\'))` is silently MSBuild-incorrect - the parser may consume the `\` as an escape character, leaving the `TrimEnd` argument empty or throwing a confusing argument exception. Use `$(Path.TrimEnd('\\'))` for a single backslash, OR (preferred) avoid the issue entirely by defining the source property without the trailing separator so no `TrimEnd` is needed.
- **Path concatenation - prefer `$(Var)\subpath` over `$(Var.TrimEnd('\\'))\subpath`.** Define `<MyDir>$(BaseDir)foo</MyDir>` without a trailing separator, then concatenate `$(MyDir)\file.ext`; this sidesteps the escaping question entirely. The only time `TrimEnd('\\')` is genuinely needed is when the input comes from outside (e.g., `$(MSBuildProjectDirectory)`, `$([System.IO.Path]::GetFullPath(...))`, or an `<Exec>` capture) and may or may not have a trailing separator.
- **Audit lens - single-quoted single backslash:** `rg "\.\w+\('[^']*\\[^\\]" *.csproj *.vcxproj *.targets *.props` flags every property-function arg containing an unpaired backslash. Each match needs review.

---

## `<Exec>` output capture - `ConsoleToMSBuild` trim required

The `<Exec ConsoleToMSBuild="true">` task captures the called process's stdout (and stderr, by default) verbatim - INCLUDING the trailing newline (`\r\n` on Windows, `\n` on Linux/macOS) the process appended. Downstream consumers that compare against an exact value, build a path, or call `Exists(...)` see a string with a trailing newline and silently misbehave: paths "don't exist", string comparisons fail, `<Copy>` source-doesn't-exist errors, registry lookups return null.

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
- **Audit lens:** `rg "ConsoleToMSBuild=\"true\"" *.csproj *.vcxproj *.targets *.props` - every match should be followed (within the same target body) by a `<PropertyGroup>` that does `$(CapturedVar.Trim())`. Missing trim is a bug regardless of whether the downstream `<Exec>` / `<Copy>` / `Exists()` happens to tolerate the trailing newline today; the failure surfaces the moment someone uses the captured value in a strict comparison.

---

## Locked-down build environments - no implicit internet fetch

Many enterprise / pipeline environments (1ES, Azure DevOps managed agents, internal-mirror NuGet feeds, air-gapped builds) block direct egress to public CDNs (`dist.nuget.org`, `download.microsoft.com`, GitHub Releases, raw GitHub content URLs). Beyond the egress concern, fetching tools from moving URLs like `.../latest/<tool>.exe` introduces a supply-chain risk (no integrity verification + non-reproducible builds) that applies to EVERY env, not just locked-down ones. The rule below addresses both.

- **Pattern: discover-on-PATH, fail-fast if not found. Do NOT auto-download.** Wrap tool acquisition in MSBuild logic that locates the binary via `where <tool>` (or platform equivalent) and emits an actionable `<Error>` if not found. The error message MUST name the canonical install commands for each consumer (dev, CI). This works locally (dev installs with `winget` / `scoop` / `choco`) AND in pipelines (the pipeline owner provisions the tool via the platform's installer task BEFORE the build target runs):
  ```xml
  <Target Name="EnsureNugetExe" Condition="'$(NugetExePath)' == ''">
    <Exec Command="where nuget.exe"
          ConsoleToMSBuild="true"
          ContinueOnError="true"
          IgnoreExitCode="true">
      <Output TaskParameter="ConsoleOutput" PropertyName="WhereOutput" />
      <Output TaskParameter="ExitCode" PropertyName="WhereExitCode" />
    </Exec>
    <PropertyGroup>
      <!-- `where` prints one match per line (newline-separated, NOT semicolon-separated).
           Use Regex.Match to extract the first line; never `Split(';')` - that returns the
           entire multi-line blob unchanged when no `;` is present, and Exists() then fails. -->
      <NugetExePath Condition="'$(WhereExitCode)' == '0'">$([System.Text.RegularExpressions.Regex]::Match($(WhereOutput), '^[^\r\n]+').Value)</NugetExePath>
    </PropertyGroup>
    <Error Condition="'$(NugetExePath)' == '' OR !Exists('$(NugetExePath)')"
           Text="nuget.exe not found on PATH. Install via `winget install Microsoft.NuGet` (dev), the NuGetToolInstaller@1 pipeline task (ADO), or `actions/setup-nuget@vN` (GitHub Actions). See &lt;repo-docs-link&gt; for prereqs." />
  </Target>
  ```
- **Do NOT include an unconditional `<DownloadFile>` fallback.** The default MUST be discover-on-PATH + fail-fast. If - and only if - you have a concrete reason to keep an auto-download (e.g., a dev-onboarding script that genuinely justifies the convenience), it MUST meet ALL of these criteria:
  1. **Pinned version URL**, not `latest` (e.g., `https://dist.nuget.org/win-x86-commandline/v7.6.0/nuget.exe`, not `.../latest/nuget.exe`). Pinning makes the build reproducible and gives a fixed target for the hash check.
  2. **SHA256 verification step** AFTER download. PowerShell `Get-FileHash` or `certutil -hashfile <path> SHA256`; compare against a hardcoded expected hash. Fail the build (and delete the file) on mismatch:
     ```xml
     <DownloadFile Condition="!Exists('$(NugetExePath)')"
                   SourceUrl="https://dist.nuget.org/win-x86-commandline/v7.6.0/nuget.exe"
                   DestinationFolder="$(IntermediateOutputPath)" />
     <Exec Command="powershell -NoProfile -Command &quot;$h = (Get-FileHash -Algorithm SHA256 -Path '$(NugetExePath)').Hash; if ($h -ne 'EXPECTED_HASH_UPPERCASE') { Remove-Item '$(NugetExePath)' -Force; Write-Error ('SHA256 mismatch: got ' + $h); exit 1 }&quot;" />
     ```
  3. **OR the source URL points at an internal mirror you control** (e.g., your org's internal CDN, `https://yourcorp.pkgs.visualstudio.com/...`), where the org's existing security review already covers the supply-chain question and the URL is not a moving `latest`. Internal mirrors are exempt from #1+#2 only because the trust boundary moves to the mirror's auth + retention guarantees.
  4. **An XML comment immediately above the `<DownloadFile>` element** naming (a) which consumer needs the download (e.g., "first-time dev onboarding"), (b) which consumers do NOT need it (e.g., "CI never hits this path - pipeline provisions `nuget.exe` via NuGetToolInstaller@1"), and (c) the maintenance commitment (e.g., "version pin must be bumped quarterly when NuGet ships a security patch").

  None of those 4 criteria is optional. Absent any one, the `<DownloadFile>` is a supply-chain risk + reproducibility hazard and the Copilot reviewer will flag it. **In practice, the cost of meeting #1+#2 is often higher than the convenience saved** - most projects find that requiring an explicit `winget install` (or pipeline installer task) is the cleaner answer. Choose deliberately, not by default.

  > **Empirical evidence**: this rule originally recommended the `DownloadFile` fallback for "dev convenience" with no integrity controls. A Copilot review flagged that as a supply-chain risk, and the fallback was removed entirely. The reversal is preserved here so future readers don't re-derive the same lesson.
- **`where <tool>` output is newline-delimited, not semicolon-delimited.** Common bug pattern: `$(WhereOutput.Split(';')[0])` treats the multi-line output as if it were `PATH`-style. There are no semicolons in `where`'s output - the split is a no-op and `[0]` returns the entire multi-line blob, which then fails `Exists(...)` checks downstream. Use `[System.Text.RegularExpressions.Regex]::Match($(WhereOutput), '^[^\r\n]+').Value` to extract just the first line. (Confusingly, `where` exists to search `PATH`, but its OUTPUT is not `PATH`-shaped - easy to mix the two up.)
- **Honor `$(RestoreConfigFile)`** - when callers pass `dotnet publish --configfile internal-mirror.config`, MSBuild propagates the path into `$(RestoreConfigFile)`. Custom restore targets that shell out to `nuget.exe` should forward the configfile:
  ```xml
  <Exec Command="&quot;$(NugetExePath)&quot; restore packages.config -ConfigFile &quot;$(RestoreConfigFile)&quot;"
        Condition="'$(RestoreConfigFile)' != ''" />
  <Exec Command="&quot;$(NugetExePath)&quot; restore packages.config"
        Condition="'$(RestoreConfigFile)' == ''" />
  ```
  Without forwarding, restore falls back to the system-default NuGet config (typically `%APPDATA%\NuGet\NuGet.Config`) which references public `nuget.org` and fails in locked-down envs even though the parent `dotnet publish` was correctly configured.
- **Tool acquisition by platform - canonical install paths to cite in `<Error>` text:**
  - **Local dev (Windows):** `winget install Microsoft.NuGet`, `scoop install nuget`, `choco install nuget.commandline`.
  - **GitHub Actions (`windows-2022` / `windows-2025`):** nuget.exe is PRE-INSTALLED in the standard runner image (verify via the runner image readme at `https://github.com/actions/runner-images/blob/main/images/windows/<image>-Readme.md` - search for "NuGet"). No action needed.
  - **GitHub Actions (linux/mac or non-pre-installed tools):** `nuget/setup-nuget@v2` or the language-specific setup action.
  - **Azure DevOps:** `NuGetToolInstaller@1` task before the build step. Same pattern for other tools: `UseDotNet@2`, `JavaToolInstaller@0`, `NodeTool@0`, etc.
  - **1ES / managed pipelines:** the platform's tool-installer task (often the same ADO tasks above). For tools without a first-party installer task, use a self-hosted-runner image that pre-installs the tool.
- **Audit lens:** `rg "DownloadFile|Invoke-WebRequest|wget|curl" *.csproj *.targets *.props eng/*.ps1 eng/*.sh` - every match must EITHER (a) meet ALL FOUR criteria above (pinned URL + SHA256 verification + internal-mirror OR documented dev-only justification + maintenance comment) OR (b) be removed in favor of the fail-fast pattern. There is no third "convenience fallback" middle ground.

---

## Cross-VS-version portability (C++ projects)

See `cpp.instructions.md` *vcxproj configuration* for the toolset / SDK pinning rules - `$(DefaultPlatformToolset)` over hardcoded `v14X`, bare `10.0` over a pinned Windows SDK build number. The same rules apply to any `.vcxproj` / `.props` / `.targets` files that reference toolset or SDK versions.

---

## `<PackageReference>` + `Directory.Packages.props` (Central Package Management)

When the repo uses CPM (`<ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>` in `Directory.Packages.props`):

- **`<PackageReference>` in csproj files must NOT carry a `Version` attribute.** The version is owned by `Directory.Packages.props` as `<PackageVersion Include="X" Version="Y" />`. A `Version=` on a `PackageReference` either errors (newer NuGet) or silently bypasses CPM (older NuGet), defeating the entire point of centralization.
- **Adding a new dependency requires TWO files: the consuming csproj's `<PackageReference Include="X" />` AND `Directory.Packages.props`'s `<PackageVersion Include="X" Version="Y" />`.** Forgetting the props-file entry produces a build error pointing at the csproj line, which is the right line to add the `<PackageReference>` to but the wrong file to fix the missing version on - readers misdiagnose.
- **Audit lens:** `rg "<PackageReference Include=" *.csproj | rg -v "/>"` - multi-line PackageReference declarations (with `<Version>` child elements) are stragglers from a pre-CPM era and should be flattened to single-line + the version moved to props.
