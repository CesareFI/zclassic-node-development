// Copyright (c) 2026 The Zclassic developers
// Distributed under the MIT software license, see COPYING.

#ifndef ZCLASSIC_NET_ONESHOT_H
#define ZCLASSIC_NET_ONESHOT_H

#include "sync.h"

#include <deque>
#include <set>
#include <string>

/** Pending seed connections, sharing the ordinary outbound permit budget. */
class COneShotQueue
{
private:
    CCriticalSection mutex;
    std::deque<std::string> destinations;
    std::set<std::string> pending;

public:
    void Add(const std::string& destination)
    {
        LOCK(mutex);
        if (pending.insert(destination).second)
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
        // Keep the selected destination in pending while the connector runs.
        // A concurrent Add() then cannot create a duplicate retry turn. A
        // failed attempt is explicitly moved to the tail; a success retires
        // the pending key and lets a later explicit request try again.
        if (!connect(destination, grant)) {
            LOCK(mutex);
            destinations.push_back(destination);
        } else {
            LOCK(mutex);
            pending.erase(destination);
        }
    }
};

#endif // ZCLASSIC_NET_ONESHOT_H
