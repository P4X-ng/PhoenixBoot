# Progressive Recovery Tests

This suite covers smoke validation for the progressive recovery flow.

Targets (invoked via `just test` or individually):
- test-progressive-smoke: Ensures level1 (scan) and level2 (ESP build/verify) execute without modifying the host.
- test-progressive-planfile: Verifies that running `just nuke progressive-dry-run` writes a well-formed planfile.
- test-esp-validation: Reuses existing ESP verification.

Manual steps (for now):
1) Smoke
   just nuke level1-scan
   just nuke level2-esp

2) Planfile
   just nuke progressive-dry-run
   ls plans/phoenix_progressive_*.json
   jq '.tool.name, .run.run_id, .levels | length' plans/phoenix_progressive_*.json | cat

3) ESP validation
   just validate verify-esp-robust

Future work: add a small shell harness to parse planfile and assert required fields without jq dependency.
