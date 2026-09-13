// Copyright (c) 2026 The Zclassic developers
// Distributed under the MIT software license, see COPYING.

#include "addrman.h"
#include "net.h"
#include "test/test_bitcoin.h"
#include "util.h"

#include <boost/test/unit_test.hpp>
#include <fstream>

namespace {
struct AddrDBSetup : BasicTestingSetup {
    const bool hadDatadir = mapArgs.count("-datadir") != 0;
    const std::string savedDatadir = GetArg("-datadir", "");
    const boost::filesystem::path directory =
        GetTempPath() / boost::filesystem::unique_path("zcl-addrdb-%%%%%%%%");
    const boost::filesystem::path path = directory / "peers.dat";

    AddrDBSetup()
    {
        boost::filesystem::create_directories(directory);
        mapArgs["-datadir"] = directory.string();
        ClearDatadirCache();
    }

    ~AddrDBSetup()
    {
        if (hadDatadir) mapArgs["-datadir"] = savedDatadir;
        else mapArgs.erase("-datadir");
        ClearDatadirCache();
        boost::filesystem::remove_all(directory);
    }

    void WriteBytes(size_t size)
    {
        std::ofstream file(path.string(), std::ios::binary | std::ios::trunc);
        BOOST_REQUIRE(file.good());
        const std::vector<char> bytes(size, 0);
        if (!bytes.empty()) file.write(bytes.data(), bytes.size());
        BOOST_REQUIRE(file.good());
    }
};
}

BOOST_FIXTURE_TEST_SUITE(addrdb_tests, AddrDBSetup)

BOOST_AUTO_TEST_CASE(valid_address_database_roundtrip)
{
    CAddrMan original;
    const CAddress address(CService("250.1.2.3", 8033));
    BOOST_REQUIRE(original.Add(address, CNetAddr("250.4.5.6")));
    CAddrDB db;
    BOOST_REQUIRE(db.Write(original));
    CAddrMan loaded;
    BOOST_REQUIRE(db.Read(loaded));
    BOOST_CHECK_EQUAL(loaded.size(), 1);
    BOOST_CHECK_EQUAL(loaded.Select().ToString(), address.ToString());
}

BOOST_AUTO_TEST_CASE(short_files_are_rejected)
{
    CAddrDB db;
    CAddrMan loaded;
    for (size_t size : {0, 1, 31, 32, 33, 35}) {
        WriteBytes(size);
        BOOST_CHECK(!db.Read(loaded));
    }
}

BOOST_AUTO_TEST_CASE(missing_and_directory_paths_fail_without_exceptions)
{
    CAddrMan loaded;
    CAddrDB db;
    BOOST_CHECK(!db.Read(loaded));
    boost::filesystem::create_directory(path);
    BOOST_CHECK(!db.Read(loaded));
}

BOOST_AUTO_TEST_CASE(corrupt_checksum_preserves_existing_addresses)
{
    CAddrDB db;
    CAddrMan empty;
    BOOST_REQUIRE(db.Write(empty));
    const auto size = boost::filesystem::file_size(path);
    std::fstream file(path.string(), std::ios::binary | std::ios::in | std::ios::out);
    BOOST_REQUIRE(file.good());
    file.seekg(size - 1);
    char byte;
    file.read(&byte, 1);
    BOOST_REQUIRE(file.good());
    byte ^= 1;
    file.seekp(size - 1);
    file.write(&byte, 1);
    file.close();
    CAddrMan loaded;
    BOOST_REQUIRE(loaded.Add(CAddress(CService("250.1.2.3", 8033)), CNetAddr("250.4.5.6")));
    BOOST_CHECK(!db.Read(loaded));
    BOOST_CHECK_EQUAL(loaded.size(), 1);
}

#ifndef WIN32 // POSIX resize extends sparse files without allocating their holes.
BOOST_AUTO_TEST_CASE(large_sparse_file_cannot_wrap_to_a_valid_prefix)
{
    CAddrMan empty;
    CAddrDB db;
    BOOST_REQUIRE(db.Write(empty));
    const auto size = boost::filesystem::file_size(path);
    boost::filesystem::resize_file(path, (uint64_t{1} << 32) + size);
    CAddrMan loaded;
    BOOST_CHECK(!db.Read(loaded));
}

BOOST_AUTO_TEST_CASE(oversized_peer_file_is_rejected)
{
    WriteBytes(1);
    boost::filesystem::resize_file(path, uint64_t{MAX_SIZE} + 36);
    CAddrMan loaded;
    CAddrDB db;
    BOOST_CHECK(!db.Read(loaded));
}
#endif

BOOST_AUTO_TEST_SUITE_END()
