//
// VNC OpenGL ES3 Renderer Header for HiSH
//
// Threading model:
//   - Poll thread: calls markDirty() only (no GL/EGL calls)
//   - JS thread: calls renderDirtyFrame() via vncRenderFrame NAPI function
//

#ifndef HISH_VNC_RENDERER_H
#define HISH_VNC_RENDERER_H

#include <cstdint>
#include <mutex>
#include <atomic>
#include <EGL/egl.h>
#include <GLES3/gl32.h>
#include <native_window/external_window.h>

class VncRenderer {
public:
    // Initialize EGL + GL with XComponent surface ID (JS thread only)
    static bool init(int64_t surfaceId);

    // Shutdown and release all resources (JS thread only)
    static void shutdown();

    // Handle surface resize (safe from any thread; marks full frame dirty)
    static void resize(int width, int height);

    // Mark a region as dirty (thread-safe, no GL calls — called from poll thread)
    static void markDirty(int x, int y, int w, int h);

    // Render the current framebuffer if dirty (JS thread only — contains GL calls)
    static void renderDirtyFrame();

    VncRenderer() = delete;

private:
    // EGL resources
    static EGLDisplay eglDisplay_;
    static EGLSurface eglSurface_;
    static EGLContext eglContext_;
    static EGLConfig eglConfig_;
    static OHNativeWindow* nativeWindow_;

    // GL resources
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

    // Surface dimensions
    static int surfaceWidth_;
    static int surfaceHeight_;

    // Dirty region tracking (written by poll thread, read by JS thread)
    static std::atomic<bool> dirty_;
    static int dirtyX_, dirtyY_, dirtyW_, dirtyH_;
    static std::mutex dirtyMutex_;

    // Render state
    static std::mutex renderMutex_;
    static std::atomic<bool> initialized_;

    // Internal methods (all called on JS thread)
    static bool initEGL(int64_t surfaceId);
    static bool initGL();
    static bool createShaders();
    static void cleanupGL();
    static void updateTexture(int x, int y, int w, int h);
};

#endif // HISH_VNC_RENDERER_H
