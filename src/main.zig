const std = @import("std");
const wlr = @import("wlroots");

const C = @import("C.zig");

const Server = @import("Server.zig");
const Output = @import("Output.zig");

const ally = std.heap.c_allocator;

fn scm_init() void {
    Server.scm_init();
    Output.scm_init();
    // View.scmInit();

    // _ = C.scm_c_primitive_load("./scheme/init.scm");
}

pub fn main() anyerror!void {
    wlr.log.init(.info);

    scm_init();

    // For debugging purposes, we use $CWD/scheme/
    const cwd = try std.process.getCwdAlloc(ally);
    defer ally.free(cwd);

    const scm_load_path = C.scm_c_lookup("%load-path");

    _ = C.scm_variable_set_x(
        scm_load_path,
        C.scm_cons(
            C.scm_from_utf8_string(
                try std.fs.path.joinZ(ally, &.{ cwd, "scheme" }),
            ),
            C.scm_variable_ref(scm_load_path),
        ),
    );

    _ = C.scm_c_primitive_load("./scheme/startup.scm");
}
