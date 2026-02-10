# Ruby UBS Samples

| File | Category |
|------|----------|
| `buggy/security_issues.rb` | eval, unsafe YAML |
| `buggy/resource_lifecycle.rb` | File/thread cleanup |
| `buggy/buggy_scripts.rb` | Shelling out, missing rescue |
| `buggy/performance.rb` | Thread leaks, backticks |
| Clean files | Managed threads, Open3 argv |

```bash
ubs --only=ruby --fail-on-warning test-suite/ruby/buggy
ubs --only=ruby test-suite/ruby/clean
```
