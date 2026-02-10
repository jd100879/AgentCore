# Java UBS Samples

| File | Focus |
|------|-------|
| `buggy/BuggyService.java` | Blocking I/O, TLS issues |
| `buggy/BuggyConcurrency.java` | ExecutorService leaks, missing shutdown |
| `buggy/ResourceLifecycle.java` | Streams not closed |
| `buggy/BuggySecurity.java` | SQL/command injection |
| Clean files | try-with-resources, prepared statements, ProcessBuilder argv |

```bash
ubs --only=java --fail-on-warning test-suite/java/buggy
ubs --only=java test-suite/java/clean
```
