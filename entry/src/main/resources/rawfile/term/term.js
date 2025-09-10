hterm.Terminal.IO.prototype.sendString = function (data) {
    native.sendInput(data);
};
hterm.Terminal.IO.prototype.onVTKeystroke = function (data) {
    native.sendInput(data);
};
hterm.Terminal.IO.prototype.onTerminalResize = function (width, height) {
    native.resize(width, height);
};

hterm.defaultStorage = new lib.Storage.Memory();
window.onload = async function () {
    await lib.init();
    window.term = new hterm.Terminal();

    term.getPrefs().set('cursor-color', '#cccccc');
    term.getPrefs().set('background-color', '#000000');
    term.getPrefs().set('terminal-encoding', 'iso-2022');
    term.getPrefs().set('enable-resize-status', false);
    term.getPrefs().set('copy-on-select', false);
    term.getPrefs().set('mouse-right-click-paste', false);
    term.getPrefs().set('enable-clipboard-notice', false);
    term.getPrefs().set('screen-padding-size', 4);
    // Creating and preloading the <audio> element for this sometimes hangs WebKit on iOS 16 for some reason. Can be most easily reproduced by resetting a simulator and starting the app. System logs show Fig hanging while trying to do work.
    term.getPrefs().set('audible-bell-sound', '');

    var fontSize = native.getFontSize();
    if (fontSize) {
        term.getPrefs().set('font-size', fontSize);
    }

    term.onTerminalReady = onTerminalReady;
    term.decorate(document.getElementById('terminal'));
    term.installKeyboard();
};

function onTerminalReady() {

    // Functions for native -> JS
    window.exports = {};

    this.setCursorVisible(true);
    var io = term.io.push();
    term.reset();

    let decoder = new TextDecoder();
    exports.write = (data) => {
        term.io.writeUTF16(decoder.decode(lib.codec.stringToCodeUnitArray(data)));
    };
    exports.paste = (data) => {
        term.io.sendString(decoder.decode(lib.codec.stringToCodeUnitArray(data)));
    };

    // hterm size updates native size
    exports.getSize = () => [term.screenSize.width, term.screenSize.height];

    // selection, copying
    term.blur();
    term.focus();
    exports.copy = () => term.getSelectionText();

    // focus
    // This listener blocks blur events that come in because the webview has lost first responder
    term.scrollPort_.screen_.addEventListener('blur', (e) => {
        if (e.target.ownerDocument.activeElement == e.target) {
            e.stopPropagation();
        }
    }, { capture: true });

    exports.setFocused = (focus) => {
        if (focus) {
            term.focus();
        } else {
            term.blur();
        }
    };
    // Scroll to bottom wrapper
    exports.scrollToBottom = () => term.scrollEnd();
    // Set scroll position
    exports.newScrollTop = (y) => {
        // two lines instead of one because the value you read out of scrollTop can be different from the value you write into it
        term.scrollPort_.screen_.scrollTop = y;
        lastScrollTop = term.scrollPort_.screen_.scrollTop;
    };

    exports.updateStyle = ({
        foregroundColor,
        backgroundColor,
        fontFamily,
        fontSize,
        colorPaletteOverrides,
        blinkCursor,
        cursorShape
    }) => {
        term.getPrefs().set('background-color', backgroundColor);
        term.getPrefs().set('foreground-color', foregroundColor);
        term.getPrefs().set('cursor-color', foregroundColor);
        term.getPrefs().set('font-family', fontFamily);
        term.getPrefs().set('font-size', fontSize);
        term.getPrefs().set('color-palette-overrides', colorPaletteOverrides);
        term.getPrefs().set('cursor-blink', blinkCursor);
        term.getPrefs().set('cursor-shape', cursorShape);
    };

    exports.getCharacterSize = () => {
        return [term.scrollPort_.characterSize.width, term.scrollPort_.characterSize.height];
    };

    exports.clearScrollback = () => term.clearScrollback();
    exports.setUserGesture = () => term.accessibilityReader_.hasUserGesture = true;

    hterm.openUrl = (url) => native.openLink(url);

    native.load();
}
