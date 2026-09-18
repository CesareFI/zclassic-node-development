// Synthetic single-chunk workload used to isolate the Sprout verifier's
// OpenMP overhead. This is not an end-to-end IBD benchmark.
#include <libsnark/common/default_types/r1cs_ppzksnark_pp.hpp>
#include <libsnark/algebra/scalar_multiplication/multiexp.hpp>
#include <libsnark/common/profiling.hpp>

#include <chrono>
#include <ctime>
#include <iostream>
#include <sstream>
#include <vector>

#ifdef MULTICORE
#include <omp.h>
#endif

int main(int argc, char** argv)
{
    unsigned int iterations = 100;
    if (argc > 2) return 1;
    if (argc == 2) {
        std::istringstream input(argv[1]);
        if (!(input >> iterations) || !input.eof() || iterations == 0 || iterations > 100000)
            return 1;
    }
    typedef libsnark::default_r1cs_ppzksnark_pp Curve;
    typedef Curve::G1_type Group;
    typedef Curve::Fp_type Field;
    Curve::init_public_params();
    libsnark::inhibit_profiling_info = true;
    libsnark::inhibit_profiling_counters = true;
    std::vector<Group> points;
    std::vector<Field> scalars;
    Group expected = Group::zero();
    for (unsigned int i = 0; i < 9; ++i) {
        points.push_back(Field(i + 1) * Group::one());
        scalars.push_back(-Field(17 * i + 5));
        expected = expected + scalars.back() * points.back();
    }
    const auto start = std::chrono::steady_clock::now();
    const std::clock_t cpuStart = std::clock();
    for (unsigned int i = 0; i < iterations; ++i) {
        const auto actual = libsnark::multi_exp<Group, Field>(
            points.begin(), points.end(), scalars.begin(), scalars.end(), 1, true);
        if (actual != expected) {
            std::cerr << "multi-exponentiation result mismatch\n";
            return 2;
        }
    }
    const double elapsed = std::chrono::duration<double>(
        std::chrono::steady_clock::now() - start).count();
    const double cpu = double(std::clock() - cpuStart) / CLOCKS_PER_SEC;
    int threads = 1;
#ifdef MULTICORE
    threads = omp_get_max_threads();
#endif
    std::cout << "{\"iterations\":" << iterations
              << ",\"omp_max_threads\":" << threads
              << ",\"elapsed_seconds\":" << elapsed
              << ",\"cpu_seconds\":" << cpu << "}\n";
}
