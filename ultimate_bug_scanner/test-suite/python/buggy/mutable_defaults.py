"""Shows Python function/scope issues for UBS."""

import hashlib
import tempfile

def append_item(item, bucket=[]):  # mutable default
    bucket.append(item)
    return bucket

append_item('a')
append_item('b')

try:
    raise ValueError('boom')
except Exception:
    pass  # swallowed

# weak hash + insecure tempfile usage
print(hashlib.md5(b'secret').hexdigest())
tempfile.mktemp()
