#!/usr/bin/env python3
"""Synchronize a Certbot certificate through 1Panel's local agent API."""

import http.client
import json
from pathlib import Path
import socket
import sys


class PanelConnection(http.client.HTTPConnection):
    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect('/etc/1panel/agent.sock')


def request(path, payload):
    connection = PanelConnection('localhost', timeout=60)
    try:
        connection.request(
            'POST', '/api/v2/' + path, json.dumps(payload),
            {'Content-Type': 'application/json'},
        )
        response = connection.getresponse()
        result = json.loads(response.read())
        if response.status != 200 or result.get('code') != 200:
            raise RuntimeError(f'1Panel request failed for {path}')
        return result.get('data')
    finally:
        connection.close()


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: sync-panel-certificate.py DOMAIN')
    domain = sys.argv[1]
    certificates = request('websites/ssl/list', {}) or []
    matches = [item for item in certificates if item['primaryDomain'] == domain]
    if len(matches) != 1:
        raise SystemExit('Expected exactly one imported certificate for the domain')
    certificate = matches[0]
    certificate_path = certificate.get('certPath')
    key_path = certificate.get('privateKeyPath')
    if not certificate_path or not key_path:
        raise SystemExit('The certificate must reference local Certbot files')
    if (Path(certificate_path).read_text() == certificate['pem']
            and Path(key_path).read_text() == certificate['privateKey']):
        print(f'1Panel certificate is current for {domain}')
        return
    request('websites/ssl/upload', {
        'type': 'local',
        'sslID': certificate['id'],
        'certificatePath': certificate_path,
        'privateKeyPath': key_path,
        'description': certificate['description'],
        'pushNode': certificate.get('pushNode', False),
        'nodes': certificate.get('nodes', ''),
    })
    print(f'1Panel certificate synchronized for {domain}')


if __name__ == '__main__':
    main()
