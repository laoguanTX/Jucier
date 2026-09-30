cmake_minimum_required(VERSION 3.14)
project(jucier_shell_tests LANGUAGES CXX)
enable_testing()
add_executable(shell_integration_test
  "shell_integration_test.cpp"
  "../../windows/runner/shell_integration.cpp")
target_compile_features(shell_integration_test PRIVATE cxx_std_17)
target_compile_options(shell_integration_test PRIVATE /W4 /WX /utf-8)
target_compile_definitions(shell_integration_test PRIVATE NOMINMAX)
target_link_libraries(shell_integration_test PRIVATE shell32 advapi32 ole32 uuid)
add_test(NAME shell_integration COMMAND shell_integration_test)

# After a Flutter Windows build, also verify the actual native frame while its
# window remains hidden. The shell tests above do not require Flutter.
set(FLUTTER_EPHEMERAL "${CMAKE_CURRENT_SOURCE_DIR}/../../windows/flutter/ephemeral")
if(EXISTS "${FLUTTER_EPHEMERAL}/flutter_windows.dll.lib")
  add_executable(window_frame_test "window_frame_test.cpp"
    "../../windows/runner/win32_window.cpp")
  target_compile_features(window_frame_test PRIVATE cxx_std_17)
  target_compile_options(window_frame_test PRIVATE /W4 /WX /utf-8)
  target_compile_definitions(window_frame_test PRIVATE NOMINMAX UNICODE _UNICODE)
  target_include_directories(window_frame_test PRIVATE "${FLUTTER_EPHEMERAL}")
  target_link_libraries(window_frame_test PRIVATE dwmapi comctl32 advapi32
    "${FLUTTER_EPHEMERAL}/flutter_windows.dll.lib")
  add_custom_command(TARGET window_frame_test POST_BUILD COMMAND ${CMAKE_COMMAND}
    -E copy_if_different "${FLUTTER_EPHEMERAL}/flutter_windows.dll"
    "$<TARGET_FILE_DIR:window_frame_test>")
  add_test(NAME window_frame COMMAND window_frame_test)
endif()
