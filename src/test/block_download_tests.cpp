// Copyright (c) 2026 The Zclassic developers
// Distributed under the MIT software license, see COPYING.

#include "chainparams.h"
#include "consensus/validation.h"
#include "crypto/common.h"
#include "main.h"
#include "net.h"
#include "test/test_bitcoin.h"
#include "utiltime.h"

#include <boost/test/unit_test.hpp>
#include <boost/test/data/test_case.hpp>
#include <fstream>
#include <memory>
#include <array>
#include <map>
#include <random>
#include <limits>

extern bool ProcessMessage(CNode*, std::string, CDataStream&, int64_t);

namespace {
std::vector<char> MalformedFrame(std::mt19937& random, unsigned step)
{
    const bool headerPayload = step % 2 == 0;
    std::vector<char> payload(1 + random() % 100);
    for (char& byte : payload) byte = static_cast<char>(random());
    // One incomplete block header; never an unbounded allocation request.
    if (headerPayload) payload.front() = 1;
    CMessageHeader header(Params().MessageStart(), headerPayload ? "headers" : "block", payload.size());
    const uint256 checksum = Hash(payload.begin(), payload.end());
    header.nChecksum = ReadLE32(checksum.begin());
    switch (step % 8) {
    case 0: header.pchMessageStart[0] ^= 1; break;
    case 1: header.nChecksum ^= 1; break;
    case 2: header.nMessageSize = MAX_PROTOCOL_MESSAGE_LENGTH + 1; break;
    case 3: header.nMessageSize = std::numeric_limits<unsigned int>::max(); break;
    case 4: header.pchCommand[0] = 0x01; break;
    default: break; // Correct framing, truncated command payload.
    }
    CDataStream encoded(SER_NETWORK, PROTOCOL_VERSION);
    encoded << header;
    encoded.write(payload.data(), payload.size());
    return {encoded.begin(), encoded.end()};
}

void FeedFragments(CNode& peer, const std::vector<char>& frame, std::mt19937& random)
{
    LOCK(peer.cs_vRecvMsg);
    for (size_t offset = 0; offset < frame.size() && !peer.fDisconnect;) {
        const size_t size = std::min<size_t>(1 + random() % 31, frame.size() - offset);
        if (!peer.ReceiveMsgBytes(frame.data() + offset, size) || !ProcessMessages(&peer))
            peer.fDisconnect = true;
        offset += size;
    }
}

struct DownloadSetup : TestingSetup {
    std::vector<CBlock> blocks;
    const int savedDownloadLimit = nMaxBlocksInTransitPerPeer;
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

    ~DownloadSetup() { SetMockTimeMicros(0); nMaxBlocksInTransitPerPeer = savedDownloadLimit; }

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

BOOST_AUTO_TEST_CASE(socket_disconnect_releases_requests_before_finalization)
{
    CNode stalled(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "A", true);
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "B", true);
    Headers(stalled);
    BOOST_REQUIRE(SendMessages(&stalled, false));
    BOOST_REQUIRE_EQUAL(Stats(stalled).nBlocksInFlight, 128);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 1);
    // Socket removal signals download cleanup while other references retain A.
    GetNodeSignals().DisconnectNode(stalled.GetId());
    GetNodeSignals().DisconnectNode(stalled.GetId());
    BOOST_CHECK_EQUAL(Stats(stalled).nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(Stats(healthy).nGlobalValidatedBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 0);
    Headers(stalled); // A queued message must not revive its download lifecycle.
    BOOST_REQUIRE(SendMessages(&stalled, false));
    BOOST_CHECK_EQUAL(Stats(stalled).nBlocksInFlight, 0);
    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_CHECK_EQUAL(Stats(healthy).nBlocksInFlight, 128);
    BOOST_CHECK_EQUAL(Stats(healthy).vHeightInFlight.front(), 1);
    // Late finalization must not release or double-subtract B's reassigned work.
    GetNodeSignals().FinalizeNode(stalled.GetId());
    GetNodeSignals().DisconnectNode(stalled.GetId());
    BOOST_CHECK_EQUAL(Stats(healthy).nBlocksInFlight, 128);
    BOOST_CHECK_EQUAL(Stats(healthy).nGlobalValidatedBlocksInFlight, 128);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 1);
}

BOOST_AUTO_TEST_CASE(randomized_receipt_reassignment_and_repeated_cleanup)
{
    std::array<std::unique_ptr<CNode>, 4> peers;
    for (auto& peer : peers) {
        peer.reset(new CNode(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "mixed", true));
        Headers(*peer);
    }
    // Reference model comes from outbound wire requests, not internal counters.
    std::map<uint256, size_t> expected;
    std::mt19937 random(0x5a434c);
    for (unsigned step = 0; step < 1000; ++step) {
        const size_t owner = random() % peers.size();
        const unsigned operation = random() % 4;
        if (operation < 2) {
            BOOST_REQUIRE(SendMessages(peers[owner].get(), false));
            for (const auto& frame : peers[owner]->vSendMsg) {
                if (frame.size() == 1) continue; // In-memory transport sentinel.
                CDataStream stream(frame, SER_NETWORK, PROTOCOL_VERSION);
                CMessageHeader header(Params().MessageStart());
                stream >> header;
                if (header.GetCommand() != "getdata") continue;
                std::vector<CInv> requests;
                stream >> requests;
                for (const auto& request : requests) {
                    if (request.type != MSG_BLOCK) continue;
                    BOOST_CHECK(expected.emplace(request.hash, owner).second);
                }
            }
            peers[owner]->vSendMsg.clear();
            peers[owner]->vSendMsg.push_back(CSerializeData(1, 0));
            peers[owner]->nSendSize = 1;
        } else if (operation == 2 && !expected.empty()) {
            auto request = expected.begin();
            std::advance(request, random() % expected.size());
            const int height = mapBlockIndex.at(request->first)->nHeight;
            expected.erase(request);
            // Any peer may deliver a requested block, including a different owner.
            Deliver(*peers[owner], height);
            Deliver(*peers[owner], height); // Duplicate receipt must not subtract twice.
        } else {
            GetNodeSignals().FinalizeNode(peers[owner]->GetId());
            GetNodeSignals().FinalizeNode(peers[owner]->GetId());
            for (auto it = expected.begin(); it != expected.end();) {
                if (it->second == owner) it = expected.erase(it);
                else ++it;
            }
            CNodeStateStats absent;
            BOOST_CHECK(!GetNodeStateStats(peers[owner]->GetId(), absent));
            GetNodeSignals().InitializeNode(peers[owner]->GetId(), peers[owner].get());
            Headers(*peers[owner]);
        }
        std::array<size_t, 4> queued{};
        for (const auto& entry : expected) ++queued[entry.second];
        for (size_t index = 0; index < peers.size(); ++index) {
            const auto stats = Stats(*peers[index]);
            BOOST_CHECK_EQUAL(stats.nBlocksInFlight, queued[index]);
            BOOST_CHECK_EQUAL(stats.nValidatedBlocksInFlight, queued[index]);
            BOOST_CHECK_EQUAL(stats.nGlobalBlocksInFlight, expected.size());
            BOOST_CHECK_EQUAL(stats.nGlobalValidatedBlocksInFlight, expected.size());
        }
    }
    for (auto& peer : peers) GetNodeSignals().FinalizeNode(peer->GetId());
    GetNodeSignals().InitializeNode(peers.front()->GetId(), peers.front().get());
    BOOST_CHECK_EQUAL(Stats(*peers.front()).nGlobalBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(Stats(*peers.front()).nGlobalValidatedBlocksInFlight, 0);
}

// Exercise the actual framed ingress path with fragmented hostile messages,
// while the sender owns requests. Teardown must still permit a healthy takeover.
BOOST_AUTO_TEST_CASE(fragmented_malformed_messages_release_downloads)
{
    std::mt19937 random(0x4f475a43);
    for (unsigned step = 0; step < 512; ++step) {
        CNode peer(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "malformed", true);
        Headers(peer);
        BOOST_REQUIRE(SendMessages(&peer, false));
        BOOST_REQUIRE_EQUAL(Stats(peer).nBlocksInFlight, 128);

        FeedFragments(peer, MalformedFrame(random, step), random);
        BOOST_REQUIRE(SendMessages(&peer, false));
        // Remote close may follow any malformed or incomplete frame. Keep the
        // object alive to ensure cleanup does not depend on final destruction.
        peer.fDisconnect = true;
        GetNodeSignals().DisconnectNode(peer.GetId());
        GetNodeSignals().DisconnectNode(peer.GetId());
        BOOST_CHECK_EQUAL(Stats(peer).nBlocksInFlight, 0);
        BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
        BOOST_CHECK_EQUAL(GetBlockDownloadStats().nValidatedBlocksInFlight, 0);
        BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 0);
    }
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 1)), "healthy", true);
    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_REQUIRE_EQUAL(Stats(healthy).nBlocksInFlight, 128);
    Deliver(healthy, 129);
    for (size_t height = 1; height <= 128; ++height) Deliver(healthy, height);
    BOOST_CHECK_EQUAL(chainActive.Height(), 129);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nValidatedBlocksInFlight, 0);
}

BOOST_DATA_TEST_CASE(download_limits_bound_requests_and_recover,
                     boost::unit_test::data::make(std::vector<int>{16, 32, 64, 128}))
{
    nMaxBlocksInTransitPerPeer = sample;
    CNode stalled(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "A", true);
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "B", true);
    Headers(stalled);
    BOOST_REQUIRE(SendMessages(&stalled, false));
    BOOST_REQUIRE_EQUAL(Stats(stalled).nBlocksInFlight, sample);
    BOOST_REQUIRE(SendMessages(&stalled, false));
    BOOST_REQUIRE_EQUAL(Stats(stalled).nBlocksInFlight, sample);
    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    const auto laterHeights = Stats(healthy).vHeightInFlight;
    BOOST_REQUIRE_EQUAL(laterHeights.size(), std::min(sample, 129 - sample));
    for (int height : laterHeights) Deliver(healthy, height);
    BOOST_REQUIRE_EQUAL(chainActive.Height(), 0);
    SetMockTimeMicros(start + 301000000LL);
    Headers(stalled);
    BOOST_REQUIRE(SendMessages(&stalled, false));
    BOOST_CHECK(stalled.fDisconnect);
    BOOST_CHECK_EQUAL(Stats(healthy).nGlobalBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(Stats(healthy).nGlobalValidatedBlocksInFlight, 0);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    const auto takeover = Stats(healthy).vHeightInFlight;
    BOOST_REQUIRE_EQUAL(takeover.size(), sample);
    BOOST_REQUIRE_EQUAL(takeover.front(), 1);
    for (int height : takeover) Deliver(healthy, height);
    BOOST_CHECK_EQUAL(chainActive.Height(), std::min(2 * sample, 129));
    BOOST_CHECK_EQUAL(Stats(healthy).nGlobalBlocksInFlight, 0);
}

BOOST_AUTO_TEST_SUITE_END()
