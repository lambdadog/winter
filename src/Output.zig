const std = @import("std");
const os = std.os;

const wl = @import("wayland").server.wl;

const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const C = @import("C.zig");

const ally = std.heap.c_allocator;

const Server = @import("Server.zig");

var scm_output_type: C.SCM = undefined;

pub fn scm_init() void {
    _ = C.scm_c_define_module(
        "winter output internal",
        scm_initModule,
        null,
    );
}

fn scm_initModule(_: ?*anyopaque) callconv(.C) void {
    scm_output_type = C.scm_make_foreign_object_type(
        C.scm_from_utf8_symbol("output"),
        C.scm_list_1(
            C.scm_from_utf8_symbol("ptr"),
        ),
        // All resources but the server are managed by wayland.
        null,
    );
}

pub fn outputToScm(output: *Output) C.SCM {
    return C.scm_make_foreign_object_1(
        scm_output_type,
        output,
    );
}

pub fn scmToOutput(scm_output: C.SCM) *Output {
    return @ptrCast(
        *Output,
        @alignCast(
            @alignOf(*Output),
            C.scm_foreign_object_ref(scm_output, 0).?,
        ),
    );
}

const Output = @This(); // {

server: *Server,

link: wl.list.Link = undefined,
wlr_output: *wlr.Output,

frame_listener: wl.Listener(*wlr.Output),
destroy_listener: wl.Listener(*wlr.Output),

pub fn create(server: *Server, wlr_output: *wlr.Output) !*Output {
    const self = try ally.create(Output);
    errdefer ally.destroy(self);

    self.* = .{
        .server = server,

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
    wlr_output: *wlr.Output,
) void {
    const self = @fieldParentPtr(Output, "frame_listener", listener);

    const scene_output = self.server.scene.getSceneOutput(wlr_output).?;
    _ = scene_output.commit();

    var now: os.timespec = undefined;
    os.clock_gettime(os.CLOCK.MONOTONIC, &now) catch {
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

    self.link.remove();

    ally.destroy(self);
}
