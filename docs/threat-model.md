# Threat Model

This pipeline is designed to mitigate specific supply-chain and deployment threats.

## Defends Against

1. **Supply-Chain Tampering:** If a malicious actor compromises the container registry and modifies the `latest` tag to point to a backdoored image, the deployment will fail because the signature will not match the new digest.
2. **Rogue/Unsigned Images:** Attempting to deploy an image built on a developer's laptop or an external CI system is rejected, as it lacks the cryptographic signature from the trusted GitHub Actions issuer.
3. **Identity Confusion:** If an attacker uses their own GitHub Actions workflow (in a different repository) to build and sign a malicious image, the policy gate rejects it. The expected identity is explicitly pinned via regex to this specific repository.
4. **Known Vulnerabilities:** Trivy scanning breaks the build if `CRITICAL` or `HIGH` vulnerabilities are found in dependencies or the base OS image.
5. **Insecure Code Patterns:** SAST tools (CodeQL/Semgrep) analyze the source code for logical flaws and OWASP Top 10 vulnerabilities before a container is even built.

## Out of Scope (Does Not Cover)

This project is scoped strictly to pipeline and supply-chain integrity. It explicitly **does not** cover:
- **Runtime Intrusion Detection:** If the container is compromised *after* deployment (e.g., via a zero-day RCE), this pipeline offers no detection or prevention.
- **Network-Layer Zero Trust:** There is no service mesh (like Istio) or mutual TLS (mTLS) enforcement implemented between services.
- **Secrets Management:** The sample application does not use sensitive credentials, so secrets management (e.g., HashiCorp Vault) is omitted.
