/**
 * C++ HTTP Media File Server
 * 使用 libmicrohttpd 提供静态文件服务
 * 支持 CORS 跨域访问
 */

#include <microhttpd.h>
#include <iostream>
#include <string>
#include <fstream>
#include <sstream>
#include <map>
#include <dirent.h>
#include <sys/stat.h>
#include <cstring>
#include <cstdlib>
#include <functional>

int g_port = 8889;
#define MAX_FILE_SIZE (50 * 1024 * 1024) // 50MB

// 媒体目录
std::string g_media_dir = "media";

// MIME 类型映射
std::map<std::string, std::string> g_mime_types = {
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
};

// 获取文件的 MIME 类型
std::string get_mime_type(const std::string& filename) {
    size_t dot_pos = filename.find_last_of('.');
    if (dot_pos != std::string::npos) {
        std::string ext = filename.substr(dot_pos);
        // 转小写
        for (auto& c : ext) c = std::tolower(c);
        
        auto it = g_mime_types.find(ext);
        if (it != g_mime_types.end()) {
            return it->second;
        }
    }
    return "application/octet-stream";
}

// 递归查找文件的辅助函数
std::string search_file_in_dir(const std::string& dir, const std::string& filename);

// 递归查找文件
std::string find_file(const std::string& filename) {
    // 首先尝试直接路径
    std::string direct_path = g_media_dir + "/" + filename;
    struct stat st;
    if (stat(direct_path.c_str(), &st) == 0 && S_ISREG(st.st_mode)) {
        return direct_path;
    }
    
    // 递归搜索子目录
    return search_file_in_dir(g_media_dir, filename);
}

std::string search_file_in_dir(const std::string& dir, const std::string& filename) {
    DIR* dp = opendir(dir.c_str());
    if (!dp) return "";
    
    struct dirent* entry;
    while ((entry = readdir(dp)) != nullptr) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
            continue;
        
        std::string full_path = dir + "/" + entry->d_name;
        
        if (entry->d_type == DT_DIR) {
            std::string result = search_file_in_dir(full_path, filename);
            if (!result.empty()) {
                closedir(dp);
                return result;
            }
        } else if (strcmp(entry->d_name, filename.c_str()) == 0) {
            closedir(dp);
            return full_path;
        }
    }
    closedir(dp);
    return "";
}

// 读取文件内容
std::string read_file(const std::string& filepath) {
    std::ifstream file(filepath, std::ios::binary);
    if (!file) return "";
    
    std::ostringstream ss;
    ss << file.rdbuf();
    return ss.str();
}

// 获取文件大小
long get_file_size(const std::string& filepath) {
    struct stat st;
    if (stat(filepath.c_str(), &st) == 0) {
        return st.st_size;
    }
    return -1;
}

// HTTP 请求处理器
static MHD_Result handle_request(
    void* cls,
    struct MHD_Connection* connection,
    const char* url,
    const char* method,
    const char* version,
    const char* upload_data,
    size_t* upload_data_size,
    void** con_cls
) {
    // 处理 OPTIONS 预检请求
    if (strcmp(method, "OPTIONS") == 0) {
        struct MHD_Response* response = MHD_create_response_from_buffer(0, nullptr, MHD_RESPMEM_PERSISTENT);
        MHD_add_response_header(response, "Access-Control-Allow-Origin", "*");
        MHD_add_response_header(response, "Access-Control-Allow-Methods", "GET, OPTIONS");
        MHD_add_response_header(response, "Access-Control-Allow-Headers", "*");
        MHD_queue_response(connection, MHD_HTTP_OK, response);
        MHD_destroy_response(response);
        return MHD_YES;
    }
    
    // 只处理 GET 和 HEAD 请求
    if (strcmp(method, "GET") != 0 && strcmp(method, "HEAD") != 0) {
        struct MHD_Response* response = MHD_create_response_from_buffer(
            strlen("Method Not Allowed"),
            (void*)"Method Not Allowed",
            MHD_RESPMEM_PERSISTENT
        );
        MHD_queue_response(connection, MHD_HTTP_METHOD_NOT_ALLOWED, response);
        MHD_destroy_response(response);
        return MHD_YES;
    }
    
    // 解析 URL: /media/<file_id>/<filename> 或 /<filename>
    std::string path = url;
    std::string filename;
    
    // 移除 /media/ 前缀
    if (path.find("/media/") == 0) {
        path = path.substr(7);
    } else if (path[0] == '/') {
        path = path.substr(1);
    }
    
    // 提取文件名（跳过 file_id 部分）
    size_t slash_pos = path.find('/');
    if (slash_pos != std::string::npos) {
        filename = path.substr(slash_pos + 1);
    } else {
        filename = path;
    }
    
    if (filename.empty()) {
        struct MHD_Response* response = MHD_create_response_from_buffer(
            strlen("Bad Request"),
            (void*)"Bad Request",
            MHD_RESPMEM_PERSISTENT
        );
        MHD_queue_response(connection, MHD_HTTP_BAD_REQUEST, response);
        MHD_destroy_response(response);
        return MHD_YES;
    }
    
    // 查找文件
    std::string filepath = find_file(filename);
    if (filepath.empty()) {
        struct MHD_Response* response = MHD_create_response_from_buffer(
            strlen("Not Found"),
            (void*)"Not Found",
            MHD_RESPMEM_PERSISTENT
        );
        MHD_queue_response(connection, MHD_HTTP_NOT_FOUND, response);
        MHD_destroy_response(response);
        return MHD_YES;
    }
    
    // 获取文件信息
    long file_size = get_file_size(filepath);
    if (file_size < 0 || file_size > MAX_FILE_SIZE) {
        struct MHD_Response* response = MHD_create_response_from_buffer(
            strlen("Internal Server Error"),
            (void*)"Internal Server Error",
            MHD_RESPMEM_PERSISTENT
        );
        MHD_queue_response(connection, MHD_HTTP_INTERNAL_SERVER_ERROR, response);
        MHD_destroy_response(response);
        return MHD_YES;
    }
    
    std::string mime_type = get_mime_type(filename);
    
    // HEAD 请求只返回头部
    if (strcmp(method, "HEAD") == 0) {
        struct MHD_Response* response = MHD_create_response_from_buffer(0, nullptr, MHD_RESPMEM_PERSISTENT);
        MHD_add_response_header(response, "Content-Type", mime_type.c_str());
        MHD_add_response_header(response, "Content-Length", std::to_string(file_size).c_str());
        MHD_add_response_header(response, "Access-Control-Allow-Origin", "*");
        MHD_add_response_header(response, "Cache-Control", "public, max-age=86400");
        MHD_queue_response(connection, MHD_HTTP_OK, response);
        MHD_destroy_response(response);
        return MHD_YES;
    }
    
    // GET 请求：读取并返回文件内容
    std::string content = read_file(filepath);
    if (content.empty()) {
        struct MHD_Response* response = MHD_create_response_from_buffer(
            strlen("Internal Server Error"),
            (void*)"Internal Server Error",
            MHD_RESPMEM_PERSISTENT
        );
        MHD_queue_response(connection, MHD_HTTP_INTERNAL_SERVER_ERROR, response);
        MHD_destroy_response(response);
        return MHD_YES;
    }
    
    struct MHD_Response* response = MHD_create_response_from_buffer(
        content.size(),
        (void*)content.data(),
        MHD_RESPMEM_MUST_COPY
    );
    
    MHD_add_response_header(response, "Content-Type", mime_type.c_str());
    MHD_add_response_header(response, "Content-Length", std::to_string(content.size()).c_str());
    MHD_add_response_header(response, "Access-Control-Allow-Origin", "*");
    MHD_add_response_header(response, "Cache-Control", "public, max-age=86400");
    
    MHD_queue_response(connection, MHD_HTTP_OK, response);
    MHD_destroy_response(response);
    
    std::cout << "[MediaServer] " << method << " " << url << " -> " << filename 
              << " (" << content.size() << " bytes)" << std::endl;
    
    return MHD_YES;
}

int main(int argc, char* argv[]) {
    // 解析命令行参数
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if ((arg == "--dir" || arg == "-d") && i + 1 < argc) {
            g_media_dir = argv[++i];
        } else if ((arg == "--port" || arg == "-p") && i + 1 < argc) {
            int port = std::stoi(argv[++i]);
            if (port > 0 && port < 65536) {
                g_port = port;
            }
        } else if (arg == "--help" || arg == "-h") {
            std::cout << "Usage: " << argv[0] << " [options]\n"
                      << "Options:\n"
                      << "  -d, --dir <directory>  Media directory (default: media)\n"
                      << "  -p, --port <port>      Server port (default: 8889)\n"
                      << "  -h, --help             Show this help message\n";
            return 0;
        }
    }
    
    // 创建媒体目录
    mkdir(g_media_dir.c_str(), 0755);
    
    // 启动服务器
    struct MHD_Daemon* daemon = MHD_start_daemon(
        MHD_USE_THREAD_PER_CONNECTION,
        g_port,
        nullptr,
        nullptr,
        &handle_request,
        nullptr,
        MHD_OPTION_END
    );
    
    if (!daemon) {
        std::cerr << "Failed to start media server on port " << g_port << std::endl;
        return 1;
    }
    
    std::cout << "C++ Media server started on port " << g_port << std::endl;
    std::cout << "Serving files from: " << g_media_dir << std::endl;
    std::cout << "Press Ctrl+C to stop" << std::endl;
    
    // 等待信号
    while (true) {
        sleep(1);
    }
    
    MHD_stop_daemon(daemon);
    return 0;
}
