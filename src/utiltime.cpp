// Copyright (c) 2009-2010 Satoshi Nakamoto
// Copyright (c) 2009-2014 The Bitcoin Core developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#if defined(HAVE_CONFIG_H)
#include "config/bitcoin-config.h"
#endif

#include "utiltime.h"

#include <chrono>
#include <atomic>
#include <cassert>
#include <boost/date_time/posix_time/posix_time.hpp>
#include <boost/thread.hpp>

using namespace std;

static int64_t nMockTime = 0;  //! For unit testing
static std::atomic<int64_t> nMockTimeMicros{0};
static std::atomic<int64_t> nMockSteadyTimeMicros{0};

void SetMockTimeMicros(int64_t time)
{
    nMockTimeMicros.store(time, std::memory_order_relaxed);
}

void SetMockSteadyTimeMicros(int64_t time)
{
    assert(time >= 0);
    nMockSteadyTimeMicros.store(time, std::memory_order_relaxed);
}

int64_t GetSteadyTimeMicros()
{
    const int64_t mock = nMockSteadyTimeMicros.load(std::memory_order_relaxed);
    if (mock) return mock;
    static const auto origin = std::chrono::steady_clock::now();
    // Use a process-local origin and reserve zero for inactive deadlines.
    return 1 + std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::steady_clock::now() - origin).count();
}

int64_t GetTime()
{
    if (nMockTime) return nMockTime;

    return time(NULL);
}

void SetMockTime(int64_t nMockTimeIn)
{
    nMockTime = nMockTimeIn;
}

int64_t GetTimeMillis()
{
    return std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count();
}

int64_t GetTimeMicros()
{
    const int64_t mock = nMockTimeMicros.load(std::memory_order_relaxed);
    if (mock) return mock;
    return std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count();
}

void MilliSleep(int64_t n)
{
    boost::this_thread::sleep_for(boost::chrono::milliseconds(n));
}

std::string DateTimeStrFormat(const char* pszFormat, int64_t nTime)
{
    // std::locale takes ownership of the pointer
    std::locale loc(std::locale::classic(), new boost::posix_time::time_facet(pszFormat));
    std::stringstream ss;
    ss.imbue(loc);
    ss << boost::posix_time::from_time_t(nTime);
    return ss.str();
}
