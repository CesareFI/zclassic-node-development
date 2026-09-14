// Copyright (c) 2026 The Zclassic developers
// Distributed under the MIT software license, see COPYING.

#include "chainparams.h"
#include "consensus/validation.h"
#include "main.h"
#include "streams.h"
#include "test/test_bitcoin.h"
#include "ui_interface.h"
#include "version.h"

#include <boost/test/unit_test.hpp>
#include <algorithm>
#include <fstream>
#include <vector>

namespace {
struct VerifyDBSetup : TestingSetup {
    const size_t savedCache = nCoinCacheUsage;
    uint256 coinbase;

    VerifyDBSetup() { nCoinCacheUsage = 64 * 1024 * 1024; }
    ~VerifyDBSetup()
    {
        SetShutdownRequestedForTest(false);
        nCoinCacheUsage = savedCache;
    }

    void LoadChain()
    {
        const auto path = boost::filesystem::path(BOOST_PP_STRINGIZE(TEST_DATA_DIR)) /
                          "zclassic-download-130.dat";
        std::ifstream file(path.string(), std::ios::binary | std::ios::ate);
        BOOST_REQUIRE(file.good());
        BOOST_REQUIRE_EQUAL(file.tellg(), 207319);
        file.seekg(0);
        std::vector<char> bytes(207319);
        BOOST_REQUIRE(file.read(bytes.data(), bytes.size()));
        CDataStream stream(bytes, SER_DISK, PROTOCOL_VERSION);
        unsigned count = 0;
        uint256 previous;
        while (!stream.empty()) {
            BOOST_REQUIRE_LT(count, 130);
            unsigned char magic[4];
            stream.read(reinterpret_cast<char*>(magic), sizeof(magic));
            BOOST_REQUIRE(std::equal(magic, magic + sizeof(magic), Params().MessageStart()));
            uint32_t size;
            stream >> size;
            BOOST_REQUIRE_LE(size, stream.size());
            const size_t before = stream.size();
            CBlock block;
            stream >> block;
            BOOST_REQUIRE_EQUAL(before - stream.size(), size);
            if (count == 0) {
                BOOST_REQUIRE(block.GetHash() == Params().GetConsensus().hashGenesisBlock);
            } else {
                BOOST_REQUIRE(block.hashPrevBlock == previous);
                CValidationState state;
                BOOST_REQUIRE_MESSAGE(ProcessNewBlock(state, nullptr, &block, true, nullptr),
                                      state.GetRejectReason());
            }
            BOOST_REQUIRE(!block.vtx.empty());
            previous = block.GetHash();
            coinbase = block.vtx.front().GetHash();
            ++count;
        }
        BOOST_REQUIRE_EQUAL(count, 130);
        BOOST_REQUIRE_EQUAL(chainActive.Height(), 129);
        BOOST_REQUIRE(pcoinsTip->Flush());
    }
};
} // namespace

BOOST_FIXTURE_TEST_SUITE(verifydb_tests, VerifyDBSetup)

BOOST_AUTO_TEST_CASE(cancellation_during_reconnect_preserves_database)
{
    LoadChain();
    const uint256 tip = chainActive.Tip()->GetBlockHash();
    CCoins original;
    BOOST_REQUIRE(pcoinsdbview->GetCoins(coinbase, original));
    unsigned reconnectProgress = 0;
    {
        boost::signals2::scoped_connection progress(uiInterface.ShowProgress.connect(
            [&](const std::string& title, int percentage) {
                if (!title.empty() && percentage >= 50) {
                    ++reconnectProgress;
                    SetShutdownRequestedForTest(true);
                }
            }));
        BOOST_CHECK(CVerifyDB().VerifyDB(pcoinsdbview, 4, 0));
    }
    BOOST_CHECK_EQUAL(reconnectProgress, 1);
    BOOST_CHECK(chainActive.Tip()->GetBlockHash() == tip);
    BOOST_CHECK(pcoinsdbview->GetBestBlock() == tip);
    CCoins after;
    BOOST_REQUIRE(pcoinsdbview->GetCoins(coinbase, after));
    BOOST_CHECK(original == after);

    SetShutdownRequestedForTest(false);
    std::vector<std::string> warmupMessages;
    {
        boost::signals2::scoped_connection messages(uiInterface.InitMessage.connect(
            [&](const std::string& message) { warmupMessages.push_back(message); }));
        BOOST_CHECK(CVerifyDB().VerifyDB(pcoinsdbview, 4, 0));
    }
    BOOST_REQUIRE_EQUAL(warmupMessages.size(), 99);
    BOOST_CHECK(warmupMessages.front().find("(1%)") != std::string::npos);
    BOOST_CHECK(warmupMessages.back().find("(99%)") != std::string::npos);
    BOOST_CHECK(std::adjacent_find(warmupMessages.begin(), warmupMessages.end()) ==
                warmupMessages.end());
}

BOOST_AUTO_TEST_SUITE_END()
