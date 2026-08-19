#!/usr/bin/env bash
set -euo pipefail

ROOT="$HOME/WASP-Baseline-Experiments"
PI="$ROOT/benchmark/wasp/webarena_prompt_injections"
VWA="$ROOT/benchmark/wasp/visualwebarena"

MODEL="gpt-4o"
CONFIG="configs/experiment_config.raw.json"
SYSTEM_PROMPT="configs/system_prompts/wa_p_cot_id_actree_3s.json"

OUT_ROOT="$ROOT/results/raw/wasp_gpt4o_nodefense_benign"
LOG_ROOT="$ROOT/results/logs/gpt4o_nodefense_benign"

mkdir -p "$OUT_ROOT" "$LOG_ROOT"

source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate wasp

source "$ROOT/.env.webarena"

set -a
source "$ROOT/.env.openai"
set +a

# ---------- network ----------
# OpenAI uses Windows SSRDOG through reverse SSH tunnel.
export ALL_PROXY="socks5h://127.0.0.1:19567"
export all_proxy="$ALL_PROXY"

# WebArena internal services MUST bypass proxy.
export NO_PROXY="127.0.0.1,localhost,10.176.60.153,172.17.0.1"
export no_proxy="$NO_PROXY"

export DATASET=webarena_prompt_injections
export MODEL="$MODEL"

# ---------- benign / no defense ----------
export WASP_BENIGN=1
unset WASP_DEFENSE || true

export PYTHONPATH="$ROOT/scripts:${PYTHONPATH:-}"

TOTAL_SCORE=0
TOTAL_TASKS=0


reset_forum() {
    echo "=================================================="
    echo "RESETTING POSTMILL TO CLEAN IMAGE"
    echo "=================================================="

    docker rm -f forum >/dev/null 2>&1 || true

    docker run \
        --name forum \
        -p 9999:80 \
        -e RATELIMIT_WHITELIST=0.0.0.0/0,::/0 \
        -d \
        postmill-populated-exposed-withimg \
        >/dev/null

    for i in $(seq 1 60); do
        if curl -fsS --max-time 5 \
            http://127.0.0.1:9999/ >/dev/null 2>&1; then
            echo "Postmill ready"
            return 0
        fi
        sleep 2
    done

    echo "ERROR: Postmill failed to become ready"
    docker logs forum --tail 100 || true
    return 1
}


cleanup_goal() {
    local goal="$1"
    local cfg="$OUT_ROOT/goal_${goal}/instantiated_prompt_injections_config.json"

    echo
    echo "=================================================="
    echo "CLEANUP GOAL $goal"
    echo "=================================================="

    if [ ! -f "$cfg" ]; then
        echo "ERROR: cleanup config missing: $cfg"
        return 1
    fi

    cd "$PI"

    python environment_cleanup.py \
        --prompt-injection-config-path "$cfg" \
        --gitlab-domain "$GITLAB" \
        --reddit-domain "$REDDIT"

    echo "GOAL $goal CLEANUP FINISHED"
}


run_goal() {
    local GOAL_IDX="$1"
    local OUT="$OUT_ROOT/goal_${GOAL_IDX}"
    local LOG="$LOG_ROOT/goal_${GOAL_IDX}.log"

    rm -rf "$OUT"
    mkdir -p "$OUT"

    echo "==================================================" | tee "$LOG"
    echo "GPT-4o BENIGN BU: goal=$GOAL_IDX" | tee -a "$LOG"
    echo "==================================================" | tee -a "$LOG"

    # Every goal starts from a clean Postmill.
    reset_forum | tee -a "$LOG"

    cd "$PI"

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

    # ---------- run WebArena ----------
    cd "$VWA"

    chmod -R 777 "$OUT"

    bash "$OUT/run_agent.sh" \
        2>&1 | tee -a "$LOG"

    # ---------- evaluate USER utility ----------
    bash prepare.sh >/dev/null 2>&1 || true

    python evaluator_final_step.py \
        --log-folder "$OUT/agent_logs/" \
        --task-folder "$OUT/webarena_tasks/" \
        2>&1 | tee -a "$LOG"

    if [ ! -f /tmp/run_user_utility.json ]; then
        echo "ERROR: /tmp/run_user_utility.json missing" | tee -a "$LOG"
        return 1
    fi

    cp /tmp/run_user_utility.json \
       "$OUT/run_user_utility.json"

    read SCORE TASKS < <(
        python - "$OUT/run_user_utility.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as f:
    d = json.load(f)

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

    # CRITICAL:
    # cleanup this goal BEFORE the next goal is allowed to start.
    cleanup_goal "$GOAL_IDX" \
        2>&1 | tee -a "$LOG"

    echo "GOAL $GOAL_IDX COMPLETE AND CLEAN" | tee -a "$LOG"
}


# ==========================================================
# GOAL 0
# ==========================================================

run_goal 0

# Belt-and-suspenders:
# goal1 gets ANOTHER fresh Postmill inside run_goal().
echo
echo "GOAL 0 FINISHED. GOAL 1 WILL START FROM CLEAN ENVIRONMENT."


# ==========================================================
# GOAL 1
# ==========================================================

run_goal 1


# ==========================================================
# FINAL CLEAN POSTMILL FOR NEXT EXPERIMENT
# ==========================================================

reset_forum

unset WASP_BENIGN || true


# ==========================================================
# SUMMARY
# ==========================================================

python - <<PY
import json
from pathlib import Path

score = float("$TOTAL_SCORE")
tasks = float("$TOTAL_TASKS")
bu = score / tasks if tasks else 0.0

out = Path("$OUT_ROOT/benign_utility.json")

out.write_text(
    json.dumps(
        {
            "model": "$MODEL",
            "defense": "none",
            "total_scores": score,
            "cnt_tasks": tasks,
            "BU": bu,
            "BU_percent": bu * 100,
            "goal_0_cleaned": True,
            "goal_1_cleaned": True,
            "final_forum_reset": True
        },
        indent=2
    )
)

print()
print("==========================================")
print(f"GPT-4o BENIGN TOTAL: {score:.0f}/{tasks:.0f}")
print(f"BU = {bu*100:.2f}%")
print("goal0 cleanup = YES")
print("goal1 cleanup = YES")
print("final Postmill reset = YES")
print("==========================================")
print(out)
PY
