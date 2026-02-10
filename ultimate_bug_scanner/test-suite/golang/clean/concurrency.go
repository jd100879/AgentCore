package clean

import (
    "context"
    "sync"
)

func runGoroutines(ctx context.Context, fns []func()) {
    var wg sync.WaitGroup
    for _, fn := range fns {
        wg.Add(1)
        go func(run func()) {
            defer wg.Done()
            run()
        }(fn)
    }
    done := make(chan struct{})
    go func() {
        wg.Wait()
        close(done)
    }()

    select {
    case <-done:
    case <-ctx.Done():
    }
}
