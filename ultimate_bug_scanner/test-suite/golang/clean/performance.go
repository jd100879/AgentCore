package main

import (
    "log"
    "time"
)

func boundedTicker(stop <-chan struct{}) {
    ticker := time.NewTicker(time.Second)
    defer ticker.Stop()
    for {
        select {
        case <-ticker.C:
            log.Println("tick")
        case <-stop:
            return
        }
    }
}

type fakeFile struct{}

func openFile() (*fakeFile, error) { return &fakeFile{}, nil }
func (f *fakeFile) Close() error { return nil }

func cleanedLoop() {
    for i := 0; i < 5; i++ {
        f, _ := openFile()
        func(file *fakeFile) {
            defer file.Close()
            log.Println("processing", i)
        }(f)
    }
}

func main() {
    stop := make(chan struct{})
    go boundedTicker(stop)
    time.Sleep(2 * time.Second)
    close(stop)
    cleanedLoop()
}
