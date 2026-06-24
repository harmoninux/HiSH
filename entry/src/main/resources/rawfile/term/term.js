// Initialize xterm.js
var term = new Terminal({
    cursorBlink: true,
    allowProposedApi: true, // Needed for some addons
    allowTransparency: true, // User preference: Transparency supported
    fontFamily: '"CodeNewRomanNerdFontMono", monospace',
    fontSize: 14, // Default, overridden by native.getFontSize() in syncPrefs
    letterSpacing: 0,  // 等宽字体不需要调整间距
    theme: {
        background: 'rgba(0, 0, 0, 0)', // Transparent by default to show effects behind
        foreground: '#ffffff',
        cursor: '#ffffff'
    },
    screenReaderMode: false, // Disabled to fix touch scrolling issues (was conflicting with native selection)
    scrollback: 3000, // [Optimization] Limit scrollback to 3000 lines (Ring Buffer) to prevent memory overflow
    smoothScrollDuration: 0, // 禁用滚动动画，提升 TUI 响应
    termName: 'xterm-256color', // 告诉 VM 终端支持 256 色，修复 OpenCode 等 TUI 黑屏
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
        // Enable WebGL for better rendering on high DPI screens
        // 改为 false 提升复杂 TUI 工具兼容性（如 opencode/tmux 等）
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

            // 3. Skip WebGL, use Canvas renderer for better TUI compatibility
            console.log("Using Canvas renderer (WebGL disabled for TUI compatibility)");

            // 4. Initialize and Start Shell
            try {
                // Boot splash is already shown, update status
                exports.setBootStatus('Connecting to VM...');
                term.writeln(
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
        if (native.getCursorBlink) {
            const blink = native.getCursorBlink();
            if (blink) term.options.cursorBlink = blink;
        }
        if (native.getCursorShape) {
            const shape = native.getCursorShape();
            if (shape) exports.setCursorShape(shape); // Use our adapter logic
        }
        if (native.getTheme) {
            const theme = native.getTheme();
            if (theme) exports.setTheme(theme);
        }
        if (native.getFont) {
            const font = native.getFont();
            if (font) exports.setFont(font);
        }
    } catch (e) {
        console.warn("Failed to sync prefs", e);
    }
}

function setupEventListeners() {
    // fit 后抑制 onData（防 textarea/Ime 残留发往 VM），覆盖折叠屏完整动画周期
    var _suppressOnDataUntil = 0;
    var _suppressOnDataMs = 500;

    // 1. Input from User (Keyboard/Mouse) -> Send to VM
    term.onData(data => {
        if (Date.now() < _suppressOnDataUntil) return;
        if (native && native.sendInput) {
            native.sendInput(data);
        }
    });

    // 2. Resize -> Notify Native（走 QGA stty，不经过串口，无 echo）
    let lastCols = -1, lastRows = -1;
    term.onResize(size => {
        if (size.cols === lastCols && size.rows === lastRows) return;
        lastCols = size.cols;
        lastRows = size.rows;
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

    // 4. 屏幕尺寸变化时 fit 画布（xterm 文字自动适配），但不发 CSI 给 VM
    let fitTimer = null;
    function scheduleFit() {
        clearTimeout(fitTimer);
        fitTimer = setTimeout(function() {
            _suppressOnDataUntil = Date.now() + _suppressOnDataMs;
            fitAddon.fit();
            // 二次 fit 兜底折叠动画
            setTimeout(function() {
                _suppressOnDataUntil = Date.now() + _suppressOnDataMs;
                fitAddon.fit();
            }, 400);
        }, 100);
    }
    const terminalEl = document.getElementById('terminal');
    if (terminalEl && window.ResizeObserver) {
        new ResizeObserver(function() { scheduleFit(); }).observe(terminalEl);
    }
    window.addEventListener('resize', function() { scheduleFit(); });

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
let firstDataReceived = false;
exports.write = (data, applicationMode) => {
    if (!firstDataReceived) {
        exports.hideBootSplash();
        firstDataReceived = true;
    }
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
    if (!firstDataReceived) {
        exports.hideBootSplash();
        firstDataReceived = true;
    }
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

// 手动触发 fit（设置面板改字体后调用，初始化请勿调用此方法）
exports.fit = () => {
    if (fitAddon) fitAddon.fit();
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

// ============== Terminal Themes ==============
const THEMES = {
    'dark': {
        background: 'rgba(0, 0, 0, 0)',
        foreground: '#ffffff',
        cursor: '#ffffff',
        cursorAccent: '#000000',
        selectionBackground: '#ffffff44',
        black: '#1a1a2e', red: '#e06c75', green: '#98c379',
        yellow: '#e5c07b', blue: '#61afef', magenta: '#c678dd',
        cyan: '#56b6c2', white: '#abb2bf',
        brightBlack: '#5c6370', brightRed: '#e06c75', brightGreen: '#98c379',
        brightYellow: '#e5c07b', brightBlue: '#61afef', brightMagenta: '#c678dd',
        brightCyan: '#56b6c2', brightWhite: '#ffffff'
    },
    'dracula': {
        background: 'rgba(40, 42, 54, 0.92)',
        foreground: '#f8f8f2',
        cursor: '#f8f8f2',
        cursorAccent: '#282a36',
        selectionBackground: '#44475a',
        black: '#21222c', red: '#ff5555', green: '#50fa7b',
        yellow: '#f1fa8c', blue: '#bd93f9', magenta: '#ff79c6',
        cyan: '#8be9fd', white: '#f8f8f2',
        brightBlack: '#6272a4', brightRed: '#ff6e6e', brightGreen: '#69ff94',
        brightYellow: '#ffffa5', brightBlue: '#d6acff', brightMagenta: '#ff92df',
        brightCyan: '#a4ffff', brightWhite: '#ffffff'
    },
    'solarized-dark': {
        background: 'rgba(0, 43, 54, 0.92)',
        foreground: '#839496',
        cursor: '#839496',
        cursorAccent: '#002b36',
        selectionBackground: '#586e75',
        black: '#073642', red: '#dc322f', green: '#859900',
        yellow: '#b58900', blue: '#268bd2', magenta: '#d33682',
        cyan: '#2aa198', white: '#eee8d5',
        brightBlack: '#002b36', brightRed: '#cb4b16', brightGreen: '#586e75',
        brightYellow: '#657b83', brightBlue: '#839496', brightMagenta: '#6c71c4',
        brightCyan: '#93a1a1', brightWhite: '#fdf6e3'
    },
    'solarized-light': {
        background: 'rgba(253, 246, 227, 0.95)',
        foreground: '#657b83',
        cursor: '#657b83',
        cursorAccent: '#fdf6e3',
        selectionBackground: '#eee8d5',
        black: '#073642', red: '#dc322f', green: '#859900',
        yellow: '#b58900', blue: '#268bd2', magenta: '#d33682',
        cyan: '#2aa198', white: '#eee8d5',
        brightBlack: '#002b36', brightRed: '#cb4b16', brightGreen: '#586e75',
        brightYellow: '#657b83', brightBlue: '#839496', brightMagenta: '#6c71c4',
        brightCyan: '#93a1a1', brightWhite: '#fdf6e3'
    },
    'monokai': {
        background: 'rgba(39, 40, 34, 0.92)',
        foreground: '#f8f8f2',
        cursor: '#f8f8f2',
        cursorAccent: '#272822',
        selectionBackground: '#49483e',
        black: '#272822', red: '#f92672', green: '#a6e22e',
        yellow: '#f4bf75', blue: '#66d9ef', magenta: '#ae81ff',
        cyan: '#a1efe4', white: '#f8f8f2',
        brightBlack: '#75715e', brightRed: '#f92672', brightGreen: '#a6e22e',
        brightYellow: '#f4bf75', brightBlue: '#66d9ef', brightMagenta: '#ae81ff',
        brightCyan: '#a1efe4', brightWhite: '#f9f8f5'
    },
    'nord': {
        background: 'rgba(46, 52, 64, 0.92)',
        foreground: '#d8dee9',
        cursor: '#d8dee9',
        cursorAccent: '#2e3440',
        selectionBackground: '#4c566a',
        black: '#3b4252', red: '#bf616a', green: '#a3be8c',
        yellow: '#ebcb8b', blue: '#81a1c1', magenta: '#b48ead',
        cyan: '#88c0d0', white: '#e5e9f0',
        brightBlack: '#4c566a', brightRed: '#bf616a', brightGreen: '#a3be8c',
        brightYellow: '#ebcb8b', brightBlue: '#81a1c1', brightMagenta: '#b48ead',
        brightCyan: '#8fbcbb', brightWhite: '#eceff4'
    },
    'gruvbox-dark': {
        background: 'rgba(40, 40, 40, 0.92)',
        foreground: '#ebdbb2',
        cursor: '#ebdbb2',
        cursorAccent: '#282828',
        selectionBackground: '#504945',
        black: '#282828', red: '#cc241d', green: '#98971a',
        yellow: '#d79921', blue: '#458588', magenta: '#b16286',
        cyan: '#689d6a', white: '#a89984',
        brightBlack: '#928374', brightRed: '#fb4934', brightGreen: '#b8bb26',
        brightYellow: '#fabd2f', brightBlue: '#83a598', brightMagenta: '#d3869b',
        brightCyan: '#8ec07c', brightWhite: '#ebdbb2'
    }
};
let currentTheme = 'dark';

exports.setTheme = (nameOrJson) => {
    // 支持预设主题名或 JSON 自定义主题
    let theme = THEMES[nameOrJson];
    if (theme) {
        // 预设主题
        currentTheme = nameOrJson;
        term.options.theme = theme;
        document.body.setAttribute('data-theme', nameOrJson);
    } else if (nameOrJson && nameOrJson.startsWith('{')) {
        // 自定义主题 JSON
        try {
            theme = JSON.parse(nameOrJson);
            // 合并默认值，确保所有必要字段存在
            const base = THEMES['dark'];
            term.options.theme = Object.assign({}, base, theme);
            currentTheme = 'custom';
            document.body.setAttribute('data-theme', 'custom');
        } catch (e) {
            console.error('Invalid custom theme JSON', e);
        }
    }
};

exports.getThemes = () => JSON.stringify(Object.keys(THEMES));

exports.getCurrentTheme = () => currentTheme;

// Apply theme on load
exports.setTheme('dark');

// ============== Terminal Search ==============
let searchQuery = '';
let searchIndex = -1;
let searchResults = [];
let searchOverlay = null;
let searchInput = null;

function buildSearchOverlay() {
    if (searchOverlay) return;

    searchOverlay = document.createElement('div');
    searchOverlay.id = 'search-overlay';
    searchOverlay.style.cssText = 'position:absolute;top:8px;right:8px;z-index:100;display:none;' +
        'background:#1e1e2e;border:1px solid #444;border-radius:8px;padding:6px 10px;' +
        'box-shadow:0 4px 12px rgba(0,0,0,0.5);align-items:center;gap:4px;';

    searchInput = document.createElement('input');
    searchInput.type = 'text';
    searchInput.placeholder = 'Search...';
    searchInput.style.cssText = 'background:transparent;border:none;color:#cdd6f4;font-size:13px;' +
        'outline:none;width:160px;font-family:monospace;';

    const countLabel = document.createElement('span');
    countLabel.id = 'search-count';
    countLabel.style.cssText = 'color:#6c7086;font-size:11px;min-width:40px;text-align:center;';

    const prevBtn = document.createElement('button');
    prevBtn.textContent = '▲';
    prevBtn.style.cssText = 'background:#313244;border:none;color:#cdd6f4;border-radius:4px;' +
        'cursor:pointer;padding:2px 6px;font-size:10px;';
    prevBtn.onclick = () => searchInBuffer(-1);

    const nextBtn = document.createElement('button');
    nextBtn.textContent = '▼';
    nextBtn.style.cssText = 'background:#313244;border:none;color:#cdd6f4;border-radius:4px;' +
        'cursor:pointer;padding:2px 6px;font-size:10px;';
    nextBtn.onclick = () => searchInBuffer(1);

    const closeBtn = document.createElement('button');
    closeBtn.textContent = '✕';
    closeBtn.style.cssText = 'background:transparent;border:none;color:#6c7086;cursor:pointer;' +
        'font-size:13px;padding:2px 4px;';
    closeBtn.onclick = () => exports.hideSearch();

    searchOverlay.appendChild(searchInput);
    searchOverlay.appendChild(countLabel);
    searchOverlay.appendChild(prevBtn);
    searchOverlay.appendChild(nextBtn);
    searchOverlay.appendChild(closeBtn);

    const container = document.getElementById('terminal-container');
    if (container) container.appendChild(searchOverlay);

    searchInput.addEventListener('input', () => {
        searchQuery = searchInput.value;
        if (searchQuery.length > 0) {
            doSearch();
        } else {
            clearSearchHighlights();
            searchResults = [];
            searchIndex = -1;
            updateSearchCount();
        }
    });

    searchInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
            e.preventDefault();
            searchInBuffer(e.shiftKey ? -1 : 1);
        } else if (e.key === 'Escape') {
            e.preventDefault();
            exports.hideSearch();
            term.focus();
        }
    });
}

function doSearch() {
    searchResults = [];
    searchIndex = -1;
    const needle = searchQuery.toLowerCase();
    const buffer = term.buffer.active;

    for (let row = 0; row < buffer.length; row++) {
        const line = buffer.getLine(row);
        if (!line) continue;
        const text = line.translateToString(true).toLowerCase();
        let pos = -1;
        while ((pos = text.indexOf(needle, pos + 1)) !== -1) {
            searchResults.push({ row: row, col: pos });
        }
    }

    updateSearchCount();
    if (searchResults.length > 0) {
        searchIndex = 0;
        highlightResult(0);
    }
}

function searchInBuffer(direction) {
    if (searchResults.length === 0) return;

    searchIndex += direction;
    if (searchIndex < 0) searchIndex = searchResults.length - 1;
    if (searchIndex >= searchResults.length) searchIndex = 0;

    highlightResult(searchIndex);
    updateSearchCount();
}

function highlightResult(index) {
    if (index < 0 || index >= searchResults.length) return;

    const result = searchResults[index];
    const buffer = term.buffer.active;
    const viewportRows = term.rows;
    const targetScroll = result.row - Math.floor(viewportRows / 2);

    if (targetScroll >= 0 && targetScroll <= buffer.length - viewportRows) {
        term.scrollToLine(targetScroll);
    } else if (result.row < buffer.length - viewportRows) {
        term.scrollToLine(Math.max(0, result.row - 2));
    }

    term.select(result.col, result.row, searchQuery.length);
    term.scrollToLine(Math.max(0, result.row - Math.floor(viewportRows / 2)));
}

function clearSearchHighlights() {
    term.clearSelection();
}

function updateSearchCount() {
    const label = document.getElementById('search-count');
    if (label) {
        if (searchResults.length > 0) {
            label.textContent = `${searchIndex + 1}/${searchResults.length}`;
        } else if (searchQuery.length > 0) {
            label.textContent = '0/0';
        } else {
            label.textContent = '';
        }
    }
}

exports.showSearch = () => {
    buildSearchOverlay();
    searchOverlay.style.display = 'flex';
    searchInput.value = '';
    searchQuery = '';
    searchResults = [];
    searchIndex = -1;
    updateSearchCount();
    clearSearchHighlights();
    setTimeout(() => searchInput.focus(), 50);
};

exports.hideSearch = () => {
    if (searchOverlay) {
        searchOverlay.style.display = 'none';
    }
    clearSearchHighlights();
    searchQuery = '';
    searchResults = [];
    searchIndex = -1;
};

exports.findNext = () => searchInBuffer(1);
exports.findPrevious = () => searchInBuffer(-1);

// Keyboard shortcut: Ctrl+F or Cmd+F to open search
document.addEventListener('keydown', (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key === 'f') {
        e.preventDefault();
        if (searchOverlay && searchOverlay.style.display === 'flex') {
            exports.hideSearch();
        } else {
            exports.showSearch();
        }
    }
});

// ============== Boot Splash Screen ==============
let bootSplash = null;

function buildBootSplash() {
    if (bootSplash) return;
    bootSplash = document.createElement('div');
    bootSplash.id = 'boot-splash';
    bootSplash.style.cssText = 'position:absolute;top:0;left:0;width:100%;height:100%;z-index:50;' +
        'display:flex;flex-direction:column;align-items:center;justify-content:center;' +
        'background:rgba(0,0,0,0.95);transition:opacity 0.4s ease-out;';
    bootSplash.innerHTML = `
        <div style="text-align:center;font-family:monospace;color:#61afef;font-size:14px;line-height:1.6;">
            <pre style="margin:0;color:#c678dd;">
     |  | _)   __|  |  |
     __ |  | \\\\__ \\\\  __ |
    _| _| _| ____/ _| _|
            </pre>
            <div style="margin-top:20px;color:#56b6c2;">
                <span id="boot-status">Booting VM...</span>
            </div>
            <div style="margin-top:12px;display:flex;gap:6px;justify-content:center;">
                <span class="boot-dot" style="animation:bootBounce 1.4s infinite 0s;">●</span>
                <span class="boot-dot" style="animation:bootBounce 1.4s infinite 0.2s;">●</span>
                <span class="boot-dot" style="animation:bootBounce 1.4s infinite 0.4s;">●</span>
            </div>
        </div>
        <style>
            @keyframes bootBounce {
                0%, 80%, 100% { opacity: 0.3; transform: scale(0.8); }
                40% { opacity: 1; transform: scale(1); }
            }
        </style>`;

    const container = document.getElementById('terminal-container');
    if (container) container.appendChild(bootSplash);
}

exports.showBootSplash = () => {
    buildBootSplash();
    bootSplash.style.display = 'flex';
    bootSplash.style.opacity = '1';
};

exports.hideBootSplash = () => {
    if (bootSplash) {
        bootSplash.style.display = 'none';
    }
};

exports.setBootStatus = (status) => {
    const el = document.getElementById('boot-status');
    if (el) el.textContent = status;
};

// Show boot splash on initialization (before VM starts)
exports.showBootSplash();

// ============== Font Management ==============
const FONT_LIST = [
    { name: 'CodeNewRoman NF Mono', family: '"CodeNewRomanNerdFontMono", monospace' },
    { name: 'Source Code Pro', family: '"SourceCodePro", monospace' },
    { name: 'Cascadia Code', family: '"CascadiaCode", monospace' },
    { name: 'JetBrains Mono', family: '"JetBrainsMono", monospace' },
    { name: 'Fira Code', family: '"FiraCode", monospace' },
    { name: 'Monospace', family: 'monospace' },
];

exports.setFont = (fontName) => {
    // 先查预设字体名，匹配不到则视为原始 CSS font-family 字符串
    const font = FONT_LIST.find(f => f.name === fontName);
    if (font) {
        term.options.fontFamily = font.family;
    } else if (fontName && fontName.length > 0) {
        // 自定义字体：直接使用用户输入的 font-family 值
        term.options.fontFamily = fontName;
    }
    // fit 由调用方负责（syncPrefs 期间 fit 由 initialize 统一触发，避免提前 resize 到未启动的 VM）
};

exports.getFonts = () => JSON.stringify(FONT_LIST.map(f => f.name));

exports.getCurrentFont = () => {
    // Find current font from list matching term.options.fontFamily
    const current = term.options.fontFamily;
    const match = FONT_LIST.find(f => f.family === current);
    return match ? match.name : FONT_LIST[0].name;
};
