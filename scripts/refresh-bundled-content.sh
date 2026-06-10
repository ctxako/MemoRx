#!/usr/bin/env bash
# Refresh MemoRx/drugs.json and MemoRx/class_quizzes.json from the live Supabase
# project. Run this before tagging a new app release so the offline-fallback
# bundle reflects the current catalog.
#
# Usage:  ./scripts/refresh-bundled-content.sh
#
# Reads SUPABASE_HOST + SUPABASE_ANON_KEY from Config/Supabase.xcconfig. Writes
# files atomically (via tmp + mv) so a partial fetch never leaves a corrupted
# bundle behind.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCCONFIG="$REPO_ROOT/Config/Supabase.xcconfig"
DRUGS_OUT="$REPO_ROOT/MemoRx/drugs.json"
GUIDES_OUT="$REPO_ROOT/MemoRx/class_quizzes.json"

if [[ ! -f "$XCCONFIG" ]]; then
  echo "✗ Missing $XCCONFIG" >&2
  exit 1
fi

# Parse SUPABASE_HOST and SUPABASE_ANON_KEY out of the xcconfig (tolerant to whitespace).
HOST=$(awk -F'=' '/^SUPABASE_HOST[[:space:]]*=/ {gsub(/[[:space:]]/,"",$2); print $2; exit}' "$XCCONFIG")
ANON=$(awk -F'=' '/^SUPABASE_ANON_KEY[[:space:]]*=/ {sub(/^[^=]*=[[:space:]]*/,"",$0); gsub(/[[:space:]]+$/,"",$0); print; exit}' "$XCCONFIG")

if [[ -z "$HOST" || -z "$ANON" ]]; then
  echo "✗ Could not read SUPABASE_HOST or SUPABASE_ANON_KEY from $XCCONFIG" >&2
  exit 1
fi

BASE_URL="https://$HOST/rest/v1"

echo "→ Fetching drugs from $HOST …"
TMP_DRUGS=$(mktemp)
trap 'rm -f "$TMP_DRUGS" "$TMP_GUIDES" 2>/dev/null || true' EXIT

curl --fail --silent --show-error \
  -H "apikey: $ANON" \
  -H "Authorization: Bearer $ANON" \
  -H "Accept: application/json" \
  "$BASE_URL/drugs?select=id,generic_name,brand_names,collection,sub_collection,drug_class,mechanism_of_action,indications,dosage,side_effects,warnings,contraindications,interactions,monitoring,counseling_points,pearls&order=id.asc" \
  > "$TMP_DRUGS"

DRUG_COUNT=$(python3 -c "import json,sys; print(len(json.load(open('$TMP_DRUGS'))))")
if [[ "$DRUG_COUNT" -lt 1 ]]; then
  echo "✗ Supabase returned 0 drug rows — aborting (bundle would be empty)." >&2
  exit 1
fi
python3 -c "import json; arr=json.load(open('$TMP_DRUGS')); json.dump(arr, open('$DRUGS_OUT','w'), indent=2, ensure_ascii=False)"
echo "✓ Wrote $DRUGS_OUT  ($DRUG_COUNT drugs)"

echo "→ Fetching class_quizzes from $HOST …"
TMP_GUIDES=$(mktemp)
curl --fail --silent --show-error \
  -H "apikey: $ANON" \
  -H "Authorization: Bearer $ANON" \
  -H "Accept: application/json" \
  "$BASE_URL/class_quizzes?select=sub_collection,display_name,suffixes,class_uses,hallmark_side_effects,high_yield_pearls,high_risk_meds&order=sub_collection.asc" \
  > "$TMP_GUIDES"

GUIDE_COUNT=$(python3 -c "import json,sys; print(len(json.load(open('$TMP_GUIDES'))))")
if [[ "$GUIDE_COUNT" -lt 1 ]]; then
  echo "✗ Supabase returned 0 class_quizzes rows — aborting." >&2
  exit 1
fi
python3 -c "import json; arr=json.load(open('$TMP_GUIDES')); json.dump(arr, open('$GUIDES_OUT','w'), indent=2, ensure_ascii=False)"
echo "✓ Wrote $GUIDES_OUT  ($GUIDE_COUNT guides)"

echo
echo "Done. Files are auto-included via Xcode 16 file-system-synchronized groups."
echo "Build the Release config to verify decode:"
echo "  xcodebuild -project MemoRx.xcodeproj -scheme MemoRx -configuration Release -destination 'generic/platform=iOS Simulator' build"
