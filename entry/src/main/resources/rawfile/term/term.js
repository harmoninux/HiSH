
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

    // Try to load WebGL, fallback to Canvas if it fails
    try {
        webglAddon.onContextLoss(e => {
            webglAddon.dispose();
        });
        term.loadAddon(webglAddon);
        console.log("WebGL renderer loaded");
    } catch (e) {
        console.warn("WebGL renderer failed to load, falling back to canvas", e);
    }

    fitAddon.fit();

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
        fitAddon.fit();
    });
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
    // Legacy hack for screen flicker?
    // term.setHeight... 
    // We probably don't need it with xterm, but force a fit might be good.
    fitAddon.fit();
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
