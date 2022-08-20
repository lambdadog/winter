const std = @import("std");
const wlr = @import("wlroots");

const Output = @import("Output.zig");
const View = @import("View.zig");
const C = @import("C.zig");

const Server = @import("Server.zig");

fn scmInit() void {
    Server.scmInit();
    Output.scmInit();
    View.scmInit();

    _ = C.scm_c_primitive_load("./scheme/init.scm");
}

pub fn main() anyerror!void {
    wlr.log.init(.debug);

    const server = try Server.create();
    defer server.destroy();

    var buf: [11]u8 = undefined;
    const socket = try server.wl_server.addSocketAuto(&buf);

    try server.backend.start();

    scmInit();

    std.log.info("Running compositor on WAYLAND_DISPLAY={s}", .{socket});
    server.wl_server.run();
}
