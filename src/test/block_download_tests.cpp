// Copyright (c) 2026 The Zclassic developers
// Distributed under the MIT software license, see COPYING.

#include "chainparams.h"
#include "consensus/validation.h"
#include "main.h"
#include "net.h"
#include "test/test_bitcoin.h"
#include "utiltime.h"

#include <boost/test/unit_test.hpp>
#include <fstream>
#include <memory>

extern bool ProcessMessage(CNode*, std::string, CDataStream&, int64_t);

namespace {
struct DownloadSetup : TestingSetup {
    std::vector<CBlock> blocks;
    const int64_t start = 1800000000000000LL;

    DownloadSetup()
    {
        SetMockTimeMicros(start);
        const auto path = boost::filesystem::path(BOOST_PP_STRINGIZE(TEST_DATA_DIR)) /
                          "zclassic-download-130.dat";
        std::ifstream file(path.string(), std::ios::binary);
        BOOST_REQUIRE(file.good());
        std::vector<char> bytes((std::istreambuf_iterator<char>(file)), {});
        CDataStream stream(bytes, SER_DISK, PROTOCOL_VERSION);
        while (!stream.empty()) {
            unsigned char magic[4];
            stream.read(reinterpret_cast<char*>(magic), 4);
            BOOST_REQUIRE(std::equal(magic, magic + 4, Params().MessageStart()));
            uint32_t size;
            stream >> size;
            BOOST_REQUIRE_LE(size, stream.size());
            const size_t before = stream.size();
            CBlock block;
            stream >> block;
            BOOST_REQUIRE_EQUAL(before - stream.size(), size);
            if (!blocks.empty()) BOOST_REQUIRE(block.hashPrevBlock == blocks.back().GetHash());
            blocks.push_back(block);
        }
        BOOST_REQUIRE_EQUAL(blocks.size(), 130);
        BOOST_REQUIRE(blocks.front().GetHash() == Params().GetConsensus().hashGenesisBlock);
    }

    ~DownloadSetup() { SetMockTimeMicros(0); }

    void Headers(CNode& peer)
    {
        peer.nVersion = PROTOCOL_VERSION;
        // Retain outgoing frames in memory for the simulated transport. An
        // already queued byte prevents optimistic writes to INVALID_SOCKET.
        if (peer.vSendMsg.empty()) {
            peer.vSendMsg.push_back(CSerializeData(1, 0));
            peer.nSendSize = 1;
        }
        CDataStream payload(SER_NETWORK, PROTOCOL_VERSION);
        WriteCompactSize(payload, blocks.size() - 1);
        for (size_t i = 1; i < blocks.size(); ++i) {
            payload << blocks[i].GetBlockHeader();
            WriteCompactSize(payload, 0);
        }
        BOOST_REQUIRE(ProcessMessage(&peer, "headers", payload, GetTime()));
    }

    CNodeStateStats Stats(CNode& peer)
    {
        CNodeStateStats stats;
        BOOST_REQUIRE(GetNodeStateStats(peer.GetId(), stats));
        return stats;
    }

    void Deliver(CNode& peer, size_t height)
    {
        CDataStream payload(SER_NETWORK, PROTOCOL_VERSION);
        payload << blocks.at(height);
        BOOST_REQUIRE(ProcessMessage(&peer, "block", payload, GetTime()));
    }

    void Churn(unsigned rounds)
    {
        for (unsigned i = 0; i < rounds; ++i) {
            CNode peer(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "A", true);
            Headers(peer);
            BOOST_REQUIRE(SendMessages(&peer, false));
            BOOST_REQUIRE_EQUAL(Stats(peer).nBlocksInFlight, 128);
        }
    }
};
}

BOOST_FIXTURE_TEST_SUITE(block_download_tests, DownloadSetup)

BOOST_AUTO_TEST_CASE(teardown_releases_all_accounting)
{
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "B", true);
    for (unsigned round = 0; round < 8; ++round) {
        Churn(1);
        auto stats = Stats(healthy);
        BOOST_CHECK_EQUAL(stats.nGlobalBlocksInFlight, 0);
        BOOST_CHECK_EQUAL(stats.nGlobalValidatedBlocksInFlight, 0);
    }
    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    const auto stats = Stats(healthy);
    BOOST_CHECK_EQUAL(stats.nBlocksInFlight, 128);
    BOOST_CHECK_EQUAL(stats.nValidatedBlocksInFlight, 128);
    BOOST_CHECK_EQUAL(stats.nGlobalBlocksInFlight, 128);
    BOOST_CHECK_EQUAL(stats.nGlobalValidatedBlocksInFlight, 128);
    BOOST_CHECK_EQUAL(stats.vHeightInFlight.front(), 1);
}

BOOST_AUTO_TEST_CASE(headers_do_not_hide_stall_and_healthy_peer_advances_chain)
{
    // Reproduce the live node's accumulated teardown history before A stalls.
    Churn(40);
    CNode stalled(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "A", true);
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "B", true);
    Headers(stalled);
    BOOST_REQUIRE(SendMessages(&stalled, false));
    BOOST_REQUIRE_EQUAL(Stats(stalled).nBlocksInFlight, 128);
    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_REQUIRE_EQUAL(Stats(healthy).nBlocksInFlight, 1);
    Deliver(healthy, 129);
    BOOST_REQUIRE_EQUAL(chainActive.Height(), 0);
    for (int second = 60; second <= 600 && !stalled.fDisconnect; second += 60) {
        SetMockTimeMicros(start + second * 1000000LL);
        Headers(stalled); // Continuing valid header traffic is not block progress.
        BOOST_REQUIRE(SendMessages(&stalled, false));
    }
    BOOST_CHECK(stalled.fDisconnect);
    BOOST_CHECK_EQUAL(Stats(stalled).nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(Stats(healthy).nGlobalBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(Stats(healthy).nGlobalValidatedBlocksInFlight, 0);
    // Keep A's object alive: takeover must not wait for its last reference.
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_REQUIRE_EQUAL(Stats(healthy).nBlocksInFlight, 128);
    for (size_t height = 1; height <= 128; ++height) Deliver(healthy, height);
    BOOST_CHECK_EQUAL(chainActive.Height(), 129);
    BOOST_CHECK(chainActive.Tip()->GetBlockHash() == blocks.back().GetHash());
    BOOST_CHECK_EQUAL(Stats(healthy).nGlobalBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(Stats(healthy).nGlobalValidatedBlocksInFlight, 0);
}

BOOST_AUTO_TEST_SUITE_END()
