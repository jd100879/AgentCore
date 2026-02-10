package main

import (
    "fmt"
    "net/http"
)

func fireAndReport(urls []string) {
    for _, url := range urls {
        go func(u string) {
            resp, err := http.Get(u)
            if err != nil {
                fmt.Println("failed", u, err)
                return
            }
            defer resp.Body.Close()
            fmt.Println("status", resp.Status)
        }(url)
    }
}

func main() {
    fireAndReport([]string{"https://example.com"})
}
