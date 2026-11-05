#!/usr/bin/env python3
"""Check required v2 field types in a read-only cktool .ckdb export.

This is a requirements check, not Apple's full grammar validator or a claim
about deployment, permissions, record contents or export completeness.
"""
import re
import sys
from pathlib import Path

REQUIRED = {
    'SubmissionGate': {'coordinationVersion': 'INT64', 'generation': 'INT64', 'privateMode': 'INT64', 'privateModeEffectiveAt': 'TIMESTAMP', 'username': 'STRING'},
    'Listen': {'listenIDs': 'LIST<STRING>', 'username': 'STRING', 'leaseToken': 'STRING', 'leaseOwner': 'STRING', 'leaseExpiresAt': 'TIMESTAMP', 'duration': 'DOUBLE', 'title': 'STRING', 'artist': 'STRING', 'startedAt': 'TIMESTAMP', 'state': 'STRING', 'submittedAt': 'TIMESTAMP', 'lastError': 'STRING'},
}

def verify(source):
    source = re.sub(r'/\*.*?\*/|//[^\n]*|--[^\n]*', '', source, flags=re.S)
    types = {}
    for match in re.finditer(r'RECORD\s+TYPE\s+"?(\w+)"?\s*\((.*?)\)\s*;', source, re.S):
        name, body = match.groups()
        if name in types:
            raise ValueError('duplicate record type: ' + name)
        types[name] = body
    errors = []
    for name, fields in REQUIRED.items():
        body = types.get(name, '')
        for field, expected in fields.items():
            found = re.findall(r'(?:^|,)\s*"?' + field + r'"?\s+(LIST\s*<\s*\w+\s*>|\w+(?:\s+PREFERRED\s+AS\s+\w+)?)', body)
            actual = re.sub(r'\s+', '', found[0]) if len(found) == 1 else ''
            if actual not in (expected, 'NUMBERPREFERREDAS' + expected):
                errors.append(name + '.' + field + ' requires ' + expected + ', found ' + (actual or 'missing/ambiguous'))
    if errors:
        raise ValueError('\n'.join(errors))

if __name__ == '__main__':
    try:
        verify(Path(sys.argv[1]).read_text())
    except (ValueError, OSError, IndexError) as error:
        sys.exit(str(error))
    print('Required CloudKit v2 field types verified in supplied export; no remote changes made')
