#!/bin/bash
#===============================================================================
# SCALED (2x) HEFT GITHUB ACTIONS BENCHMARK RUNNER
#===============================================================================

N_RUNS=${1:-100}
REPO_OWNER="Kushcodingexe"
REPO_NAME="Argo-Workflow-Github-Actions-Kubernetes-Rack-Resiliency-Simulations"
WORKFLOW_FILE="rack-resiliency-scaled-heft.yml"
OUTPUT_DIR="/home/snu/kubernetes/comparison-logs/github-actions-scaled-heft"
SUMMARY_FILE="${OUTPUT_DIR}/benchmark_summary.csv"

GITHUB_TOKEN="${GITHUB_TOKEN:-}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=============================================="
echo "SCALED (2x) HEFT GITHUB ACTIONS BENCHMARK"
echo "=============================================="
echo "Runs: ${N_RUNS} | Scale: 2x | Scheduler: HEFT"
echo -e "==============================================${NC}"

[ -z "$GITHUB_TOKEN" ] && { echo -e "${RED}ERROR: GITHUB_TOKEN not set${NC}"; exit 1; }

mkdir -p "${OUTPUT_DIR}"
echo "run_id,run_number,start_epoch,end_epoch,duration_seconds,status,workflow_run_id,scale,scheduler" > "${SUMMARY_FILE}"

SUCCESSFUL_RUNS=0
FAILED_RUNS=0
TOTAL_DURATION=0

trigger() {
    curl -s -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/workflows/${WORKFLOW_FILE}/dispatches" \
        -d '{"ref":"main"}'
}

latest_run() {
    curl -s -H "Accept: application/vnd.github+json" -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs?per_page=1" | jq -r '.workflow_runs[0]'
}

wait_workflow() {
    local run_id=$1 waited=0
    while [ $waited -lt 7200 ]; do
        STATUS=$(curl -s -H "Accept: application/vnd.github+json" -H "Authorization: Bearer ${GITHUB_TOKEN}" \
            "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs/${run_id}" | jq -r '.status')
        [ "$STATUS" == "completed" ] && return 0
        echo "  ${STATUS}..."
        sleep 60
        waited=$((waited + 60))
    done
    return 1
}

conclusion() {
    curl -s -H "Accept: application/vnd.github+json" -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs/$1" | jq -r '.conclusion'
}

for i in $(seq 1 ${N_RUNS}); do
    RUN_ID="scaled-heft-gha-$(date +%Y%m%d-%H%M%S)-${i}"
    RUN_DIR="${OUTPUT_DIR}/${RUN_ID}"
    mkdir -p "${RUN_DIR}"
    
    echo -e "\n${YELLOW}========== SCALED HEFT RUN ${i}/${N_RUNS} ==========${NC}"
    START_EPOCH=$(date +%s)
    
    trigger
    sleep 15
    
    RUN=$(latest_run)
    RUN_ID_GH=$(echo "$RUN" | jq -r '.id')
    
    [ "$RUN_ID_GH" == "null" ] && {
        END_EPOCH=$(date +%s)
        echo "${RUN_ID},${i},${START_EPOCH},${END_EPOCH},$((END_EPOCH-START_EPOCH)),TRIGGER_FAILED,,2x,HEFT" >> "${SUMMARY_FILE}"
        FAILED_RUNS=$((FAILED_RUNS + 1))
        continue
    }
    
    echo "GitHub Run: ${RUN_ID_GH}"
    wait_workflow "${RUN_ID_GH}"
    RESULT=$(conclusion "${RUN_ID_GH}")
    
    END_EPOCH=$(date +%s)
    DURATION=$((END_EPOCH - START_EPOCH))
    TOTAL_DURATION=$((TOTAL_DURATION + DURATION))
    
    cat > "${RUN_DIR}/metrics.txt" << EOF
PLATFORM=GitHub_Actions_Scaled_HEFT
SCALE=2x
SCHEDULER=HEFT
RUN_ID=${RUN_ID}
DURATION_SECONDS=${DURATION}
STATUS=${RESULT}
EOF
    
    echo "${RUN_ID},${i},${START_EPOCH},${END_EPOCH},${DURATION},${RESULT},${RUN_ID_GH},2x,HEFT" >> "${SUMMARY_FILE}"
    
    [ "$RESULT" == "success" ] && { echo -e "${GREEN}✓ ${DURATION}s${NC}"; SUCCESSFUL_RUNS=$((SUCCESSFUL_RUNS + 1)); } || { echo -e "${RED}✗ ${RESULT}${NC}"; FAILED_RUNS=$((FAILED_RUNS + 1)); }
    
    [ $i -lt $N_RUNS ] && sleep 60
done

echo -e "\n${CYAN}===== COMPLETE: ${SUCCESSFUL_RUNS}/${N_RUNS} successful, avg $((TOTAL_DURATION / N_RUNS))s =====${NC}"
