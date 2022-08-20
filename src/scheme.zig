const C = @cImport({
    @cInclude("libguile.h");
});

const Server = @import("Server.zig");
const Output = @import("Output.zig");
const View = @import("View.zig");

pub fn init() void {
    Server.scmInit();
    Output.scmInit();
    View.scmInit();

    _ = C.scm_c_primitive_load("./scheme/init.scm");
}
