#include <future>
#include <iostream>

int risky() {
    return 42;
}

int main() {
    try {
        std::future<int> fut = std::async(std::launch::async, risky);
        std::cout << "result: " << fut.get() << std::endl;
    } catch (const std::exception &ex) {
        std::cerr << "async failure: " << ex.what() << std::endl;
    }
    return 0;
}
