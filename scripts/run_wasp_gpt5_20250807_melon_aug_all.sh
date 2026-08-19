#!/usr/bin/env bash
set -euo pipefail

ROOT="$HOME/WASP-Baseline-Experiments"

echo "=================================================="
echo "GPT-5-2025-08-07 + MELON-Aug"
echo "FULL PIPELINE: BU42 + ATTACK84"
echo "=================================================="

cd "$ROOT"

echo
echo "===== PHASE 1: BENIGN BU42 ====="

bash scripts/run_wasp_gpt5_20250807_melon_aug_benign_bu.sh

BU="$ROOT/results/raw/wasp_gpt5_20250807_melon_aug_benign/benign_utility.json"

if [ ! -f "$BU" ]; then
    echo "ERROR: MELON-Aug BU result missing"
    exit 1
fi

echo
echo "===== BENIGN RESULT ====="
cat "$BU"

echo
echo "===== PHASE 2: ATTACK84 ====="

START_GROUP=0 \
MAX_RETRIES=3 \
RETRY_SLEEP=20 \
bash scripts/run_wasp_gpt5_20250807_melon_aug_full84_retry.sh

ATTACK="$ROOT/results/raw/wasp_gpt5_20250807_melon_aug_full84"

echo
echo "===== VERIFYING ALL ATTACK RESULTS ====="

for g in 0 1 2 3; do
    for f in \
        run_user_utility.json \
        run_step_by_step_asr.json \
        run_attacker_utility.json
    do
        if [ ! -f "$ATTACK/$g/$f" ]; then
            echo "ERROR: missing $ATTACK/$g/$f"
            exit 1
        fi
    done

    echo "GROUP $g: ALL 3 RESULTS PRESENT"
done

echo
echo "===== FINAL RESULTS ====="

for g in 0 1 2 3; do
    echo
    echo "================ GROUP $g ================"

    echo "--- User Utility ---"
    cat "$ATTACK/$g/run_user_utility.json"

    echo "--- Intermediate ASR ---"
    cat "$ATTACK/$g/run_step_by_step_asr.json"

    echo "--- End-to-End ASR ---"
    cat "$ATTACK/$g/run_attacker_utility.json"
done

echo
echo "=================================================="
echo "GPT-5 + MELON-Aug BU42 + ATTACK84 COMPLETED"
echo "ALL RESULT FILES VERIFIED"
echo "=================================================="
