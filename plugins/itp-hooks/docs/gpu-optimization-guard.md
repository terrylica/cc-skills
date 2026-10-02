# gpu-optimization-guard

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md). Hook: [`pretooluse-gpu-optimization-guard.ts`](../hooks/pretooluse-gpu-optimization-guard.ts), subhook `gpu-optimization-guard` of the [PreToolUse Write/Edit orchestrator](./pretooluse-write-edit-orchestrator.md) (timeout 4000 ms).

## Scope

A Write or Edit of a `.py` file (not `test_*.py`, `*_test.py` or `conftest.py`) whose new text (`content`, or `new_string` for an Edit) imports `torch` and shows a training indicator: `.backward()`, `.step()`, `nn.Module`, `DataLoader`, `.train()`, a `for … in …loader` loop, or the word "epoch".

The philosophy is parameter-free optimization: rather than demanding a particular batch size, it requires a mechanism that finds the right value for the hardware (Lightning `Tuner.scale_batch_size`, Accelerate `find_executable_batch_size`, a binary search, or gradient accumulation).

## The six checks

| Check               | Fires when                                                                           | Severity                                                |
| ------------------- | ------------------------------------------------------------------------------------ | ------------------------------------------------------- |
| Batch size          | CUDA use + training loop, a literal `batch_size`, and no auto-tuning or accumulation | error below `minBatchSize` (default 64), otherwise info |
| AMP                 | CUDA use + `.backward()` + `.step()` with no `autocast`/`GradScaler`/`torch.amp`     | error                                                   |
| `torch.compile`     | CUDA use + a model, and no `torch.compile`                                           | warn                                                    |
| DataLoader          | a `DataLoader(...)` call without `num_workers=` or `pin_memory=`                     | warn                                                    |
| Device availability | `device = "cuda"` hardcoded with no `torch.cuda.is_available()`                      | warn                                                    |
| `cudnn.benchmark`   | convolution layers + CUDA use, and no `cudnn.benchmark = True`                       | info                                                    |

A comment saying the optimization is disabled (for example `# AMP disabled`, `# torch.compile disabled`, `# cudnn … disabled`) or a `# batch … ok/tuned/optimal/tested` comment satisfies the matching check.

**Any finding denies the write**, including a warn- or info-only result; the deny reason groups findings under blocking errors, warnings and suggestions, each with a code suggestion.

## Bypass and configuration

- Bypass: a `# gpu-optimization-bypass: <reason>` comment in the new text.
- Config: `.claude/gpu-optimization-guard.json` under the session's working directory, else `~/.claude/gpu-optimization-guard.json`; the first one found is shallow-merged over the defaults (`enabled`, `minBatchSize`, `requireAMP`, `requireTorchCompile`, `requireDataLoaderOptim`). `enabled: false` turns the guard off.

## Code

The classifier is `classifyGpuOptimizationGuardForOrchestrator`. The file also runs standalone (`bun pretooluse-gpu-optimization-guard.ts < payload.json`) through its `import.meta.main` guard.
