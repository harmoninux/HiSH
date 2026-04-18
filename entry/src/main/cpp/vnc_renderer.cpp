//
// VNC OpenGL ES3 Renderer Implementation for HiSH
// Renders RGB565 VNC framebuffer via XComponent + EGL + OpenGL ES
//
// Threading:
//   - Render thread owns the EGL context and performs all GL operations.
//     It sleeps on a condition variable and wakes when dirty or resized.
//   - Poll thread calls markDirty() which wakes the render thread.
//   - JS thread calls init/shutdown/resize — no GL calls except during init().
//

#include "include/vnc_renderer.hpp"
#include "include/vnc_client.hpp"
#include <native_window/external_window.h>
#include <cstring>
#include <vector>
#include <chrono>
#include "hilog/log.h"

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3303
#define LOG_TAG "VNCRender"

// Vertex shader: fullscreen quad in NDC (GLES 3.0)
static const char* VERTEX_SHADER_ES3 = R"(#version 300 es
layout(location = 0) in vec2 a_pos;
layout(location = 1) in vec2 a_texCoord;
out vec2 v_texCoord;
void main() {
    gl_Position = vec4(a_pos, 0.0, 1.0);
    v_texCoord = a_texCoord;
}
)";

// Fragment shader: sample RGB565 texture (GLES 3.0)
static const char* FRAGMENT_SHADER_ES3 = R"(#version 300 es
precision mediump float;
in vec2 v_texCoord;
out vec4 fragColor;
uniform sampler2D u_tex;
void main() {
    fragColor = texture(u_tex, v_texCoord);
}
)";

// Vertex shader (GLES 2.0 fallback)
static const char* VERTEX_SHADER_ES2 = R"(#version 100 es
attribute vec2 a_pos;
attribute vec2 a_texCoord;
varying vec2 v_texCoord;
void main() {
    gl_Position = vec4(a_pos, 0.0, 1.0);
    v_texCoord = a_texCoord;
}
)";

// Fragment shader (GLES 2.0 fallback)
static const char* FRAGMENT_SHADER_ES2 = R"(#version 100 es
precision mediump float;
varying vec2 v_texCoord;
uniform sampler2D u_tex;
void main() {
    gl_FragColor = texture2D(u_tex, v_texCoord);
}
)";

// Static member initialization
EGLDisplay VncRenderer::eglDisplay_ = EGL_NO_DISPLAY;
EGLSurface VncRenderer::eglSurface_ = nullptr;
EGLContext VncRenderer::eglContext_ = nullptr;
EGLConfig VncRenderer::eglConfig_ = nullptr;
OHNativeWindow* VncRenderer::nativeWindow_ = nullptr;

GLuint VncRenderer::shaderProgram_ = 0;
GLuint VncRenderer::vao_ = 0;
GLuint VncRenderer::vbo_ = 0;
GLuint VncRenderer::textureId_ = 0;

GLint VncRenderer::posLoc_ = -1;
GLint VncRenderer::texCoordLoc_ = -1;
GLint VncRenderer::texLoc_ = -1;

int VncRenderer::vncWidth_ = 0;
int VncRenderer::vncHeight_ = 0;
int VncRenderer::surfaceWidth_ = 0;
int VncRenderer::surfaceHeight_ = 0;

std::atomic<bool> VncRenderer::dirty_(false);
int VncRenderer::dirtyX_ = 0;
int VncRenderer::dirtyY_ = 0;
int VncRenderer::dirtyW_ = 0;
int VncRenderer::dirtyH_ = 0;
std::mutex VncRenderer::dirtyMutex_;

std::thread VncRenderer::renderThread_;
std::atomic<bool> VncRenderer::renderRunning_(false);
std::mutex VncRenderer::renderWakeMutex_;
std::condition_variable VncRenderer::renderWakeCv_;
std::atomic<bool> VncRenderer::surfaceResized_(false);
std::atomic<bool> VncRenderer::initialized_(false);

// Diagnostics: frame counter
std::atomic<int> g_renderFrameCount{0};
std::atomic<int> g_dirtyMarkCount{0};
std::atomic<int> g_tsfnCallCount{0};

// ---- Helper: compile a GL shader ----
static GLuint compileShader(GLenum type, const char* source) {
    GLuint shader = glCreateShader(type);
    if (shader == 0) {
        OH_LOG_ERROR(LOG_APP, "glCreateShader failed: %{public}d", glGetError());
        return 0;
    }

    glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader);

    GLint compiled = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
    if (!compiled) {
        GLint infoLen = 0;
        glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &infoLen);
        if (infoLen > 1) {
            char* infoLog = new char[infoLen];
            glGetShaderInfoLog(shader, infoLen, nullptr, infoLog);
            OH_LOG_ERROR(LOG_APP, "Shader compile error: %{public}s", infoLog);
            delete[] infoLog;
        }
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

// ---- Helper: calculate letterbox viewport ----
static void calcViewport(int surfaceW, int surfaceH, int vncW, int vncH,
                         int& outX, int& outY, int& outW, int& outH) {
    outX = 0;
    outY = 0;
    outW = surfaceW;
    outH = surfaceH;
    if (surfaceW > 0 && surfaceH > 0 && vncW > 0 && vncH > 0) {
        float surfaceAspect = static_cast<float>(surfaceW) / surfaceH;
        float vncAspect = static_cast<float>(vncW) / vncH;
        if (surfaceAspect > vncAspect) {
            outW = static_cast<int>(surfaceH * vncAspect);
            outX = (surfaceW - outW) / 2;
        } else {
            outH = static_cast<int>(surfaceW / vncAspect);
            outY = (surfaceH - outH) / 2;
        }
    }
}

bool VncRenderer::initEGL(int64_t surfaceId) {
    OH_LOG_INFO(LOG_APP, "initEGL: surfaceId=%{public}lld", static_cast<long long>(surfaceId));

    OHNativeWindow* nativeWindow = nullptr;
    int ret = OH_NativeWindow_CreateNativeWindowFromSurfaceId(surfaceId, &nativeWindow);
    if (ret != 0 || nativeWindow == nullptr) {
        OH_LOG_ERROR(LOG_APP, "Failed to create native window: ret=%{public}d", ret);
        return false;
    }

    eglDisplay_ = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (eglDisplay_ == EGL_NO_DISPLAY) {
        OH_LOG_ERROR(LOG_APP, "Failed to get EGL display");
        OH_NativeWindow_DestroyNativeWindow(nativeWindow);
        return false;
    }

    EGLint majorVersion = 0, minorVersion = 0;
    if (!eglInitialize(eglDisplay_, &majorVersion, &minorVersion)) {
        OH_LOG_ERROR(LOG_APP, "Failed to initialize EGL");
        OH_NativeWindow_DestroyNativeWindow(nativeWindow);
        return false;
    }
    OH_LOG_INFO(LOG_APP, "EGL %{public}d.%{public}d", majorVersion, minorVersion);

    const char* eglExts = eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS);
    OH_LOG_INFO(LOG_APP, "EGL extensions: %{public}s", eglExts ? eglExts : "(null)");

    const EGLint configAttribs[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT | EGL_OPENGL_ES3_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_NONE
    };

    EGLint numConfigs = 0;
    if (!eglChooseConfig(eglDisplay_, configAttribs, nullptr, 0, &numConfigs) || numConfigs < 1) {
        OH_LOG_ERROR(LOG_APP, "No EGL configs found: err=%{public}d", eglGetError());
        eglTerminate(eglDisplay_);
        eglDisplay_ = EGL_NO_DISPLAY;
        OH_NativeWindow_DestroyNativeWindow(nativeWindow);
        return false;
    }

    OH_LOG_INFO(LOG_APP, "Found %{public}d EGL configs, searching for compatible one", numConfigs);

    std::vector<EGLConfig> configs(numConfigs);
    if (!eglChooseConfig(eglDisplay_, configAttribs, configs.data(), numConfigs, &numConfigs)) {
        OH_LOG_ERROR(LOG_APP, "eglChooseConfig failed: err=%{public}d", eglGetError());
        eglTerminate(eglDisplay_);
        eglDisplay_ = EGL_NO_DISPLAY;
        OH_NativeWindow_DestroyNativeWindow(nativeWindow);
        return false;
    }

    eglConfig_ = nullptr;
    for (int i = 0; i < numConfigs; i++) {
        EGLint redSize = 0, greenSize = 0, blueSize = 0, alphaSize = 0, renderable = 0, depthSize = 0, stencilSize = 0;
        eglGetConfigAttrib(eglDisplay_, configs[i], EGL_RED_SIZE, &redSize);
        eglGetConfigAttrib(eglDisplay_, configs[i], EGL_GREEN_SIZE, &greenSize);
        eglGetConfigAttrib(eglDisplay_, configs[i], EGL_BLUE_SIZE, &blueSize);
        eglGetConfigAttrib(eglDisplay_, configs[i], EGL_ALPHA_SIZE, &alphaSize);
        eglGetConfigAttrib(eglDisplay_, configs[i], EGL_RENDERABLE_TYPE, &renderable);
        eglGetConfigAttrib(eglDisplay_, configs[i], EGL_DEPTH_SIZE, &depthSize);
        eglGetConfigAttrib(eglDisplay_, configs[i], EGL_STENCIL_SIZE, &stencilSize);

        OH_LOG_INFO(LOG_APP, "  Config[%{public}d]: R%{public}dG%{public}dB%{public}dA%{public}d D%{public}dS%{public}d renderable=0x%{public}x",
                    i, redSize, greenSize, blueSize, alphaSize, depthSize, stencilSize, renderable);

        if (depthSize > 0 || stencilSize > 0) continue;

        eglSurface_ = eglCreateWindowSurface(eglDisplay_, configs[i], (EGLNativeWindowType)nativeWindow, nullptr);
        if (eglSurface_ != nullptr) {
            eglConfig_ = configs[i];
            OH_LOG_INFO(LOG_APP, "Using config[%{public}d]", i);
            break;
        }
        EGLint surfErr = eglGetError();
        OH_LOG_WARN(LOG_APP, "  Config[%{public}d] surface failed: 0x%{public}x", i, surfErr);
    }

    if (eglConfig_ == nullptr) {
        OH_LOG_WARN(LOG_APP, "No config without depth/stencil worked, trying all configs");
        for (int i = 0; i < numConfigs; i++) {
            eglSurface_ = eglCreateWindowSurface(eglDisplay_, configs[i], (EGLNativeWindowType)nativeWindow, nullptr);
            if (eglSurface_ != nullptr) {
                eglConfig_ = configs[i];
                OH_LOG_INFO(LOG_APP, "Fallback: using config[%{public}d]", i);
                break;
            }
        }
    }

    if (eglConfig_ == nullptr || eglSurface_ == nullptr) {
        OH_LOG_ERROR(LOG_APP, "No EGL config works with native window (EGL_BAD_MATCH)");
        eglTerminate(eglDisplay_);
        eglDisplay_ = EGL_NO_DISPLAY;
        OH_NativeWindow_DestroyNativeWindow(nativeWindow);
        return false;
    }

    EGLint redSize = 0, greenSize = 0, blueSize = 0, alphaSize = 0, renderable = 0;
    eglGetConfigAttrib(eglDisplay_, eglConfig_, EGL_RED_SIZE, &redSize);
    eglGetConfigAttrib(eglDisplay_, eglConfig_, EGL_GREEN_SIZE, &greenSize);
    eglGetConfigAttrib(eglDisplay_, eglConfig_, EGL_BLUE_SIZE, &blueSize);
    eglGetConfigAttrib(eglDisplay_, eglConfig_, EGL_ALPHA_SIZE, &alphaSize);
    eglGetConfigAttrib(eglDisplay_, eglConfig_, EGL_RENDERABLE_TYPE, &renderable);
    OH_LOG_INFO(LOG_APP, "Chosen EGL config: R%{public}dG%{public}dB%{public}dA%{public}d renderable=0x%{public}x",
                redSize, greenSize, blueSize, alphaSize, renderable);

    // Try GLES 3.x first, fallback to GLES 2.0
    const EGLint contextAttribs3[] = {
        EGL_CONTEXT_CLIENT_VERSION, 3,
        EGL_NONE
    };
    eglContext_ = eglCreateContext(eglDisplay_, eglConfig_, EGL_NO_CONTEXT, contextAttribs3);
    if (eglContext_ == nullptr) {
        OH_LOG_WARN(LOG_APP, "GLES 3.x context failed (err=%{public}d), trying GLES 2.0", eglGetError());
        const EGLint contextAttribs2[] = {
            EGL_CONTEXT_CLIENT_VERSION, 2,
            EGL_NONE
        };
        eglContext_ = eglCreateContext(eglDisplay_, eglConfig_, EGL_NO_CONTEXT, contextAttribs2);
    }
    if (eglContext_ == nullptr) {
        OH_LOG_ERROR(LOG_APP, "Failed to create EGL context: err=%{public}d", eglGetError());
        eglDestroySurface(eglDisplay_, eglSurface_);
        eglSurface_ = nullptr;
        eglTerminate(eglDisplay_);
        eglDisplay_ = EGL_NO_DISPLAY;
        OH_NativeWindow_DestroyNativeWindow(nativeWindow);
        return false;
    }

    // Make context current for init (render thread not started yet)
    if (!eglMakeCurrent(eglDisplay_, eglSurface_, eglSurface_, eglContext_)) {
        OH_LOG_ERROR(LOG_APP, "Failed to make EGL context current: err=%{public}d", eglGetError());
        eglDestroyContext(eglDisplay_, eglContext_);
        eglContext_ = nullptr;
        eglDestroySurface(eglDisplay_, eglSurface_);
        eglSurface_ = nullptr;
        eglTerminate(eglDisplay_);
        eglDisplay_ = EGL_NO_DISPLAY;
        OH_NativeWindow_DestroyNativeWindow(nativeWindow);
        return false;
    }

    nativeWindow_ = nativeWindow;

    const char* glVersion = reinterpret_cast<const char*>(glGetString(GL_VERSION));
    const char* glRenderer = reinterpret_cast<const char*>(glGetString(GL_RENDERER));
    const char* glVendor = reinterpret_cast<const char*>(glGetString(GL_VENDOR));
    const char* glslVersion = reinterpret_cast<const char*>(glGetString(GL_SHADING_LANGUAGE_VERSION));
    OH_LOG_INFO(LOG_APP, "GL_VERSION: %{public}s", glVersion ? glVersion : "(null)");
    OH_LOG_INFO(LOG_APP, "GL_RENDERER: %{public}s", glRenderer ? glRenderer : "(null)");
    OH_LOG_INFO(LOG_APP, "GL_VENDOR: %{public}s", glVendor ? glVendor : "(null)");
    OH_LOG_INFO(LOG_APP, "GLSL_VERSION: %{public}s", glslVersion ? glslVersion : "(null)");

    EGLint eglWidth = 0, eglHeight = 0;
    eglQuerySurface(eglDisplay_, eglSurface_, EGL_WIDTH, &eglWidth);
    eglQuerySurface(eglDisplay_, eglSurface_, EGL_HEIGHT, &eglHeight);
    if (eglWidth > 0 && eglHeight > 0) {
        surfaceWidth_ = eglWidth;
        surfaceHeight_ = eglHeight;
    }

    OH_LOG_INFO(LOG_APP, "EGL initialized: surface %{public}dx%{public}d", surfaceWidth_, surfaceHeight_);
    return true;
}

bool VncRenderer::createShaders() {
    const char* glVersionStr = reinterpret_cast<const char*>(glGetString(GL_VERSION));
    bool isGLES3 = false;
    if (glVersionStr) {
        int major = 0;
        if (sscanf(glVersionStr, "OpenGL ES %d.", &major) == 1) {
            isGLES3 = (major >= 3);
        }
    }
    OH_LOG_INFO(LOG_APP, "GL version detected: %{public}s, using %{public}s shaders",
                glVersionStr ? glVersionStr : "(null)", isGLES3 ? "ES3" : "ES2");

    const char* vertSrc = isGLES3 ? VERTEX_SHADER_ES3 : VERTEX_SHADER_ES2;
    const char* fragSrc = isGLES3 ? FRAGMENT_SHADER_ES3 : FRAGMENT_SHADER_ES2;

    GLuint vertexShader = compileShader(GL_VERTEX_SHADER, vertSrc);
    if (vertexShader == 0) {
        OH_LOG_ERROR(LOG_APP, "Vertex shader compilation failed");
        return false;
    }

    GLuint fragmentShader = compileShader(GL_FRAGMENT_SHADER, fragSrc);
    if (fragmentShader == 0) {
        OH_LOG_ERROR(LOG_APP, "Fragment shader compilation failed");
        glDeleteShader(vertexShader);
        return false;
    }

    shaderProgram_ = glCreateProgram();
    if (shaderProgram_ == 0) {
        OH_LOG_ERROR(LOG_APP, "glCreateProgram failed: %{public}d", glGetError());
        glDeleteShader(vertexShader);
        glDeleteShader(fragmentShader);
        return false;
    }

    if (!isGLES3) {
        glBindAttribLocation(shaderProgram_, 0, "a_pos");
        glBindAttribLocation(shaderProgram_, 1, "a_texCoord");
    }

    glAttachShader(shaderProgram_, vertexShader);
    glAttachShader(shaderProgram_, fragmentShader);
    glLinkProgram(shaderProgram_);

    GLint linked = 0;
    glGetProgramiv(shaderProgram_, GL_LINK_STATUS, &linked);
    if (!linked) {
        GLint infoLen = 0;
        glGetProgramiv(shaderProgram_, GL_INFO_LOG_LENGTH, &infoLen);
        if (infoLen > 1) {
            char* infoLog = new char[infoLen];
            glGetProgramInfoLog(shaderProgram_, infoLen, nullptr, infoLog);
            OH_LOG_ERROR(LOG_APP, "Program link error: %{public}s", infoLog);
            delete[] infoLog;
        }
        glDeleteShader(vertexShader);
        glDeleteShader(fragmentShader);
        glDeleteProgram(shaderProgram_);
        shaderProgram_ = 0;
        return false;
    }

    glDeleteShader(vertexShader);
    glDeleteShader(fragmentShader);

    posLoc_ = glGetAttribLocation(shaderProgram_, "a_pos");
    texCoordLoc_ = glGetAttribLocation(shaderProgram_, "a_texCoord");
    texLoc_ = glGetUniformLocation(shaderProgram_, "u_tex");

    OH_LOG_INFO(LOG_APP, "Shader locations: pos=%{public}d texCoord=%{public}d tex=%{public}d",
                posLoc_, texCoordLoc_, texLoc_);

    if (posLoc_ < 0 || texCoordLoc_ < 0 || texLoc_ < 0) {
        OH_LOG_ERROR(LOG_APP, "Invalid shader attribute/uniform locations");
        return false;
    }

    return true;
}

bool VncRenderer::initGL() {
    const float vertices[] = {
        -1.0f,  1.0f,    0.0f, 0.0f,
         1.0f,  1.0f,    1.0f, 0.0f,
        -1.0f, -1.0f,    0.0f, 1.0f,
         1.0f, -1.0f,    1.0f, 1.0f,
    };

    glGenVertexArrays(1, &vao_);
    if (vao_ != 0) {
        glBindVertexArray(vao_);
    }

    glGenBuffers(1, &vbo_);
    glBindBuffer(GL_ARRAY_BUFFER, vbo_);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);

    glEnableVertexAttribArray(posLoc_);
    glVertexAttribPointer(posLoc_, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), nullptr);

    glEnableVertexAttribArray(texCoordLoc_);
    glVertexAttribPointer(texCoordLoc_, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float),
                          reinterpret_cast<void*>(2 * sizeof(float)));

    if (vao_ != 0) {
        glBindVertexArray(0);
    }
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glDisableVertexAttribArray(posLoc_);
    glDisableVertexAttribArray(texCoordLoc_);

    glGenTextures(1, &textureId_);
    if (textureId_ == 0) {
        OH_LOG_ERROR(LOG_APP, "glGenTextures failed: %{public}d", glGetError());
        return false;
    }
    glBindTexture(GL_TEXTURE_2D, textureId_);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 2);
    glBindTexture(GL_TEXTURE_2D, 0);

    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);

    OH_LOG_INFO(LOG_APP, "OpenGL initialized: VAO=%{public}u VBO=%{public}u TEX=%{public}u",
                vao_, vbo_, textureId_);
    return true;
}

void VncRenderer::markDirty(int x, int y, int w, int h) {
    {
        std::lock_guard<std::mutex> lock(dirtyMutex_);
        if (!dirty_.load()) {
            dirtyX_ = x;
            dirtyY_ = y;
            dirtyW_ = w;
            dirtyH_ = h;
        } else {
            int nx2 = x + w;
            int ny2 = y + h;
            int ox2 = dirtyX_ + dirtyW_;
            int oy2 = dirtyY_ + dirtyH_;
            dirtyX_ = std::min(dirtyX_, x);
            dirtyY_ = std::min(dirtyY_, y);
            dirtyW_ = std::max(ox2, nx2) - dirtyX_;
            dirtyH_ = std::max(oy2, ny2) - dirtyY_;
        }
    }
    dirty_.store(true, std::memory_order_release);
    int cnt = g_dirtyMarkCount.fetch_add(1, std::memory_order_relaxed);

    /* HiSH diagnostic: log markDirty calls */
    if (cnt < 10 || cnt % 100 == 0) {
        OH_LOG_INFO(LOG_APP, "markDirty #%{public}d: (%{public}d,%{public}d %{public}dx%{public}d)",
                    cnt, x, y, w, h);
    }

    // Wake render thread
    renderWakeCv_.notify_one();
}

// ---- Render thread main loop ----
void VncRenderer::renderLoop() {
    OH_LOG_INFO(LOG_APP, "Render thread started");

    // Make EGL context current on this thread
    if (!eglMakeCurrent(eglDisplay_, eglSurface_, eglSurface_, eglContext_)) {
        OH_LOG_ERROR(LOG_APP, "Render thread: eglMakeCurrent failed: 0x%{public}x", eglGetError());
        return;
    }

    while (renderRunning_.load(std::memory_order_acquire)) {
        // Wait for wakeup signal (dirty or resize)
        {
            std::unique_lock<std::mutex> lk(renderWakeMutex_);
            renderWakeCv_.wait_for(lk, std::chrono::milliseconds(100),
                [] { return dirty_.load(std::memory_order_acquire) ||
                             surfaceResized_.load(std::memory_order_acquire) ||
                             !renderRunning_.load(std::memory_order_acquire); });
        }

        if (!renderRunning_.load(std::memory_order_acquire)) break;

        /* HiSH diagnostic: log wake reasons periodically */
        {
            static std::atomic<int> wakeCount{0};
            int wc = wakeCount.fetch_add(1, std::memory_order_relaxed);
            if (wc < 10 || wc % 100 == 0) {
                OH_LOG_INFO(LOG_APP, "renderLoop wake #%{public}d: dirty=%{public}d resized=%{public}d "
                            "dirtyMarkTotal=%{public}d renderFrameTotal=%{public}d",
                            wc, dirty_.load() ? 1 : 0, surfaceResized_.load() ? 1 : 0,
                            g_dirtyMarkCount.load(std::memory_order_relaxed),
                            g_renderFrameCount.load(std::memory_order_relaxed));
            }
        }

        renderFrameInternal();
    }

    // Release context from this thread
    eglMakeCurrent(eglDisplay_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    OH_LOG_INFO(LOG_APP, "Render thread stopped");
}

// ---- Render a single frame (render thread only) ----
void VncRenderer::renderFrameInternal() {
    if (!dirty_.load(std::memory_order_acquire) && !surfaceResized_.load(std::memory_order_acquire)) return;

    // Grab and clear dirty region
    int x, y, w, h;
    {
        std::lock_guard<std::mutex> lock(dirtyMutex_);
        x = dirtyX_;
        y = dirtyY_;
        w = dirtyW_;
        h = dirtyH_;
        dirty_.store(false, std::memory_order_release);
    }

    // Verify surface is still valid and get actual dimensions
    EGLint surfWidth = 0, surfHeight = 0;
    eglQuerySurface(eglDisplay_, eglSurface_, EGL_WIDTH, &surfWidth);
    eglQuerySurface(eglDisplay_, eglSurface_, EGL_HEIGHT, &surfHeight);

    // Handle surface resize: detect dimension changes
    bool needFullUpload = surfaceResized_.load(std::memory_order_acquire);
    if (needFullUpload) {
        surfaceResized_.store(false, std::memory_order_release);
        OH_LOG_INFO(LOG_APP, "renderFrame: surface resize flagged, eglQuerySurface=%{public}dx%{public}d",
                    surfWidth, surfHeight);
    }

    // Always sync surface dimensions from EGL — the source of truth
    if (surfWidth > 0 && surfHeight > 0 && (surfWidth != surfaceWidth_ || surfHeight != surfaceHeight_)) {
        OH_LOG_INFO(LOG_APP, "renderFrame: surface dims changed %{public}dx%{public}d -> %{public}dx%{public}d",
                    surfaceWidth_, surfaceHeight_, surfWidth, surfHeight);
        surfaceWidth_ = surfWidth;
        surfaceHeight_ = surfHeight;
        needFullUpload = true;
    }

    if (surfWidth <= 0 || surfHeight <= 0) {
        dirty_.store(true, std::memory_order_release);
        return;
    }

    // Upload dirty region to texture
    updateTexture(x, y, w, h, needFullUpload);

    if (vncWidth_ <= 0 || vncHeight_ <= 0) return;

    // Draw with letterbox viewport
    int vpX, vpY, vpW, vpH;
    calcViewport(surfaceWidth_, surfaceHeight_, vncWidth_, vncHeight_, vpX, vpY, vpW, vpH);

    glViewport(0, 0, surfaceWidth_, surfaceHeight_);
    glClear(GL_COLOR_BUFFER_BIT);

    glViewport(vpX, vpY, vpW, vpH);

    glUseProgram(shaderProgram_);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, textureId_);
    glUniform1i(texLoc_, 0);

    if (vao_ != 0) {
        glBindVertexArray(vao_);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        glBindVertexArray(0);
    } else {
        glBindBuffer(GL_ARRAY_BUFFER, vbo_);
        glEnableVertexAttribArray(posLoc_);
        glVertexAttribPointer(posLoc_, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), nullptr);
        glEnableVertexAttribArray(texCoordLoc_);
        glVertexAttribPointer(texCoordLoc_, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float),
                              reinterpret_cast<void*>(2 * sizeof(float)));
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        glDisableVertexAttribArray(posLoc_);
        glDisableVertexAttribArray(texCoordLoc_);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
    }
    glBindTexture(GL_TEXTURE_2D, 0);

    GLenum glErr = glGetError();

    if (!eglSwapBuffers(eglDisplay_, eglSurface_)) {
        EGLint err = eglGetError();
        OH_LOG_ERROR(LOG_APP, "eglSwapBuffers failed: 0x%{public}x", err);
    }

    int frameNum = g_renderFrameCount.fetch_add(1, std::memory_order_relaxed);
    if (frameNum < 5 || frameNum % 60 == 0) {
        OH_LOG_INFO(LOG_APP, "renderFrame #%{public}d: dirty=(%{public}d,%{public}d,%{public}d,%{public}d) "
                    "vnc=%{public}dx%{public}d surface=%{public}dx%{public}d vp=(%{public}d,%{public}d,%{public}d,%{public}d) "
                    "glErr=0x%{public}x",
                    frameNum, x, y, w, h, vncWidth_, vncHeight_, surfaceWidth_, surfaceHeight_,
                    vpX, vpY, vpW, vpH, glErr);
    }
}

void VncRenderer::updateTexture(int x, int y, int w, int h, bool forceFull) {
    if (textureId_ == 0) return;

    uint8_t* fb = VncClient::getFrameBuffer();
    if (!fb) {
        OH_LOG_WARN(LOG_APP, "updateTexture: framebuffer is NULL");
        return;
    }

    int vw = VncClient::getFrameWidth();
    int vh = VncClient::getFrameHeight();
    if (vw <= 0 || vh <= 0) {
        OH_LOG_WARN(LOG_APP, "updateTexture: invalid dimensions vw=%{public}d vh=%{public}d", vw, vh);
        return;
    }

    // Diagnostic: check if framebuffer has non-zero content
    {
        bool hasContent = false;
        int checkBytes = std::min(vw * vh * 2, 256);
        for (int i = 0; i < checkBytes; i++) {
            if (fb[i] != 0) { hasContent = true; break; }
        }
        static std::atomic<int> uploadCount{0};
        int cnt = uploadCount.fetch_add(1, std::memory_order_relaxed);
        if (cnt < 5 || cnt % 60 == 0) {
            OH_LOG_INFO(LOG_APP, "updateTexture #%{public}d: forceFull=%{public}d rect=(%{public}d,%{public}d,%{public}d,%{public}d) "
                        "fbSize=%{public}dx%{public}d hasContent=%{public}d",
                        cnt, forceFull, x, y, w, h, vw, vh, hasContent);
        }
    }

    glBindTexture(GL_TEXTURE_2D, textureId_);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 2);

    if (forceFull || vw != vncWidth_ || vh != vncHeight_) {
        vncWidth_ = vw;
        vncHeight_ = vh;
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, vncWidth_, vncHeight_, 0,
                     GL_RGB, GL_UNSIGNED_SHORT_5_6_5, fb);
    } else if (vao_ != 0) {
        glPixelStorei(GL_UNPACK_ROW_LENGTH, vncWidth_);
        glPixelStorei(GL_UNPACK_SKIP_PIXELS, x);
        glPixelStorei(GL_UNPACK_SKIP_ROWS, y);
        glTexSubImage2D(GL_TEXTURE_2D, 0, x, y, w, h,
                        GL_RGB, GL_UNSIGNED_SHORT_5_6_5, fb);
        glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
        glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0);
        glPixelStorei(GL_UNPACK_SKIP_ROWS, 0);
    } else {
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, vncWidth_, vncHeight_,
                        GL_RGB, GL_UNSIGNED_SHORT_5_6_5, fb);
    }

    glBindTexture(GL_TEXTURE_2D, 0);
}

void VncRenderer::cleanupGL() {
    OH_LOG_INFO(LOG_APP, "Cleaning up GL resources");

    // Must make context current before deleting GL objects
    if (eglDisplay_ != EGL_NO_DISPLAY && eglSurface_ != nullptr && eglContext_ != nullptr) {
        eglMakeCurrent(eglDisplay_, eglSurface_, eglSurface_, eglContext_);
    }

    if (vao_ != 0) { glDeleteVertexArrays(1, &vao_); vao_ = 0; }
    if (vbo_ != 0) { glDeleteBuffers(1, &vbo_); vbo_ = 0; }
    if (shaderProgram_ != 0) { glDeleteProgram(shaderProgram_); shaderProgram_ = 0; }
    if (textureId_ != 0) { glDeleteTextures(1, &textureId_); textureId_ = 0; }

    vncWidth_ = 0;
    vncHeight_ = 0;
    surfaceWidth_ = 0;
    surfaceHeight_ = 0;

    if (eglDisplay_ != EGL_NO_DISPLAY) {
        eglMakeCurrent(eglDisplay_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    }

    if (eglSurface_ != nullptr && eglDisplay_ != EGL_NO_DISPLAY) {
        eglDestroySurface(eglDisplay_, eglSurface_);
        eglSurface_ = nullptr;
    }
    if (eglContext_ != nullptr && eglDisplay_ != EGL_NO_DISPLAY) {
        eglDestroyContext(eglDisplay_, eglContext_);
        eglContext_ = nullptr;
    }
    if (eglDisplay_ != EGL_NO_DISPLAY) {
        eglTerminate(eglDisplay_);
        eglDisplay_ = EGL_NO_DISPLAY;
    }

    if (nativeWindow_ != nullptr) {
        OH_NativeWindow_DestroyNativeWindow(nativeWindow_);
        nativeWindow_ = nullptr;
    }

    initialized_.store(false, std::memory_order_release);
    surfaceResized_.store(false, std::memory_order_release);
    OH_LOG_INFO(LOG_APP, "GL cleanup done");
}

bool VncRenderer::init(int64_t surfaceId) {
    OH_LOG_INFO(LOG_APP, "VncRenderer::init surfaceId=%{public}lld", static_cast<long long>(surfaceId));

    if (initialized_.load(std::memory_order_acquire)) {
        OH_LOG_WARN(LOG_APP, "Renderer already initialized, shutting down first");
        shutdown();
    }

    if (!initEGL(surfaceId)) {
        OH_LOG_ERROR(LOG_APP, "Failed to initialize EGL");
        return false;
    }
    if (!createShaders()) {
        OH_LOG_ERROR(LOG_APP, "Failed to create shaders");
        cleanupGL();
        return false;
    }
    if (!initGL()) {
        OH_LOG_ERROR(LOG_APP, "Failed to initialize GL");
        cleanupGL();
        return false;
    }

    // Upload existing VNC framebuffer if already available
    int vw = VncClient::getFrameWidth();
    int vh = VncClient::getFrameHeight();
    if (vw > 0 && vh > 0) {
        uint8_t* fb = VncClient::getFrameBuffer();
        if (fb) {
            vncWidth_ = vw;
            vncHeight_ = vh;
            glBindTexture(GL_TEXTURE_2D, textureId_);
            glPixelStorei(GL_UNPACK_ALIGNMENT, 2);
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, vncWidth_, vncHeight_, 0,
                         GL_RGB, GL_UNSIGNED_SHORT_5_6_5, fb);
            glBindTexture(GL_TEXTURE_2D, 0);
            OH_LOG_INFO(LOG_APP, "Uploaded initial framebuffer: %{public}dx%{public}d", vw, vh);
        }
    }

    // Render initial frame (blue test + first VNC frame)
    {
        glViewport(0, 0, surfaceWidth_, surfaceHeight_);
        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);

        if (vncWidth_ > 0 && vncHeight_ > 0) {
            int vpX, vpY, vpW, vpH;
            calcViewport(surfaceWidth_, surfaceHeight_, vncWidth_, vncHeight_, vpX, vpY, vpW, vpH);
            glViewport(vpX, vpY, vpW, vpH);
            glUseProgram(shaderProgram_);
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, textureId_);
            glUniform1i(texLoc_, 0);
            if (vao_ != 0) {
                glBindVertexArray(vao_);
                glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
                glBindVertexArray(0);
            } else {
                glBindBuffer(GL_ARRAY_BUFFER, vbo_);
                glEnableVertexAttribArray(posLoc_);
                glVertexAttribPointer(posLoc_, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), nullptr);
                glEnableVertexAttribArray(texCoordLoc_);
                glVertexAttribPointer(texCoordLoc_, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float),
                                      reinterpret_cast<void*>(2 * sizeof(float)));
                glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
                glDisableVertexAttribArray(posLoc_);
                glDisableVertexAttribArray(texCoordLoc_);
                glBindBuffer(GL_ARRAY_BUFFER, 0);
            }
            glBindTexture(GL_TEXTURE_2D, 0);
        }

        eglSwapBuffers(eglDisplay_, eglSurface_);
    }

    // Release context from JS thread — render thread will take ownership
    eglMakeCurrent(eglDisplay_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);

    initialized_.store(true, std::memory_order_release);

    // Start render thread
    renderRunning_.store(true, std::memory_order_release);
    renderThread_ = std::thread(renderLoop);

    OH_LOG_INFO(LOG_APP, "VNC renderer initialized: fb=%{public}dx%{public}d, surface=%{public}dx%{public}d",
                vncWidth_, vncHeight_, surfaceWidth_, surfaceHeight_);
    return true;
}

void VncRenderer::shutdown() {
    OH_LOG_INFO(LOG_APP, "VncRenderer::shutdown");

    // Stop render thread first
    renderRunning_.store(false, std::memory_order_release);
    renderWakeCv_.notify_one();
    if (renderThread_.joinable()) {
        renderThread_.join();
    }

    if (!initialized_.load(std::memory_order_acquire)) return;

    // Now safe to cleanup — no other thread touches GL
    // Re-make context current on this thread for cleanup
    if (eglDisplay_ != EGL_NO_DISPLAY && eglSurface_ != nullptr && eglContext_ != nullptr) {
        eglMakeCurrent(eglDisplay_, eglSurface_, eglSurface_, eglContext_);
    }
    cleanupGL();
}

void VncRenderer::resize(int width, int height) {
    if (!initialized_.load(std::memory_order_acquire)) return;

    surfaceResized_.store(true, std::memory_order_release);

    int vw = VncClient::getFrameWidth();
    int vh = VncClient::getFrameHeight();
    if (vw > 0 && vh > 0) {
        markDirty(0, 0, vw, vh);
    } else {
        dirty_.store(true, std::memory_order_release);
    }

    // Wake render thread
    renderWakeCv_.notify_one();

    OH_LOG_INFO(LOG_APP, "resize: %{public}dx%{public}d, marked surfaceResized, vnc=%{public}dx%{public}d",
                width, height, vw, vh);
}
