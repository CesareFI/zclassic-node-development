// Copyright (c) 2026 The Zclassic developers
// Distributed under the MIT software license, see COPYING.

#include "net_oneshot.h"

#include <boost/test/unit_test.hpp>
#include <vector>

BOOST_AUTO_TEST_SUITE(net_oneshot_tests)

BOOST_AUTO_TEST_CASE(full_outbound_pool_preserves_pending_destinations)
{
    COneShotQueue queue;
    CSemaphore slots(1);
    CSemaphoreGrant occupied(slots, true);
    BOOST_REQUIRE(static_cast<bool>(occupied));
    queue.Add("seed-a.invalid");
    queue.Add("seed-b.invalid");
    std::vector<std::string> attempts;
    auto connect = [&](const std::string& destination, CSemaphoreGrant& grant) {
        BOOST_CHECK(static_cast<bool>(grant));
        attempts.push_back(destination);
        return true;
    };
    for (unsigned i = 0; i < 8; ++i)
        queue.Process(slots, connect);
    BOOST_CHECK(attempts.empty());

    occupied.Release();
    queue.Process(slots, connect);
    queue.Process(slots, connect);
    queue.Process(slots, connect);
    const std::vector<std::string> expected{"seed-a.invalid", "seed-b.invalid"};
    BOOST_CHECK_EQUAL_COLLECTIONS(attempts.begin(), attempts.end(), expected.begin(), expected.end());
    BOOST_CHECK(occupied.TryAcquire());
}

BOOST_AUTO_TEST_CASE(failed_attempt_retries_after_connected_peer_releases_permit)
{
    COneShotQueue queue;
    CSemaphore slots(1);
    CSemaphoreGrant connected;
    queue.Add("seed-a.invalid");
    queue.Add("seed-b.invalid");
    std::vector<std::string> attempts;
    auto connect = [&](const std::string& destination, CSemaphoreGrant& grant) {
        attempts.push_back(destination);
        if (attempts.size() == 1)
            return false;
        grant.MoveTo(connected);
        return true;
    };
    queue.Process(slots, connect); // A fails and is queued after B.
    BOOST_CHECK(!connected);
    queue.Process(slots, connect); // B retains the sole outbound permit.
    BOOST_REQUIRE(static_cast<bool>(connected));
    queue.Process(slots, connect); // A must survive while B is connected.
    BOOST_CHECK_EQUAL(attempts.size(), 2);
    connected.Release();
    queue.Process(slots, connect);
    const std::vector<std::string> expected{"seed-a.invalid", "seed-b.invalid", "seed-a.invalid"};
    BOOST_CHECK_EQUAL_COLLECTIONS(attempts.begin(), attempts.end(), expected.begin(), expected.end());
    BOOST_CHECK(static_cast<bool>(connected));
    connected.Release();
    queue.Process(slots, connect);
    BOOST_CHECK_EQUAL(attempts.size(), 3);
    CSemaphoreGrant available(slots, true);
    BOOST_CHECK(static_cast<bool>(available));
}

BOOST_AUTO_TEST_CASE(duplicate_seed_does_not_delay_distinct_source_retry)
{
    COneShotQueue queue;
    CSemaphore slots(1);
    queue.Add("stalled-seed.invalid");
    queue.Add("stalled-seed.invalid");
    queue.Add("healthy-seed.invalid");
    std::vector<std::string> attempts;
    auto connect = [&](const std::string& destination, CSemaphoreGrant&) {
        attempts.push_back(destination);
        return destination == "healthy-seed.invalid";
    };

    queue.Process(slots, connect);
    queue.Process(slots, connect);
    const std::vector<std::string> expected{
        "stalled-seed.invalid", "healthy-seed.invalid"};
    BOOST_CHECK_EQUAL_COLLECTIONS(attempts.begin(), attempts.end(),
                                  expected.begin(), expected.end());
}

BOOST_AUTO_TEST_CASE(inflight_seed_deduplication_survives_concurrent_add)
{
    COneShotQueue queue;
    CSemaphore slots(1);
    queue.Add("seed.invalid");
    unsigned attempts = 0;
    auto connect = [&](const std::string& destination, CSemaphoreGrant&) {
        ++attempts;
        // Process() invokes connectors without the queue lock, matching an
        // AddOneShot call arriving while name resolution/connect is active.
        queue.Add(destination);
        return true;
    };

    queue.Process(slots, connect);
    queue.Process(slots, connect);
    BOOST_CHECK_EQUAL(attempts, 1U);
}

BOOST_AUTO_TEST_SUITE_END()
