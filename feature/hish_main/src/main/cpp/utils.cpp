//
// VNC Utils Implementation for HiSH
//

#include "include/utils.hpp"
#include <cstring>

std::tuple<napi_value, uint8_t *> createNewBuffer(napi_env env, size_t num) {
    napi_value buffer;
    uint8_t *arrayPtr = NULL;
    if (napi_ok != napi_create_arraybuffer(env, num * sizeof(uint8_t), (void **)&arrayPtr, &buffer)) {
        napi_throw_error(env, "-10", "napi_create_arraybuffer error.");
        return std::make_tuple(nullptr, nullptr);
    }

    napi_value array;
    if (napi_ok != napi_create_typedarray(env, napi_uint8_array, num, buffer, 0, &array)) {
        napi_throw_error(env, "-10", "napi_create_typedarray error.");
        return std::make_tuple(nullptr, nullptr);
    };

    memset(arrayPtr, 0, num);

    return std::make_tuple(array, arrayPtr);
}

rfbKeySym ohKeyCode2RFBKeyCode(Input_KeyCode k, rfbBool down) {
    static bool alt = false, ctrl = false, shift = false;
    switch (k) {
    case KEYCODE_UNKNOWN:
    case KEYCODE_FN:
    case KEYCODE_VOLUME_UP:
    case KEYCODE_VOLUME_DOWN:
    case KEYCODE_POWER:
    case KEYCODE_CAMERA:
    case KEYCODE_VOLUME_MUTE:
    case KEYCODE_MUTE:
    case KEYCODE_BRIGHTNESS_UP:
    case KEYCODE_BRIGHTNESS_DOWN:
        return XK_VoidSymbol;
    case KEYCODE_0:
        return shift ? XK_parenright : XK_0;
    case KEYCODE_1:
        return shift ? XK_exclam : XK_1;
    case KEYCODE_2:
        return shift ? XK_at : XK_2;
    case KEYCODE_3:
        return shift ? XK_numbersign : XK_3;
    case KEYCODE_4:
        return shift ? XK_dollar : XK_4;
    case KEYCODE_5:
        return shift ? XK_percent : XK_5;
    case KEYCODE_6:
        return shift ? XK_asciicircum : XK_6;
    case KEYCODE_7:
        return shift ? XK_ampersand : XK_7;
    case KEYCODE_8:
        return shift ? XK_asterisk : XK_8;
    case KEYCODE_9:
        return (shift ? XK_parenleft : XK_9);
    case KEYCODE_STAR:
        return XK_asterisk;
    case KEYCODE_POUND:
        return XK_numbersign;
    case KEYCODE_DPAD_UP:
        return XK_Up;
    case KEYCODE_DPAD_DOWN:
        return XK_Down;
    case KEYCODE_DPAD_LEFT:
        return XK_Left;
    case KEYCODE_DPAD_RIGHT:
        return XK_Right;
    case KEYCODE_DPAD_CENTER:
        return XK_VoidSymbol;
    case KEYCODE_A:
        return shift ? XK_A : XK_a;
    case KEYCODE_B:
        return shift ? XK_B : XK_b;
    case KEYCODE_C:
        return shift ? XK_C : XK_c;
    case KEYCODE_D:
        return shift ? XK_D : XK_d;
    case KEYCODE_E:
        return shift ? XK_E : XK_e;
    case KEYCODE_F:
        return shift ? XK_F : XK_f;
    case KEYCODE_G:
        return shift ? XK_G : XK_g;
    case KEYCODE_H:
        return shift ? XK_H : XK_h;
    case KEYCODE_I:
        return shift ? XK_I : XK_i;
    case KEYCODE_J:
        return shift ? XK_J : XK_j;
    case KEYCODE_K:
        return shift ? XK_K : XK_k;
    case KEYCODE_L:
        return shift ? XK_L : XK_l;
    case KEYCODE_M:
        return shift ? XK_M : XK_m;
    case KEYCODE_N:
        return shift ? XK_N : XK_n;
    case KEYCODE_O:
        return shift ? XK_O : XK_o;
    case KEYCODE_P:
        return shift ? XK_P : XK_p;
    case KEYCODE_Q:
        return shift ? XK_Q : XK_q;
    case KEYCODE_R:
        return shift ? XK_R : XK_r;
    case KEYCODE_S:
        return shift ? XK_S : XK_s;
    case KEYCODE_T:
        return shift ? XK_T : XK_t;
    case KEYCODE_U:
        return shift ? XK_U : XK_u;
    case KEYCODE_V:
        return shift ? XK_V : XK_v;
    case KEYCODE_W:
        return shift ? XK_W : XK_w;
    case KEYCODE_X:
        return shift ? XK_X : XK_x;
    case KEYCODE_Y:
        return shift ? XK_Y : XK_y;
    case KEYCODE_Z:
        return shift ? XK_Z : XK_z;
    case KEYCODE_COMMA:
        return shift ? XK_less : XK_comma;
    case KEYCODE_PERIOD:
        return shift ? XK_greater : XK_period;
    case KEYCODE_ALT_LEFT:
        alt = down;
        return XK_Alt_L;
    case KEYCODE_ALT_RIGHT:
        alt = down;
        return XK_Alt_R;
    case KEYCODE_SHIFT_LEFT:
        shift = down;
        return XK_Shift_L;
    case KEYCODE_SHIFT_RIGHT:
        shift = down;
        return XK_Shift_R;
    case KEYCODE_TAB:
        return XK_Tab;
    case KEYCODE_SPACE:
        return XK_space;
    case KEYCODE_SYM:
        return XK_VoidSymbol;
    case KEYCODE_EXPLORER:
        return XK_VoidSymbol;
    case KEYCODE_ENVELOPE:
        return XK_VoidSymbol;
    case KEYCODE_ENTER:
        return XK_Return;
    case KEYCODE_DEL:
        return XK_BackSpace;
    case KEYCODE_GRAVE:
        return XK_grave;
    case KEYCODE_MINUS:
        return shift ? XK_underscore : XK_minus;
    case KEYCODE_EQUALS:
        return shift ? XK_plus : XK_equal;
    case KEYCODE_LEFT_BRACKET:
        return shift ? XK_braceleft : XK_bracketleft;
    case KEYCODE_RIGHT_BRACKET:
        return shift ? XK_braceright : XK_bracketright;
    case KEYCODE_BACKSLASH:
        return shift ? XK_bar : XK_backslash;
    case KEYCODE_SEMICOLON:
        return shift ? XK_colon : XK_semicolon;
    case KEYCODE_APOSTROPHE:
        return shift ? XK_quotedbl : XK_apostrophe;
    case KEYCODE_SLASH:
        return shift ? XK_question : XK_slash;
    case KEYCODE_AT:
        return XK_at;
    case KEYCODE_PLUS:
        return XK_plus;
    case KEYCODE_MENU:
        return XK_Menu;
    case KEYCODE_PAGE_UP:
        return XK_Page_Up;
    case KEYCODE_PAGE_DOWN:
        return XK_Page_Down;
    case KEYCODE_ESCAPE:
        return XK_Escape;
    case KEYCODE_FORWARD_DEL:
        return XK_Delete;
    case KEYCODE_CTRL_LEFT:
        ctrl = down;
        return XK_Control_L;
    case KEYCODE_CTRL_RIGHT:
        ctrl = down;
        return XK_Control_R;
    case KEYCODE_CAPS_LOCK:
        return XK_Caps_Lock;
    case KEYCODE_SCROLL_LOCK:
        return XK_Scroll_Lock;
    case KEYCODE_META_LEFT:
        return XK_Meta_L;
    case KEYCODE_META_RIGHT:
        return XK_Meta_R;
    case KEYCODE_FUNCTION:
        return XK_VoidSymbol;
    case KEYCODE_SYSRQ:
        return XK_Sys_Req;
    case KEYCODE_BREAK:
        return XK_Break;
    case KEYCODE_MOVE_HOME:
        return XK_Home;
    case KEYCODE_MOVE_END:
        return XK_End;
    case KEYCODE_INSERT:
        return XK_Insert;
    case KEYCODE_FORWARD:
        return XK_VoidSymbol;
    case KEYCODE_MEDIA_PLAY:
        return XK_VoidSymbol;
    case KEYCODE_MEDIA_PAUSE:
        return XK_VoidSymbol;
    case KEYCODE_MEDIA_CLOSE:
        return XK_VoidSymbol;
    case KEYCODE_MEDIA_EJECT:
        return XK_VoidSymbol;
    case KEYCODE_MEDIA_RECORD:
        return XK_VoidSymbol;
    case KEYCODE_F1:
        return XK_F1;
    case KEYCODE_F2:
        return XK_F2;
    case KEYCODE_F3:
        return XK_F3;
    case KEYCODE_F4:
        return XK_F4;
    case KEYCODE_F5:
        return XK_F5;
    case KEYCODE_F6:
        return XK_F6;
    case KEYCODE_F7:
        return XK_F7;
    case KEYCODE_F8:
        return XK_F8;
    case KEYCODE_F9:
        return XK_F9;
    case KEYCODE_F10:
        return XK_F10;
    case KEYCODE_F11:
        return XK_F11;
    case KEYCODE_F12:
        return XK_F12;
    case KEYCODE_NUM_LOCK:
        return XK_Num_Lock;
    case KEYCODE_NUMPAD_0:
        return XK_KP_0;
    case KEYCODE_NUMPAD_1:
        return XK_KP_1;
    case KEYCODE_NUMPAD_2:
        return XK_KP_2;
    case KEYCODE_NUMPAD_3:
        return XK_KP_3;
    case KEYCODE_NUMPAD_4:
        return XK_KP_4;
    case KEYCODE_NUMPAD_5:
        return XK_KP_5;
    case KEYCODE_NUMPAD_6:
        return XK_KP_6;
    case KEYCODE_NUMPAD_7:
        return XK_KP_7;
    case KEYCODE_NUMPAD_8:
        return XK_KP_8;
    case KEYCODE_NUMPAD_9:
        return XK_KP_9;
    case KEYCODE_NUMPAD_DIVIDE:
        return XK_KP_Divide;
    case KEYCODE_NUMPAD_MULTIPLY:
        return XK_KP_Multiply;
    case KEYCODE_NUMPAD_SUBTRACT:
        return XK_KP_Subtract;
    case KEYCODE_NUMPAD_ADD:
        return XK_KP_Add;
    case KEYCODE_NUMPAD_DOT:
        return XK_KP_Decimal;
    case KEYCODE_NUMPAD_COMMA:
        return XK_KP_Separator;
    case KEYCODE_NUMPAD_ENTER:
        return XK_KP_Enter;
    case KEYCODE_NUMPAD_EQUALS:
        return XK_KP_Equal;
    case KEYCODE_NUMPAD_LEFT_PAREN:
        return XK_VoidSymbol;
    case KEYCODE_NUMPAD_RIGHT_PAREN:
        return XK_VoidSymbol;
    default:
        return XK_VoidSymbol;
    }
}
