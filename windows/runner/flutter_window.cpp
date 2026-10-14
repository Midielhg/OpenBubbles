#include "flutter_window.h"

#include <optional>
#include <string>
#include <variant>

#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "hello_prompt.h"

namespace {
constexpr int kPasswordsHotkeyId = 0x0B0B;
// posted by the Windows Hello prompt when it closes (see hello_prompt.h)
constexpr UINT kHelloDoneMessage = WM_APP + 0x0B0B;

std::wstring Utf16FromUtf8(const std::string& text) {
  int length = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
  std::wstring wide(length > 0 ? length : 0, L'\0');
  if (length > 0) {
    MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), wide.data(), length);
  }
  return wide;
}
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  shortcuts_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "openbubbles/shortcuts",
      &flutter::StandardMethodCodec::GetInstance());
  // "verifyUser": Windows Hello for passkeys, shown centered and on top (see hello_prompt.h)
  shortcuts_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "verifyUser") {
          result->NotImplemented();
          return;
        }
        if (hello_result_) {
          result->Error("busy", "A Windows Hello prompt is already open");
          return;
        }
        std::string reason = "OpenBubbles";
        if (const auto* text = std::get_if<std::string>(call.arguments())) reason = *text;
        if (!StartHelloPrompt(GetHandle(), kHelloDoneMessage, Utf16FromUtf8(reason))) {
          result->Error("unavailable", "Windows Hello couldn't be shown");
          return;
        }
        hello_result_ = std::move(result);
      });
  // fails quietly if another app already uses the combination
  passwords_hotkey_ = RegisterHotKey(GetHandle(), kPasswordsHotkeyId,
                                     MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, 'P') != 0;

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (passwords_hotkey_) {
    UnregisterHotKey(GetHandle(), kPasswordsHotkeyId);
    passwords_hotkey_ = false;
  }
  if (hello_result_) {
    hello_result_->Success(flutter::EncodableValue(false));
    hello_result_ = nullptr;
  }
  shortcuts_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case kHelloDoneMessage:
      FinishHelloPrompt(reinterpret_cast<HWND>(lparam));
      if (hello_result_) {
        hello_result_->Success(flutter::EncodableValue(wparam == 1));
        hello_result_ = nullptr;
      }
      return 0;
    case WM_HOTKEY:
      if (wparam == kPasswordsHotkeyId && shortcuts_channel_) {
        shortcuts_channel_->InvokeMethod("openPasswords", nullptr);
        return 0;
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
