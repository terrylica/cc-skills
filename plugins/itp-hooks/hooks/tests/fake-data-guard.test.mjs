#!/usr/bin/env bun
/**
 * Unit tests for Fake Data Guard pattern detection.
 *
 * Run with: bun test plugins/itp-hooks/hooks/tests/
 *
 * ADR: /docs/adr/2025-12-27-fake-data-guard-universal.md
 */

import { describe, it, expect, beforeEach } from "bun:test";
import {
  PATTERNS,
  DEFAULT_CONFIG,
  detectFakeData,
  isWhitelisted,
  isExcludedPath,
  formatFindings,
} from "../fake-data-patterns.mjs";

// All patterns enabled for testing
const ALL_PATTERNS_ENABLED = {
  numpy_random: true,
  python_random: true,
  faker_library: true,
  factory_patterns: true,
  synthetic_keywords: true,
  data_generation: true,
  test_data_libs: true,
};

describe("PATTERNS structure", () => {
  it("has 7 categories", () => {
    expect(Object.keys(PATTERNS).length).toBe(7);
  });

  it("has 69 total patterns", () => {
    const totalPatterns = Object.values(PATTERNS).reduce(
      (sum, patterns) => sum + patterns.length,
      0
    );
    expect(totalPatterns).toBe(69);
  });

  it("has correct pattern counts per category", () => {
    expect(PATTERNS.numpy_random.length).toBe(15);
    expect(PATTERNS.python_random.length).toBe(10);
    expect(PATTERNS.faker_library.length).toBe(4);
    expect(PATTERNS.factory_patterns.length).toBe(7);
    expect(PATTERNS.synthetic_keywords.length).toBe(21);
    expect(PATTERNS.data_generation.length).toBe(7);
    expect(PATTERNS.test_data_libs.length).toBe(5);
  });
});

describe("detectFakeData - NumPy Random", () => {
  it("detects np.random.randn", () => {
    const content = "data = np.random.randn(100, 5)";
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED);
    expect(findings.length).toBeGreaterThan(0);
    expect(findings[0].category).toBe("numpy_random");
    expect(findings[0].match).toBe("np.random.randn");
    expect(findings[0].line).toBe(1);
  });

  it("detects np.random.rand", () => {
    const content = "x = np.random.rand(10)";
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED);
    expect(findings.length).toBeGreaterThan(0);
    expect(findings[0].match).toBe("np.random.rand");
  });

  it("detects np.random.normal", () => {
    const content = "samples = np.random.normal(0, 1, 1000)";
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED);
    expect(findings.length).toBeGreaterThan(0);
    expect(findings[0].match).toBe("np.random.normal");
  });

  it("detects RandomState", () => {
    const content = "rng = np.random.RandomState(42)";
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED);
    expect(findings.length).toBeGreaterThan(0);
    expect(findings[0].match).toBe("RandomState");
  });

  it("detects default_rng", () => {
    const content = "rng = np.random.default_rng(seed=42)";
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED);
    expect(findings.length).toBeGreaterThan(0);
    expect(findings[0].match).toBe("default_rng");
  });
});

describe("detectFakeData - Python Random", () => {
  it("detects random.random()", () => {
    const content = "x = random.random()";
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED);
    expect(findings.length).toBeGreaterThan(0);
    expect(findings[0].category).toBe("python_random");
  });

  it("detects random.randint()", () => {
    const content = "n = random.randint(1, 100)";
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED);
    expect(findings.length).toBeGreaterThan(0);
    expect(findings[0].match).toBe("random.randint(");
  });

  it("detects random.choice()", () => {
    const content = "item = random.choice(items)";
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED);
    expect(findings.length).toBeGreaterThan(0);
  });
});

describe("detectFakeData - Faker Library", () => {
  it("detects Faker()", () => {
    const content = "fake = Faker()";
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED);
    expect(findings.length).toBeGreaterThan(0);
    expect(findings[0].category).toBe("faker_library");
  });

  it("detects faker.name", () => {
    const content = "name = faker.name()";
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED);
    expect(findings.length).toBeGreaterThan(0);
  });

  it("detects from faker import", () => {
    const content = "from faker import Faker";
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED);
    expect(findings.length).toBeGreaterThan(0);
  });
});

describe("detectFakeData - Factory Patterns", () => {
  it("detects Factory.create", () => {
    const content = "user = Factory.create()";
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED);
    expect(findings.length).toBeGreaterThan(0);
    expect(findings[0].category).toBe("factory_patterns");
  });

  it("detects _factory suffix", () => {
    const content = "user_factory = UserFactory()";
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED);
    expect(findings.length).toBeGreaterThan(0);
  });
});

describe("detectFakeData - Synthetic Keywords", () => {
  it("detects synthetic_data", () => {
    const content = "synthetic_data = generate()";
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED);
    expect(findings.length).toBeGreaterThan(0);
    expect(findings[0].category).toBe("synthetic_keywords");
  });

  it("detects mock_data (case insensitive)", () => {
    const content = "MOCK_DATA = {}";
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED);
    expect(findings.length).toBeGreaterThan(0);
  });

  it("detects generate_random", () => {
    const content = "data = generate_random(100)";
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED);
    expect(findings.length).toBeGreaterThan(0);
  });
});

describe("detectFakeData - Data Generation", () => {
  it("detects make_classification", () => {
    const content = "X, y = make_classification(n_samples=100)";
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED);
    expect(findings.length).toBeGreaterThan(0);
    expect(findings[0].category).toBe("data_generation");
  });

  it("detects make_regression", () => {
    const content = "X, y = make_regression()";
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED);
    expect(findings.length).toBeGreaterThan(0);
  });

  it("detects sklearn.datasets.make", () => {
    const content = "from sklearn.datasets.make import make_blobs";
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED);
    expect(findings.length).toBeGreaterThan(0);
  });
});

describe("detectFakeData - Test Data Libraries", () => {
  it("detects hypothesis", () => {
    const content = "from hypothesis import given";
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED);
    expect(findings.length).toBeGreaterThan(0);
    expect(findings[0].category).toBe("test_data_libs");
  });

  it("detects polyfactory", () => {
    const content = "from polyfactory import ModelFactory";
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED);
    expect(findings.length).toBeGreaterThan(0);
  });
});

describe("detectFakeData - Category Filtering", () => {
  it("respects disabled numpy_random category", () => {
    const content = "data = np.random.randn(100)";
    const findings = detectFakeData(content, { ...ALL_PATTERNS_ENABLED, numpy_random: false });
    // Should not find numpy_random, but might find others
    const numpyFindings = findings.filter((f) => f.category === "numpy_random");
    expect(numpyFindings.length).toBe(0);
  });

  it("respects disabled faker_library category", () => {
    const content = "fake = Faker()";
    const findings = detectFakeData(content, { ...ALL_PATTERNS_ENABLED, faker_library: false });
    const fakerFindings = findings.filter((f) => f.category === "faker_library");
    expect(fakerFindings.length).toBe(0);
  });

  it("returns empty when all categories disabled", () => {
    const content = "data = np.random.randn(100)\nfake = Faker()";
    const noPatterns = {
      numpy_random: false,
      python_random: false,
      faker_library: false,
      factory_patterns: false,
      synthetic_keywords: false,
      data_generation: false,
      test_data_libs: false,
    };
    const findings = detectFakeData(content, noPatterns);
    expect(findings.length).toBe(0);
  });
});

describe("detectFakeData - Whitelist", () => {
  it("skips whitelisted lines with noqa", () => {
    const content = "data = np.random.randn(100)  # noqa: fake-data";
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED, ["# noqa: fake-data"]);
    expect(findings.length).toBe(0);
  });

  it("skips whitelisted lines with allow-random", () => {
    const content = "data = np.random.randn(100)  # allow-random";
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED, ["# allow-random"]);
    expect(findings.length).toBe(0);
  });

  it("detects non-whitelisted lines", () => {
    const content = `
data = np.random.randn(100)  # noqa: fake-data
other = np.random.rand(50)
    `.trim();
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED, ["# noqa: fake-data"]);
    expect(findings.length).toBe(1);
    expect(findings[0].line).toBe(2);
  });
});

describe("detectFakeData - Comments", () => {
  it("skips Python comment lines", () => {
    const content = "# data = np.random.randn(100)";
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED);
    expect(findings.length).toBe(0);
  });

  it("detects code after comment on same line", () => {
    // This is actual code, not just a comment
    const content = 'x = 1  # np.random.randn is not used here';
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED);
    // The pattern is in the comment part, but the whole line is not a comment
    // Our implementation checks if trimmed line starts with #
    expect(findings.length).toBe(1);
  });
});

describe("detectFakeData - Line Numbers", () => {
  it("reports correct line numbers", () => {
    const content = `
import numpy as np

def generate():
    data = np.random.randn(100)
    return data
    `.trim();
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED);
    expect(findings.length).toBeGreaterThan(0);
    expect(findings[0].line).toBe(4); // Line with np.random.randn
  });

  it("detects multiple patterns on different lines", () => {
    const content = `
data1 = np.random.randn(100)
data2 = random.randint(1, 100)
fake = Faker()
    `.trim();
    const findings = detectFakeData(content, ALL_PATTERNS_ENABLED);
    expect(findings.length).toBe(3);
    expect(findings.map((f) => f.line).sort()).toEqual([1, 2, 3]);
  });
});

describe("isWhitelisted", () => {
  it("returns true for matching comment", () => {
    expect(isWhitelisted("x = 1  # noqa: fake-data", ["# noqa: fake-data"])).toBe(true);
  });

  it("returns false for non-matching line", () => {
    expect(isWhitelisted("x = 1", ["# noqa: fake-data"])).toBe(false);
  });

  it("handles multiple whitelist patterns", () => {
    expect(isWhitelisted("x = 1  # allow-random", ["# noqa: fake-data", "# allow-random"])).toBe(
      true
    );
  });
});

describe("isExcludedPath", () => {
  it("excludes paths starting with tests/", () => {
    expect(isExcludedPath("tests/test_model.py", ["tests/"])).toBe(true);
  });

  it("excludes paths containing tests/", () => {
    expect(isExcludedPath("src/tests/test_model.py", ["tests/"])).toBe(true);
  });

  it("excludes *_test.py files", () => {
    expect(isExcludedPath("src/model_test.py", ["*_test.py"])).toBe(true);
  });

  it("excludes conftest.py", () => {
    expect(isExcludedPath("tests/conftest.py", ["conftest.py"])).toBe(true);
    expect(isExcludedPath("src/tests/conftest.py", ["conftest.py"])).toBe(true);
  });

  it("does not exclude non-matching paths", () => {
    expect(isExcludedPath("src/model.py", ["tests/", "*_test.py", "conftest.py"])).toBe(false);
  });
});

describe("formatFindings", () => {
  it("groups findings by category", () => {
    const findings = [
      { category: "numpy_random", line: 5, match: "np.random.randn", context: "..." },
      { category: "numpy_random", line: 10, match: "np.random.rand", context: "..." },
      { category: "faker_library", line: 15, match: "Faker(", context: "..." },
    ];
    const formatted = formatFindings(findings);
    expect(formatted).toContain("numpy_random:");
    expect(formatted).toContain("faker_library:");
    expect(formatted).toContain("Line 5");
    expect(formatted).toContain("Line 15");
  });

  it("limits to 3 findings per category", () => {
    const findings = [
      { category: "numpy_random", line: 1, match: "a", context: "" },
      { category: "numpy_random", line: 2, match: "b", context: "" },
      { category: "numpy_random", line: 3, match: "c", context: "" },
      { category: "numpy_random", line: 4, match: "d", context: "" },
      { category: "numpy_random", line: 5, match: "e", context: "" },
    ];
    const formatted = formatFindings(findings);
    expect(formatted).toContain("... and 2 more");
  });
});

describe("DEFAULT_CONFIG", () => {
  it("has all pattern categories enabled by default", () => {
    for (const category of Object.keys(PATTERNS)) {
      expect(DEFAULT_CONFIG.patterns[category]).toBe(true);
    }
  });

  it("has ask mode by default", () => {
    expect(DEFAULT_CONFIG.mode).toBe("ask");
  });

  it("has default whitelist comments", () => {
    expect(DEFAULT_CONFIG.whitelist_comments).toContain("# noqa: fake-data");
  });

  it("has default exclude paths", () => {
    expect(DEFAULT_CONFIG.exclude_paths).toContain("tests/");
  });
});
