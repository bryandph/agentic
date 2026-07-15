Private PKI here is **layered and declared**: root CAs stay offline or
in a vault; intermediates issue; leaves are short-lived and renewed
automatically.

- Trust anchors are distributed declaratively (nix module / config
  management), never by hand-installing certs on hosts.
- Issuance is ACME-first even internally (step-ca / vault PKI /
  cert-manager); a service that can't ACME gets a documented issuance
  path with an expiry owner.
- Short-lived certs need renewal *headroom*: alert well before expiry
  and treat issuer rate limits/backoff as failure modes to design for
  (a 24h cert meeting an hourly-backoff renewal loop is an outage).
- CA hierarchy, names, and constraints are declared data; when two CAs
  must trust each other's subjects, prefer explicit cross-signing or
  constrained trust over blanket dual-anchoring.
- Never move private key material through an agent conversation; key
  generation and custody live in the secret store / HSM workflows.

Deeper sources: https://smallstep.com/docs/step-ca/,
https://cert-manager.io/docs/.
