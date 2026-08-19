#!/usr/bin/env bash
set -euo pipefail

ROOT="$HOME/WASP-Baseline-Experiments"
PI="$ROOT/benchmark/wasp/webarena_prompt_injections"
VWA="$ROOT/benchmark/wasp/visualwebarena"

MODEL="${MODEL:-qwen3-max-2026-01-23}"
DEFENSE="${DEFENSE:-none}"

CONFIG="configs/experiment_config.raw.json"
SYSTEM_PROMPT="configs/system_prompts/wa_p_cot_id_actree_3s.json"

OUT_ROOT="$ROOT/results/raw/wasp_qwen3max_${DEFENSE}_benign"
LOG_ROOT="$ROOT/results/logs/qwen3max_${DEFENSE}_benign"

mkdir -p "$OUT_ROOT" "$LOG_ROOT"

source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate wasp

source "$ROOT/.env.webarena"
source "$ROOT/.env.qwen"

export DATASET=webarena_prompt_injections
export MODEL="$MODEL"
export OPENAI_BASE_URL="$OPENAI_API_BASE"
export WASP_BENIGN=1
export PYTHONPATH="$ROOT/defenses/ipiguard/agentdojo/src:$ROOT/scripts:$PYTHONPATH"

case "$DEFENSE" in
    none)
        unset WASP_DEFENSE || true
        ;;
    ipiguard)
        export WASP_DEFENSE=ipiguard
        ;;
    melon_aug)
        export WASP_DEFENSE=melon_aug
        ;;
    *)
        echo "Unknown DEFENSE=$DEFENSE"
        exit 1
        ;;
esac

TOTAL_SCORE=0
TOTAL_TASKS=0

cd "$PI"

for GOAL_IDX in 0 1; do
    OUT="$OUT_ROOT/goal_${GOAL_IDX}"
    LOG="$LOG_ROOT/goal_${GOAL_IDX}.log"

    rm -rf "$OUT"
    mkdir -p "$OUT"

    echo "==================================================" | tee "$LOG"
    echo "BENIGN BU: defense=$DEFENSE goal=$GOAL_IDX" | tee -a "$LOG"
    echo "==================================================" | tee -a "$LOG"

    # ---------- generate benign tasks ----------
    python prompt_injector.py \
        --config "$CONFIG" \
        --gitlab-domain "$GITLAB" \
        --reddit-domain "$REDDIT" \
        --model "$MODEL" \
        --system_prompt "$SYSTEM_PROMPT" \
        --output-dir "$OUT" \
        --user_goal_idx "$GOAL_IDX" \
        --injection_format goal_hijacking_plain_text \
        --output-format webarena \
        2>&1 | tee -a "$LOG"

    # ---------- run WebArena agent ----------
    cd "$VWA"

    chmod -R 777 "$OUT"

    bash "$OUT/run_agent.sh" 2>&1 | tee -a "$LOG"

    # ---------- evaluate USER task only ----------
    bash prepare.sh >/dev/null 2>&1 || true

    python evaluator_final_step.py \
        --log-folder "$OUT/agent_logs/" \
        --task-folder "$OUT/webarena_tasks/" \
        2>&1 | tee -a "$LOG"

    if [ ! -f /tmp/run_user_utility.json ]; then
        echo "ERROR: /tmp/run_user_utility.json missing"
        exit 1
    fi

    cp /tmp/run_user_utility.json \
       "$OUT/run_user_utility.json"

    read SCORE TASKS < <(
        python - "$OUT/run_user_utility.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(d["total_scores"], d["cnt_tasks"])
PY
    )

    TOTAL_SCORE=$(python - <<PY
print(float("$TOTAL_SCORE") + float("$SCORE"))
PY
)

    TOTAL_TASKS=$(python - <<PY
print(float("$TOTAL_TASKS") + float("$TASKS"))
PY
)

    cd "$PI"
done

python - <<PY
import json
from pathlib import Path

score = float("$TOTAL_SCORE")
tasks = float("$TOTAL_TASKS")
bu = score / tasks if tasks else 0.0

out = Path("$OUT_ROOT/benign_utility.json")
out.write_text(json.dumps({
    "total_scores": score,
    "cnt_tasks": tasks,
    "BU": bu,
    "BU_percent": bu * 100,
}, indent=2))

print()
print("==========================================")
print(f"BENIGN TOTAL: {score:.0f}/{tasks:.0f}")
print(f"BU = {bu*100:.2f}%")
print("==========================================")
print(out)
PY

unset WASP_BENIGN
