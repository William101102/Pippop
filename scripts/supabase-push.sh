#!/usr/bin/env bash
# Run after: npx supabase login
set -euo pipefail
cd "$(dirname "$0")/.."

echo "→ Linking project nzqgkbibuqnfbxfarswu..."
npx supabase@latest link --project-ref nzqgkbibuqnfbxfarswu

echo "→ Pushing migrations (skips already-applied)..."
npx supabase@latest db push

echo "Done. Migrations in supabase/migrations/ are now applied to your remote project."
