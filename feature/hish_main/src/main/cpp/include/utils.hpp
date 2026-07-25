//
// VNC Utils Header for HiSH
//

#ifndef HISH_UTILS_HPP_H
#define HISH_UTILS_HPP_H

#include "napi/native_api.h"
#include "tuple"
#include "multimodalinput/oh_key_code.h"
#include "rfb/rfbclient.h"

std::tuple<napi_value, uint8_t *> createNewBuffer(napi_env, size_t);
rfbKeySym ohKeyCode2RFBKeyCode(Input_KeyCode, rfbBool);

#endif // HISH_UTILS_HPP_H
