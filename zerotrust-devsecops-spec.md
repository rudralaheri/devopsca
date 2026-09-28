# Zero-Trust DevSecOps Pipeline — Build Specification

**Project title:** Zero-Trust DevSecOps Pipeline: Automated SAST, Cryptographic Image Signing with Cosign, and Policy Enforcement Using GitHub Actions, Docker, and Trivy

**Purpose of this document:** A complete, implementation-ready spec for an AI coding agent (or a human) to build the project end-to-end. It fixes the stack, the repo layout, the exact behavior of every pipeline stage, and the pass/fail logic of the policy gate, so the build can proceed without re-deriving architecture decisions.

TASK AT HAND: Students will develop and demonstrate a complete DevOps project by implementing a software delivery pipeline. The project should include version control using Git/GitHub, application build, automated testing, containerization using Docker, CI/CD pipeline implementation using Jenkins/GitHub Actions, and deployment to a suitable environment. Students will submit project documentation and demonstrate the working pipeline.
---

## 1. Objective

Build a small CI/CD pipeline that treats every container image as **untrusted until cryptographically proven otherwise**. Concretely:

1. Code is scanned for vulnerabilities at the source level (SAST) before it's even built.
2. The built container image gets an SBOM and a vulnerability scan.
3. The image is signed **keylessly** using Sigstore/Cosign, binding the signature to the GitHub Actions OIDC identity that built it (no long-lived private keys to manage or leak).
4. Deployment is blocked by a policy gate that verifies the signature, issuer, and identity before `docker compose up` is allowed to run. An unsigned, re-tagged, or tampered image is rejected.

This is "zero trust" in the supply-chain sense: trust is never assumed from context (e.g., "it's in our registry so it must be fine") — it is verified cryptographically at the point of deployment, every time.

---

## 2. Tech stack

| Concern | Tool |
|---|---|
| Source control | Git / GitHub |
| Sample application | Node.js 20 + Express |
| Unit/regression testing | Jest + Supertest |
| Linting | ESLint |
| SAST (code-level security scan) | CodeQL (GitHub-native) — Semgrep as an alternative/addition |
| Containerization | Docker (multi-stage, non-root, Alpine base) |
| SBOM generation | Syft (Anchore) |
| Container vulnerability scanning | Trivy (Aqua Security) |
| Image signing | Cosign (Sigstore), keyless via GitHub OIDC |
| Image registry | GHCR (GitHub Container Registry) |
| CI/CD orchestration | GitHub Actions |
| Local deployment target | Docker Compose |
| Policy enforcement (deploy gate) | Bash script wrapping `cosign verify`, documented in parallel as an OPA/Rego policy for portability to Kubernetes |

---

## 3. Repository layout

```
zerotrust-devsecops/
├── .github/
│   └── workflows/
│       └── pipeline.yml          # the full CI/CD pipeline (see §5)
├── docs/
│   ├── architecture.md           # diagram + written explanation
│   └── threat-model.md           # what this pipeline defends against
├── policy/
│   ├── image_signature.rego      # OPA policy, documents the rule set declaratively
│   └── sample_input_allow.json   # example input for `opa eval` demonstration
├── scripts/
│   └── verify-and-deploy.sh      # the actual enforcement point (see §7)
├── src/
│   └── app.js                    # Express API
├── test/
│   └── app.test.js               # Jest + Supertest unit/regression tests
├── .dockerignore
├── .eslintrc.json
├── docker-compose.yml
├── Dockerfile                    # multi-stage, non-root runtime
├── package.json
└── README.md
```

---

## 4. Sample application

A minimal task-list REST API. Deliberately simple so the *pipeline* is the graded artifact, not the app.

**Endpoints:**
- `GET /health` → `200 { status: "ok" }`
- `GET /api/tasks` → list seeded tasks
- `GET /api/tasks/:id` → single task or `404`
- `POST /api/tasks` → create task; `400` on missing/empty `title`

**Design choices that matter for the security narrative:**
- No `eval`, no dynamic `require`, no shell exec from user input — keeps SAST/CodeQL clean so the demo shows a *passing* security gate, not just a scanner running.
- Strict input validation on `POST` (rejects empty/whitespace-only titles) — gives the regression test suite something real to check.
- No secrets, no database, no filesystem writes — keeps the container attack surface small and the SBOM short and readable for demonstration purposes.

**Verified locally already:** `npm install`, `npx eslint src test`, and `npm test` (Jest) all pass cleanly (7/7 tests, ~93% line coverage) using `express`, `jest`, `supertest`, `eslint`, `jest-junit`. Use these exact dependency versions as a starting point:
```json
"dependencies": { "express": "^4.19.2" },
"devDependencies": {
  "eslint": "^8.57.0",
  "jest": "^29.7.0",
  "jest-junit": "^16.0.0",
  "supertest": "^7.0.0"
}
```

---

## 5. Pipeline stages (GitHub Actions)

Single workflow file, `.github/workflows/pipeline.yml`, triggered on `push` to `main` and on `pull_request`. Jobs run in this dependency order (each depends on the previous via `needs:`):

### Stage 1 — Lint & SAST
- Checkout code.
- `actions/setup-node@v4` (Node 20), `npm ci`.
- `npm run lint` (ESLint) — fails the build on lint errors.
- **CodeQL analysis**: `github/codeql-action/init` → `github/codeql-action/analyze` for the `javascript` language. Results appear in the repo's Security tab.
- Optional/parallel: **Semgrep** via `returntocorp/semgrep-action` with the `p/javascript` and `p/owasp-top-ten` rulesets, to show a second, independent SAST engine (useful to discuss false-negative coverage in the report).

### Stage 2 — Automated testing
- Depends on Stage 1.
- `npm test` (Jest + Supertest), output as JUnit XML via `jest-junit` (already configured in `package.json`) so GitHub Actions can render a test summary.
- Upload coverage report as a build artifact.
- Fail the pipeline on any test failure — this is a hard gate before a container is even built.

### Stage 3 — Build, SBOM, and vulnerability scan
- Depends on Stage 2.
- `docker/setup-buildx-action@v3`.
- Build the image with `docker/build-push-action@v6`, tag it with both `latest` and the commit SHA, **but do not push yet**.
- Generate SBOM with **Syft**: `anchore/sbom-action@v0` against the built image, output format `spdx-json`, upload as a build artifact (`sbom.spdx.json`).
- Scan the image with **Trivy**: `aquasecurity/trivy-action@master`, `scan-type: image`, `severity: CRITICAL,HIGH`, `exit-code: 1` (fails the build if criticals/highs are found — this is the second hard security gate). Upload the SARIF results to the Security tab via `github/codeql-action/upload-sarif`.
- Only after both SBOM generation and Trivy scan succeed, push the image to GHCR (`ghcr.io/<owner>/<repo>:<tag>`) using `docker/login-action@v3` with the built-in `GITHUB_TOKEN`.

### Stage 4 — Cryptographic signing
- Depends on Stage 3 (image must exist in GHCR).
- Install Cosign via `sigstore/cosign-installer@v3`.
- Requires workflow permission `id-token: write` (for OIDC) and `packages: write` (for GHCR).
- Sign **keylessly**:
  ```bash
  cosign sign --yes ghcr.io/<owner>/<repo>@<digest>
  ```
  Keyless signing uses GitHub Actions' own OIDC token to get a short-lived certificate from Sigstore's Fulcio CA — no private key is generated, stored, or rotated. The signature and certificate are published to the public Rekor transparency log.
- Optionally also attach the SBOM as an in-toto attestation: `cosign attest --yes --predicate sbom.spdx.json --type spdxjson ghcr.io/<owner>/<repo>@<digest>`.

### Stage 5 — Policy-gated deployment
- Depends on Stage 4.
- Runs `scripts/verify-and-deploy.sh` (see §7) with `IMAGE`, `EXPECTED_ISSUER`, and `EXPECTED_IDENTITY_REGEX` set as environment variables, the last one pinned to this exact repo/workflow path to prevent identity confusion attacks.
- If verification fails, the job fails and **`docker compose up` is never invoked** — this is the enforcement point that gives the project its "zero-trust" claim, and the part worth demonstrating live (e.g., by re-tagging an old image and showing the deploy get rejected).
- If verification passes, deploy locally via Docker Compose and curl `/health` as a smoke test.

---

## 6. SBOM + Trivy detail

- **Syft** output: SPDX JSON, stored as a workflow artifact and optionally attached to the image via `cosign attest` (Stage 4) so the SBOM itself is also tamper-evident.
- **Trivy** config: scan the *image*, not just the filesystem, so it also catches OS-package CVEs introduced by the Alpine base layer, not only npm dependency CVEs. Recommended flags: `--severity CRITICAL,HIGH --ignore-unfixed --exit-code 1`. `--ignore-unfixed` avoids failing the build on CVEs with no available patch yet, which is a reasonable and defensible policy choice to state in the report.

---

## 7. Policy gate — exact logic (already written and syntax-validated)

`scripts/verify-and-deploy.sh` is the real enforcement point. Its logic:

1. Require `IMAGE` env var (fails loudly if unset — no silent fallback to `:latest`).
2. Default `EXPECTED_ISSUER` to `https://token.actions.githubusercontent.com`.
3. Require (warn if absent) `EXPECTED_IDENTITY_REGEX`, e.g. `^https://github.com/<owner>/<repo>/\.github/workflows/.*`.
4. Run:
   ```bash
   cosign verify "$IMAGE" \
     --certificate-oidc-issuer "$EXPECTED_ISSUER" \
     --certificate-identity-regexp "$EXPECTED_IDENTITY_REGEX"
   ```
5. Non-zero exit from `cosign verify` → print the failure reason, **exit 1, do not deploy**.
6. Zero exit → `export IMAGE` and run `docker compose -f docker-compose.yml up -d --remove-orphans`, then print health-check instructions.

This script is callable identically from CI or from a developer's laptop, which is worth stating explicitly in the report as a "policy as code, not policy as pipeline-only convention" design point.

**Demo attack scenarios worth scripting for the live demonstration:**
- Attempt to deploy `image:latest` pulled and re-pushed to a personal registry → signature identity mismatch → rejected.
- Attempt to deploy an image with the tag mutated to point at a different (unsigned) digest → `cosign verify` fails because the signature is bound to a digest, not a mutable tag → rejected.
- Attempt to deploy with `EXPECTED_IDENTITY_REGEX` pointed at a different repo path → rejected even though the image *is* signed, demonstrating identity-confusion protection.

---

## 8. OPA/Rego policy (portability artifact, not the enforcement path in this project)

`policy/image_signature.rego` declares the same four rules as the bash gate, in Rego, so the project can be discussed/extended in a Kubernetes context (OPA Gatekeeper / Kyverno ValidatingAdmissionPolicy) without re-deriving the logic:

- `has_signature` — image carries ≥1 signature record.
- `trusted_issuer` — signature's OIDC issuer equals the GitHub Actions issuer.
- `trusted_identity` — signature's certificate identity (SAN) matches this repo/workflow via regex.
- `digest_matches` — the digest being deployed equals the digest that was actually signed (blocks tag-substitution attacks).

`allow` requires all four; `deny[msg]` produces a specific human-readable reason for each failure mode. Include `sample_input_allow.json` as a fixture and instruct the report to show one passing and one failing `opa eval` run as evidence the policy logic itself is correct, independent of the bash script.

---

## 9. Dockerfile requirements

- Multi-stage build: `build` stage installs prod-only deps (`npm ci --omit=dev`), `runtime` stage copies only `node_modules` + `src` — keeps final image small and avoids shipping devDependencies (smaller attack surface, smaller SBOM).
- Base image: `node:20-alpine` for both stages.
- Runtime user: create and switch to a non-root `appuser` (`USER appuser`) — least privilege.
- `HEALTHCHECK` instruction hitting `/health`.
- No secrets or `.env` files copied in; `.dockerignore` excludes `node_modules`, `test/`, `.git/`, `docs/`, and markdown files from the build context.

## 10. docker-compose.yml requirements

- `image` is required via `${IMAGE:?...}` — compose refuses to start if `IMAGE` isn't exported, forcing every deploy through the verification script rather than a bare `docker compose up`.
- Hardening: `read_only: true`, `cap_drop: [ALL]`, `security_opt: [no-new-privileges:true]`.
- Healthcheck matching the Dockerfile's.

---

## 11. Documentation deliverables to write alongside the code

1. **README.md** — quickstart, architecture summary, how to run the pipeline, how to run the policy gate locally, how to reproduce the three attack-demo scenarios in §7.
2. **docs/architecture.md** — a diagram (Mermaid is fine) of the five pipeline stages and data flow: source → SAST → test → build+SBOM+scan → sign → policy gate → deploy.
3. **docs/threat-model.md** — explicitly name what this defends against (supply-chain tampering, unsigned/rogue images, tag mutation, identity confusion, known CVEs in deps and base image, insecure code patterns) and what it does *not* cover (runtime intrusion detection, network-layer zero trust, secrets management — good to be honest about scope in an academic submission).
4. Final project report/slides (separate from this spec) should include: pipeline run screenshots, the Security tab showing CodeQL/Trivy SARIF findings, the Rekor transparency log entry for a signed image, and a screenshot of a rejected deployment attempt.

---

## 12. Suggested build order for the agent

1. Scaffold `src/app.js`, `test/app.test.js`, `package.json`, `.eslintrc.json` — confirm `npm test` and lint pass locally first.
2. Write `Dockerfile`, `.dockerignore`, confirm `docker build` succeeds locally.
3. Write `docker-compose.yml` and `scripts/verify-and-deploy.sh`; confirm the script's `bash -n` syntax check passes and that it correctly refuses to run without `IMAGE` set.
4. Write `.github/workflows/pipeline.yml` implementing Stages 1–5 in order, with `needs:` chaining so a failure at any stage halts the rest.
5. Write `policy/image_signature.rego` + sample input.
6. Push to GitHub, confirm the full pipeline goes green on a clean commit, then run the three attack-demo scenarios and capture the rejections.
7. Write README, architecture doc, and threat model last, once behavior is confirmed rather than assumed.

---

## 13. Grading-criteria checklist (map back to the original assignment)

- [x] Version control using Git/GitHub — repo, branches, commit history.
- [x] Application build — Node/Express app with `npm` build/install step.
- [x] Automated testing — Jest + Supertest unit and regression tests, gating the pipeline.
- [x] Containerization using Docker — multi-stage, non-root Dockerfile.
- [x] CI/CD pipeline using GitHub Actions — five-stage workflow.
- [x] Deployment to a suitable environment — Docker Compose, gated by signature verification.
- [x] Project documentation — README, architecture, threat model.
- [x] Working pipeline demonstration — green pipeline run + live rejection demo of an unsigned/tampered image.
- [x] **Differentiator over a baseline DevOps project**: SAST (CodeQL/Semgrep), SBOM (Syft), vulnerability scanning (Trivy), keyless cryptographic signing (Cosign/Sigstore), and an explicit deploy-time policy gate (OPA-documented, bash-enforced) — this is what makes it "Zero-Trust DevSecOps" rather than plain DevOps.
