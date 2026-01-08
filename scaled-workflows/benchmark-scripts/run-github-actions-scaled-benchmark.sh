#!/bin/bash
#===============================================================================
# SCALED (2x) GITHUB ACTIONS BENCHMARK RUNNER
# Triggers scaled GitHub Actions workflow N times
#===============================================================================

N_RUNS=${1:-100}
REPO_OWNER="Kushcodingexe"
REPO_NAME="Argo-Workflow-Github-Actions-Kubernetes-Rack-Resiliency-Simulations"
WORKFLOW_FILE="rack-resiliency-scaled.yml"
OUTPUT_DIR="/home/snu/kubernetes/comparison-logs/github-actions-scaled"
SUMMARY_FILE="${OUTPUT_DIR}/benchmark_summary.csv"

GITHUB_TOKEN="${GITHUB_TOKEN:-}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=============================================="
echo "SCALED (2x) GITHUB ACTIONS BENCHMARK RUNNER"
echo "=============================================="
echo "Number of runs: ${N_RUNS}"
echo "Repository: ${REPO_OWNER}/${REPO_NAME}"
echo "Workflow: ${WORKFLOW_FILE}"
echo "Scale: 6 HC, 2 Node Sim, 2 Rack Sim"
echo -e "==============================================${NC}"

if [ -z "$GITHUB_TOKEN" ]; then
    echo -e "${RED}ERROR: GITHUB_TOKEN not set${NC}"
    exit 1
fi

mkdir -p "${OUTPUT_DIR}"
echo "run_id,run_number,start_epoch,end_epoch,duration_seconds,status,workflow_run_id,scale" > "${SUMMARY_FILE}"

SUCCESSFUL_RUNS=0
FAILED_RUNS=0
TOTAL_DURATION=0

trigger_workflow() {
    curl -s -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/workflows/${WORKFLOW_FILE}/dispatches" \
        -d '{"ref":"main"}'
}

get_latest_run() {
    curl -s \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs?per_page=1" \
        | jq -r '.workflow_runs[0]'
}

wait_for_workflow() {
    local run_id=$1
    local max_wait=7200
    local wait_interval=60
    local waited=0
    
    while [ $waited -lt $max_wait ]; do
        STATUS=$(curl -s \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer ${GITHUB_TOKEN}" \
            "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs/${run_id}" \
            | jq -r '.status')
        
        if [ "$STATUS" == "completed" ]; then
            return 0
        fi
        
        echo "  Workflow ${STATUS}, waiting ${wait_interval}s..."
        sleep $wait_interval
        waited=$((waited + wait_interval))
    done
    
    return 1
}

get_conclusion() {
    local run_id=$1
    curl -s \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs/${run_id}" \
        | jq -r '.conclusion'
}

for i in $(seq 1 ${N_RUNS}); do
    RUN_ID="scaled-gha-$(date +%Y%m%d-%H%M%S)-${i}"
    RUN_DIR="${OUTPUT_DIR}/${RUN_ID}"
    mkdir -p "${RUN_DIR}"
    
    echo ""
    echo -e "${YELLOW}========== SCALED RUN ${i}/${N_RUNS} ==========${NC}"
    echo "Run ID: ${RUN_ID}"
    
    START_EPOCH=$(date +%s)
    
    trigger_workflow
    sleep 15
    
    WORKFLOW_RUN=$(get_latest_run)
    WORKFLOW_RUN_ID=$(echo "$WORKFLOW_RUN" | jq -r '.id')
    
    if [ "$WORKFLOW_RUN_ID" == "null" ] || [ -z "$WORKFLOW_RUN_ID" ]; then
        echo -e "${RED}Failed to get workflow run ID${NC}"
        END_EPOCH=$(date +%s)
        DURATION=$((END_EPOCH - START_EPOCH))
        echo "${RUN_ID},${i},${START_EPOCH},${END_EPOCH},${DURATION},TRIGGER_FAILED,,2x" >> "${SUMMARY_FILE}"
        FAILED_RUNS=$((FAILED_RUNS + 1))
        continue
    fi
    
    echo "Workflow Run ID: ${WORKFLOW_RUN_ID}"
    
    wait_for_workflow "${WORKFLOW_RUN_ID}"
    CONCLUSION=$(get_conclusion "${WORKFLOW_RUN_ID}")
    
    END_EPOCH=$(date +%s)
    DURATION=$((END_EPOCH - START_EPOCH))
    TOTAL_DURATION=$((TOTAL_DURATION + DURATION))
    
    curl -s \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs/${WORKFLOW_RUN_ID}" \
        > "${RUN_DIR}/workflow_run.json"
    
    cat > "${RUN_DIR}/metrics.txt" << EOF
# Scaled (2x) GitHub Actions Metrics
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

PLATFORM=GitHub_Actions_Scaled
SCALE=2x
RUN_ID=${RUN_ID}
RUN_NUMBER=${i}
GITHUB_RUN_ID=${WORKFLOW_RUN_ID}
START_EPOCH=${START_EPOCH}
END_EPOCH=${END_EPOCH}
DURATION_SECONDS=${DURATION}
STATUS=${CONCLUSION}
EOF
    
    echo "${RUN_ID},${i},${START_EPOCH},${END_EPOCH},${DURATION},${CONCLUSION},${WORKFLOW_RUN_ID},2x" >> "${SUMMARY_FILE}"
    
    if [ "$CONCLUSION" == "success" ]; then
        echo -e "${GREEN}✓ Scaled Run ${i} completed in ${DURATION}s${NC}"
        SUCCESSFUL_RUNS=$((SUCCESSFUL_RUNS + 1))
    else
        echo -e "${RED}✗ Scaled Run ${i} failed: ${CONCLUSION}${NC}"
        FAILED_RUNS=$((FAILED_RUNS + 1))
    fi
    
    if [ $i -lt $N_RUNS ]; then
        sleep 60
    fi
done

AVG_DURATION=$((TOTAL_DURATION / N_RUNS))

echo ""
echo -e "${CYAN}=============================================="
echo "SCALED GITHUB ACTIONS BENCHMARK COMPLETE"
echo "=============================================="
echo "Total runs: ${N_RUNS}"
echo "Successful: ${SUCCESSFUL_RUNS}"
echo "Failed: ${FAILED_RUNS}"
echo "Average duration: ${AVG_DURATION}s"
echo -e "==============================================${NC}"

cat > "${OUTPUT_DIR}/final_summary.txt" << EOF
SCALED (2x) GITHUB ACTIONS BENCHMARK SUMMARY
=============================================
Date: $(date '+%Y-%m-%d %H:%M:%S')
Scale: 2x
Total Runs: ${N_RUNS}
Successful: ${SUCCESSFUL_RUNS}
Failed: ${FAILED_RUNS}
Success Rate: $(echo "scale=2; ${SUCCESSFUL_RUNS}*100/${N_RUNS}" | bc)%
Average Duration: ${AVG_DURATION} seconds
EOF

echo "Done!"
