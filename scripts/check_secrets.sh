#!/bin/sh
# Fails if an Anthropic API key could end up in this public repository.
# Runs in CI; to run it before every commit:  ln -s ../../scripts/check_secrets.sh .git/hooks/pre-commit
set -eu
cd "$(git rev-parse --show-toplevel)"
status=0
fail() { echo "check_secrets: $1" >&2; status=1; }

# Config/Local.xcconfig holds personal values (team ID, built-in key) and must never be committed.
git check-ignore -q Config/Local.xcconfig || fail "Config/Local.xcconfig is not git-ignored (.gitignore)."
if git ls-files --error-unmatch Config/Local.xcconfig >/dev/null 2>&1; then
    fail "Config/Local.xcconfig is tracked. Run: git rm --cached Config/Local.xcconfig"
fi

# The committed default must stay empty.
grep -Eq '^ANTHROPIC_API_KEY[[:space:]]*=[[:space:]]*$' Config/Base.xcconfig \
    || fail "ANTHROPIC_API_KEY in Config/Base.xcconfig must be empty; put the key in Config/Local.xcconfig."
grep -Eq '^ANTHROPIC_API_KEY[[:space:]]*=[[:space:]]*$' Config/Local.xcconfig.example \
    || fail "ANTHROPIC_API_KEY in Config/Local.xcconfig.example must be empty."

# The app's Info.plist may only reference the build setting; the widget's must not carry it at all.
grep -q '<string>$(ANTHROPIC_API_KEY)</string>' Config/TimeTracker-Info.plist \
    || fail "Config/TimeTracker-Info.plist must contain \$(ANTHROPIC_API_KEY), not a literal key."
if grep -q 'ANTHROPIC_API_KEY\|TTBundledAnthropicKey' Config/TimeTrackerWidgets-Info.plist; then
    fail "The widget extension must not embed the Anthropic key."
fi

# Anything that looks like a real key in tracked or staged files (test placeholders are short).
matches=$( { git ls-files -z; git diff --cached --name-only -z; } | sort -zu \
    | xargs -0 grep -IEln 'sk-ant-[A-Za-z0-9_-]{20,}' 2>/dev/null || true)
if [ -n "$matches" ]; then
    fail "Possible Anthropic API key in: $(echo "$matches" | tr '\n' ' ')"
fi

[ "$status" -eq 0 ] && echo "check_secrets: OK, no Anthropic key in tracked files."
exit "$status"
