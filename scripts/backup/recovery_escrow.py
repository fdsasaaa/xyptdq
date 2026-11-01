"""Verify an owner's downloaded recovery file without publishing its contents."""
import hashlib
import hmac
import json
import re


def verify_export(grant, payload, owner_sha256, repository, password):
    if (grant.get('purpose') != 'export_recovery' or not grant.get('used')
            or not grant.get('exported_at')):
        raise ValueError('a completed owner-only recovery export is required')
    owner_sha256 = owner_sha256.lower()
    if not re.fullmatch(r'[0-9a-f]{64}', owner_sha256):
        raise ValueError('invalid owner file checksum')
    actual = hashlib.sha256(payload).hexdigest()
    if not hmac.compare_digest(actual, owner_sha256):
        raise ValueError('owner file checksum does not match the exported file')
    if (not hmac.compare_digest(actual, str(grant.get('recovery_file_sha256', '')))
            or len(payload) != grant.get('recovery_file_bytes')):
        raise ValueError('private export receipt is inconsistent')
    envelope = json.loads(payload.decode('ascii'))
    if (envelope.get('schema_version') != 1 or envelope.get('project') != 'xyptdq'
            or envelope.get('repository') != repository
            or not isinstance(envelope.get('repository_password'), str)
            or not hmac.compare_digest(envelope['repository_password'], password)):
        raise ValueError('recovery file does not unlock the current repository')
    return {'schema_version': 1, 'grant_id': grant['grant_id'],
            'owner_file_sha256': actual, 'recovery_file_bytes': len(payload),
            'owner_file_sha256_verified': True, 'current_repository_key_verified': True}
