## REMOVED Requirements

### Requirement: Independent watcher escalates coordinator attention
**Reason**: retired by Bryan 2026-11-16; rely on Cotal's stalled status and Herdr.
**Migration**: Stop selecting the retired watcher package and using recovery's broker-sample or watcher-state flags and evidence. Use native Cotal stalled reporting and Herdr; environment owners retire host services, credentials and state separately. Existing snapshot diagnostics and explicit fenced recovery remain.
