// Copyright (c) 2026 The Zclassic developers
// Distributed under the MIT software license, see COPYING.

#ifndef ZCLASSIC_NET_SELECTION_H
#define ZCLASSIC_NET_SELECTION_H

#include "addrman.h"

// Callbacks run synchronously. The caller retains network-group, local-address
// and enabled-network policy; addrman retains randomized candidate selection.
template <typename Select, typename Excluded, typename Limited>
CAddrInfo SelectOutboundAddress(Select select, Excluded excluded, Limited limited,
                                int64_t now, int defaultPort)
{
    // Every draw consumes the budget, including already-connected groups.
    for (int tries = 1; tries <= 100; ++tries) {
        CAddrInfo address = select();
        if (!address.IsValid())
            break;
        if (excluded(address) || limited(address))
            continue;

        // Preserve the retry preference even across the signed time range.
        const bool recentlyTried = address.nLastTry > now ||
            static_cast<uint64_t>(now) - static_cast<uint64_t>(address.nLastTry) < 600;
        if (recentlyTried && tries < 30)
            continue;
        // Prefer the default port until enough candidates have been tried.
        if (address.GetPort() != defaultPort && tries < 50)
            continue;
        return address;
    }
    return CAddrInfo();
}

#endif // ZCLASSIC_NET_SELECTION_H
