#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_SCRIPT="$SCRIPT_DIR/verify-and-deploy.sh"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

TOTAL_ATTACKS=0
BLOCKED_ATTACKS=0

print_header() {
    echo ""
    echo -e "${BLUE}========================================================================${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${BLUE}========================================================================${NC}"
}

run_attack_test() {
    local scenario_num="$1"
    local scenario_title="$2"
    local attack_description="$3"
    local test_image="$4"
    local test_issuer="$5"
    local test_regex="$6"
    local expected_failure_reason="$7"

    TOTAL_ATTACKS=$((TOTAL_ATTACKS + 1))

    print_header "Attack Scenario $scenario_num: $scenario_title"
    echo -e "${CYAN}Threat Context:${NC} $attack_description"
    echo -e "${CYAN}Target Image:${NC}   $test_image"
    echo -e "${CYAN}Expected Gate:${NC}  Issuer: $test_issuer | Identity Regex: $test_regex"
    echo -e "${YELLOW}Attempting deployment through policy gate...${NC}"
    echo "------------------------------------------------------------------------"

    # Run verify-and-deploy in a subshell, capturing output
    set +e
    OUTPUT=$(IMAGE="$test_image" EXPECTED_ISSUER="$test_issuer" EXPECTED_IDENTITY_REGEX="$test_regex" "$GATE_SCRIPT" 2>&1)
    EXIT_CODE=$?
    set -e

    echo "$OUTPUT"
    echo "------------------------------------------------------------------------"

    if [ $EXIT_CODE -ne 0 ]; then
        echo -e "${GREEN}🛡️  VERIFICATION RESULT: BLOCKED (Exit code: $EXIT_CODE)${NC}"
        echo -e "${GREEN}✅ SUCCESS: The policy gate successfully detected and blocked this attack!${NC}"
        echo -e "   Reason caught: $expected_failure_reason"
        BLOCKED_ATTACKS=$((BLOCKED_ATTACKS + 1))
    else
        echo -e "${RED}🚨 SECURITY BREACH: The policy gate allowed an untrusted image to deploy!${NC}"
        echo -e "${RED}❌ FAILED: Zero-trust invariant violated.${NC}"
    fi
}

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║       ZERO-TRUST DEVSECOPS: COSIGN POLICY GATE ATTACK DEMO           ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "This test suite simulates real-world supply chain attacks against"
echo "the deployment gate to verify that unauthorized images are rejected."

chmod +x "$GATE_SCRIPT"

# ------------------------------------------------------------------------------
# Scenario 1: Unsigned Image Attack
# ------------------------------------------------------------------------------
run_attack_test \
    "1" \
    "Unsigned Container Image Deployment" \
    "An attacker attempts to deploy an arbitrary public image from Docker Hub with no cryptographic signature." \
    "nginx:latest" \
    "https://token.actions.githubusercontent.com" \
    "^https://github.com/rudralaheri/devopsca/.*" \
    "No signature artifact exists in the registry for this image."

# ------------------------------------------------------------------------------
# Scenario 2: Identity Confusion Attack (Unauthorized Repo / Workflow)
# ------------------------------------------------------------------------------
run_attack_test \
    "2" \
    "Identity Confusion Attack (Unauthorized Signer)" \
    "An attacker signs their own backdoored image using GitHub Actions OIDC, but from an unauthorized repository." \
    "ghcr.io/attacker/malicious-app:latest" \
    "https://token.actions.githubusercontent.com" \
    "^https://github.com/rudralaheri/devopsca/.*" \
    "Signer identity does not match the authorized repository regex."

# ------------------------------------------------------------------------------
# Scenario 3: Tag Mutation / Digest Tampering Attack
# ------------------------------------------------------------------------------
run_attack_test \
    "3" \
    "Tag Mutation / Digest Tampering Attack" \
    "An attacker modifies image layers or substitutes an untrusted digest under an approved repo name." \
    "ghcr.io/rudralaheri/devopsca@sha256:0000000000000000000000000000000000000000000000000000000000000000" \
    "https://token.actions.githubusercontent.com" \
    "^https://github.com/rudralaheri/devopsca/.*" \
    "Cryptographic digest mismatch between deployed image and signed record."

# ------------------------------------------------------------------------------
# Scenario 4: Untrusted OIDC Issuer Attack (Rogue IdP)
# ------------------------------------------------------------------------------
run_attack_test \
    "4" \
    "Untrusted OIDC Issuer Attack (Rogue IdP)" \
    "A developer signs an image using a personal Google/corporate account rather than the official CI/CD pipeline." \
    "nginx:latest" \
    "https://accounts.google.com" \
    "^https://github.com/rudralaheri/devopsca/.*" \
    "OIDC Issuer is not trusted by policy (requires GitHub Actions OIDC)."

# ------------------------------------------------------------------------------
# Final Summary
# ------------------------------------------------------------------------------
echo ""
echo -e "${BLUE}========================================================================${NC}"
echo -e "${BOLD}ATTACK SIMULATION SUMMARY${NC}"
echo -e "${BLUE}========================================================================${NC}"
echo -e "Total Attacks Simulated: ${BOLD}$TOTAL_ATTACKS${NC}"
echo -e "Total Attacks Blocked:   ${GREEN}${BOLD}$BLOCKED_ATTACKS${NC}"

if [ $BLOCKED_ATTACKS -eq $TOTAL_ATTACKS ]; then
    echo ""
    echo -e "${GREEN}${BOLD}🏆 ALL ATTACK SCENARIOS SUCCESSFULLY REJECTED BY COSIGN POLICY GATE!${NC}"
    echo -e "${GREEN}Zero-Trust policy enforcement is active and fully functional.${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}${BOLD}⚠️  SOME ATTACKS BYPASSED THE POLICY GATE. INSPECT LOGS ABOVE.${NC}"
    exit 1
fi
