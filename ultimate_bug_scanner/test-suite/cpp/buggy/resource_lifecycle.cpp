#include <thread>
#include <chrono>
#include <cstdlib>

void worker() {
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
}

void leak_threads_and_memory() {
    std::thread background(worker);
    (void)background; // never joined or detached

    void* buf = malloc(256);
    (void)buf; // never freed
}
