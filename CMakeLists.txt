cmake_minimum_required(VERSION 3.20)
project(taskmon LANGUAGES C)

file(GLOB SOURCES CONFIGURE_DEPENDS "src/*.c" "src/*.rc")
add_executable(taskmon WIN32 ${SOURCES})
target_compile_definitions(taskmon PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
if(MSVC)
	target_compile_options(taskmon PRIVATE /GS- /W4 /Os /Oy /std:c17 /Zc:preprocessor)
	target_link_options(taskmon PRIVATE /NODEFAULTLIB /ENTRY:WinMainCRTStartup /SUBSYSTEM:WINDOWS /OPT:REF /OPT:ICF /MERGE:.rdata=.text /MERGE:.pdata=.text)
endif()
target_link_libraries(taskmon PRIVATE kernel32 user32 gdi32 shell32 comctl32 ole32 shlwapi ntdll advapi32 dwmapi uxtheme comdlg32 version pdh)

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

find_program(ISCC_EXECUTABLE ISCC)
if(ISCC_EXECUTABLE)
	if(CMAKE_VS_PLATFORM_NAME STREQUAL "ARM64")
		set(TASKMON_INSTALLER_ARCH "arm64")
	else()
		set(TASKMON_INSTALLER_ARCH "x64")
	endif()
	if(DEFINED ENV{TASKMON_VERSION})
		set(TASKMON_VERSION "$ENV{TASKMON_VERSION}")
	else()
		set(TASKMON_VERSION "0.2.1")
	endif()
	add_custom_target(installer ALL
		COMMAND ${ISCC_EXECUTABLE}
				"/DMyAppArch=${TASKMON_INSTALLER_ARCH}"
				"/DMyAppVersion=${TASKMON_VERSION}"
				"/DSourceExeDir=$<TARGET_FILE_DIR:taskmon>"
				"/DMyOutputDir=${CMAKE_BINARY_DIR}"
				"${CMAKE_CURRENT_SOURCE_DIR}/installer/taskmon.iss"
		DEPENDS taskmon
		COMMENT "Building Inno Setup installer (${TASKMON_INSTALLER_ARCH})"
		VERBATIM
	)
endif()
