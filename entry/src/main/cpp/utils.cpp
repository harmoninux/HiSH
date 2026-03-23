//
// VNC Utils Implementation for HiSH
//

#include "include/utils.hpp"

std::tuple<napi_value, uint8_t *> createNewBuffer(napi_env env, size_t num) {
    napi_value buffer;
    uint8_t *arrayPtr = NULL;
    if (napi_ok != napi_create_arraybuffer(env, num * sizeof(uint8_t), (void **)&arrayPtr, &buffer)) {
        napi_throw_error(env, "-10", "napi_create_arraybuffer error.");
        return std::make_tuple(nullptr, nullptr);
    }

    napi_value array;
    if (napi_ok != napi_create_typedarray(env, napi_uint8_array, num, buffer, 0, &array)) {
        napi_throw_error(env, "-10", "napi_create_typedarray error.");
        return std::make_tuple(nullptr, nullptr);
    };

    memset(arrayPtr, 0, num);

    return std::make_tuple(array, arrayPtr);
}

napi_value parseRfbUpdateInfo(napi_env env, struct RfbUpdateInfo &info) {
    napi_value jsInfo;
    uint8_t *infoPtr = NULL;
    constexpr size_t num = sizeof(info);
    auto ret = createNewBuffer(env, num);

    jsInfo = std::get<0>(ret);
    infoPtr = std::get<1>(ret);

    memcpy(infoPtr, &info, sizeof(info));

    return jsInfo;
}
