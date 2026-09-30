#ifndef RUNNER_SHELL_INTEGRATION_H_
#define RUNNER_SHELL_INTEGRATION_H_

#include <windows.h>
#include <functional>
#include <string>
#include <vector>

// Per-user Explorer verbs; COM receives the entire selection in one request.
namespace shell_integration {
using ActionHandler = std::function<void(const std::string&,
                                       const std::vector<std::string>&)>;
bool Available();
LSTATUS Install();
LSTATUS Uninstall();
HRESULT Register(ActionHandler handler);
void Unregister();
}  // namespace shell_integration
#endif
