#ifndef RIME_ENGINE_BRIDGE_H
#define RIME_ENGINE_BRIDGE_H

// stdbool must precede rime_api.h so Swift imports the bool-flavored API.
#include <rime_api_stdbool.h>
#include <rime_api.h>

#ifdef __cplusplus
extern "C" {
#endif
void rime_ios_configure_modules(RimeTraits* traits);
#ifdef __cplusplus
}
#endif

#endif  // RIME_ENGINE_BRIDGE_H
