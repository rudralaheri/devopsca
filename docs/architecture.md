# Architecture

This project implements a Zero-Trust DevSecOps pipeline. The core concept is that a container image is untrusted until cryptographically proven otherwise at deployment time.

## Pipeline Stages

```mermaid
graph TD
    A[Code Push] --> B(Stage 1: Lint & SAST)
    B -->|ESLint & CodeQL/Semgrep| C(Stage 2: Test)
    C -->|Jest Unit/Regression| D(Stage 3: Build & Scan)
    D -->|Docker Build, Syft SBOM, Trivy Scan| E(Stage 4: Sign)
    E -->|Cosign Keyless Signature| F(Stage 5: Policy Gate)
    F -->|Verify Signature, Identity, Issuer| G((Deployment))
    
    style B fill:#f97316,color:#fff
    style C fill:#eab308,color:#000
    style D fill:#3b82f6,color:#fff
    style E fill:#8b5cf6,color:#fff
    style F fill:#ef4444,color:#fff
    style G fill:#22c55e,color:#fff
```

## Data Flow
1. **Source Code** is pushed to GitHub.
2. **SAST (Static Application Security Testing)** scans the raw source for insecure patterns (e.g., CodeQL, Semgrep).
3. **Tests** confirm application logic.
4. **Build** produces a container image.
5. **SBOM Generation** creates a software bill of materials mapping all dependencies.
6. **Vulnerability Scanning** analyzes the final image for CVEs (Trivy).
7. **Keyless Signing** binds the container digest to the GitHub Actions OIDC identity using Cosign, recording it in the Rekor transparency log.
8. **Policy Gate** enforces deployment rules via `verify-and-deploy.sh` (or OPA Gatekeeper in Kubernetes), refusing to start if the image isn't correctly signed by the expected identity.
