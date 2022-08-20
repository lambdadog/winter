const std = @import("std");

const wlr = @import("wlroots");

const Server = @import("Server.zig");
const scheme = @import("scheme.zig");

pub fn main() anyerror!void {
    wlr.log.init(.debug);

    const server = try Server.create();
    defer server.destroy();

    var buf: [11]u8 = undefined;
    const socket = try server.wl_server.addSocketAuto(&buf);

    try server.backend.start();

    scheme.init();

    std.log.info("Running compositor on WAYLAND_DISPLAY={s}", .{socket});
    server.wl_server.run();
}
