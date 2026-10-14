#ifndef RUNNER_HELLO_PROMPT_H_
#define RUNNER_HELLO_PROMPT_H_

#include <windows.h>

#include <string>

// Windows Hello (PIN / face / fingerprint) for passkeys used from the browser extension.
//
// The prompt belongs to a window; when that is OpenBubbles' own window while it sits in the tray or
// behind the browser, Windows opens the prompt minimized in the taskbar. Like browsers do, this
// opens it over a small invisible window brought to the front in the middle of the screen the user
// is looking at, so the prompt appears centered and on top.
//
// When the prompt closes, |notify_message| is posted to |notify_window| with WPARAM = 1 when the
// user was verified (0 otherwise) and LPARAM = the owner window, to pass to FinishHelloPrompt.
// Returns false when the prompt couldn't be shown (nothing is posted then).
bool StartHelloPrompt(HWND notify_window, UINT notify_message, const std::wstring& reason);

// Closes the owner window of a finished prompt.
void FinishHelloPrompt(HWND owner);

#endif  // RUNNER_HELLO_PROMPT_H_
