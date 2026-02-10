#include <thread>
#include <vector>
#include <cstring>
#include <iostream>

void leak_thread() {
    std::thread([] {
        while (true) { /* spin */ }
    }).detach(); // BUG: runaway detach
}

struct Buffer {
    Buffer() { data = new char[16]; }
    ~Buffer() { /* BUG: missing delete[] */ }
    char* data;
};

int main() {
    leak_thread();
    Buffer b;
    std::strcpy(b.data, "super long string that overflows the buffer");
    std::cout << b.data << std::endl;
    return 0;
}
