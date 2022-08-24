const std = @import("std");
const os = std.os;

const wl = @import("wayland").server.wl;

const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const C = @import("C.zig");

const ally = std.heap.c_allocator;

const Output = @import("Output.zig");
const View = @import("View.zig");
// const Keyboard = @import("Keyboard.zig");
const Cursor = @import("Cursor.zig");

pub var scm_server_type: C.SCM = undefined;

pub fn scm_init() void {
    _ = C.scm_c_define_module(
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
        "server-outputs",
        1,
        0,
        0,
        @intToPtr(?*anyopaque, @ptrToInt(scm_serverOutputs)),
    );

    _ = C.scm_c_define_gsubr(
        "server-views",
        1,
        0,
        0,
        @intToPtr(?*anyopaque, @ptrToInt(scm_serverViews)),
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
    var scm_exports = C.SCM_EOL;
    for ([_][:0]const u8{
        "make-server",
        "server-outputs",
        "server-views",
        "server-socket",
        "run-server",
    }) |symbol_name| {
        scm_exports = C.scm_cons(
            C.scm_from_utf8_symbol(symbol_name.ptr),
            scm_exports,
        );
    }
    _ = C.scm_module_export(
        C.scm_current_module(),
        scm_exports,
    );
}

fn scm_makeServer() callconv(.C) C.SCM {
    const server = Server.create() catch {
        C.scm_error(
            C.scm_misc_error_key,
            "make-server",
            "Failed to create server",
            null,
            C.SCM_BOOL_F,
        );
    };

    return serverToScm(server);
}

fn scm_serverOutputs(scm_server: C.SCM) callconv(.C) C.SCM {
    const server = scmToServer(scm_server);

    var list = C.SCM_EOL;
    var iter = server.outputs.iterator(.reverse);
    while (iter.next()) |output| {
        list = C.scm_cons(
            Output.outputToScm(output),
            list,
        );
    }

    return list;
}

fn scm_serverViews(scm_server: C.SCM) callconv(.C) C.SCM {
    const server = scmToServer(scm_server);

    var list = C.SCM_EOL;
    var iter = server.views.iterator(.reverse);
    while (iter.next()) |view| {
        list = C.scm_cons(
            View.viewToScm(view),
            list,
        );
    }

    return list;
}

fn scm_serverSocket(scm_server: C.SCM) callconv(.C) C.SCM {
    const server = scmToServer(scm_server);

    return C.scm_from_utf8_string(server.socket[0..server.socket.len]);
}

fn scm_runServer(scm_server: C.SCM) callconv(.C) C.SCM {
    const server = scmToServer(scm_server);

    server.backend.start() catch {
        C.scm_error(
            C.scm_misc_error_key,
            "run-server",
            "Failed to start server backend",
            null,
            C.SCM_BOOL_F,
        );
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
    C.scm_assert_foreign_object_type(scm_server_type, scm_server);

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

outputs: wl.list.Head(Output, "link") = undefined,
views: wl.list.Head(View, "link") = undefined,
// keyboards: wl.list.Head(Keyboard, "link") = undefined,
cursor: Cursor = undefined,

new_output_listener: wl.Listener(*wlr.Output),
on_new_output_function: ?C.SCM = null,
new_xdg_surface_listener: wl.Listener(*wlr.XdgSurface),
on_new_view_function: ?C.SCM = null,
new_input_listener: wl.Listener(*wlr.InputDevice),

pub fn create() !*Server {
    const self = try ally.create(Server);
    errdefer ally.destroy(self);

    const wl_server = try wl.Server.create();
    const backend = try wlr.Backend.autocreate(wl_server);
    const renderer = try wlr.Renderer.autocreate(backend);

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
        .new_xdg_surface_listener = wl.Listener(*wlr.XdgSurface).init(
            onNewXdgSurface,
        ),
        .new_input_listener = wl.Listener(*wlr.InputDevice).init(
            onNewInput,
        ),
    };

    // Copy the socket name into our server struct so it isn't
    // destroyed with our stack.
    for (socket[0..socket.len]) |b, i| self.socket[i] = b;

    try renderer.initServer(wl_server);
    try self.scene.attachOutputLayout(self.output_layout);

    _ = try wlr.Compositor.create(self.wl_server, self.renderer);
    _ = try wlr.DataDeviceManager.create(self.wl_server);

    self.backend.events.new_output.add(&self.new_output_listener);
    self.xdg_shell.events.new_surface.add(&self.new_xdg_surface_listener);
    self.backend.events.new_input.add(&self.new_input_listener);

    self.outputs.init();
    self.views.init();
    // self.keyboards.init();
    try self.cursor.init(self);

    return self;
}

pub fn destroy(self: *Server) void {
    self.wl_server.destroyClients();
    self.wl_server.destroy();

    ally.destroy(self);
}

pub fn bindScmFunction(
    self: *Server,
    scm_event_symbol: C.SCM,
    scm_procedure: C.SCM,
) C.SCM {
    inline for ([_][2][:0]const u8{
        // symbol name   field name
        .{ "new-output", "on_new_output_function" },
        .{ "new-view", "on_new_view_function" },
    }) |event| {
        if (C.SCM_BOOL_T == C.scm_eqv_p(
            scm_event_symbol,
            C.scm_from_utf8_symbol(event[0].ptr),
        )) {
            if (@field(self, event[1])) |scm_fn| {
                _ = C.scm_gc_unprotect_object(scm_fn);
            }
            @field(self, event[1]) = C.scm_gc_protect_object(
                scm_procedure,
            );
            return scm_procedure;
        }
    }
    // else:
    return C.SCM_BOOL_F;
}

pub const ViewAtResult = struct {
    view: *View,
    surface: *wlr.Surface,
    relative_x: f64,
    relative_y: f64,
};

pub fn viewAt(self: *Server, absolute_x: f64, absolute_y: f64) ?ViewAtResult {
    var relative_y: f64 = undefined;
    var relative_x: f64 = undefined;

    if (self.scene.node.at(
        absolute_x,
        absolute_y,
        &relative_x,
        &relative_y,
    )) |node| {
        if (node.type != .surface) return null;
        const surface = wlr.SceneSurface.fromNode(node).surface;

        var it: ?*wlr.SceneNode = node;
        while (it) |n| : (it = n.parent) {
            if (@intToPtr(?*View, n.data)) |view| {
                return ViewAtResult{
                    .view = view,
                    .surface = surface,
                    .relative_x = relative_x,
                    .relative_y = relative_y,
                };
            }
        }
    }

    return null;
}

fn onNewOutput(
    listener: *wl.Listener(*wlr.Output),
    wlr_output: *wlr.Output,
) void {
    const self = @fieldParentPtr(Server, "new_output_listener", listener);

    if (!wlr_output.initRender(self.allocator, self.renderer)) {
        std.log.err("Failed to init renderer for output.", .{});
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

    //_ = try self.cursor.cursor_mgr.load(wlr_output.scale);

    const output = Output.create(self, wlr_output) catch |err| {
        std.log.err("Failed to create output:\n{}", .{err});
        if (@errorReturnTrace()) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
        return;
    };

    self.outputs.prepend(output);
    self.output_layout.addAuto(wlr_output);

    // FIXME: handle guile errors so a scheme error doesn't cause a
    // crash.
    if (self.on_new_output_function) |scm_fn| {
        _ = C.scm_call_2(
            scm_fn,
            serverToScm(self),
            Output.outputToScm(output),
        );
    }
}

fn onNewXdgSurface(
    listener: *wl.Listener(*wlr.XdgSurface),
    xdg_surface: *wlr.XdgSurface,
) void {
    const self = @fieldParentPtr(Server, "new_xdg_surface_listener", listener);

    switch (xdg_surface.role) {
        .toplevel => {
            const view = View.create(self, xdg_surface) catch |err| {
                std.log.err("Failed to create view:\n{}", .{err});
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace.*);
                }
                return;
            };

            self.views.prepend(view);

            // FIXME: handle guile errors so a scheme error doesn't
            // cause a crash.
            if (self.on_new_view_function) |scm_fn| {
                _ = C.scm_call_2(
                    scm_fn,
                    serverToScm(self),
                    View.viewToScm(view),
                );
            }
        },
        .popup => {
            // Since we only support XDG shell this is a safe assert
            const parent = wlr.XdgSurface.fromWlrSurface(
                xdg_surface.role_data.popup.parent.?,
            );
            const parent_node = @intToPtr(
                ?*wlr.SceneNode,
                parent.data,
            ) orelse return;
            const scene_node = parent_node.createSceneXdgSurface(
                xdg_surface,
            ) catch |err| {
                std.log.err("Failed to allocate XDG popup node:\n{}", .{err});
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace.*);
                }
                return;
            };
            xdg_surface.data = @ptrToInt(scene_node);
        },
        .none => unreachable,
    }
}

fn onNewInput(
    listener: *wl.Listener(*wlr.InputDevice),
    input_device: *wlr.InputDevice,
) void {
    const self = @fieldParentPtr(Server, "new_input_listener", listener);
    switch (input_device.type) {
        .pointer => self.cursor.attachInputDevice(input_device),
        else => {},
    }

    self.seat.setCapabilities(.{
        .pointer = true,
        .keyboard = false,
    });
}
