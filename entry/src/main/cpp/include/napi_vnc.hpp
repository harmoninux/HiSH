//
// VNC NAPI Bindings Header for HiSH
//

#ifndef HISH_NAPI_VNC_H
#define HISH_NAPI_VNC_H

#include "napi/native_api.h"

// Register VNC NAPI functions on the exports object
void registerVncFunctions(napi_env env, napi_value exports);

#endif // HISH_NAPI_VNC_H
