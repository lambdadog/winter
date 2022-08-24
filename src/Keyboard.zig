const std = @import("std");
const os = std.os;

const wl = @import("wayland").server.wl;

const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const C = @import("C.zig");

const ally = std.heap.c_allocator;

const Server = @import("Server.zig");

pub var scm_keyboard_type: C.SCM = undefined;

pub fn scm_init() void {
    _ = C.scm_c_define_module(
        "wl keyboard internal",
        scm_initModule,
        null,
    );
}

fn scm_initModule(_: ?*anyopaque) callconv(.C) void {
    scm_keyboard_type = C.scm_make_foreign_object_type(
        C.scm_from_utf8_symbol("keyboard"),
        C.scm_list_1(
            C.scm_from_utf8_symbol("ptr"),
        ),
        null,
    );
}

pub fn keyboardToScm(keyboard: *Keyboard) C.SCM {
    return C.scm_make_foreign_object_1(
        scm_keyboard_type,
        keyboard,
    );
}

pub fn scmToKeyboard(scm_keyboard: C.SCM) *Keyboard {
    C.scm_assert_foreign_object_type(scm_keyboard_type, scm_keyboard);

    return @ptrCast(
        *Keyboard,
        @alignCast(
            @alignOf(*Keyboard),
            C.scm_foreign_object_ref(scm_keyboard, 0).?,
        ),
    );
}

const Keyboard = @This(); // {

server: *Server,
seat: *wlr.Seat,

link: wl.list.Link = undefined,
input_device: *wlr.InputDevice,

modifiers_listener: wl.Listener(*wlr.Keyboard),
key_listener: wl.Listener(*wlr.Keyboard.event.Key),

fn create(server: *Server, input_device: *wlr.InputDevice) !*Keyboard {
    const self = try ally.create(Keyboard);
    errdefer ally.destroy(self);

    self.* = .{
        .server = server,
        .seat = server.seat,

        .input_device = input_device,

        // listeners
        .modifiers_listener = wl.Listener(*wlr.Keyboard).init(
            onModifiers,
        ),
        .key_listener = wl.Listener(*wlr.Keyboard.event.Key).init(
            onKey,
        ),
    };

    const context = xkb.Context.new(.no_flags) orelse {
        return error.ContextFailed;
    };
    defer context.unref();
    const keymap = xkb.Keymap.newFromString(
        context,
        .{},
        .no_flags,
    ) orelse return error.KeymapFailed;
    defer keymap.unref();

    const wlr_keyboard = self.input_device.device.keyboard;
    if (!wlr_keyboard.setKeymap(keymap)) return error.SetKeymapFailed;
    wlr_keyboard.setRepeatInfo(25, 600);

    wlr_keyboard.events.modifiers.add(&self.modifiers_listener);
    wlr_keyboard.events.key.add(&self.key_listener);

    self.seat.setKeyboard(input_device);
}

fn onModifiers(listener: *wl.Listener(*wlr.Keyboard), wlr_keyboard: *wlr.Keyboard) void {
    const self = @fieldParentPtr(Keyboard, "modifiers_listener", listener);

    self.seat.setKeyboard(keyboard.device);
    self.seat.keyboardNotifyModifiers(&wlr_keyboard.modifiers);
}

fn onKey(
    listener: *wl.Listener(*wlr.Keyboard.event.Key),
    event: *wlr.Keyboard.event.Key,
) void {
    const self = @fieldParentPtr(Keyboard, "key_listener", listener);
    const wlr_keyboard = self.input_device.device.keyboard;

    // // Translate libinput keycode -> xkbcommon
    // const keycode = event.keycode + 8;

    var handled = false;

    // potentially handle key

    if (!handled) {
        self.seat.setKeyboard(keyboard.device);
        self.seat.keyboardNotifyKey(event.time_msec, event.keycode, event.state);
    }
}
