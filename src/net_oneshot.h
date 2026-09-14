// Copyright (c) 2026 The Zclassic developers
// Distributed under the MIT software license, see COPYING.

#ifndef ZCLASSIC_NET_ONESHOT_H
#define ZCLASSIC_NET_ONESHOT_H

#include "sync.h"

#include <deque>
#include <string>

/** Pending seed connections, sharing the ordinary outbound permit budget. */
class COneShotQueue
{
private:
    CCriticalSection mutex;
    std::deque<std::string> destinations;

public:
    void Add(const std::string& destination)
    {
        LOCK(mutex);
        destinations.push_back(destination);
    }

    /** Try one connection outside the queue lock. The connector may transfer
     *  the grant to its connection; a failed attempt is queued for retry. */
    template<typename Connector>
    void Process(CSemaphore& outboundSlots, Connector&& connect)
    {
        // Keep the destination queued until a connection can actually be tried.
        CSemaphoreGrant grant(outboundSlots, true);
        if (!grant)
            return;
        std::string destination;
        {
            LOCK(mutex);
            if (destinations.empty())
                return;
            destination = destinations.front();
            destinations.pop_front();
        }
        if (!connect(destination, grant))
            Add(destination);
    }
};

#endif // ZCLASSIC_NET_ONESHOT_H
