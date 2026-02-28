cmake_minimum_required(VERSION 3.15)
project(native_input LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)

add_library(native_input SHARED native_input.cpp)

target_link_libraries(native_input PRIVATE
    user32      # Keyboard hooks, SendInput
    ole32       # COM (CoCreateInstance)
    oleaut32    # PROPVARIANT helpers
    propsys     # Property system
    avrt        # Audio thread priority
    uuid        # WASAPI GUIDs
)

# Output to project root native_lib directory
set_target_properties(native_input PROPERTIES
    OUTPUT_NAME "native_input"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/.."
)
