"""G4: URL Fork / Stale-Org Validator.

Canonical repo home after the 2026-07 org migration is ``example-org/research-repo``.
Both the personal fork (``terrylica/research-repo``) and the now-dead old org
(``example-org-legacy/research-repo``, transferred to example-org and wound down) must be
rewritten to ``example-org/`` in shipped code and docs.
"""
import re
from typing import List

# (pattern, issue-type, message). Order = reporting order.
_BAD_REPO_URLS = [
    (r'terrylica/research-repo', 'FORK_URL',
     'Use the canonical org URL (example-org/research-repo), not the personal fork (terrylica/).'),
    (r'example-org-legacy/research-repo', 'STALE_ORG_URL',
     'example-org-legacy was migrated to example-org (2026-07) and wound down; update to example-org/research-repo.'),
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
