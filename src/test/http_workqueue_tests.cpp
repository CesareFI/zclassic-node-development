// Copyright (c) 2026 The Zclassic developers
// Distributed under the MIT software license, see COPYING.

#include "http_workqueue.h"

#include <boost/test/unit_test.hpp>
#include <boost/thread.hpp>
#include <atomic>
#include <functional>
#include <memory>

namespace {
bool WaitFor(const std::atomic<bool>& flag)
{
    const auto deadline = boost::chrono::steady_clock::now() + boost::chrono::seconds(5);
    while (!flag.load() && boost::chrono::steady_clock::now() < deadline)
        boost::this_thread::sleep_for(boost::chrono::milliseconds(1));
    return flag.load();
}

struct Task {
    std::atomic<unsigned>& destroyed;
    std::function<void()> action;

    Task(std::atomic<unsigned>& destroyed, std::function<void()> action) :
        destroyed(destroyed), action(action) {}
    ~Task() { ++destroyed; }
    void operator()() { action(); }
};
} // namespace

BOOST_AUTO_TEST_SUITE(http_workqueue_tests)

BOOST_AUTO_TEST_CASE(interrupted_queue_rejects_new_work_without_taking_ownership)
{
    std::atomic<unsigned> destroyed(0);
    WorkQueue<Task> queue(1);
    queue.Interrupt();
    std::unique_ptr<Task> task(new Task(destroyed, [] {}));
    const bool accepted = queue.Enqueue(task.get());
    if (accepted)
        task.release();
    BOOST_CHECK(!accepted);
    BOOST_CHECK_EQUAL(queue.Depth(), 0);
    BOOST_CHECK_EQUAL(destroyed.load(), 0);
}

BOOST_AUTO_TEST_CASE(interrupt_during_task_finishes_worker_cleanly)
{
    std::atomic<unsigned> destroyed(0);
    std::atomic<bool> started(false);
    std::atomic<bool> finished(false);
    std::atomic<bool> exited(false);
    WorkQueue<Task> queue(1);
    std::unique_ptr<Task> task(new Task(destroyed, [&] {
        started = true;
        // Main interrupts while this ordinary callback is still running.
        boost::this_thread::sleep_for(boost::chrono::milliseconds(50));
        finished = true;
    }));
    BOOST_REQUIRE(queue.Enqueue(task.get()));
    task.release();
    boost::thread worker([&] {
        queue.Run();
        exited = true;
    });
    const bool began = WaitFor(started);
    queue.Interrupt();
    // Observe the loop exit before join can add thread-library synchronization.
    const bool exitedBeforeJoin = WaitFor(exited);
    worker.join();
    BOOST_CHECK(began);
    BOOST_CHECK(exitedBeforeJoin);
    BOOST_CHECK(finished.load());
    BOOST_CHECK_EQUAL(destroyed.load(), 1);
    BOOST_CHECK_EQUAL(queue.Depth(), 0);
}

BOOST_AUTO_TEST_CASE(queue_capacity_and_pending_task_cleanup)
{
    std::atomic<unsigned> destroyed(0);
    {
        WorkQueue<Task> queue(2);
        for (unsigned i = 0; i < 3; ++i) {
            std::unique_ptr<Task> task(new Task(destroyed, [] {}));
            const bool accepted = queue.Enqueue(task.get());
            if (accepted)
                task.release();
            BOOST_CHECK_EQUAL(accepted, i < 2);
        }
        BOOST_CHECK_EQUAL(queue.Depth(), 2);
        BOOST_CHECK_EQUAL(destroyed.load(), 1);
        queue.Interrupt();
    }
    BOOST_CHECK_EQUAL(destroyed.load(), 3);
}

BOOST_AUTO_TEST_SUITE_END()
