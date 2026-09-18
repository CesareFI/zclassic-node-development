// Isolate fixed-width field multiplication costs observed during Sprout IBD.
// This synthetic benchmark is not an end-to-end synchronization measurement.
#include <libsnark/common/default_types/r1cs_ppzksnark_pp.hpp>
#include <gmpxx.h>

#include <chrono>
#include <ctime>
#include <iostream>
#include <sstream>

int main(int argc, char** argv)
{
    unsigned int iterations = 5000000;
    if (argc > 2) return 1;
    if (argc == 2) {
        std::istringstream input(argv[1]);
        if (!(input >> iterations) || !input.eof() || iterations == 0 || iterations > 100000000)
            return 1;
    }
    typedef libsnark::default_r1cs_ppzksnark_pp Curve;
    typedef Curve::Fq_type Field;
    Curve::init_public_params();
    Field accumulator(7), factor(42);
    const auto start = std::chrono::steady_clock::now();
    const std::clock_t cpuStart = std::clock();
    for (unsigned int i = 0; i < iterations; ++i)
        accumulator *= factor;
    const double elapsed = std::chrono::duration<double>(
        std::chrono::steady_clock::now() - start).count();
    const double cpu = double(std::clock() - cpuStart) / CLOCKS_PER_SEC;

    // Independently compute 7 * 42^iterations mod p with GMP's integer API.
    mpz_class modulus, expected, actual;
    Field::field_char().to_mpz(modulus.get_mpz_t());
    mpz_set_ui(expected.get_mpz_t(), 42);
    mpz_powm_ui(expected.get_mpz_t(), expected.get_mpz_t(), iterations, modulus.get_mpz_t());
    expected = (expected * 7) % modulus;
    accumulator.as_bigint().to_mpz(actual.get_mpz_t());
    if (actual != expected) {
        std::cerr << "field multiplication result mismatch\n";
        return 2;
    }
    std::cout << "{\"iterations\":" << iterations
              << ",\"elapsed_seconds\":" << elapsed
              << ",\"cpu_seconds\":" << cpu
              << ",\"result\":\"" << actual.get_str(16) << "\"}\n";
}
