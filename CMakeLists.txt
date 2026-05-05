cmake_minimum_required(VERSION 3.20)
project(taskmon LANGUAGES C)

file(GLOB SOURCES CONFIGURE_DEPENDS "src/*.c" "src/*.rc")
add_executable(taskmon WIN32 ${SOURCES})
target_compile_definitions(taskmon PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
if(MSVC)
	target_compile_options(taskmon PRIVATE /GS- /W4 /Os /Oy)
	target_link_options(taskmon PRIVATE /NODEFAULTLIB /ENTRY:WinMainCRTStartup /SUBSYSTEM:WINDOWS /OPT:REF /OPT:ICF /MERGE:.rdata=.text /MERGE:.pdata=.text)
endif()
target_link_libraries(taskmon PRIVATE kernel32 user32 gdi32 shell32 comctl32 ole32 shlwapi ntdll advapi32 dwmapi uxtheme comdlg32 version)

find_program(PANDOC_EXECUTABLE pandoc)
if(PANDOC_EXECUTABLE)
    add_custom_command(
        OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/readme.html"
        COMMAND ${PANDOC_EXECUTABLE} -s "${CMAKE_CURRENT_SOURCE_DIR}/doc/readme.md" -o "${CMAKE_CURRENT_BINARY_DIR}/readme.html"
        DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/doc/readme.md"
        COMMENT "Generating HTML documentation from README.md"
    )
    add_custom_target(doc ALL DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/readme.html")
endif()
