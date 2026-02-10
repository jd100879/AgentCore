"""Clean example for function/scope patterns."""

import hashlib
import tempfile

def append_item(item, bucket=None):
    bucket = [] if bucket is None else bucket
    bucket.append(item)
    return bucket

try:
    raise ValueError('boom')
except ValueError as err:
    raise

print(hashlib.sha256(b'secret').hexdigest())
with tempfile.NamedTemporaryFile(delete=True) as tmp:
    tmp.write(b'ok')
