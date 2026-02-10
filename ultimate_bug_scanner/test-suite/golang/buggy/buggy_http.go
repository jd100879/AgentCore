package buggy

import (
    "context"
    "net/http"
    "os/exec"
    "time"
)

var httpClient = &http.Client{} // WARNING: no timeout

func fetch(url string) (*http.Response, error) {
    return httpClient.Get(url) // WARNING: no context, no error handling
}

func spawnLoop(urls []string) {
    for _, url := range urls {
        go func(u string) {
            fetch(u) // goroutine leak, no cancel
        }(url)
    }
}

func withCancel(ctx context.Context) context.Context {
    // WARNING: context.WithTimeout without cancel
    ctx, _ = context.WithTimeout(ctx, time.Second)
    return ctx
}

func shell(cmd string) error {
    // CRITICAL: exec with "sh -c"
    return exec.Command("sh", "-c", cmd).Run()
}
