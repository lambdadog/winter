const std = @import("std");
const wlr = @import("wlroots");

const C = @import("C.zig");

const Server = @import("Server.zig");
const Output = @import("Output.zig");
const View = @import("View.zig");

const ally = std.heap.c_allocator;

fn scm_init() void {
    _ = C.scm_c_define_module(
        "wl internal",
        scm_initModule,
        null,
    );

    Server.scm_init();
    Output.scm_init();
    View.scm_init();
}

fn scm_initModule(_: ?*anyopaque) callconv(.C) void {
    _ = C.scm_c_define_gsubr(
        "bind!",
        3,
        0,
        0,
        @intToPtr(?*anyopaque, @ptrToInt(scm_bindX)),
    );

    _ = C.scm_module_export(
        C.scm_current_module(),
        C.scm_list_1(
            C.scm_from_utf8_symbol("bind!"),
        ),
    );
}

fn scm_bindX(
    scm_wl_object: C.SCM,
    scm_event_symbol: C.SCM,
    scm_procedure: C.SCM,
) C.SCM {
    if (C.scm_is_a_p(scm_wl_object, Server.scm_server_type)) {
        return Server.scmToServer(scm_wl_object).bindScmFunction(
            scm_event_symbol,
            scm_procedure,
        );
    }
    if (C.scm_is_a_p(scm_wl_object, Output.scm_output_type)) {
        return Output.scmToOutput(scm_wl_object).bindScmFunction(
            scm_event_symbol,
            scm_procedure,
        );
    }
    if (C.scm_is_a_p(scm_wl_object, View.scm_view_type)) {
        return View.scmToView(scm_wl_object).bindScmFunction(
            scm_event_symbol,
            scm_procedure,
        );
    }

    // no match
    return C.SCM_BOOL_F;
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

    // We want an error if this fails to load, so we don't use a
    // handler.
    _ = C.scm_c_primitive_load("./scheme/startup.scm");
}
