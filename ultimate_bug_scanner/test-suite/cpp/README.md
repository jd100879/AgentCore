# C++ UBS Samples

| File | Focus |
|------|-------|
| `buggy/buggy_raii.cpp` | Missing deletes, manual memory, `new`/`delete` mismatch |
| `buggy/buggy_concurrency.cpp` | Detached threads, shared data races |
| `buggy/resource_lifecycle.cpp` | FILE* leaks, missing `close()` |
| `buggy/security_overflow.cpp` | `strcpy`, `system()` usage, leaks |
| `buggy/math_precision.cpp` | Integer overflow + float equality |
| Clean files (`clean/*.cpp`) | RAII, smart pointers, bounded math |

Run C++ scans with:

```bash
ubs --only=cpp --fail-on-warning test-suite/cpp/buggy
ubs --only=cpp test-suite/cpp/clean
```
