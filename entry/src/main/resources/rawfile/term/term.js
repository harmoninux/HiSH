window.exports = {};

hterm.Keyboard.prototype.originalOnTextInput_ = hterm.Keyboard.prototype.onTextInput_;
hterm.Keyboard.prototype.onTextInput_ = function (e) {
    // console.log('textInput', e)
    this.originalOnTextInput_(e);
    e.preventDefault();
    e.stopPropagation();
};

hterm.Terminal.IO.prototype.sendString = function (data) {
    console.log('sendString', data)
    native.sendInput(data);
};
hterm.Terminal.IO.prototype.onVTKeystroke = function (data) {
    console.log('onVTKeystroke', data)
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
    var cursorShape = native.getCursorShape();
    if (cursorShape) {
        term.getPrefs().set('cursor-shape', cursorShape);
    }
    var cursorBlink = native.getCursorBlink();
    if (cursorBlink) {
        term.getPrefs().set('cursor-blink', cursorBlink);
    }

    term.onTerminalReady = onTerminalReady;
    term.decorate(document.getElementById('terminal'));
    term.installKeyboard();
};

function onTerminalReady() {

    this.setCursorVisible(true);
    var io = term.io.push();
    term.reset();

    let decoder = new TextDecoder();
    exports.write = (data) => {
        term.io.writeUTF16(decoder.decode(lib.codec.stringToCodeUnitArray(data), { stream: true }));
    };
    exports.paste = (data) => {
        term.io.sendString(decoder.decode(lib.codec.stringToCodeUnitArray(data), { stream: true }));
    };
    exports.clearScrollback = () => {
        term.clearScrollback()
        //  真机上运行会黑屏，加上这个就好了
        term.setHeight(term.screenSize.height)
        setTimeout(() => term.setHeight(null), 50)
    }

    // hterm size updates native size
    exports.getSize = () => [term.screenSize.width, term.screenSize.height];

    // selection, copying
    term.blur();
    term.focus();
    exports.copy = () => term.getSelectionText();

    exports.setFocused = (focus) => {
        if (focus) {
            term.focus();
        } else {
            term.blur();
        }
    };

    exports.getCharacterSize = () => {
        return [term.scrollPort_.characterSize.width, term.scrollPort_.characterSize.height];
    };

    exports.setFontSize = (fontSize) => term.getPrefs().set('font-size', fontSize);
    exports.setCursorShape = (shape) => term.getPrefs().set('cursor-shape', shape);
    exports.setCursorBlink = (blink) => term.getPrefs().set('cursor-blink', blink);

    hterm.openUrl = (url) => native.openLink(url);

    io.print(
        'HiSH is starting...\r\n\r\n' +
        '     |  | _)   __|  |  |\r\n' +
        '     __ |  | \\__ \\  __ |\r\n' +
        '    _| _| _| ____/ _| _|\r\n' +
        '\r\n'
    );

    native.load();

    let selectionTimeout;
    document.addEventListener('selectionchange', () => {
        clearTimeout(selectionTimeout);
        selectionTimeout = setTimeout(() => {
            const text = term.getSelectionText();
            if (text) {
                native.onSelectionChange(text);
            }
        }, 200);
    });
}
