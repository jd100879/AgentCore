#include <iostream>

int main() {
    long long money_cents = 1000; // $10.00
    long long price_cents = 375;  // $3.75
    long long change = money_cents - price_cents * 2;
    std::cout << change << " cents" << std::endl;
    return 0;
}
