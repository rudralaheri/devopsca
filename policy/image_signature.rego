package devsecops.policy

default allow = false

allow {
    has_signature
    trusted_issuer
    trusted_identity
    digest_matches
}

has_signature {
    count(input.signatures) > 0
}

trusted_issuer {
    some i
    input.signatures[i].issuer == "https://token.actions.githubusercontent.com"
}

trusted_identity {
    some i
    regex.match("^https://github.com/.*?/.*?/\\.github/workflows/.*", input.signatures[i].subject)
}

digest_matches {
    some i
    input.signatures[i].digest == input.image_digest
}

# Provide human-readable deny messages
deny["Image has no signatures"] {
    not has_signature
}

deny["Signature not from trusted GitHub Actions OIDC issuer"] {
    not trusted_issuer
    has_signature
}

deny["Signature identity does not match authorized workflow pattern"] {
    not trusted_identity
    has_signature
    trusted_issuer
}

deny["Deployed digest does not match signed digest (Tag mutation detected)"] {
    not digest_matches
    has_signature
}
