// Native messaging host for the Passwords browser extension (browser_extension/).
//
// Chrome/Edge start this program for that extension only (see the host manifest the app writes,
// whose allowed_origins lists the extension's fixed ID) and exchange length-prefixed JSON over
// stdin/stdout. It relays those messages unchanged to the running OpenBubbles app over a loopback
// socket, after introducing itself with the per-launch token the app writes to
// %LOCALAPPDATA%\OpenBubbles\browser-bridge.txt (readable only by this Windows user).

#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <thread>

namespace {

constexpr char kExtensionOrigin[] = "chrome-extension://odfmlmhmmoamgcgboaclpookgfjnehin/";

HANDLE g_stdout = INVALID_HANDLE_VALUE;

bool WriteAll(HANDLE handle, const char* data, DWORD size) {
  while (size > 0) {
    DWORD written = 0;
    if (!WriteFile(handle, data, size, &written, nullptr) || written == 0) return false;
    data += written;
    size -= written;
  }
  return true;
}

bool SendAll(SOCKET socket, const char* data, int size) {
  while (size > 0) {
    int sent = send(socket, data, size, 0);
    if (sent <= 0) return false;
    data += sent;
    size -= sent;
  }
  return true;
}

std::string Frame(const std::string& json) {
  uint32_t length = static_cast<uint32_t>(json.size());
  std::string out(reinterpret_cast<const char*>(&length), sizeof(length));  // little-endian on x64
  out += json;
  return out;
}

// Tells the extension why nothing works (e.g. the app isn't open), then exits.
[[noreturn]] void FailWith(const char* error) {
  std::string frame = Frame(std::string("{\"type\":\"error\",\"error\":\"") + error + "\"}");
  WriteAll(g_stdout, frame.data(), static_cast<DWORD>(frame.size()));
  ExitProcess(0);
}

bool IsHex(const std::string& s) {
  if (s.empty()) return false;
  for (char c : s) {
    if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return false;
  }
  return true;
}

bool ReadBridgeFile(int* port, std::string* token) {
  const char* local = std::getenv("LOCALAPPDATA");
  if (!local) return false;
  std::ifstream file(std::string(local) + "\\OpenBubbles\\browser-bridge.txt");
  if (!file) return false;
  std::string port_line;
  if (!std::getline(file, port_line) || !std::getline(file, *token)) return false;
  if (!token->empty() && token->back() == '\r') token->pop_back();
  if (!port_line.empty() && port_line.back() == '\r') port_line.pop_back();
  *port = std::atoi(port_line.c_str());
  return *port > 0 && *port < 65536 && IsHex(*token);
}

}  // namespace

int main(int argc, char** argv) {
  g_stdout = GetStdHandle(STD_OUTPUT_HANDLE);
  HANDLE std_in = GetStdHandle(STD_INPUT_HANDLE);

  // Chrome and Edge pass the calling extension's origin as the first argument.
  if (argc < 2 || std::strcmp(argv[1], kExtensionOrigin) != 0) return 1;

  int port = 0;
  std::string token;
  if (!ReadBridgeFile(&port, &token)) FailWith("not_running");

  WSADATA wsa;
  if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) FailWith("not_running");
  SOCKET app = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (app == INVALID_SOCKET) FailWith("not_running");
  sockaddr_in address = {};
  address.sin_family = AF_INET;
  address.sin_port = htons(static_cast<u_short>(port));
  address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  if (connect(app, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0) FailWith("not_running");

  std::string hello = Frame("{\"type\":\"hello\",\"token\":\"" + token + "\",\"origin\":\"" + kExtensionOrigin + "\"}");
  if (!SendAll(app, hello.data(), static_cast<int>(hello.size()))) FailWith("not_running");

  // browser -> app
  std::thread upstream([std_in, app]() {
    char buffer[16384];
    for (;;) {
      DWORD read = 0;
      if (!ReadFile(std_in, buffer, sizeof(buffer), &read, nullptr) || read == 0) break;
      if (!SendAll(app, buffer, static_cast<int>(read))) break;
    }
    // the browser closed the connection
    ExitProcess(0);
  });
  upstream.detach();

  // app -> browser
  char buffer[16384];
  for (;;) {
    int received = recv(app, buffer, sizeof(buffer), 0);
    if (received <= 0) break;
    if (!WriteAll(g_stdout, buffer, static_cast<DWORD>(received))) break;
  }
  ExitProcess(0);
}
