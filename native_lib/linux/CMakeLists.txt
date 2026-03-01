cmake_minimum_required(VERSION 3.10)
project(native_input C)

set(CMAKE_C_STANDARD 11)

# Find PulseAudio
find_package(PkgConfig REQUIRED)
pkg_check_modules(PULSE REQUIRED libpulse-simple libpulse)

add_library(native_input SHARED native_input.c)

target_include_directories(native_input PRIVATE ${PULSE_INCLUDE_DIRS})
target_link_libraries(native_input ${PULSE_LIBRARIES} pthread dl m)
target_compile_options(native_input PRIVATE -Wall -Wextra -fvisibility=hidden)

# Output to project root native_lib directory
set_target_properties(native_input PROPERTIES
    PREFIX "lib"
    OUTPUT_NAME "native_input"
)
