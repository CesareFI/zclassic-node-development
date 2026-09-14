// Copyright (c) 2026 The Zclassic developers
// Distributed under the MIT software license, see COPYING.

#ifndef ZCLASSIC_IMPORTING_H
#define ZCLASSIC_IMPORTING_H

#include <cassert>
#include <atomic>

// Written by the importer and observed by networking and validation threads.
extern std::atomic<bool> fImporting;
extern std::atomic<bool> fReindex;

// Releases request ownership under cs_main at import entry, even when the whole
// import finishes between two peer-scheduler visits.
void ResetBlockDownloadForImport();

// The block importer has one owner for each file or reindex pass.
struct CImportingNow
{
    CImportingNow() {
        const bool previous = fImporting.exchange(true);
        assert(!previous);
        ResetBlockDownloadForImport();
    }

    ~CImportingNow() {
        const bool previous = fImporting.exchange(false);
        assert(previous);
    }

    CImportingNow(const CImportingNow&) = delete;
    CImportingNow& operator=(const CImportingNow&) = delete;
};

#endif // ZCLASSIC_IMPORTING_H
