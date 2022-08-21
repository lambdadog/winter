const std = @import("std");
const wlr = @import("wlroots");

const C = @import("C.zig");

const Server = @import("Server.zig");

fn scm_init() void {
    Server.scm_init();
    // Output.scmInit();
    // View.scmInit();

    // _ = C.scm_c_primitive_load("./scheme/init.scm");
}

pub fn main() anyerror!void {
    wlr.log.init(.debug);

    scm_init();

    _ = C.scm_c_primitive_load("./scheme/loadup.scm");
    _ = C.scm_c_primitive_load("./scheme/startup.scm");
}
