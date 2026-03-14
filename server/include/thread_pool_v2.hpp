#ifndef THREAD_POOL_V2_HPP
#define THREAD_POOL_V2_HPP

#include <thread>
#include <condition_variable>
#include <queue>
#include <mutex>
#include <functional>
#include <vector>
#include <atomic>
#include <chrono>
#include <iostream>

namespace chat {

/**
 * 高性能线程池
 * - 支持任务队列大小限制
 * - 支持背压机制（拒绝策略）
 * - 支持任务优先级
 * - 支持统计信息
 */
class ThreadPoolV2 {
public:
    /**
     * 任务优先级
     */
    enum class Priority {
        LOW = 0,
        NORMAL = 1,
        HIGH = 2,
        CRITICAL = 3
    };
    
    /**
     * 任务拒绝策略
     */
    enum class RejectionPolicy {
        BLOCK,          // 阻塞等待队列有空位
        DISCARD,        // 直接丢弃任务
        DISCARD_OLDEST, // 丢弃最旧的任务
        CALLER_RUNS     // 由调用者线程执行
    };
    
    /**
     * 线程池配置
     */
    struct Config {
        size_t min_threads = 4;
        size_t max_threads = 16;
        size_t max_queue_size = 1000;       // 最大任务队列大小
        size_t idle_timeout = 60;           // 空闲线程超时时间（秒）
        RejectionPolicy rejection_policy = RejectionPolicy::BLOCK;
    };
    
    /**
     * 统计信息
     */
    struct Stats {
        size_t total_tasks;
        size_t completed_tasks;
        size_t rejected_tasks;
        size_t queue_size;
        size_t active_threads;
        size_t total_threads;
        std::chrono::milliseconds avg_wait_time;
        std::chrono::milliseconds avg_exec_time;
    };
    
    explicit ThreadPoolV2(const Config& config);
    ~ThreadPoolV2();
    
    // 禁止拷贝和移动
    ThreadPoolV2(const ThreadPoolV2&) = delete;
    ThreadPoolV2& operator=(const ThreadPoolV2&) = delete;
    ThreadPoolV2(ThreadPoolV2&&) = delete;
    ThreadPoolV2& operator=(ThreadPoolV2&&) = delete;
    
    /**
     * 提交任务（普通优先级）
     * @return 是否成功提交
     */
    bool enqueue(std::function<void()> task);
    
    /**
     * 提交任务（带优先级）
     * @return 是否成功提交
     */
    bool enqueue(std::function<void()> task, Priority priority);
    
    /**
     * 尝试提交任务（非阻塞）
     * @return 是否成功提交
     */
    bool try_enqueue(std::function<void()> task);
    
    /**
     * 提交任务并等待完成
     */
    void enqueue_and_wait(std::function<void()> task);
    
    /**
     * 获取统计信息
     */
    Stats get_stats() const;
    
    /**
     * 获取当前队列大小
     */
    size_t queue_size() const;
    
    /**
     * 获取线程数量
     */
    size_t thread_count() const;
    
    /**
     * 检查是否已停止
     */
    bool is_stopped() const { return stopped_; }
    
    /**
     * 停止线程池
     */
    void stop();
    
    /**
     * 等待所有任务完成
     */
    void wait_all();
    
    /**
     * 清空任务队列
     */
    void clear_queue();

private:
    /**
     * 内部任务结构
     */
    struct Task {
        std::function<void()> func;
        Priority priority;
        std::chrono::steady_clock::time_point submit_time;
        
        // 优先级比较（优先级高的排前面）
        bool operator<(const Task& other) const {
            return static_cast<int>(priority) < static_cast<int>(other.priority);
        }
    };
    
    /**
     * 工作线程函数
     */
    void worker();
    
    /**
     * 尝试添加工作线程
     */
    void try_add_thread();
    
    /**
     * 处理拒绝策略
     */
    bool handle_rejection(Task task);

private:
    Config config_;
    
    mutable std::mutex mutex_;
    std::condition_variable cv_task_;
    std::condition_variable cv_done_;
    
    std::priority_queue<Task> tasks_;
    std::vector<std::thread> workers_;
    
    std::atomic<bool> stopped_{false};
    std::atomic<size_t> active_workers_{0};
    
    // 统计信息
    std::atomic<size_t> total_tasks_{0};
    std::atomic<size_t> completed_tasks_{0};
    std::atomic<size_t> rejected_tasks_{0};
    std::atomic<uint64_t> total_wait_time_ns_{0};
    std::atomic<uint64_t> total_exec_time_ns_{0};
};

/**
 * 简化的线程池（向后兼容）
 * 保持与原 ThreadPool 接口兼容
 */
class ThreadPool {
public:
    explicit ThreadPool(size_t num_threads = 4);
    ~ThreadPool();
    
    void enqueue(std::function<void()> task);
    void stop();
    
    size_t queue_size() const;
    size_t thread_count() const;
    bool is_stopped() const;
    
private:
    std::unique_ptr<ThreadPoolV2> impl_;
};

} // namespace chat

#endif // THREAD_POOL_V2_HPP
