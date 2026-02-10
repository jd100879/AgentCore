#include <cstdio>
#include <cstring>
#include <iostream>
#include <mutex>

char *copy_user_input(const char *input) {
    // CRITICAL: manual new/delete with strcpy -> buffer overflow risk
    char *buf = new char[16];
    std::strcpy(buf, input);
    return buf;  // leaked when caller forgets delete
}

class BadDestructor {
public:
    ~BadDestructor() noexcept(false) {
        // CRITICAL: throwing in destructor triggers std::terminate
        throw std::runtime_error("boom");
    }
};

void run() {
    BadDestructor d;
    auto raw = copy_user_input("unbounded user input that overflows the buffer");
    std::printf("%s\n", raw);
    delete raw;  // mismatched delete (should be delete[])
}

int main() {
    run();
    // manual mutex lock/unlock w/out RAII
    std::mutex m;
    m.lock();
    if (std::rand() % 2) {
        return 0;  // lock never unlocked
    }
    m.unlock();
    return 0;
}
