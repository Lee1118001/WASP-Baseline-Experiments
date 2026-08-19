#!/usr/bin/env bash
set -euo pipefail

ROOT="$HOME/WASP-Baseline-Experiments"

echo "=================================================="
echo "GPT-5-2025-08-07 + IPIGuard"
echo "FULL PIPELINE: BU42 + ATTACK84"
echo "=================================================="

cd "$ROOT"

echo
echo "===== PHASE 1: BENIGN BU 42 ====="
bash scripts/run_wasp_gpt5_20250807_ipiguard_benign_bu.sh

echo
echo "===== BENIGN RESULT ====="
cat \
  results/raw/wasp_gpt5_20250807_ipiguard_benign/benign_utility.json

echo
echo "===== PHASE 1 COMPLETE ====="
echo "Benign cleanup and final Postmill reset must already be complete."
echo

echo "===== PHASE 2: ATTACK 84 ====="

START_GROUP=0 \
MAX_RETRIES=3 \
RETRY_SLEEP=20 \
bash scripts/run_wasp_gpt5_20250807_ipiguard_full84_retry.sh

echo
echo "===== ATTACK RESULTS ====="

ROOT_RESULT="$ROOT/results/raw/wasp_gpt5_20250807_ipiguard_full84"

for g in 0 1 2 3; do
    echo
    echo "================ GROUP $g ================"

    echo "--- User Utility ---"
    cat "$ROOT_RESULT/$g/run_user_utility.json"

    echo "--- Intermediate ASR ---"
    cat "$ROOT_RESULT/$g/run_step_by_step_asr.json"

    echo "--- End-to-End ASR ---"
    cat "$ROOT_RESULT/$g/run_attacker_utility.json"
done

echo
echo "=================================================="
echo "GPT-5 + IPIGuard BU42 + ATTACK84 COMPLETED"
echo "=================================================="
