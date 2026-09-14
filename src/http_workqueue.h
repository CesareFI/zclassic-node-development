// Copyright (c) 2015 The Bitcoin Core developers
// Distributed under the MIT software license, see COPYING.

#ifndef BITCOIN_HTTP_WORKQUEUE_H
#define BITCOIN_HTTP_WORKQUEUE_H

#include "sync.h"

#include <cstddef>
#include <deque>

/** Simple work queue for distributing work over multiple threads.
 * Work items are simply callable objects.
 */
template <typename WorkItem>
class WorkQueue
{
private:
    /** Mutex protects entire object */
    CWaitableCriticalSection cs;
    CConditionVariable cond;
    /* XXX in C++11 we can use std::unique_ptr here and avoid manual cleanup */
    std::deque<WorkItem*> queue;
    bool running;
    size_t maxDepth;
    int numThreads;

    /** RAII object to keep track of number of running worker threads */
    class ThreadCounter
    {
    public:
        WorkQueue &wq;
        ThreadCounter(WorkQueue &w): wq(w)
        {
            boost::lock_guard<boost::mutex> lock(wq.cs);
            wq.numThreads += 1;
        }
        ~ThreadCounter()
        {
            boost::lock_guard<boost::mutex> lock(wq.cs);
            wq.numThreads -= 1;
            wq.cond.notify_all();
        }
    };

public:
    WorkQueue(size_t maxDepth) : running(true),
                                 maxDepth(maxDepth),
                                 numThreads(0)
    {
    }
    /*( Precondition: worker threads have all stopped
     * (call WaitExit)
     */
    ~WorkQueue()
    {
        while (!queue.empty()) {
            delete queue.front();
            queue.pop_front();
        }
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
        ThreadCounter count(*this);
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
        boost::unique_lock<boost::mutex> lock(cs);
        while (numThreads > 0)
            cond.wait(lock);
    }

    /** Return current depth of queue */
    size_t Depth()
    {
        boost::unique_lock<boost::mutex> lock(cs);
        return queue.size();
    }
};

#endif // BITCOIN_HTTP_WORKQUEUE_H
