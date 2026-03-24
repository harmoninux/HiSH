//
// VNC Viewer Header for HiSH
//

#ifndef HISH_VNC_VIEWER_H
#define HISH_VNC_VIEWER_H

#include "rfb/rfbclient.h"
#include <cstddef>
#include <cstdint>
#include <functional>
#include <sys/stat.h>
#include "hilog/log.h"
#include <setjmp.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3301
#define LOG_TAG "VNC"

struct RfbUpdateInfo {
    int32_t width;
    int32_t height;
    int32_t x;
    int32_t y;
    int32_t w;
    int32_t h;
};

class VncViewer {
public:
    using onResizeCallback = std::function<uint8_t *(size_t)>;
    using onUpdateCallback = std::function<void(struct RfbUpdateInfo &)>;

    static void closeViewer();
    static int waitForMessage(onResizeCallback, onUpdateCallback);
    static void initViewer(onResizeCallback);
    static void setViewer(const char *, int, const char *);
    static void mouseEvent(int x, int y, int buttonMask) {
        if (checkConnection())
            SendPointerEvent(VncViewer::cl, x, y, buttonMask);
    }
    static void keyEvent(rfbKeySym key, rfbBool down) {
        if (checkConnection())
            SendKeyEvent(VncViewer::cl, key, down);
    }

    VncViewer() = delete;

private:
    static onResizeCallback onResize;
    static onUpdateCallback onUpdate;
    static void update(rfbClient *, int, int, int, int);
    static rfbClient *cl;
    static char *getPasswd(rfbClient *);
    static rfbBool resize(rfbClient *);
    static char passwd[RFB_BUF_SIZE];
    static bool checkConnection();
    // Track current frame buffer to ensure it stays valid
    static uint8_t *currentFrameBuffer;
    static size_t currentBufferSize;
};

#endif // HISH_VNC_VIEWER_H
