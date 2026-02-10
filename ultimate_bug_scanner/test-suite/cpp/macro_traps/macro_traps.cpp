#include <cstdio>

#define min(a, b) ((a) < (b) ? (a) : (b))
#define max(a, b) ((a) > (b) ? (a) : (b))
#define DEBUG 1

int main() {
    int low = min(5, 2);
    int high = max(5, 2);
    printf("%d %d\n", low, high);
#if DEBUG
    printf("debug: %d %d\n", low, high);
#endif
    return 0;
}
