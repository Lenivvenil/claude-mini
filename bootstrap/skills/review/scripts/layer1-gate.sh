#!/usr/bin/env bash
# layer1-gate.sh — wrapper for ~/.claude/scripts/verify.sh.
# Emits LAYER1_SKIPPED (not LAYER1_PASSED) if verify.sh is absent.
# The review SKILL.md treats LAYER1_SKIPPED as a non-pass state requiring
# explicit operator acknowledgement before Layer 2 proceeds.
if [ -x "$HOME/.claude/scripts/verify.sh" ]; then
    "$HOME/.claude/scripts/verify.sh" 2>&1
else
    echo "LAYER1_SKIPPED: verify.sh not installed. Run ./bootstrap/universal-setup.sh --install, then re-run review."
fi
