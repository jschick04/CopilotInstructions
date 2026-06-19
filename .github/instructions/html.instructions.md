---
applyTo: "**/*.html,**/*.htm,**/*.razor,**/*.cshtml"
---

# HTML Instructions

<!-- read-receipt-token: 633aab2b -->

> **Scope:** loaded automatically when the working set contains HTML/Razor markup files. Extends the always-loaded `AGENTS.md` core. (Razor/cshtml codebehind C# is covered by the C# instructions file.)

---

## HTML Code Style

### Formatting

- 4 spaces for indentation (no tabs).
- Lowercase for element names and attributes.
- Always use double quotes for attribute values.
- Include the `lang` attribute on `<html>`.
- Include a `charset` meta tag.
- Close all elements (use `/>` for self-closing in XHTML, or omit the slash in HTML5).
- Insert a final newline in every file.

### Attribute Ordering (Recommended)

1. `class`
2. `id`, `name`
3. `data-*` attributes
4. `src`, `href`, `for`, `type`, `value`
5. `title`, `alt`
6. `role`, `aria-*`
7. Other attributes

### Best Practices

- Use semantic elements (`<header>`, `<nav>`, `<main>`, `<article>`, `<section>`, `<footer>`).
- Include appropriate ARIA attributes for accessibility.
- **`aria-label` that is wrong, duplicated, or describes appearance not behavior.** A new interactive control's `aria-label` (when it needs one) must read naturally and describe what the control DOES. Watch for duplicated words (`"Filter filter sets by tag"`), appearance-only labels (`"X icon"` instead of `"Close dialog"`), and an ICON-ONLY `<button>` / custom select with NO visible text and no other label. Spot new `aria-label=` / `AriaLabel=` on added controls and read each aloud. Acceptable: the control is already labeled by visible text, an associated `<label for=...>`, or `aria-labelledby` - do NOT add a redundant `aria-label` (it overrides a visible-text / `<label for>` accessible name, and is itself superseded when `aria-labelledby` is present).
- **A new multi-select dropdown without the clear / "All" affordance its siblings have.** When you add a multi-select control, check existing sibling multi-selects for a clear / reset-to-empty affordance (a clear entry, an "All" option) and match it, so users can reset in one click. Compare the new component against existing ones for affordance parity. Acceptable: a documented reason the control should not be clearable.
- In Razor, never bind a raw `bool` to an enumerated `aria-*` state (`aria-expanded`, `aria-pressed`, `aria-checked`, `aria-selected`): Blazor applies boolean-attribute semantics, so `aria-expanded="@isOpen"` emits a bare `aria-expanded` when `true` and omits it entirely when `false` - never the `"true"`/`"false"` string these states require, so assistive tech reads no valid state. Bind an explicit string - `aria-expanded="@(isOpen ? "true" : "false")"` for states that are always meaningful; use `@(cond ? "true" : null)` (which omits the attribute) only where absence IS the off-state, e.g. `aria-current`.
- Keep inline styles to a minimum; prefer CSS classes.
- Use meaningful `id` and `class` names (kebab-case: `item-list`, `header-nav`).
- Validate HTML structure.
- Place `<script>` tags at end of `<body>` or use `defer` / `async` attributes.
