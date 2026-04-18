//
// VNC OpenGL ES3 Renderer Header for HiSH
//
// Threading model:
//   - Poll thread: calls markDirty() only (no GL/EGL calls)
//   - Render thread: owns EGL context, runs renderLoop() with condition variable wakeup
//   - JS thread: calls init/shutdown/resize (no GL calls except during init)
//     resize() and markDirty() wake the render thread via condition variable
//

#ifndef HISH_VNC_RENDERER_H
#define HISH_VNC_RENDERER_H

#include <cstdint>
#include <mutex>
#include <atomic>
#include <thread>
#include <condition_variable>
#include <EGL/egl.h>
#include <GLES3/gl32.h>
#include <native_window/external_window.h>

class VncRenderer {
public:
    // Initialize EGL + GL with XComponent surface ID, then start render thread
    // Called from JS thread
    static bool init(int64_t surfaceId);

    // Stop render thread and release all resources
    // Called from JS thread
    static void shutdown();

    // Handle surface resize — wakes render thread for full re-upload
    // Safe from any thread
    static void resize(int width, int height);

    // Mark a region as dirty — wakes render thread
    // Thread-safe, no GL calls — called from poll thread
    static void markDirty(int x, int y, int w, int h);

    VncRenderer() = delete;

private:
    // EGL resources (only touched on render thread after init)
    static EGLDisplay eglDisplay_;
    static EGLSurface eglSurface_;
    static EGLContext eglContext_;
    static EGLConfig eglConfig_;
    static OHNativeWindow* nativeWindow_;

    // GL resources (only touched on render thread)
    static GLuint shaderProgram_;
    static GLuint vao_;
    static GLuint vbo_;
    static GLuint textureId_;

    // Shader uniform/attribute locations
    static GLint posLoc_;
    static GLint texCoordLoc_;
    static GLint texLoc_;

    // VNC framebuffer dimensions (set by updateTexture on realloc)
    static int vncWidth_;
    static int vncHeight_;

    // Surface dimensions (synced from eglQuerySurface on render thread)
    static int surfaceWidth_;
    static int surfaceHeight_;

    // Dirty region tracking (written by any thread via markDirty, read by render thread)
    static std::atomic<bool> dirty_;
    static int dirtyX_, dirtyY_, dirtyW_, dirtyH_;
    static std::mutex dirtyMutex_;

    // Render thread state
    static std::thread renderThread_;
    static std::atomic<bool> renderRunning_;
    static std::mutex renderWakeMutex_;
    static std::condition_variable renderWakeCv_;
    static std::atomic<bool> surfaceResized_;

    // Init state (set during init, checked by render thread)
    static std::atomic<bool> initialized_;

    // Internal methods
    static bool initEGL(int64_t surfaceId);
    static bool initGL();
    static bool createShaders();
    static void cleanupGL();
    static void updateTexture(int x, int y, int w, int h, bool forceFull = false);
    static void renderLoop();           // Render thread entry point
    static void renderFrameInternal();  // Single frame render (called on render thread)
};

#endif // HISH_VNC_RENDERER_H
