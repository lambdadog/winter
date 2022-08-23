//! Since Guile requires programs embedding it to enter [guile
//! mode](https://www.gnu.org/software/guile/manual/html_node/Initialization.html),
//! wrapper.zig's `main` is the actual entrypoint of our program and it
//! enters guile mode with `scm_with_guile` before calling main.zig's
//! `main` function.

const std = @import("std");
const C = @import("C.zig");

const guile_mode_main = @import("main.zig").main;

pub fn main() anyerror!void {
    _ = C.scm_with_guile(innerMain, null);
}

fn innerMain(_: ?*anyopaque) callconv(.C) ?*anyopaque {
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
