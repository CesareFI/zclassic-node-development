// Copyright (c) 2026 The Zclassic developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#ifndef ZCLASSIC_CRYPTO_SHA256STREAM_H
#define ZCLASSIC_CRYPTO_SHA256STREAM_H

#include <openssl/evp.h>

#include <algorithm>
#include <array>
#include <istream>
#include <memory>
#include <vector>

/** Hash every remaining byte of a stream using libcrypto's SHA-256 backend.
 * The caller owns the stream. Digest is cleared on failure; read failures must
 * never be confused with EOF and accepted as a hash of a truncated file.
 * This helper is for file integrity checks, not consensus serialization.
 */
inline bool SHA256Stream(std::istream& input, std::array<unsigned char, 32>& digest)
{
    digest.fill(0);
    if (!input.good()) return false;
    struct ContextDeleter {
        void operator()(EVP_MD_CTX* context) const { EVP_MD_CTX_destroy(context); }
    };
    // create/destroy also support the older libcrypto versions used by this tree.
    std::unique_ptr<EVP_MD_CTX, ContextDeleter> context(EVP_MD_CTX_create());
    if (!context || EVP_DigestInit_ex(context.get(), EVP_sha256(), nullptr) != 1)
        return false;

    std::vector<char> buffer(256 * 1024);
    while (input) {
        input.read(buffer.data(), buffer.size());
        const std::streamsize count = input.gcount();
        if (count > 0 && EVP_DigestUpdate(context.get(), buffer.data(), static_cast<size_t>(count)) != 1)
            return false;
    }
    if (!input.eof() || input.bad()) return false;

    std::array<unsigned char, EVP_MAX_MD_SIZE> result;
    unsigned int length = 0;
    if (EVP_DigestFinal_ex(context.get(), result.data(), &length) != 1 || length != digest.size())
        return false;
    std::copy_n(result.begin(), digest.size(), digest.begin());
    return true;
}

#endif // ZCLASSIC_CRYPTO_SHA256STREAM_H
