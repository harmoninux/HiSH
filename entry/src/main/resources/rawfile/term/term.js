// Initialize xterm.js
var term = new Terminal({
    cursorBlink: true,
    allowProposedApi: true, // Needed for some addons
    allowTransparency: true, // User preference: Transparency supported
    fontFamily: 'monospace, "Droid Sans Mono", "Courier New", "Courier", monospace',
    fontSize: 14, // Default, will be overridden by native.getFontSize()
    theme: {
        background: 'rgba(0, 0, 0, 0)', // Transparent by default to show effects behind
        foreground: '#ffffff',
        cursor: '#ffffff'
    },
    screenReaderMode: false, // Disabled to fix touch scrolling issues (was conflicting with native selection)
    scrollback: 3000, // [Optimization] Limit scrollback to 3000 lines (Ring Buffer) to prevent memory overflow
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

function setupImeGuard() {
    if (!term.textarea) {
        return;
    }
    const textarea = term.textarea;
    textarea.setAttribute('autocomplete', 'off');
    textarea.setAttribute('autocorrect', 'off');
    textarea.setAttribute('spellcheck', 'false');
    textarea.setAttribute('autocapitalize', 'off');
}

// Detects which monospace fonts are actually available in the WebView.
// Uses Canvas measureText: compares "CandidateFont, monospace" against
// pure "monospace" baseline. If a font doesn't exist, the browser falls
// back to monospace and the widths match → it gets filtered out.
function detectAvailableMonospaceFonts() {
    var testNarrow = 'iiiiilllll';
    var testWide = 'WWWWWmmmmm';
    var baseFont = 'monospace';

    // Comprehensive list of monospace fonts commonly available across
    // HarmonyOS / Android / Linux systems
    var candidates = [
        'Droid Sans Mono',
        'Noto Sans Mono',
        'Roboto Mono',
        'Source Code Pro',
        'Cascadia Code',
        'Fira Code',
        'JetBrains Mono',
        'Courier New',
        'Courier',
        'Consolas',
        'Menlo',
        'DejaVu Sans Mono',
        'Liberation Mono',
        'Ubuntu Mono',
        'Monaco',
    ];

    var canvas = document.createElement('canvas');
    var ctx = canvas.getContext('2d');
    var testFontSize = '16px';

    function measure(fontStack, text) {
        ctx.font = testFontSize + ' ' + fontStack;
        return ctx.measureText(text).width;
    }

    // Baseline with pure monospace (the browser's default monospace font)
    var monoNarrow = measure(baseFont, testNarrow);
    var monoWide = measure(baseFont, testWide);

    return candidates.filter(function(font) {
        // Measure with candidate + monospace fallback.
        // If the candidate font does NOT exist, the browser falls back
        // to monospace → same metrics as baseline → detected as unavailable.
        // If it DOES exist → different metrics → detected as available.
        var fontStack = '"' + font + '", ' + baseFont;
        var narrow = measure(fontStack, testNarrow);
        var wide = measure(fontStack, testWide);

        // Font is distinct from default monospace (it actually exists and differs)
        var narrowDiff = Math.abs(narrow - monoNarrow);
        var wideDiff = Math.abs(wide - monoWide);
        var isDistinct = narrowDiff > 0.5 || wideDiff > 0.5;

        // Font is monospace: narrow and wide chars have equal width
        // (1px tolerance for sub-pixel rendering differences)
        var monoDiff = Math.abs(narrow - wide);
        var isMonospace = monoDiff <= 1;

        return isDistinct && isMonospace;
    });
}

// Maps user-friendly font family name to CSS font-family stack.
// 'Default' uses the system monospace fallback chain;
// named fonts include a monospace fallback for safety.
function mapFontFamily(family) {
    if (!family || family === 'Default') {
        return 'monospace, "Droid Sans Mono", "Courier New", "Courier", monospace';
    }
    return '"' + family + '", monospace';
}

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
    setupImeGuard();

    // Retry mechanism for native object injection
    let retryCount = 0;
    const maxRetries = 10;

    function initialize() {
        // Disable WebGL as per user request (Compatibility Mode)
        let shouldEnableWebGL = false;

        // Check if native is ready
        if (!window.native && retryCount < maxRetries) {
            console.log(`Waiting for native object... (${retryCount + 1}/${maxRetries})`);
            retryCount++;
            setTimeout(initialize, 200);
            return;
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

            // 2. Detect available monospace fonts
            //    Preload bundled fonts first to ensure they're detected
            try {
                // Bundled fonts — always available, loaded via fonts.css @font-face
                var bundledFonts = ['JetBrains Mono', 'Fira Code', 'Source Code Pro'];
                var preloadPromises = [];
                if (document.fonts && document.fonts.load) {
                    for (var b = 0; b < bundledFonts.length; b++) {
                        preloadPromises.push(
                            document.fonts.load('14px "' + bundledFonts[b] + '"')
                                .catch(function() { /* ignore individual load failures */ })
                        );
                    }
                }
                // Run detection after preload (with timeout fallback)
                var doDetection = function() {
                    var availableFonts = detectAvailableMonospaceFonts();
                    // Ensure bundled fonts are always present (their woff2 files are baked in)
                    for (var k = 0; k < bundledFonts.length; k++) {
                        if (availableFonts.indexOf(bundledFonts[k]) === -1) {
                            availableFonts.push(bundledFonts[k]);
                        }
                    }
                    console.log('Detected monospace fonts: ' + availableFonts.join(', '));
                    if (native.onAvailableFontsDetected) {
                        native.onAvailableFontsDetected(JSON.stringify(availableFonts));
                    }
                };
                if (preloadPromises.length > 0) {
                    // Wait up to 2s for fonts to load, then run detection
                    Promise.race([
                        Promise.all(preloadPromises),
                        new Promise(function(r) { setTimeout(r, 2000); })
                    ]).then(doDetection);
                } else {
                    doDetection();
                }
            } catch (e) {
                console.warn('Font detection failed', e);
            }

            // 3. Fit Terminal (now onResize listener is ready to capture this)
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

            // 4. Load WebGL
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

            // 5. Initialize and Start Shell
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
    }

    // Start initialization
    initialize();
};

function syncPrefs() {
    try {
        if (native.getFontSize) {
            const fs = native.getFontSize();
            if (fs) term.options.fontSize = fs;
        }
        if (native.getFontFamily) {
            const ff = native.getFontFamily();
            if (ff) exports.setFontFamily(ff);
        }
        if (native.getCursorBlink) {
            const blink = native.getCursorBlink();
            if (blink) term.options.cursorBlink = blink;
        }
        if (native.getCursorShape) {
            const shape = native.getCursorShape();
            if (shape) exports.setCursorShape(shape); // Use our adapter logic
        }
    } catch (e) {
        console.warn("Failed to sync prefs", e);
    }
}

function setupEventListeners() {
    // 1. Input from User (Keyboard/Mouse) -> Send to VM
    term.onData(data => {
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

// --- Implementation of exports matching term.js.bak ---

// exports.write(data) - Write data from VM to terminal
exports.write = (data, applicationMode) => {
    // legacy hterm code imply data is Binary String (UTF-8/Latin1 bytes)
    try {
        const uint8 = strToUint8Array(data);
        term.write(uint8);
        if (term.modes.applicationCursorKeysMode !== applicationMode) {
            native.setApplicationMode(term.modes.applicationCursorKeysMode)
        }
    } catch (e) {
        console.error("exports.write failed", e);
    }
};

exports.writeBase64 = (base64Data, applicationMode) => {
    try {
        let binaryString = atob(base64Data);

        // 兼容性修复：还原字面量转义序列 (Unescape)
        // 支持 \xHH, \uHHHH, 以及常见 C 风格转义符 (\n, \r, \t, \', \", \\)
        binaryString = binaryString.replace(/\\(x[0-9a-fA-F]{2}|u[0-9a-fA-F]{4}|.)/g, (match, param) => {
            if (param[0] === 'x' || param[0] === 'u') {
                return String.fromCharCode(parseInt(param.slice(1), 16));
            }
            switch (param) {
                case 'n': return '\n';
                case 'r': return '\r';
                case 't': return '\t';
                case 'b': return '\b';
                case 'f': return '\f';
                case 'v': return '\v';
                case '0': return '\0';
                default: return param; // For \' \" \\ and others, just return the char
            }
        });

        const uint8 = new Uint8Array(binaryString.length);
        for (let i = 0; i < binaryString.length; i++) {
            uint8[i] = binaryString.charCodeAt(i);
        }
        term.write(uint8);

        // Sync Application Cursor Mode using xterm.js state
        if (term.modes.applicationCursorKeysMode !== applicationMode) {
            if (native && native.setApplicationMode) {
                native.setApplicationMode(term.modes.applicationCursorKeysMode);
            }
        }
    } catch (e) {
        console.error("exports.writeBase64 failed", e);
    }
};

exports.paste = (data) => {
    if (native && native.sendInput) {
        // If data is already binary string (UTF-8 bytes as chars), just send it.
        native.sendInput(data);
    }
};

exports.copy = () => {
    // xmm.js selection API
    return term.getSelection();
};

exports.setFontSize = (size) => {
    term.options.fontSize = size;
    fitAddon.fit();
};

exports.setFontFamily = (family) => {
    var newFamily = mapFontFamily(family);
    term.options.fontFamily = newFamily;

    // Resize to current dimensions to force xterm.js to
    // re-layout with the new font metrics, then re-fit.
    if (term.cols > 0 && term.rows > 0) {
        term.resize(term.cols, term.rows);
    }
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

exports.setFocused = (focus) => {
    if (focus) {
        setupImeGuard();
        term.focus();
    } else {
        term.blur();
    }
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
