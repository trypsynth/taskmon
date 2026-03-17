cmake_minimum_required(VERSION 3.20)
project(taskmon LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

file(GLOB SOURCES CONFIGURE_DEPENDS "src/*.cpp")
add_executable(taskmon WIN32 ${SOURCES})
target_compile_definitions(taskmon PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(taskmon PRIVATE comctl32 shell32)
