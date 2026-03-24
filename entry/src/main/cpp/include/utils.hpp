//
// VNC Utils Header for HiSH
//

#ifndef HISH_VNC_UTILS_HPP_H
#define HISH_VNC_UTILS_HPP_H

#include "vnc_viewer.hpp"
#include "napi/native_api.h"
#include "tuple"
#include "multimodalinput/oh_key_code.h"
#include "rfb/keysym.h"

napi_value parseRfbUpdateInfo(napi_env, struct RfbUpdateInfo &);
std::tuple<napi_value, uint8_t *> createNewBuffer(napi_env, size_t);
rfbKeySym ohKeyCode2RFBKeyCode(Input_KeyCode, rfbBool);

#endif // HISH_VNC_UTILS_HPP_H
