// Copyright (c) 2026 The Zclassic developers
// Distributed under the MIT software license, see COPYING.

#include "txdb.h"

#include <boost/test/unit_test.hpp>
#include <array>
#include <limits>

BOOST_AUTO_TEST_SUITE(init_tests)

BOOST_AUTO_TEST_CASE(dbcache_preserves_valid_budgets)
{
    const int64_t mebibyte = 1024 * 1024;
    for (int64_t value : std::array<int64_t, 4>{{nMinDbCache, nDefaultDbCache, 1024, nMaxDbCache}})
        BOOST_CHECK_EQUAL(GetDbCacheSizeBytes(value), value * mebibyte);
}

BOOST_AUTO_TEST_CASE(dbcache_clamps_large_budgets_before_conversion)
{
    const int64_t maximum = nMaxDbCache * 1024 * 1024;
    for (int64_t value : std::array<int64_t, 3>{{nMaxDbCache + 1, int64_t(1) << 43,
                                              std::numeric_limits<int64_t>::max()}})
        BOOST_CHECK_EQUAL(GetDbCacheSizeBytes(value), maximum);
}

BOOST_AUTO_TEST_CASE(dbcache_clamps_small_budgets_before_conversion)
{
    const int64_t minimum = nMinDbCache * 1024 * 1024;
    for (int64_t value : std::array<int64_t, 4>{{std::numeric_limits<int64_t>::min(),
                                              -1, 0, nMinDbCache - 1}})
        BOOST_CHECK_EQUAL(GetDbCacheSizeBytes(value), minimum);
}

BOOST_AUTO_TEST_SUITE_END()
