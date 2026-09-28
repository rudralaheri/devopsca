# Zero-Trust DevSecOps Pipeline

This project demonstrates a complete software delivery pipeline where **every container image is treated as untrusted until cryptographically proven otherwise**.

It integrates automated SAST, SBOM generation, container vulnerability scanning, keyless cryptographic signing with Cosign, and an explicit deployment policy gate.

## Features & Technologies
- **App**: Node.js + Express (tested with Jest & Supertest)
- **Container**: Docker (Multi-stage, Non-root user)
- **SAST**: CodeQL / Semgrep
- **SBOM**: Syft
- **Vuln Scanning**: Trivy
- **Signing**: Cosign (Keyless via GitHub OIDC)
- **Policy Gate**: Bash + Cosign (documented with OPA/Rego)

## Running Locally

To run the application locally without the pipeline:

```bash
npm install
npm test
npm run lint
npm start
```

## How the Pipeline Works
The pipeline is defined in `.github/workflows/pipeline.yml` and consists of 5 hard gates:
1. **Lint & SAST**: Rejects code with syntax errors or identified security flaws.
2. **Tests**: Rejects failing application logic.
3. **Build & Scan**: Builds the image, generates an SBOM, and scans for Critical/High CVEs.
4. **Sign**: Cryptographically signs the image using Sigstore/Cosign.
5. **Policy Gate**: The deployment script (`scripts/verify-and-deploy.sh`) verifies the signature, issuer, and repository identity before allowing `docker compose up` to run.

## Demonstrating Attack Scenarios

The power of this pipeline is its enforcement. You can demonstrate the policy gate locally by simulating these attacks:

### 1. Unsigned / Untrusted Registry Attack
Attempt to deploy an image that hasn't been signed by our CI.
```bash
export IMAGE="nginx:latest"
./scripts/verify-and-deploy.sh
# Result: Rejected (No signature found)
```

### 2. Identity Confusion Attack
Simulate an attacker who signed the image with their own GitHub Actions, but from a different repository.
```bash
# Provide a valid image, but change the expected regex to a fake repo
export IMAGE="ghcr.io/your-username/zerotrust-devsecops:latest" 
export EXPECTED_IDENTITY_REGEX="^https://github.com/attacker/repo/.*"
./scripts/verify-and-deploy.sh
# Result: Rejected (Identity mismatch)
```

## Documentation
- [Architecture Diagram & Data Flow](docs/architecture.md)
- [Threat Model](docs/threat-model.md)
