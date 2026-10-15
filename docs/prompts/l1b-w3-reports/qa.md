# L1b Wave 3 QA (qa-runner, at 1f1a589; saved by the lead)

All gates PASS; mutate.py still running at the time of the report.
1. stylua PASS; selene 0 errors, 1 expected warning (LegacyPanel.luau:200 shadowing)
2. sourcemaps PASS
3. luau-lsp hub PASS, combat PASS
4. check_compile `CHECK: PASS -- 156 files compile with Studio settings (-O1 -g2)`
5. builds test / combat / proving PASS
6. sim_economy `CHECK: PASS -- all eras in band`
7. sim_combat `CHECK: PASS -- all twenty-three assertions hold`
8. sim_range `CHECK: PASS`
9. check_levels `CHECK: PASS`
10. check_stage_mirror `CHECK: PASS`
11. run_harness `HARNESS: PASS (2,004 checks, ...tycoon-p5\tools\crowd_harness)`; mutate.py running
12. no diff under src/server, src/client, src/combat
13. Config diff = the two Longbow damage lines only
14. gen_asset_manifest `CHECK: PASS -- configs valid, manifest up to date`
