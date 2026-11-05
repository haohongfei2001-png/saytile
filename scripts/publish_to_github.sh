#!/usr/bin/env bash
# Prepared publishing entry point; NOT executed in the recovery environment.
# Uses existing gh credentials. Does not alter visibility or merge into main.
set -euo pipefail
root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
repo="haohongfei2001-png/saytile"
branch="recovery/v1-design-20261106"
base="090ecd14f0f621d206b7d253590360cbba4ad12f"
for tool in git gh python3; do command -v "$tool" >/dev/null || { echo "Required command unavailable: $tool" >&2; exit 1; }; done
python3 "$root/scripts/check_integrity.py"
gh auth status >/dev/null 2>&1 || { echo 'Existing GitHub CLI authentication is required; no credentials were read or exported.' >&2; exit 1; }
work="$(mktemp -d "${TMPDIR:-/tmp}/saytile-publish.XXXXXX")"
echo "Isolated checkout: $work"
gh repo clone "$repo" "$work/repository" -- --branch main --single-branch
checkout="$work/repository"
actual="$(git -C "$checkout" rev-parse HEAD)"
if [ "$actual" != "$base" ]; then
  echo "Remote main has changed ($actual). Stop and reconcile; no remote changes were made." >&2
  exit 2
fi
if [ -n "$(git -C "$checkout" ls-remote --heads origin "refs/heads/$branch")" ]; then
  echo 'The recovery branch already exists. Inspect/reuse it instead of overwriting.' >&2
  exit 2
fi
git -C "$checkout" switch -c "$branch"
python3 - "$root" "$checkout" <<'PY'
from pathlib import Path
import shutil,sys
source=Path(sys.argv[1]).resolve();dest=Path(sys.argv[2]).resolve()
for line in (source/'SHA256SUMS.txt').read_text().splitlines():
 _,name=line.split('  ',1)
 a=(source/name).resolve();b=(dest/name).resolve()
 if not a.is_relative_to(source) or not b.is_relative_to(dest):raise ValueError('invalid manifest path')
 b.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(a,b)
shutil.copy2(source/'SHA256SUMS.txt',dest/'SHA256SUMS.txt')
PY
login="$(gh api user --jq .login)"
id="$(gh api user --jq .id)"
git -C "$checkout" config user.name "$login"
git -C "$checkout" config user.email "$id+$login@users.noreply.github.com"
git -C "$checkout" add --all
git -C "$checkout" commit -m "Recover Saytile V1 design and rebuild audio-erasure/dispatch contracts"
git -C "$checkout" push -u origin "$branch"
gh pr create --repo "$repo" --base main --head "$branch" \
 --title "Recover Saytile V1 design and review contracts" \
 --body-file "$root/docs/PR-DESCRIPTION.md"
echo 'Branch and PR created. No merge, deployment or native installation was performed.'
