const std = @import("std");
const os = std.os;

const wl = @import("wayland").server.wl;

const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const C = @import("C.zig");

const ally = std.heap.c_allocator;

const Server = @import("Server.zig");

var scm_module: C.SCM = undefined;
var scm_output_type: C.SCM = undefined;

pub fn scm_init() void {
    scm_module = C.scm_c_define_module(
        "winter output internal",
        scm_initModule,
        null,
    );
}

fn scm_initModule(_: ?*anyopaque) callconv(.C) void {}
