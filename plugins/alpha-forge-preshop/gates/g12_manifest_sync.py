"""G12: Manifest Sync Validator"""
from typing import Any, Dict, List

class ManifestSyncValidator:
    @staticmethod
    def validate_decorator_yaml_sync(decorator: Dict[str, Any], yaml_manifest: Dict[str, Any], plugin_name: str = "plugin") -> List[str]:
        issues = []
        deco_cols = set(decorator.get('outputs', {}).get('columns', []))
        yaml_cols = set(yaml_manifest.get('outputs', {}).get('columns', []))
        if deco_cols != yaml_cols:
            issues.append(f"[{plugin_name}] Output columns mismatch")
        return issues
