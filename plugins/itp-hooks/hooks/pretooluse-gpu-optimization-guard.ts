#!/usr/bin/env bun
// FILE-SIZE-OK: 525 lines preserves 6-check policy logic + per-check
// suggestion text; iter-87 refactor extracted classifier without adding
// new bloat (was 538 lines pre-refactor).
/**
 * PreToolUse Hook: GPU Optimization Guard (iter-87 orchestrator-inlined)
 *
 * PHILOSOPHY: Parameter-free optimization over magic numbers
 *
 * Instead of hardcoding "batch_size >= 64", we REQUIRE automatic optimization
 * mechanisms that find the optimal values for the actual hardware:
 *
 * BATCH SIZE (parameter-free approaches):
 * - PyTorch Lightning: Tuner.scale_batch_size(mode="binsearch")
 * - Hugging Face Accelerate: @find_executable_batch_size decorator
 * - Manual: Binary search for largest batch that fits in GPU memory
 * - Gradient accumulation: accumulation_steps pattern
 *
 * AMP (Automatic Mixed Precision):
 * - Required when: CUDA + backward() + step() (GPU training)
 * - ~2x speedup, ~50% memory reduction
 *
 * TRIGGER CONDITIONS:
 * - AMP check: cuda usage + .backward() + .step() = GPU training
 * - Batch check: cuda usage + training loop
 *
 * ENFORCEMENT LEVELS:
 * - ERROR (hard block): Missing AMP, small hardcoded batch without auto-tuning
 * - WARN (block): Missing torch.compile, suboptimal DataLoader
 * - INFO: Missing cudnn.benchmark for CNN models
 *
 * Lessons learned from exp068 disaster (2026-01-22):
 * - batch_size=32 on RTX 4090 (24GB) = 45% GPU utilization, 61 hours
 * - Auto-tuned batch + AMP + torch.compile = 8 hours, full utilization
 *
 * BYPASS: # gpu-optimization-bypass: <reason>
 *
 * Iter-87 dual-use contract (mirrors iter-85/86 migrations):
 *   - Standalone CLI mode (preserved for backward-compat + direct testing):
 *     `bun pretooluse-gpu-optimization-guard.ts < payload.json` runs main()
 *     under `import.meta.main` guard.
 *   - Orchestrator-inlined mode (NEW owner of the Write|Edit hooks.json slot):
 *     The orchestrator imports `classifyGpuOptimizationGuardForOrchestrator`
 *     and invokes it directly in the single bun process — no per-subhook
 *     bun cold-start cost. Conforms to PreToolUseSubhookContract.
 *
 * @see https://lightning.ai/docs/pytorch/stable/api/lightning.pytorch.callbacks.BatchSizeFinder.html
 * @see https://huggingface.co/docs/accelerate/v0.11.0/en/memory
 * @see https://pytorch.org/tutorials/recipes/recipes/tuning_guide.html
 */

import { basename, dirname } from "path";
import {
  parseStdinOrAllow,
  allow,
  deny,
  createHookLogger,
  type PreToolUseInput,
} from "./pretooluse-helpers.ts";
import {
  ALLOW_DECISION,
  denyDecision,
  isFileEditToolNameHonoredByPreToolUseBlockingSubhook,
  type PreToolUseSubhookDecision,
} from "./lib/pretooluse-subhook-contract-for-in-process-orchestrator-inlining-iter84.ts";

const logger = createHookLogger("gpu-optimization-guard");

// =============================================================================
// Configuration
// =============================================================================

interface GpuOptimizationGuardConfig {
  enabled: boolean;
  minBatchSize: number;
  requireAMP: boolean;
  requireTorchCompile: boolean;
  requireDataLoaderOptim: boolean;
  filePatterns: string[];
  excludePatterns: string[];
}

const DEFAULT_GPU_OPTIMIZATION_GUARD_CONFIG: GpuOptimizationGuardConfig = {
  enabled: true,
  minBatchSize: 64,
  requireAMP: true,
  requireTorchCompile: true,
  requireDataLoaderOptim: true,
  filePatterns: ["**/*.py"],
  excludePatterns: ["**/test_*.py", "**/*_test.py", "**/conftest.py"],
};

async function loadGpuOptimizationGuardConfigWithProjectAndGlobalFallback(
  projectDir: string | undefined,
): Promise<GpuOptimizationGuardConfig> {
  const config = { ...DEFAULT_GPU_OPTIMIZATION_GUARD_CONFIG };
  const home = Bun.env.HOME || "";

  if (projectDir) {
    const projectConfig = `${projectDir}/.claude/gpu-optimization-guard.json`;
    const file = Bun.file(projectConfig);
    if (await file.exists()) {
      try {
        const loaded = await file.json();
        return { ...config, ...loaded };
      } catch (e) {
        const errorMsg = e instanceof Error ? e.message : String(e);
        logger.warn("Failed to parse project config", {
          path: projectConfig,
          error: errorMsg,
        });
      }
    }
  }

  const globalConfig = `${home}/.claude/gpu-optimization-guard.json`;
  const globalFile = Bun.file(globalConfig);
  if (await globalFile.exists()) {
    try {
      const loaded = await globalFile.json();
      return { ...config, ...loaded };
    } catch (e) {
      const errorMsg = e instanceof Error ? e.message : String(e);
      logger.warn("Failed to parse global config", {
        path: globalConfig,
        error: errorMsg,
      });
    }
  }

  return config;
}

// =============================================================================
// Detection Patterns (pure regex; no I/O)
// =============================================================================

interface GpuOptimizationFinding {
  category: string;
  severity: "error" | "warn" | "info";
  message: string;
  suggestion: string;
}

function hasGpuOptimizationBypassComment(content: string): boolean {
  return /# gpu-optimization-bypass:/.test(content);
}

function isPyTorchTrainingScript(content: string): boolean {
  if (!/import\s+torch|from\s+torch/.test(content)) return false;

  const trainingIndicators = [
    /\.backward\(\)/,
    /\.step\(\)/,
    /nn\.Module/,
    /DataLoader/,
    /\.train\(\)/,
    /for\s+.*\s+in\s+.*loader/,
    /epoch/i,
  ];
  return trainingIndicators.some((pattern) => pattern.test(content));
}

function checkBatchSizeAutoTuningAdoption(
  content: string,
  config: GpuOptimizationGuardConfig,
): GpuOptimizationFinding | null {
  const hasGPU = /\.cuda\(\)|\.to\(\s*["']cuda["']|device\s*=\s*["']cuda/.test(content);
  const hasTrainingLoop = /\.backward\(\)|for\s+.*\s+in\s+.*loader/i.test(content);
  if (!hasGPU || !hasTrainingLoop) return null;

  const hasAutoBatchSize =
    /scale_batch_size|BatchSizeFinder|auto_scale_batch_size/.test(content) ||
    /find_executable_batch_size|auto_find_batch_size/.test(content) ||
    /find_optimal_batch_size|binary.*search.*batch|batch.*binary.*search/i.test(content) ||
    /accumulation_steps|gradient_accumulation|accum_iter/i.test(content) ||
    /# ?batch.*(ok|tuned|optimal|tested)/i.test(content);
  if (hasAutoBatchSize) return null;

  const batchSizeMatch = content.match(/batch_size\s*[=:]\s*(\d+)/);
  if (batchSizeMatch) {
    const batchSize = parseInt(batchSizeMatch[1], 10);
    if (batchSize < config.minBatchSize) {
      return {
        category: "batch_size",
        severity: "error",
        message: `batch_size=${batchSize} is hardcoded without automatic optimization`,
        suggestion: `Use PARAMETER-FREE automatic batch size optimization:

  # Option 1: PyTorch Lightning (RECOMMENDED)
  from lightning.pytorch.tuner import Tuner
  tuner = Tuner(trainer)
  tuner.scale_batch_size(model, mode="binsearch")

  # Option 2: Hugging Face Accelerate
  from accelerate.utils import find_executable_batch_size
  @find_executable_batch_size(starting_batch_size=512)
  def train_loop(batch_size):
      dataloader = DataLoader(dataset, batch_size=batch_size)
      ...

  # Option 3: Manual binary search
  def find_optimal_batch_size(model, sample, device="cuda"):
      torch.cuda.empty_cache()
      low, high, optimal = 1, 4096, 1
      while low <= high:
          mid = (low + high) // 2
          try:
              _ = model(sample.repeat(mid, 1, 1).to(device))
              optimal, low = mid, mid + 1
          except RuntimeError:
              high = mid - 1
          torch.cuda.empty_cache()
      return optimal

  # Option 4: Gradient accumulation (if memory-constrained)
  accumulation_steps = 8  # effective_batch = batch_size * accumulation_steps`,
      };
    }
  }

  if (batchSizeMatch && !hasAutoBatchSize) {
    return {
      category: "batch_size",
      severity: "info",
      message: "Hardcoded batch_size without automatic optimization",
      suggestion: `Consider using automatic batch size finder for optimal GPU utilization:
  from lightning.pytorch.tuner import Tuner
  tuner.scale_batch_size(model, mode="binsearch")  # Finds largest that fits

  Or add comment to acknowledge: # batch-size-ok: tested on RTX 4090`,
    };
  }

  return null;
}

function checkCudnnBenchmarkEnabledForConvolutionalModelsOnGpu(content: string): GpuOptimizationFinding | null {
  const hasConv = /nn\.Conv|Conv2d|Conv1d|conv_|convolution/i.test(content);
  const hasGPU = /\.cuda\(\)|\.to\(\s*["']cuda["']|device\s*=\s*["']cuda/.test(content);
  if (!hasConv || !hasGPU) return null;

  const hasBenchmark = /cudnn\.benchmark\s*=\s*True/.test(content);
  const hasBenchmarkComment = /# ?cudnn.*disabled/i.test(content);

  if (!hasBenchmark && !hasBenchmarkComment) {
    return {
      category: "cudnn_benchmark",
      severity: "info",
      message: "Conv model without cudnn.benchmark = True",
      suggestion: `Add for auto-tuned convolution algorithms (10-20% speedup):
  torch.backends.cudnn.benchmark = True  # Add before training loop
  # Note: Only helps when input sizes are constant`,
    };
  }
  return null;
}

function checkAutomaticMixedPrecisionAdoptionInGpuTrainingLoop(
  content: string,
  config: GpuOptimizationGuardConfig,
): GpuOptimizationFinding | null {
  if (!config.requireAMP) return null;

  const hasGPU = /\.cuda\(\)|\.to\(\s*["']cuda["']|\.to\(\s*device\)|device\s*=\s*["']cuda/.test(content);
  const hasBackward = /\.backward\(\)/.test(content);
  const hasOptimizerStep = /optimizer\.step\(\)|\.step\(\)/.test(content);
  const isGPUTraining = hasGPU && hasBackward && hasOptimizerStep;
  if (!isGPUTraining) return null;

  const hasAMP = /autocast|GradScaler|torch\.amp|torch\.cuda\.amp/.test(content);
  const hasAMPComment = /# ?(AMP|mixed precision|autocast).*disabled/i.test(content);

  if (!hasAMP && !hasAMPComment) {
    return {
      category: "amp",
      severity: "error",
      message: "GPU training loop without AMP (Automatic Mixed Precision)",
      suggestion: `Add AMP for ~2x speedup and 50% memory reduction:
  from torch.amp import autocast, GradScaler
  scaler = GradScaler('cuda')
  with autocast('cuda'):
      loss = model(x)
  scaler.scale(loss).backward()
  scaler.step(optimizer)
  scaler.update()`,
    };
  }
  return null;
}

function checkTorchCompileAdoptionForPyTorchTwoPlusGpuModels(
  content: string,
  config: GpuOptimizationGuardConfig,
): GpuOptimizationFinding | null {
  if (!config.requireTorchCompile) return null;

  const hasGPU = /\.cuda\(\)|\.to\(\s*["']cuda["']|device\s*=\s*["']cuda/.test(content);
  if (!hasGPU) return null;

  const hasModel = /nn\.Module|model\s*=/.test(content);
  const hasTorchCompile = /torch\.compile/.test(content);
  const hasCompileComment = /# ?(torch\.compile|compile).*disabled/i.test(content);

  if (hasModel && !hasTorchCompile && !hasCompileComment) {
    return {
      category: "torch_compile",
      severity: "warn",
      message: "GPU model without torch.compile (PyTorch 2.0+ optimization)",
      suggestion: `Add torch.compile for 30-50% speedup on GPU:
  if hasattr(torch, 'compile'):
      model = torch.compile(model, mode="default")
  # Use mode="default" (not "reduce-overhead") to avoid CUDA graph conflicts`,
    };
  }
  return null;
}

function checkDataLoaderHasNumWorkersAndPinMemoryConfigured(
  content: string,
  config: GpuOptimizationGuardConfig,
): GpuOptimizationFinding | null {
  if (!config.requireDataLoaderOptim) return null;

  const dataLoaderMatch = content.match(/DataLoader\s*\([^)]+\)/gs);
  if (!dataLoaderMatch) return null;

  const findings: string[] = [];
  for (const match of dataLoaderMatch) {
    if (!/num_workers\s*=/.test(match)) {
      findings.push("num_workers not set (default 0 = main process only)");
    }
    if (!/pin_memory\s*=/.test(match)) {
      findings.push("pin_memory not set (faster CPU→GPU transfer)");
    }
  }

  if (findings.length > 0) {
    return {
      category: "dataloader",
      severity: "warn",
      message: `DataLoader missing optimizations: ${findings.join(", ")}`,
      suggestion: `Optimize DataLoader:
  DataLoader(
      dataset,
      batch_size=256,
      num_workers=4,           # Parallel data loading
      pin_memory=True,         # Faster GPU transfer
      persistent_workers=True  # Reuse workers across epochs
  )`,
    };
  }
  return null;
}

function checkCudaDeviceHardcodingWithoutAvailabilityFallback(content: string): GpuOptimizationFinding | null {
  const hasHardcodedCuda = /device\s*=\s*["']cuda["']/.test(content);
  const hasAvailabilityCheck = /torch\.cuda\.is_available\(\)/.test(content);

  if (hasHardcodedCuda && !hasAvailabilityCheck) {
    return {
      category: "device",
      severity: "warn",
      message: 'device="cuda" hardcoded without availability check',
      suggestion: `Use conditional device selection:
  device = "cuda" if torch.cuda.is_available() else "cpu"`,
    };
  }
  return null;
}

// =============================================================================
// Pure classifier (iter-87 orchestrator-inlineable contract)
// =============================================================================

/**
 * Pure classifier conforming to PreToolUseSubhookClassifierFunction.
 *
 * Identical 6-check policy logic to the pre-iter-87 main() body, but
 * factored out so the orchestrator can invoke it without subprocess-spawning
 * this file (which would defeat the orchestrator's ~44ms cold-start saving).
 *
 * Short-circuit order (early-exits cheap → expensive):
 *   1. tool_name not Write/Edit → ALLOW
 *   2. file_path not .py → ALLOW (O(1) extension check)
 *   3. test file → ALLOW (filename pattern)
 *   4. # gpu-optimization-bypass comment → ALLOW
 *   5. Not a PyTorch training script → ALLOW (regex scan)
 *   6. config.enabled == false → ALLOW
 *   7. Run all 6 checks; collect findings
 *   8. No findings → ALLOW; else DENY with formatted multi-section message
 *
 * MUST NOT call allow()/deny() or touch stdin/stdout/process.exit.
 */
export async function classifyGpuOptimizationGuardForOrchestrator(
  input: PreToolUseInput,
): Promise<PreToolUseSubhookDecision> {
  const toolName = input.tool_name || "";
  // Iter-102: route through canonical contract helper (closes iter-101 residual gap).
  if (!isFileEditToolNameHonoredByPreToolUseBlockingSubhook(toolName)) {
    return ALLOW_DECISION;
  }
  // Iter-102 staged-migration short-circuit: MultiEdit payload-shape
  // adaptation is iter-103+ per-classifier work. Preserves status quo.
  if (toolName === "MultiEdit") {
    return ALLOW_DECISION;
  }

  const filePath = (input.tool_input?.file_path as string) || "";
  const content = ((input.tool_input?.content as string) || (input.tool_input?.new_string as string) || "");

  // Only check Python files
  if (!filePath.endsWith(".py")) {
    return ALLOW_DECISION;
  }

  // Skip test files
  const fileName = basename(filePath);
  if (fileName.startsWith("test_") || fileName.endsWith("_test.py") || fileName === "conftest.py") {
    return ALLOW_DECISION;
  }

  // Check for explicit bypass comment
  if (hasGpuOptimizationBypassComment(content)) {
    logger.debug("Bypass comment found, allowing", { file: fileName });
    return ALLOW_DECISION;
  }

  // Only check PyTorch training scripts
  if (!isPyTorchTrainingScript(content)) {
    return ALLOW_DECISION;
  }

  // Load configuration
  const projectDir = input.cwd || dirname(filePath);
  const config = await loadGpuOptimizationGuardConfigWithProjectAndGlobalFallback(projectDir);
  if (!config.enabled) {
    return ALLOW_DECISION;
  }

  // Run all checks
  const findings: GpuOptimizationFinding[] = [];

  const batchCheck = checkBatchSizeAutoTuningAdoption(content, config);
  if (batchCheck) findings.push(batchCheck);

  const ampCheck = checkAutomaticMixedPrecisionAdoptionInGpuTrainingLoop(content, config);
  if (ampCheck) findings.push(ampCheck);

  const compileCheck = checkTorchCompileAdoptionForPyTorchTwoPlusGpuModels(content, config);
  if (compileCheck) findings.push(compileCheck);

  const dataLoaderCheck = checkDataLoaderHasNumWorkersAndPinMemoryConfigured(content, config);
  if (dataLoaderCheck) findings.push(dataLoaderCheck);

  const deviceCheck = checkCudaDeviceHardcodingWithoutAvailabilityFallback(content);
  if (deviceCheck) findings.push(deviceCheck);

  const cudnnCheck = checkCudnnBenchmarkEnabledForConvolutionalModelsOnGpu(content);
  if (cudnnCheck) findings.push(cudnnCheck);

  if (findings.length === 0) {
    return ALLOW_DECISION;
  }

  // Format deny reason with three severity sections
  const errors = findings.filter((f) => f.severity === "error");
  const warnings = findings.filter((f) => f.severity === "warn");
  const infos = findings.filter((f) => f.severity === "info");

  let message = `[GPU-OPTIMIZATION-GUARD] PyTorch training code in ${fileName} missing MANDATORY optimizations:\n\n`;

  if (errors.length > 0) {
    message += "**BLOCKING ERRORS** (MUST fix before proceeding):\n";
    for (const f of errors) {
      message += `- ${f.message}\n  → ${f.suggestion}\n\n`;
    }
  }
  if (warnings.length > 0) {
    message += "**WARNINGS** (significant performance impact):\n";
    for (const f of warnings) {
      message += `- ${f.message}\n  → ${f.suggestion}\n\n`;
    }
  }
  if (infos.length > 0) {
    message += "**SUGGESTIONS** (recommended optimizations):\n";
    for (const f of infos) {
      message += `- ${f.message}\n  → ${f.suggestion}\n\n`;
    }
  }

  message += `\n**Context**: These optimizations can reduce training time by 5-10x.
Example: batch_size=32 on RTX 4090 = 61 hours; batch_size=256 + AMP = 8 hours.

**Explicit Bypass**: Add comment \`# gpu-optimization-bypass: <reason>\` to allow anyway.
**Config**: Create .claude/gpu-optimization-guard.json to customize thresholds.`;

  logger.debug("Found optimization issues - BLOCKING", {
    file: fileName,
    findings: findings.length,
    errors: errors.length,
    warnings: warnings.length,
  });

  return denyDecision(message);
}

// =============================================================================
// Standalone main (backward-compat for direct CLI invocation)
// =============================================================================

async function main(): Promise<void> {
  const input = await parseStdinOrAllow("gpu-optimization-guard");
  if (!input) return;

  const decision = await classifyGpuOptimizationGuardForOrchestrator(input);
  switch (decision.kind) {
    case "deny":
      return deny(decision.reason ?? "(no reason given)");
    case "ask":
      return deny(decision.reason ?? "(no reason given)");
    default:
      return allow();
  }
}

// import.meta.main is true only for the entry-point script; when the orchestrator
// imports classifyGpuOptimizationGuardForOrchestrator, this branch does NOT fire.
if (import.meta.main) {
  main().catch((e) => {
    logger.error("Hook crashed", { error: e instanceof Error ? e.message : String(e) });
    allow();
  });
}
