#!/usr/bin/env python3
"""
Stores an incoming SIP MESSAGE to /var/lib/asterisk/messages.json.
Args: <from_b64> <to_ext> <body_b64>
Called from Asterisk [from-internal-msg] dialplan context via System().
"""
import sys
import json
import os
import re
import uuid
import time
import base64


def _b64d(s: str) -> str:
    padded = s + '=' * (-len(s) % 4)
    return base64.b64decode(padded).decode('utf-8', errors='replace')


from_b64, to_ext, body_b64 = sys.argv[1], sys.argv[2], sys.argv[3]
from_uri = _b64d(from_b64)
body     = _b64d(body_b64)

# Extract extension number from SIP URI like sip:1001@host or <sip:1001@host>
m = re.search(r'(?:sip:)?(\w+)@', from_uri)
from_ext = m.group(1) if m else from_uri

MESSAGES_FILE = '/var/lib/asterisk/messages.json'
os.makedirs(os.path.dirname(MESSAGES_FILE), exist_ok=True)
try:
    with open(MESSAGES_FILE) as f:
        messages = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    messages = []

messages.append({
    'id':        str(uuid.uuid4()),
    'from':      from_ext,
    'to':        to_ext,
    'body':      body,
    'timestamp': time.time(),
    'direction': 'received',
    'delivered': True,
})

with open(MESSAGES_FILE, 'w') as f:
    json.dump(messages, f)
