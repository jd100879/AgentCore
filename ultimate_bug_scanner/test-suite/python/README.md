# Python UBS Samples

| File | Category | What UBS should flag |
|------|----------|----------------------|
| `buggy/buggy_async_security.py` | Async/await pitfalls + insecure requests | unguarded awaits, missing try/except, `verify=False` |
| `buggy/resource_lifecycle.py` | File/task cleanup | missing `close()`/`cancel()` |
| `buggy/security_injection.py` | Code & command injection, yaml.load, eval | eval/exec, yaml.load without Loader, shell=True |
| `buggy/mutable_defaults.py` | Function scope issues | mutable defaults, swallowed exceptions, weak hash |
| `clean/*.py` mirrors | Defensive patterns | safe YAML, parameterized SQL, integer cents |

Run:

```bash
ubs --only=python --fail-on-warning test-suite/python/buggy
ubs --only=python test-suite/python/clean
```
