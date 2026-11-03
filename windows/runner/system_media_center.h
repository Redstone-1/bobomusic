#ifndef RUNNER_SYSTEM_MEDIA_CENTER_H_
#define RUNNER_SYSTEM_MEDIA_CENTER_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

#include <memory>

// 只桥接 Dart 命令与快照；异步系统事件经窗口消息回到 Flutter 平台线程。
class SystemMediaCenter {
 public:
  static constexpr UINT kDispatchMessage = WM_APP + 0x51;
  SystemMediaCenter(HWND window, flutter::BinaryMessenger* messenger);
  ~SystemMediaCenter();
  SystemMediaCenter(const SystemMediaCenter&) = delete;
  SystemMediaCenter& operator=(const SystemMediaCenter&) = delete;
  void DispatchPending();

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_SYSTEM_MEDIA_CENTER_H_
