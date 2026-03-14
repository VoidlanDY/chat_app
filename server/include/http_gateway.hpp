/**
 * HTTP Gateway Service
 * 统一 HTTP 入口，处理文件上传、下载和 API 请求
 * 集成到主服务器中，作为分发网关
 */

#ifndef HTTP_GATEWAY_HPP
#define HTTP_GATEWAY_HPP

#include <string>
#include <memory>
#include <functional>
#include <map>
#include <vector>
#include <mutex>
#include <microhttpd.h>

namespace chat {

// 前向声明
class Database;
class UserManager;

/**
 * HTTP 请求上下文
 */
struct HttpRequest {
    std::string method;
    std::string path;
    std::string query;
    std::map<std::string, std::string> headers;
    std::map<std::string, std::string> params;
    std::vector<uint8_t> body;
    std::string content_type;
    std::string authorization;
};

/**
 * HTTP 响应
 */
struct HttpResponse {
    int status_code = 200;
    std::string content_type = "application/json";
    std::vector<uint8_t> body;
    std::map<std::string, std::string> headers;
    
    // 静态工厂方法
    static HttpResponse json(int status, const std::string& json_str);
    static HttpResponse error(int status, const std::string& message);
    static HttpResponse file(const std::vector<uint8_t>& data, const std::string& mime_type);
    static HttpResponse redirect(const std::string& url);
};

/**
 * 路由处理器类型
 */
using RouteHandler = std::function<HttpResponse(const HttpRequest&)>;

/**
 * HTTP Gateway 服务
 * 提供统一的 HTTP 入口，支持：
 * 1. 文件上传 API
 * 2. 文件下载服务
 * 3. RESTful API 路由
 */
class HttpGateway {
public:
    struct Config {
        uint16_t port = 8888;
        std::string media_dir = "media";
        size_t max_upload_size = 50 * 1024 * 1024; // 50MB
        bool enable_cors = true;
    };
    
    HttpGateway(const Config& config);
    ~HttpGateway();
    
    /**
     * 设置依赖
     */
    void set_database(std::shared_ptr<Database> db) { database_ = db; }
    void set_user_manager(std::shared_ptr<UserManager> um) { user_manager_ = um; }
    
    /**
     * 设置媒体目录
     */
    void set_media_dir(const std::string& dir) { config_.media_dir = dir; }
    
    /**
     * 启动/停止服务
     */
    bool start();
    void stop();
    
    /**
     * 注册路由处理器
     */
    void register_route(const std::string& method, const std::string& path, RouteHandler handler);
    
    /**
     * 获取端口
     */
    uint16_t get_port() const { return config_.port; }
    
    /**
     * 检查是否运行中
     */
    bool is_running() const { return daemon_ != nullptr; }

private:
    // MHD 请求处理器
    static MHD_Result handle_request(
        void* cls,
        struct MHD_Connection* connection,
        const char* url,
        const char* method,
        const char* version,
        const char* upload_data,
        size_t* upload_data_size,
        void** con_cls
    );
    
    // 内部路由处理
    HttpResponse route_request(const HttpRequest& request);
    
    // API 处理器
    HttpResponse handle_upload(const HttpRequest& request);
    HttpResponse handle_download(const HttpRequest& request);
    HttpResponse handle_api_auth(const HttpRequest& request);
    
    // 工具方法
    std::string get_mime_type(const std::string& filename);
    bool parse_multipart_form(const HttpRequest& request, 
                              std::map<std::string, std::string>& fields,
                              std::vector<uint8_t>& file_data,
                              std::string& filename);
    bool verify_token(const std::string& token, uint64_t& user_id);

private:
    Config config_;
    MHD_Daemon* daemon_ = nullptr;
    
    std::shared_ptr<Database> database_;
    std::shared_ptr<UserManager> user_manager_;
    
    // 路由表: method -> path -> handler
    std::map<std::string, std::map<std::string, RouteHandler>> routes_;
    std::mutex routes_mutex_;
    
    // 连接状态跟踪
    struct ConnectionContext {
        HttpRequest request;
        bool headers_processed = false;
    };
    std::map<void*, ConnectionContext> connections_;
    std::mutex connections_mutex_;
};

} // namespace chat

#endif // HTTP_GATEWAY_HPP
