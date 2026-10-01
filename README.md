# V4A Patch Skill

A skill for AI agents to generate error-free V4A patch files for `apply_patch.pl`.

## Included Files

- `SKILL.md`: Main skill definition and system instructions.
- `README.md`: This file.
- `INSTALL.md`: Installation and deployment instructions for local agents.
- `references/v4a-spec.md`: Formal specification of the V4A diff/patch format.

## Usage

When an agent needs to generate a code modification patch:
```bash
perl apply_patch.pl patch.v4a

```

Or with ellipsis support:

```bash
perl apply_patch.pl --ellipsis patch.v4a

```

