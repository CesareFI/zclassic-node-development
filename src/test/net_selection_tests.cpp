// Copyright (c) 2026 The Zclassic developers
// Distributed under the MIT software license, see COPYING.

#include "net_selection.h"
#include "test/test_bitcoin.h"

#include <boost/test/unit_test.hpp>
#include <limits>

namespace {
constexpr int PORT = 8033;
constexpr int64_t NOW = 10000;

// Numeric address values only; these fixtures perform no DNS or connections.
CAddrInfo Candidate(const char* host, int port = PORT)
{
    return CAddrInfo(CAddress(CService(host, port, false), NODE_NETWORK), CNetAddr());
}

bool NeverReject(const CAddrInfo&) { return false; }
}

BOOST_FIXTURE_TEST_SUITE(net_selection_tests, BasicTestingSetup)

BOOST_AUTO_TEST_CASE(connected_group_does_not_hide_a_different_group)
{
    const auto blocked = Candidate("8.1.1.1");
    const auto healthy = Candidate("9.1.1.1");
    BOOST_REQUIRE(blocked.GetGroup() != healthy.GetGroup());
    unsigned calls = 0;
    auto select = [&] { return ++calls == 1 ? blocked : healthy; };
    auto excluded = [&](const CAddrInfo& address) { return address.GetGroup() == blocked.GetGroup(); };
    const auto chosen = SelectOutboundAddress(select, excluded, NeverReject, NOW, PORT);
    BOOST_CHECK_EQUAL(chosen.ToString(), healthy.ToString());
    BOOST_CHECK_EQUAL(calls, 2);
}

BOOST_AUTO_TEST_CASE(local_candidate_does_not_end_selection)
{
    const auto local = Candidate("8.1.1.1");
    const auto healthy = Candidate("9.1.1.1");
    unsigned calls = 0;
    auto select = [&] { return ++calls == 1 ? local : healthy; };
    auto excluded = [&](const CAddrInfo& address) { return address.ToString() == local.ToString(); };
    const auto chosen = SelectOutboundAddress(select, excluded, NeverReject, NOW, PORT);
    BOOST_CHECK_EQUAL(chosen.ToString(), healthy.ToString());
    BOOST_CHECK_EQUAL(calls, 2);
}

BOOST_AUTO_TEST_CASE(excluded_and_disabled_candidates_have_a_fixed_search_budget)
{
    const auto address = Candidate("8.1.1.1");
    for (bool excluded : {false, true}) {
        unsigned calls = 0;
        auto select = [&] { ++calls; return address; };
        const auto chosen = SelectOutboundAddress(select,
            [=](const CAddrInfo&) { return excluded; },
            [=](const CAddrInfo&) { return !excluded; }, NOW, PORT);
        BOOST_CHECK(!chosen.IsValid());
        BOOST_CHECK_EQUAL(calls, 100);
    }
}

BOOST_AUTO_TEST_CASE(last_candidate_within_budget_remains_eligible)
{
    const auto blocked = Candidate("8.1.1.1");
    const auto healthy = Candidate("9.1.1.1");
    unsigned calls = 0;
    auto select = [&] { return ++calls < 100 ? blocked : healthy; };
    auto excluded = [&](const CAddrInfo& address) { return address.GetGroup() == blocked.GetGroup(); };
    const auto chosen = SelectOutboundAddress(select, excluded, NeverReject, NOW, PORT);
    BOOST_CHECK_EQUAL(chosen.ToString(), healthy.ToString());
    BOOST_CHECK_EQUAL(calls, 100);
}

BOOST_AUTO_TEST_CASE(empty_address_pool_stops_after_one_lookup)
{
    unsigned calls = 0;
    auto select = [&] { ++calls; return CAddrInfo(); };
    auto unused = [](const CAddrInfo&) { BOOST_ERROR("policy called for empty pool"); return false; };
    BOOST_CHECK(!SelectOutboundAddress(select, unused, unused, NOW, PORT).IsValid());
    BOOST_CHECK_EQUAL(calls, 1);
}

BOOST_AUTO_TEST_CASE(retry_delay_and_port_preferences_handle_clock_boundaries)
{
    struct Case { int64_t now, last; int port; unsigned calls; };
    const int64_t min = std::numeric_limits<int64_t>::min();
    const int64_t max = std::numeric_limits<int64_t>::max();
    const Case cases[] = {{NOW, 0, PORT, 1}, {NOW, NOW, PORT, 30},
        {NOW, NOW - 599, PORT, 30}, {NOW, NOW - 600, PORT, 1},
        {NOW, NOW + 1, PORT, 30}, {NOW, 0, PORT + 1, 50},
        {max, min, PORT, 1}, {min, max, PORT, 30},
        {min, min, PORT, 30}, {max, max - 600, PORT, 1}};
    for (const auto& test : cases) {
        BOOST_TEST_CONTEXT("now=" << test.now << " last=" << test.last << " port=" << test.port) {
            auto address = Candidate("9.1.1.1", test.port);
            address.nLastTry = test.last;
            unsigned calls = 0;
            auto select = [&] { ++calls; return address; };
            const auto chosen = SelectOutboundAddress(select, NeverReject, NeverReject, test.now, PORT);
            BOOST_CHECK_EQUAL(chosen.ToString(), address.ToString());
            BOOST_CHECK_EQUAL(calls, test.calls);
        }
    }
}

BOOST_AUTO_TEST_SUITE_END()
