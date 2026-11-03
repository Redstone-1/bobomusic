#include "system_media_center.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <roapi.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>
#include <systemmediatransportcontrolsinterop.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <deque>
#include <exception>
#include <limits>
#include <mutex>
#include <string>
#include <utility>

namespace {
using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::Foundation::AsyncStatus;
using winrt::Windows::Foundation::TimeSpan;
using winrt::Windows::Media::MediaPlaybackStatus;
using winrt::Windows::Media::MediaPlaybackType;
using winrt::Windows::Media::SystemMediaTransportControls;
using winrt::Windows::Media::SystemMediaTransportControlsButton;
using winrt::Windows::Storage::StorageFile;
using winrt::Windows::Storage::Streams::RandomAccessStreamReference;

const EncodableValue* Value(const EncodableMap& map, const char* key) {
  const auto found = map.find(EncodableValue(key));
  return found == map.end() ? nullptr : &found->second;
}

std::string Text(const EncodableMap& map, const char* key) {
  const auto value = Value(map, key);
  const auto text = value ? std::get_if<std::string>(value) : nullptr;
  return text ? *text : "";
}

double Number(const EncodableMap& map, const char* key, double fallback = 0) {
  const auto value = Value(map, key);
  if (!value) return fallback;
  if (const auto number = std::get_if<int32_t>(value)) return *number;
  if (const auto number = std::get_if<int64_t>(value)) return static_cast<double>(*number);
  if (const auto number = std::get_if<double>(value)) return *number;
  return fallback;
}

bool Flag(const EncodableMap& map, const char* key) {
  const auto value = Value(map, key);
  const auto flag = value ? std::get_if<bool>(value) : nullptr;
  return flag && *flag;
}

TimeSpan MediaTime(double milliseconds) {
  // 防止无效载荷溢出 WinRT 的 100ns 时间单位。
  const auto safe = std::isfinite(milliseconds)
      ? std::clamp(milliseconds, 0.0, 9.0e14) : 0.0;
  return TimeSpan{static_cast<int64_t>(safe * 10000.0)};
}

struct Pending {
  std::string method;
  EncodableValue argument;
  uint64_t cover_generation = 0;
  RandomAccessStreamReference thumbnail{nullptr};
};

struct DispatchState {
  std::mutex mutex;
  HWND window = nullptr;
  bool alive = true;
  std::deque<Pending> pending;
};

void Queue(const std::weak_ptr<DispatchState>& weak, Pending event) {
  if (const auto state = weak.lock()) {
    std::lock_guard<std::mutex> lock(state->mutex);
    if (!state->alive) return;
    state->pending.push_back(std::move(event));
    // 不把堆指针放入消息参数；关闭窗口时可统一清空，迟到回调只持有弱引用。
    if (!PostMessage(state->window, SystemMediaCenter::kDispatchMessage, 0, 0)) {
      state->pending.pop_back();
    }
  }
}
}  // namespace

struct SystemMediaCenter::Impl {
  std::shared_ptr<DispatchState> dispatch = std::make_shared<DispatchState>();
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;
  SystemMediaTransportControls controls{nullptr};
  SystemMediaTransportControls::ButtonPressed_revoker buttons;
  SystemMediaTransportControls::PlaybackPositionChangeRequested_revoker seek;
  SystemMediaTransportControls::PlaybackRateChangeRequested_revoker speed;
  HRESULT runtime = E_FAIL;
  uint64_t cover_generation = 0;
  std::string cover_path;
  std::string track_id;
  std::string title;
  std::string artist;

  Impl(HWND window, flutter::BinaryMessenger* messenger) {
    dispatch->window = window;
    runtime = RoInitialize(RO_INIT_SINGLETHREADED);
    channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
        messenger, "com.bobomusic/media_center",
        &flutter::StandardMethodCodec::GetInstance());
    channel->SetMethodCallHandler([this](const auto& call, auto result) {
      try {
        if (call.method_name() == "stop") {
          Stop();
        } else if (call.method_name() == "update") {
          const auto map = call.arguments() ? std::get_if<EncodableMap>(call.arguments()) : nullptr;
          if (!map) {
            result->Error("invalid_snapshot", "媒体快照格式无效");
            return;
          }
          EnsureControls();
          Update(*map);
        } else {
          result->NotImplemented();
          return;
        }
        result->Success();
      } catch (const winrt::hresult_error& error) {
        Reset();
        result->Error("smtc_unavailable", winrt::to_string(error.message()));
      } catch (const std::exception& error) {
        Reset();
        result->Error("smtc_error", error.what());
      }
    });
  }

  ~Impl() {
    channel->SetMethodCallHandler(nullptr);
    {
      std::lock_guard<std::mutex> lock(dispatch->mutex);
      dispatch->alive = false;
      dispatch->pending.clear();
    }
    Reset();
    channel.reset();
    if (SUCCEEDED(runtime)) RoUninitialize();
  }

  void EnsureControls() {
    if (controls) return;
    winrt::check_hresult(runtime);
    const auto factory = winrt::get_activation_factory<
        SystemMediaTransportControls, ISystemMediaTransportControlsInterop>();
    winrt::check_hresult(factory->GetForWindow(dispatch->window,
        winrt::guid_of<SystemMediaTransportControls>(), winrt::put_abi(controls)));
    const std::weak_ptr<DispatchState> weak = dispatch;
    buttons = controls.ButtonPressed(winrt::auto_revoke, [weak](const auto&, const auto& args) {
      Pending event;
      switch (args.Button()) {
        case SystemMediaTransportControlsButton::Play: event.method = "play"; break;
        case SystemMediaTransportControlsButton::Pause: event.method = "pause"; break;
        case SystemMediaTransportControlsButton::Next: event.method = "next"; break;
        case SystemMediaTransportControlsButton::Previous: event.method = "previous"; break;
        case SystemMediaTransportControlsButton::Stop: event.method = "stop"; break;
        default: return;
      }
      Queue(weak, std::move(event));
    });
    seek = controls.PlaybackPositionChangeRequested(winrt::auto_revoke, [weak](const auto&, const auto& args) {
      Pending event;
      event.method = "seek";
      event.argument = EncodableValue(static_cast<int64_t>(args.RequestedPlaybackPosition().count() / 10000));
      Queue(weak, std::move(event));
    });
    speed = controls.PlaybackRateChangeRequested(winrt::auto_revoke, [weak](const auto&, const auto& args) {
      Pending event;
      event.method = "setSpeed";
      event.argument = EncodableValue(args.RequestedPlaybackRate());
      Queue(weak, std::move(event));
    });
    controls.IsPlayEnabled(true);
    controls.IsPauseEnabled(true);
    controls.IsNextEnabled(true);
    controls.IsPreviousEnabled(true);
    controls.IsStopEnabled(true);
  }

  void Update(const EncodableMap& map) {
    controls.IsEnabled(true);
    controls.PlaybackStatus(Flag(map, "buffering") ? MediaPlaybackStatus::Changing :
        Flag(map, "playing") ? MediaPlaybackStatus::Playing : MediaPlaybackStatus::Paused);
    const auto rate = Number(map, "speed", 1);
    controls.PlaybackRate(std::isfinite(rate) ? std::clamp(rate, 0.5, 2.0) : 1.0);
    winrt::Windows::Media::SystemMediaTransportControlsTimelineProperties timeline;
    const auto duration = MediaTime(Number(map, "durationMs"));
    timeline.StartTime(TimeSpan{0});
    timeline.EndTime(duration);
    timeline.MinSeekTime(TimeSpan{0});
    timeline.MaxSeekTime(duration);
    timeline.Position(std::min(MediaTime(Number(map, "positionMs")), duration));
    controls.UpdateTimelineProperties(timeline);

    const auto next_id = Text(map, "id");
    const auto next_title = Text(map, "title");
    const auto next_artist = Text(map, "artist");
    auto next_cover = Text(map, "coverPath");
    std::replace(next_cover.begin(), next_cover.end(), '/', '\\');
    const bool cover_changed = next_id != track_id || next_cover != cover_path;
    const bool text_changed = next_id != track_id || next_title != title || next_artist != artist;
    const auto updater = controls.DisplayUpdater();
    if (text_changed) {
      updater.Type(MediaPlaybackType::Music);
      updater.MusicProperties().Title(winrt::to_hstring(next_title));
      updater.MusicProperties().Artist(winrt::to_hstring(next_artist));
    }
    track_id = next_id;
    title = next_title;
    artist = next_artist;
    if (cover_changed) {
      cover_path = next_cover;
      const auto generation = ++cover_generation;
      updater.Thumbnail(nullptr);
      if (!cover_path.empty()) {
        const std::weak_ptr<DispatchState> weak = dispatch;
        // 不在平台线程等待文件读取；完成后仍须通过代次校验，旧封面不能覆盖新曲。
        try {
          StorageFile::GetFileFromPathAsync(winrt::to_hstring(cover_path)).Completed(
              [weak, generation](const auto& operation, AsyncStatus status) {
                if (status != AsyncStatus::Completed || weak.expired()) return;
                try {
                  Pending event;
                  event.cover_generation = generation;
                  event.thumbnail = RandomAccessStreamReference::CreateFromFile(operation.GetResults());
                  Queue(weak, std::move(event));
                } catch (...) {
                  OutputDebugStringW(L"啵啵音乐：系统媒体封面读取失败\n");
                }
              });
        } catch (...) {
          OutputDebugStringW(L"啵啵音乐：系统媒体封面路径不可用\n");
        }
      }
    }
    if (cover_changed || text_changed) updater.Update();
  }

  void Stop() {
    ++cover_generation;
    track_id.clear();
    title.clear();
    artist.clear();
    cover_path.clear();
    {
      std::lock_guard<std::mutex> lock(dispatch->mutex);
      dispatch->pending.clear();
    }
    if (!controls) return;
    controls.PlaybackStatus(MediaPlaybackStatus::Stopped);
    controls.IsEnabled(false);
    controls.DisplayUpdater().ClearAll();
    controls.DisplayUpdater().Update();
  }

  void Reset() noexcept {
    buttons.revoke();
    seek.revoke();
    speed.revoke();
    try { Stop(); } catch (...) {}
    controls = nullptr;
  }

  void DispatchPending() {
    std::deque<Pending> events;
    {
      std::lock_guard<std::mutex> lock(dispatch->mutex);
      events.swap(dispatch->pending);
    }
    for (auto& event : events) {
      if (!event.method.empty()) {
        channel->InvokeMethod(event.method, std::make_unique<EncodableValue>(event.argument));
      } else if (controls && event.thumbnail && event.cover_generation == cover_generation) {
        try {
          controls.DisplayUpdater().Thumbnail(event.thumbnail);
          controls.DisplayUpdater().Update();
        } catch (...) {
          OutputDebugStringW(L"啵啵音乐：系统媒体封面更新失败\n");
        }
      }
    }
  }
};

SystemMediaCenter::SystemMediaCenter(HWND window, flutter::BinaryMessenger* messenger)
    : impl_(std::make_unique<Impl>(window, messenger)) {}
SystemMediaCenter::~SystemMediaCenter() = default;
void SystemMediaCenter::DispatchPending() { impl_->DispatchPending(); }
