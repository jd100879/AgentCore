package buggy

import (
    "context"
    "sync"
)

func leakGoroutines(ctx context.Context, fns []func()) {
    var wg sync.WaitGroup
    for _, fn := range fns {
        wg.Add(1)
        go func(run func()) {
            run()
            // BUG: missing wg.Done()
        }(fn)
    }
    // BUG: never waits
    _ = ctx.Err()
}
