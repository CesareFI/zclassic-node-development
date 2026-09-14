// Copyright (c) 2026 The Zclassic developers
// Distributed under the MIT software license, see COPYING.

#include "importing.h"

#include <boost/test/unit_test.hpp>
#include <atomic>
#include <thread>

// A focused TSAN build uses the real guard and flag declarations without
// linking the daemon. Request cleanup is covered by block_download_tests.
#ifdef ZCLASSIC_IMPORT_TEST_STANDALONE
decltype(fImporting) fImporting(false);
void ResetBlockDownloadForImport() {}
#endif

BOOST_AUTO_TEST_SUITE(importing_tests)

BOOST_AUTO_TEST_CASE(import_scope_restores_flag_on_unwind)
{
    BOOST_REQUIRE(!fImporting);
    try {
        CImportingNow importing;
        BOOST_CHECK(fImporting);
        throw 1;
    } catch (int) {
    }
    BOOST_CHECK(!fImporting);
}

BOOST_AUTO_TEST_CASE(import_flag_can_be_observed_while_importer_runs)
{
    BOOST_REQUIRE(!fImporting);
    std::atomic<bool> readerReady(false), finished(false);
    unsigned active = 0, idle = 0;
    std::thread reader([&] {
        readerReady.store(true);
        while (!finished.load()) {
            if (fImporting) ++active;
            else ++idle;
        }
    });
    while (!readerReady.load()) std::this_thread::yield();
    for (unsigned round = 0; round < 10000; ++round) {
        CImportingNow importing;
        // Import work is not an empty scope. Yield also keeps the baseline
        // compiler from eliminating the unsynchronized intermediate flag.
        std::this_thread::yield();
    }
    finished.store(true);
    reader.join();
    BOOST_CHECK_GT(active + idle, 0U);
    BOOST_CHECK(!fImporting);
}

BOOST_AUTO_TEST_SUITE_END()
