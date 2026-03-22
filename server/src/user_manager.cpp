#include "user_manager.hpp"
#include <sodium.h>
#include <openssl/sha.h>
#include <sstream>
#include <iomanip>
#include <cstring>

namespace chat {

UserManager::UserManager(std::shared_ptr<Database> database)
    : database_(database) {
    // 初始化 libsodium
    if (sodium_init() < 0) {
        throw std::runtime_error("Failed to initialize libsodium");
    }
}

// 旧的 SHA256 哈希函数（仅用于迁移验证）
static std::string hash_password_sha256(const std::string& password) {
    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256(reinterpret_cast<const unsigned char*>(password.c_str()),
           password.size(), hash);

    std::stringstream ss;
    for (int i = 0; i < SHA256_DIGEST_LENGTH; ++i) {
        ss << std::hex << std::setw(2) << std::setfill('0') << static_cast<int>(hash[i]);
    }
    return ss.str();
}

// 检测密码哈希类型
static bool is_argon2_hash(const std::string& hash) {
    return hash.size() > 10 && hash.substr(0, 9) == "$argon2id";
}

std::string UserManager::hash_password(const std::string& password) {
    char hashed[crypto_pwhash_STRBYTES];

    if (crypto_pwhash_str(
            hashed,
            password.c_str(),
            password.size(),
            crypto_pwhash_OPSLIMIT_INTERACTIVE,
            crypto_pwhash_MEMLIMIT_INTERACTIVE) != 0) {
        throw std::runtime_error("Failed to hash password with Argon2");
    }

    return std::string(hashed);
}

bool UserManager::verify_password(const std::string& password, const std::string& hash) {
    if (is_argon2_hash(hash)) {
        // 新格式：Argon2
        return crypto_pwhash_str_verify(hash.c_str(), password.c_str(), password.size()) == 0;
    } else {
        // 旧格式：SHA256（用于迁移）
        return hash_password_sha256(password) == hash;
    }
}

bool UserManager::register_user(const std::string& username, const std::string& password,
                                const std::string& nickname, uint64_t& user_id,
                                std::string& error) {
    // 检查用户名是否已存在
    UserInfo existing_user;
    if (database_->get_user_by_username(username, existing_user)) {
        error = "Username already exists";
        return false;
    }
    
    // 哈希密码
    std::string hashed_password = hash_password(password);
    
    // 创建用户
    if (!database_->create_user(username, hashed_password, nickname, user_id)) {
        error = "Failed to create user";
        return false;
    }
    
    return true;
}

bool UserManager::login(const std::string& username, const std::string& password,
                        uint64_t& user_id, UserInfo& user_info, std::string& error) {
    // 获取用户信息
    if (!database_->get_user_by_username(username, user_info)) {
        error = "User not found";
        return false;
    }

    // 获取密码哈希
    std::string stored_hash;
    if (!database_->get_user_password_hash(username, stored_hash)) {
        error = "Failed to retrieve password";
        return false;
    }

    // 验证密码（支持旧的 SHA256 和新的 Argon2）
    if (!verify_password(password, stored_hash)) {
        error = "Invalid password";
        return false;
    }

    user_id = user_info.user_id;

    // 渐进式迁移：如果用户使用旧的 SHA256 密码，自动升级到 Argon2
    if (!is_argon2_hash(stored_hash)) {
        try {
            std::string new_hash = hash_password(password);
            database_->update_user_password(user_id, new_hash);
        } catch (const std::exception& e) {
            // 升级失败不影响登录，只记录错误
            // 在生产环境中应该记录到日志
        }
    }

    return true;
}

bool UserManager::get_user_info(uint64_t user_id, UserInfo& user) {
    return database_->get_user_by_id(user_id, user);
}

bool UserManager::update_user_info(const UserInfo& user) {
    return database_->update_user(user);
}

bool UserManager::update_password(uint64_t user_id, const std::string& old_password,
                                  const std::string& new_password, std::string& error) {
    UserInfo user;
    if (!database_->get_user_by_id(user_id, user)) {
        error = "User not found";
        return false;
    }

    // 获取密码哈希
    std::string stored_hash;
    if (!database_->get_user_password_hash(user.username, stored_hash)) {
        error = "Failed to retrieve password";
        return false;
    }

    // 验证旧密码（支持旧的 SHA256 和新的 Argon2）
    if (!verify_password(old_password, stored_hash)) {
        error = "Invalid old password";
        return false;
    }

    // 更新密码（使用新的 Argon2 格式）
    std::string hashed_new = hash_password(new_password);
    return database_->update_user_password(user_id, hashed_new);
}

std::vector<UserInfo> UserManager::search_users(const std::string& keyword, int limit) {
    return database_->search_users(keyword, limit);
}

bool UserManager::set_online_status(uint64_t user_id, OnlineStatus status) {
    return database_->update_user_online_status(user_id, status);
}

} // namespace chat
