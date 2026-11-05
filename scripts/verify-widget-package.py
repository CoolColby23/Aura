#!/usr/bin/env python3
"""Verify embedded widget metadata and signed entitlements (no registration)."""
import os
import pathlib
import plistlib
import subprocess
import sys

def require(condition, message):
    if not condition:
        raise ValueError(message)

app = pathlib.Path(sys.argv[1])
widget = app / 'Contents/PlugIns/AuraWidget.appex'
def plist(path):
    return plistlib.loads(path.read_bytes())
def entitlements(path):
    return plistlib.loads(subprocess.check_output(['codesign', '-d', '--entitlements', ':-', str(path)], stderr=subprocess.DEVNULL))
try:
    host = plist(app / 'Contents/Info.plist')
    info = plist(widget / 'Contents/Info.plist')
    require(info['CFBundleIdentifier'] == host['CFBundleIdentifier'] + '.Widget', 'extension bundle identifier mismatch')
    require(info['CFBundlePackageType'] == 'XPC!', 'extension package type mismatch')
    require(info['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension', 'extension point mismatch')
    for key in ['CFBundleShortVersionString', 'CFBundleVersion', 'LSMinimumSystemVersion']:
        require(info[key] == host[key], key + ' differs from host')
    executable = widget / 'Contents/MacOS' / info['CFBundleExecutable']
    require(executable.is_file() and os.access(executable, os.X_OK), 'extension executable missing or not executable')
    subprocess.run(['codesign', '--verify', '--strict', str(widget)], check=True)
    extension_ent = entitlements(widget)
    require(extension_ent.get('com.apple.security.app-sandbox') is True, 'extension must be sandboxed')
    for path in [app, widget]:
        require(entitlements(path).get('com.apple.security.application-groups') == ['group.fm.aura.Aura'], 'app group mismatch')
    def team(path):
        output = subprocess.check_output(['codesign', '-dv', str(path)], stderr=subprocess.STDOUT).decode()
        return next(line for line in output.splitlines() if line.startswith('TeamIdentifier='))
    require(team(app) == team(widget), 'signing teams differ')
except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
    sys.exit('Widget package verification failed: ' + str(error))
print('Verified embedded widget metadata, sandbox, shared group and signatures; gallery acceptance requires provisioned hardware')
