#ifndef RUNNER_PLATFORM_SERVICES_H_
#define RUNNER_PLATFORM_SERVICES_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <string>
#include <vector>

// Implements the same channel contract as the macOS runner.
class PlatformServices {
 public:
  PlatformServices(flutter::BinaryMessenger* messenger, HWND window,
                   const std::vector<std::string>& arguments);
  ~PlatformServices();

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> platform_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> archive_open_;
};

#endif  // RUNNER_PLATFORM_SERVICES_H_
