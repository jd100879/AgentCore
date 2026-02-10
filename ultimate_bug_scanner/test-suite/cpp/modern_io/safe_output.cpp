#include <format>
#include <iostream>
#include <string>

int main() {
    std::string name = "ubs";
    auto msg = std::format("hello {}", name);
    std::cout << msg << "\n";
    return 0;
}
