//
// VNC NAPI Bindings for HiSH
//
// Architecture:
//   - Poll thread: VNC protocol only (WaitForMessage + HandleRFBServerMessage)
//   - On frame update: markDirty() + TSFN notify(status=2)
//     → tsfnCallJs calls VncRenderer::renderDirtyFrame() directly (no JS→NAPI round-trip)
//   - On resize: VncRenderer::resize() + TSFN notify(status=1) → JS callback for UI update
//   - On disconnect: TSFN notify(status=-1) → JS callback for UI update
//
// Thread safety:
//   - libvncclient socket I/O is NOT thread-safe: poll cycle protected by socketMutex_
//   - sendMouseEvent/sendKeyEvent use separate sendMutex_ to avoid blocking poll thread
//   - sendMutex_ and socketMutex_ are never held simultaneously by the same thread
//

#include "napi/native_api.h"
#include <cassert>
#include <cstdint>
#include <cstring>
#include <thread>
#include <atomic>
#include <mutex>

#include "hilog/log.h"
#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3300
#define LOG_TAG "HiSH_VNC"

#include "include/vnc_client.hpp"
#include "include/vnc_renderer.hpp"
#include "include/utils.hpp"

// ---- Poll Thread State ----
static std::atomic<bool> g_pollRunning(false);
static std::thread g_pollThread;
static std::mutex g_pollMutex;  // protects thread creation/joining

// ---- TSFN for JS notifications ----
// status: 2 = frame update (rendered directly in tsfnCallJs), 1 = resize, -1 = disconnected
static napi_threadsafe_function g_tsfn = nullptr;

// Pre-allocated notify data pool to avoid per-frame heap allocation
static constexpr int NOTIFY_POOL_SIZE = 4;
struct VncNotifyData {
    int status;         // 2=frame, 1=resize, -1=disconnected
    int fbWidth;
    int fbHeight;
    bool inUse;
};
static VncNotifyData g_notifyPool[NOTIFY_POOL_SIZE];
static std::mutex g_poolMutex;

static VncNotifyData* allocNotifyData() {
    std::lock_guard<std::mutex> lock(g_poolMutex);
    for (int i = 0; i < NOTIFY_POOL_SIZE; i++) {
        if (!g_notifyPool[i].inUse) {
            g_notifyPool[i].inUse = true;
            return &g_notifyPool[i];
        }
    }
    // Pool exhausted — fall back to heap
    auto* nd = new VncNotifyData();
    nd->inUse = true;  // marks as heap-allocated (never returned to pool)
    return nd;
}

static void freeNotifyData(VncNotifyData* nd) {
    if (nd >= g_notifyPool && nd < g_notifyPool + NOTIFY_POOL_SIZE) {
        nd->inUse = false;  // Return to pool
    } else {
        delete nd;  // Heap-allocated fallback
    }
}

// Diagnostics: frame counter (declared in vnc_renderer.cpp)
extern std::atomic<int> g_tsfnCallCount;

static void tsfnCallJs(napi_env env, napi_value js_cb, void* context, void* data) {
    if (!env || !js_cb || !data) return;

    VncNotifyData* nd = static_cast<VncNotifyData*>(data);
    g_tsfnCallCount.fetch_add(1, std::memory_order_relaxed);

    if (nd->status == 2) {
        // Frame update: render directly on the JS thread (skip JS→NAPI round-trip)
        VncRenderer::renderDirtyFrame();
        // No need to call JS callback for frame updates —
        // dimension changes are handled by resize callback (status=1)
        freeNotifyData(nd);
        return;
    }

    // Resize / disconnect: forward to JS callback for UI state update
    napi_value jsObj;
    napi_create_object(env, &jsObj);

    napi_value v;
    napi_create_int32(env, nd->status, &v);
    napi_set_named_property(env, jsObj, "status", v);
    napi_create_int32(env, nd->fbWidth, &v);
    napi_set_named_property(env, jsObj, "fbWidth", v);
    napi_create_int32(env, nd->fbHeight, &v);
    napi_set_named_property(env, jsObj, "fbHeight", v);

    napi_value undefined;
    napi_get_undefined(env, &undefined);
    napi_call_function(env, undefined, js_cb, 1, &jsObj, nullptr);

    freeNotifyData(nd);
}

// ---- VNC Poll Thread ----
static void vncPollThread() {
    OH_LOG_INFO(LOG_APP, "VNC poll thread started");

    // Send initial full framebuffer request inside poll thread (thread safety)
    {
        std::lock_guard<std::mutex> lock(VncClient::getSocketMutex());
        rfbClient* cl = VncClient::getClient();
        if (cl) {
            OH_LOG_INFO(LOG_APP, "Requesting initial FB update: %{public}dx%{public}d", cl->width, cl->height);
            SendFramebufferUpdateRequest(cl, 0, 0, cl->width, cl->height, FALSE);
        }
    }

    while (g_pollRunning.load()) {
        rfbClient* cl = VncClient::getClient();
        if (!cl) {
            OH_LOG_WARN(LOG_APP, "Poll: client lost, exiting");
            break;
        }

        // Lock socket for the Wait+Handle cycle only
        {
            std::lock_guard<std::mutex> lock(VncClient::getSocketMutex());
            int i = WaitForMessage(cl, 50);
            if (!g_pollRunning.load()) break;

            if (i < 0) {
                OH_LOG_ERROR(LOG_APP, "Poll: WaitForMessage error");
                if (g_tsfn) {
                    auto* nd = allocNotifyData();
                    nd->status = -1; nd->fbWidth = 0; nd->fbHeight = 0;
                    napi_call_threadsafe_function(g_tsfn, nd, napi_tsfn_nonblocking);
                }
                break;
            }

            if (i > 0) {
                if (!HandleRFBServerMessage(cl)) {
                    OH_LOG_ERROR(LOG_APP, "Poll: HandleRFBServerMessage failed");
                    if (g_tsfn) {
                        auto* nd = allocNotifyData();
                        nd->status = -1; nd->fbWidth = 0; nd->fbHeight = 0;
                        napi_call_threadsafe_function(g_tsfn, nd, napi_tsfn_nonblocking);
                    }
                    break;
                }
            }
        }

        // Request incremental update outside the main lock to reduce contention
        // with sendMouseEvent/sendKeyEvent
        {
            std::lock_guard<std::mutex> lock(VncClient::getSocketMutex());
            if (g_pollRunning.load() && cl) {
                SendIncrementalFramebufferUpdateRequest(cl);
            }
        }
    }

    OH_LOG_INFO(LOG_APP, "VNC poll thread stopped");
}

// ---- NAPI Functions ----

static napi_value vncInit(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_status status = napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (status != napi_ok || argc < 3) {
        napi_throw_error(env, "-10", "Expected (address, port, password)");
        return nullptr;
    }

    size_t addrLen = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &addrLen);
    std::string address(addrLen, '\0');
    napi_get_value_string_utf8(env, args[0], &address[0], addrLen + 1, &addrLen);

    int32_t port = 0;
    napi_get_value_int32(env, args[1], &port);

    size_t pwdLen = 0;
    napi_get_value_string_utf8(env, args[2], nullptr, 0, &pwdLen);
    std::string password(pwdLen, '\0');
    napi_get_value_string_utf8(env, args[2], &password[0], pwdLen + 1, &pwdLen);

    OH_LOG_INFO(LOG_APP, "vncInit: %{public}s:%{public}d", address.c_str(), port);

    // Connect first (connect() calls disconnect() which clears callbacks,
    // so callbacks MUST be set AFTER connect)
    bool ok = VncClient::connect(address.c_str(), port, password.c_str());

    // Set frame callback: mark dirty + notify JS (NO GL calls on poll thread)
    VncClient::setFrameCallback([](const VncFrameInfo& info) {
        VncRenderer::markDirty(info.x, info.y, info.w, info.h);
        if (g_tsfn) {
            auto* nd = allocNotifyData();
            nd->status = 2;
            nd->fbWidth = info.fbWidth;
            nd->fbHeight = info.fbHeight;
            napi_call_threadsafe_function(g_tsfn, nd, napi_tsfn_nonblocking);
        } else {
            OH_LOG_WARN(LOG_APP, "Frame callback but TSFN is null!");
        }
    });

    // Set resize callback
    VncClient::setResizeCallback([](int width, int height) {
        OH_LOG_INFO(LOG_APP, "VNC resize: %{public}dx%{public}d", width, height);
        VncRenderer::resize(-1, -1);
        if (g_tsfn) {
            auto* nd = allocNotifyData();
            nd->status = 1;
            nd->fbWidth = width;
            nd->fbHeight = height;
            napi_call_threadsafe_function(g_tsfn, nd, napi_tsfn_nonblocking);
        }
    });

    napi_value ret;
    napi_get_boolean(env, ok, &ret);
    return ret;
}

static napi_value vncClose(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "vncClose");

    // 1. Stop poll thread (must join before destroying client)
    {
        std::lock_guard<std::mutex> lock(g_pollMutex);
        g_pollRunning.store(false);
        if (g_pollThread.joinable()) {
            g_pollThread.join();
        }
    }

    // 2. Release TSFN
    if (g_tsfn != nullptr) {
        napi_release_threadsafe_function(g_tsfn, napi_tsfn_release);
        g_tsfn = nullptr;
    }

    // 3. Destroy VNC client
    VncClient::disconnect();

    // 4. Shutdown renderer
    VncRenderer::shutdown();

    napi_value ret;
    napi_create_int32(env, 0, &ret);
    return ret;
}

static napi_value vncMouseEvent(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_status status = napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (status != napi_ok || argc < 3) return nullptr;

    int32_t x = 0, y = 0, buttonMask = 0;
    napi_get_value_int32(env, args[0], &x);
    napi_get_value_int32(env, args[1], &y);
    napi_get_value_int32(env, args[2], &buttonMask);

    VncClient::sendMouseEvent(x, y, buttonMask);
    return nullptr;
}

static napi_value vncKeyEvent(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_status status = napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (status != napi_ok || argc < 2) return nullptr;

    uint32_t keyCode = 0;
    bool down = false;
    napi_get_value_uint32(env, args[0], &keyCode);
    napi_get_value_bool(env, args[1], &down);

    rfbKeySym keysym = ohKeyCode2RFBKeyCode(static_cast<Input_KeyCode>(keyCode), down ? TRUE : FALSE);
    VncClient::sendKeyEvent(keysym, down);
    return nullptr;
}

static napi_value vncStartUpdateLoop(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_status status = napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (status != napi_ok || argc < 1) {
        napi_throw_error(env, "-10", "Expected callback argument");
        return nullptr;
    }

    napi_valuetype val_type;
    napi_typeof(env, args[0], &val_type);
    if (val_type != napi_function) {
        napi_throw_error(env, "-12", "Expected function for callback");
        return nullptr;
    }

    std::lock_guard<std::mutex> lock(g_pollMutex);

    // Release previous TSFN if exists
    if (g_tsfn != nullptr) {
        napi_release_threadsafe_function(g_tsfn, napi_tsfn_release);
        g_tsfn = nullptr;
    }

    // Create TSFN for notifications
    napi_value tsfnName;
    napi_create_string_utf8(env, "vncNotify", NAPI_AUTO_LENGTH, &tsfnName);
    napi_create_threadsafe_function(env, args[0], nullptr, tsfnName, 0, 1,
                                    nullptr, nullptr, nullptr, tsfnCallJs, &g_tsfn);

    // Join any previous thread
    if (g_pollThread.joinable()) {
        g_pollRunning.store(false);
        g_pollThread.join();
    }

    g_pollRunning.store(true);
    g_pollThread = std::thread(vncPollThread);

    // Send initial VNC dimensions to JS if already connected
    rfbClient* cl = VncClient::getClient();
    if (cl && g_tsfn) {
        auto* nd = allocNotifyData();
        nd->status = 1;
        nd->fbWidth = cl->width;
        nd->fbHeight = cl->height;
        napi_call_threadsafe_function(g_tsfn, nd, napi_tsfn_nonblocking);
    }

    OH_LOG_INFO(LOG_APP, "vncStartUpdateLoop: thread started");

    napi_value ret;
    napi_get_boolean(env, true, &ret);
    return ret;
}

static napi_value vncStopUpdateLoop(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "vncStopUpdateLoop");

    std::lock_guard<std::mutex> lock(g_pollMutex);
    g_pollRunning.store(false);
    if (g_pollThread.joinable()) {
        g_pollThread.join();
    }

    if (g_tsfn != nullptr) {
        napi_release_threadsafe_function(g_tsfn, napi_tsfn_release);
        g_tsfn = nullptr;
    }

    return nullptr;
}

static napi_value vncCreateSurface(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_status status = napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (status != napi_ok || argc < 1) return nullptr;

    int64_t surfaceId = 0;
    napi_valuetype val_type;
    napi_typeof(env, args[0], &val_type);

    if (val_type == napi_bigint) {
        bool lossless = true;
        napi_get_value_bigint_int64(env, args[0], &surfaceId, &lossless);
    } else if (val_type == napi_number) {
        double d = 0;
        napi_get_value_double(env, args[0], &d);
        surfaceId = static_cast<int64_t>(d);
    } else {
        napi_throw_error(env, "-12", "Expected bigint or number for surfaceId");
        return nullptr;
    }

    bool result = VncRenderer::init(surfaceId);

    napi_value ret;
    napi_get_boolean(env, result, &ret);
    return ret;
}

static napi_value vncResizeSurface(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_status status = napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (status != napi_ok || argc < 3) return nullptr;

    // args[0] is surfaceId (kept for API compatibility but unused by VncRenderer::resize)
    int32_t width = 0, height = 0;
    napi_get_value_int32(env, args[1], &width);
    napi_get_value_int32(env, args[2], &height);

    VncRenderer::resize(width, height);

    napi_value ret;
    napi_create_int32(env, 0, &ret);
    return ret;
}

static napi_value vncDestroySurface(napi_env env, napi_callback_info info) {
    VncRenderer::shutdown();

    napi_value ret;
    napi_create_int32(env, 0, &ret);
    return ret;
}

// vncRenderFrame is kept for backward compatibility but frame rendering now
// happens directly in tsfnCallJs (status=2) without JS→NAPI round-trip.
// JS code no longer needs to call this for frame updates.
static napi_value vncRenderFrame(napi_env env, napi_callback_info info) {
    VncRenderer::renderDirtyFrame();
    return nullptr;
}

// ---- Register ----
void registerVncFunctions(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"vncInit", nullptr, vncInit, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"vncClose", nullptr, vncClose, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"vncMouseEvent", nullptr, vncMouseEvent, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"vncKeyEvent", nullptr, vncKeyEvent, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"vncStartUpdateLoop", nullptr, vncStartUpdateLoop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"vncStopUpdateLoop", nullptr, vncStopUpdateLoop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"vncCreateSurface", nullptr, vncCreateSurface, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"vncResizeSurface", nullptr, vncResizeSurface, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"vncDestroySurface", nullptr, vncDestroySurface, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"vncRenderFrame", nullptr, vncRenderFrame, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
