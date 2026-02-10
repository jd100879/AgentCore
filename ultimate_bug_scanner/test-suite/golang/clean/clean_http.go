package clean

import (
    "context"
    "net/http"
    "time"
)

var httpClient = &http.Client{
    Timeout: 5 * time.Second,
}

func fetch(ctx context.Context, url string) (*http.Response, error) {
    req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
    if err != nil {
        return nil, err
    }
    return httpClient.Do(req)
}

func spawn(ctx context.Context, urls []string) ([]*http.Response, error) {
    ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
    defer cancel()

    responses := make([]*http.Response, 0, len(urls))
    for _, url := range urls {
        resp, err := fetch(ctx, url)
        if err != nil {
            return nil, err
        }
        responses = append(responses, resp)
    }
    return responses, nil
}
