cmake_minimum_required(VERSION 3.14)
project(openbubbles_password_host LANGUAGES CXX)

# Native messaging host for the Passwords browser extension; installed next to the app.
add_executable(openbubbles_password_host "main.cpp")
target_compile_features(openbubbles_password_host PRIVATE cxx_std_17)
target_compile_definitions(openbubbles_password_host PRIVATE "NOMINMAX" "WIN32_LEAN_AND_MEAN" "_CRT_SECURE_NO_WARNINGS")
target_link_libraries(openbubbles_password_host PRIVATE ws2_32)
