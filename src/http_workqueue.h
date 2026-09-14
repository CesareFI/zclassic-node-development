// Copyright (c) 2015 The Bitcoin Core developers
// Distributed under the MIT software license, see COPYING.

#ifndef BITCOIN_HTTP_WORKQUEUE_H
#define BITCOIN_HTTP_WORKQUEUE_H

#include "sync.h"

#include <boost/thread.hpp>
#include <cstddef>
#include <deque>

/** Simple work queue for distributing work over multiple threads.
 * Work items are simply callable objects.
 */
template <typename WorkItem>
class WorkQueue
{
private:
    /** Protects queued tasks and interruption state. */
    CWaitableCriticalSection cs;
    CConditionVariable cond;
    /* XXX in C++11 we can use std::unique_ptr here and avoid manual cleanup */
    std::deque<WorkItem*> queue;
    bool running;
    size_t maxDepth;
    boost::thread_group workers;

public:
    WorkQueue(size_t maxDepth) : running(true), maxDepth(maxDepth)
    {
    }
    /** Stop owned workers before destroying queued tasks. Callers that invoke
     *  Run directly must join their own threads before destroying the queue. */
    ~WorkQueue()
    {
        Interrupt();
        WaitExit();
        while (!queue.empty()) {
            delete queue.front();
            queue.pop_front();
        }
    }
    /** Start owned workers, running per-thread initialization before the loop.
     *  Start and WaitExit must be called by the lifecycle owner, sequentially. */
    template<typename ThreadInit>
    void Start(int count, ThreadInit initialize)
    {
        for (int i = 0; i < count; ++i)
            workers.create_thread([this, initialize] {
                initialize();
                Run();
            });
    }
    /** Enqueue a work item */
    bool Enqueue(WorkItem* item)
    {
        boost::unique_lock<boost::mutex> lock(cs);
        if (!running || queue.size() >= maxDepth) {
            return false;
        }
        queue.push_back(item);
        cond.notify_one();
        return true;
    }
    /** Thread function */
    void Run()
    {
        for (;;) {
            WorkItem* i = 0;
            {
                boost::unique_lock<boost::mutex> lock(cs);
                while (running && queue.empty())
                    cond.wait(lock);
                if (!running)
                    break;
                i = queue.front();
                queue.pop_front();
            }
            (*i)();
            delete i;
        }
    }
    /** Interrupt and exit loops */
    void Interrupt()
    {
        boost::unique_lock<boost::mutex> lock(cs);
        running = false;
        cond.notify_all();
    }
    /** Wait for worker threads to exit */
    void WaitExit()
    {
        // A launched worker may still be initializing and not yet inside Run.
        workers.join_all();
    }

    /** Return current depth of queue */
    size_t Depth()
    {
        boost::unique_lock<boost::mutex> lock(cs);
        return queue.size();
    }
};

#endif // BITCOIN_HTTP_WORKQUEUE_H
