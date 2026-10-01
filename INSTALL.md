# Installation Guide

## Prerequisites

- Perl 5.10 or higher
- `apply_patch.pl` script in your execution path or repository root

## Setup

1. Copy the skill folder `apply-v4a-patch` to your local agent's skill directory:
   ```bash
   cp -r apply-v4a-patch ~/.agent/skills/

```

2. Ensure `apply_patch.pl` has execution permissions:
```bash
chmod +x apply_patch.pl

```


3. Verify installation by running a dry-run test:
```bash
perl apply_patch.pl --dry-run patch.v4a

```


