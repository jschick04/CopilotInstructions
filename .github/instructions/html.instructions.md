---
applyTo: "**/*.html,**/*.htm,**/*.razor,**/*.cshtml"
---

# HTML Instructions

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
- In Razor, never bind a raw `bool` to an enumerated `aria-*` state (`aria-expanded`, `aria-pressed`, `aria-checked`, `aria-selected`): Blazor applies boolean-attribute semantics, so `aria-expanded="@isOpen"` emits a bare `aria-expanded` when `true` and omits it entirely when `false` - never the `"true"`/`"false"` string these states require, so assistive tech reads no valid state. Bind an explicit string - `aria-expanded="@(isOpen ? "true" : "false")"` for states that are always meaningful; use `@(cond ? "true" : null)` (which omits the attribute) only where absence IS the off-state, e.g. `aria-current`.
- Keep inline styles to a minimum; prefer CSS classes.
- Use meaningful `id` and `class` names (kebab-case: `item-list`, `header-nav`).
- Validate HTML structure.
- Place `<script>` tags at end of `<body>` or use `defer` / `async` attributes.
