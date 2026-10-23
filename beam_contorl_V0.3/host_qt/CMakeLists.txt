cmake_minimum_required(VERSION 3.21)
project(beam_control_host VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Widgets SerialPort)

add_library(beam_protocol src/protocol.cpp src/protocol.h)
target_include_directories(beam_protocol PUBLIC src)
target_compile_options(beam_protocol PRIVATE $<$<CXX_COMPILER_ID:MSVC>:/utf-8>)

add_executable(beam_control_host WIN32
    src/main.cpp
    src/mainwindow.cpp
    src/mainwindow.h
)
target_link_libraries(beam_control_host PRIVATE beam_protocol Qt6::Core Qt6::Widgets Qt6::SerialPort)
target_compile_options(beam_control_host PRIVATE $<$<CXX_COMPILER_ID:MSVC>:/utf-8>)

include(CTest)
if(BUILD_TESTING)
    find_package(Qt6 6.5 REQUIRED COMPONENTS Test)
    add_executable(protocol_tests tests/protocol_tests.cpp)
    target_link_libraries(protocol_tests PRIVATE beam_protocol)
    target_compile_options(protocol_tests PRIVATE $<$<CXX_COMPILER_ID:MSVC>:/utf-8>)
    add_test(NAME protocol_tests COMMAND protocol_tests)
    add_executable(ui_smoke tests/ui_smoke.cpp src/mainwindow.cpp src/mainwindow.h)
    target_link_libraries(ui_smoke PRIVATE beam_protocol Qt6::Core Qt6::Widgets Qt6::SerialPort Qt6::Test)
    target_compile_options(ui_smoke PRIVATE $<$<CXX_COMPILER_ID:MSVC>:/utf-8>)
    add_test(NAME ui_smoke COMMAND ui_smoke)
    set_tests_properties(ui_smoke PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
