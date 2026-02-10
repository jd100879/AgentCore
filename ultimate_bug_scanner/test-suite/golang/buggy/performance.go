package main

import (
    "log"
    "time"
)

func chattyTicker() {
    for _ = range time.Tick(time.Second) { // never stopped
        log.Println("tick")
    }
}

func leakingDefers() {
    for i := 0; i < 5; i++ {
        f, _ := openFile() // imaginary helper defined below
        defer f.Close() // defer in loop
    }
}

type fakeFile struct{}

func openFile() (*fakeFile, error) { return &fakeFile{}, nil }
func (f *fakeFile) Close() error { return nil }

func main() {
    go chattyTicker()
    leakingDefers()
}
