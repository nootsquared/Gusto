cmake_minimum_required(VERSION 3.21)

set(FWOG_BSP_PATH "${CMAKE_CURRENT_LIST_DIR}/third_party/wiliOGbsp" CACHE PATH
    "Path to the FreeWili OG board-support package")
get_filename_component(FWOG_BSP_PATH "${FWOG_BSP_PATH}" ABSOLUTE)

if(NOT EXISTS "${FWOG_BSP_PATH}/bsp/CMakeLists.txt")
    message(FATAL_ERROR "FreeWili BSP not found. Follow the dependency setup in README.md.")
endif()

set(PICO_BOARD freewili_og CACHE STRING "Board type" FORCE)
list(APPEND PICO_BOARD_HEADER_DIRS "${FWOG_BSP_PATH}/bsp/boards")
set(PICO_STDIO_UART 0 CACHE BOOL "UART stdio" FORCE)
include("${FWOG_BSP_PATH}/pico_sdk_import.cmake")

project(free_wili_screen C CXX ASM)
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(Python3 COMPONENTS Interpreter REQUIRED)
pico_sdk_init()

set(APP_VERSION 012)
set(FWOG_GIT_DESCRIBE "climate-${APP_VERSION}")
set(FWOG_GIT_COMMIT_TS 0)
add_subdirectory("${FWOG_BSP_PATH}/bsp" "${CMAKE_BINARY_DIR}/bsp")

add_library(climate_protocol common/climate_protocol.c)
target_include_directories(climate_protocol PUBLIC common)
target_link_libraries(climate_protocol PUBLIC m)

add_executable(climate_display display/main.c)
target_link_libraries(climate_display PRIVATE fwog_display_bsp climate_protocol)
target_compile_options(climate_display PRIVATE -Wall -Wextra)
fwog_display_app(climate_display
    VERSION ${APP_VERSION}
    DESCRIPTION "Live Nano Fahrenheit/Celsius, humidity and light counts; manual warnings")

add_executable(climate_main main/main.c)
target_link_libraries(climate_main PRIVATE fwog_main_bsp climate_protocol hardware_uart)
target_compile_options(climate_main PRIVATE -Wall -Wextra)
fwog_embed_display_image(climate_main)
fwog_main_app(climate_main
    VERSION ${APP_VERSION}
    DESCRIPTION "Nano UART receiver and ping bridge with paired climate display")
