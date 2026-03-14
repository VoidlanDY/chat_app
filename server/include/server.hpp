#ifndef SERVER_HPP
#define SERVER_HPP

#include <memory>
#include <map>
#include <mutex>
#include <functional>
#include <thread>
#include <atomic>
#include <asio.hpp>
#include "protocol.hpp"
#include "session.hpp"
#include "thread_pool_v2.hpp"
#include "database_pool.hpp"

namespace chat {

// 前向声明
class UserManager;
class MessageManager;
class GroupManager;
class FriendManager;
class Database;
class BotManager;
class FcmManager;
class JPushManager;

class Server : public std::enable_shared_from_this<Server> {
public:
    using IOContext = asio::io_context;
    using Acceptor = asio::ip::tcp::acceptor;
    using Endpoint = asio::ip::tcp::endpoint;
    using Socket = asio::ip::tcp::socket;
    using SignalSet = asio::signal_set;
    
    struct Config {
        std::string host = "0.0.0.0";
        uint16_t port = 8888;
        int thread_count = 4;
        int heartbeat_timeout = 60; // seconds
        int cleanup_interval = 300;  // seconds - 清理过期会话的间隔
        
        // 线程池配置
        size_t min_worker_threads = 4;
        size_t max_worker_threads = 16;
        size_t max_task_queue_size = 1000;
        
        // 数据库连接池配置
        size_t db_min_connections = 5;
        size_t db_max_connections = 20;
    };
    
    Server(const Config& config);
    ~Server();
    
    bool start();
    void stop();
    void run();
    
    // 会话管理
    void add_session(Session::ptr session);
    void remove_session(Session::ptr session);
    Session::ptr get_session(uint64_t user_id);
    void broadcast(const std::vector<uint8_t>& data);
    void broadcast_to_group(uint64_t group_id, const std::vector<uint8_t>& data);
    void send_to_user(uint64_t user_id, const std::vector<uint8_t>& data);
    
    // 设置用户上线/下线
    void set_user_online(uint64_t user_id, Session::ptr session);
    void set_user_offline(uint64_t user_id);
    bool is_user_online(uint64_t user_id);
    bool is_user_active(uint64_t user_id);  // 检查用户是否活跃（最近有心跳）
    
    // 获取在线用户列表
    std::vector<uint64_t> get_online_users();
    
    // 设置管理器
    void set_managers(std::shared_ptr<UserManager> user_manager,
                      std::shared_ptr<MessageManager> message_manager,
                      std::shared_ptr<GroupManager> group_manager,
                      std::shared_ptr<FriendManager> friend_manager,
                      std::shared_ptr<Database> database);
    
    // 设置机器人管理器
    void set_bot_manager(std::shared_ptr<BotManager> bot_manager);
    
    // 设置 FCM 管理器
    void set_fcm_manager(std::shared_ptr<FcmManager> fcm_manager);
    std::shared_ptr<FcmManager> get_fcm_manager() { return fcm_manager_; }
    
    // 设置 JPush 管理器
    void set_jpush_manager(std::shared_ptr<JPushManager> jpush_manager);
    std::shared_ptr<JPushManager> get_jpush_manager() { return jpush_manager_; }
    
    // 设置数据库连接池
    void set_database_pool(std::shared_ptr<DatabasePool> pool) { database_pool_ = pool; }
    std::shared_ptr<DatabasePool> get_database_pool() { return database_pool_; }
    
    // 获取 io_context（用于异步操作）
    IOContext& get_io_context() { return io_context_; }
    
    // 获取线程池（用于数据库操作）
    ThreadPoolV2& get_thread_pool() { return *thread_pool_; }
    
    // 获取服务器统计信息
    struct Stats {
        size_t total_connections = 0;
        size_t current_connections = 0;
        size_t messages_processed = 0;
        std::chrono::steady_clock::time_point start_time;
        
        // 线程池统计
        size_t thread_pool_queue_size = 0;
        size_t thread_pool_threads = 0;
        size_t thread_pool_active = 0;
        
        // 数据库连接池统计
        size_t db_total_connections = 0;
        size_t db_idle_connections = 0;
        size_t db_used_connections = 0;
    };
    Stats get_stats();
    
private:
    void do_accept();
    void handle_accept(Session::ptr session, const asio::error_code& ec);
    void check_heartbeats();
    void cleanup_expired_resources();  // 定期清理过期资源
    
private:
    Config config_;
    IOContext io_context_;
    Acceptor acceptor_;
    SignalSet signals_;
    
    // Work guard - 防止 io_context 在没有任务时停止
    std::unique_ptr<asio::executor_work_guard<IOContext::executor_type>> work_guard_;
    
    // 高性能线程池用于处理消息和数据库操作
    std::unique_ptr<ThreadPoolV2> thread_pool_;
    
    // 数据库连接池
    std::shared_ptr<DatabasePool> database_pool_;
    
    std::map<uint64_t, Session::ptr> sessions_;
    std::mutex sessions_mutex_;
    
    std::atomic<bool> running_;
    std::vector<std::thread> threads_;
    
    asio::steady_timer heartbeat_timer_;
    asio::steady_timer cleanup_timer_;  // 清理定时器
    
    // 管理器
    std::shared_ptr<UserManager> user_manager_;
    std::shared_ptr<MessageManager> message_manager_;
    std::shared_ptr<GroupManager> group_manager_;
    std::shared_ptr<FriendManager> friend_manager_;
    std::shared_ptr<Database> database_;
    std::shared_ptr<BotManager> bot_manager_;
    std::shared_ptr<FcmManager> fcm_manager_;
    std::shared_ptr<JPushManager> jpush_manager_;
    
    // 统计信息
    std::atomic<size_t> total_connections_{0};
    std::atomic<size_t> messages_processed_{0};
    std::chrono::steady_clock::time_point start_time_;
};

} // namespace chat

#endif // SERVER_HPP
