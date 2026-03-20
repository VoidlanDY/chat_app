cmake_minimum_required(VERSION 3.16)
project(chat_server VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Termux 路径
set(TERMUX_PREFIX "/data/data/com.termux/files/usr")

# 查找依赖
find_package(Threads REQUIRED)
find_package(OpenSSL REQUIRED)

# ASIO (header-only) - 优先使用系统路径
find_path(ASIO_INCLUDE_DIR NAMES asio.hpp PATHS /usr/include ${TERMUX_PREFIX}/include)

# nlohmann_json
find_package(nlohmann_json 3.2.0 REQUIRED)

# QuickJS - 手动查找，因为没有 CMake config
find_path(QJS_INCLUDE_DIR NAMES quickjs.h PATHS /usr/include/quickjs)
find_library(QJS_LIBRARY NAMES quickjs PATHS /usr/lib/aarch64-linux-gnu/quickjs /usr/lib/quickjs /usr/lib)

if(NOT QJS_INCLUDE_DIR OR NOT QJS_LIBRARY)
    message(FATAL_ERROR "QuickJS not found!")
endif()
message(STATUS "QuickJS include: ${QJS_INCLUDE_DIR}, lib: ${QJS_LIBRARY}")

# libcurl - 优先使用系统路径
find_path(CURL_INCLUDE_DIR NAMES curl/curl.h PATHS /usr/include ${TERMUX_PREFIX}/include)
find_library(CURL_LIBRARY NAMES curl PATHS /usr/lib/aarch64-linux-gnu /usr/lib ${TERMUX_PREFIX}/lib)

# MariaDB/MySQL - 优先使用系统路径
find_path(MYSQL_INCLUDE_DIR NAMES mysql.h PATHS 
    /usr/include/mariadb
    /usr/include/mysql
    /usr/include
    ${TERMUX_PREFIX}/include/mariadb
    ${TERMUX_PREFIX}/include/mysql
    ${TERMUX_PREFIX}/include
)
find_library(MYSQL_LIBRARY NAMES 
    mariadb 
    mysqlclient 
    mysql
    PATHS 
    /usr/lib/aarch64-linux-gnu
    /usr/lib 
    ${TERMUX_PREFIX}/lib 
)

if(NOT MYSQL_INCLUDE_DIR OR NOT MYSQL_LIBRARY)
    message(STATUS "MySQL/MariaDB not found, checking for alternative headers...")
    # 检查 mariadb 有哪些头文件
    file(GLOB MYSQL_HEADERS "${TERMUX_PREFIX}/include/mariadb/*.h")
    if(MYSQL_HEADERS)
        set(MYSQL_INCLUDE_DIR "${TERMUX_PREFIX}/include/mariadb")
    endif()
endif()

# libmicrohttpd for media server - 优先使用系统路径
find_path(MHD_INCLUDE_DIR NAMES microhttpd.h PATHS /usr/include ${TERMUX_PREFIX}/include)
find_library(MHD_LIBRARY NAMES microhttpd PATHS /usr/lib/aarch64-linux-gnu /usr/lib ${TERMUX_PREFIX}/lib)

# 打印找到的路径
message(STATUS "ASIO include: ${ASIO_INCLUDE_DIR}")
message(STATUS "CURL include: ${CURL_INCLUDE_DIR}, lib: ${CURL_LIBRARY}")
message(STATUS "MySQL include: ${MYSQL_INCLUDE_DIR}, lib: ${MYSQL_LIBRARY}")
message(STATUS "MHD include: ${MHD_INCLUDE_DIR}, lib: ${MHD_LIBRARY}")

# 服务器可执行文件
add_executable(chat_server
    src/main.cpp
    src/server.cpp
    src/session.cpp
    src/database.cpp
    src/database_pool.cpp
    src/user_manager.cpp
    src/message_manager.cpp
    src/group_manager.cpp
    src/friend_manager.cpp
    src/deepseek_client.cpp
    src/bot_manager.cpp
    src/js_bot.cpp
    src/fcm_manager.cpp
    src/jpush_manager.cpp
    src/thread_pool_v2.cpp
    src/http_gateway.cpp
)

target_include_directories(chat_server PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${ASIO_INCLUDE_DIR}
    ${MYSQL_INCLUDE_DIR}
    ${CURL_INCLUDE_DIR}
    ${QJS_INCLUDE_DIR}
)

target_link_libraries(chat_server PRIVATE
    Threads::Threads
    OpenSSL::SSL
    OpenSSL::Crypto
    ${MYSQL_LIBRARY}
    ${CURL_LIBRARY}
    ${MHD_LIBRARY}
    nlohmann_json::nlohmann_json
    ${QJS_LIBRARY}
    dl
    m
)

target_compile_definitions(chat_server PRIVATE
    ASIO_STANDALONE
    ASIO_CPP14
)

# 编译选项
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(chat_server PRIVATE
        -Wall
        -Wextra
        -Wpedantic
        -O2
    )
endif()

# 媒体服务器可执行文件
add_executable(media_server
    src/media_server.cpp
)

target_include_directories(media_server PRIVATE
    ${MHD_INCLUDE_DIR}
)

target_link_libraries(media_server PRIVATE
    ${MHD_LIBRARY}
)

# 网关服务器可执行文件 (统一入口 - WebSocket + HTTP)
add_executable(gateway_server
    src/gateway_main.cpp
    src/server.cpp
    src/session.cpp
    src/websocket_server.cpp
    src/http_gateway.cpp
    src/database.cpp
    src/database_pool.cpp
    src/user_manager.cpp
    src/message_manager.cpp
    src/group_manager.cpp
    src/friend_manager.cpp
    src/deepseek_client.cpp
    src/bot_manager.cpp
    src/js_bot.cpp
    src/fcm_manager.cpp
    src/jpush_manager.cpp
    src/thread_pool_v2.cpp
)

target_include_directories(gateway_server PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${ASIO_INCLUDE_DIR}
    ${MYSQL_INCLUDE_DIR}
    ${CURL_INCLUDE_DIR}
    ${MHD_INCLUDE_DIR}
    ${QJS_INCLUDE_DIR}
)

target_link_libraries(gateway_server PRIVATE
    Threads::Threads
    OpenSSL::SSL
    OpenSSL::Crypto
    ${MYSQL_LIBRARY}
    ${CURL_LIBRARY}
    ${MHD_LIBRARY}
    nlohmann_json::nlohmann_json
    ${QJS_LIBRARY}
    dl
    m
)

target_compile_definitions(gateway_server PRIVATE
    ASIO_STANDALONE
    ASIO_CPP14
)

# 安装
install(TARGETS chat_server media_server gateway_server DESTINATION bin)
