-- xmake.lua for chat_app server
-- 更快的增量编译

set_project("chat_server")
set_version("1.0.0")
set_languages("c++17")

add_rules("mode.debug", "mode.release")

-- Termux 路径
local TERMUX_PREFIX = "/data/data/com.termux/files/usr"

-- 添加系统库路径
add_includedirs(TERMUX_PREFIX .. "/include")
add_linkdirs(TERMUX_PREFIX .. "/lib")

-- 通用编译选项
add_syslinks("pthread", "dl", "m")
add_defines("ASIO_STANDALONE", "ASIO_CPP14")

-- 主服务器 (包含 main.cpp)
target("chat_server")
    set_kind("binary")
    add_files("src/*.cpp")
    remove_files("src/gateway_main.cpp", "src/media_server.cpp", "src/gateway_server.cpp")
    add_includedirs("include")
    add_links("mariadb", "curl", "microhttpd", "ssl", "crypto", "qjs")

-- 媒体服务器
target("media_server")
    set_kind("binary")
    add_files("src/media_server.cpp")
    add_links("microhttpd")

-- 网关服务器 (排除 main.cpp, server.cpp, session.cpp, media_server.cpp, bot_manager.cpp, js_bot.cpp, gateway_server.cpp)
target("gateway_server")
    set_kind("binary")
    add_files("src/*.cpp")
    remove_files("src/main.cpp", "src/server.cpp", "src/session.cpp", "src/media_server.cpp", "src/bot_manager.cpp", "src/js_bot.cpp", "src/gateway_server.cpp")
    add_includedirs("include")
    add_links("mariadb", "curl", "microhttpd", "ssl", "crypto")
