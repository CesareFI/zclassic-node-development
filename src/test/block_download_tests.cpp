// Copyright (c) 2026 The Zclassic developers
// Distributed under the MIT software license, see COPYING.

#include "chainparams.h"
#include "addrman.h"
#include "bootstrap.h"
#include "consensus/validation.h"
#include "crypto/common.h"
#include "importing.h"
#include "main.h"
#include "net.h"
#include "rpc/server.h"
#include "test/test_bitcoin.h"
#include "util.h"
#include "utilstrencodings.h"
#include "utiltime.h"
#include "timedata.h"

#include <boost/test/unit_test.hpp>
#include <boost/test/data/test_case.hpp>
#include <fstream>
#include <memory>
#include <array>
#include <map>
#include <random>
#include <limits>
#include <chrono>

extern bool ProcessMessage(CNode*, std::string, CDataStream&, int64_t);
extern UniValue CallRPC(std::string);

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

std::vector<char> TruncatedPayloadFrame(const char* command)
{
    // Both commands require more bytes after this nonzero prefix: a block
    // needs its header and headers needs the declared header body.
    const std::vector<char> payload(1, 1);
    CMessageHeader header(Params().MessageStart(), command, payload.size());
    const uint256 checksum = Hash(payload.begin(), payload.end());
    header.nChecksum = ReadLE32(checksum.begin());
    CDataStream encoded(SER_NETWORK, PROTOCOL_VERSION);
    encoded << header;
    encoded.write(payload.data(), payload.size());
    return {encoded.begin(), encoded.end()};
}

std::vector<char> FramePayload(const char* command, const CDataStream& payload)
{
    CMessageHeader header(Params().MessageStart(), command, payload.size());
    const uint256 checksum = Hash(payload.begin(), payload.end());
    header.nChecksum = ReadLE32(checksum.begin());
    CDataStream encoded(SER_NETWORK, PROTOCOL_VERSION);
    encoded << header;
    if (!payload.empty())
        encoded.write(&payload[0], payload.size());
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

class ScopedSendBuffer {
    bool existed;
    std::string value;

public:
    ScopedSendBuffer()
    {
        const auto previous = mapArgs.find("-maxsendbuffer");
        existed = previous != mapArgs.end();
        if (existed) value = previous->second;
        mapArgs["-maxsendbuffer"] = "1";
    }

    ~ScopedSendBuffer()
    {
        if (existed) mapArgs["-maxsendbuffer"] = value;
        else mapArgs.erase("-maxsendbuffer");
    }
};

struct DownloadSetup : TestingSetup {
    std::vector<CBlock> blocks;
    const int savedDownloadLimit = nMaxBlocksInTransitPerPeer;
    const int64_t start = 1800000000000000LL;

    void SetClocks(int64_t time)
    {
        SetMockTimeMicros(time);
        SetMockSteadyTimeMicros(time);
    }

    DownloadSetup()
    {
        SetClocks(start);
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

    ~DownloadSetup() { SetMockTime(0); SetClocks(0); nMaxBlocksInTransitPerPeer = savedDownloadLimit; }

    void PrepareTransport(CNode& peer)
    {
        peer.nVersion = PROTOCOL_VERSION;
        // Retain outgoing frames in memory for the simulated transport. An
        // already queued byte prevents optimistic writes to INVALID_SOCKET.
        if (peer.vSendMsg.empty()) {
            peer.vSendMsg.push_back(CSerializeData(1, 0));
            peer.nSendSize = 1;
        }
    }

    void Headers(CNode& peer)
    {
        Headers(peer, blocks.size() - 1);
    }

    void Headers(CNode& peer, size_t count)
    {
        BOOST_REQUIRE_LT(count, blocks.size());
        PrepareTransport(peer);
        CDataStream payload(SER_NETWORK, PROTOCOL_VERSION);
        WriteCompactSize(payload, count);
        for (size_t i = 1; i <= count; ++i) {
            payload << blocks[i].GetBlockHeader();
            WriteCompactSize(payload, 0);
        }
        BOOST_REQUIRE(ProcessMessage(&peer, "headers", payload, GetTime()));
    }

    void Handshake(CNode& peer, uint64_t services = NODE_NETWORK)
    {
        PrepareTransport(peer);
        peer.nVersion = 0;
        CDataStream version(SER_NETWORK, PROTOCOL_VERSION);
        version << PROTOCOL_VERSION << services << GetTime() << CAddress();
        BOOST_REQUIRE(ProcessMessage(&peer, "version", version, GetTime()));
        CDataStream verack(SER_NETWORK, PROTOCOL_VERSION);
        BOOST_REQUIRE(ProcessMessage(&peer, "verack", verack, GetTime()));
    }

    std::vector<CBlockHeader> ExtendedHeaders()
    {
        std::vector<CBlockHeader> headers;
        for (const CBlock& block : blocks) headers.push_back(block.GetBlockHeader());
        const auto path = boost::filesystem::path(BOOST_PP_STRINGIZE(TEST_DATA_DIR)) /
                          "zclassic-header-extension-320.dat";
        std::ifstream file(path.string(), std::ios::binary);
        BOOST_REQUIRE(file.good());
        std::vector<char> bytes((std::istreambuf_iterator<char>(file)), {});
        BOOST_REQUIRE_EQUAL(bytes.size(), 284017);
        CDataStream stream(bytes, SER_DISK, PROTOCOL_VERSION);
        while (!stream.empty()) {
            CBlockHeader header;
            stream >> header;
            BOOST_REQUIRE(header.hashPrevBlock == headers.back().GetHash());
            headers.push_back(header);
        }
        BOOST_REQUIRE_EQUAL(headers.size(), 321);
        return headers;
    }

    void HeaderBatch(CNode& peer, const std::vector<CBlockHeader>& headers,
                     size_t first, size_t count)
    {
        BOOST_REQUIRE_LE(count, MAX_HEADERS_RESULTS);
        BOOST_REQUIRE_LE(first, headers.size());
        BOOST_REQUIRE_LE(count, headers.size() - first);
        CDataStream payload(SER_NETWORK, PROTOCOL_VERSION);
        WriteCompactSize(payload, count);
        for (size_t index = first; index < first + count; ++index) {
            payload << headers[index];
            WriteCompactSize(payload, 0);
        }
        BOOST_REQUIRE(ProcessMessage(&peer, "headers", payload, GetTime()));
    }

    unsigned Sent(CNode& peer, const std::string& command)
    {
        unsigned count = 0;
        for (const auto& frame : peer.vSendMsg) {
            if (frame.size() == 1) continue;
            CDataStream stream(frame, SER_NETWORK, PROTOCOL_VERSION);
            CMessageHeader header(Params().MessageStart());
            stream >> header;
            if (header.GetCommand() == command) ++count;
        }
        return count;
    }

    CNodeStateStats Stats(CNode& peer)
    {
        CNodeStateStats stats;
        BOOST_REQUIRE(GetNodeStateStats(peer.GetId(), stats));
        return stats;
    }

    UniValue PeerInfo(CNode& peer)
    {
        const auto info = CallRPC("getpeerinfo");
        for (size_t index = 0; index < info.size(); ++index) {
            if (find_value(info[index], "id").get_int() == peer.GetId())
                return info[index];
        }
        BOOST_FAIL("peer missing from diagnostic RPC");
        return UniValue();
    }

    void Deliver(CNode& peer, size_t height)
    {
        CDataStream payload(SER_NETWORK, PROTOCOL_VERSION);
        payload << blocks.at(height);
        BOOST_REQUIRE(ProcessMessage(&peer, "block", payload, GetTime()));
    }

    void CheckReject(CNode& peer, const std::string& command, const std::string& reason, const uint256& hash)
    {
        unsigned found = 0;
        for (const auto& frame : peer.vSendMsg) {
            if (frame.size() == 1) continue; // In-memory transport sentinel.
            CDataStream stream(frame, SER_NETWORK, PROTOCOL_VERSION);
            CMessageHeader header(Params().MessageStart());
            stream >> header;
            if (header.GetCommand() != "reject") continue;
            ++found;
            std::string actualCommand, actualReason;
            unsigned char code;
            uint256 actualHash;
            stream >> actualCommand >> code >> actualReason >> actualHash;
            BOOST_CHECK_EQUAL(actualCommand, command);
            BOOST_CHECK_EQUAL(code, REJECT_INVALID);
            BOOST_CHECK_EQUAL(actualReason, reason);
            BOOST_CHECK(actualHash == hash);
            BOOST_CHECK(stream.empty());
        }
        BOOST_CHECK_EQUAL(found, 1);
    }

    uint64_t LastPingNonce(CNode& peer)
    {
        uint64_t nonce = 0;
        for (const auto& frame : peer.vSendMsg) {
            if (frame.size() == 1) continue;
            CDataStream stream(frame, SER_NETWORK, PROTOCOL_VERSION);
            CMessageHeader header(Params().MessageStart());
            stream >> header;
            if (header.GetCommand() == "ping") {
                stream >> nonce;
                BOOST_REQUIRE(stream.empty());
            }
        }
        BOOST_REQUIRE(nonce != 0);
        return nonce;
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

// A bounded index-only branch for scheduler tests. It is never submitted to
// validation or made active: it merely gives the downloader enough known
// heights to reach its BLOCK_DOWNLOAD_WINDOW-full path without a chain copy.
struct BlockWindowFixture {
    std::vector<uint256> hashes;
    std::vector<CBlockIndex> indexes;

    BlockWindowFixture() : hashes(BLOCK_DOWNLOAD_WINDOW + 2),
                           indexes(BLOCK_DOWNLOAD_WINDOW + 1)
    {
        CBlockIndex* previous = chainActive.Tip();
        for (unsigned int height = 1; height <= BLOCK_DOWNLOAD_WINDOW + 1;
             ++height) {
            WriteLE32(hashes[height].begin(), height);
            CBlockIndex& index = indexes[height - 1];
            index.phashBlock = &hashes[height];
            index.pprev = previous;
            index.nHeight = height;
            index.nChainWork = previous->nChainWork + arith_uint256(1);
            index.nStatus = BLOCK_VALID_TREE;
            index.BuildSkip();
            const bool inserted = mapBlockIndex.insert(
                std::make_pair(hashes[height], &index)).second;
            assert(inserted);
            previous = &index;
        }
    }

    ~BlockWindowFixture()
    {
        for (unsigned int height = 1; height <= BLOCK_DOWNLOAD_WINDOW + 1;
             ++height)
            mapBlockIndex.erase(hashes[height]);
    }

    const uint256& Tip() const { return hashes.back(); }
};
}

BOOST_FIXTURE_TEST_SUITE(block_download_tests, DownloadSetup)

BOOST_DATA_TEST_CASE(idle_peer_scheduling_preserves_completed_roles,
                    boost::unit_test::data::make({125U, 750U}), peerCount)
{
    std::vector<std::unique_ptr<CNode>> peers;
    for (unsigned index = 0; index < peerCount; ++index) {
        peers.emplace_back(new CNode(INVALID_SOCKET,
            CAddress(CService("127.0.0.1", static_cast<int>(index + 1))), "idle", index != 0));
        Handshake(*peers.back());
        BOOST_REQUIRE(SendMessages(peers.back().get(), false));
        Headers(*peers.back(), 0);
    }
    BOOST_REQUIRE_EQUAL(GetBlockDownloadStats().nPreferredDownloadPeers, 1);
    BOOST_REQUIRE_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 0);
    const auto begin = std::chrono::steady_clock::now();
    bool sent = true;
    for (unsigned round = 0; round < 1000; ++round)
        for (const auto& peer : peers)
            sent &= SendMessages(peer.get(), false);
    const std::chrono::duration<double> elapsed = std::chrono::steady_clock::now() - begin;
    BOOST_TEST_MESSAGE("idle_peer_count=" << peerCount << " idle_scheduling_seconds=" << elapsed.count());
    BOOST_CHECK(sent);
    for (const auto& peer : peers) {
        BOOST_CHECK(!peer->fDisconnect);
        BOOST_CHECK_EQUAL(Sent(*peer, "getheaders"), 1);
        BOOST_CHECK_EQUAL(Stats(*peer).nBlocksInFlight, 0);
    }
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nPreferredDownloadPeers, 1);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
}

BOOST_AUTO_TEST_CASE(inbound_discovers_work_after_preferred_sources_finish_without_headers)
{
    CNode outbound(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "A", false);
    CNode inbound(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "B", true);
    Handshake(outbound);
    BOOST_REQUIRE(SendMessages(&outbound, false));
    Headers(outbound, 0);
    BOOST_REQUIRE(Stats(outbound).fPreferredDownload);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 0);

    Handshake(inbound);
    BOOST_REQUIRE(SendMessages(&inbound, false));
    BOOST_REQUIRE_EQUAL(Sent(inbound, "getheaders"), 1);
    BOOST_CHECK(!Stats(inbound).fPreferredDownload);
    Headers(inbound);
    BOOST_REQUIRE(SendMessages(&inbound, false));
    BOOST_REQUIRE_EQUAL(Stats(inbound).nBlocksInFlight, 128);
    for (size_t height = 1; height <= 128; ++height) Deliver(inbound, height);
    BOOST_REQUIRE(SendMessages(&inbound, false));
    Deliver(inbound, 129);
    BOOST_CHECK_EQUAL(chainActive.Height(), 129);
    BOOST_CHECK(!outbound.fDisconnect);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
}

BOOST_AUTO_TEST_CASE(preferred_source_after_many_inbounds_retains_priority)
{
    std::vector<std::unique_ptr<CNode>> inbounds;
    for (unsigned index = 0; index < 64; ++index) {
        inbounds.emplace_back(new CNode(INVALID_SOCKET,
            CAddress(CService("127.0.0.1", static_cast<int>(index + 10))), "inbound", true));
        Handshake(*inbounds.back());
    }
    CNode preferred(INVALID_SOCKET, CAddress(CService("127.0.0.2", 1)), "preferred", false);
    Handshake(preferred);
    BOOST_REQUIRE(SendMessages(&preferred, false));
    for (const auto& peer : inbounds) {
        BOOST_REQUIRE(SendMessages(peer.get(), false));
        BOOST_CHECK_EQUAL(Sent(*peer, "getheaders"), 0);
    }
    Headers(preferred);
    for (const auto& peer : inbounds) {
        BOOST_REQUIRE(SendMessages(peer.get(), false));
        BOOST_CHECK_EQUAL(Sent(*peer, "getheaders"), 0);
        BOOST_CHECK_EQUAL(Stats(*peer).nBlocksInFlight, 0);
    }
    BOOST_REQUIRE(SendMessages(&preferred, false));
    BOOST_REQUIRE_EQUAL(Stats(preferred).nBlocksInFlight, 128);
    GetNodeSignals().DisconnectNode(preferred.GetId());
    CNode& fallback = *inbounds.front();
    BOOST_REQUIRE(SendMessages(&fallback, false));
    BOOST_CHECK_EQUAL(Sent(fallback, "getheaders"), 1);
    Headers(fallback);
    BOOST_REQUIRE(SendMessages(&fallback, false));
    BOOST_REQUIRE_EQUAL(Stats(fallback).nBlocksInFlight, 128);
    for (size_t height = 1; height <= 128; ++height) Deliver(fallback, height);
    BOOST_REQUIRE(SendMessages(&fallback, false));
    Deliver(fallback, 129);
    BOOST_CHECK_EQUAL(chainActive.Height(), 129);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
}

BOOST_AUTO_TEST_CASE(preferred_discovery_and_known_work_keep_priority_over_inbound)
{
    CNode empty(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "empty", false);
    CNode preferred(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "preferred", false);
    CNode inbound(INVALID_SOCKET, CAddress(CService("127.0.0.3", 3)), "inbound", true);
    Handshake(empty);
    BOOST_REQUIRE(SendMessages(&empty, false));
    Headers(empty, 0);
    Handshake(preferred);
    Handshake(inbound);
    BOOST_REQUIRE(SendMessages(&inbound, false));
    BOOST_CHECK_EQUAL(Sent(inbound, "getheaders"), 0);
    BOOST_REQUIRE(SendMessages(&preferred, false));
    Headers(preferred);
    BOOST_CHECK(!Stats(preferred).fHeaderSyncStarted);
    // Visit the inbound before the preferred peer has any block assignments.
    BOOST_REQUIRE(SendMessages(&inbound, false));
    BOOST_CHECK_EQUAL(Sent(inbound, "getheaders"), 0);
    BOOST_CHECK_EQUAL(Stats(inbound).nBlocksInFlight, 0);
    BOOST_REQUIRE(SendMessages(&preferred, false));
    for (size_t height = 1; height <= 128; ++height) Deliver(preferred, height);
    BOOST_REQUIRE(SendMessages(&preferred, false));
    Deliver(preferred, 129);
    BOOST_REQUIRE(SendMessages(&inbound, false));
    BOOST_CHECK_EQUAL(Sent(inbound, "getheaders"), 1);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
}

BOOST_AUTO_TEST_CASE(known_inventory_resolves_before_preferred_source_fallback)
{
    CNode preferred(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "A", false);
    CNode inbound(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "B", true);
    Handshake(preferred);
    BOOST_REQUIRE(SendMessages(&preferred, false));
    Headers(preferred, 0);
    CDataStream inventory(SER_NETWORK, PROTOCOL_VERSION);
    inventory << std::vector<CInv>{CInv(MSG_BLOCK, blocks[129].GetHash())};
    BOOST_REQUIRE(ProcessMessage(&preferred, "inv", inventory, GetTime()));
    BOOST_CHECK_EQUAL(Stats(preferred).nSyncHeight, -1);
    Handshake(inbound);
    Headers(inbound); // The previously unknown outbound announcement is now known.
    BOOST_REQUIRE(SendMessages(&inbound, false));
    BOOST_CHECK_EQUAL(Stats(inbound).nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(Stats(preferred).nSyncHeight, 129);
    BOOST_REQUIRE(SendMessages(&preferred, false));
    BOOST_CHECK_EQUAL(Stats(preferred).nBlocksInFlight, 128);
}

BOOST_AUTO_TEST_CASE(unanswered_headers_release_role_without_waiting_for_block_requests)
{
    CNode silent(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "A", false);
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "B", false);
    Handshake(silent);
    Handshake(healthy);
    BOOST_REQUIRE(SendMessages(&silent, false));
    BOOST_REQUIRE_EQUAL(Sent(silent, "getheaders"), 1);
    BOOST_REQUIRE_EQUAL(Stats(silent).nBlocksInFlight, 0);
    const int64_t deadline = Stats(silent).nHeaderSyncDeadline;
    BOOST_REQUIRE_EQUAL(deadline - start, 15 * 60 * 1000000LL);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_REQUIRE_EQUAL(Sent(healthy, "getheaders"), 0);

    SetClocks(deadline);
    BOOST_REQUIRE(SendMessages(&silent, false));
    BOOST_CHECK(!silent.fDisconnect);
    SetClocks(deadline + 1);
    BOOST_REQUIRE(SendMessages(&silent, false));
    BOOST_CHECK(silent.fDisconnect);
    BOOST_CHECK(Stats(silent).fBlockDownloadStopped);
    BOOST_CHECK_EQUAL(Stats(silent).nHeaderSyncDeadline, 0);
    BOOST_CHECK_EQUAL(Stats(silent).nMisbehavior, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);

    // Visit repeated inbound reconnects before B. Existing outbound eligibility
    // must prevent these connections from reclaiming the free header role.
    for (unsigned round = 0; round < 8; ++round) {
        CNode inbound(INVALID_SOCKET, silent.addr, "reconnect", true);
        Handshake(inbound);
        BOOST_REQUIRE(SendMessages(&inbound, false));
        BOOST_CHECK_EQUAL(Sent(inbound, "getheaders"), 0);
    }
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_REQUIRE_EQUAL(Sent(healthy, "getheaders"), 1);
    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    for (size_t height = 1; height <= 128; ++height) Deliver(healthy, height);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    Deliver(healthy, 129);
    BOOST_CHECK_EQUAL(chainActive.Height(), 129);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
    GetNodeSignals().DisconnectNode(silent.GetId());
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 0);
}

BOOST_DATA_TEST_CASE(header_timeout_ignores_wall_clock_steps,
                    boost::unit_test::data::make({-3600, 3600}), wallStep)
{
    CNode silent(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "silent", false);
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "healthy", false);
    Handshake(silent);
    Handshake(healthy);
    BOOST_REQUIRE(SendMessages(&silent, false));
    BOOST_REQUIRE_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 1);

    // Civil time changes independently of the elapsed request age.
    SetMockTimeMicros(start + wallStep * 1000000LL);
    SetMockSteadyTimeMicros(start + 899 * 1000000LL);
    BOOST_REQUIRE(SendMessages(&silent, false));
    BOOST_CHECK(!silent.fDisconnect);
    BOOST_CHECK_EQUAL(Stats(silent).nHeaderSyncTimeoutRemaining, 1000000);
    BOOST_CHECK_EQUAL(Stats(silent).nHeaderSyncDeadline, GetTimeMicros() + 1000000);
    SetMockSteadyTimeMicros(start + 900 * 1000000LL);
    BOOST_REQUIRE(SendMessages(&silent, false));
    BOOST_CHECK(!silent.fDisconnect); // Preserve the strict expiry boundary.
    SetMockSteadyTimeMicros(start + 900 * 1000000LL + 1);
    BOOST_REQUIRE(SendMessages(&silent, false));
    BOOST_CHECK(silent.fDisconnect);
    BOOST_CHECK_EQUAL(Stats(silent).nHeaderSyncDeadline, 0);
    BOOST_CHECK_EQUAL(Stats(silent).nMisbehavior, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 0);

    // The next source acquires the role without waiting for object destruction.
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_CHECK_EQUAL(Sent(healthy, "getheaders"), 1);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 1);
    BOOST_CHECK_EQUAL(Stats(healthy).nHeaderSyncDeadline,
                      GetTimeMicros() + 900 * 1000000LL);
    BOOST_CHECK_EQUAL(Stats(healthy).nHeaderSyncTimeoutRemaining, 900 * 1000000LL);
}

BOOST_AUTO_TEST_CASE(repeated_full_header_batch_does_not_extend_response_deadline)
{
    const auto headers = ExtendedHeaders();
    CNode first(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "A", false);
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "B", false);
    Handshake(first);
    Handshake(healthy);
    BOOST_REQUIRE(SendMessages(&first, false));
    SetClocks(start + 500 * 1000000LL);
    HeaderBatch(first, headers, 1, MAX_HEADERS_RESULTS);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 1);
    const int64_t deadline = Stats(first).nHeaderSyncDeadline;
    BOOST_CHECK_EQUAL(deadline, start + 1400 * 1000000LL);
    SetClocks(start + 1300 * 1000000LL);
    HeaderBatch(first, headers, 1, MAX_HEADERS_RESULTS);
    BOOST_CHECK_EQUAL(Stats(first).nHeaderSyncDeadline, deadline);
    // Both replies are valid. Repeating the same range is not progress and
    // must not postpone the deadline for the requested continuation.
    BOOST_CHECK_EQUAL(Stats(first).nMisbehavior, 0);
    BOOST_CHECK_EQUAL(Stats(first).nBlocksInFlight, 0);
    SetClocks(start + 1401 * 1000000LL);
    BOOST_REQUIRE(SendMessages(&first, false));
    BOOST_CHECK(first.fDisconnect);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 0);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_REQUIRE_EQUAL(Sent(healthy, "getheaders"), 1);
}

BOOST_AUTO_TEST_CASE(unsolicited_full_headers_do_not_restart_completed_sync)
{
    const auto headers = ExtendedHeaders();
    CNode peer(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "peer", false);
    Handshake(peer);
    BOOST_REQUIRE(SendMessages(&peer, false));
    BOOST_REQUIRE_EQUAL(Sent(peer, "getheaders"), 1);

    // A short reply completes the request and releases the header-sync role.
    Headers(peer, 0);
    BOOST_REQUIRE(!Stats(peer).fHeaderSyncStarted);
    BOOST_REQUIRE_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 0);

    // A later unsolicited maximum-size batch is still validated and updates
    // availability, but must not manufacture an unbounded continuation loop.
    HeaderBatch(peer, headers, 1, MAX_HEADERS_RESULTS);
    BOOST_CHECK_EQUAL(Sent(peer, "getheaders"), 1);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 0);
    BOOST_CHECK(!Stats(peer).fHeaderSyncStarted);
    BOOST_CHECK_EQUAL(Stats(peer).nHeaderSyncDeadline, 0);
}

BOOST_AUTO_TEST_CASE(advancing_header_batches_keep_slow_discovery_alive)
{
    const auto headers = ExtendedHeaders();
    CNode peer(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "A", false);
    Handshake(peer);
    BOOST_REQUIRE(SendMessages(&peer, false));
    SetClocks(start + 500 * 1000000LL);
    HeaderBatch(peer, headers, 1, MAX_HEADERS_RESULTS);
    SetClocks(start + 1000 * 1000000LL);
    BOOST_REQUIRE(SendMessages(&peer, false));
    BOOST_REQUIRE(!peer.fDisconnect);
    BOOST_REQUIRE_EQUAL(Stats(peer).nBlocksInFlight, 128);
    for (size_t height = 1; height <= 128; ++height) Deliver(peer, height);
    SetClocks(start + 1300 * 1000000LL);
    HeaderBatch(peer, headers, 161, MAX_HEADERS_RESULTS);
    BOOST_CHECK_EQUAL(Stats(peer).nHeaderSyncDeadline, start + 2200 * 1000000LL);
    SetClocks(start + 1401 * 1000000LL);
    BOOST_REQUIRE(SendMessages(&peer, false));
    BOOST_CHECK(!peer.fDisconnect);
    BOOST_CHECK_EQUAL(Stats(peer).nSyncHeight, 320);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 1);
    BOOST_CHECK_EQUAL(Sent(peer, "getheaders"), 3);
    Headers(peer, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 0);
    BOOST_CHECK(!Stats(peer).fBlockDownloadStopped);
    BOOST_CHECK_EQUAL(Stats(peer).nHeaderSyncDeadline, 0);
}

namespace {
struct ImportGuard {
    std::atomic<bool>& flag;
    const bool previous;
    explicit ImportGuard(std::atomic<bool>& value) : flag(value), previous(value) { flag = true; }
    ~ImportGuard() { flag = previous; }
};
}

BOOST_DATA_TEST_CASE(local_import_releases_block_requests_and_resumes,
                    boost::unit_test::data::make({false, true}), reindex)
{
    CNode inbound(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "A", true);
    Handshake(inbound);
    Headers(inbound);
    BOOST_REQUIRE(SendMessages(&inbound, false));
    BOOST_REQUIRE_EQUAL(Stats(inbound).nBlocksInFlight, 128);

    CNode preferred(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "B", false);
    Handshake(preferred);
    Headers(preferred);
    BOOST_REQUIRE(SendMessages(&preferred, false));
    BOOST_REQUIRE_EQUAL(Stats(preferred).nBlocksInFlight, 1);

    for (unsigned round = 0; round < 3; ++round) {
        const auto inboundRequests = Sent(inbound, "getdata");
        const auto preferredRequests = Sent(preferred, "getdata");
        const int64_t deadline = std::max(Stats(inbound).nDownloadDeadline,
                                         Stats(preferred).nDownloadDeadline);
        {
            ImportGuard guard(reindex ? fReindex : fImporting);
            // Ordinary requested blocks are ignored while the local importer
            // owns validation. That must not count as these peers stalling.
            Deliver(round == 0 ? inbound : preferred, 1);
            BOOST_REQUIRE_EQUAL(chainActive.Height(), 0);
            BOOST_REQUIRE(SendMessages(&inbound, false));
            BOOST_REQUIRE(SendMessages(&preferred, false));
            BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
            BOOST_CHECK_EQUAL(GetBlockDownloadStats().nValidatedBlocksInFlight, 0);
            SetClocks(deadline + 1);
            BOOST_REQUIRE(SendMessages(&inbound, false));
            BOOST_REQUIRE(SendMessages(&preferred, false));
            BOOST_CHECK_EQUAL(Sent(inbound, "getdata"), inboundRequests);
            BOOST_CHECK_EQUAL(Sent(preferred, "getdata"), preferredRequests);
            for (CNode* peer : {&inbound, &preferred}) {
                const auto stats = Stats(*peer);
                BOOST_CHECK(!peer->fDisconnect);
                BOOST_CHECK(!stats.fBlockDownloadStopped);
                BOOST_CHECK_EQUAL(stats.nDownloadDeadline, 0);
                BOOST_CHECK_EQUAL(stats.nStallingSince, 0);
                BOOST_CHECK_EQUAL(stats.nMisbehavior, 0);
            }
            BOOST_CHECK(Stats(preferred).fPreferredDownload);
        }
        // Visit the inbound first: the preferred peer must retain priority
        // and acquire the released work immediately when local import ends.
        BOOST_REQUIRE(SendMessages(&inbound, false));
        BOOST_CHECK_EQUAL(Stats(inbound).nBlocksInFlight, 0);
        BOOST_REQUIRE(SendMessages(&preferred, false));
        BOOST_REQUIRE_EQUAL(Stats(preferred).nBlocksInFlight, 128);
        BOOST_CHECK_GT(Stats(preferred).nDownloadDeadline, GetTimeMicros());
    }
    for (size_t height = 1; height <= 128; ++height) Deliver(preferred, height);
    BOOST_REQUIRE(SendMessages(&preferred, false));
    Deliver(preferred, 129);
    BOOST_CHECK_EQUAL(chainActive.Height(), 129);
    BOOST_CHECK(chainActive.Tip()->GetBlockHash() == blocks.back().GetHash());
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nValidatedBlocksInFlight, 0);
}

BOOST_AUTO_TEST_CASE(short_import_cancels_requests_before_the_next_scheduler_visit)
{
    CNode preferred(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "A", false);
    Handshake(preferred);
    Headers(preferred);
    BOOST_REQUIRE(SendMessages(&preferred, false));
    BOOST_REQUIRE_EQUAL(Stats(preferred).nBlocksInFlight, 128);
    BOOST_REQUIRE(Stats(preferred).fHeaderSyncStarted);

    for (unsigned round = 0; round < 3; ++round) {
        const auto before = Stats(preferred);
        {
            CImportingNow importing;
            // The whole import completes before SendMessages runs again.
            BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
            BOOST_CHECK_EQUAL(GetBlockDownloadStats().nValidatedBlocksInFlight, 0);
            BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 0);
            BOOST_CHECK(Stats(preferred).fPreferredDownload);
            Deliver(preferred, 1);
            BOOST_REQUIRE_EQUAL(chainActive.Height(), 0);
        }
        SetClocks(std::max(before.nDownloadDeadline, before.nHeaderSyncDeadline) + 1);
        BOOST_REQUIRE(SendMessages(&preferred, false));
        BOOST_CHECK(!preferred.fDisconnect);
        BOOST_CHECK(!Stats(preferred).fBlockDownloadStopped);
        BOOST_REQUIRE_EQUAL(Stats(preferred).nBlocksInFlight, 128);
        BOOST_CHECK_GT(Stats(preferred).nDownloadDeadline, GetTimeMicros());
        BOOST_CHECK_GT(Stats(preferred).nHeaderSyncDeadline, GetTimeMicros());
    }
    for (size_t height = 1; height <= 128; ++height) Deliver(preferred, height);
    BOOST_REQUIRE(SendMessages(&preferred, false));
    Deliver(preferred, 129);
    BOOST_CHECK_EQUAL(chainActive.Height(), 129);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nValidatedBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(Stats(preferred).nMisbehavior, 0);
}

BOOST_AUTO_TEST_CASE(local_import_retries_headers_without_timing_out_ignored_replies)
{
    for (std::atomic<bool>* importing : {&fImporting, &fReindex}) {
        CNode peer(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "A", false);
        Handshake(peer);
        BOOST_REQUIRE(SendMessages(&peer, false));
        const int64_t deadline = Stats(peer).nHeaderSyncDeadline;
        {
            ImportGuard guard(*importing);
            SetClocks(deadline + 1);
            Headers(peer, 0); // Normal reply is ignored during local import.
            BOOST_REQUIRE(SendMessages(&peer, false));
            BOOST_CHECK(!peer.fDisconnect);
            BOOST_CHECK_EQUAL(Stats(peer).nHeaderSyncDeadline, 0);
            BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 0);
        }
        BOOST_REQUIRE(SendMessages(&peer, false));
        BOOST_CHECK(!peer.fDisconnect);
        BOOST_CHECK_EQUAL(Sent(peer, "getheaders"), 2);
        BOOST_CHECK_GT(Stats(peer).nHeaderSyncDeadline, GetTimeMicros());
        BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 1);
        Headers(peer, 0);
        BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 0);
    }
}

BOOST_AUTO_TEST_CASE(empty_header_response_allows_another_preferred_source)
{
    CNode first(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "A", false);
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "B", false);
    Handshake(first);
    Handshake(healthy);
    BOOST_REQUIRE(SendMessages(&first, false));
    BOOST_REQUIRE_EQUAL(Sent(first, "getheaders"), 1);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_CHECK_EQUAL(Sent(healthy, "getheaders"), 0);

    Headers(first, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 0);
    BOOST_CHECK(!Stats(first).fHeaderSyncStarted);
    BOOST_CHECK(!Stats(first).fBlockDownloadStopped);
    BOOST_CHECK(Stats(first).fPreferredDownload);
    BOOST_CHECK(!first.fDisconnect);
    BOOST_CHECK_EQUAL(Stats(first).nMisbehavior, 0);
    for (unsigned round = 0; round < 8; ++round) {
        Headers(first, 0);
        BOOST_REQUIRE(SendMessages(&first, false));
        BOOST_CHECK_EQUAL(Sent(first, "getheaders"), 1);
    }

    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_REQUIRE_EQUAL(Sent(healthy, "getheaders"), 1);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 1);
    GetNodeSignals().DisconnectNode(first.GetId());
    GetNodeSignals().DisconnectNode(first.GetId());
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 1);
    Headers(healthy);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 0);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    for (size_t height = 1; height <= 128; ++height) Deliver(healthy, height);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    Deliver(healthy, 129);
    BOOST_CHECK_EQUAL(chainActive.Height(), 129);
    BOOST_CHECK_EQUAL(Sent(healthy, "getheaders"), 1);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
}

BOOST_AUTO_TEST_CASE(short_header_response_preserves_blocks_and_releases_header_role)
{
    CNode first(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "A", false);
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "B", false);
    Handshake(first);
    BOOST_REQUIRE(SendMessages(&first, false));
    Headers(first);
    BOOST_REQUIRE(SendMessages(&first, false));
    BOOST_REQUIRE_EQUAL(Stats(first).nBlocksInFlight, 128);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 0);
    BOOST_CHECK(Stats(first).fPreferredDownload);
    BOOST_CHECK(!Stats(first).fBlockDownloadStopped);
    BOOST_CHECK_EQUAL(Sent(first, "getheaders"), 1);

    Handshake(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_REQUIRE_EQUAL(Sent(healthy, "getheaders"), 1);
    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 0);
    BOOST_CHECK_EQUAL(Stats(first).nBlocksInFlight, 128);
    BOOST_REQUIRE_EQUAL(Stats(healthy).nBlocksInFlight, 1);
    Deliver(healthy, 129);
    SetClocks(Stats(first).nDownloadDeadline + 1);
    BOOST_REQUIRE(SendMessages(&first, false));
    BOOST_CHECK(first.fDisconnect);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_REQUIRE_EQUAL(Stats(healthy).nBlocksInFlight, 128);
    for (size_t height = 1; height <= 128; ++height) Deliver(healthy, height);
    BOOST_CHECK_EQUAL(chainActive.Height(), 129);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
}

BOOST_AUTO_TEST_CASE(empty_header_response_releases_inbound_fallback_role)
{
    CNode first(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "A", true);
    CNode second(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "B", true);
    Handshake(first);
    Handshake(second);
    BOOST_REQUIRE(SendMessages(&first, false));
    Headers(first, 0);
    BOOST_REQUIRE(SendMessages(&first, false));
    BOOST_REQUIRE(SendMessages(&second, false));
    BOOST_REQUIRE_EQUAL(Sent(second, "getheaders"), 1);
    BOOST_CHECK_EQUAL(Sent(first, "getheaders"), 1);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 1);
    Headers(first, 0); // Late repeats cannot consume the other peer's role.
    GetNodeSignals().DisconnectNode(first.GetId());
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 1);
    Headers(second, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 0);
}

BOOST_AUTO_TEST_CASE(download_role_rpc_diagnostics_track_reassignment)
{
    CNode inbound(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "A", true);
    CNode preferred(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "B", false);
    struct ListedPeers {
        ListedPeers(CNode& a, CNode& b) {
            LOCK(cs_vNodes);
            BOOST_REQUIRE(vNodes.empty());
            vNodes = {&a, &b};
        }
        ~ListedPeers() {
            LOCK(cs_vNodes);
            vNodes.clear();
        }
    } listed(inbound, preferred);

    auto initial = PeerInfo(inbound);
    BOOST_REQUIRE(find_value(initial, "header_sync_started").isBool());
    BOOST_CHECK(!find_value(initial, "header_sync_started").get_bool());
    BOOST_CHECK(find_value(initial, "header_sync_deadline").isNull());
    BOOST_CHECK(!find_value(initial, "block_download_stopped").get_bool());
    Handshake(inbound);
    Headers(inbound);
    BOOST_REQUIRE(SendMessages(&inbound, false));
    auto assigned = PeerInfo(inbound);
    BOOST_CHECK(find_value(assigned, "header_sync_started").get_bool());
    BOOST_CHECK_EQUAL(find_value(assigned, "blocks_in_flight").get_int(), 128);

    Handshake(preferred);
    BOOST_REQUIRE(SendMessages(&preferred, false));
    auto discovering = PeerInfo(preferred);
    BOOST_CHECK(find_value(discovering, "preferred_download").get_bool());
    BOOST_CHECK(find_value(discovering, "header_sync_started").get_bool());
    BOOST_CHECK_EQUAL(find_value(discovering, "header_sync_deadline").get_int64(),
                      Stats(preferred).nHeaderSyncDeadline / 1000000);
    BOOST_CHECK_EQUAL(find_value(discovering, "header_sync_timeout_remaining").get_real(), 900.0);
    BOOST_CHECK_EQUAL(find_value(discovering, "synced_headers").get_int(), -1);
    const int64_t maxTime = std::numeric_limits<int64_t>::max();
    const std::pair<int64_t, int64_t> wallSteps[] = {
        {start - 3600 * 1000000LL, start - 2700 * 1000000LL},
        {start + 3600 * 1000000LL, start + 4500 * 1000000LL},
        {maxTime - 1, maxTime},
    };
    for (const auto& step : wallSteps) {
        SetMockTimeMicros(step.first);
        const auto shifted = PeerInfo(preferred);
        BOOST_CHECK_EQUAL(find_value(shifted, "header_sync_deadline").get_int64(),
                          step.second / 1000000);
        BOOST_CHECK_EQUAL(find_value(shifted, "header_sync_timeout_remaining").get_real(), 900.0);
    }
    SetMockTimeMicros(start);
    Headers(preferred);
    BOOST_REQUIRE(SendMessages(&preferred, false));
    Deliver(preferred, 129);

    GetNodeSignals().DisconnectNode(inbound.GetId());
    GetNodeSignals().DisconnectNode(inbound.GetId());
    auto stopped = PeerInfo(inbound);
    BOOST_CHECK(!find_value(stopped, "header_sync_started").get_bool());
    BOOST_CHECK(find_value(stopped, "block_download_stopped").get_bool());
    BOOST_CHECK_EQUAL(find_value(stopped, "blocks_in_flight").get_int(), 0);
    BOOST_CHECK(find_value(stopped, "oldest_block_request").isNull());

    BOOST_REQUIRE(SendMessages(&preferred, false));
    auto takeover = PeerInfo(preferred);
    BOOST_CHECK(!find_value(takeover, "header_sync_started").get_bool());
    BOOST_CHECK(find_value(takeover, "header_sync_deadline").isNull());
    BOOST_CHECK(find_value(takeover, "header_sync_timeout_remaining").isNull());
    BOOST_CHECK(!find_value(takeover, "block_download_stopped").get_bool());
    BOOST_CHECK_EQUAL(find_value(takeover, "blocks_in_flight").get_int(), 128);
    for (size_t height = 1; height <= 128; ++height) Deliver(preferred, height);
    BOOST_CHECK_EQUAL(chainActive.Height(), 129);
    GetNodeSignals().DisconnectNode(preferred.GetId());
    auto finished = PeerInfo(preferred);
    BOOST_CHECK(!find_value(finished, "header_sync_started").get_bool());
    BOOST_CHECK(find_value(finished, "block_download_stopped").get_bool());
    BOOST_CHECK_EQUAL(find_value(finished, "global_blocks_in_flight").get_int(), 0);
}

BOOST_AUTO_TEST_CASE(queued_ping_matches_wire_nonce_and_measures_elapsed_time)
{
    CNode peer(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "ping", true);
    Headers(peer);
    BOOST_REQUIRE(SendMessages(&peer, false));
    LastPingNonce(peer);
    SetClocks(start + 1000000);
    {
        LOCK(peer.cs_ping);
        peer.fPingQueued = true;
    }
    BOOST_REQUIRE(SendMessages(&peer, false));
    const uint64_t nonce = LastPingNonce(peer);
    SetClocks(start + 3000000);
    CDataStream wrong(SER_NETWORK, PROTOCOL_VERSION);
    wrong << (nonce == std::numeric_limits<uint64_t>::max() ? uint64_t{1} : nonce + 1);
    BOOST_REQUIRE(ProcessMessage(&peer, "pong", wrong, GetTimeMicros()));
    CNodeStats pending;
    peer.copyStats(pending);
    BOOST_CHECK_EQUAL(pending.dPingWait, 2.0);
    CDataStream correct(SER_NETWORK, PROTOCOL_VERSION);
    correct << nonce;
    BOOST_REQUIRE(ProcessMessage(&peer, "pong", correct, GetTimeMicros()));
    CNodeStats finished;
    peer.copyStats(finished);
    BOOST_CHECK_EQUAL(finished.dPingWait, 0.0);
    BOOST_CHECK_EQUAL(finished.dPingTime, 2.0);
}

BOOST_AUTO_TEST_CASE(trailing_ping_releases_requests_for_takeover)
{
    CNode malformed(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "malformed", true);
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "healthy", true);
    Headers(malformed);
    BOOST_REQUIRE(SendMessages(&malformed, false));
    BOOST_REQUIRE_EQUAL(Stats(malformed).nBlocksInFlight, 128);

    CDataStream payload(SER_NETWORK, PROTOCOL_VERSION);
    payload << uint64_t{1} << uint8_t{0};
    std::mt19937 random(0x50494e47);
    FeedFragments(malformed, FramePayload("ping", payload), random);
    BOOST_REQUIRE(malformed.fDisconnect);
    BOOST_REQUIRE(SendMessages(&malformed, false));
    BOOST_CHECK_EQUAL(Stats(malformed).nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nValidatedBlocksInFlight, 0);

    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_CHECK_EQUAL(Stats(healthy).nBlocksInFlight, 128);
}

BOOST_AUTO_TEST_CASE(block_reject_uses_single_byte_wire_code)
{
    CNode peer(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "reject-block", true);
    Headers(peer);
    CBlock invalid = blocks[1];
    CMutableTransaction coinbase(invalid.vtx[0]);
    ++coinbase.vout[0].nValue;
    invalid.vtx[0] = CTransaction(coinbase);
    // Keep the original valid PoW header, but supply a mismatching Merkle body.
    CDataStream payload(SER_NETWORK, PROTOCOL_VERSION);
    payload << invalid;
    BOOST_REQUIRE(ProcessMessage(&peer, "block", payload, GetTime()));
    CheckReject(peer, "block", "bad-txnmrklroot", invalid.GetHash());
    BOOST_CHECK_EQUAL(chainActive.Height(), 0);
}

BOOST_AUTO_TEST_CASE(block_trailing_bytes_release_request_for_takeover)
{
    CNode malformed(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "malformed", true);
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "healthy", true);
    Headers(malformed);
    BOOST_REQUIRE(SendMessages(&malformed, false));
    BOOST_REQUIRE_EQUAL(Stats(malformed).nBlocksInFlight, 128);

    CDataStream payload(SER_NETWORK, PROTOCOL_VERSION);
    payload << blocks[1] << uint8_t{0};
    BOOST_CHECK(!ProcessMessage(&malformed, "block", payload, GetTime()));
    BOOST_REQUIRE(malformed.fDisconnect);
    BOOST_CHECK_EQUAL(chainActive.Height(), 0);
    BOOST_REQUIRE(SendMessages(&malformed, false));
    BOOST_CHECK_EQUAL(Stats(malformed).nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nValidatedBlocksInFlight, 0);

    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_CHECK_EQUAL(Stats(healthy).nBlocksInFlight, 128);
}

BOOST_AUTO_TEST_CASE(transaction_reject_uses_single_byte_wire_code)
{
    CNode peer(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "reject-tx", true);
    Headers(peer);
    CDataStream payload(SER_NETWORK, PROTOCOL_VERSION);
    payload << blocks[0].vtx[0]; // Coinbase transactions are invalid in the mempool.
    BOOST_REQUIRE(ProcessMessage(&peer, "tx", payload, GetTime()));
    CheckReject(peer, "tx", "coinbase", blocks[0].vtx[0].GetHash());
    BOOST_CHECK_EQUAL(mempool.size(), 0);
}

BOOST_AUTO_TEST_CASE(invalid_foreign_block_preserves_request_ownership)
{
    CNode owner(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "owner", true);
    CNode other(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "other", true);
    Headers(owner);
    Headers(other);
    BOOST_REQUIRE(SendMessages(&owner, false));
    const auto before = Stats(owner);
    BOOST_REQUIRE_EQUAL(before.nBlocksInFlight, 128);

    CBlock invalid = blocks[1];
    CMutableTransaction coinbase(invalid.vtx[0]);
    ++coinbase.vout[0].nValue;
    invalid.vtx[0] = CTransaction(coinbase);
    BOOST_REQUIRE(invalid.GetHash() == blocks[1].GetHash());
    CDataStream payload(SER_NETWORK, PROTOCOL_VERSION);
    payload << invalid;
    BOOST_REQUIRE(ProcessMessage(&other, "block", payload, GetTime()));
    CheckReject(other, "block", "bad-txnmrklroot", invalid.GetHash());

    const auto after = Stats(owner);
    BOOST_CHECK_EQUAL(after.nBlocksInFlight, before.nBlocksInFlight);
    BOOST_CHECK_EQUAL(after.nGlobalValidatedBlocksInFlight, before.nGlobalValidatedBlocksInFlight);
    BOOST_CHECK_EQUAL(after.nDownloadDeadline, before.nDownloadDeadline);
    BOOST_CHECK(after.hashOldestRequest == before.hashOldestRequest);
    BOOST_CHECK(after.vHeightInFlight == before.vHeightInFlight);
    BOOST_CHECK_EQUAL(chainActive.Height(), 0);

    // Valid cross-peer delivery still satisfies the original request.
    Deliver(other, 1);
    BOOST_CHECK_EQUAL(Stats(owner).nBlocksInFlight, 127);
    BOOST_CHECK_EQUAL(chainActive.Height(), 1);
}

BOOST_AUTO_TEST_CASE(invalid_owned_block_releases_request_for_reassignment)
{
    CNode owner(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "owner", true);
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "healthy", true);
    Headers(owner);
    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&owner, false));
    CBlock invalid = blocks[1];
    CMutableTransaction coinbase(invalid.vtx[0]);
    ++coinbase.vout[0].nValue;
    invalid.vtx[0] = CTransaction(coinbase);
    CDataStream payload(SER_NETWORK, PROTOCOL_VERSION);
    payload << invalid;
    BOOST_REQUIRE(ProcessMessage(&owner, "block", payload, GetTime()));
    CheckReject(owner, "block", "bad-txnmrklroot", invalid.GetHash());
    BOOST_CHECK_EQUAL(Stats(owner).nBlocksInFlight, 127);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    const auto reassigned = Stats(healthy);
    BOOST_REQUIRE_EQUAL(reassigned.nBlocksInFlight, 2);
    BOOST_CHECK_EQUAL(reassigned.vHeightInFlight.front(), 1);
    Deliver(healthy, 1);
    BOOST_CHECK_EQUAL(chainActive.Height(), 1);
}

BOOST_AUTO_TEST_CASE(disconnected_peer_releases_unlinked_block_source)
{
    CNode peer(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "source", true);
    Headers(peer);
    BOOST_REQUIRE(SendMessages(&peer, false));
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nTrackedBlockSources, 0);

    // Block 2 is requested and valid, but its parent body is still absent, so
    // it remains unlinked and retains source provenance until peer teardown.
    Deliver(peer, 2);
    BOOST_CHECK_EQUAL(chainActive.Height(), 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nTrackedBlockSources, 1);

    GetNodeSignals().DisconnectNode(peer.GetId());
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nTrackedBlockSources, 0);
    GetNodeSignals().FinalizeNode(peer.GetId()); // Deferred finalization is idempotent.
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nTrackedBlockSources, 0);
}

BOOST_AUTO_TEST_CASE(requested_unlinked_sources_are_bounded_and_connect_cleanup)
{
    CNode peer(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "source", true);
    Headers(peer);
    BOOST_REQUIRE(SendMessages(&peer, false));
    BOOST_REQUIRE_EQUAL(Stats(peer).nBlocksInFlight, 128);

    // The scheduler admits at most its 128-request window. Deliver every
    // requested child before its parent: attribution is needed while they are
    // unlinked, but cannot grow beyond the admitted bodies.
    for (size_t height = 2; height <= 128; ++height) {
        Deliver(peer, height);
    }
    BOOST_CHECK_EQUAL(chainActive.Height(), 0);
    BOOST_CHECK_EQUAL(Stats(peer).nBlocksInFlight, 1);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nTrackedBlockSources, 127);

    // Once the missing parent connects, all buffered descendants connect and
    // their source provenance is consumed by the existing chain path.
    Deliver(peer, 1);
    BOOST_CHECK_EQUAL(chainActive.Height(), 128);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nTrackedBlockSources, 0);
}

BOOST_AUTO_TEST_CASE(unrequested_far_ahead_block_does_not_retain_provenance)
{
    CNode peer(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "far-ahead", true);
    const std::vector<CBlockHeader> headers = ExtendedHeaders();
    Handshake(peer);
    BOOST_REQUIRE(SendMessages(&peer, false));
    HeaderBatch(peer, headers, 1, 160);
    HeaderBatch(peer, headers, 161, 160);
    BOOST_REQUIRE_EQUAL(chainActive.Height(), 0);
    BOOST_REQUIRE_EQUAL(GetBlockDownloadStats().nTrackedBlockSources, 0);

    // Original mainnet block 320. Its header has been accepted above, but its
    // body is 320 blocks ahead of our tip and was never requested. AcceptBlock
    // must ignore it without retaining a source entry for data it did not keep.
    const std::vector<unsigned char> bytes = ParseHex(
        "040000005c6d91c46d60e7c794cf12fdacb43f04475f383ae6a6592f6d4367842b0200004e3ed65c"
        "5994c39dfab31242e2f981e6de1ac89776d30453fcb125b4e0497d80000000000000000000000000"
        "0000000000000000000000000000000000000000f2131f582ad40e1e000000000000000000000000"
        "0413f8ce4b000010000000000000000000000000fd400500827efed1b6e06df8cb521be35babc586"
        "1b7be8b702ee61cada6a43bf93001115eb6f98adf39df530"
        "770494d357e04663f0ec9e75aa786580aea5379ac57612b39b79d3d244d146bcd51a9bbb301d9"
        "64f76e95504d506b183a786e9d445041e005ca659e637af81641f0029c2a337b377c6b303d6f1"
        "61698d9b9356e1cc106554ce78a03dbfdf3433cc05ce6a4906411b581c26ad745b5a93fa4b1a7"
        "6b27a90d0481b4ced3d125e051b9b41402e7eff9f2dd2ef4479a2767530b84f53054bc9f337cf"
        "07f6b271c2cf7bf99eea76fdb4ddc70f87db137e93b679af13f183d3215139143c18a38c1bc23"
        "4d93e084dbf821192debfa4eeb512fd3f8c4c0a320c842115686774ba1110256f5e98ab275ea0"
        "274cf9c4b729a0e56919f1a92275f3ed3770a25cfe53185cf3804d1de6a54fda4228aa9da9e1f"
        "621149c2d25a1df32accd1438fb54b5b787ed8b3a869a96631d00a2cfef64defddf4621111ab6"
        "9ef66eb85bd8e9771723452f8b1e3d6d4bc4cb5a025ed67b33663b00b509c912ab695ac053a9d"
        "a2193b8d057218bc01b366f216de26086cbf188b96bb51fa1c75cc9548295f16007413be40f8d"
        "8ddebb5790cfde518f5e806939fb51351315c7cf1e0b4160ab1365135f83851fe99774df0ad03"
        "968db9d4145580314afdbe877eabedc9bfa231159499995c461baea40d7edf64421f6b9021d8c"
        "250275d34fdbcbbddff45e919b45c8f5311946b597172513b229ab2119350e05f4c8f2e062e5"
        "a49678325609424f06c1c2e51c577bb2f5d89df1b0d9fb5b34fe38bf19e36672f397b08b6690b"
        "04588469fac3ea9d6070a5fefe2a10349970a0a0beed6e1a2b68c1a77980b5d66da1d92cf20d"
        "07dd20f83460228df7f1949451b56a3533d6c5c61fbbc91e95a714c2b567c7b0a5d2e81634eba"
        "6e8b45f67003399c6baa6bd2aefeeb8901a99f0fd89088cb7332141c3ccf6af5f67c59b50741c"
        "7871590571c8f598b269fa5d1222311d6395d522df8f7bc0a2cb6f374e522e0a4515e1189c8f"
        "5921b593c5c942d61ecd93069e64eb26db591a855cf97480b49246a1f1247a8b17ea6a4423dc"
        "2c1b41c58829947381d21f214db995a03455499311e52880277fc38271d5ea0ff5326853bd983"
        "150362d8f1b5b05887712910edd8b92b17019caf56e4dbfb4585c3595fc3e301b1e6901811ba0"
        "5ff3932b58aa660a9d45f33e2cb0764b8e41fcf9ae2a902125837522197566bdbd12210331fa0"
        "a12630a73531c314c41c583def599a72b93d1e85c4c0b33b89b10279b03970d662a359da81a30"
        "9ecd96f979debcf731e8418575ef735f94db76e080d38debc9b23dafd5969843608d97d959174"
        "7b495323b3f54478d964fb3cb0f5a51ee7c6d61d65b360792836c72c40ce6d3eb59a8787fd6b4"
        "057627bddf85702545dba42dc4927c05cc1e6d829464ac6299ab85d1ed5e4541410e1999b5c89"
        "629d6f0452e363b7393c0caa4c3ffd954625663161b42ea727151dfcaedc3b1e06e4425f58bd9"
        "162c372dbd9ef6102a14ede7db80c234c6e3d8878eeb16c6560db76f64708c8dd14643b384785"
        "621d2077df54c3c1162f37999586d9ed780da3d175ec4763792b96911bf68d0e1f0b2e98f902"
        "0fe76a92c7e00069a92c58a40c4ea132422a38a3f0051827289a1fe4e5ec0bd44f61e0822ef95"
        "d7cad43222389b47eaf7491c71fa5b4cf57c47ad2f91e64e517d04bc8264ebf4fff2f6834d4eb"
        "c46b15377d72d4349e9ed31299388cedaf943134b870290e5253c0980635db1cfd85260ae7fd6"
        "14d6232506caaa7fcff8b08b8b1b19c27208782dea43904d3a0b6730293ac790977843f2ea049"
        "39e2305247c532559975d2f928e3570caef4575aff1dfc671689657ab626bffef9306d01010000"
        "00010000000000000000000000000000000000000000000000000000000000000000ffffffff0402"
        "400100ffffffff01807c814a000000002321025ac17db0d2527e601e326dec296338565abbb25b"
        "20bc79636777d49140deaf70ac00000000");
    BOOST_REQUIRE_EQUAL(bytes.size(), 1587U);
    CDataStream payload(bytes, SER_NETWORK, PROTOCOL_VERSION);
    CBlock block;
    payload >> block;
    BOOST_REQUIRE(payload.empty());
    BOOST_REQUIRE(block.GetHash() == headers[320].GetHash());

    CDataStream message(SER_NETWORK, PROTOCOL_VERSION);
    message << block;
    BOOST_REQUIRE(ProcessMessage(&peer, "block", message, GetTime()));
    BOOST_CHECK_EQUAL(chainActive.Height(), 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nTrackedBlockSources, 0);
}

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
        SetClocks(start + second * 1000000LL);
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

BOOST_AUTO_TEST_CASE(preferred_peer_discovers_chain_while_inbound_holds_requests)
{
    CNode stalled(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "A", true);
    Handshake(stalled);
    Headers(stalled);
    BOOST_REQUIRE(SendMessages(&stalled, false));
    BOOST_REQUIRE_EQUAL(Stats(stalled).nBlocksInFlight, 128);
    BOOST_REQUIRE_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 1);

    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "B", false);
    Handshake(healthy);
    BOOST_REQUIRE(Stats(healthy).fPreferredDownload);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    // B only announces its chain after we request headers, as a normal peer
    // can do. A's existing sync role must not suppress that request.
    BOOST_REQUIRE_EQUAL(Sent(healthy, "getheaders"), 1);
    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_REQUIRE_EQUAL(Stats(healthy).nBlocksInFlight, 1);
    Deliver(healthy, 129);

    SetClocks(Stats(stalled).nDownloadDeadline + 1);
    BOOST_REQUIRE(SendMessages(&stalled, false));
    BOOST_REQUIRE(stalled.fDisconnect);
    BOOST_CHECK_EQUAL(Stats(stalled).nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
    // Reconnecting inbound peers are visited first, but cannot reclaim B's
    // abandoned work while a preferred download peer is connected.
    for (unsigned round = 0; round < 8; ++round) {
        CNode reconnect(INVALID_SOCKET, stalled.addr, "reconnect", true);
        Handshake(reconnect);
        Headers(reconnect);
        BOOST_REQUIRE(SendMessages(&reconnect, false));
        BOOST_CHECK_EQUAL(Stats(reconnect).nBlocksInFlight, 0);
        BOOST_CHECK_EQUAL(Sent(reconnect, "getheaders"), 0);
    }
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_REQUIRE_EQUAL(Stats(healthy).nBlocksInFlight, 128);
    for (size_t height = 1; height <= 128; ++height) Deliver(healthy, height);
    BOOST_CHECK_EQUAL(chainActive.Height(), 129);
    BOOST_CHECK(chainActive.Tip()->GetBlockHash() == blocks.back().GetHash());
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(Stats(healthy).nGlobalValidatedBlocksInFlight, 0);
}

BOOST_AUTO_TEST_CASE(preferred_header_sync_is_bounded_and_reassigned_on_disconnect)
{
    CNode inbound(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "inbound", true);
    Handshake(inbound);
    BOOST_REQUIRE(SendMessages(&inbound, false));
    BOOST_REQUIRE_EQUAL(Sent(inbound, "getheaders"), 1);

    CNode first(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "first", false);
    CNode second(INVALID_SOCKET, CAddress(CService("127.0.0.3", 3)), "second", false);
    Handshake(first);
    Handshake(second);
    BOOST_REQUIRE(SendMessages(&first, false));
    BOOST_REQUIRE_EQUAL(Sent(first, "getheaders"), 1);
    BOOST_REQUIRE(SendMessages(&second, false));
    BOOST_CHECK_EQUAL(Sent(second, "getheaders"), 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 2);

    GetNodeSignals().DisconnectNode(first.GetId());
    GetNodeSignals().DisconnectNode(first.GetId());
    BOOST_REQUIRE(SendMessages(&second, false));
    BOOST_CHECK_EQUAL(Sent(second, "getheaders"), 1);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 2);
    GetNodeSignals().FinalizeNode(first.GetId());
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 2);

    CNode client(INVALID_SOCKET, CAddress(CService("127.0.0.4", 4)), "client", false);
    Handshake(client, 0);
    BOOST_REQUIRE(SendMessages(&client, false));
    BOOST_CHECK(!Stats(client).fPreferredDownload);
    BOOST_CHECK_EQUAL(Sent(client, "getheaders"), 0);
    CNode oneShot(INVALID_SOCKET, CAddress(CService("127.0.0.5", 5)), "one-shot", false);
    oneShot.fOneShot = true;
    Handshake(oneShot);
    BOOST_REQUIRE(SendMessages(&oneShot, false));
    BOOST_CHECK(!Stats(oneShot).fPreferredDownload);
    BOOST_CHECK_EQUAL(Sent(oneShot, "getheaders"), 0);
}

BOOST_AUTO_TEST_CASE(unavailable_block_releases_downloads_for_immediate_takeover)
{
    CNode unavailable(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "A", false);
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "B", false);
    Handshake(unavailable);
    Headers(unavailable);
    BOOST_REQUIRE(SendMessages(&unavailable, false));
    BOOST_REQUIRE_EQUAL(Stats(unavailable).nBlocksInFlight, 128);
    Handshake(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_CHECK_EQUAL(Sent(healthy, "getheaders"), 0);

    CDataStream missing(SER_NETWORK, PROTOCOL_VERSION);
    missing << std::vector<CInv>{CInv(MSG_BLOCK, blocks[1].GetHash())};
    BOOST_REQUIRE(ProcessMessage(&unavailable, "notfound", missing, GetTime()));
    BOOST_REQUIRE(unavailable.fDisconnect);
    BOOST_CHECK_EQUAL(Stats(unavailable).nMisbehavior, 0);
    BOOST_CHECK_EQUAL(Stats(unavailable).nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nValidatedBlocksInFlight, 0);

    // A negative response is sufficient to try another source immediately;
    // neither the block timeout nor A's final reference needs to expire.
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_REQUIRE_EQUAL(Sent(healthy, "getheaders"), 1);
    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_REQUIRE_EQUAL(Stats(healthy).nBlocksInFlight, 128);
    CDataStream late(SER_NETWORK, PROTOCOL_VERSION);
    late << std::vector<CInv>{CInv(MSG_BLOCK, blocks[1].GetHash())};
    BOOST_REQUIRE(ProcessMessage(&unavailable, "notfound", late, GetTime()));
    GetNodeSignals().FinalizeNode(unavailable.GetId());
    BOOST_CHECK_EQUAL(Stats(healthy).nBlocksInFlight, 128);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nValidatedBlocksInFlight, 128);
    for (size_t height = 1; height <= 128; ++height) Deliver(healthy, height);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    Deliver(healthy, 129);
    BOOST_CHECK_EQUAL(chainActive.Height(), 129);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
}

BOOST_AUTO_TEST_CASE(notfound_cannot_cancel_another_peers_requests)
{
    CNode owner(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "owner", true);
    CNode other(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "other", true);
    Headers(owner);
    PrepareTransport(other);
    BOOST_REQUIRE(SendMessages(&owner, false));
    BOOST_REQUIRE_EQUAL(Stats(owner).nBlocksInFlight, 128);
    for (CNode* sender : {&owner, &other}) {
        CDataStream unrelated(SER_NETWORK, PROTOCOL_VERSION);
        unrelated << std::vector<CInv>{CInv(MSG_TX, blocks[1].GetHash()),
                                      CInv(MSG_BLOCK, uint256S("ff"))};
        BOOST_REQUIRE(ProcessMessage(sender, "notfound", unrelated, GetTime()));
        BOOST_CHECK(!sender->fDisconnect);
        BOOST_CHECK_EQUAL(Stats(owner).nBlocksInFlight, 128);
    }
    CDataStream forged(SER_NETWORK, PROTOCOL_VERSION);
    forged << std::vector<CInv>{CInv(MSG_BLOCK, blocks[1].GetHash())};
    BOOST_REQUIRE(ProcessMessage(&other, "notfound", forged, GetTime()));
    BOOST_CHECK(!other.fDisconnect);
    BOOST_CHECK(!owner.fDisconnect);
    BOOST_CHECK_EQUAL(Stats(owner).nBlocksInFlight, 128);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nValidatedBlocksInFlight, 128);
}

BOOST_AUTO_TEST_CASE(notfound_inventory_is_bounded_and_fully_decoded)
{
    CNode peer(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "missing", true);
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "healthy", true);
    const auto malformedNotFound = [&](CDataStream& payload) {
        Headers(peer);
        BOOST_REQUIRE(SendMessages(&peer, false));
        BOOST_REQUIRE_EQUAL(Stats(peer).nBlocksInFlight, 128);
        BOOST_CHECK(!ProcessMessage(&peer, "notfound", payload, GetTime()));
        BOOST_CHECK(peer.fDisconnect);
        BOOST_CHECK_EQUAL(Stats(peer).nBlocksInFlight, 0);
        BOOST_CHECK_EQUAL(GetBlockDownloadStats().nValidatedBlocksInFlight, 0);
        BOOST_CHECK_GE(Stats(peer).nMisbehavior, 20);
    };

    CDataStream oversized(SER_NETWORK, PROTOCOL_VERSION);
    WriteCompactSize(oversized, MAX_INV_SZ + 1);
    malformedNotFound(oversized);

    // Use a new owner after the malformed source's cleanup has completed.
    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_CHECK_EQUAL(Stats(healthy).nBlocksInFlight, 128);

    CDataStream truncated(SER_NETWORK, PROTOCOL_VERSION);
    WriteCompactSize(truncated, 2);
    truncated << CInv(MSG_BLOCK, blocks[1].GetHash()); // Second entry absent.
    BOOST_CHECK(!ProcessMessage(&healthy, "notfound", truncated, GetTime()));
    BOOST_CHECK(healthy.fDisconnect);
    BOOST_CHECK_EQUAL(Stats(healthy).nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nValidatedBlocksInFlight, 0);

    CNode trailing(INVALID_SOCKET, CAddress(CService("127.0.0.3", 3)), "trailing", true);
    Headers(trailing);
    BOOST_REQUIRE(SendMessages(&trailing, false));
    BOOST_REQUIRE_EQUAL(Stats(trailing).nBlocksInFlight, 128);
    CDataStream extra(SER_NETWORK, PROTOCOL_VERSION);
    extra << std::vector<CInv>{CInv(MSG_BLOCK, blocks[1].GetHash())};
    extra << uint8_t{0};
    BOOST_CHECK(!ProcessMessage(&trailing, "notfound", extra, GetTime()));
    BOOST_CHECK(trailing.fDisconnect);
    BOOST_CHECK_EQUAL(Stats(trailing).nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nValidatedBlocksInFlight, 0);
}

BOOST_AUTO_TEST_CASE(headers_trailing_bytes_do_not_advance_peer_availability)
{
    CNode peer(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "headers", true);
    PrepareTransport(peer);
    CDataStream malformed(SER_NETWORK, PROTOCOL_VERSION);
    WriteCompactSize(malformed, 1);
    malformed << blocks[1].GetBlockHeader();
    WriteCompactSize(malformed, 0);
    malformed << uint8_t{0};
    const auto before = Stats(peer);
    BOOST_CHECK(!ProcessMessage(&peer, "headers", malformed, GetTime()));
    const auto after = Stats(peer);
    BOOST_CHECK_EQUAL(after.nSyncHeight, before.nSyncHeight);
    BOOST_CHECK_EQUAL(after.nBlocksInFlight, before.nBlocksInFlight);
    BOOST_CHECK_GE(after.nMisbehavior - before.nMisbehavior, 20);
    BOOST_CHECK(peer.fDisconnect);
}

BOOST_AUTO_TEST_CASE(malformed_headers_release_requests_for_takeover)
{
    CNode malformed(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "malformed", true);
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "healthy", true);
    Headers(malformed);
    BOOST_REQUIRE(SendMessages(&malformed, false));
    BOOST_REQUIRE_EQUAL(Stats(malformed).nBlocksInFlight, 128);

    CDataStream payload(SER_NETWORK, PROTOCOL_VERSION);
    WriteCompactSize(payload, 1);
    payload << blocks[1].GetBlockHeader();
    WriteCompactSize(payload, 0);
    payload << uint8_t{0};
    BOOST_CHECK(!ProcessMessage(&malformed, "headers", payload, GetTime()));
    BOOST_REQUIRE(malformed.fDisconnect);
    BOOST_REQUIRE(SendMessages(&malformed, false));
    BOOST_CHECK_EQUAL(Stats(malformed).nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nValidatedBlocksInFlight, 0);

    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_CHECK_EQUAL(Stats(healthy).nBlocksInFlight, 128);
}

BOOST_AUTO_TEST_CASE(headers_nonzero_transaction_count_does_not_advance_peer_availability)
{
    CNode peer(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "headers", true);
    PrepareTransport(peer);
    CDataStream malformed(SER_NETWORK, PROTOCOL_VERSION);
    WriteCompactSize(malformed, 1);
    malformed << blocks[1].GetBlockHeader();
    WriteCompactSize(malformed, 1);
    const auto before = Stats(peer);
    BOOST_CHECK(!ProcessMessage(&peer, "headers", malformed, GetTime()));
    const auto after = Stats(peer);
    BOOST_CHECK_EQUAL(after.nSyncHeight, before.nSyncHeight);
    BOOST_CHECK_EQUAL(after.nBlocksInFlight, before.nBlocksInFlight);
    BOOST_CHECK_GE(after.nMisbehavior - before.nMisbehavior, 20);
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

BOOST_AUTO_TEST_CASE(invalid_wire_header_releases_requests_for_takeover)
{
    CNode malformed(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "malformed", true);
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "healthy", true);
    Headers(malformed);
    BOOST_REQUIRE(SendMessages(&malformed, false));
    BOOST_REQUIRE_EQUAL(Stats(malformed).nBlocksInFlight, 128);

    // A validly framed payload with an invalid command byte reaches the real
    // message-header validation branch before any command is dispatched.
    std::mt19937 random(0x48445245);
    FeedFragments(malformed, MalformedFrame(random, 4), random);
    BOOST_REQUIRE(malformed.fDisconnect);
    BOOST_REQUIRE(SendMessages(&malformed, false));
    BOOST_CHECK_EQUAL(Stats(malformed).nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nValidatedBlocksInFlight, 0);

    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_CHECK_EQUAL(Stats(healthy).nBlocksInFlight, 128);
}

BOOST_AUTO_TEST_CASE(invalid_wire_checksum_releases_requests_for_takeover)
{
    CNode malformed(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "malformed", true);
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "healthy", true);
    Headers(malformed);
    BOOST_REQUIRE(SendMessages(&malformed, false));
    BOOST_REQUIRE_EQUAL(Stats(malformed).nBlocksInFlight, 128);

    // The header and payload are otherwise valid, but the wire checksum does
    // not match. This reaches the framed checksum validator, not a command
    // decoder or block-validation path.
    std::mt19937 random(0x43484b53);
    FeedFragments(malformed, MalformedFrame(random, 1), random);
    BOOST_REQUIRE(malformed.fDisconnect);
    BOOST_REQUIRE(SendMessages(&malformed, false));
    BOOST_CHECK_EQUAL(Stats(malformed).nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nValidatedBlocksInFlight, 0);

    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_CHECK_EQUAL(Stats(healthy).nBlocksInFlight, 128);
}

BOOST_AUTO_TEST_CASE(truncated_block_frame_releases_requests_for_takeover)
{
    CNode malformed(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "malformed", true);
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "healthy", true);
    Headers(malformed);
    BOOST_REQUIRE(SendMessages(&malformed, false));
    BOOST_REQUIRE_EQUAL(Stats(malformed).nBlocksInFlight, 128);

    std::mt19937 random(0x424c4f43);
    FeedFragments(malformed, TruncatedPayloadFrame("block"), random);
    BOOST_REQUIRE(malformed.fDisconnect);
    BOOST_REQUIRE(SendMessages(&malformed, false));
    BOOST_CHECK_EQUAL(Stats(malformed).nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nValidatedBlocksInFlight, 0);

    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_REQUIRE_EQUAL(Stats(healthy).nBlocksInFlight, 128);
    for (size_t height = 1; height <= 128; ++height) Deliver(healthy, height);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    Deliver(healthy, 129);
    BOOST_CHECK_EQUAL(chainActive.Height(), 129);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
}

BOOST_AUTO_TEST_CASE(truncated_headers_frame_releases_header_role)
{
    CNode malformed(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "malformed", false);
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "healthy", false);
    Handshake(malformed);
    BOOST_REQUIRE(SendMessages(&malformed, false));
    BOOST_REQUIRE(Stats(malformed).fHeaderSyncStarted);
    BOOST_REQUIRE_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 1);

    std::mt19937 random(0x48445253);
    FeedFragments(malformed, TruncatedPayloadFrame("headers"), random);
    BOOST_REQUIRE(malformed.fDisconnect);
    BOOST_REQUIRE(SendMessages(&malformed, false));
    BOOST_CHECK(!Stats(malformed).fHeaderSyncStarted);
    BOOST_CHECK(Stats(malformed).fBlockDownloadStopped);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nHeaderSyncPeers, 0);

    Handshake(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_CHECK_EQUAL(Sent(healthy, "getheaders"), 1);
    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_REQUIRE_EQUAL(Stats(healthy).nBlocksInFlight, 128);
}

BOOST_AUTO_TEST_CASE(truncated_notfound_frame_releases_requests_for_takeover)
{
    CNode malformed(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "malformed", true);
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "healthy", true);
    Headers(malformed);
    BOOST_REQUIRE(SendMessages(&malformed, false));
    BOOST_REQUIRE_EQUAL(Stats(malformed).nBlocksInFlight, 128);

    // A declared one-entry reply with only its compact-size prefix reaches the
    // real framed-message dispatcher, then fails while decoding its CInv.
    std::mt19937 random(0x4e4f5446);
    FeedFragments(malformed, TruncatedPayloadFrame("notfound"), random);
    BOOST_REQUIRE(malformed.fDisconnect);
    BOOST_CHECK_EQUAL(Stats(malformed).nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nValidatedBlocksInFlight, 0);

    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_CHECK_EQUAL(Stats(healthy).nBlocksInFlight, 128);
}

BOOST_DATA_TEST_CASE(unsolicited_bootstrap_chunk_releases_requests_for_takeover,
                     boost::unit_test::data::make(std::vector<std::string>{
                         NetMsgType::BSCHK, NetMsgType::BSPCHK}), command)
{
    CNode unsolicited(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "unsolicited", true);
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "healthy", true);
    Headers(unsolicited);
    BOOST_REQUIRE(SendMessages(&unsolicited, false));
    BOOST_REQUIRE_EQUAL(Stats(unsolicited).nBlocksInFlight, 128);

    CBootstrapSnapshotChunk chunk;
    chunk.nFileIndex = 0;
    chunk.nOffset = 0;
    chunk.vData = {'x'};
    CDataStream payload(SER_NETWORK, PROTOCOL_VERSION);
    payload << chunk;
    std::mt19937 random(command == NetMsgType::BSCHK ? 0x42534348 : 0x42535043);
    FeedFragments(unsolicited, FramePayload(command.c_str(), payload), random);
    BOOST_REQUIRE(unsolicited.fDisconnect);
    BOOST_REQUIRE(SendMessages(&unsolicited, false));
    BOOST_CHECK_EQUAL(Stats(unsolicited).nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nValidatedBlocksInFlight, 0);

    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_CHECK_EQUAL(Stats(healthy).nBlocksInFlight, 128);
}

BOOST_DATA_TEST_CASE(unsolicited_bootstrap_manifest_releases_requests_for_takeover,
                     boost::unit_test::data::make(std::vector<std::string>{
                         NetMsgType::BSMAN, NetMsgType::BSPMAN}), command)
{
    CNode unsolicited(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "unsolicited", true);
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "healthy", true);
    Headers(unsolicited);
    BOOST_REQUIRE(SendMessages(&unsolicited, false));
    BOOST_REQUIRE_EQUAL(Stats(unsolicited).nBlocksInFlight, 128);

    // A complete, serializable manifest reaches the CNode extension handler.
    // Its contents are intentionally not trusted: the CNode path has no
    // bootstrap client and must release this unusable block source.
    CBootstrapSnapshotManifest manifest;
    CDataStream payload(SER_NETWORK, PROTOCOL_VERSION);
    payload << manifest;
    std::mt19937 random(command == NetMsgType::BSMAN ? 0x42534d41 : 0x4253504d);
    FeedFragments(unsolicited, FramePayload(command.c_str(), payload), random);
    BOOST_REQUIRE(unsolicited.fDisconnect);
    BOOST_REQUIRE(SendMessages(&unsolicited, false));
    BOOST_CHECK_EQUAL(Stats(unsolicited).nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nValidatedBlocksInFlight, 0);

    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_CHECK_EQUAL(Stats(healthy).nBlocksInFlight, 128);
}

BOOST_AUTO_TEST_CASE(malformed_inventory_releases_requests_for_takeover)
{
    CNode malformed(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "malformed", true);
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "healthy", true);
    Headers(malformed);
    BOOST_REQUIRE(SendMessages(&malformed, false));
    BOOST_REQUIRE_EQUAL(Stats(malformed).nBlocksInFlight, 128);

    // A valid frame that declares an inventory entry but omits it reaches the
    // command decoder. It must not leave this source owning its block window
    // until the ordinary download timeout.
    std::mt19937 random(0x494e5654);
    FeedFragments(malformed, TruncatedPayloadFrame("inv"), random);
    BOOST_REQUIRE(malformed.fDisconnect);
    BOOST_REQUIRE(SendMessages(&malformed, false));
    BOOST_CHECK_EQUAL(Stats(malformed).nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nValidatedBlocksInFlight, 0);

    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_CHECK_EQUAL(Stats(healthy).nBlocksInFlight, 128);
}

BOOST_AUTO_TEST_CASE(trailing_inventory_releases_requests_for_takeover)
{
    CNode malformed(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "malformed", true);
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "healthy", true);
    Headers(malformed);
    BOOST_REQUIRE(SendMessages(&malformed, false));
    BOOST_REQUIRE_EQUAL(Stats(malformed).nBlocksInFlight, 128);

    CDataStream payload(SER_NETWORK, PROTOCOL_VERSION);
    payload << std::vector<CInv>() << uint8_t{0};
    std::mt19937 random(0x494e5654);
    FeedFragments(malformed, FramePayload("inv", payload), random);
    BOOST_REQUIRE(malformed.fDisconnect);
    BOOST_REQUIRE(SendMessages(&malformed, false));
    BOOST_CHECK_EQUAL(Stats(malformed).nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nValidatedBlocksInFlight, 0);

    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_CHECK_EQUAL(Stats(healthy).nBlocksInFlight, 128);
}

BOOST_AUTO_TEST_CASE(malformed_nonresponse_releases_requests_for_takeover)
{
    CNode malformed(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "malformed", true);
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "healthy", true);
    Headers(malformed);
    BOOST_REQUIRE(SendMessages(&malformed, false));
    BOOST_REQUIRE_EQUAL(Stats(malformed).nBlocksInFlight, 128);

    // A malformed request is not a block response, but it is still a complete
    // protocol failure from a source that currently owns requested blocks.
    CDataStream payload(SER_NETWORK, PROTOCOL_VERSION);
    payload << CBlockLocator() << uint256() << uint8_t{0};
    std::mt19937 random(0x47455448);
    FeedFragments(malformed, FramePayload("getheaders", payload), random);
    BOOST_REQUIRE(malformed.fDisconnect);
    BOOST_REQUIRE(SendMessages(&malformed, false));
    BOOST_CHECK_EQUAL(Stats(malformed).nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nValidatedBlocksInFlight, 0);

    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_CHECK_EQUAL(Stats(healthy).nBlocksInFlight, 128);
}

BOOST_AUTO_TEST_CASE(inventory_send_abort_releases_requests_for_takeover)
{
    CNode overloaded(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "overloaded", true);
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "healthy", true);
    PrepareTransport(overloaded);
    SetMockTime(blocks.front().GetBlockTime() + 1);
    {
        ScopedSendBuffer sendBuffer;
        BOOST_REQUIRE_EQUAL(SendBufferSize(), 1000);
        CDataStream first(SER_NETWORK, PROTOCOL_VERSION);
        first << std::vector<CInv>{CInv(MSG_BLOCK, blocks[1].GetHash())};
        BOOST_REQUIRE(ProcessMessage(&overloaded, "inv", first, GetTime()));
        BOOST_REQUIRE_EQUAL(Stats(overloaded).nBlocksInFlight, 1);

        CDataStream payload(SER_NETWORK, PROTOCOL_VERSION);
        std::vector<CInv> inventory;
        for (size_t height = 2; height < blocks.size(); ++height)
            inventory.emplace_back(MSG_BLOCK, blocks[height].GetHash());
        payload << inventory;
        std::mt19937 random(0x494e5641);
        FeedFragments(overloaded, FramePayload("inv", payload), random);
    }
    SetMockTime(0);
    BOOST_REQUIRE(overloaded.fDisconnect);
    BOOST_REQUIRE(SendMessages(&overloaded, false));
    BOOST_CHECK_EQUAL(Stats(overloaded).nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nValidatedBlocksInFlight, 0);

    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    BOOST_CHECK_EQUAL(Stats(healthy).nBlocksInFlight, 128);
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
    SetClocks(start + 301000000LL);
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

BOOST_AUTO_TEST_CASE(block_timeout_saturates_at_int64_max)
{
    SetClocks(std::numeric_limits<int64_t>::max() - 1);
    CNode peer(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "boundary", true);
    Headers(peer, 1);
    BOOST_REQUIRE(SendMessages(&peer, false));
    BOOST_CHECK_EQUAL(Stats(peer).nDownloadDeadline,
                      std::numeric_limits<int64_t>::max());
}

BOOST_DATA_TEST_CASE(block_timeout_ignores_wall_clock_steps,
                    boost::unit_test::data::make({-3600, 3600}), wallStep)
{
    CNode peer(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)),
               "clock", true);
    Headers(peer, 1);
    BOOST_REQUIRE(SendMessages(&peer, false));
    const auto before = Stats(peer);
    BOOST_REQUIRE_GT(before.nDownloadDeadline, start);

    // Civil time must not decide whether an otherwise healthy in-flight
    // request timed out. Keep elapsed monotonic time one microsecond short
    // of the request deadline while moving wall time by an hour.
    SetMockTimeMicros(start + wallStep * 1000000LL);
    SetMockSteadyTimeMicros(before.nDownloadDeadline - 1);
    BOOST_REQUIRE(SendMessages(&peer, false));
    BOOST_CHECK(!peer.fDisconnect);
    BOOST_CHECK_EQUAL(Stats(peer).nDownloadDeadline, GetTimeMicros() + 1);

    SetMockSteadyTimeMicros(before.nDownloadDeadline + 1);
    BOOST_REQUIRE(SendMessages(&peer, false));
    BOOST_CHECK(peer.fDisconnect);
    BOOST_CHECK_EQUAL(Stats(peer).nBlocksInFlight, 0);
}

BOOST_DATA_TEST_CASE(block_window_stall_ignores_wall_clock_steps,
                    boost::unit_test::data::make({-3600, 3600}), wallStep)
{
    BlockWindowFixture branch;
    std::vector<std::unique_ptr<CNode>> owners;
    owners.reserve(BLOCK_DOWNLOAD_WINDOW / MAX_BLOCKS_IN_TRANSIT_PER_PEER);
    for (unsigned int count = 0;
         count < BLOCK_DOWNLOAD_WINDOW / MAX_BLOCKS_IN_TRANSIT_PER_PEER;
         ++count) {
        owners.emplace_back(new CNode(
            INVALID_SOCKET,
            CAddress(CService("127.0.0.1", static_cast<int>(count + 1))),
            "window-owner", false));
        CNode& owner = *owners.back();
        PrepareTransport(owner);
        CDataStream inventory(SER_NETWORK, PROTOCOL_VERSION);
        inventory << std::vector<CInv>{CInv(MSG_BLOCK, branch.Tip())};
        BOOST_REQUIRE(ProcessMessage(&owner, "inv", inventory, GetTime()));
        BOOST_REQUIRE(SendMessages(&owner, false));
        BOOST_REQUIRE_EQUAL(Stats(owner).nBlocksInFlight,
                            MAX_BLOCKS_IN_TRANSIT_PER_PEER);
    }
    BOOST_REQUIRE_EQUAL(GetBlockDownloadStats().nBlocksInFlight,
                        BLOCK_DOWNLOAD_WINDOW);

    CNode waiting(INVALID_SOCKET, CAddress(CService("127.0.0.2", 1)),
                  "window-waiting", false);
    PrepareTransport(waiting);
    CDataStream inventory(SER_NETWORK, PROTOCOL_VERSION);
    inventory << std::vector<CInv>{CInv(MSG_BLOCK, branch.Tip())};
    BOOST_REQUIRE(ProcessMessage(&waiting, "inv", inventory, GetTime()));
    BOOST_REQUIRE(SendMessages(&waiting, false));
    const auto stalled = Stats(*owners.front());
    BOOST_REQUIRE_NE(stalled.nStallingSince, 0);

    SetMockTimeMicros(start + wallStep * 1000000LL);
    SetMockSteadyTimeMicros(start + (BLOCK_STALLING_TIMEOUT - 1) * 1000000LL);
    BOOST_REQUIRE(SendMessages(owners.front().get(), false));
    BOOST_CHECK(!owners.front()->fDisconnect);
    BOOST_CHECK_EQUAL(Stats(*owners.front()).nStallingSince,
                      GetTimeMicros() - (BLOCK_STALLING_TIMEOUT - 1) * 1000000LL);

    SetMockSteadyTimeMicros(start + BLOCK_STALLING_TIMEOUT * 1000000LL + 1);
    BOOST_REQUIRE(SendMessages(owners.front().get(), false));
    BOOST_CHECK(owners.front()->fDisconnect);
    BOOST_CHECK_EQUAL(Stats(*owners.front()).nBlocksInFlight, 0);
}

BOOST_AUTO_TEST_CASE(receive_queue_size_accounts_message_overhead)
{
    CNode peer(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "queue-size", true);
    CNetMessage first(Params().MessageStart(), SER_NETWORK, PROTOCOL_VERSION);
    CNetMessage second(Params().MessageStart(), SER_NETWORK, PROTOCOL_VERSION);
    first.vRecv.resize(1024);
    second.vRecv.resize(2048);
    {
        LOCK(peer.cs_vRecvMsg);
        peer.vRecvMsg.push_back(first);
        peer.vRecvMsg.push_back(second);
        BOOST_CHECK_EQUAL(peer.GetTotalRecvSize(), 1024 + 2048 + 2 * 24);
        peer.vRecvMsg.clear();
    }
}

BOOST_AUTO_TEST_CASE(inventory_trailing_bytes_do_not_schedule_block_download)
{
    CNode peer(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "inv", true);
    PrepareTransport(peer);
    CDataStream malformed(SER_NETWORK, PROTOCOL_VERSION);
    malformed << std::vector<CInv>{CInv(MSG_BLOCK, blocks[1].GetHash())};
    malformed << uint8_t{0};
    const auto before = Stats(peer);
    const unsigned headersBefore = Sent(peer, "getheaders");
    const unsigned getdataBefore = Sent(peer, "getdata");
    BOOST_CHECK(!ProcessMessage(&peer, "inv", malformed, GetTime()));
    const auto after = Stats(peer);
    BOOST_CHECK_EQUAL(after.nBlocksInFlight, before.nBlocksInFlight);
    BOOST_CHECK_EQUAL(after.nGlobalBlocksInFlight, before.nGlobalBlocksInFlight);
    BOOST_CHECK_EQUAL(Sent(peer, "getheaders"), headersBefore);
    BOOST_CHECK_EQUAL(Sent(peer, "getdata"), getdataBefore);
    BOOST_CHECK_GE(after.nMisbehavior - before.nMisbehavior, 20);
}

BOOST_AUTO_TEST_CASE(getdata_trailing_bytes_do_not_queue_service_work)
{
    CNode peer(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "getdata", true);
    PrepareTransport(peer);
    CDataStream malformed(SER_NETWORK, PROTOCOL_VERSION);
    malformed << std::vector<CInv>();
    malformed << uint8_t{0};
    BOOST_CHECK(peer.vRecvGetData.empty());
    BOOST_CHECK(!ProcessMessage(&peer, "getdata", malformed, GetTime()));
    BOOST_CHECK(peer.vRecvGetData.empty());
    BOOST_CHECK_GE(Stats(peer).nMisbehavior, 20);
}

BOOST_AUTO_TEST_CASE(chain_request_trailing_bytes_do_not_enter_service)
{
    for (const std::string& command : {"getblocks", "getheaders"}) {
        CNode peer(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)),
                   command.c_str(), true);
        PrepareTransport(peer);
        CDataStream malformed(SER_NETWORK, PROTOCOL_VERSION);
        malformed << CBlockLocator() << uint256() << uint8_t{0};
        const auto before = Stats(peer);
        const unsigned invBefore = Sent(peer, "inv");
        const unsigned headersBefore = Sent(peer, "headers");
        BOOST_CHECK(!ProcessMessage(&peer, command, malformed, GetTime()));
        const auto after = Stats(peer);
        BOOST_CHECK_EQUAL(Sent(peer, "inv"), invBefore);
        BOOST_CHECK_EQUAL(Sent(peer, "headers"), headersBefore);
        BOOST_CHECK_EQUAL(after.nBlocksInFlight, before.nBlocksInFlight);
        BOOST_CHECK_EQUAL(after.nGlobalBlocksInFlight,
                          before.nGlobalBlocksInFlight);
        BOOST_CHECK_GE(after.nMisbehavior - before.nMisbehavior, 20);
    }
}

BOOST_AUTO_TEST_CASE(address_trailing_bytes_do_not_mutate_peer_discovery)
{
    CNode peer(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)),
               "addr", true);
    PrepareTransport(peer);
    CAddress advertised(CService("8.8.8.8", Params().GetDefaultPort()));
    advertised.nTime = GetAdjustedTime();
    CDataStream malformed(SER_NETWORK, PROTOCOL_VERSION);
    malformed << std::vector<CAddress>{advertised} << uint8_t{0};
    const size_t before = addrman.size();
    BOOST_CHECK(!ProcessMessage(&peer, "addr", malformed, GetTime()));
    BOOST_CHECK_EQUAL(addrman.size(), before);
    BOOST_CHECK_GE(Stats(peer).nMisbehavior, 20);
}

BOOST_AUTO_TEST_CASE(inventory_send_abort_releases_only_unsent_requests)
{
    CNode announced(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "inv", true);
    PrepareTransport(announced);
    SetMockTime(blocks.front().GetBlockTime() + 1);
    {
        ScopedSendBuffer sendBuffer;
        BOOST_REQUIRE_EQUAL(SendBufferSize(), 1000);

        // This request was actually queued before the later batch aborts.
        CDataStream first(SER_NETWORK, PROTOCOL_VERSION);
        first << std::vector<CInv>{CInv(MSG_BLOCK, blocks[1].GetHash())};
        BOOST_REQUIRE(ProcessMessage(&announced, "inv", first, GetTime()));
        BOOST_REQUIRE_EQUAL(Sent(announced, "getdata"), 1);
        const auto before = Stats(announced);
        BOOST_REQUIRE_EQUAL(before.nBlocksInFlight, 1);
        BOOST_REQUIRE(before.hashOldestRequest == blocks[1].GetHash());
        BOOST_REQUIRE_LT(announced.nSendSize, SendBufferSize());

        // Valid bounded inventory generates enough getheaders output to abort
        // before its accumulated getdata message can be queued.
        std::vector<CInv> inventory;
        for (size_t height = 2; height < blocks.size(); ++height)
            inventory.emplace_back(MSG_BLOCK, blocks[height].GetHash());
        CDataStream batch(SER_NETWORK, PROTOCOL_VERSION);
        batch << inventory;
        BOOST_CHECK(!ProcessMessage(&announced, "inv", batch, GetTime()));
        const auto after = Stats(announced);
        BOOST_TEST_MESSAGE("inv_abort_outstanding=" << after.nBlocksInFlight
                           << " getdata_frames=" << Sent(announced, "getdata"));
        BOOST_CHECK_EQUAL(after.nMisbehavior, 50);
        BOOST_CHECK(!announced.fDisconnect);
        BOOST_CHECK_EQUAL(Sent(announced, "getdata"), 1);
        BOOST_CHECK_EQUAL(after.nBlocksInFlight, 1);
        BOOST_CHECK_EQUAL(after.nGlobalBlocksInFlight, 1);
        BOOST_CHECK_EQUAL(after.nGlobalValidatedBlocksInFlight, 0);
        BOOST_CHECK(after.hashOldestRequest == before.hashOldestRequest);
        BOOST_CHECK_EQUAL(after.nDownloadDeadline, before.nDownloadDeadline);
    }
    SetMockTime(0);

    // Keep the first source alive. Unsent work is available immediately,
    // without waiting for its oldest correctly issued request to time out.
    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "healthy", true);
    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    const auto reassigned = Stats(healthy);
    BOOST_CHECK_EQUAL(reassigned.nBlocksInFlight, 128);
    BOOST_REQUIRE(!reassigned.vHeightInFlight.empty());
    BOOST_CHECK_EQUAL(reassigned.vHeightInFlight.front(), 2);
    BOOST_CHECK_EQUAL(reassigned.vHeightInFlight.back(), 129);
    Deliver(announced, 1);
    for (int height : reassigned.vHeightInFlight) Deliver(healthy, height);
    BOOST_CHECK_EQUAL(chainActive.Height(), 129);
    BOOST_CHECK(chainActive.Tip()->GetBlockHash() == blocks.back().GetHash());
    BOOST_CHECK_EQUAL(GetBlockDownloadStats().nBlocksInFlight, 0);
}

BOOST_DATA_TEST_CASE(inventory_requests_mix_with_validated_downloads,
                     boost::unit_test::data::make(std::vector<int>{16, 32, 64, 128}))
{
    nMaxBlocksInTransitPerPeer = sample;
    CNode announced(INVALID_SOCKET, CAddress(CService("127.0.0.1", 1)), "inv", true);
    PrepareTransport(announced);
    // Exercise the near-tip inventory fast path without inventing or mining
    // blocks. The hashes are announced before their headers are available.
    SetMockTime(blocks.front().GetBlockTime() + 1);
    std::vector<CInv> inventory;
    for (size_t height = 1; height < blocks.size(); ++height)
        inventory.emplace_back(MSG_BLOCK, blocks[height].GetHash());
    for (unsigned repeat = 0; repeat < 2; ++repeat) {
        CDataStream payload(SER_NETWORK, PROTOCOL_VERSION);
        payload << inventory;
        BOOST_REQUIRE(ProcessMessage(&announced, "inv", payload, GetTime()));
        BOOST_CHECK_EQUAL(Stats(announced).nBlocksInFlight, sample);
        BOOST_CHECK_EQUAL(Stats(announced).nValidatedBlocksInFlight, 0);
        BOOST_CHECK_EQUAL(Stats(announced).nGlobalBlocksInFlight, sample);
        BOOST_CHECK_EQUAL(Stats(announced).nGlobalValidatedBlocksInFlight, 0);
    }
    SetMockTime(0);
    Deliver(announced, 1);
    Deliver(announced, 1); // Duplicate receipt of an unvalidated request.
    BOOST_REQUIRE_EQUAL(chainActive.Height(), 1);
    BOOST_CHECK_EQUAL(Stats(announced).nBlocksInFlight, sample - 1);

    CNode healthy(INVALID_SOCKET, CAddress(CService("127.0.0.2", 2)), "headers", true);
    Headers(healthy);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    const auto laterHeights = Stats(healthy).vHeightInFlight;
    BOOST_REQUIRE_EQUAL(laterHeights.size(), std::min(sample, 129 - sample));
    BOOST_CHECK_EQUAL(Stats(healthy).nGlobalBlocksInFlight, sample - 1 + laterHeights.size());
    BOOST_CHECK_EQUAL(Stats(healthy).nGlobalValidatedBlocksInFlight, laterHeights.size());

    GetNodeSignals().DisconnectNode(announced.GetId());
    GetNodeSignals().DisconnectNode(announced.GetId());
    GetNodeSignals().FinalizeNode(announced.GetId());
    BOOST_CHECK_EQUAL(Stats(healthy).nGlobalBlocksInFlight, laterHeights.size());
    BOOST_CHECK_EQUAL(Stats(healthy).nGlobalValidatedBlocksInFlight, laterHeights.size());
    for (int height : laterHeights) Deliver(healthy, height);
    BOOST_REQUIRE(SendMessages(&healthy, false));
    const auto takeover = Stats(healthy).vHeightInFlight;
    BOOST_REQUIRE(!takeover.empty());
    BOOST_CHECK_LE(takeover.size(), sample);
    BOOST_CHECK_EQUAL(takeover.front(), 2);
    for (int height : takeover) Deliver(healthy, height);
    BOOST_CHECK_EQUAL(chainActive.Height(), std::min(2 * sample + 1, 129));
    BOOST_CHECK_EQUAL(Stats(healthy).nGlobalBlocksInFlight, 0);
    BOOST_CHECK_EQUAL(Stats(healthy).nGlobalValidatedBlocksInFlight, 0);
}

BOOST_AUTO_TEST_SUITE_END()
