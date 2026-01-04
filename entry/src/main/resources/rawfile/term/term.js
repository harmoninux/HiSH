
// Initialize xterm.js
var term = new Terminal({
    cursorBlink: true,
    allowProposedApi: true, // Needed for some addons
    fontFamily: 'monospace, "Droid Sans Mono", "Courier New", "Courier", monospace',
    fontSize: 14, // Default, will be overridden by native.getFontSize()
    theme: {
        background: '#000000',
        foreground: '#cccccc',
        cursor: '#cccccc'
    }
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
    // Try to load WebGL only on non-mobile devices (to avoid mirroring issues)
    let shouldEnableWebGL = true;
    try {
        if (native && native.getDeviceType) {
            const deviceType = native.getDeviceType();
            // phone and tablet often have mirroring issues with WebGL in WebView
            if (deviceType === 'phone' || deviceType === 'tablet') {
                shouldEnableWebGL = false;
                console.log("Mobile device detected, disabling WebGL to avoid mirroring issues");
            }
        }
    } catch (e) {
        console.warn("Failed to detect device type", e);
    }

    if (shouldEnableWebGL) {
        try {
            webglAddon.onContextLoss(e => {
                webglAddon.dispose();
            });
            term.loadAddon(webglAddon);
            console.log("WebGL renderer loaded");

            // Experimental fix for mirroring on mobile
            if (deviceType === 'phone' || deviceType === 'tablet') {
                const termEl = document.getElementById('terminal');
                termEl.classList.add('webgl-mobile-fix');
                setupMirroredInputFix(termEl);
            }
        } catch (e) {
            console.warn("WebGL renderer failed to load, falling back to canvas", e);
        }
    }

    // Initial fit with a slight delay to ensure container is ready
    setTimeout(() => {
        fitAddon.fit();
    }, 100);

    // Sync preferences from native
    syncPrefs();

    // Event Listeners
    setupEventListeners();

    // Restore HiSH Startup Logo
    term.writeln(
        'HiSH is starting...\r\n\r\n' +
        '     |  | _)   __|  |  |\r\n' +
        '     __ |  | \\__ \\  __ |\r\n' +
        '    _| _| _| ____/ _| _|\r\n'
    );

    // Notify native that we are ready
    if (native && native.load) {
        native.load();
    }
};

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
        e.preventDefault();
    }, { passive: false });
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
    return term.getSelection();
};

exports.clearScrollback = () => {
    term.clear();
    // Legacy hack for screen flicker/black screen on real devices
    const oldHeight = document.getElementById('terminal').style.height;
    document.getElementById('terminal').style.height = '99%';
    setTimeout(() => {
        document.getElementById('terminal').style.height = oldHeight || '100%';
        fitAddon.fit();
    }, 50);
};

exports.getSize = () => {
    return [term.cols, term.rows];
};

exports.setFocused = (focus) => {
    if (focus) {
        term.focus();
    } else {
        term.blur();
    }
};

exports.getCharacterSize = () => {
    const cellWidth = term._core?._renderService?.dimensions?.css?.cell?.width || 9;
    const cellHeight = term._core?._renderService?.dimensions?.css?.cell?.height || 18;
    return [cellWidth, cellHeight];
};

exports.setFontSize = (size) => {
    term.options.fontSize = size;
    fitAddon.fit(); // Re-fit after size change
};

exports.setCursorShape = (shape) => {
    // shape string from Native ('BLOCK', 'UNDERLINE', 'BEAM')
    // xterm options: 'block', 'underline', 'bar'
    let style = 'block';
    if (shape === 'UNDERLINE') style = 'underline';
    else if (shape === 'BEAM') style = 'bar';
    else if (shape === 'BLOCK') style = 'block';
    // legacy hterm might use different strings? 
    // term.js.bak: term.getPrefs().set('cursor-shape', shape);
    // hterm shapes: BLOCK, BEAM, UNDERLINE.
    term.options.cursorStyle = style;
};

exports.setCursorBlink = (blink) => {
    term.options.cursorBlink = blink;
};

// Mock hterm.openUrl for compatibility if something calls it directly
window.hterm = {
    openUrl: (url) => {
        if (native && native.openLink) native.openLink(url);
    }
};

// Also listen to link clicks in xterm
term.options.linkHandler = {
    activate: (e, text, range) => {
        if (native && native.openLink) native.openLink(text);
    }
};
