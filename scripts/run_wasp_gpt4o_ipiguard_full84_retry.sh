#!/usr/bin/env bash
set -euo pipefail

ROOT="$HOME/WASP-Baseline-Experiments"
PI="$ROOT/benchmark/wasp/webarena_prompt_injections"

MODEL="gpt-4o"
CONFIG="configs/experiment_config.raw.json"
SYSTEM_PROMPT="configs/system_prompts/wa_p_cot_id_actree_3s.json"

OUT_ROOT="$ROOT/results/raw/wasp_gpt4o_ipiguard_full84"
LOG_ROOT="$ROOT/results/logs/gpt4o_ipiguard_full84"

MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_SLEEP="${RETRY_SLEEP:-20}"

mkdir -p "$OUT_ROOT" "$LOG_ROOT"

source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate wasp

source "$ROOT/.env.webarena"

unset OPENAI_BASE_URL || true
unset OPENAI_API_BASE || true

set -a
source "$ROOT/.env.openai"
set +a

unset OPENAI_BASE_URL || true
unset OPENAI_API_BASE || true

export DATASET=webarena_prompt_injections
export MODEL="$MODEL"

unset WASP_BENIGN || true
export WASP_DEFENSE=ipiguard

export PYTHONPATH="$ROOT/defenses/ipiguard/agentdojo/src:$ROOT/scripts:${PYTHONPATH:-}"

# OpenAI through Windows SSRDOG tunnel
export ALL_PROXY="socks5h://127.0.0.1:19567"
export all_proxy="$ALL_PROXY"

# WebArena internal services bypass proxy
export NO_PROXY="127.0.0.1,localhost,10.176.60.153,172.17.0.1"
export no_proxy="$NO_PROXY"

cd "$PI"

injections=(
  "goal_hijacking_plain_text"
  "goal_hijacking_url_injection"
)

reset_forum() {
    echo "===== resetting Postmill ====="

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
    return 1
}

is_retryable_error() {
    local logfile="$1"

    grep -Eq \
'TimeoutError|Request timed out|Page\.goto: Timeout|Page\.captureScreenshot|TargetClosedError|APIConnectionError|Connection error|ConnectError|timed out|Tracing\.stop: ENOENT|playwright-artifacts|Failed to create a post' \
    "$logfile"
}

run_group() {
    local goal_idx="$1"
    local injection_idx="$2"
    local output_idx=$((goal_idx * 2 + injection_idx))
    local injection="${injections[$injection_idx]}"

    local out_dir="$OUT_ROOT/$output_idx/"
    local log_file="$LOG_ROOT/group_${output_idx}.log"
    local attempt=1

    while true; do
        echo "==================================================" | tee -a "$log_file"
        echo "group=$output_idx goal=$goal_idx injection=$injection attempt=$attempt" | tee -a "$log_file"
        echo "==================================================" | tee -a "$log_file"

        reset_forum || return 1
        rm -rf "$out_dir"

        set +e

        bash scripts/run_end_to_end.sh \
          "$out_dir" \
          "$MODEL" \
          "$SYSTEM_PROMPT" \
          "$CONFIG" \
          "$goal_idx" \
          "$injection" \
          webarena \
          2>&1 | tee -a "$log_file"

        status=${PIPESTATUS[0]}
        set -e

        if [ "$status" -eq 0 ]; then
            echo "GROUP $output_idx SUCCESS" | tee -a "$log_file"

            [ -f /tmp/run_step_by_step_asr.json ] && \
              cp /tmp/run_step_by_step_asr.json \
                 "$out_dir/run_step_by_step_asr.json"

            [ -f /tmp/run_attacker_utility.json ] && \
              cp /tmp/run_attacker_utility.json \
                 "$out_dir/run_attacker_utility.json"

            [ -f /tmp/run_user_utility.json ] && \
              cp /tmp/run_user_utility.json \
                 "$out_dir/run_user_utility.json"

            return 0
        fi

        if is_retryable_error "$log_file"; then
            if [ "$attempt" -ge "$MAX_RETRIES" ]; then
                echo "GROUP $output_idx FAILED after $MAX_RETRIES retries" \
                  | tee -a "$log_file"
                return 1
            fi

            echo "Retryable error detected." | tee -a "$log_file"
            echo "Retrying group $output_idx in ${RETRY_SLEEP}s..." \
              | tee -a "$log_file"

            sleep "$RETRY_SLEEP"
            attempt=$((attempt + 1))
            continue
        fi

        echo "NON-RETRYABLE ERROR in group $output_idx" \
          | tee -a "$log_file"

        return "$status"
    done
}

START_GROUP="${START_GROUP:-0}"

for goal_idx in 0 1; do
    for injection_idx in 0 1; do
        group_idx=$((goal_idx * 2 + injection_idx))

        if [ "$group_idx" -lt "$START_GROUP" ]; then
            echo "Skipping completed group $group_idx"
            continue
        fi

        run_group "$goal_idx" "$injection_idx" || exit 1
    done
done

echo "ALL 4 GROUPS COMPLETED"
