#include <array>
#include <cstdio>
#include <cstring>
#include <iostream>
#include <memory>
#include <string>

void safeCopy(const std::string &input) {
    std::array<char, 8> buf{};
    std::snprintf(buf.data(), buf.size(), "%s", input.c_str());
    std::cout << buf.data() << std::endl;
}

int main() {
    safeCopy("hello");
    auto data = std::make_unique<char[]>(64);
    std::snprintf(data.get(), 64, "%s", "secret");
    std::cout << data.get() << std::endl;
    return 0;
}
