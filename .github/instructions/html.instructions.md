---
applyTo: "**/*.html,**/*.htm,**/*.razor,**/*.cshtml"
---

<!-- CopilotInstructions: SENTINEL html -->

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
- Keep inline styles to a minimum; prefer CSS classes.
- Use meaningful `id` and `class` names (kebab-case: `item-list`, `header-nav`).
- Validate HTML structure.
- Place `<script>` tags at end of `<body>` or use `defer` / `async` attributes.
