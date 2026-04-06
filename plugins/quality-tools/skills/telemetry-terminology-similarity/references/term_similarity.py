#!/usr/bin/env python3
# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "sentence-transformers",
#     "rapidfuzz",
#     "wordninja",
#     "orjson",
# ]
# ///
"""
Telemetry Terminology Similarity Analyzer

Detects semantically similar or duplicate field names across telemetry,
logging, and observability schemas. Uses a 3-layer pipeline:

  Layer 1 (Normalize): camelCase/snake_case splitting + wordninja expansion
  Layer 2 (Syntactic):  RapidFuzz token_set_ratio on normalized forms
  Layer 3 (Semantic):   sentence-transformers cosine similarity

Usage:
  # Analyze field names from stdin (one per line)
  echo -e "trace_id\\ntraceId\\nrequest_id\\ncorrelation_id" | uv run --python 3.13 term_similarity.py

  # Analyze a JSONL file's field names
  uv run --python 3.13 term_similarity.py --jsonl /path/to/telemetry.jsonl

  # Analyze two schemas for cross-schema overlap
  uv run --python 3.13 term_similarity.py --schema-a schema1.json --schema-b schema2.json

  # Custom thresholds
  # SSoT-OK: uv run handles PEP 723 inline deps
  uv run --python 3.13 term_similarity.py --syntactic-threshold 70 --semantic-threshold 0.45
"""
from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

import orjson
import wordninja
from rapidfuzz import fuzz
from sentence_transformers import SentenceTransformer, util


# ---------------------------------------------------------------------------
# Layer 1: Normalization
# ---------------------------------------------------------------------------

# Domain abbreviations commonly found in telemetry schemas
ABBREVIATIONS: dict[str, str] = {
    "ts": "timestamp",
    "uid": "user id",
    "acct": "account",
    "req": "request",
    "resp": "response",
    "err": "error",
    "msg": "message",
    "dur": "duration",
    "ms": "milliseconds",
    "ns": "nanoseconds",
    "us": "microseconds",
    "svc": "service",
    "env": "environment",
    "src": "source",
    "dst": "destination",
    "ctx": "context",
    "op": "operation",
    "lvl": "level",
    "evt": "event",
    "attr": "attribute",
    "idx": "index",
    "cnt": "count",
    "num": "number",
    "desc": "description",
    "cfg": "configuration",
    "auth": "authentication",
    "conn": "connection",
    "lat": "latency",
}


def normalize_field_name(name: str) -> str:
    """Normalize a field name to space-separated lowercase tokens.

    Handles: camelCase, snake_case, kebab-case, dot.notation,
    abbreviation expansion, and concatenated-word splitting.
    """
    # Split camelCase: "traceId" -> "trace Id"
    tokens = re.sub(r"([a-z0-9])([A-Z])", r"\1 \2", name)
    # Split on delimiters: snake_case, kebab-case, dot.notation
    tokens = re.sub(r"[_\-./]", " ", tokens).lower().strip()

    parts: list[str] = []
    for token in tokens.split():
        # Expand known abbreviations
        if token in ABBREVIATIONS:
            parts.extend(ABBREVIATIONS[token].split())
        else:
            # WordNinja split any remaining concatenated words
            split = wordninja.split(token)
            parts.extend(split if len(split) > 1 else [token])

    return " ".join(parts)


# ---------------------------------------------------------------------------
# Layer 2: Syntactic Matching (RapidFuzz)
# ---------------------------------------------------------------------------


def syntactic_similarity(a: str, b: str) -> float:
    """Token-set fuzzy ratio on normalized field names (0-100)."""
    return fuzz.token_set_ratio(a, b)


# ---------------------------------------------------------------------------
# Layer 3: Semantic Matching (sentence-transformers)
# ---------------------------------------------------------------------------

_MODEL: SentenceTransformer | None = None


def get_model() -> SentenceTransformer:
    global _MODEL
    if _MODEL is None:
        _MODEL = SentenceTransformer("all-MiniLM-L6-v2")
    return _MODEL


def semantic_similarity_matrix(
    normalized_names: list[str],
) -> list[list[float]]:
    """Compute pairwise cosine similarity using sentence-transformers."""
    model = get_model()
    embeddings = model.encode(normalized_names, show_progress_bar=False)
    sim_matrix = util.cos_sim(embeddings, embeddings)
    return sim_matrix.tolist()


# ---------------------------------------------------------------------------
# Analysis Pipeline
# ---------------------------------------------------------------------------


@dataclass
class SimilarityMatch:
    field_a: str
    field_b: str
    normalized_a: str
    normalized_b: str
    syntactic_score: float  # 0-100
    semantic_score: float  # 0.0-1.0
    match_type: str  # "exact", "syntactic", "semantic", "both"


@dataclass
class SimilarityCluster:
    canonical: str
    members: list[str] = field(default_factory=list)
    match_type: str = ""


@dataclass
class AnalysisReport:
    total_fields: int
    unique_normalized: int
    matches: list[SimilarityMatch]
    clusters: list[SimilarityCluster]
    exact_duplicates: list[tuple[str, str]]

    def to_json(self) -> str:
        return orjson.dumps(
            {
                "total_fields": self.total_fields,
                "unique_normalized": self.unique_normalized,
                "exact_duplicates": self.exact_duplicates,
                "similarity_matches": [
                    {
                        "field_a": m.field_a,
                        "field_b": m.field_b,
                        "normalized_a": m.normalized_a,
                        "normalized_b": m.normalized_b,
                        "syntactic_score": round(m.syntactic_score, 1),
                        "semantic_score": round(m.semantic_score, 3),
                        "match_type": m.match_type,
                    }
                    for m in self.matches
                ],
                "clusters": [
                    {"canonical": c.canonical, "members": c.members, "match_type": c.match_type}
                    for c in self.clusters
                ],
            },
            option=orjson.OPT_INDENT_2,
        ).decode()

    def to_text(self) -> str:
        lines: list[str] = []
        lines.append(f"Fields analyzed: {self.total_fields}")
        lines.append(f"Unique after normalization: {self.unique_normalized}")
        lines.append("")

        if self.exact_duplicates:
            lines.append("=== EXACT DUPLICATES (after normalization) ===")
            for a, b in self.exact_duplicates:
                lines.append(f"  {a}  ==  {b}")
            lines.append("")

        if self.clusters:
            lines.append("=== SIMILARITY CLUSTERS ===")
            for cluster in self.clusters:
                tag = f"[{cluster.match_type}]"
                lines.append(f"  {tag:12s} {cluster.canonical}")
                for member in cluster.members:
                    lines.append(f"               ~ {member}")
            lines.append("")

        if self.matches:
            lines.append("=== ALL MATCHES (sorted by combined score) ===")
            for m in self.matches:
                lines.append(
                    f"  syn={m.syntactic_score:5.1f}  sem={m.semantic_score:.3f}  "
                    f"[{m.match_type:9s}]  {m.field_a:25s} <-> {m.field_b}"
                )

        return "\n".join(lines)


def analyze_fields(
    fields: list[str],
    *,
    syntactic_threshold: float = 65.0,
    semantic_threshold: float = 0.55,
) -> AnalysisReport:
    """Run the full 3-layer similarity analysis pipeline."""
    # Layer 1: Normalize
    normalized = {f: normalize_field_name(f) for f in fields}

    # Detect exact duplicates (same normalized form)
    norm_to_originals: dict[str, list[str]] = defaultdict(list)
    for orig, norm in normalized.items():
        norm_to_originals[norm].append(orig)

    exact_duplicates: list[tuple[str, str]] = []
    for norm, originals in norm_to_originals.items():
        if len(originals) > 1:
            for i in range(1, len(originals)):
                exact_duplicates.append((originals[0], originals[i]))

    # Deduplicate for similarity analysis (use first occurrence)
    unique_fields = list(norm_to_originals.keys())
    unique_originals = [norm_to_originals[n][0] for n in unique_fields]

    # Layer 2 + 3: Compute similarities
    n = len(unique_fields)
    sem_matrix = semantic_similarity_matrix(unique_fields)

    matches: list[SimilarityMatch] = []
    for i in range(n):
        for j in range(i + 1, n):
            syn_score = syntactic_similarity(unique_fields[i], unique_fields[j])
            sem_score = sem_matrix[i][j]

            is_syn = syn_score >= syntactic_threshold
            is_sem = sem_score >= semantic_threshold

            if is_syn or is_sem:
                if is_syn and is_sem:
                    match_type = "both"
                elif is_syn:
                    match_type = "syntactic"
                else:
                    match_type = "semantic"

                matches.append(
                    SimilarityMatch(
                        field_a=unique_originals[i],
                        field_b=unique_originals[j],
                        normalized_a=unique_fields[i],
                        normalized_b=unique_fields[j],
                        syntactic_score=syn_score,
                        semantic_score=sem_score,
                        match_type=match_type,
                    )
                )

    # Sort by combined score (semantic weighted higher)
    matches.sort(key=lambda m: (m.semantic_score * 2 + m.syntactic_score / 100), reverse=True)

    # Build clusters via union-find
    parent: dict[str, str] = {f: f for f in unique_originals}

    def find(x: str) -> str:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a: str, b: str) -> None:
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    for m in matches:
        # Only cluster on strong matches to prevent mega-clusters from
        # transitive chains of weak matches through common English words.
        # Require: both layers agree, OR semantic score is very high.
        is_strong = (
            m.match_type == "both"
            or m.semantic_score >= 0.65
            or m.syntactic_score >= 90
        )
        if is_strong:
            union(m.field_a, m.field_b)

    cluster_map: dict[str, list[str]] = defaultdict(list)
    for f in unique_originals:
        root = find(f)
        if root != f:
            cluster_map[root].append(f)

    # Add exact duplicate members
    for a, b in exact_duplicates:
        root = find(a)
        if b not in cluster_map[root]:
            cluster_map[root].append(b)

    clusters: list[SimilarityCluster] = []
    for canonical, members in sorted(cluster_map.items()):
        # Determine cluster match type
        match_types = set()
        for m in matches:
            if m.field_a in [canonical, *members] and m.field_b in [canonical, *members]:
                match_types.add(m.match_type)
        for a, b in exact_duplicates:
            if a in [canonical, *members] or b in [canonical, *members]:
                match_types.add("exact")

        cluster_type = "+".join(sorted(match_types)) if match_types else "exact"
        clusters.append(SimilarityCluster(canonical=canonical, members=members, match_type=cluster_type))

    return AnalysisReport(
        total_fields=len(fields),
        unique_normalized=len(unique_fields),
        matches=matches,
        clusters=clusters,
        exact_duplicates=exact_duplicates,
    )


# ---------------------------------------------------------------------------
# Input helpers
# ---------------------------------------------------------------------------


def fields_from_jsonl(path: Path) -> list[str]:
    """Extract all unique field names from a JSONL file."""
    all_fields: set[str] = set()
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = orjson.loads(line)
                if isinstance(obj, dict):
                    _collect_keys(obj, "", all_fields)
            except orjson.JSONDecodeError:
                continue
    return sorted(all_fields)


def fields_from_json_schema(path: Path) -> list[str]:
    """Extract field names from a JSON schema file."""
    with open(path) as f:
        schema = orjson.loads(f.read())
    fields: set[str] = set()
    _collect_schema_fields(schema, fields)
    return sorted(fields)


def _collect_keys(obj: dict, prefix: str, keys: set[str]) -> None:
    for k, v in obj.items():
        full_key = f"{prefix}.{k}" if prefix else k
        keys.add(full_key)
        if isinstance(v, dict):
            _collect_keys(v, full_key, keys)


def _collect_schema_fields(schema: dict, fields: set[str]) -> None:
    if "properties" in schema:
        for name, prop in schema["properties"].items():
            fields.add(name)
            if isinstance(prop, dict):
                _collect_schema_fields(prop, fields)
    if "items" in schema and isinstance(schema["items"], dict):
        _collect_schema_fields(schema["items"], fields)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Detect similar/duplicate field names in telemetry schemas."
    )
    parser.add_argument(
        "fields",
        nargs="*",
        help="Field names to analyze (also reads stdin if no args)",
    )
    parser.add_argument(
        "--jsonl",
        type=Path,
        help="Extract field names from a JSONL file",
    )
    parser.add_argument(
        "--schema-a",
        type=Path,
        help="First JSON schema for cross-schema comparison",
    )
    parser.add_argument(
        "--schema-b",
        type=Path,
        help="Second JSON schema for cross-schema comparison",
    )
    parser.add_argument(
        "--syntactic-threshold",
        type=float,
        default=65.0,
        help="RapidFuzz token_set_ratio threshold (0-100, default: 65)",
    )
    parser.add_argument(
        "--semantic-threshold",
        type=float,
        default=0.45,
        help="Cosine similarity threshold (0.0-1.0, default: 0.45)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output as JSON instead of text",
    )

    args = parser.parse_args()

    # Collect field names from all sources
    fields: list[str] = []

    if args.jsonl:
        fields.extend(fields_from_jsonl(args.jsonl))
    elif args.schema_a and args.schema_b:
        fields_a = fields_from_json_schema(args.schema_a)
        fields_b = fields_from_json_schema(args.schema_b)
        fields.extend(fields_a)
        fields.extend(fields_b)
    elif args.fields:
        fields.extend(args.fields)
    elif not sys.stdin.isatty():
        for line in sys.stdin:
            line = line.strip()
            if line:
                fields.append(line)

    if not fields:
        parser.print_help()
        sys.exit(1)

    # Deduplicate input preserving order
    seen: set[str] = set()
    unique_fields: list[str] = []
    for f in fields:
        if f not in seen:
            seen.add(f)
            unique_fields.append(f)

    report = analyze_fields(
        unique_fields,
        syntactic_threshold=args.syntactic_threshold,
        semantic_threshold=args.semantic_threshold,
    )

    if args.json:
        print(report.to_json())
    else:
        print(report.to_text())


if __name__ == "__main__":
    main()
