#include "hello_prompt.h"

#include <UserConsentVerifierInterop.h>
#include <roapi.h>
#include <windows.foundation.h>
#include <windows.security.credentials.ui.h>
#include <wrl/client.h>
#include <wrl/event.h>
#include <wrl/wrappers/corewrappers.h>

namespace {

using ABI::Windows::Foundation::AsyncStatus;
using ABI::Windows::Foundation::IAsyncOperation;
using ABI::Windows::Foundation::IAsyncOperationCompletedHandler;
using ABI::Windows::Security::Credentials::UI::UserConsentVerificationResult;
using ABI::Windows::Security::Credentials::UI::UserConsentVerificationResult_Verified;
using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::FtmBase;
using Microsoft::WRL::Implements;
using Microsoft::WRL::RuntimeClassFlags;
using Microsoft::WRL::ClassicCom;
using Microsoft::WRL::Wrappers::HStringReference;

constexpr wchar_t kOwnerClass[] = L"OpenBubblesHelloOwner";

void RegisterOwnerClass() {
  static bool registered = false;
  if (registered) return;
  WNDCLASSW window_class = {};
  window_class.lpfnWndProc = DefWindowProcW;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kOwnerClass;
  RegisterClassW(&window_class);
  registered = true;
}

// Brings |window| to the front. Windows only allows that when this app may take the foreground
// (the browser's helper allows it before asking for a passkey); attaching to the foreground
// window's input covers the rest.
void BringToFront(HWND window) {
  if (SetForegroundWindow(window)) return;
  HWND foreground = GetForegroundWindow();
  DWORD foreground_thread = foreground ? GetWindowThreadProcessId(foreground, nullptr) : 0;
  DWORD this_thread = GetCurrentThreadId();
  if (foreground_thread && foreground_thread != this_thread &&
      AttachThreadInput(this_thread, foreground_thread, TRUE)) {
    BringWindowToTop(window);
    SetForegroundWindow(window);
    AttachThreadInput(this_thread, foreground_thread, FALSE);
  }
}

// A tiny invisible, topmost window in the middle of the screen the user is on (the one with the
// browser), without a taskbar button.
HWND CreateOwner() {
  RegisterOwnerClass();
  HWND foreground = GetForegroundWindow();
  HMONITOR monitor = foreground ? MonitorFromWindow(foreground, MONITOR_DEFAULTTONEAREST)
                                : MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO info = {sizeof(info)};
  GetMonitorInfo(monitor, &info);
  int x = (info.rcWork.left + info.rcWork.right) / 2;
  int y = (info.rcWork.top + info.rcWork.bottom) / 2;
  HWND owner = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_LAYERED, kOwnerClass,
                               L"OpenBubbles", WS_POPUP, x, y, 1, 1, nullptr, nullptr,
                               GetModuleHandle(nullptr), nullptr);
  if (!owner) return nullptr;
  SetLayeredWindowAttributes(owner, 0, 0, LWA_ALPHA);
  ShowWindow(owner, SW_SHOW);
  BringToFront(owner);
  return owner;
}

}  // namespace

bool StartHelloPrompt(HWND notify_window, UINT notify_message, const std::wstring& reason) {
  ComPtr<IUserConsentVerifierInterop> interop;
  HRESULT hr = RoGetActivationFactory(
      HStringReference(RuntimeClass_Windows_Security_Credentials_UI_UserConsentVerifier).Get(),
      IID_PPV_ARGS(&interop));
  if (FAILED(hr)) return false;

  HWND owner = CreateOwner();
  if (!owner) return false;

  ComPtr<IAsyncOperation<UserConsentVerificationResult>> operation;
  hr = interop->RequestVerificationForWindowAsync(
      owner, HStringReference(reason.c_str()).Get(),
      __uuidof(IAsyncOperation<UserConsentVerificationResult>),
      reinterpret_cast<void**>(operation.GetAddressOf()));
  if (FAILED(hr)) {
    DestroyWindow(owner);
    return false;
  }

  auto handler = Callback<Implements<RuntimeClassFlags<ClassicCom>,
                                     IAsyncOperationCompletedHandler<UserConsentVerificationResult>,
                                     FtmBase>>(
      [notify_window, notify_message, owner](IAsyncOperation<UserConsentVerificationResult>* done,
                                             AsyncStatus status) -> HRESULT {
        UserConsentVerificationResult result = {};
        bool verified = status == AsyncStatus::Completed && SUCCEEDED(done->GetResults(&result)) &&
                        result == UserConsentVerificationResult_Verified;
        PostMessage(notify_window, notify_message, verified ? 1 : 0,
                    reinterpret_cast<LPARAM>(owner));
        return S_OK;
      });
  hr = operation->put_Completed(handler.Get());
  if (FAILED(hr)) {
    DestroyWindow(owner);
    return false;
  }
  return true;
}

void FinishHelloPrompt(HWND owner) {
  if (owner && IsWindow(owner)) DestroyWindow(owner);
}
