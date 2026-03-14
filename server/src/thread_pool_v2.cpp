#include "thread_pool_v2.hpp"
#include <future>

namespace chat {

// ==================== ThreadPoolV2 实现 ====================

ThreadPoolV2::ThreadPoolV2(const Config& config)
    : config_(config) {
    // 预创建最小数量的工作线程
    for (size_t i = 0; i < config_.min_threads; ++i) {
        workers_.emplace_back(&ThreadPoolV2::worker, this);
    }
    
    std::cout << "[ThreadPoolV2] Initialized with " << config_.min_threads 
              << " threads, max queue size: " << config_.max_queue_size << std::endl;
}

ThreadPoolV2::~ThreadPoolV2() {
    stop();
}

bool ThreadPoolV2::enqueue(std::function<void()> task) {
    return enqueue(std::move(task), Priority::NORMAL);
}

bool ThreadPoolV2::enqueue(std::function<void()> task, Priority priority) {
    if (!task || stopped_) {
        return false;
    }
    
    Task t;
    t.func = std::move(task);
    t.priority = priority;
    t.submit_time = std::chrono::steady_clock::now();
    
    std::unique_lock<std::mutex> lock(mutex_);
    
    // 检查队列是否已满
    if (tasks_.size() >= config_.max_queue_size) {
        // 处理拒绝策略
        switch (config_.rejection_policy) {
            case RejectionPolicy::BLOCK: {
                // 等待队列有空位
                cv_done_.wait(lock, [this] {
                    return tasks_.size() < config_.max_queue_size || stopped_;
                });
                if (stopped_) return false;
                break;
            }
            case RejectionPolicy::DISCARD:
                ++rejected_tasks_;
                return false;
                
            case RejectionPolicy::DISCARD_OLDEST: {
                // 弹出最旧的任务（优先级队列底层是最小堆，无法直接弹出最旧）
                // 这里简化处理，丢弃最低优先级的任务
                if (!tasks_.empty()) {
                    tasks_.pop();
                }
                break;
            }
            case RejectionPolicy::CALLER_RUNS: {
                // 由调用者执行
                lock.unlock();
                task();
                ++completed_tasks_;
                return true;
            }
        }
    }
    
    tasks_.push(std::move(t));
    ++total_tasks_;
    
    // 尝试添加更多线程（如果需要）
    if (active_workers_.load() >= workers_.size() && 
        workers_.size() < config_.max_threads) {
        try_add_thread();
    }
    
    cv_task_.notify_one();
    return true;
}

bool ThreadPoolV2::try_enqueue(std::function<void()> task) {
    if (!task || stopped_) {
        return false;
    }
    
    std::lock_guard<std::mutex> lock(mutex_);
    
    if (tasks_.size() >= config_.max_queue_size) {
        ++rejected_tasks_;
        return false;
    }
    
    Task t;
    t.func = std::move(task);
    t.priority = Priority::NORMAL;
    t.submit_time = std::chrono::steady_clock::now();
    
    tasks_.push(std::move(t));
    ++total_tasks_;
    
    cv_task_.notify_one();
    return true;
}

void ThreadPoolV2::enqueue_and_wait(std::function<void()> task) {
    if (!task || stopped_) {
        return;
    }
    
    std::promise<void> promise;
    auto future = promise.get_future();
    
    auto wrapper = [&task, &promise]() {
        try {
            task();
            promise.set_value();
        } catch (...) {
            promise.set_exception(std::current_exception());
        }
    };
    
    enqueue(wrapper);
    future.wait();
}

ThreadPoolV2::Stats ThreadPoolV2::get_stats() const {
    Stats stats;
    std::lock_guard<std::mutex> lock(mutex_);
    
    stats.total_tasks = total_tasks_.load();
    stats.completed_tasks = completed_tasks_.load();
    stats.rejected_tasks = rejected_tasks_.load();
    stats.queue_size = tasks_.size();
    stats.active_threads = active_workers_.load();
    stats.total_threads = workers_.size();
    
    if (stats.completed_tasks > 0) {
        stats.avg_wait_time = std::chrono::milliseconds(
            total_wait_time_ns_.load() / stats.completed_tasks / 1000000);
        stats.avg_exec_time = std::chrono::milliseconds(
            total_exec_time_ns_.load() / stats.completed_tasks / 1000000);
    }
    
    return stats;
}

size_t ThreadPoolV2::queue_size() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return tasks_.size();
}

size_t ThreadPoolV2::thread_count() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return workers_.size();
}

void ThreadPoolV2::stop() {
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (stopped_) return;
        stopped_ = true;
    }
    
    cv_task_.notify_all();
    cv_done_.notify_all();
    
    for (auto& w : workers_) {
        if (w.joinable()) {
            w.join();
        }
    }
    workers_.clear();
    
    // 输出最终统计信息
    auto stats = get_stats();
    std::cout << "[ThreadPoolV2] Stopped - tasks: " << stats.total_tasks
              << ", completed: " << stats.completed_tasks
              << ", rejected: " << stats.rejected_tasks << std::endl;
}

void ThreadPoolV2::wait_all() {
    std::unique_lock<std::mutex> lock(mutex_);
    cv_done_.wait(lock, [this] {
        return tasks_.empty() && active_workers_.load() == 0;
    });
}

void ThreadPoolV2::clear_queue() {
    std::lock_guard<std::mutex> lock(mutex_);
    while (!tasks_.empty()) {
        tasks_.pop();
    }
}

void ThreadPoolV2::worker() {
    while (true) {
        Task task;
        
        {
            std::unique_lock<std::mutex> lock(mutex_);
            
            // 等待任务或停止信号
            cv_task_.wait(lock, [this] {
                return !tasks_.empty() || stopped_;
            });
            
            if (stopped_ && tasks_.empty()) {
                return;
            }
            
            if (tasks_.empty()) {
                continue;
            }
            
            task = tasks_.top();
            tasks_.pop();
            
            ++active_workers_;
        }
        
        // 记录等待时间
        auto start_time = std::chrono::steady_clock::now();
        auto wait_time = std::chrono::duration_cast<std::chrono::nanoseconds>(
            start_time - task.submit_time);
        total_wait_time_ns_.fetch_add(wait_time.count());
        
        // 执行任务
        try {
            task.func();
        } catch (const std::exception& e) {
            std::cerr << "[ThreadPoolV2] Task exception: " << e.what() << std::endl;
        } catch (...) {
            std::cerr << "[ThreadPoolV2] Unknown task exception" << std::endl;
        }
        
        // 记录执行时间
        auto end_time = std::chrono::steady_clock::now();
        auto exec_time = std::chrono::duration_cast<std::chrono::nanoseconds>(
            end_time - start_time);
        total_exec_time_ns_.fetch_add(exec_time.count());
        
        --active_workers_;
        ++completed_tasks_;
        
        // 通知等待的线程
        cv_done_.notify_all();
    }
}

void ThreadPoolV2::try_add_thread() {
    // 在锁内调用，不需要额外加锁
    if (workers_.size() >= config_.max_threads) {
        return;
    }
    
    workers_.emplace_back(&ThreadPoolV2::worker, this);
    std::cout << "[ThreadPoolV2] Added thread, total: " << workers_.size() << std::endl;
}

// ==================== ThreadPool（向后兼容版本）实现 ====================

ThreadPool::ThreadPool(size_t num_threads) {
    ThreadPoolV2::Config config;
    config.min_threads = num_threads;
    config.max_threads = num_threads;
    config.max_queue_size = 500;  // 默认队列大小
    impl_ = std::make_unique<ThreadPoolV2>(config);
}

ThreadPool::~ThreadPool() {
    stop();
}

void ThreadPool::enqueue(std::function<void()> task) {
    if (impl_) {
        impl_->enqueue(std::move(task));
    }
}

void ThreadPool::stop() {
    if (impl_) {
        impl_->stop();
    }
}

size_t ThreadPool::queue_size() const {
    return impl_ ? impl_->queue_size() : 0;
}

size_t ThreadPool::thread_count() const {
    return impl_ ? impl_->thread_count() : 0;
}

bool ThreadPool::is_stopped() const {
    return impl_ ? impl_->is_stopped() : true;
}

} // namespace chat
