const std = @import("std");
const os = std.os;

const wl = @import("wayland").server.wl;

const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const C = @import("C.zig");

const ally = std.heap.c_allocator;

// const Output = @import("Output.zig");
// const View = @import("View.zig");
// const Keyboard = @import("Keyboard.zig");
// const Cursor = @import("Cursor.zig");

var scm_module: C.SCM = undefined;
var scm_server_type: C.SCM = undefined;

pub fn scm_init() void {
    std.log.info("Setting up (winter server internal)", .{});
    scm_module = C.scm_c_define_module(
        "wl server internal",
        scm_initModule,
        null,
    );
}

fn scm_initModule(_: ?*anyopaque) callconv(.C) void {
    scm_server_type = C.scm_make_foreign_object_type(
        C.scm_from_utf8_symbol("server"),
        C.scm_list_1(
            C.scm_from_utf8_symbol("ptr"),
        ),
        finalizeServer,
    );

    _ = C.scm_c_define_gsubr(
        "make-server",
        0,
        0,
        0,
        @intToPtr(?*anyopaque, @ptrToInt(scm_makeServer)),
    );

    _ = C.scm_c_define_gsubr(
        "server-socket",
        1,
        0,
        0,
        @intToPtr(?*anyopaque, @ptrToInt(scm_serverSocket)),
    );

    _ = C.scm_c_define_gsubr(
        "run-server",
        1,
        0,
        0,
        @intToPtr(?*anyopaque, @ptrToInt(scm_runServer)),
    );

    // scm_c_export is broken with @cImport so we use
    // scm_module_export instead.
    _ = C.scm_module_export(
        C.scm_current_module(),
        C.scm_list_3(
            C.scm_from_utf8_symbol("make-server"),
            C.scm_from_utf8_symbol("server-socket"),
            C.scm_from_utf8_symbol("run-server"),
        ),
    );
}

fn scm_makeServer() callconv(.C) C.SCM {
    const server = Server.create() catch {
        // will error
        return null;
    };

    return serverToScm(server);
}

fn scm_serverSocket(scm_server: C.SCM) callconv(.C) C.SCM {
    const server = scmToServer(scm_server);

    return C.scm_from_utf8_string(server.socket[0..server.socket.len]);
}

fn scm_runServer(scm_server: C.SCM) callconv(.C) C.SCM {
    const server = scmToServer(scm_server);

    server.backend.start() catch {
        // will error
        return null;
    };

    server.wl_server.run();

    return scm_server;
}

fn finalizeServer(scm_server: C.SCM) callconv(.C) void {
    const server = scmToServer(scm_server);
    server.destroy();
}

pub fn serverToScm(server: *Server) C.SCM {
    return C.scm_make_foreign_object_1(
        scm_server_type,
        server,
    );
}

pub fn scmToServer(scm_server: C.SCM) *Server {
    return @ptrCast(
        *Server,
        @alignCast(
            @alignOf(*Server),
            C.scm_foreign_object_ref(scm_server, 0).?,
        ),
    );
}

const Server = @This(); // {

// Filled with 0s since guile likes null terminated strings
socket: [11]u8 = [11]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },

wl_server: *wl.Server,
backend: *wlr.Backend,
renderer: *wlr.Renderer,
allocator: *wlr.Allocator,
scene: *wlr.Scene,

output_layout: *wlr.OutputLayout,
xdg_shell: *wlr.XdgShell,
seat: *wlr.Seat,

// outputs: wl.list.Head(Output, "link") = undefined,
// views: wl.list.Head(View, "link") = undefined,
// keyboards: wl.list.Head(Keyboard, "link") = undefined,
// cursor: Cursor = undefined,

new_output_listener: wl.Listener(*wlr.Output),
// new_xdg_surface_listener: wl.Listener(*wlr.XdgSurface),
// new_input_device_listener: wl.Listener(*wlr.InputDevice),

pub fn create() !*Server {
    const self = try ally.create(Server);
    errdefer ally.destroy(self);

    const wl_server = try wl.Server.create();
    const backend = try wlr.Backend.autocreate(wl_server);
    const renderer = try wlr.Renderer.autocreate(backend);

    // roundabout so I don't have to deal with deallocation
    var buf: [11]u8 = undefined;
    const socket = try wl_server.addSocketAuto(&buf);

    self.* = .{
        .wl_server = wl_server,
        .backend = backend,
        .renderer = renderer,
        .allocator = try wlr.Allocator.autocreate(backend, renderer),
        .scene = try wlr.Scene.create(),

        .output_layout = try wlr.OutputLayout.create(),
        .xdg_shell = try wlr.XdgShell.create(wl_server),
        .seat = try wlr.Seat.create(wl_server, "default"),

        //listeners
        .new_output_listener = wl.Listener(*wlr.Output).init(
            onNewOutput,
        ),
        // .new_xdg_surface_listener = wl.Listener(*wlr.XdgSurface).init(
        //     onNewXdgSurface,
        // ),
        // .new_input_device_listener = wl.Listener(*wlr.InputDevice).init(
        //     onNewInputDevice,
        // ),
    };

    for (socket[0..socket.len]) |b, i| self.socket[i] = b;

    try renderer.initServer(wl_server);
    try self.scene.attachOutputLayout(self.output_layout);

    _ = try wlr.Compositor.create(self.wl_server, self.renderer);
    _ = try wlr.DataDeviceManager.create(self.wl_server);

    self.backend.events.new_output.add(&self.new_output_listener);
    // self.xdg_shell.events.new_surface.add(&self.new_xdg_surface_listener);
    // self.backend.events.new_input.add(&self.new_input_device_listener);

    // self.outputs.init();
    // self.views.init();
    // self.keyboards.init();
    // self.cursor.init(self.seat);

    return self;
}

pub fn destroy(self: *Server) void {
    self.wl_server.destroyClients();
    self.wl_server.destroy();

    ally.destroy(self);
}

fn onNewOutput(
    listener: *wl.Listener(*wlr.Output),
    wlr_output: *wlr.Output,
) void {
    const self = @fieldParentPtr(Server, "new_output_listener", listener);

    if (!wlr_output.initRender(self.allocator, self.renderer)) {
        std.log.err("Failed to init renderer for output.", .{});
        if (@errorReturnTrace()) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
        return;
    }

    if (wlr_output.preferredMode()) |mode| {
        wlr_output.setMode(mode);
        wlr_output.enable(true);
        wlr_output.commit() catch |err| {
            std.log.err("Failed to set output mode:\n{}", .{err});
            if (@errorReturnTrace()) |trace| {
                std.debug.dumpStackTrace(trace.*);
            }
            return;
        };
    }

    // onst output = Output.create(self, wlr_output) catch |err| {
    //     std.log.err("Failed to create output:\n{}", .{err});
    //     if (@errorReturnTrace()) |trace| {
    //         std.debug.dumpStackTrace(trace.*);
    //     }
    //     return;
    // };

    // self.outputs.prepend(output);
    self.output_layout.addAuto(wlr_output);
}
