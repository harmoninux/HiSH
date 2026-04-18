//
// VNC Client Implementation for HiSH
// Wraps libvncclient with RGB565 format and thread-safe callbacks
//

#include "include/vnc_client.hpp"
#include "hilog/log.h"
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <cstring>
#include <cstdlib>
#include <atomic>
#include <cstdarg>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3301
#define LOG_TAG "VNCClient"

// Redirect libvncserver logs to HiLog
static void hishVncLog(const char* format, ...) {
    char buf[512];
    va_list args;
    va_start(args, format);
    vsnprintf(buf, sizeof(buf), format, args);
    va_end(args);
    int len = strlen(buf);
    while (len > 0 && (buf[len-1] == '\n' || buf[len-1] == '\r'))
        buf[--len] = '\0';
    OH_LOG_INFO(LOG_APP, "libvnc: %{public}s", buf);
}

static void hishVncErr(const char* format, ...) {
    char buf[512];
    va_list args;
    va_start(args, format);
    vsnprintf(buf, sizeof(buf), format, args);
    va_end(args);
    int len = strlen(buf);
    while (len > 0 && (buf[len-1] == '\n' || buf[len-1] == '\r'))
        buf[--len] = '\0';
    OH_LOG_ERROR(LOG_APP, "libvnc: %{public}s", buf);
}

// Static member initialization
rfbClient* VncClient::client_ = nullptr;
std::atomic<bool> VncClient::connected_(false);
char VncClient::password_[256] = {};

uint8_t* VncClient::frameBuffer_ = nullptr;
int VncClient::fbWidth_ = 0;
int VncClient::fbHeight_ = 0;
std::mutex VncClient::fbMutex_;

VncResizeCallback VncClient::resizeCallback_ = nullptr;
VncFrameCallback VncClient::frameCallback_ = nullptr;
std::mutex VncClient::socketMutex_;

rfbBool VncClient::onResize(rfbClient* cl) {
    size_t size = static_cast<size_t>(cl->height) * cl->width * cl->format.bitsPerPixel / 8;
    OH_LOG_INFO(LOG_APP, "Resize: %{public}dx%{public}d bpp=%{public}d",
                cl->width, cl->height, cl->format.bitsPerPixel);

    {
        std::lock_guard<std::mutex> lock(fbMutex_);
        delete[] frameBuffer_;
        frameBuffer_ = new uint8_t[size];
        memset(frameBuffer_, 0, size);
        cl->frameBuffer = frameBuffer_;

        fbWidth_ = cl->width;
        fbHeight_ = cl->height;
    }

    if (resizeCallback_) {
        resizeCallback_(cl->width, cl->height);
    }

    return TRUE;
}

void VncClient::onUpdate(rfbClient* cl, int x, int y, int w, int h) {
    if (frameCallback_) {
        VncFrameInfo info = {
            .fbWidth = cl->width,
            .fbHeight = cl->height,
            .x = x,
            .y = y,
            .w = w,
            .h = h
        };
        frameCallback_(info);
    }
}

// libvncclient calls GetPassword and frees the returned pointer with free()
char* VncClient::getPassword(rfbClient* cl) {
    char* passwd = static_cast<char*>(malloc(256));
    if (passwd) {
        strncpy(passwd, VncClient::password_, 255);
        passwd[255] = '\0';
    }
    return passwd;
}

bool VncClient::checkConnection() {
    if (!client_ || client_->sock < 0) {
        return false;
    }

    struct sockaddr_in peer_addr;
    socklen_t addr_len = sizeof(peer_addr);
    return getpeername(client_->sock, reinterpret_cast<struct sockaddr*>(&peer_addr), &addr_len) == 0;
}

bool VncClient::connect(const char* address, int port, const char* passwd) {
    // Clean up any existing connection (also clears callbacks)
    disconnect();

    OH_LOG_INFO(LOG_APP, "Connect to %{public}s:%{public}d", address, port);

    // Redirect libvncserver logging to HiLog
    rfbClientLog = hishVncLog;
    rfbClientErr = hishVncErr;

    strncpy(password_, passwd, 255);
    password_[255] = '\0';

    client_ = rfbGetClient(8, 3, 2);  // 8 bits/sample, 3 samples, 2 bytes/pixel (RGB565)
    if (!client_) {
        OH_LOG_ERROR(LOG_APP, "Failed to create VNC client");
        return false;
    }

    client_->serverHost = strdup(address);
    client_->serverPort = port;

    // Configure RGB565 format
    client_->canHandleNewFBSize = TRUE;
    client_->MallocFrameBuffer = VncClient::onResize;
    client_->format.depth = 16;
    client_->format.bitsPerPixel = 16;
    client_->format.redShift = 11;
    client_->format.greenShift = 5;
    client_->format.blueShift = 0;
    client_->format.redMax = 0x1f;
    client_->format.greenMax = 0x3f;
    client_->format.blueMax = 0x1f;

    // Compression
    client_->appData.compressLevel = 5;
    client_->appData.qualityLevel = 1;
#ifdef LIBVNCSERVER_HAVE_LIBZ
    client_->appData.encodingsString = "zrle ultra hextile zlib copyrect raw";
#else
    client_->appData.encodingsString = "ultra hextile copyrect raw";
#endif
    // useRemoteCursor=FALSE: QEMU cursor pseudo-encodings may cause stream desync.
    // Standard vncviewer defaults to FALSE.
    client_->appData.useRemoteCursor = FALSE;
    client_->GetPassword = VncClient::getPassword;
    client_->GotFrameBufferUpdate = VncClient::onUpdate;
    client_->connectTimeout = 5;
    // readTimeout=0 (infinite): non-zero values cause spurious ReadFromRFBServer
    // timeouts during ZRLE/zlib decode of large frames, killing the poll thread.
    client_->readTimeout = 0;

    if (!rfbInitClient(client_, 0, nullptr)) {
        OH_LOG_ERROR(LOG_APP, "rfbInitClient failed");
        // rfbClientCleanup frees serverHost and other internal allocations
        rfbClientCleanup(client_);
        client_ = nullptr;
        return false;
    }

    connected_.store(true);
    OH_LOG_INFO(LOG_APP, "Connected: %{public}dx%{public}d sock=%{public}d encodings=[%{public}s]",
                client_->width, client_->height, client_->sock,
                client_->appData.encodingsString);
    return true;
}

void VncClient::disconnect() {
    // Clear callbacks first to prevent in-flight calls
    resizeCallback_ = nullptr;
    frameCallback_ = nullptr;

    if (client_) {
        connected_.store(false);

        if (client_->sock >= 0) {
            rfbCloseSocket(client_->sock);
        }
        rfbClientCleanup(client_);
        client_ = nullptr;
    }

    {
        std::lock_guard<std::mutex> lock(fbMutex_);
        delete[] frameBuffer_;
        frameBuffer_ = nullptr;
        fbWidth_ = 0;
        fbHeight_ = 0;
    }
}

bool VncClient::isConnected() {
    return connected_.load() && checkConnection();
}

void VncClient::sendMouseEvent(int x, int y, int buttonMask) {
    std::lock_guard<std::mutex> lock(socketMutex_);
    if (checkConnection()) {
        SendPointerEvent(client_, x, y, buttonMask);
    }
}

void VncClient::sendKeyEvent(uint32_t key, bool down) {
    std::lock_guard<std::mutex> lock(socketMutex_);
    if (checkConnection()) {
        SendKeyEvent(client_, key, down ? TRUE : FALSE);
    }
}

void VncClient::setResizeCallback(VncResizeCallback cb) {
    resizeCallback_ = cb;
}

void VncClient::setFrameCallback(VncFrameCallback cb) {
    frameCallback_ = cb;
}

uint8_t* VncClient::getFrameBuffer() {
    return frameBuffer_;
}

int VncClient::getFrameWidth() {
    return fbWidth_;
}

int VncClient::getFrameHeight() {
    return fbHeight_;
}

rfbClient* VncClient::getClient() {
    return client_;
}
