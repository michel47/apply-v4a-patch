# Installation Guide

## Prerequisites

- Perl 5.10 or higher
- `apply_patch.pl` script in your execution path or repository root

## Setup

1. Copy the skill folder `apply-v4a-patch` to your local agent's skill directory:
   ```sh
   cp -r apply-v4a-patch ~/.agent/skills/

```
   optionally
   ```sh
   ln -sf $(git rev-parse --show-toplevel)/apply-v4a-patch/scripts/apply_patch.pl $HOME/bin/
```

2. Ensure `apply_patch.pl` has execution permissions:
   ```sh
   chmod +x apply_patch.pl

```


3. Verify installation by running a dry-run test:
   ```sh
   perl apply_patch.pl --dry-run patch.v4a

```


