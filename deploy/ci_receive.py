#!/usr/bin/python3
"""Receive a CI-built CsAC image through a restricted SSH command."""

from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import signal
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.request


SERVICES = ('rpc', 'serverbot', 'acop', 'emapps')


@dataclass(frozen=True)
class Release:
    sha: str
    run: int
    attempt: int
    digest: str

    @property
    def tag(self):
        return f'{self.sha}-{self.run}-{self.attempt}'

    @property
    def image(self):
        return f'csac-backend:{self.tag}'


def parse_command(command):
    fields = shlex.split(command)
    if (len(fields) != 5 or fields[0] != 'deploy'
            or not re.fullmatch(r'[0-9a-f]{40}', fields[1])
            or not re.fullmatch(r'[1-9][0-9]{0,14}', fields[2])
            or not re.fullmatch(r'[1-9][0-9]{0,5}', fields[3])
            or not re.fullmatch(r'[0-9a-f]{64}', fields[4])):
        raise ValueError('Expected deploy <commit-sha> <run-number> <attempt> <archive-sha256>')
    return Release(fields[1], int(fields[2]), int(fields[3]), fields[4])


def sync_directory(directory):
    descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def atomic_write(path, contents):
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(contents)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.chmod(0o600)
        os.replace(temporary, path)
        temporary = None
        sync_directory(path.parent)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def atomic_remove(path):
    path.unlink(missing_ok=True)
    sync_directory(path.parent)


def with_release(contents, tag):
    lines = [line for line in contents.splitlines()
             if line.partition('=')[0].strip() != 'CSAC_RELEASE']
    return '\n'.join(lines + [f'CSAC_RELEASE={tag}']) + '\n'


def receive_image(stream, path, expected, maximum):
    digest = hashlib.sha256()
    total = 0
    with path.open('xb') as target:
        while chunk := stream.read(1024 * 1024):
            total += len(chunk)
            if total > maximum:
                raise ValueError('Image upload exceeds the configured size limit')
            digest.update(chunk)
            target.write(chunk)
    if total == 0 or digest.hexdigest() != expected:
        raise ValueError('Image upload failed SHA256 verification')


def validate_archive(path, image):
    with tarfile.open(path, 'r:gz') as archive:
        unpacked = 0
        for member in archive:
            unpacked += member.size
            if (unpacked > 1024 * 1024 * 1024 or member.name.startswith('/')
                    or '..' in Path(member.name).parts
                    or not (member.isfile() or member.isdir())):
                raise ValueError('Unsupported Docker image archive')
        manifest_file = archive.getmember('manifest.json')
        if manifest_file.size > 1024 * 1024:
            raise ValueError('Docker manifest exceeds the size limit')
        manifest = json.load(archive.extractfile(manifest_file))
        tags = [tag for entry in manifest for tag in (entry.get('RepoTags') or [])]
        if tags != [image]:
            raise ValueError('Archive must contain only the requested CsAC image tag')
        if 'index.json' in archive.getnames():
            index_file = archive.getmember('index.json')
            if index_file.size > 1024 * 1024:
                raise ValueError('Docker index exceeds the size limit')
            descriptors = json.load(archive.extractfile(index_file)).get('manifests', [])
            if len(descriptors) != 1:
                raise ValueError('Archive must contain one image reference')
            annotations = descriptors[0].get('annotations', {})
            if (annotations.get('io.containerd.image.name', image)
                    not in (image, f'docker.io/library/{image}')
                    or annotations.get('org.opencontainers.image.ref.name', image.split(':')[1])
                    != image.split(':')[1]):
                raise ValueError('Unexpected Docker image reference')


class Deployer:
    def __init__(self, config):
        self.repo = Path(config['repo_dir'])
        self.releases = Path(config['releases_dir'])
        self.backups = Path(config['backup_dir'])
        self.project = config.get('project', 'csac')
        self.health_url = config.get('health_url', 'http://127.0.0.1:18081/healthz')
        self.lock = Path(config.get('lock_file', '/run/lock/csac-deploy.lock'))
        self.maximum = config.get('max_image_bytes', 256 * 1024 * 1024)
        self.wait_seconds = config.get('wait_seconds', 120)
        self.environment = self.repo / '.env'
        self.state = self.releases / '.deploy-state.json'
        self.pending = self.releases / '.deploy-pending.json'

    def compose(self, *arguments, override=None):
        command = ['docker', 'compose', '-p', self.project,
                   '--env-file', str(self.environment), '-f', str(self.repo / 'compose.yaml')]
        if override is not None:
            command.extend(['-f', str(override)])
        subprocess.run(command + list(arguments), cwd=self.repo, check=True)

    def current_images(self):
        images = {}
        for service in SERVICES:
            image = subprocess.check_output(
                ['docker', 'inspect', '--format', '{{.Config.Image}}',
                 f'{self.project}-{service}-1'], text=True,
            ).strip()
            if not re.fullmatch(r'csac-backend:[A-Za-z0-9_.-]+', image):
                raise ValueError(f'Unexpected running image for {service}')
            images[service] = image
        return images

    def wait_healthy(self):
        deadline = time.monotonic() + 30
        while True:
            try:
                with urllib.request.urlopen(self.health_url, timeout=3) as response:
                    if response.status == 200 and json.load(response).get('success') is True:
                        return
            except (OSError, ValueError, urllib.error.HTTPError):
                pass
            if time.monotonic() >= deadline:
                raise RuntimeError('CsAC HTTP health check failed')
            time.sleep(1)

    def activate(self, override=None):
        self.compose('up', '-d', '--no-build', '--no-deps', '--wait',
                     '--wait-timeout', str(self.wait_seconds), *SERVICES, override=override)
        self.wait_healthy()

    def restore(self, record):
        previous_environment = Path(record['environment_backup'])
        atomic_write(self.environment, previous_environment.read_text())
        override = previous_environment.parent / 'previous-images.json'
        atomic_write(override, json.dumps({
            'services': {service: {'image': image}
                         for service, image in record['previous_images'].items()},
        }))
        self.activate(override)
        if record['previous_state'] is None:
            atomic_remove(self.state)
        else:
            atomic_write(self.state, json.dumps(record['previous_state'], indent=2) + '\n')
        atomic_remove(self.pending)

    def deploy(self, release, stream):
        self.releases.mkdir(parents=True, exist_ok=True, mode=0o700)
        with tempfile.TemporaryDirectory(prefix='.upload-', dir=self.releases) as directory:
            archive = Path(directory) / 'image.tar.gz'
            receive_image(stream, archive, release.digest, self.maximum)
            validate_archive(archive, release.image)
            with self.lock.open('a') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                if self.pending.exists():
                    print('Recovering an interrupted deployment.', flush=True)
                    self.restore(json.loads(self.pending.read_text()))
                state = json.loads(self.state.read_text()) if self.state.exists() else None
                if state:
                    if release.run == state['run'] and release.sha != state['sha']:
                        raise ValueError('A workflow run cannot change its commit SHA')
                    if (release.run, release.attempt) <= (state['run'], state['attempt']):
                        print('Skipped superseded CsAC workflow run.', flush=True)
                        return
                subprocess.run(['docker', 'image', 'load', '--input', str(archive)], check=True)
                image = json.loads(subprocess.check_output(
                    ['docker', 'image', 'inspect', release.image], text=True,
                ))[0]
                if (image['Config']['User'] != 'csac:csac' or image['Os'] != 'linux'
                        or image['Architecture'] != 'amd64'
                        or image['Config'].get('Labels', {}).get('org.opencontainers.image.revision')
                        != release.sha):
                    raise ValueError('Image runtime identity or revision does not match')
                backup = self.backups / f'ci-{release.tag}'
                backup.mkdir(parents=True, exist_ok=True, mode=0o700)
                previous_environment = backup / '.env'
                atomic_write(previous_environment, self.environment.read_text())
                record = asdict(release) | {
                    'image': release.image,
                    'image_id': image['Id'],
                    'previous_images': self.current_images(),
                    'previous_state': state,
                    'environment_backup': str(previous_environment),
                    'deployed_at': datetime.now(timezone.utc).isoformat(),
                }
                subprocess.run(
                    ['bash', str(self.repo / 'deploy/backup.sh'), str(backup)],
                    cwd=self.repo, check=True,
                    env=dict(os.environ, COMPOSE_PROJECT_NAME=self.project),
                )
                self.compose('config', '--quiet')
                atomic_write(self.pending, json.dumps(record, indent=2) + '\n')
                try:
                    atomic_write(self.environment,
                                 with_release(previous_environment.read_text(), release.tag))
                    self.activate()
                    completed = {key: value for key, value in record.items()
                                 if key not in ('previous_state', 'environment_backup')}
                    atomic_write(self.state, json.dumps(completed, indent=2) + '\n')
                    atomic_write(self.releases / f'ci-{release.tag}.json',
                                 json.dumps(completed, indent=2) + '\n')
                    atomic_remove(self.pending)
                except BaseException:
                    print('Deployment failed; restoring previous application images.', flush=True)
                    self.restore(record)
                    raise
                print(f'Deployed {release.image}; four services are healthy.', flush=True)


def interrupted(signum, _frame):
    signal.signal(signum, signal.SIG_IGN)
    raise RuntimeError(f'Deployment interrupted by signal {signum}')


def main():
    if os.geteuid() != 0:
        raise PermissionError('The restricted deployment receiver must run as root')
    command = os.environ.get('SSH_ORIGINAL_COMMAND', '')
    if command == 'check':
        print('CsAC restricted deployment receiver ready')
        return
    release = parse_command(command)
    config = json.loads(Path('/etc/csac/deploy.json').read_text())
    for signum in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(signum, interrupted)
    Deployer(config).deploy(release, sys.stdin.buffer)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(f'CsAC deployment error: {error}', file=sys.stderr)
        sys.exit(1)
