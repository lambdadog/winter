const std = @import("std");
const os = std.os;

const wl = @import("wayland").server.wl;

const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const C = @import("C.zig");

const ally = std.heap.c_allocator;

const Server = @import("Server.zig");

pub var scm_cursor_type: C.SCM = undefined;

pub fn scm_init() void {
    _ = C.scm_c_define_module(
        "wl cursor internal",
        scm_initModule,
        null,
    );
}

fn scm_initModule(_: ?*anyopaque) callconv(.C) void {
    scm_cursor_type = C.scm_make_foreign_object_type(
        C.scm_from_utf8_symbol("cursor"),
        C.scm_list_1(
            C.scm_from_utf8_symbol("ptr"),
        ),
        null,
    );
}

pub fn cursorToScm(cursor: *Cursor) C.SCM {
    return C.scm_make_foreign_object_1(
        scm_cursor_type,
        cursor,
    );
}

pub fn scmToCursor(scm_cursor: C.SCM) *Cursor {
    C.scm_assert_foreign_object_type(scm_cursor_type, scm_cursor);

    return @ptrCast(
        *Cursor,
        @alignCast(
            @alignOf(*Cursor),
            C.scm_foreign_object_ref(scm_cursor, 0).?,
        ),
    );
}

const Cursor = @This(); // {

server: *Server,
seat: *wlr.Seat,

wlr_cursor: *wlr.Cursor,
cursor_mgr: *wlr.XcursorManager,

// TODO: add grabbing and resizing
mode: enum { passthrough } = .passthrough,

request_set_listener: wl.Listener(*wlr.Seat.event.RequestSetCursor),

motion_listener: wl.Listener(*wlr.Pointer.event.Motion),
motion_absolute_listener: wl.Listener(*wlr.Pointer.event.MotionAbsolute),
button_listener: wl.Listener(*wlr.Pointer.event.Button),
axis_listener: wl.Listener(*wlr.Pointer.event.Axis),
frame_listener: wl.Listener(*wlr.Cursor),

pub fn init(self: *Cursor, server: *Server) !void {
    self.* = .{
        .server = server,
        .seat = server.seat,

        .wlr_cursor = try wlr.Cursor.create(),
        .cursor_mgr = try wlr.XcursorManager.create(null, 24),

        // listeners
        .request_set_listener = wl.Listener(*wlr.Seat.event.RequestSetCursor).init(
            onRequestSet,
        ),

        .motion_listener = wl.Listener(*wlr.Pointer.event.Motion).init(
            onMotion,
        ),
        .motion_absolute_listener = wl.Listener(*wlr.Pointer.event.MotionAbsolute).init(
            onMotionAbsolute,
        ),
        .button_listener = wl.Listener(*wlr.Pointer.event.Button).init(
            onButton,
        ),
        .axis_listener = wl.Listener(*wlr.Pointer.event.Axis).init(
            onAxis,
        ),
        .frame_listener = wl.Listener(*wlr.Cursor).init(
            onFrame,
        ),
    };

    self.wlr_cursor.attachOutputLayout(server.output_layout);

    // TODO: actually handle scaling correctly
    try self.cursor_mgr.load(1);

    self.seat.events.request_set_cursor.add(&self.request_set_listener);

    self.wlr_cursor.events.motion.add(&self.motion_listener);
    self.wlr_cursor.events.motion_absolute.add(&self.motion_absolute_listener);
    self.wlr_cursor.events.button.add(&self.button_listener);
    self.wlr_cursor.events.axis.add(&self.axis_listener);
    self.wlr_cursor.events.frame.add(&self.frame_listener);
}

//fn destroy(self: *Cursor) {}

pub fn attachInputDevice(self: *Cursor, input_device: *wlr.InputDevice) void {
    self.wlr_cursor.attachInputDevice(input_device);
}

fn onRequestSet(
    listener: *wl.Listener(*wlr.Seat.event.RequestSetCursor),
    event: *wlr.Seat.event.RequestSetCursor,
) void {
    const self = @fieldParentPtr(Cursor, "request_set_listener", listener);

    if (event.seat_client == self.seat.pointer_state.focused_client) {
        self.wlr_cursor.setSurface(
            event.surface,
            event.hotspot_x,
            event.hotspot_y,
        );
    }
}

fn onMotion(
    listener: *wl.Listener(*wlr.Pointer.event.Motion),
    event: *wlr.Pointer.event.Motion,
) void {
    const self = @fieldParentPtr(Cursor, "motion_listener", listener);

    self.wlr_cursor.move(event.device, event.delta_x, event.delta_y);
    self.processMotion(event.time_msec);
}

fn onMotionAbsolute(
    listener: *wl.Listener(*wlr.Pointer.event.MotionAbsolute),
    event: *wlr.Pointer.event.MotionAbsolute,
) void {
    const self = @fieldParentPtr(Cursor, "motion_absolute_listener", listener);

    self.wlr_cursor.warpAbsolute(event.device, event.x, event.y);
    self.processMotion(event.time_msec);
}

fn processMotion(self: *Cursor, time_msec: u32) void {
    switch (self.mode) {
        .passthrough => if (self.server.viewAt(
            self.wlr_cursor.x,
            self.wlr_cursor.y,
        )) |result| {
            self.seat.pointerNotifyEnter(
                result.surface,
                result.relative_x,
                result.relative_y,
            );
            self.seat.pointerNotifyMotion(
                time_msec,
                result.relative_x,
                result.relative_y,
            );
        } else {
            self.cursor_mgr.setCursorImage("left_ptr", self.wlr_cursor);
            self.seat.pointerClearFocus();
        },
    }
}

fn onButton(
    listener: *wl.Listener(*wlr.Pointer.event.Button),
    event: *wlr.Pointer.event.Button,
) void {
    const self = @fieldParentPtr(Cursor, "button_listener", listener);

    _ = self.seat.pointerNotifyButton(event.time_msec, event.button, event.state);
    if (event.state == .released) {
        self.mode = .passthrough;
    } else if (self.server.viewAt(self.wlr_cursor.x, self.wlr_cursor.y)) |result| {
        _ = result;
        // self.server.focusView(result.view, result.surface);
    }
}

fn onAxis(
    listener: *wl.Listener(*wlr.Pointer.event.Axis),
    event: *wlr.Pointer.event.Axis,
) void {
    const self = @fieldParentPtr(Cursor, "axis_listener", listener);
    self.seat.pointerNotifyAxis(
        event.time_msec,
        event.orientation,
        event.delta,
        event.delta_discrete,
        event.source,
    );
}

fn onFrame(
    listener: *wl.Listener(*wlr.Cursor),
    _: *wlr.Cursor,
) void {
    const self = @fieldParentPtr(Cursor, "frame_listener", listener);
    self.seat.pointerNotifyFrame();
}

// }
