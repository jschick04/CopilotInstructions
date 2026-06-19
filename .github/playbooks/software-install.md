---
name: software-install
description: Use when user wants to install, upgrade, or uninstall software on the user's machine. Prefers the platform package manager (winget on Windows, brew on macOS, distro native on Linux) over hand-rolled downloads; falls back to vendor bootstrappers and raw binaries with signature / checksum / magic-bytes / version-cross-check verification.
triggers:
  - "install"
  - "upgrade"
  - "uninstall"
  - "set up <tool>"
  - "get <tool> on my machine"
  - "winget install"
  - "brew install"
---

# Playbook: Software install / upgrade / uninstall

## Purpose

Install, upgrade, or uninstall software on the user's machine using the platform's package manager whenever possible. Fires when the user asks to install / upgrade / uninstall a tool, SDK, runtime, IDE, or any other software.

## Hard gates

- **Package manager confirmed installed** before any install / upgrade / uninstall command runs (`winget --version` / `brew --version` / `which apt`).
- **Exact-ID match confirmed in the package manager** before invoking install (`winget search --id <Vendor.Product> --exact`, `brew info <name>`, `apt-cache show <name>`). If no exact match, surface to user; do NOT guess an ID.
- **Version / edition matches what the user asked for** - re-read the package ID before invoking install (e.g. `Microsoft.VisualStudio.2026.Enterprise` vs `Microsoft.VisualStudio.2026.Community`).
- **Vendor-bootstrapper fallback path:** signature verified (`Get-AuthenticodeSignature` / `codesign -dv` / `gpg --verify`) AND magic bytes match (PE / ELF / Mach-O) AND **embedded version metadata read and confirmed to match the requested major version** (`(Get-Item <path>).VersionInfo.FileVersion` on Windows, etc.) - all THREE before launching the binary. A signed binary from a working URL can still be the wrong product version when shortlinks rot or query parameters silently fall back to a default. **Raw single-file binary exception:** when the binary genuinely has no embedded version metadata to read (common for `kubectl` / `terraform` / `helm`-style ELF or Mach-O CLIs), the *Raw single-file binary fallback* documented below substitutes provenance + versioned URL + signed-checksum verification + post-install `--version` check for the embedded-metadata read - that path satisfies the hard gate via the documented fallback, not by violating it.
- **Never execute a downloaded bootstrapper "to see what happens"** if any of the above checks fails or cannot be confirmed.

## Intake questions

Bundle these in one prompt:

1. Operation: install / upgrade / uninstall?
2. What software? (full name AND vendor - "Visual Studio 2026 Enterprise" not just "VS").
3. Specific version required, or latest available?
4. Per-machine (admin) or per-user install?
5. Any options that wouldn't be exposed by the package manager (custom workloads, license-server config, MSI properties)? If yes, the vendor bootstrapper path applies - see "When to fall back" below.

## Procedure

### Default: prefer the platform package manager

| Platform | Manager | Check availability |
| --- | --- | --- |
| Windows | `winget` (Microsoft Store + community manifests) | `winget --version` |
| macOS | `brew` (and `brew install --cask` for GUI apps) | `brew --version` |
| Linux | distro's native manager (`apt`, `dnf`, `pacman`, `zypper`, etc.) | `which apt` / `which dnf` / etc. |

**Why this is the default:** package managers verify signatures, track installed versions, support clean upgrade and uninstall, are idempotent, and don't require chasing the right download URL (which often rots - `aka.ms` shortlinks redirect to Bing search pages when the slug doesn't exist, vendor sites move bootstrappers between releases). They also write to standard locations and integrate with the OS uninstall surface, so a future "remove this" request is a one-liner instead of an archaeology project.

### Mandatory pre-flight before any install / upgrade / uninstall

1. **Confirm the manager is installed** (`winget --version` / `brew --version` / `which apt`).
2. **Confirm the package exists in the manager** with an exact ID search:
   - `winget search --id <Vendor.Product> --exact`
   - `brew info <name>`
   - `apt-cache show <name>`
   If the search hangs or returns no exact match, do not guess - surface the result to the user and decide together whether to (a) try a different ID, (b) fall back to the vendor bootstrapper, or (c) abort.
3. **Confirm the version / edition matches what the user asked for.** Package-manager IDs sometimes pin to a specific edition (`Microsoft.VisualStudio.2026.Enterprise` vs `Microsoft.VisualStudio.2026.Community`) - re-read the ID before invoking install.

### When to fall back to the vendor's bootstrapper / installer

- The package isn't published in the manager (or only an outdated version is).
- The install requires options the manager wrapper doesn't expose (e.g., complex workload/component selection that needs a `--config <file>.vsconfig`, custom MSI properties, license-server configuration).
- The user explicitly asks for the vendor installer.
- An offline / air-gapped install is required.

In these cases:

1. **Download the bootstrapper from a URL you've verified resolves to a real signed binary.** Fetch with `Invoke-WebRequest` / `curl`, check the magic bytes (`MZ` for PE, `7F 45 4C 46` for ELF, `CF FA ED FE` for Mach-O), and run the platform's signature check (`Get-AuthenticodeSignature` on Windows, `codesign -dv` on macOS, `gpg --verify` on Linux). An HTML page saved as `.exe` is a recurring failure mode when shortlinks rot - always validate before executing.

2. **Verify the bootstrapper's embedded version metadata BEFORE execution.** A signed Microsoft binary from a working URL can still be the *wrong product version* - vendor download endpoints often accept query parameters like `?version=...` and silently ignore unknown values, falling back to a default that may be many releases old. Before launching any bootstrapper / installer / setup binary you downloaded, read its embedded version using a **non-executing** method:
   - Windows: `(Get-Item <path>).VersionInfo.FileVersion` (reads PE metadata; does not execute the binary).
   - macOS: `mdls -name kMDItemVersion <path>` or `defaults read <bundle>/Contents/Info CFBundleShortVersionString` (Spotlight / Info.plist read; non-executing).
   - Linux packaged installers: `rpm -qpi <file>` for RPM packages, `dpkg-deb -I <file>` for DEB packages, `tar -tvf` / `unzip -p` to inspect archive metadata. **Do NOT use the binary's `--version` flag for the pre-execution check** - running `--version` IS executing the unverified bootstrapper and violates the hard gate above.

   Assert the version matches the major version of the product the user actually asked for. The user-facing `ProductName` / `ProductVersion` strings are sometimes friendly labels (e.g. "Visual Studio 2026") that don't sort numerically - prefer the numeric `FileVersion` for the assertion. If the version doesn't match, abort and re-source the bootstrapper from a different URL - never run it "to see what happens." A wrong-version install can silently overwrite, downgrade, or sit alongside the user's existing install and waste 30+ minutes of cleanup.

   **Rule of thumb:** if you can't print the bootstrapper's major version *without executing it* and confirm it matches before launching, you're not ready to launch.

3. **Raw single-file binary fallback** (Linux / macOS tools like `kubectl`, `terraform`, `helm`, `jq`, `mc`, etc. distributed as a bare ELF / Mach-O with no embedded version-readable metadata, only a vendor-published checksum + versioned URL). When the embedded-metadata check above is impossible because no embedded metadata exists, the install path is still safe IF all of these hold:
   - **Provenance: official source.** URL is the vendor's documented release endpoint (GitHub Releases under the vendor org, vendor's official `dl.<vendor>.com` / `releases.<vendor>.com` mirror, or the project's documented install script source). Not a community mirror, package proxy, or shortlink.
   - **Versioned URL.** The download URL itself contains the version (e.g. `.../v1.29.3/kubectl`, `.../terraform_1.7.5_linux_amd64.zip`). Record the URL-version as the asserted version.
   - **Checksum + signature verified.** Download the vendor's published `SHA256SUMS` (and `SHA256SUMS.sig` / `SHA256SUMS.asc` when available) from the same release endpoint, verify the signature against the vendor's published GPG key, then verify the binary's SHA-256 matches.
   - **Magic bytes match** the expected platform format (ELF / Mach-O).
   - **Install without pre-executing.** Place the binary on PATH (or extract the archive) - do NOT run it for any purpose before install completes.
   - **POST-install `--version` verification.** After install, run `--version` and assert the printed version matches the URL-version recorded above. If they disagree, the binary on PATH is not what was downloaded - investigate before considering the install successful.
   - **Record what was used.** Note in the install record that no embedded version metadata existed; provenance + versioned-URL + checksum-with-signature substituted for the embedded-metadata check. This satisfies the hard gate via a documented fallback, not by violating it.

   If any of the above conditions fails (no signature, no checksum file, ambiguous URL, community mirror), surface to the user (do not claim the hard gate passed) and decide together whether to proceed.

4. **Locating the right URL when shortlinks fail.** Vendor download portals usually expose a "thank you for downloading" intermediate page (e.g., `https://visualstudio.microsoft.com/thank-you-downloading-visual-studio/?sku=...&version=...`) that contains the actual signed bootstrapper URL with the correct query-parameter values for the current release. Scrape that page (regex out the real download URL) rather than guessing slugs. The query parameters that matter (e.g., `version=VS18` vs `version=VS2026`, `channel=stable` vs `channel=Release`) often differ from what the marketing material implies - read them from the page that the official "Download" button submits to, not from your own assumptions.

### Idempotency note

`winget install`, `brew install`, and `apt install` are all safe to re-run when a package is already installed (they no-op or upgrade). Don't add bespoke "is it already installed?" checks unless you need to branch on the result - let the manager handle it.

## After-install verification

- Run the installed tool's `--version` (or equivalent) to confirm it actually launches.
- For SDKs / runtimes: check `where <tool>` (Windows) / `which <tool>` (Unix) returns the expected path.
- If the install was supposed to register a system service or PATH entry, verify it took effect (may require a new shell session for PATH).
