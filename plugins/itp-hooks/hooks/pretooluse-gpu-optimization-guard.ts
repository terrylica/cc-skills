#!/usr/bin/env bun
/**
 * PreToolUse Hook: GPU Optimization Guard (MANDATORY ENFORCEMENT)
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
} from "./pretooluse-helpers.ts";

const logger = createHookLogger("gpu-optimization-guard");

// =============================================================================
// Configuration
// =============================================================================

interface GuardConfig {
  enabled: boolean;
  minBatchSize: number;           // Block if batch_size < this
  requireAMP: boolean;            // Require AMP for training loops
  requireTorchCompile: boolean;   // Require torch.compile for PyTorch 2.0+
  requireDataLoaderOptim: boolean; // Require num_workers, pin_memory
  filePatterns: string[];         // Files to check (glob patterns)
  excludePatterns: string[];      // Files to skip
}

const DEFAULT_CONFIG: GuardConfig = {
  enabled: true,
  minBatchSize: 64,              // Reasonable minimum for modern GPUs
  requireAMP: true,
  requireTorchCompile: true,
  requireDataLoaderOptim: true,
  filePatterns: ["**/*.py"],
  excludePatterns: ["**/test_*.py", "**/*_test.py", "**/conftest.py"],
};

async function loadConfig(projectDir: string | undefined): Promise<GuardConfig> {
  const config = { ...DEFAULT_CONFIG };
  const home = Bun.env.HOME || "";

  // Try project-level config
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

  // Try global config
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
// Detection Patterns
// =============================================================================

interface Finding {
  category: string;
  severity: "error" | "warn" | "info";
  message: string;
  suggestion: string;
}

/**
 * Check for explicit bypass comment
 */
function hasBypassComment(content: string): boolean {
  return /# gpu-optimization-bypass:/.test(content);
}

/**
 * Detect if this is a PyTorch training script (not just imports)
 */
function isPyTorchTrainingScript(content: string): boolean {
  // Must have torch import
  if (!/import\s+torch|from\s+torch/.test(content)) {
    return false;
  }

  // Must have training indicators
  const trainingIndicators = [
    /\.backward\(\)/,           // Loss backpropagation
    /\.step\(\)/,               // Optimizer step
    /nn\.Module/,               // Model definition
    /DataLoader/,               // Data loading
    /\.train\(\)/,              // Training mode
    /for\s+.*\s+in\s+.*loader/, // Training loop
    /epoch/i,                   // Epoch iteration
  ];

  return trainingIndicators.some((pattern) => pattern.test(content));
}

/**
 * Check for batch size optimization patterns
 *
 * PARAMETER-FREE APPROACH: Instead of magic numbers like "batch_size >= 64",
 * we require one of these automatic batch size optimization patterns:
 *
 * 1. PyTorch Lightning: Tuner.scale_batch_size() or BatchSizeFinder
 * 2. Hugging Face Accelerate: @find_executable_batch_size decorator
 * 3. Manual binary search: find_optimal_batch_size pattern
 * 4. Gradient accumulation: accumulation_steps pattern
 *
 * @see https://lightning.ai/docs/pytorch/stable/api/lightning.pytorch.callbacks.BatchSizeFinder.html
 * @see https://huggingface.co/docs/accelerate/v0.11.0/en/memory
 */
function checkBatchSize(content: string, config: GuardConfig): Finding | null {
  // Check if this is GPU training code
  const hasGPU = /\.cuda\(\)|\.to\(\s*["']cuda["']|device\s*=\s*["']cuda/.test(content);
  const hasTrainingLoop = /\.backward\(\)|for\s+.*\s+in\s+.*loader/i.test(content);

  if (!hasGPU || !hasTrainingLoop) return null;

  // Check for automatic batch size optimization patterns (PREFERRED)
  const hasAutoBatchSize =
    // PyTorch Lightning
    /scale_batch_size|BatchSizeFinder|auto_scale_batch_size/.test(content) ||
    // Hugging Face Accelerate
    /find_executable_batch_size|auto_find_batch_size/.test(content) ||
    // Manual binary search pattern
    /find_optimal_batch_size|binary.*search.*batch|batch.*binary.*search/i.test(content) ||
    // Gradient accumulation (effective large batch)
    /accumulation_steps|gradient_accumulation|accum_iter/i.test(content) ||
    // Explicit bypass
    /# ?batch.*(ok|tuned|optimal|tested)/i.test(content);

  if (hasAutoBatchSize) return null;

  // Check for hardcoded small batch sizes
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

  // Even if batch_size is large, suggest auto-tuning for optimal GPU utilization
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

/**
 * Check for missing cudnn.benchmark (important for conv-heavy models)
 */
function checkCudnnBenchmark(content: string): Finding | null {
  // Only check if this looks like a CNN/conv model
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

/**
 * Check for missing AMP (Automatic Mixed Precision)
 *
 * AMP is required when ALL of these are present:
 * - GPU usage (cuda device)
 * - Backpropagation (.backward())
 * - Optimizer step (.step())
 */
function checkAMP(content: string, config: GuardConfig): Finding | null {
  if (!config.requireAMP) return null;

  // Check for GPU training (all three must be present)
  const hasGPU = /\.cuda\(\)|\.to\(\s*["']cuda["']|\.to\(\s*device\)|device\s*=\s*["']cuda/.test(content);
  const hasBackward = /\.backward\(\)/.test(content);
  const hasOptimizerStep = /optimizer\.step\(\)|\.step\(\)/.test(content);

  const isGPUTraining = hasGPU && hasBackward && hasOptimizerStep;

  if (!isGPUTraining) return null;

  const hasAMP =
    /autocast|GradScaler|torch\.amp|torch\.cuda\.amp/.test(content);
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

/**
 * Check for missing torch.compile (PyTorch 2.0+)
 *
 * Only applies to GPU training - torch.compile provides biggest gains on CUDA.
 * CPU training can benefit too, but it's not mandatory.
 */
function checkTorchCompile(content: string, config: GuardConfig): Finding | null {
  if (!config.requireTorchCompile) return null;

  // Only check for GPU training (torch.compile is most impactful on GPU)
  const hasGPU = /\.cuda\(\)|\.to\(\s*["']cuda["']|device\s*=\s*["']cuda/.test(content);
  if (!hasGPU) return null;

  // Has model creation but no torch.compile
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

/**
 * Check for suboptimal DataLoader configuration
 */
function checkDataLoader(content: string, config: GuardConfig): Finding | null {
  if (!config.requireDataLoaderOptim) return null;

  // Has DataLoader but missing optimizations
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

/**
 * Check for hardcoded device without availability check
 */
function checkDeviceHardcoding(content: string): Finding | null {
  // device = "cuda" without torch.cuda.is_available()
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
// Main Hook Logic
// =============================================================================

async function main(): Promise<void> {
  const input = await parseStdinOrAllow("gpu-optimization-guard");
  if (!input) return;

  const toolName = input.tool_name || "";
  if (toolName !== "Write" && toolName !== "Edit") {
    allow();
    return;
  }

  const filePath = input.tool_input?.file_path || "";
  const content = input.tool_input?.content || input.tool_input?.new_string || "";

  // Only check Python files
  if (!filePath.endsWith(".py")) {
    allow();
    return;
  }

  // Skip test files
  const fileName = basename(filePath);
  if (fileName.startsWith("test_") || fileName.endsWith("_test.py") || fileName === "conftest.py") {
    allow();
    return;
  }

  // Check for explicit bypass comment
  if (hasBypassComment(content)) {
    logger.debug("Bypass comment found, allowing", { file: fileName });
    allow();
    return;
  }

  // Only check if it looks like a PyTorch training script
  if (!isPyTorchTrainingScript(content)) {
    allow();
    return;
  }

  // Load configuration
  const projectDir = input.cwd || dirname(filePath);
  const config = await loadConfig(projectDir);

  if (!config.enabled) {
    allow();
    return;
  }

  // Run all checks
  const findings: Finding[] = [];

  const batchCheck = checkBatchSize(content, config);
  if (batchCheck) findings.push(batchCheck);

  const ampCheck = checkAMP(content, config);
  if (ampCheck) findings.push(ampCheck);

  const compileCheck = checkTorchCompile(content, config);
  if (compileCheck) findings.push(compileCheck);

  const dataLoaderCheck = checkDataLoader(content, config);
  if (dataLoaderCheck) findings.push(dataLoaderCheck);

  const deviceCheck = checkDeviceHardcoding(content);
  if (deviceCheck) findings.push(deviceCheck);

  const cudnnCheck = checkCudnnBenchmark(content);
  if (cudnnCheck) findings.push(cudnnCheck);

  // No issues found
  if (findings.length === 0) {
    allow();
    return;
  }

  // Format findings
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

  // MANDATORY: Use "deny" (hard block) for errors, "ask" for warnings only
  if (errors.length > 0) {
    deny(message);
  } else {
    // Only warnings/info - still deny but could be configured to ask
    deny(message);
  }
}

main().catch((e) => {
  logger.error("Hook crashed", { error: e instanceof Error ? e.message : String(e) });
  allow(); // Fail safely
});
