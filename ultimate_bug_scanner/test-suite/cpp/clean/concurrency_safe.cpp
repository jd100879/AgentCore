#include <thread>
#include <vector>
#include <array>
#include <iostream>

void bounded_thread_pool() {
    std::vector<std::thread> workers;
    for (int i = 0; i < 2; ++i) {
        workers.emplace_back([] { std::this_thread::sleep_for(std::chrono::milliseconds(10)); });
    }
    for (auto &t : workers) {
        t.join();
    }
}

struct Buffer {
    std::array<char, 32> data{};
};

int main() {
    bounded_thread_pool();
    Buffer b;
    std::snprintf(b.data.data(), b.data.size(), "%s", "hello");
    std::cout << b.data.data() << std::endl;
    return 0;
}
