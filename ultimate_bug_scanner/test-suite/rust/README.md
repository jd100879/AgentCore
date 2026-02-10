# Rust UBS Samples

| File | Category |
|------|----------|
| `buggy/buggy_unwrap.rs` | Panic-prone unwrap chains |
| `buggy/async_block.rs` | Spawned tasks never awaited |
| `buggy/resource_lifecycle.rs` | Missing JoinHandle cleanup |
| `buggy/security_injection.rs` | Command injection + exposed secrets |
| `buggy/math_precision.rs` | Float equality for money |
| Clean files (`clean/*.rs`) | `Result` handling, JoinHandle waiting, integer cents |

```bash
ubs --only=rust --fail-on-warning test-suite/rust/buggy
ubs --only=rust test-suite/rust/clean
```
