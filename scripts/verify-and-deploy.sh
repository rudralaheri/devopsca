#!/bin/bash
set -eo pipefail

if [ -z "$IMAGE" ]; then
    echo "ERROR: IMAGE environment variable is required."
    echo "Usage: IMAGE=ghcr.io/owner/repo@sha256:... ./scripts/verify-and-deploy.sh"
    exit 1
fi

EXPECTED_ISSUER=${EXPECTED_ISSUER:-"https://token.actions.githubusercontent.com"}

if [ -z "$EXPECTED_IDENTITY_REGEX" ]; then
    echo "WARNING: EXPECTED_IDENTITY_REGEX is not set. In a real deployment, this should be pinned to the workflow path."
    # Fallback to allow generic matching if missing (helpful for testing, but warned)
    EXPECTED_IDENTITY_REGEX=".*"
fi

echo "Verifying image signature for $IMAGE..."
echo "Issuer: $EXPECTED_ISSUER"
echo "Identity Regex: $EXPECTED_IDENTITY_REGEX"

if ! cosign verify "$IMAGE" \
    --certificate-oidc-issuer "$EXPECTED_ISSUER" \
    --certificate-identity-regexp "$EXPECTED_IDENTITY_REGEX"; then
    
    echo "=================================================="
    echo "❌ SIGNATURE VERIFICATION FAILED."
    echo "The image is either unsigned, tampered with, or signed by an unauthorized identity."
    echo "Deployment rejected."
    echo "=================================================="
    exit 1
fi

echo "✅ Signature verified successfully."
echo "Deploying via Docker Compose..."

export IMAGE
docker compose -f docker-compose.yml up -d --remove-orphans

echo "Deployment initiated. Check status with: docker compose ps"
