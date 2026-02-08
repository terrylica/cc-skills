# Evolution Log

Reverse chronological - newest on top.

## 2026-02-08 - Initial creation

- Created skill from real disk audit session
- Benchmarked dust (20.4s), gdu (28.8s), dua-cli (37.1s), ncdu (96.6s) on ~632GB home dir
- Documented cache cleanup workflow: uv (10.8GB), brew (9.4GB), pip (837MB), npm (1.1GB) = ~22GB reclaimed
- Added forgotten file detection patterns (ISOs, video exports, old recordings)
- Added Downloads triage workflow with AskUserQuestion multi-select pattern
- Covers 10 cache types: uv, brew, pip, npm, cargo, rustup, Docker, Playwright, sccache, huggingface
