#!/bin/bash
# Skills conformance verification script
# Validates S1 (≤200 lines), S2 (progressive disclosure), S3 (description format)
# Based on: https://github.com/mrgoonie/claudekit-skills/blob/main/REFACTOR.md

set -euo pipefail

echo "=== SKILL CONFORMANCE VERIFICATION ==="
echo ""

total_skills=0
s1_pass=0
s2_pass=0
s3_pass=0

for skill_md in $(find "$HOME/.claude/skills" -name "SKILL.md" -type f 2>/dev/null); do
  total_skills=$((total_skills + 1))
  skill_name=$(basename $(dirname "$skill_md"))

  # S1: Line count ≤200
  lines=$(wc -l < "$skill_md")
  if [ $lines -le 200 ]; then
    s1_status="✅"
    s1_pass=$((s1_pass + 1))
  else
    s1_status="❌ $lines lines"
  fi

  # S2: Has references/ if >200 lines
  skill_dir=$(dirname "$skill_md")
  if [ $lines -gt 200 ] && [ ! -d "$skill_dir/references" ]; then
    s2_status="❌ Missing refs"
  else
    s2_status="✅"
    s2_pass=$((s2_pass + 1))
  fi

  # S3: Description <200 chars, third person
  desc=$(grep "^description:" "$skill_md" | sed 's/description: //')
  desc_len=${#desc}
  if [ $desc_len -gt 200 ]; then
    s3_status="❌ $desc_len chars"
  elif echo "$desc" | grep -qE "^(Read|Write|Create|Extract|Research|Query|Configure|Detect|Generate|Install|Manage|Organize|Guide|Compile|Build|Send|Enable|Deploy|Handle|Format|Validate|Call|Track|Sync|Push|Check|Resolve) "; then
    s3_status="⚠️ Imperative"
  else
    s3_status="✅"
    s3_pass=$((s3_pass + 1))
  fi

  printf "%-40s | S1: %-15s | S2: %-15s | S3: %-15s\n" \
    "$skill_name" "$s1_status" "$s2_status" "$s3_status"
done

echo ""
echo "=== SUMMARY ==="
echo "S1 (≤200 lines):     $s1_pass/$total_skills ($(( s1_pass * 100 / total_skills ))%)"
echo "S2 (Progressive):    $s2_pass/$total_skills ($(( s2_pass * 100 / total_skills ))%)"
echo "S3 (Description):    $s3_pass/$total_skills ($(( s3_pass * 100 / total_skills ))%)"
echo ""

if [ $s1_pass -eq $total_skills ] && [ $s2_pass -eq $total_skills ] && [ $s3_pass -eq $total_skills ]; then
  echo "🎉 100% COMPLIANCE ACHIEVED!"
  exit 0
else
  echo "⚠️  Compliance gaps remain"
  exit 1
fi
