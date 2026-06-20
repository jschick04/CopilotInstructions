---
applyTo: "**/*.css,**/*.scss,**/*.sass,**/*.less"
---

# CSS Instructions

<!-- read-receipt-token: f7a6b78d -->

> **Topic instruction file - not the whole ruleset.** The mandatory governed workflow (`AGENTS.md` §0 git-safety gates + §1 pre-implementation / post-code-change phase gates + the playbook router incl. `multi-model-review`) lives at the instruction-set repo root. If `AGENTS.md` is not already in your context this session, read it before editing.

> **Scope:** loaded automatically when the working set contains CSS/SCSS/SASS/LESS files. Extends the `AGENTS.md` core.

---

## CSS Code Style

### Naming Conventions

- Use kebab-case for class names (`item-list`, `header-navigation`).
- Use BEM methodology when appropriate (`block__element--modifier`).
- Avoid ID selectors for styling; prefer classes.
- Use meaningful, descriptive names.

### Formatting

- 4 spaces for indentation (no tabs).
- Opening brace on the same line as the selector.
- One property per line.
- Space after the colon in declarations.
- End all declarations with a semicolon.
- Separate rule sets with a blank line.
- Insert a final newline in every file.

### Property Ordering (Recommended)

1. Positioning (`position`, `top`, `right`, `bottom`, `left`, `z-index`)
2. Box model (`display`, `flex`, `grid`, `width`, `height`, `margin`, `padding`, `border`)
3. Typography (`font`, `line-height`, `text-align`, `color`)
4. Visual (`background`, `box-shadow`, `opacity`)
5. Animation (`transition`, `animation`)
6. Misc (`cursor`, `overflow`)
