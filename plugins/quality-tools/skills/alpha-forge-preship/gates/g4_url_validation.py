"""G4: URL Fork / Stale-Org Validator.

Canonical repo home after the 2026-07 org migration is ``Eon-Labs/alpha-forge``.
Both the personal fork (``terrylica/alpha-forge``) and the now-dead old org
(``EonLabs-Spartan/alpha-forge``, transferred to Eon-Labs and wound down) must be
rewritten to ``Eon-Labs/`` in shipped code and docs.
"""
import re
from typing import List

# (pattern, issue-type, message). Order = reporting order.
_BAD_REPO_URLS = [
    (r'terrylica/alpha-forge', 'FORK_URL',
     'Use the canonical org URL (Eon-Labs/alpha-forge), not the personal fork (terrylica/).'),
    (r'EonLabs-Spartan/alpha-forge', 'STALE_ORG_URL',
     'EonLabs-Spartan was migrated to Eon-Labs (2026-07) and wound down; update to Eon-Labs/alpha-forge.'),
]


def validate_org_urls(file_path: str) -> List[dict]:
    with open(file_path) as f:
        content = f.read()
    issues = []
    for pattern, kind, message in _BAD_REPO_URLS:
        for match in re.finditer(pattern, content):
            line_num = content[:match.start()].count('\n') + 1
            issues.append({'type': kind, 'line': line_num, 'severity': 'error', 'message': message})
    return issues
