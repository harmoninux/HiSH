//
// VNC Client Header for HiSH
// Wraps libvncclient with RGB565 pixel format and thread-safe socket access
//

#ifndef HISH_VNC_CLIENT_H
#define HISH_VNC_CLIENT_H

#include "rfb/rfbclient.h"
#include <cstdint>
#include <functional>
#include <mutex>
#include <atomic>
#include <cstring>

struct VncFrameInfo {
    int32_t fbWidth;
    int32_t fbHeight;
    int32_t x;
    int32_t y;
    int32_t w;
    int32_t h;
};

using VncResizeCallback = std::function<void(int width, int height)>;
using VncFrameCallback = std::function<void(const VncFrameInfo& info)>;

class VncClient {
public:
    static bool connect(const char* address, int port, const char* passwd);
    static void disconnect();
    static bool isConnected();

    static void sendMouseEvent(int x, int y, int buttonMask);
    static void sendKeyEvent(uint32_t key, bool down);

    static void setResizeCallback(VncResizeCallback cb);
    static void setFrameCallback(VncFrameCallback cb);

    static uint8_t* getFrameBuffer();
    static int getFrameWidth();
    static int getFrameHeight();
    static rfbClient* getClient();

    // Framebuffer mutex: protects frameBuffer_/fbWidth_/fbHeight_ across threads.
    // onResize (poll thread) writes, updateTexture (render thread) reads.
    static std::mutex& getFbMutex() { return fbMutex_; }

    // Socket mutex: libvncclient is NOT thread-safe, all socket I/O must be serialized
    static std::mutex& getSocketMutex() { return socketMutex_; }

    VncClient() = delete;

private:
    static rfbClient* client_;
    static std::atomic<bool> connected_;
    static char password_[256];

    static uint8_t* frameBuffer_;
    static int fbWidth_;
    static int fbHeight_;
    static std::mutex fbMutex_;

    static VncResizeCallback resizeCallback_;
    static VncFrameCallback frameCallback_;
    static std::mutex socketMutex_;

    // libvncclient callbacks
    static rfbBool onResize(rfbClient* cl);
    static void onUpdate(rfbClient* cl, int x, int y, int w, int h);
    static char* getPassword(rfbClient* cl);
    static bool checkConnection();
};

#endif // HISH_VNC_CLIENT_H
