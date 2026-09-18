// Compare full parameter-file hashing; neither mode skips any input bytes.
#include "crypto/sha256stream.h"
#include "sha256.h"

#include <chrono>
#include <ctime>
#include <fstream>
#include <iostream>
#include <string>

int main(int argc, char** argv)
{
    if (argc != 3 || (std::string(argv[1]) != "legacy" && std::string(argv[1]) != "candidate")) {
        std::cerr << "usage: benchmark-parameter-hash legacy|candidate FILE\n";
        return 1;
    }
    std::ifstream input(argv[2], std::ios::binary);
    if (!input.is_open()) return 2;
    const auto start = std::chrono::steady_clock::now();
    const std::clock_t cpuStart = std::clock();
    std::string hash;
    if (std::string(argv[1]) == "legacy") {
        SHA256 context;
        std::vector<char> buffer(256 * 1024);
        while (input) {
            input.read(buffer.data(), buffer.size());
            if (input.gcount() > 0) context.update(buffer.data(), static_cast<size_t>(input.gcount()));
        }
        if (!input.eof() || input.bad()) return 3;
        hash = context.hash();
    } else {
        std::array<unsigned char, 32> digest;
        if (!SHA256Stream(input, digest)) return 3;
        static const char hex[] = "0123456789abcdef";
        for (unsigned char byte : digest) {
            hash += hex[byte >> 4];
            hash += hex[byte & 15];
        }
    }
    const double elapsed = std::chrono::duration<double>(
        std::chrono::steady_clock::now() - start).count();
    const double cpu = double(std::clock() - cpuStart) / CLOCKS_PER_SEC;
    std::cout << "{\"mode\":\"" << argv[1] << "\",\"sha256\":\"" << hash
              << "\",\"elapsed_seconds\":" << elapsed << ",\"cpu_seconds\":" << cpu << "}\n";
}
