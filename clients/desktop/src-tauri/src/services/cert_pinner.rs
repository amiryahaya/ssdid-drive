//! TLS certificate pinning for SSDID infrastructure.
//!
//! Provides SPKI SHA-256 pin verification for connections to registry.ssdid.my
//! and drive.ssdid.my. Pins are checked post-connection via reqwest middleware.

use sha2::{Sha256, Digest};

/// SPKI SHA-256 pins for SSDID infrastructure endpoints.
/// Generate with:
///   openssl s_client -connect registry.ssdid.my:443 < /dev/null 2>/dev/null \
///     | openssl x509 -pubkey -noout \
///     | openssl pkey -pubin -outform DER \
///     | openssl dgst -sha256 -binary \
///     | base64
pub const PINNED_HOSTS: &[PinnedHost] = &[
    PinnedHost {
        hostname: "registry.ssdid.my",
        pins: &[
            "YLh1dUR9y6Kja30RrAn7JKnbQG/uEtLMkBgFF2Fuihg=",
            "Vjs8r4z+80wjNcr1YKepWQboSIRi63WsWXhIMN+eWys=",
        ],
    },
    PinnedHost {
        hostname: "drive.ssdid.my",
        pins: &[
            "YLh1dUR9y6Kja30RrAn7JKnbQG/uEtLMkBgFF2Fuihg=",
            "Vjs8r4z+80wjNcr1YKepWQboSIRi63WsWXhIMN+eWys=",
        ],
    },
    PinnedHost {
        hostname: "notify.ssdid.my",
        pins: &[
            "YLh1dUR9y6Kja30RrAn7JKnbQG/uEtLMkBgFF2Fuihg=",
            "Vjs8r4z+80wjNcr1YKepWQboSIRi63WsWXhIMN+eWys=",
        ],
    },
];

pub struct PinnedHost {
    pub hostname: &'static str,
    pub pins: &'static [&'static str],
}

/// Check if a hostname requires certificate pinning.
pub fn is_pinned_host(hostname: &str) -> bool {
    PINNED_HOSTS.iter().any(|h| h.hostname == hostname)
}

/// Verify a DER-encoded certificate chain against pinned SPKI hashes.
/// Returns true if any certificate in the chain matches a pin for the host.
pub fn verify_pin(hostname: &str, spki_der_chain: &[Vec<u8>]) -> bool {
    let host = match PINNED_HOSTS.iter().find(|h| h.hostname == hostname) {
        Some(h) => h,
        None => return true, // Not a pinned host — allow
    };

    for spki_der in spki_der_chain {
        let hash = Sha256::digest(spki_der);
        let pin = base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &hash);
        if host.pins.contains(&pin.as_str()) {
            return true;
        }
    }

    tracing::warn!(
        "Certificate pin verification failed for {} — no matching pin in chain of {} certs",
        hostname,
        spki_der_chain.len()
    );
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn is_pinned_host_returns_true_for_known_hosts() {
        assert!(is_pinned_host("registry.ssdid.my"));
        assert!(is_pinned_host("drive.ssdid.my"));
        assert!(is_pinned_host("notify.ssdid.my"));
    }

    #[test]
    fn is_pinned_host_returns_false_for_unknown_hosts() {
        assert!(!is_pinned_host("example.com"));
        assert!(!is_pinned_host("evil.ssdid.my"));
    }

    #[test]
    fn verify_pin_allows_unpinned_hosts() {
        assert!(verify_pin("example.com", &[]));
    }

    #[test]
    fn verify_pin_rejects_empty_chain_for_pinned_host() {
        assert!(!verify_pin("registry.ssdid.my", &[]));
    }
}
