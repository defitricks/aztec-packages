#include "barretenberg/crypto/merkle_tree/lmdb_store/callbacks.hpp"
#include "barretenberg/numeric/uint256/uint256.hpp"
#include "lmdb.h"
#include <algorithm>
#include <cstdint>
#include <cstring>
#include <functional>
#include <vector>

namespace bb::crypto::merkle_tree {
void throw_error(const std::string& errorString, int error)
{
    std::stringstream ss;
    ss << errorString << ": " << error << " - " << mdb_strerror(error) << std::endl;
    throw std::runtime_error(ss.str());
}

std::vector<uint8_t> serialise_key(uint8_t key)
{
    return { key };
}

void deserialise_key(void* data, uint8_t& key)
{
    uint8_t* p = static_cast<uint8_t*>(data);
    key = *p;
}

// 64 bit integers are stored in little endian byte order
std::vector<uint8_t> serialise_key(uint64_t key)
{
    uint64_t le = key;
    const uint8_t* p = reinterpret_cast<uint8_t*>(&le);
    return std::vector<uint8_t>(p, p + sizeof(key));
}

void deserialise_key(void* data, uint64_t& key)
{
    uint64_t le = 0;
    std::memcpy(&le, data, sizeof(le));
    key = le;
}

std::vector<uint8_t> serialise_key(uint256_t key)
{
    std::vector<uint8_t> buf(32);
    std::memcpy(buf.data(), key.data, 32);
    return buf;
}

void deserialise_key(void* data, uint256_t& key)
{
    std::memcpy(key.data, data, 32);
}

int size_cmp(const MDB_val* a, const MDB_val* b)
{
    if (a->mv_size < b->mv_size) {
        return -1;
    }
    if (a->mv_size > b->mv_size) {
        return 1;
    }
    return 0;
}

std::vector<uint8_t> mdb_val_to_vector(const MDB_val& dbVal)
{
    const uint8_t* p = static_cast<uint8_t*>(dbVal.mv_data);
    return std::vector<uint8_t>(p, p + dbVal.mv_size);
}

void copy_to_vector(const MDB_val& dbVal, std::vector<uint8_t>& target)
{
    std::vector<uint8_t> temp = mdb_val_to_vector(dbVal);
    target.swap(temp);
}
} // namespace bb::crypto::merkle_tree