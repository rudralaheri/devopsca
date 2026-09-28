# Zero-Trust DevSecOps Pipeline

> **KJ Somaiya College of Engineering — Semester 7 DevOps Lab CA**
> **Student:** Rudra Laheri | **Repository:** [rudralaheri/devopsca](https://github.com/rudralaheri/devopsca)

A production-grade, automated CI/CD pipeline that enforces a **Zero-Trust security model** throughout the software supply chain. Every component of the delivery process is treated as untrusted by default and must cryptographically prove its integrity before deployment is allowed.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Technology Stack](#2-technology-stack)
3. [Repository Structure](#3-repository-structure)
4. [The Application](#4-the-application)
5. [Pipeline Architecture](#5-pipeline-architecture)
6. [Running Locally](#6-running-locally)
7. [Attack Demo Scenarios](#7-attack-demo-scenarios)
8. [Key Design Decisions](#8-key-design-decisions)
9. [Further Documentation](#9-further-documentation)

---

## 1. Project Overview

Traditional CI/CD pipelines focus on **speed**: build fast, deploy fast. This project demonstrates what happens when you add **security as a hard gate at every step**:

| Traditional Pipeline | Zero-Trust Pipeline (This Project) |
|---|---|
| Build → Test → Deploy | Lint → SAST → Test → Build → SBOM → Scan → Sign → Verify → Deploy |
| Trust the registry | Trust nothing; verify cryptographically |
| Deploy any image | Only deploy images signed by this exact repository's CI |
| Scan manually or never | Automated CVE scanning breaks the build |

### Core Principle
> *"If the image is unsigned, tampered with, or built by anyone other than this pipeline — it does not get deployed. Full stop."*

---

## 2. Technology Stack

### Application Layer
| Tool | Role |
|---|---|
| **Node.js v22** | JavaScript runtime |
| **Express.js v4.21+** | REST API framework |
| **Jest** | Unit & regression test runner |
| **Supertest** | HTTP assertion library for Express |
| **ESLint** | Static code linting |

### Pipeline & CI/CD
| Tool | Role |
|---|---|
| **GitHub Actions** | Pipeline orchestration engine (5 automated stages) |
| **GitHub Container Registry (GHCR)** | Container image registry |

### Security & DevSecOps
| Tool | Role | Stage |
|---|---|---|
| **CodeQL** | Deep semantic SAST (finds logic-level security flaws) | 1 |
| **Semgrep** | Fast SAST pattern matching (OWASP Top 10) | 1 |
| **Syft** | Software Bill of Materials (SBOM) generation | 3 |
| **Trivy** | Container & OS vulnerability (CVE) scanner | 3 |
| **Cosign / Sigstore** | Keyless cryptographic image signing via OIDC | 4 |
| **Bash Policy Gate** | Enforces Zero-Trust deployment policy | 5 |
| **OPA / Rego** | Policy-as-code documentation | — |

### Containerization
| Tool | Role |
|---|---|
| **Docker** | Multi-stage container build with non-root user |
| **Docker Compose** | Local orchestration target for deployment |

---

## 3. Repository Structure

```
.
├── .github/
│   └── workflows/
│       └── pipeline.yml        # The 5-stage CI/CD pipeline definition
├── docs/
│   ├── architecture.md         # Pipeline architecture & data flow
│   └── threat-model.md         # Threat model & security decisions
├── policy/
│   └── image_signature.rego    # OPA/Rego policy (documented rules)
├── scripts/
│   └── verify-and-deploy.sh    # The Zero-Trust policy gate script
├── src/
│   └── app.js                  # Express REST API application
├── test/
│   └── app.test.js             # Jest unit & regression tests (7 tests)
├── .dockerignore               # Files excluded from Docker build context
├── .eslintrc.json              # ESLint configuration
├── .trivyignore                # Known acceptable CVEs (documented risk acceptance)
├── docker-compose.yml          # Deployment configuration
├── Dockerfile                  # Multi-stage, non-root container definition
└── package.json                # Node.js dependencies & scripts
```

---

## 4. The Application

A minimal **Task List REST API** built with Express.js. It exists solely as the artifact that travels through the pipeline.

### Endpoints

| Method | Endpoint | Description | Response |
|---|---|---|---|
| `GET` | `/health` | Health check | `200 { status: "ok" }` |
| `GET` | `/api/tasks` | List all tasks | `200 [ ...tasks ]` |
| `GET` | `/api/tasks/:id` | Get a task by ID | `200 { task }` or `404` |
| `POST` | `/api/tasks` | Create a new task | `201 { task }` or `400` |

### Test Coverage

```
Tests:       7 passed, 7 total
Coverage:    88.88% Statements | 70% Branches | 83.33% Functions | 88% Lines
```

---

## 5. Pipeline Architecture

The pipeline is defined in [`.github/workflows/pipeline.yml`](.github/workflows/pipeline.yml) and triggers on every push to `main`. Each stage uses `needs:` to enforce strict sequential execution — **a single failure anywhere stops the entire chain**.

```
Code Push
    │
    ▼
┌─────────────────────────────────┐
│  Stage 1: Lint & SAST           │  ← ESLint, CodeQL, Semgrep
│  Fails if: code errors or       │
│  security flaws detected        │
└───────────────┬─────────────────┘
                │ (needs: Stage 1)
                ▼
┌─────────────────────────────────┐
│  Stage 2: Automated Testing     │  ← Jest + Supertest
│  Fails if: any test fails       │
└───────────────┬─────────────────┘
                │ (needs: Stage 2)
                ▼
┌─────────────────────────────────┐
│  Stage 3: Build, SBOM & Scan    │  ← Docker Build, Syft, Trivy
│  Fails if: CRITICAL/HIGH CVE    │
│  found (that has a known fix)   │
└───────────────┬─────────────────┘
                │ (needs: Stage 3)
           ┌────┴────┐
           ▼         ▼
┌──────────────┐   (Stage 5 waits)
│  Stage 4:    │
│  Keyless     │  ← Cosign signs via GitHub OIDC
│  Signing     │    Records to Rekor transparency log
└──────┬───────┘
       │ (needs: Stage 3 + Stage 4)
       ▼
┌─────────────────────────────────┐
│  Stage 5: Policy-Gated Deploy   │  ← verify-and-deploy.sh
│  Fails if: image is unsigned,   │
│  from wrong repo, or tampered   │
└───────────────┬─────────────────┘
                │
                ▼
           ✅ DEPLOYED
```

### Stage-by-Stage Breakdown

#### Stage 1 — Lint & SAST
- **ESLint** checks code style and syntax errors.
- **CodeQL** performs deep semantic analysis. It understands how data flows through your code and flags patterns like SQL injection or path traversal.
- **Semgrep** runs fast pattern matching against the OWASP Top 10 ruleset.
- Results are uploaded to the GitHub Security tab as SARIF reports.

#### Stage 2 — Automated Testing
- All 7 **Jest** tests run using `supertest` to simulate HTTP requests.
- A code coverage report is uploaded as a workflow artifact (kept for 7 days).
- The pipeline is blocked if any test fails.

#### Stage 3 — Build, SBOM & Scan
- **Docker** builds a multi-stage, hardened container image (see [Dockerfile](#dockerfile-design)).
- **Syft** generates an SPDX-format **Software Bill of Materials** cataloguing every package inside the image.
- **Trivy** scans the image for known CVEs, failing the build on any `CRITICAL` or `HIGH` severity issue that has a known fix available.
- Once clean, the image is pushed to **GHCR**.

#### Stage 4 — Keyless Signing
- **Cosign** signs the image **keylessly** — no private key is stored anywhere. Instead, it uses the **GitHub Actions OIDC token** to prove its identity.
- The signature is recorded in the **Rekor public transparency log** (an immutable, public audit trail).
- The SBOM is attached to the image as a Cosign attestation.

#### Stage 5 — Policy-Gated Deployment
The [`scripts/verify-and-deploy.sh`](scripts/verify-and-deploy.sh) script is the heart of the Zero-Trust model. Before calling `docker compose up`, it runs `cosign verify` and checks **three conditions**:

1. ✅ A valid cryptographic **signature** exists for the image.
2. ✅ The **issuer** is `https://token.actions.githubusercontent.com` (proving it came from GitHub Actions).
3. ✅ The **identity regex** matches this exact repository's workflow path (preventing identity confusion attacks).

If any one of these fails, deployment is **rejected** with an explicit error message.

---

### Dockerfile Design

The Dockerfile uses two key security best practices:

```dockerfile
# Multi-Stage Build: Only production deps end up in final image
FROM node:22-alpine AS build
RUN apk update && apk upgrade   # Patch OS vulnerabilities
WORKDIR /app
RUN npm install --omit=dev      # No dev/test tools in production

FROM node:22-alpine AS runtime
RUN apk update && apk upgrade
RUN addgroup -S appgroup && adduser -S appuser -G appgroup  # Non-root user
COPY --from=build /app/node_modules ./node_modules
USER appuser                    # Run as non-root
```

| Decision | Why |
|---|---|
| `node:22-alpine` | Minimal attack surface; alpine has far fewer packages than debian |
| Multi-stage build | Excludes `devDependencies`, test files, and build tools from the final image |
| Non-root `appuser` | If the container is compromised, the attacker doesn't get root privileges |
| `apk upgrade` in both stages | Patches OS-level CVEs that the base image may have missed |

---

## 6. Running Locally

### Prerequisites
- Node.js v22+
- Docker Desktop

### Run the Application

```bash
# Install dependencies
npm install

# Run tests (with coverage report)
npm test

# Run the linter
npm run lint

# Start the server (port 3000)
npm start
```

### Build & Run the Docker Container

```bash
# Build the image
docker build -t zerotrust-app .

# Run it
docker run -p 3000:3000 zerotrust-app

# Test the health endpoint
curl http://localhost:3000/health
```

### Run via Docker Compose

```bash
docker compose up
```

---

## 7. Attack Demo Scenarios

The power of this pipeline is its **enforcement**. The following scenarios can be run locally to demonstrate the policy gate in action.

### Scenario 1: Unsigned Image Attack
An attacker tries to deploy an image pulled from Docker Hub — no pipeline signature exists.

```bash
export IMAGE="nginx:latest"
export EXPECTED_ISSUER="https://token.actions.githubusercontent.com"
export EXPECTED_IDENTITY_REGEX="^https://github.com/rudralaheri/devopsca/.*"

./scripts/verify-and-deploy.sh
```
> **Expected Result:** `❌ SIGNATURE VERIFICATION FAILED. Deployment rejected.`

---

### Scenario 2: Identity Confusion Attack
An attacker signs an image using their *own* GitHub Actions workflow from a *different* repository, then tries to deploy it here.

```bash
export IMAGE="ghcr.io/attacker/malicious-app:latest"
export EXPECTED_ISSUER="https://token.actions.githubusercontent.com"
export EXPECTED_IDENTITY_REGEX="^https://github.com/rudralaheri/devopsca/.*"

./scripts/verify-and-deploy.sh
```
> **Expected Result:** `❌ SIGNATURE VERIFICATION FAILED.` — The identity regex doesn't match the attacker's repository, so even a validly-signed image from a different source is rejected.

---

### Scenario 3: Vulnerable Dependency Attack (CVE Demo)
Change `express` back to a known-vulnerable version to show Trivy catching it:

```json
// In package.json, temporarily change:
"express": "^4.19.2"
```
Then commit and push. Watch the GitHub Action fail at **Stage 3** with a Trivy CVE report before anything is ever deployed.

> **Expected Result:** Pipeline fails at Stage 3. The image is never signed, never pushed, and the policy gate never runs — the vulnerability is caught before it can reach production.

---

## 8. Key Design Decisions

### Why Keyless Signing?
Traditional signing requires storing a private key securely (expensive, leak-prone). Keyless signing via Sigstore uses **short-lived certificates** tied to a verified OIDC identity. There is no secret to steal. The Rekor transparency log provides a public, immutable, auditable record of every signing event.

### Why `.trivyignore`?
The official `node:22-alpine` Docker image bundles the `npm` CLI tool. Trivy scans the *entire* image, including `npm`'s own dependencies, which contained several recently discovered CVEs. Since:
1. Our application does **not** invoke `npm` at runtime (only at build time in Stage 1).
2. The CVEs are in `npm`'s own internals, not our application code.

These are documented as accepted risks in [`.trivyignore`](.trivyignore) with explanatory comments. This is the industry-standard approach (preferred over suppressing all output or disabling the scanner).

### Why Two Trivy Steps?
The pipeline runs Trivy **twice** in Stage 3:
1. Once with `exit-code: 0` to generate the SARIF file and upload results to the GitHub Security tab (so reports are always visible, even on failure).
2. Once with `exit-code: 1` to actually enforce the gate and fail the build if vulnerabilities exist.

This pattern ensures the Security tab is always populated with the latest scan, regardless of whether the build passed or failed.

---

## 9. Further Documentation

| Document | Description |
|---|---|
| [Architecture Diagram & Data Flow](docs/architecture.md) | Detailed Mermaid pipeline diagram and stage-by-stage data flow |
| [Threat Model](docs/threat-model.md) | What attacks this pipeline defends against, and what is explicitly out of scope |
