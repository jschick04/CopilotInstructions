---
applyTo: "**/*.css,**/*.scss,**/*.sass,**/*.less"
---

# CSS Instructions

> **Scope:** loaded automatically when the working set contains CSS/SCSS/SASS/LESS files. Extends the always-loaded `AGENTS.md` core.

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
