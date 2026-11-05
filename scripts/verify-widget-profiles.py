#!/usr/bin/env python3
"""Read-only profile checks before packaging; never installs profiles."""
import datetime
import plistlib
import subprocess
import sys

GROUP = 'group.fm.aura.Aura'

def require(condition, message):
    if not condition:
        raise ValueError(message)

def validate(profile, bundle, now=None):
    ent = profile['Entitlements']
    team = profile['TeamIdentifier'][0]
    require(profile['ExpirationDate'] > (now or datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)), 'profile expired')
    require(ent.get('com.apple.application-identifier') == team + '.' + bundle, 'profile must match explicit bundle ID')
    require(GROUP in ent.get('com.apple.security.application-groups', []), 'profile must authorize shared app group')
    return team

def read(path, bundle):
    return validate(plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', path], stderr=subprocess.DEVNULL)), bundle)

if __name__ == '__main__':
    try:
        team = read(sys.argv[1], 'fm.aura.Aura')
        require(team == read(sys.argv[2], 'fm.aura.Aura.Widget'), 'profile teams differ')
        if len(sys.argv) > 3:
            require(team == sys.argv[3], 'profile does not match actual signing team')
        print(team)
    except (ValueError, KeyError, IndexError, subprocess.CalledProcessError) as error:
        sys.exit('Widget provisioning verification failed: ' + str(error))
