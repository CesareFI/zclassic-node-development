// Copyright (c) 2012-2013 The Bitcoin Core developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include "random.h"
#include "scheduler.h"

#include "test/test_bitcoin.h"

#include <array>
#include <atomic>
#include <boost/bind/bind.hpp>
#include <boost/random/mersenne_twister.hpp>
#include <boost/random/uniform_int_distribution.hpp>
#include <boost/thread.hpp>
#include <boost/test/unit_test.hpp>

BOOST_AUTO_TEST_SUITE(scheduler_tests)

static void microTask(CScheduler& s, boost::mutex& mutex, int& counter, int delta, boost::chrono::system_clock::time_point rescheduleTime)
{
    {
        boost::unique_lock<boost::mutex> lock(mutex);
        counter += delta;
    }
    boost::chrono::system_clock::time_point noTime = boost::chrono::system_clock::time_point::min();
    if (rescheduleTime != noTime) {
        CScheduler::Function f = boost::bind(&microTask, boost::ref(s), boost::ref(mutex), boost::ref(counter), -delta + 1, noTime);
        s.schedule(f, rescheduleTime);
    }
}

static void MicroSleep(uint64_t n)
{
    boost::this_thread::sleep_for(boost::chrono::microseconds(n));
}

BOOST_AUTO_TEST_CASE(manythreads)
{
    seed_insecure_rand(false);

    // Stress test: hundreds of microsecond-scheduled tasks,
    // serviced by 10 threads.
    //
    // So... ten shared counters, which if all the tasks execute
    // properly will sum to the number of tasks done.
    // Each task adds or subtracts from one of the counters a
    // random amount, and then schedules another task 0-1000
    // microseconds in the future to subtract or add from
    // the counter -random_amount+1, so in the end the shared
    // counters should sum to the number of initial tasks performed.
    CScheduler microTasks;

    boost::mutex counterMutex[10];
    int counter[10] = { 0 };
    boost::random::mt19937 rng(insecure_rand());
    boost::random::uniform_int_distribution<> zeroToNine(0, 9);
    boost::random::uniform_int_distribution<> randomMsec(-11, 1000);
    boost::random::uniform_int_distribution<> randomDelta(-1000, 1000);

    boost::chrono::system_clock::time_point start = boost::chrono::system_clock::now();
    boost::chrono::system_clock::time_point now = start;
    boost::chrono::system_clock::time_point first, last;
    size_t nTasks = microTasks.getQueueInfo(first, last);
    BOOST_CHECK(nTasks == 0);

    for (int i = 0; i < 100; i++) {
        boost::chrono::system_clock::time_point t = now + boost::chrono::microseconds(randomMsec(rng));
        boost::chrono::system_clock::time_point tReschedule = now + boost::chrono::microseconds(500 + randomMsec(rng));
        int whichCounter = zeroToNine(rng);
        CScheduler::Function f = boost::bind(&microTask, boost::ref(microTasks),
                                             boost::ref(counterMutex[whichCounter]), boost::ref(counter[whichCounter]),
                                             randomDelta(rng), tReschedule);
        microTasks.schedule(f, t);
    }
    nTasks = microTasks.getQueueInfo(first, last);
    BOOST_CHECK(nTasks == 100);
    BOOST_CHECK(first < last);
    BOOST_CHECK(last > now);

    // As soon as these are created they will start running and servicing the queue
    boost::thread_group microThreads;
    for (int i = 0; i < 5; i++)
        microThreads.create_thread(boost::bind(&CScheduler::serviceQueue, &microTasks));

    MicroSleep(600);
    now = boost::chrono::system_clock::now();

    // More threads and more tasks:
    for (int i = 0; i < 5; i++)
        microThreads.create_thread(boost::bind(&CScheduler::serviceQueue, &microTasks));
    for (int i = 0; i < 100; i++) {
        boost::chrono::system_clock::time_point t = now + boost::chrono::microseconds(randomMsec(rng));
        boost::chrono::system_clock::time_point tReschedule = now + boost::chrono::microseconds(500 + randomMsec(rng));
        int whichCounter = zeroToNine(rng);
        CScheduler::Function f = boost::bind(&microTask, boost::ref(microTasks),
                                             boost::ref(counterMutex[whichCounter]), boost::ref(counter[whichCounter]),
                                             randomDelta(rng), tReschedule);
        microTasks.schedule(f, t);
    }

    // Drain the task queue then exit threads
    microTasks.stop(true);
    microThreads.join_all(); // ... wait until all the threads are done

    int counterSum = 0;
    for (int i = 0; i < 10; i++) {
        BOOST_CHECK(counter[i] != 0);
        counterSum += counter[i];
    }
    BOOST_CHECK_EQUAL(counterSum, 200);
}

BOOST_AUTO_TEST_CASE(shared_deadline_is_safe_with_multiple_workers)
{
    CScheduler scheduler;
    std::array<std::atomic<unsigned>, 64> executions;
    for (auto& count : executions)
        count = 0;
    std::atomic<bool> ranEarly(false);
    const auto deadline = boost::chrono::system_clock::now() + boost::chrono::milliseconds(100);
    for (size_t i = 0; i < executions.size(); ++i) {
        scheduler.schedule([&, i] {
            if (boost::chrono::system_clock::now() < deadline)
                ranEarly = true;
            ++executions[i];
        }, deadline);
    }

    // All workers can wait on the same first entry. Erasing it must not
    // invalidate the deadline still used by another worker's timed wait.
    boost::thread_group workers;
    for (unsigned i = 0; i < 8; ++i)
        workers.create_thread([&] { scheduler.serviceQueue(); });
    scheduler.stop(true);
    workers.join_all();

    for (const auto& count : executions)
        BOOST_CHECK_EQUAL(count.load(), 1);
    BOOST_CHECK(!ranEarly.load());
    boost::chrono::system_clock::time_point first, last;
    BOOST_CHECK_EQUAL(scheduler.getQueueInfo(first, last), 0);
}

BOOST_AUTO_TEST_CASE(earlier_task_can_stop_workers_waiting_on_later_deadline)
{
    CScheduler scheduler;
    std::atomic<unsigned> laterExecutions(0);
    std::atomic<unsigned> earlierExecutions(0);
    scheduler.schedule([&] { ++laterExecutions; },
                       boost::chrono::system_clock::now() + boost::chrono::hours(1));
    boost::thread_group workers;
    for (unsigned i = 0; i < 4; ++i)
        workers.create_thread([&] { scheduler.serviceQueue(); });

    scheduler.schedule([&] {
        ++earlierExecutions;
        scheduler.stop();
    }, boost::chrono::system_clock::now());
    workers.join_all();

    BOOST_CHECK_EQUAL(earlierExecutions.load(), 1);
    BOOST_CHECK_EQUAL(laterExecutions.load(), 0);
    boost::chrono::system_clock::time_point first, last;
    BOOST_CHECK_EQUAL(scheduler.getQueueInfo(first, last), 1);
}

BOOST_AUTO_TEST_SUITE_END()
