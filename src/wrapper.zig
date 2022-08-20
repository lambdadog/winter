const std = @import("std");
const C = @cImport({
    @cInclude("libguile.h");
});

const guile_mode_main = @import("main.zig").main;

pub fn main() anyerror!void {
    _ = C.scm_with_guile(innerMain, null);
}

// A small sacrifice to appease the scheme gods...
fn innerMain(_: ?*anyopaque) callconv(.C) ?*anyopaque {
    // If I ever get to the point where I'm handling all errors I'll
    // be happy to have done this, but for now it's probably
    // unnecessary. I just don't want to have to think about the
    // wrapper code at all.
    switch (@typeInfo(@TypeOf(guile_mode_main))) {
        .Fn => |fn_info| {
            if (fn_info.return_type) |return_type| {
                switch (@typeInfo(return_type)) {
                    .Void => guile_mode_main(),
                    .ErrorUnion => guile_mode_main() catch |err| {
                        std.debug.print("{}\n", .{err});
                        if (@errorReturnTrace()) |trace| {
                            std.debug.dumpStackTrace(trace.*);
                        }
                    },
                    else => unreachable,
                }
            } else {
                guile_mode_main();
            }
        },
        else => @compileError("main must be a function"),
    }
    return null;
}
