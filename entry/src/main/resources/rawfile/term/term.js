
// Initialize xterm.js
var term = new Terminal({
    cursorBlink: true,
    allowProposedApi: true, // Needed for some addons
    allowTransparency: true, // User preference: Transparency supported
    fontFamily: 'monospace, "Droid Sans Mono", "Courier New", "Courier", monospace',
    fontSize: 14, // Default, will be overridden by native.getFontSize()
    theme: {
        background: 'rgba(0, 0, 0, 0)', // Transparent by default to show effects behind
        foreground: '#cccccc',
        cursor: '#cccccc'
    },
    screenReaderMode: false, // Disabled to fix touch scrolling issues (was conflicting with native selection)
});

// Initialize Addons
const fitAddon = new FitAddon.FitAddon();
const webglAddon = new WebglAddon.WebglAddon();

term.loadAddon(fitAddon);

// Initialize exports for ArkTS to call
window.exports = {};

// Helper for decoding Latin1/Binary string from ArkTS to UTF-8
const decoder = new TextDecoder('utf-8');
const encoder = new TextEncoder();

// Function to convert "binary string" (where charCode < 256) to Uint8Array
// ArkTS sends data as a string where each char is a byte.
function strToUint8Array(str) {
    const buf = new Uint8Array(str.length);
    for (let i = 0; i < str.length; i++) {
        buf[i] = str.charCodeAt(i);
    }
    return buf;
}

// Setup global term object for debugging if needed
window.term = term;

// Main initialization function
window.onload = function () {
    term.open(document.getElementById('terminal'));

    // Retry mechanism for native object injection
    let retryCount = 0;
    const maxRetries = 10;

    function initialize() {
        // Disable WebGL as per user request (Compatibility Mode)
        let shouldEnableWebGL = false;
        let deviceType = 'unknown';

        // Check if native is ready
        if (!window.native && retryCount < maxRetries) {
            console.log(`Waiting for native object... (${retryCount + 1}/${maxRetries})`);
            retryCount++;
            setTimeout(initialize, 200);
            return;
        }

        try {
            if (window.native && native.getDeviceType) {
                deviceType = native.getDeviceType();
                console.log("Device type detected: " + deviceType);
            }
        } catch (e) {
            console.warn("Failed to detect device type", e);
        }

        // Initial fit with a slight delay to ensure container is ready
        setTimeout(() => {
            // 1. Setup event listeners and sync preferences FIRST
            //    确保 term.onResize 在 fitAddon.fit() 之前设置好，
            //    这样首次 fit 的 resize 事件才能触发 native.resize() 发送给 VM 内核
            try {
                syncPrefs();
                setupEventListeners();
            } catch (e) {
                console.error("Error during setup", e);
            }

            // 2. Fit Terminal (now onResize listener is ready to capture this)
            try {
                fitAddon.fit();
                console.log(`Terminal size after fit: ${term.cols}x${term.rows}`);

                // If fit failed (size 0), force a default size
                if (term.cols < 2 || term.rows < 2) {
                    term.resize(80, 24);
                    console.log("Forced resize to 80x24");
                }
            } catch (e) {
                console.error("Fit failed", e);
                term.resize(80, 24); // Fallback
            }

            // 3. Load WebGL
            if (shouldEnableWebGL) {
                try {
                    webglAddon.onContextLoss(e => {
                        webglAddon.dispose();
                    });
                    term.loadAddon(webglAddon);
                    console.log("WebGL renderer loaded");
                } catch (e) {
                    console.warn("WebGL renderer failed to load, falling back to canvas", e);
                }
            }

            // 4. Initialize and Start Shell
            try {
                // Restore HiSH Startup Logo
                term.writeln(
                    'HiSH is starting...\r\n\r\n' +
                    '     |  | _)   __|  |  |\r\n' +
                    '     __ |  | \\__ \\  __ |\r\n' +
                    '    _| _| _| ____/ _| _|\r\n'
                );

                // Notify native that we are ready
                if (window.native && native.load) {
                    native.load();
                } else {
                    console.error("Native object still missing after retries");
                    term.writeln('\r\nError: Native bridge failed to initialize.\r\n');
                }
            } catch (e) {
                console.error("Error during init/load", e);
            }

        }, 300); // 300ms delay to ensure container is ready

        // Initialize Matrix Rain
        matrixRain = new MatrixRain('matrix');
        resetScreensaverTimer();
    }

    // Start initialization
    initialize();
};

// Matrix Rain Implementation
class Trail {
    constructor(column, fontSize, canvasHeight, chars) {
        this.column = column;
        this.fontSize = fontSize;
        this.canvasHeight = canvasHeight;
        this.chars = chars;
        this.rows = Math.ceil(canvasHeight / fontSize) + 2;
        this.body = [];
        this.isBinary = false;
        this.options = {
            size: Math.floor(Math.random() * 20) + 10, // 轨迹长度 r(10, 30)
            offset: Math.floor(Math.random() * this.rows) // 初始偏移
        };
        this.build();
    }

    build() {
        this.body = [];
        for (let i = 0; i < this.rows; i++) {
            this.body.push({
                char: this.getRandomChar(),
                mutate: Math.random() < 0.5
            });
        }
    }

    getRandomChar() {
        return this.chars.charAt(Math.floor(Math.random() * this.chars.length));
    }

    update() {
        // 模拟参考代码的 move 逻辑：offset 递增并取模
        this.options.offset = (this.options.offset + 1) % (this.rows + this.options.size);

        // 模拟参考代码的 mutate 逻辑
        // 01 序列模式下大幅提高切换率 (0.3)，随机字符模式保持自然 (0.02)
        const mutationRate = this.isBinary ? 0.3 : 0.02;

        this.body.forEach(c => {
            if (c.mutate && Math.random() < mutationRate) {
                c.char = this.getRandomChar();
            }
        });
    }

    draw(ctx) {
        const { offset, size } = this.options;
        const x = this.column * this.fontSize;

        for (let i = 0; i < size; i++) {
            const index = offset + i - size + 1;

            if (index >= 0 && index < this.rows) {
                const c = this.body[index];
                const charY = index * this.fontSize;
                const last = (i === size - 1);

                if (last) {
                    ctx.fillStyle = 'hsl(136, 100%, 85%)';
                    ctx.shadowBlur = 12;
                    ctx.shadowColor = '#fff';
                    c.char = this.getRandomChar();
                } else {
                    const brightness = (85 / size) * (i + 1);
                    ctx.fillStyle = `hsl(136, 100%, ${brightness}%)`;
                    ctx.shadowBlur = 0;
                    ctx.shadowColor = 'transparent';
                }

                ctx.fillText(c.char, x, charY);
            }
        }
    }
}

class MatrixRain {
    constructor(canvasId) {
        this.canvas = document.getElementById(canvasId);
        this.ctx = this.canvas.getContext('2d');
        this.trails = [];
        this.fontSize = 16;
        this.isBinary = false;
        this.isScreensaver = false;
        this.chars = this.getSampleCharSet();
        this.animationId = null;
        this.resize();
        window.addEventListener('resize', () => this.resize());
    }

    // 模拟参考代码的 getChar 逻辑生成字符集，并根据用户要求调整概率和加入乱码
    getSampleCharSet() {
        let chars = '';
        let prioritized = '';
        let junk = '';

        // 日文平假名与片假名
        for (let i = 0x3041; i <= 0x30ff; i++) chars += String.fromCharCode(i);

        // 优先字符：大小写英文字母 + 数字及数字行符号
        for (let i = 0x0041; i <= 0x005a; i++) prioritized += String.fromCharCode(i); // A-Z
        for (let i = 0x0061; i <= 0x007a; i++) prioritized += String.fromCharCode(i); // a-z
        prioritized += '0123456789!@#$%^&*()_+-=[]{}|;:\'",.<>?/\\';

        // 乱码字符：方块、特殊符号、数学符号等
        junk += '█▓▒░√×÷±≠≈∞∑∏π∫∆∇√∝∞∟∠∡∢∣∤∥∦∧∨∩∪∫∬∭∮∯∰∱∲∳';
        for (let i = 0x2500; i <= 0x257f; i++) junk += String.fromCharCode(i); // Box Drawing

        // 通用标点符号
        for (let i = 0x2000; i <= 0x206f; i++) chars += String.fromCharCode(i);

        // 组合字符集
        // prioritized 重复 6 次以保持约 66% 的高概率
        // junk 重复 2 次以占据约 28% 的比例
        return chars + prioritized.repeat(6) + junk.repeat(2);
    }

    setCharSet(type) {
        this.isBinary = (type === 'binary');
        if (this.isBinary) {
            this.chars = '01';
        } else {
            this.chars = this.getSampleCharSet();
        }
        this.trails.forEach(t => {
            t.chars = this.chars;
            t.isBinary = this.isBinary;
        });
    }

    resize() {
        this.canvas.width = window.innerWidth;
        this.canvas.height = window.innerHeight;
        const columns = Math.floor(this.canvas.width / this.fontSize);
        this.trails = [];
        for (let i = 0; i < columns; i++) {
            const trail = new Trail(i, this.fontSize, this.canvas.height, this.chars);
            trail.isBinary = this.isBinary;
            this.trails.push(trail);
        }
    }

    draw() {
        const now = Date.now();
        const delay = 50; // 约 20fps，匹配参考代码的节奏感

        if (!this.lastFrameTime || now - this.lastFrameTime >= delay) {
            // 屏保模式下填充黑色背景以遮挡终端，背景特效模式下保持透明
            if (this.isScreensaver) {
                this.ctx.fillStyle = '#000';
                this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
            } else {
                this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
            }

            this.ctx.font = `bold ${this.fontSize}px monospace`;
            this.ctx.textAlign = 'center';
            this.ctx.shadowBlur = 0;
            this.ctx.shadowColor = 'transparent';

            this.trails.forEach(trail => {
                trail.update();
                trail.draw(this.ctx);
            });
            this.lastFrameTime = now;
        }

        this.animationId = requestAnimationFrame(() => this.draw());
    }

    start() {
        if (!this.animationId) {
            this.canvas.style.display = 'block';
            this.draw();
        }
    }

    stop() {
        if (this.animationId) {
            cancelAnimationFrame(this.animationId);
            this.animationId = null;
            this.canvas.style.display = 'none';
        }
    }
}

let matrixRain = null;
let terminalEffectsEnabled = false;
let screensaverTimeoutValue = 0;
let screensaverTimer = null;
let currentTransparency = 1;
let currentEffectType = 'random';

exports.setTerminalEffectType = (type) => {
    currentEffectType = type;
    if (matrixRain) {
        matrixRain.setCharSet(type);
    }
};

function resetScreensaverTimer() {
    if (screensaverTimer) clearTimeout(screensaverTimer);

    // Logic:
    // 1. If Effects Enabled: Matrix runs in BACKGROUND (z-index 0).
    // 2. If Screensaver Activates: Matrix runs in FOREGROUND (z-index 2).

    const canvas = document.getElementById('matrix');

    // Default state: If effects enabled, run in background.
    if (terminalEffectsEnabled) {
        if (matrixRain) {
            const wasScreensaver = matrixRain.isScreensaver;
            matrixRain.stop();
            // Force refresh terminal to clear any screensaver remnants ONLY when exiting screensaver
            if (wasScreensaver) {
                term.refresh(0, term.rows - 1);
            }
            matrixRain.isScreensaver = false;
            matrixRain.start();
        }
        if (canvas) canvas.style.zIndex = '0'; // Background
    } else {
        // Effects disabled, stop rain until screensaver
        if (matrixRain) {
            const wasScreensaver = matrixRain.isScreensaver;
            matrixRain.stop();
            if (wasScreensaver) {
                term.refresh(0, term.rows - 1);
            }
            matrixRain.isScreensaver = false;
        }
    }

    // Screensaver Timer
    if (screensaverTimeoutValue > 0) {
        screensaverTimer = setTimeout(() => {
            if (matrixRain) {
                matrixRain.isScreensaver = true;
                matrixRain.start();
                // Bring to front when screensaver activates
                if (canvas) canvas.style.zIndex = '2'; // Foreground
            }
        }, screensaverTimeoutValue * 1000);
    }
}

function syncPrefs() {
    try {
        if (native.getFontSize) {
            const fs = native.getFontSize();
            if (fs) term.options.fontSize = fs;
        }
        if (native.getCursorBlink) {
            const blink = native.getCursorBlink();
            if (blink) term.options.cursorBlink = blink;
        }
        if (native.getCursorShape) {
            const shape = native.getCursorShape();
            if (shape) exports.setCursorShape(shape); // Use our adapter logic
        }
        if (native.getTerminalEffects) {
            const effects = native.getTerminalEffects();
            exports.setTerminalEffects(effects);
        }
        if (native.getTerminalTransparency) {
            const transparency = native.getTerminalTransparency();
            exports.setTerminalTransparency(transparency);
        }
        if (native.getTerminalScreensaver) {
            const screensaver = native.getTerminalScreensaver();
            exports.setTerminalScreensaver(screensaver);
        }
        if (native.getTerminalEffectType) {
            const effectType = native.getTerminalEffectType();
            exports.setTerminalEffectType(effectType);
        }
    } catch (e) {
        console.warn("Failed to sync prefs", e);
    }
}

function setupEventListeners() {
    // 1. Input from User (Keyboard/Mouse) -> Send to VM
    term.onData(data => {
        resetScreensaverTimer(); // Reset screensaver on input
        // Pass data directly to native (matching original hterm behavior)
        if (native && native.sendInput) {
            native.sendInput(data);
        }
    });

    // 2. Resize -> Notify Native
    term.onResize(size => {
        if (native && native.resize) {
            native.resize(size.cols, size.rows);
        }
    });

    // 3. Selection Change -> Notify Native
    term.onSelectionChange(() => {
        const text = term.getSelection();
        if (native && native.onSelectionChange) {
            native.onSelectionChange(text);
        }
    });

    // 4. Handle Window Resize
    window.addEventListener('resize', () => {
        setTimeout(() => fitAddon.fit(), 100);
    });

    // 5. Prevent default browser behaviors that might interfere
    document.addEventListener('keydown', (e) => {
        // Allow some system shortcuts if needed, but generally intercept
        if (e.ctrlKey || e.altKey || (e.keyCode >= 112 && e.keyCode <= 123)) {
            // Let xterm handle it or prevent default
        }
    }, { passive: false });

    // Prevent scrolling/bouncing on mobile
    document.addEventListener('touchmove', (e) => {
        if (e.touches.length > 1) return; // Allow pinch zoom if not handled by CSS
        // e.preventDefault(); // DISABLED: Allow native text selection gestures
    }, { passive: false });

    // --- EVENT SHIELD: Force Native Context Menu (Global Capture) ---
    // This listener runs in the CAPTURE phase on the DOCUMENT.
    // It intercepts the 'contextmenu' event BEFORE it reaches xterm.js.
    // We stop it from propagating to xterm, but allow the default browser behavior (menu).

    document.addEventListener('contextmenu', (e) => {
        // Only intercept if inside the terminal
        if (e.target.closest('#terminal')) {
            e.stopImmediatePropagation(); // Kill it before xterm sees it
            // e.preventDefault(); // DO NOT CALL THIS! We want the menu!
            return true;
        }
    }, true); // true = Capture Phase

    console.log("Global ContextMenu Interceptor activated");
}

// Fix for mouse/touch coordinates when the terminal is visually flipped
function setupMirroredInputFix(termEl) {
    const fixEvent = (e) => {
        if (!termEl.classList.contains('webgl-mobile-fix')) return;

        // If the event was already fixed, skip
        if (e._fixed) return;

        const rect = termEl.getBoundingClientRect();
        let clientY = e.clientY;
        if (e.touches && e.touches.length > 0) {
            clientY = e.touches[0].clientY;
        }

        // Calculate relative Y and flip it
        const relativeY = clientY - rect.top;
        const flippedY = rect.height - relativeY;
        const newClientY = rect.top + flippedY;

        // We can't easily modify clientY of a native event, 
        // but xterm.js uses offsetX/offsetY or calculates from clientX/Y.
        // This is a complex area. A simpler way is to use a proxy element or 
        // just warn the user that touch selection might be inverted.
        console.log("Input coordinates might need inversion due to WebGL fix");
    };

    // termEl.addEventListener('mousedown', fixEvent, true);
    // termEl.addEventListener('touchstart', fixEvent, true);
}

// Add global event listeners to reset screensaver on any user activity
['mousedown', 'mousemove', 'keydown', 'touchstart'].forEach(event => {
    document.addEventListener(event, () => {
        resetScreensaverTimer();
    }, { passive: true });
});

// --- Implementation of exports matching term.js.bak ---

// exports.write(data) - Write data from VM to terminal
exports.write = (data) => {
    // legacy hterm code imply data is Binary String (UTF-8/Latin1 bytes)
    try {
        const uint8 = strToUint8Array(data);
        term.write(uint8);
    } catch (e) {
        console.error("exports.write failed", e);
    }
};

exports.paste = (data) => {
    if (native && native.sendInput) {
        // If data is already binary string (UTF-8 bytes as chars), just send it.
        native.sendInput(data);
    }
};

exports.copy = () => {
    // xterm.js selection API
    const selection = term.getSelection();
    return JSON.stringify(selection);
};

exports.setFontSize = (size) => {
    term.options.fontSize = size;
    fitAddon.fit();
};

exports.setCursorShape = (shape) => {
    // hterm: BLOCK, BEAM, UNDERLINE
    // xterm: block, bar, underline
    switch (shape) {
        case 'BEAM': term.options.cursorStyle = 'bar'; break;
        case 'UNDERLINE': term.options.cursorStyle = 'underline'; break;
        default: term.options.cursorStyle = 'block'; break;
    }
};

exports.setCursorBlink = (blink) => {
    term.options.cursorBlink = blink;
};

exports.setTerminalEffects = (enabled) => {
    terminalEffectsEnabled = enabled;
    resetScreensaverTimer();
};

exports.setTerminalTransparency = (alpha) => {
    // alpha is 0-100
    currentTransparency = alpha / 100;
    term.options.theme = {
        ...term.options.theme,
        background: `rgba(0, 0, 0, ${currentTransparency})`
    };
};

exports.setTerminalScreensaver = (timeout) => {
    screensaverTimeoutValue = timeout;
    resetScreensaverTimer();
};

// Mock hterm.openUrl for compatibility if something calls it directly
window.hterm = {
    openUrl: (url) => {
        if (native && native.openLink) native.openLink(url);
    }
};

// Also listen to link clicks in xterm
term.options.linkHandler = {
    activate: (e, text) => {
        if (native && native.openLink) native.openLink(text);
    }
};

exports.selectAll = () => {
    term.selectAll();
};
