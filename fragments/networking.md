Network state is **derived from a declared topology**, never hand-kept
in parallel lists.

- VLANs/subnets are declared once with their prefixes; host addresses
  derive from (vlan, id) lookups — if you find yourself typing a
  literal IP twice, the second one should be a lookup.
- DNS records and DHCP reservations render from the same member
  contract that defines the hosts; adding a host means declaring it
  once, not editing three zone files.
- Mesh overlays (WireGuard-family) are part of the topology: member
  identity, mesh DNS names, and reachability are declared data.
- Segmentation intent matters more than the current table: record WHY
  a flow is allowed (service, direction, ports) so a firewall rule can
  be reconstructed, not just copied.
- When auditing, compare the rendered projection against live state —
  drift between declared and actual is the finding.

Deeper sources: the consuming repo's topology/inventory modules (see
its repo fragment for exact paths).
