# Go UBS Samples

| File | Category | Expected findings |
|------|----------|-------------------|
| `buggy/buggy_http.go` | HTTP client/server safety | missing timeouts, TLS defaults |
| `buggy/buggy_concurrency.go` | Concurrency handling | goroutines ignoring errors, WaitGroup misuse |
| `buggy/resource_lifecycle.go` | Resource lifecycle | context leaks, missing cancel() |
| `buggy/security_sql.go` | SQL/command injection + http.Client default | string concatenated SQL, exec.Command("sh -c"), no timeout |
| `buggy/performance.go` | Timers + defer in loops | `time.Tick` leaks, defer inside loop |
| Clean counterparts | Defensive examples | context.WithTimeout, prepared statements, ticker.Stop |

```bash
ubs --only=golang --fail-on-warning test-suite/golang/buggy
ubs --only=golang test-suite/golang/clean
```
