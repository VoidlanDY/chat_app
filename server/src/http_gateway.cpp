/**
 * HTTP Gateway Service Implementation
 */

#include "http_gateway.hpp"
#include "database.hpp"
#include "user_manager.hpp"
#include <iostream>
#include <fstream>
#include <sstream>
#include <algorithm>
#include <ctime>
#include <iomanip>
#include <sys/stat.h>
#include <cstring>
#include <cstdlib>
#include <dirent.h>

namespace chat {

// ==================== HttpResponse 静态方法 ====================

HttpResponse HttpResponse::json(int status, const std::string& json_str) {
    HttpResponse resp;
    resp.status_code = status;
    resp.content_type = "application/json";
    resp.body = std::vector<uint8_t>(json_str.begin(), json_str.end());
    resp.headers["Access-Control-Allow-Origin"] = "*";
    return resp;
}

HttpResponse HttpResponse::error(int status, const std::string& message) {
    std::string json_body = "{\"code\":" + std::to_string(status) + 
                       ",\"message\":\"" + message + "\"}";
    return json(status, json_body);
}

HttpResponse HttpResponse::file(const std::vector<uint8_t>& data, const std::string& mime_type) {
    HttpResponse resp;
    resp.status_code = 200;
    resp.content_type = mime_type;
    resp.body = data;
    resp.headers["Access-Control-Allow-Origin"] = "*";
    resp.headers["Cache-Control"] = "public, max-age=86400";
    return resp;
}

HttpResponse HttpResponse::redirect(const std::string& url) {
    HttpResponse resp;
    resp.status_code = 302;
    resp.headers["Location"] = url;
    return resp;
}

// ==================== HttpGateway ====================

HttpGateway::HttpGateway(const Config& config) 
    : config_(config) {
}

HttpGateway::~HttpGateway() {
    stop();
}

bool HttpGateway::start() {
    if (daemon_) {
        std::cerr << "[HttpGateway] Already running" << std::endl;
        return true;
    }
    
    // 创建媒体目录
    mkdir(config_.media_dir.c_str(), 0755);
    
    // 启动 MHD daemon
    daemon_ = MHD_start_daemon(
        MHD_USE_THREAD_PER_CONNECTION,
        config_.port,
        nullptr, nullptr,
        &HttpGateway::handle_request, this,
        MHD_OPTION_CONNECTION_LIMIT, 100,
        MHD_OPTION_CONNECTION_TIMEOUT, 30,
        MHD_OPTION_END
    );
    
    if (!daemon_) {
        std::cerr << "[HttpGateway] Failed to start on port " << config_.port << std::endl;
        return false;
    }
    
    std::cout << "[HttpGateway] Started on port " << config_.port << std::endl;
    std::cout << "[HttpGateway] Media directory: " << config_.media_dir << std::endl;
    
    // 注册默认路由
    register_route("POST", "/api/upload", [this](const HttpRequest& req) {
        return handle_upload(req);
    });
    
    register_route("GET", "/media", [this](const HttpRequest& req) {
        return handle_download(req);
    });
    
    register_route("OPTIONS", "*", [](const HttpRequest& req) {
        HttpResponse resp;
        resp.status_code = 200;
        resp.headers["Access-Control-Allow-Origin"] = "*";
        resp.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS";
        resp.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization";
        return resp;
    });
    
    return true;
}

void HttpGateway::stop() {
    if (daemon_) {
        MHD_stop_daemon(daemon_);
        daemon_ = nullptr;
        std::cout << "[HttpGateway] Stopped" << std::endl;
    }
}

void HttpGateway::register_route(const std::string& method, const std::string& path, RouteHandler handler) {
    std::lock_guard<std::mutex> lock(routes_mutex_);
    routes_[method][path] = handler;
}

// ==================== MHD 请求处理 ====================

MHD_Result HttpGateway::handle_request(
    void* cls,
    struct MHD_Connection* connection,
    const char* url,
    const char* method,
    const char* version,
    const char* upload_data,
    size_t* upload_data_size,
    void** con_cls
) {
    HttpGateway* self = static_cast<HttpGateway*>(cls);
    
    // 处理 OPTIONS 预检请求
    if (strcmp(method, "OPTIONS") == 0) {
        struct MHD_Response* response = MHD_create_response_from_buffer(0, nullptr, MHD_RESPMEM_PERSISTENT);
        MHD_add_response_header(response, "Access-Control-Allow-Origin", "*");
        MHD_add_response_header(response, "Access-Control-Allow-Methods", "GET, POST, OPTIONS");
        MHD_add_response_header(response, "Access-Control-Allow-Headers", "Content-Type, Authorization");
        MHD_add_response_header(response, "Access-Control-Max-Age", "86400");
        MHD_queue_response(connection, MHD_HTTP_OK, response);
        MHD_destroy_response(response);
        return MHD_YES;
    }
    
    // 获取或创建连接上下文
    ConnectionContext* ctx = nullptr;
    if (*con_cls == nullptr) {
        // 首次调用，创建上下文
        std::lock_guard<std::mutex> lock(self->connections_mutex_);
        auto& conn_ctx = self->connections_[connection];
        conn_ctx.request.method = method;
        conn_ctx.request.path = url;
        conn_ctx.headers_processed = false;
        *con_cls = &conn_ctx;
        ctx = &conn_ctx;
        
        // 解析查询参数
        const char* query = MHD_lookup_connection_value(connection, MHD_GET_ARGUMENT_KIND, nullptr);
        if (query) {
            ctx->request.query = query;
        }
        
        // 解析头部
        MHD_get_connection_values(connection, MHD_HEADER_KIND, 
            [](void* cls, enum MHD_ValueKind /*kind*/, const char* key, const char* value) -> enum MHD_Result {
                auto* req = static_cast<HttpRequest*>(cls);
                req->headers[key] = value;
                if (strcasecmp(key, "Content-Type") == 0) {
                    req->content_type = value;
                }
                if (strcasecmp(key, "Authorization") == 0) {
                    req->authorization = value;
                }
                return MHD_YES;
            }, &ctx->request);
        
        return MHD_YES;
    }
    
    ctx = static_cast<ConnectionContext*>(*con_cls);
    
    // 接收上传数据
    if (*upload_data_size > 0) {
        size_t old_size = ctx->request.body.size();
        ctx->request.body.resize(old_size + *upload_data_size);
        memcpy(ctx->request.body.data() + old_size, upload_data, *upload_data_size);
        *upload_data_size = 0;
        return MHD_YES;
    }
    
    // 完成接收，处理请求
    HttpRequest& request = ctx->request;
    
    std::cout << "[HttpGateway] " << method << " " << url 
              << " (body: " << request.body.size() << " bytes)" << std::endl;
    
    // 路由请求
    HttpResponse response = self->route_request(request);
    
    // 构建响应
    struct MHD_Response* mhd_response;
    if (response.body.empty()) {
        mhd_response = MHD_create_response_from_buffer(0, nullptr, MHD_RESPMEM_PERSISTENT);
    } else {
        mhd_response = MHD_create_response_from_buffer(
            response.body.size(),
            response.body.data(),
            MHD_RESPMEM_MUST_COPY
        );
    }
    
    // 设置头部
    MHD_add_response_header(mhd_response, "Content-Type", response.content_type.c_str());
    for (const auto& [key, value] : response.headers) {
        MHD_add_response_header(mhd_response, key.c_str(), value.c_str());
    }
    
    MHD_queue_response(connection, response.status_code, mhd_response);
    MHD_destroy_response(mhd_response);
    
    // 清理连接上下文
    {
        std::lock_guard<std::mutex> lock(self->connections_mutex_);
        self->connections_.erase(connection);
    }
    
    return MHD_YES;
}

// ==================== 路由处理 ====================

HttpResponse HttpGateway::route_request(const HttpRequest& request) {
    std::lock_guard<std::mutex> lock(routes_mutex_);
    
    std::string method = request.method;
    std::string path = request.path;
    
    // 查找精确匹配
    auto method_it = routes_.find(method);
    if (method_it != routes_.end()) {
        // 精确路径匹配
        auto path_it = method_it->second.find(path);
        if (path_it != method_it->second.end()) {
            return path_it->second(request);
        }
        
        // 前缀匹配 (如 /media/*)
        for (const auto& [route_path, handler] : method_it->second) {
            if (path.find(route_path) == 0) {
                return handler(request);
            }
        }
    }
    
    // 未找到路由
    return HttpResponse::error(404, "Not Found");
}

// ==================== 文件上传处理 ====================

HttpResponse HttpGateway::handle_upload(const HttpRequest& request) {
    // 验证 Authorization
    uint64_t user_id = 0;
    if (!verify_token(request.authorization, user_id)) {
        return HttpResponse::error(401, "Unauthorized");
    }
    
    // 检查 Content-Type
    std::string content_type = request.content_type;
    
    std::string file_name;
    std::vector<uint8_t> file_data;
    int media_type = 1; // 默认图片
    
    // 解析 multipart/form-data
    if (content_type.find("multipart/form-data") != std::string::npos) {
        // 查找 boundary
        size_t boundary_pos = content_type.find("boundary=");
        if (boundary_pos == std::string::npos) {
            return HttpResponse::error(400, "Missing boundary");
        }
        std::string boundary = "--" + content_type.substr(boundary_pos + 9);
        
        // 解析 multipart 数据
        std::string body_str(request.body.begin(), request.body.end());
        size_t pos = 0;
        
        while ((pos = body_str.find(boundary, pos)) != std::string::npos) {
            size_t part_start = pos + boundary.length();
            if (body_str.substr(part_start, 2) == "--") break; // 结束标记
            
            size_t header_end = body_str.find("\r\n\r\n", part_start);
            if (header_end == std::string::npos) break;
            
            std::string part_header = body_str.substr(part_start, header_end - part_start);
            
            // 提取文件名
            size_t name_pos = part_header.find("filename=\"");
            if (name_pos != std::string::npos) {
                size_t name_start = name_pos + 10;
                size_t name_end = part_header.find("\"", name_start);
                file_name = part_header.substr(name_start, name_end - name_start);
            }
            
            // 提取 Content-Type
            size_t ct_pos = part_header.find("Content-Type: ");
            if (ct_pos != std::string::npos) {
                size_t ct_start = ct_pos + 14;
                size_t ct_end = part_header.find("\r\n", ct_start);
                std::string file_ct = part_header.substr(ct_start, ct_end - ct_start);
                
                // 根据 Content-Type 确定媒体类型
                if (file_ct.find("image/") == 0) {
                    media_type = 1; // 图片
                } else {
                    media_type = 2; // 文件
                }
            }
            
            // 提取文件数据
            size_t data_start = header_end + 4;
            size_t data_end = body_str.find(boundary, data_start);
            if (data_end != std::string::npos) {
                // 移除末尾的 \r\n
                if (data_end >= 2 && body_str[data_end-2] == '\r' && body_str[data_end-1] == '\n') {
                    data_end -= 2;
                }
                file_data = std::vector<uint8_t>(
                    request.body.begin() + data_start,
                    request.body.begin() + data_end
                );
            }
            
            pos = data_end;
        }
    } else {
        // 尝试解析 JSON
        std::string body_str(request.body.begin(), request.body.end());
        
        // 简单 JSON 解析 (不使用库以减少依赖)
        auto extract_string = [&body_str](const std::string& key) -> std::string {
            std::string search = "\"" + key + "\":\"";
            size_t pos = body_str.find(search);
            if (pos == std::string::npos) return "";
            pos += search.length();
            size_t end = body_str.find("\"", pos);
            if (end == std::string::npos) return "";
            return body_str.substr(pos, end - pos);
        };
        
        auto extract_int = [&body_str](const std::string& key) -> int {
            std::string search = "\"" + key + "\":";
            size_t pos = body_str.find(search);
            if (pos == std::string::npos) return 0;
            pos += search.length();
            return std::stoi(body_str.substr(pos));
        };
        
        file_name = extract_string("file_name");
        media_type = extract_int("media_type");
        
        // 查找 base64 数据
        std::string base64_data = extract_string("file_data");
        if (!base64_data.empty()) {
            // Base64 解码
            static const int decode_table[256] = {
                -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
                -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
                -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,62,-1,-1,-1,63,
                52,53,54,55,56,57,58,59,60,61,-1,-1,-1,-1,-1,-1,
                -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12,13,14,
                15,16,17,18,19,20,21,22,23,24,25,-1,-1,-1,-1,-1,
                -1,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,
                41,42,43,44,45,46,47,48,49,50,51,-1,-1,-1,-1,-1,
                -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
                -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
                -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
                -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
                -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
                -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
                -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
                -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
            };
            
            int val = 0, valb = -8;
            for (unsigned char c : base64_data) {
                if (decode_table[c] == -1) break;
                val = (val << 6) + decode_table[c];
                valb += 6;
                if (valb >= 0) {
                    file_data.push_back(static_cast<uint8_t>((val >> valb) & 0xFF));
                    valb -= 8;
                }
            }
        }
    }
    
    if (file_name.empty() || file_data.empty()) {
        return HttpResponse::error(400, "Missing file or filename");
    }
    
    // 检查文件大小
    if (file_data.size() > config_.max_upload_size) {
        return HttpResponse::error(400, "File too large");
    }
    
    // 生成年月子目录
    auto now = std::time(nullptr);
    std::tm* tm_info = std::localtime(&now);
    char date_path[32];
    std::strftime(date_path, sizeof(date_path), "%Y/%m/%d", tm_info);
    
    std::string full_dir = config_.media_dir + "/" + date_path;
    std::string mkdir_cmd = "mkdir -p " + full_dir;
    system(mkdir_cmd.c_str());
    
    // 生成唯一文件名
    auto timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()
    ).count();
    
    std::string extension;
    size_t dot_pos = file_name.find_last_of('.');
    if (dot_pos != std::string::npos) {
        extension = file_name.substr(dot_pos);
    }
    
    std::ostringstream unique_name;
    unique_name << user_id << "_" << timestamp << extension;
    std::string saved_filename = unique_name.str();
    std::string file_path = full_dir + "/" + saved_filename;
    
    // 写入文件
    std::ofstream out_file(file_path, std::ios::binary);
    if (!out_file) {
        return HttpResponse::error(500, "Failed to save file");
    }
    out_file.write(reinterpret_cast<const char*>(file_data.data()), file_data.size());
    out_file.close();
    
    // 保存到数据库
    uint64_t file_id = 0;
    std::string url;
    
    if (database_) {
        // 调用数据库保存
        if (!database_->save_media_file(user_id, saved_filename, file_path,
                                         static_cast<MediaType>(media_type),
                                         file_id, url)) {
            std::remove(file_path.c_str());
            return HttpResponse::error(500, "Failed to save file info");
        }
    }
    
    // 构建响应 URL
    std::ostringstream url_stream;
    url_stream << "/media/" << file_id << "/" << saved_filename;
    
    std::ostringstream resp_json;
    resp_json << "{"
              << "\"code\":0,"
              << "\"data\":{" 
              << "\"file_id\":" << file_id << ","
              << "\"url\":\"" << url_stream.str() << "\","
              << "\"file_name\":\"" << file_name << "\","
              << "\"file_size\":" << file_data.size() << ","
              << "\"media_type\":" << media_type
              << "}}";
    
    std::cout << "[HttpGateway] File uploaded: " << saved_filename 
              << " (" << file_data.size() << " bytes) for user " << user_id << std::endl;
    
    return HttpResponse::json(200, resp_json.str());
}

// ==================== 文件下载处理 ====================

HttpResponse HttpGateway::handle_download(const HttpRequest& request) {
    // 解析路径: /media/{file_id}/{filename} 或 /media/{filename}
    std::string path = request.path;
    
    // 移除 /media/ 前缀
    if (path.find("/media/") == 0) {
        path = path.substr(7);
    } else if (path[0] == '/') {
        path = path.substr(1);
    }
    
    // 提取文件名
    std::string filename;
    size_t slash_pos = path.find('/');
    if (slash_pos != std::string::npos) {
        filename = path.substr(slash_pos + 1);
    } else {
        filename = path;
    }
    
    if (filename.empty()) {
        return HttpResponse::error(400, "Invalid file path");
    }
    
    // 递归查找文件
    std::string filepath;
    std::function<std::string(const std::string&, const std::string&)> search_file;
    search_file = [&](const std::string& dir, const std::string& fname) -> std::string {
        DIR* dp = opendir(dir.c_str());
        if (!dp) return "";
        
        struct dirent* entry;
        while ((entry = readdir(dp)) != nullptr) {
            if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
                continue;
            
            std::string full_path = dir + "/" + entry->d_name;
            
            if (entry->d_type == DT_DIR) {
                std::string result = search_file(full_path, fname);
                if (!result.empty()) {
                    closedir(dp);
                    return result;
                }
            } else if (strcmp(entry->d_name, fname.c_str()) == 0) {
                closedir(dp);
                return full_path;
            }
        }
        closedir(dp);
        return "";
    };
    
    filepath = search_file(config_.media_dir, filename);
    
    if (filepath.empty()) {
        return HttpResponse::error(404, "File not found");
    }
    
    // 读取文件
    std::ifstream file(filepath, std::ios::binary);
    if (!file) {
        return HttpResponse::error(500, "Failed to read file");
    }
    
    std::vector<uint8_t> content((std::istreambuf_iterator<char>(file)),
                                  std::istreambuf_iterator<char>());
    
    std::string mime_type = get_mime_type(filename);
    
    std::cout << "[HttpGateway] File served: " << filename 
              << " (" << content.size() << " bytes)" << std::endl;
    
    return HttpResponse::file(content, mime_type);
}

// ==================== Token 验证 ====================

bool HttpGateway::verify_token(const std::string& token, uint64_t& user_id) {
    // 支持多种格式:
    // 1. Bearer <token>
    // 2. <user_id>:<session_token>
    
    if (token.empty()) {
        return false;
    }
    
    std::string clean_token = token;
    if (token.find("Bearer ") == 0) {
        clean_token = token.substr(7);
    }
    
    // 解析 user_id:token 格式
    size_t colon_pos = clean_token.find(':');
    if (colon_pos != std::string::npos) {
        try {
            user_id = std::stoull(clean_token.substr(0, colon_pos));
            // TODO: 验证 session token
            return true;
        } catch (...) {
            return false;
        }
    }
    
    // TODO: 实现更完整的 token 验证
    // 目前简单验证，后续可以添加 JWT 或 session 验证
    return true;
}

// ==================== MIME 类型 ====================

std::string HttpGateway::get_mime_type(const std::string& filename) {
    static std::map<std::string, std::string> mime_types = {
        {".jpg", "image/jpeg"},
        {".jpeg", "image/jpeg"},
        {".png", "image/png"},
        {".gif", "image/gif"},
        {".webp", "image/webp"},
        {".bmp", "image/bmp"},
        {".svg", "image/svg+xml"},
        {".mp4", "video/mp4"},
        {".webm", "video/webm"},
        {".mp3", "audio/mpeg"},
        {".wav", "audio/wav"},
        {".ogg", "audio/ogg"},
        {".pdf", "application/pdf"},
        {".doc", "application/msword"},
        {".docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"},
        {".xls", "application/vnd.ms-excel"},
        {".xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"},
        {".ppt", "application/vnd.ms-powerpoint"},
        {".pptx", "application/vnd.openxmlformats-officedocument.presentationml.presentation"},
        {".zip", "application/zip"},
        {".rar", "application/x-rar-compressed"},
        {".7z", "application/x-7z-compressed"},
        {".txt", "text/plain"},
        {".html", "text/html"},
        {".css", "text/css"},
        {".js", "application/javascript"},
        {".json", "application/json"},
        {".xml", "application/xml"},
        {".apk", "application/vnd.android.package-archive"},
    };
    
    size_t dot_pos = filename.find_last_of('.');
    if (dot_pos != std::string::npos) {
        std::string ext = filename.substr(dot_pos);
        for (auto& c : ext) c = std::tolower(c);
        
        auto it = mime_types.find(ext);
        if (it != mime_types.end()) {
            return it->second;
        }
    }
    return "application/octet-stream";
}

} // namespace chat
