# V4A Patch Format Specification

## Grammar & Syntax

```text
*** Begin Patch
[*** Update File: <path>
 [@@ <hint>]
 <prefix><line>...
]
[*** Add File: <path>
 +<line>...
 *** End of File
]
[*** Delete File: <path>]
*** End Patch

```

## Line Prefixes in Update Blocks

| Prefix | Meaning |
| --- | --- |
| ` ` (space) | Context line (must match target file exactly) |
| `-` | Line to remove |
| `+` | Line to insert |

## Common Pitfalls

1. **Missing space on blank context lines**: Empty context lines in a hunk must still begin with a single space ` `.
2. **Tab vs Space mismatch**: Ensure original indentation whitespace matches the target file precisely.
3. **Stale Hunk Hints**: If lines have moved, ensure `@@` hints point to unique string matches ahead of the current cursor.

