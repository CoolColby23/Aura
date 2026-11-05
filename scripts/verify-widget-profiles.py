#!/usr/bin/env python3
"""Read-only profile and signing-certificate checks; never installs profiles."""
import argparse
import datetime
import hashlib
import pathlib
import plistlib
import re
import subprocess
import sys
import tempfile

GROUP = 'group.fm.aura.Aura'

def require(condition, message):
    if not condition:
        raise ValueError(message)

def fingerprint(certificate):
    # codesign identity hashes are SHA-1 fingerprints of public DER certificates.
    return hashlib.sha1(certificate).hexdigest().upper()

def validate(profile, bundle, certificate_sha1, now=None):
    ent = profile['Entitlements']
    team = profile['TeamIdentifier'][0]
    require(profile['ExpirationDate'] > (now or datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)), 'profile expired')
    require(ent.get('com.apple.application-identifier') == team + '.' + bundle, 'profile must match explicit bundle ID')
    require(GROUP in ent.get('com.apple.security.application-groups', []), 'profile must authorize shared app group')
    require(bool(re.fullmatch(r'[0-9A-Fa-f]{40}', certificate_sha1)), 'signing identity must be a certificate SHA-1 hash')
    allowed = [fingerprint(cert) for cert in profile.get('DeveloperCertificates', [])]
    require(certificate_sha1.upper() in allowed, 'profile does not authorize signing certificate')
    return team

def read(path):
    return plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(path)], stderr=subprocess.DEVNULL))

def signing_certificate(app):
    with tempfile.TemporaryDirectory(prefix='aura-signature-') as directory:
        prefix = str(pathlib.Path(directory) / 'certificate')
        subprocess.run(['codesign', '-d', '--extract-certificates', prefix, str(app)], check=True, stderr=subprocess.DEVNULL)
        return fingerprint(pathlib.Path(prefix + '0').read_bytes())

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('host_profile')
    parser.add_argument('widget_profile')
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--identity', help='pre-signing certificate SHA-1 identity hash')
    mode.add_argument('--app', type=pathlib.Path, help='verify actual host and widget leaf certificates after signing')
    parser.add_argument('--team')
    args = parser.parse_args()
    try:
        host_cert = args.identity or signing_certificate(args.app)
        widget_cert = args.identity or signing_certificate(args.app / 'Contents/PlugIns/AuraWidget.appex')
        team = validate(read(args.host_profile), 'fm.aura.Aura', host_cert)
        require(team == validate(read(args.widget_profile), 'fm.aura.Aura.Widget', widget_cert), 'profile teams differ')
        if args.team:
            require(team == args.team, 'profile does not match actual signing team')
        print(team)
    except (ValueError, TypeError, KeyError, IndexError, OSError, subprocess.CalledProcessError) as error:
        sys.exit('Widget provisioning verification failed: ' + str(error))
