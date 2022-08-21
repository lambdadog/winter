const std = @import("std");
const os = std.os;

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const C = @import("C.zig");

const ally = std.heap.c_allocator;

const Server = @import("Server.zig");

var scm_output_type: C.SCM = undefined;

pub fn scmInit() void {
    scm_output_type = C.scm_make_foreign_object_type(
        C.scm_from_utf8_symbol("output"),
        C.scm_list_1(
            C.scm_from_utf8_symbol("ptr"),
        ),
        null,
    );

    _ = C.scm_c_define_gsubr(
        "outputs",
        0,
        0,
        0,
        @intToPtr(?*anyopaque, @ptrToInt(scm_outputs)),
    );
}

pub fn makeScmOutput(output: *Output) C.SCM {
    return C.scm_make_foreign_object_1(
        scm_output_type,
        output,
    );
}

fn scm_outputs() callconv(.C) C.SCM {
    const server = Server.getServer();

    var iter = server.outputs.iterator(.forward);
    var list: C.SCM = C.scm_make_list(
        C.scm_from_uint(@truncate(c_uint, server.outputs.length())),
        null,
    );
    var index: C.SCM = C.scm_from_int(0);
    while (iter.next()) |output| {
        _ = C.scm_list_set_x(
            list,
            index,
            makeScmOutput(output),
        );
        index = C.scm_oneplus(index);
    }
    return list;
}

const Output = @This(); // {

link: wl.list.Link = undefined,
wlr_output: *wlr.Output,

frame_listener: wl.Listener(*wlr.Output),
destroy_listener: wl.Listener(*wlr.Output),

pub fn create(_: *Server, wlr_output: *wlr.Output) !*Output {
    const self = try ally.create(Output);
    errdefer ally.destroy(self);

    self.* = .{
        .wlr_output = wlr_output,

        // listeners
        .frame_listener = wl.Listener(*wlr.Output).init(onFrame),
        .destroy_listener = wl.Listener(*wlr.Output).init(onDestroy),
    };

    wlr_output.events.frame.add(&self.frame_listener);
    wlr_output.events.destroy.add(&self.destroy_listener);

    return self;
}

fn onFrame(
    listener: *wl.Listener(*wlr.Output),
    _: *wlr.Output,
) void {
    const self = @fieldParentPtr(Output, "frame_listener", listener);

    const scene_output = Server.getServer().scene.getSceneOutput(self.wlr_output).?;
    _ = scene_output.commit();

    var now: os.timespec = undefined;
    std.os.clock_gettime(std.os.CLOCK.MONOTONIC, &now) catch {
        @panic("CLOCK_MONOTONIC not supported");
    };
    scene_output.sendFrameDone(&now);
}

fn onDestroy(
    listener: *wl.Listener(*wlr.Output),
    _: *wlr.Output,
) void {
    const self = @fieldParentPtr(Output, "destroy_listener", listener);

    self.frame_listener.link.remove();
    self.destroy_listener.link.remove();

    ally.destroy(self);
}

// }
