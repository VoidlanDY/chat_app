#include "database_pool.hpp"
#include <algorithm>
#include <thread>

namespace chat {

// ==================== DatabaseConnection 实现 ====================

DatabaseConnection::DatabaseConnection()
    : connection_(nullptr)
    , in_use_(false)
    , last_used_(std::chrono::steady_clock::now()) {
}

DatabaseConnection::~DatabaseConnection() {
    if (connection_) {
        mysql_close(connection_);
        connection_ = nullptr;
    }
}

DatabaseConnection::DatabaseConnection(DatabaseConnection&& other) noexcept
    : connection_(other.connection_)
    , in_use_(other.in_use_)
    , last_used_(other.last_used_)
    , config_(std::move(other.config_)) {
    other.connection_ = nullptr;
    other.in_use_ = false;
}

DatabaseConnection& DatabaseConnection::operator=(DatabaseConnection&& other) noexcept {
    if (this != &other) {
        if (connection_) {
            mysql_close(connection_);
        }
        connection_ = other.connection_;
        in_use_ = other.in_use_;
        last_used_ = other.last_used_;
        config_ = std::move(other.config_);
        other.connection_ = nullptr;
        other.in_use_ = false;
    }
    return *this;
}

bool DatabaseConnection::connect(const DatabaseConfig& config) {
    config_ = config;
    
    // 初始化连接
    connection_ = mysql_init(nullptr);
    if (!connection_) {
        std::cerr << "[DatabaseConnection] mysql_init failed" << std::endl;
        return false;
    }
    
    // 设置连接选项
    bool reconnect = true;
    mysql_options(connection_, MYSQL_OPT_RECONNECT, &reconnect);
    mysql_options(connection_, MYSQL_SET_CHARSET_NAME, config.charset.c_str());
    mysql_options(connection_, MYSQL_OPT_CONNECT_TIMEOUT, &config.connect_timeout);
    mysql_options(connection_, MYSQL_OPT_READ_TIMEOUT, &config.read_timeout);
    mysql_options(connection_, MYSQL_OPT_WRITE_TIMEOUT, &config.write_timeout);
    
    // 连接数据库
    MYSQL* conn = mysql_real_connect(
        connection_,
        config.host.c_str(),
        config.user.c_str(),
        config.password.c_str(),
        config.database.c_str(),
        config.port,
        nullptr,
        CLIENT_MULTI_STATEMENTS
    );
    
    if (!conn) {
        std::cerr << "[DatabaseConnection] mysql_real_connect failed: " 
                  << mysql_error(connection_) << std::endl;
        mysql_close(connection_);
        connection_ = nullptr;
        return false;
    }
    
    touch();
    return true;
}

bool DatabaseConnection::is_valid() const {
    if (!connection_) return false;
    return mysql_ping(connection_) == 0;
}

bool DatabaseConnection::query(const std::string& sql) {
    if (!connection_) return false;
    
    touch();
    
    if (mysql_query(connection_, sql.c_str()) != 0) {
        // 如果连接断开，尝试重连
        if (mysql_errno(connection_) == CR_SERVER_LOST ||
            mysql_errno(connection_) == CR_SERVER_GONE_ERROR) {
            std::cerr << "[DatabaseConnection] Connection lost, attempting reconnect..." << std::endl;
            
            // 关闭并重新连接
            mysql_close(connection_);
            connection_ = mysql_init(nullptr);
            if (!connection_) return false;
            
            bool reconnect = true;
            mysql_options(connection_, MYSQL_OPT_RECONNECT, &reconnect);
            mysql_options(connection_, MYSQL_SET_CHARSET_NAME, config_.charset.c_str());
            mysql_options(connection_, MYSQL_OPT_CONNECT_TIMEOUT, &config_.connect_timeout);
            mysql_options(connection_, MYSQL_OPT_READ_TIMEOUT, &config_.read_timeout);
            mysql_options(connection_, MYSQL_OPT_WRITE_TIMEOUT, &config_.write_timeout);
            
            MYSQL* conn = mysql_real_connect(
                connection_,
                config_.host.c_str(),
                config_.user.c_str(),
                config_.password.c_str(),
                config_.database.c_str(),
                config_.port,
                nullptr,
                CLIENT_MULTI_STATEMENTS
            );
            
            if (!conn) {
                std::cerr << "[DatabaseConnection] Reconnect failed" << std::endl;
                return false;
            }
            
            // 重试查询
            if (mysql_query(connection_, sql.c_str()) != 0) {
                return false;
            }
        } else {
            return false;
        }
    }
    
    return true;
}

MYSQL_RES* DatabaseConnection::store_result() {
    if (!connection_) return nullptr;
    return mysql_store_result(connection_);
}

uint64_t DatabaseConnection::affected_rows() {
    if (!connection_) return 0;
    return mysql_affected_rows(connection_);
}

uint64_t DatabaseConnection::insert_id() {
    if (!connection_) return 0;
    return mysql_insert_id(connection_);
}

std::string DatabaseConnection::error() const {
    if (!connection_) return "No connection";
    return mysql_error(connection_);
}

unsigned int DatabaseConnection::error_code() const {
    if (!connection_) return 0;
    return mysql_errno(connection_);
}

std::string DatabaseConnection::escape_string(const std::string& str) {
    if (!connection_) return str;
    
    std::string escaped;
    escaped.resize(str.length() * 2 + 1);
    
    size_t len = mysql_real_escape_string(connection_, 
                                          &escaped[0], 
                                          str.c_str(), 
                                          str.length());
    escaped.resize(len);
    
    return escaped;
}

bool DatabaseConnection::ping() {
    if (!connection_) return false;
    return mysql_ping(connection_) == 0;
}

// ==================== DatabasePool 实现 ====================

DatabasePool::DatabasePool(const DatabaseConfig& db_config, const PoolConfig& pool_config)
    : db_config_(db_config)
    , pool_config_(pool_config) {
}

DatabasePool::~DatabasePool() {
    shutdown();
}

bool DatabasePool::init() {
    std::lock_guard<std::mutex> lock(mutex_);
    
    if (initialized_) {
        return true;
    }
    
    // 初始化 MySQL 库
    if (mysql_library_init(0, nullptr, nullptr) != 0) {
        std::cerr << "[DatabasePool] mysql_library_init failed" << std::endl;
        return false;
    }
    
    // 创建最小数量的连接
    for (size_t i = 0; i < pool_config_.min_connections; ++i) {
        auto conn = create_connection();
        if (!conn) {
            std::cerr << "[DatabasePool] Failed to create initial connection " << i << std::endl;
            // 继续尝试创建其他连接
        } else {
            idle_connections_.push(conn);
            all_connections_.push_back(conn);
        }
    }
    
    if (all_connections_.empty()) {
        std::cerr << "[DatabasePool] Failed to create any database connections" << std::endl;
        mysql_library_end();
        return false;
    }
    
    // 启动健康检查线程
    health_check_thread_ = std::thread(&DatabasePool::health_check_loop, this);
    
    initialized_ = true;
    std::cout << "[DatabasePool] Initialized with " << all_connections_.size() 
              << " connections" << std::endl;
    
    return true;
}

std::shared_ptr<DatabaseConnection> DatabasePool::create_connection() {
    auto conn = std::make_shared<DatabaseConnection>();
    if (conn->connect(db_config_)) {
        return conn;
    }
    ++connection_errors_;
    return nullptr;
}

std::shared_ptr<DatabaseConnection> DatabasePool::acquire() {
    std::unique_lock<std::mutex> lock(mutex_);
    
    if (shutdown_) {
        return nullptr;
    }
    
    // 等待可用连接或创建新连接
    auto timeout = std::chrono::seconds(pool_config_.connection_timeout);
    auto deadline = std::chrono::steady_clock::now() + timeout;
    
    while (true) {
        // 尝试从空闲队列获取
        while (!idle_connections_.empty()) {
            auto conn = idle_connections_.front();
            idle_connections_.pop();
            
            // 检查连接是否有效
            if (conn->is_valid()) {
                conn->set_in_use(true);
                conn->touch();
                ++total_acquires_;
                return conn;
            } else {
                // 移除无效连接
                auto it = std::find(all_connections_.begin(), all_connections_.end(), conn);
                if (it != all_connections_.end()) {
                    all_connections_.erase(it);
                }
            }
        }
        
        // 如果未达到最大连接数，创建新连接
        if (all_connections_.size() < pool_config_.max_connections) {
            auto conn = create_connection();
            if (conn) {
                conn->set_in_use(true);
                all_connections_.push_back(conn);
                ++total_acquires_;
                return conn;
            }
        }
        
        // 等待其他线程释放连接
        auto status = cv_.wait_until(lock, deadline);
        if (status == std::cv_status::timeout) {
            ++acquire_timeouts_;
            std::cerr << "[DatabasePool] Connection acquire timeout, pool size: " 
                      << all_connections_.size() << std::endl;
            return nullptr;
        }
        
        if (shutdown_) {
            return nullptr;
        }
    }
}

std::shared_ptr<DatabaseConnection> DatabasePool::try_acquire() {
    std::lock_guard<std::mutex> lock(mutex_);
    
    if (shutdown_ || idle_connections_.empty()) {
        return nullptr;
    }
    
    auto conn = idle_connections_.front();
    idle_connections_.pop();
    
    if (conn->is_valid()) {
        conn->set_in_use(true);
        conn->touch();
        ++total_acquires_;
        return conn;
    }
    
    // 移除无效连接
    auto it = std::find(all_connections_.begin(), all_connections_.end(), conn);
    if (it != all_connections_.end()) {
        all_connections_.erase(it);
    }
    
    return nullptr;
}

void DatabasePool::release(std::shared_ptr<DatabaseConnection> conn) {
    if (!conn) return;
    
    std::lock_guard<std::mutex> lock(mutex_);
    
    if (shutdown_) {
        return;
    }
    
    conn->set_in_use(false);
    conn->touch();
    
    // 检查连接是否有效
    if (conn->is_valid()) {
        idle_connections_.push(conn);
        cv_.notify_one();
    } else {
        // 移除无效连接
        auto it = std::find(all_connections_.begin(), all_connections_.end(), conn);
        if (it != all_connections_.end()) {
            all_connections_.erase(it);
        }
    }
    
    ++total_releases_;
}

size_t DatabasePool::size() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return all_connections_.size();
}

size_t DatabasePool::idle_size() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return idle_connections_.size();
}

size_t DatabasePool::used_size() const {
    std::lock_guard<std::mutex> lock(mutex_);
    size_t used = 0;
    for (const auto& conn : all_connections_) {
        if (conn->is_in_use()) {
            ++used;
        }
    }
    return used;
}

DatabasePool::Stats DatabasePool::get_stats() const {
    Stats stats;
    std::lock_guard<std::mutex> lock(mutex_);
    stats.total_connections = all_connections_.size();
    stats.idle_connections = idle_connections_.size();
    stats.used_connections = stats.total_connections - stats.idle_connections;
    stats.total_acquires = total_acquires_;
    stats.total_releases = total_releases_;
    stats.acquire_timeouts = acquire_timeouts_;
    stats.connection_errors = connection_errors_;
    return stats;
}

void DatabasePool::shutdown() {
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (shutdown_) return;
        shutdown_ = true;
    }
    
    cv_.notify_all();
    
    if (health_check_thread_.joinable()) {
        health_check_thread_.join();
    }
    
    std::lock_guard<std::mutex> lock(mutex_);
    
    // 清空空闲连接
    while (!idle_connections_.empty()) {
        idle_connections_.pop();
    }
    
    all_connections_.clear();
    
    mysql_library_end();
    
    initialized_ = false;
    std::cout << "[DatabasePool] Shutdown complete" << std::endl;
}

void DatabasePool::cleanup_idle_connections() {
    std::lock_guard<std::mutex> lock(mutex_);
    
    if (shutdown_) return;
    
    auto now = std::chrono::steady_clock::now();
    auto max_idle = std::chrono::seconds(pool_config_.max_idle_time);
    
    std::queue<std::shared_ptr<DatabaseConnection>> valid_connections;
    
    while (!idle_connections_.empty()) {
        auto conn = idle_connections_.front();
        idle_connections_.pop();
        
        auto idle_time = std::chrono::duration_cast<std::chrono::seconds>(
            now - conn->get_last_used());
        
        // 保留最小连接数，清理超过最大空闲时间的连接
        if (all_connections_.size() > pool_config_.min_connections &&
            idle_time > max_idle) {
            // 移除连接
            auto it = std::find(all_connections_.begin(), all_connections_.end(), conn);
            if (it != all_connections_.end()) {
                all_connections_.erase(it);
            }
            std::cout << "[DatabasePool] Cleaned up idle connection, pool size: " 
                      << all_connections_.size() << std::endl;
        } else {
            valid_connections.push(conn);
        }
    }
    
    idle_connections_ = std::move(valid_connections);
    
    // 确保最小连接数
    while (all_connections_.size() < pool_config_.min_connections) {
        auto conn = create_connection();
        if (conn) {
            idle_connections_.push(conn);
            all_connections_.push_back(conn);
        } else {
            break;
        }
    }
}

void DatabasePool::health_check_loop() {
    while (!shutdown_) {
        std::this_thread::sleep_for(
            std::chrono::seconds(pool_config_.health_check_interval));
        
        if (shutdown_) break;
        
        // 执行健康检查
        cleanup_idle_connections();
        
        // 输出统计信息
        auto stats = get_stats();
        std::cout << "[DatabasePool] Health check - connections: " << stats.total_connections
                  << ", idle: " << stats.idle_connections
                  << ", used: " << stats.used_connections
                  << ", acquires: " << stats.total_acquires
                  << ", timeouts: " << stats.acquire_timeouts
                  << std::endl;
    }
}

// ==================== ConnectionGuard 实现 ====================

ConnectionGuard::ConnectionGuard(DatabasePool& pool)
    : pool_(pool)
    , connection_(pool.acquire()) {
}

ConnectionGuard::~ConnectionGuard() {
    release();
}

ConnectionGuard::ConnectionGuard(ConnectionGuard&& other) noexcept
    : pool_(other.pool_)
    , connection_(std::move(other.connection_)) {
    other.connection_ = nullptr;
}

ConnectionGuard& ConnectionGuard::operator=(ConnectionGuard&& other) noexcept {
    if (this != &other) {
        release();
        connection_ = std::move(other.connection_);
        other.connection_ = nullptr;
    }
    return *this;
}

DatabaseConnection* ConnectionGuard::get() {
    return connection_ ? connection_.get() : nullptr;
}

void ConnectionGuard::release() {
    if (connection_) {
        pool_.release(connection_);
        connection_ = nullptr;
    }
}

} // namespace chat
