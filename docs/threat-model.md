# Threat Model: Zero-Trust DevSecOps Pipeline

## Methodology

This threat model follows the **STRIDE** framework to categorize threats and documents how each stage of the pipeline acts as a countermeasure.

| STRIDE Category | Meaning |
|---|---|
| **S**poofing | Pretending to be someone/something else |
| **T**ampering | Modifying data or code without authorization |
| **R**epudiation | Denying having performed an action |
| **I**nformation Disclosure | Exposing sensitive data |
| **D**enial of Service | Making a system unavailable |
| **E**levation of Privilege | Gaining unauthorized access or capabilities |

---

## Threat Actors

| Actor | Motivation | Capability |
|---|---|---|
| **External Attacker** | Compromise the production environment | Can access the public image registry; cannot access GitHub secrets |
| **Malicious Insider** | Bypass security controls for unauthorized deployment | Has commit access; cannot bypass pipeline gates without detection |
| **Compromised Dependency** | Inject malicious code via a supply chain attack | Code is in a published npm package or OS package |

---

## Threats & Mitigations

### Threat 1: Supply-Chain Tampering (Tampering / Spoofing)

**Scenario:** An attacker gains write access to the GHCR container registry (e.g., via a stolen token) and replaces the `latest` tag with a backdoored image that has the same name but a different digest.

**Impact without mitigation:** The deployment pipeline would pull and run the malicious image, giving the attacker code execution in the production environment.

**Mitigation:** Stage 5's policy gate uses `cosign verify` on the **image digest** (`sha256:...`), not the tag name. A tag is mutable — a digest is not. If the image content changes, the digest changes, and the original Cosign signature no longer matches. The deployment will fail with `no signatures found`.

**Residual Risk:** Low. An attacker would need to also forge a Cosign signature in the Rekor transparency log, which requires compromising the GitHub OIDC provider — a nation-state-level attack.

---

### Threat 2: Rogue / Unsigned Image Deployment (Spoofing)

**Scenario:** A developer (or attacker) builds an image locally on their laptop (`docker build -t malicious .`) and attempts to deploy it directly.

**Impact without mitigation:** Untested, unscanned code reaches production.

**Mitigation:** Every image must pass through the pipeline to receive a Cosign signature. Images built outside of the official GitHub Actions workflow have no valid signature from the `https://token.actions.githubusercontent.com` issuer. The policy gate rejects them.

**Demo:**
```bash
export IMAGE="nginx:latest"
./scripts/verify-and-deploy.sh
# Output: ❌ SIGNATURE VERIFICATION FAILED. Deployment rejected.
```

---

### Threat 3: Identity Confusion Attack (Spoofing)

**Scenario:** An attacker creates their own public GitHub repository and sets up a nearly identical workflow. They build and sign a malicious image using their own GitHub Actions OIDC identity (which is technically valid Sigstore signature), then try to deploy it here.

**Impact without mitigation:** An image signed by a valid but untrusted source is deployed.

**Mitigation:** The `--certificate-identity-regexp` flag in `cosign verify` pins the accepted identity to a specific repository path:
```
^https://github.com/rudralaheri/devopsca/.github/workflows/.*
```
Any signature issued to `github.com/attacker/evil-repo/...` will not match this regex and will be rejected, even though it is a technically valid Cosign signature.

---

### Threat 4: Known Vulnerability Exploitation (Elevation of Privilege / Tampering)

**Scenario:** A known CVE exists in one of the application's dependencies (e.g., a path traversal flaw in an old version of Express, or an OS-level privilege escalation in the base Alpine image). An attacker exploits this after deployment.

**Impact without mitigation:** The attacker can execute arbitrary code or escape the container, depending on severity.

**Mitigation:**
- **Application dependencies:** `npm audit` and Trivy's `node-pkg` scanner detect vulnerable npm packages. The pipeline blocked deployment when `express@4.19.2` (which had documented CVEs) was used. Bumping to `express@4.21.0` resolved this.
- **OS packages:** `apk update && apk upgrade` in the Dockerfile patches Alpine OS packages. Trivy's `alpine` scanner verifies this.
- **Hard gate:** Any `CRITICAL` or `HIGH` severity CVE with a known fix causes `exit-code: 1`, immediately stopping the pipeline.

**Residual Risk:** Medium. Zero-day vulnerabilities (CVEs without a published fix) are not caught. Trivy's `ignore-unfixed: true` flag intentionally skips these as they cannot be patched — the appropriate response for unfixed CVEs is threat monitoring, which is out of scope for this project.

---

### Threat 5: Insecure Code Patterns (Elevation of Privilege)

**Scenario:** A developer accidentally introduces an insecure pattern such as SQL injection, command injection, or insecure deserialization into the codebase.

**Impact without mitigation:** The vulnerability is deployed to production where it can be exploited.

**Mitigation:**
- **CodeQL** performs semantic analysis of the JavaScript source and understands data flow. It can detect if user-supplied input from `req.body` reaches a dangerous sink like `exec()` or a database query without sanitization.
- **Semgrep** runs against the OWASP Top 10 ruleset, catching common patterns like the use of `eval()`, hardcoded secrets, or insecure regular expressions.
- Both tools upload SARIF results to the GitHub Security tab for review.

---

### Threat 6: Privilege Escalation Inside Container (Elevation of Privilege)

**Scenario:** An attacker exploits a vulnerability in the running Node.js application to get a remote shell. If the process runs as `root`, they have full control of the container and potentially the host.

**Impact without mitigation:** Full container compromise; potential host escape.

**Mitigation:** The Dockerfile creates a dedicated `appuser` with no home directory and no sudo privileges, and the `USER appuser` instruction ensures the Node.js process runs as this restricted user. Even if an attacker gets RCE, they are constrained to a non-privileged user context.

```dockerfile
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser
```

---

### Threat 7: Dependency Confusion / Malicious Package (Tampering)

**Scenario:** An attacker publishes a malicious package to npm with the same name as an internal or popular package. A `npm install` command pulls the malicious version.

**Impact without mitigation:** Malicious code is executed at build time or shipped in the production image.

**Mitigation:**
- `npm ci` (used in the pipeline) installs *exact* versions from `package-lock.json`, preventing version floating.
- Trivy's node-pkg scanner checks installed packages against the CVE database.
- The SBOM generated by Syft provides a complete, auditable inventory of every package in the final image.

---

## What This Pipeline Does NOT Cover

This project is scoped strictly to **build-time and supply-chain security**. The following threats are explicitly out of scope:

| Threat | Why Out of Scope |
|---|---|
| **Runtime Intrusion Detection** | Tools like Falco or eBPF-based agents monitor running containers. This project ends at deployment. |
| **Network-Layer Zero Trust** | Service meshes (Istio/Linkerd) with mTLS enforce network identity. Not implemented. |
| **Secrets Management** | The sample app has no real secrets. In production, HashiCorp Vault or AWS Secrets Manager would be used. |
| **Zero-Day Exploits** | By definition, no patch exists. Mitigated only through runtime monitoring and WAFs. |
| **Social Engineering** | Obtaining a developer's GitHub credentials bypasses all pipeline controls at the source. |
| **GitHub Actions Supply-Chain** | The pipeline itself trusts `actions/checkout@v4`, `aquasecurity/trivy-action`, etc. A compromised third-party action could exfiltrate secrets. SHA-pinning actions would mitigate this. |

---

## Risk Summary

| Threat | Likelihood | Impact | Residual Risk | Primary Mitigating Control |
|---|---|---|---|---|
| Supply-chain tampering | Medium | Critical | Low | Cosign digest-based verification |
| Rogue unsigned image | High | High | Low | Policy gate (exit 1 on no signature) |
| Identity confusion | Low | High | Low | `--certificate-identity-regexp` |
| Known CVE exploitation | High | High | Medium | Trivy gate; apk upgrade; npm audit |
| Insecure code pattern | Medium | High | Medium | CodeQL + Semgrep SAST |
| Container privilege escalation | Low | High | Low | Non-root user (appuser) |
| Dependency confusion | Low | Critical | Medium | npm ci + package-lock.json |
