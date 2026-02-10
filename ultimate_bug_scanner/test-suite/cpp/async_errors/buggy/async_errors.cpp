#include <future>
#include <iostream>

int risky() {
    throw std::runtime_error("boom");
}

int main() {
    std::future<int> fut = std::async(std::launch::async, risky);
    if (fut.valid()) {
        std::cout << "task scheduled" << std::endl;
    }
    return 0;
}
