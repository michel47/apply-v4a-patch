---
name: apply-v4a-patch
description: Generates valid V4A format patches for apply_patch.pl to update source code files cleanly on the first try. Use when generating patch files, diffs, or code modifications.
---

# Apply V4A Patch

This skill provides precise rules and templates for generating V4A format patch files (compatible with `apply_patch.pl`).

## Overview

The V4A format is a structured patch format designed for reliable code modifications. To guarantee that `apply_patch.pl` applies the patch without `hunk not found` errors, every patch must strictly adhere to prefix formatting and line matching rules.

## Core Rules for V4A Patches

1. **Section Headers**:
   - Every patch must start with `*** Begin Patch` and end with `*** End Patch`.
   - File actions use:
     - `*** Update File: <path>`
     - `*** Add File: <path>`
     - `*** Delete File: <path>`

2. **Hunk Context and Prefixes**:
   - **CRITICAL**: Every single line inside an `Update File` hunk MUST start with an explicit character prefix:
     - ` ` (a single space) for unchanged context lines.
     - `-` for lines to be deleted.
     - `+` for lines to be added.
   - Never omit the prefix space on context lines, empty lines, or header boundaries.

3. **Context Hints (`@@`)**:
   - Optional `@@ <hint>` markers anchor the search cursor in the target file.
   - Hints should reference a unique nearby line (e.g., function header or structural delimiter).

4. **Wildcards and Ellipses**:
   - When passing `--ellipsis` to `apply_patch.pl`, lines containing only `...` act as non-greedy wildcards matching intermediate lines.

## Detailed Instructions

For detailed patch structures, edge-case handling, and manual installation steps, refer to:
- `references/v4a-spec.md` - Complete syntax and matching specifications
- `INSTALL.md` - Setup and integration guide for local agent scripts
- `README.md` - Repository overview
