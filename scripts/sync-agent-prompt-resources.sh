#!/bin/bash
# Copies the SDK type definitions and component reference into the AgentPrompt resources.
# Idempotent. Run manually after editing sdk/index.d.ts or COMPONENTS.md (a test fails if copies are stale).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DST="$ROOT/Packages/WidgeeKit/Sources/AgentPrompt/Resources"
mkdir -p "$DST"
cp "$ROOT/sdk/index.d.ts" "$DST/sdk-index.d.ts"
cp "$ROOT/Packages/WidgeeKit/Sources/Renderer/COMPONENTS.md" "$DST/COMPONENTS.md"
echo "synced agent prompt resources -> $DST"
