// Copyright (c) 2009-2010 Satoshi Nakamoto
// Copyright (c) 2009-2014 The Bitcoin Core developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#ifndef BITCOIN_UTILTIME_H
#define BITCOIN_UTILTIME_H

#include <stdint.h>
#include <string>

int64_t GetTime();
int64_t GetTimeMillis();
int64_t GetTimeMicros();
/** Monotonic microseconds for process-local elapsed-time enforcement. */
int64_t GetSteadyTimeMicros();
void SetMockTime(int64_t nMockTimeIn);
/** Override the request clock in deterministic tests; zero restores real time. */
void SetMockTimeMicros(int64_t time);
/** Override with nonnegative monotonic microseconds; zero restores real time. */
void SetMockSteadyTimeMicros(int64_t time);
void MilliSleep(int64_t n);

std::string DateTimeStrFormat(const char* pszFormat, int64_t nTime);

#endif // BITCOIN_UTILTIME_H
