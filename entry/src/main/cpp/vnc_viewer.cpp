//
// VNC Viewer Implementation for HiSH
//

#include "include/vnc_viewer.hpp"
#include "rfb/rfb.h"
#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <cstring>

rfbClient *VncViewer::cl = nullptr;
VncViewer::onResizeCallback VncViewer::onResize = nullptr;
VncViewer::onUpdateCallback VncViewer::onUpdate = nullptr;
char VncViewer::passwd[] = {};

// Track the current frame buffer to ensure it stays valid during updates
uint8_t *VncViewer::currentFrameBuffer = nullptr;
size_t VncViewer::currentBufferSize = 0;

void VncViewer::update(rfbClient *cl, int x, int y, int w, int h) {
    struct RfbUpdateInfo info = {.width = cl->width, .height = cl->height, .x = x, .y = y, .w = w, .h = h};
    if (onUpdate) {
        onUpdate(info);
    }
}

bool VncViewer::checkConnection() {
    if (!cl || cl->sock < 0) {
        return false;
    }

    // Use getpeername() to check if socket is connected
    // Returns 0 if connected, error (ENOTCONN or others) if not
    struct sockaddr_in peer_addr;
    socklen_t addr_len = sizeof(peer_addr);
    int result = getpeername(cl->sock, (struct sockaddr *)&peer_addr, &addr_len);

    if (result == 0) {
        return true;
    } else {
        int err = errno;
        OH_LOG_WARN(LOG_APP, "VNC socket not connected: errno=%{public}d", err);
        return false;
    }
}

int VncViewer::waitForMessage(VncViewer::onResizeCallback onResize, VncViewer::onUpdateCallback onUpdate) {
    if (!checkConnection()) {
        return -1;
    }
    VncViewer::onResize = onResize;
    VncViewer::onUpdate = onUpdate;

    int i = WaitForMessage(cl, 500);
    if (i < 0) {
        rfbClientCleanup(cl);
    }
    if (i) {
        if (!HandleRFBServerMessage(cl)) {
            rfbClientCleanup(cl);
        }
    }
    VncViewer::onResize = nullptr;
    VncViewer::onUpdate = nullptr;
    return i;
}

char *VncViewer::getPasswd(rfbClient *cl) {
    char *passwd = (char *)malloc(RFB_BUF_SIZE);
    strcpy(passwd, VncViewer::passwd);
    return passwd;
}

void VncViewer::closeViewer() {
    if (cl) {
        if (cl->sock >= 0) {
            rfbCloseSocket(cl->sock);
        }
        rfbClientCleanup(cl);
        VncViewer::cl = nullptr;
    }
}

rfbBool VncViewer::resize(rfbClient *cl) {
    OH_LOG_INFO(LOG_APP, "VNC resize: width=%{public}d, height=%{public}d", cl->width, cl->height);
    size_t num = cl->height * cl->width * cl->format.bitsPerPixel / 8;

    if (onResize) {
        // Call the resize callback to get new buffer from JavaScript
        uint8_t *ptr = onResize(num);

        // Only update frameBuffer if we got a valid pointer
        if (ptr != nullptr) {
            cl->frameBuffer = ptr;
            // Track the current buffer
            VncViewer::currentFrameBuffer = ptr;
            VncViewer::currentBufferSize = num;
            OH_LOG_INFO(LOG_APP, "Frame buffer updated: ptr=%{public}p, size=%{public}zu", ptr, num);
            return TRUE;
        } else {
            OH_LOG_ERROR(LOG_APP, "Resize callback returned null pointer");
            return FALSE;
        }
    } else {
        OH_LOG_ERROR(LOG_APP, "No resize callback set");
        return FALSE;
    }
}

void VncViewer::setViewer(const char *address, int port, const char *passwd) {
    // Clean up any existing connection first
    if (cl) {
        OH_LOG_INFO(LOG_APP, "Cleaning up existing VNC connection before creating new one");
        if (cl->sock >= 0) {
            rfbCloseSocket(cl->sock);
        }
        rfbClientCleanup(cl);
        VncViewer::cl = nullptr;
    }

    VncViewer::cl = rfbGetClient(8, 3, 2);

    strncpy(VncViewer::passwd, passwd, RFB_BUF_SIZE - 1);
    VncViewer::passwd[RFB_BUF_SIZE - 1] = '\0';
    VncViewer::cl->serverHost = strdup(address);
    VncViewer::cl->serverPort = port;

    VncViewer::cl->canHandleNewFBSize = TRUE;
    VncViewer::cl->MallocFrameBuffer = VncViewer::resize;
    VncViewer::cl->format.depth = 16;
    VncViewer::cl->format.bitsPerPixel = 16;
    VncViewer::cl->format.redShift = 11;
    VncViewer::cl->format.greenShift = 5;
    VncViewer::cl->format.blueShift = 0;
    VncViewer::cl->format.redMax = 0x1f;
    VncViewer::cl->format.greenMax = 0x3f;
    VncViewer::cl->format.blueMax = 0x1f;
    VncViewer::cl->appData.compressLevel = 5;
    VncViewer::cl->appData.qualityLevel = 1;
    VncViewer::cl->appData.encodingsString = "tight ultra";
    VncViewer::cl->GotFrameBufferUpdate = VncViewer::update;
    VncViewer::cl->appData.useRemoteCursor = TRUE;
    VncViewer::cl->GetPassword = VncViewer::getPasswd;
    VncViewer::cl->connectTimeout = 1;
    VncViewer::cl->readTimeout = 1;
}

void VncViewer::initViewer(VncViewer::onResizeCallback onResize) {
    VncViewer::onResize = onResize;

    OH_LOG_INFO(LOG_APP, "Init VNC viewer...");
    if (!rfbInitClient(VncViewer::cl, 0, nullptr)) {
        throw std::runtime_error("Failed to init VNC client");
    }
    VncViewer::onResize = nullptr;
}
