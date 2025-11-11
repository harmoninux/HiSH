window.exports = {};

function installVirtualCtrl() {
    var ctrlPressed = false;

    function preProcessKeyEvent(e) {
        if (ctrlPressed) {
            Object.defineProperty(e, 'ctrlKey', { value: true });
            Object.defineProperty(e, 'returnValue', { value: true });
            Object.defineProperty(e, 'defaultPrevented', { value: true });
        }
    }

    hterm.Keyboard.prototype.originalOnKeyDown_ = hterm.Keyboard.prototype.onKeyDown_;
    hterm.Keyboard.prototype.onKeyDown_ = function (e) {
        console.log('keyDown', e)
        preProcessKeyEvent(e);
        this.originalOnKeyDown_(e);
    };
    hterm.Keyboard.prototype.originalonKeyPress_ = hterm.Keyboard.prototype.onKeyPress_;
    hterm.Keyboard.prototype.onKeyPress_ = function (e) {
        console.log('keyPress', e)
        preProcessKeyEvent(e);
        this.originalonKeyPress_(e);
    };
    hterm.Keyboard.prototype.originalOnKeyUp_ = hterm.Keyboard.prototype.onKeyUp_;
    hterm.Keyboard.prototype.onKeyUp_ = function (e) {
        console.log('keyUp', e)
        preProcessKeyEvent(e);
        this.originalOnKeyUp_(e);
    };
    hterm.Keyboard.prototype.originalOnTextInput_ = hterm.Keyboard.prototype.onTextInput_;
    hterm.Keyboard.prototype.onTextInput_ = function (e) {
        console.log('textInput', e)
        if (!ctrlPressed) {
            this.originalOnTextInput_(e);
        } else {
            var data = ''
            for (var i = 0; i < e.data.length; i++) {
                var c;
                if (e.data[i] >= 'a' && e.data[i] <= 'z') {
                    c = String.fromCharCode(e.data.charCodeAt(i) - 'a'.charCodeAt(0) + 1);
                } else {
                    c = e.data.charAt(i);
                }
                data += c;
            }
            Object.defineProperty(e, 'data', { value: data })
            this.originalOnTextInput_(e)
        }
        e.preventDefault();
        e.stopPropagation();
    };

    exports.setCtrlPressed = (b) => {
        ctrlPressed = b;
    };
}

installVirtualCtrl();

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

    exports.clearScrollback = () => term.clearScrollback();

    exports.setFontSize = (fontSize) => term.getPrefs().set('font-size', fontSize);

    hterm.openUrl = (url) => native.openLink(url);

    io.print(
        'HiSH is starting...\r\n\r\n' +
            '     |  | _)   __|  |  |\r\n' +
            '     __ |  | \\__ \\  __ |\r\n' +
            '    _| _| _| ____/ _| _|\r\n'+
            '\r\n'
    );

    native.load();
}
