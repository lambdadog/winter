const std = @import("std");
const os = std.os;

const wl = @import("wayland").server.wl;

const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const C = @import("C.zig");

const ally = std.heap.c_allocator;

const Output = @import("Output.zig");
const View = @import("View.zig");
//const Keyboard = @import("Keyboard.zig");
//const Cursor = @import("Cursor.zig");

// needs to be a global variable so scheme can access it.
var server: Server = undefined;

pub fn getServer() *Server {
    return &server;
}

pub fn scmInit() void {
    _ = C.scm_c_define_gsubr(
        "focus-view!",
        1,
        0,
        0,
        @intToPtr(?*anyopaque, @ptrToInt(scm_focus_view_x)),
    );
}

fn scm_focus_view_x(scm_view: C.SCM) callconv(.C) C.SCM {
    const view = View.getViewFromScm(scm_view);
    getServer().focusView(view);
    return scm_view;
}

const Server = @This(); // {

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
//keyboards: wl.list.Head(Keyboard, "link") = undefined,

//cursor: Cursor = undefined,

new_output_listener: wl.Listener(*wlr.Output),
new_xdg_surface_listener: wl.Listener(*wlr.XdgSurface),
new_input_device_listener: wl.Listener(*wlr.InputDevice),

pub fn create() !*Server {
    const self = getServer();

    const wl_server = try wl.Server.create();
    const backend = try wlr.Backend.autocreate(wl_server);
    const renderer = try wlr.Renderer.autocreate(backend);

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
        .new_input_device_listener = wl.Listener(*wlr.InputDevice).init(
            onNewInputDevice,
        ),
    };

    try self.renderer.initServer(wl_server);
    try self.scene.attachOutputLayout(server.output_layout);

    _ = try wlr.Compositor.create(self.wl_server, self.renderer);
    _ = try wlr.DataDeviceManager.create(self.wl_server);

    self.backend.events.new_output.add(&self.new_output_listener);
    self.xdg_shell.events.new_surface.add(&self.new_xdg_surface_listener);
    self.backend.events.new_input.add(&self.new_input_device_listener);

    self.outputs.init();
    self.views.init();
    //self.keyboards.init();

    //self.cursor.init(self.seat);

    return self;
}

pub fn destroy(self: *Server) void {
    self.wl_server.destroyClients();
    self.wl_server.destroy();
}

pub fn focusView(self: *Server, view: *View) void {
    if (self.seat.keyboard_state.focused_surface) |previous_surface| {
        if (previous_surface == view.xdg_surface.surface) return;
        if (previous_surface.isXdgSurface()) {
            const xdg_surface = wlr.XdgSurface.fromWlrSurface(previous_surface);
            _ = xdg_surface.role_data.toplevel.setActivated(false);
        }
    }

    view.scene_node.raiseToTop();
    view.link.remove();
    self.views.prepend(view);

    _ = view.xdg_surface.role_data.toplevel.setActivated(true);

    const wlr_keyboard = server.seat.getKeyboard() orelse return;
    self.seat.keyboardNotifyEnter(
        view.xdg_surface.surface,
        &wlr_keyboard.keycodes,
        wlr_keyboard.num_keycodes,
        &wlr_keyboard.modifiers,
    );
}

fn onNewOutput(
    listener: *wl.Listener(*wlr.Output),
    wlr_output: *wlr.Output,
) void {
    const self = @fieldParentPtr(Server, "new_output_listener", listener);

    if (!wlr_output.initRender(self.allocator, self.renderer)) {
        std.log.err("Failed to init renderer for output!", .{});
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

    const output = Output.create(self, wlr_output) catch |err| {
        std.log.err("Failed to create output:\n{}", .{err});
        if (@errorReturnTrace()) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
        return;
    };

    self.outputs.prepend(output);

    self.output_layout.addAuto(wlr_output);
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
        },
        // We should probably figure out how to plug this into Scheme
        // somehow. I need to learn more about the XDG shell protocol
        // first though.
        .popup => {
            // Since we don't support anything else that can make XDG
            // popups, this is okay.
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

fn onNewInputDevice(
    listener: *wl.Listener(*wlr.InputDevice),
    input_device: *wlr.InputDevice,
) void {
    const self = @fieldParentPtr(Server, "new_input_device_listener", listener);
    _ = self;
    _ = input_device;
    // switch (input_device.type) {
    //     .keyboard => Keyboard.create(self, input_device) catch |err| {
    //         std.log.err("Failed to create keyboard:\n{}", .{err});
    //         if (@errorReturnTrace()) |trace| {
    //             std.debug.dumpStackTrace(trace.*);
    //         }
    //         return;
    //     },
    //     .pointer => self.cursor.attachInputDevice(input_device),
    //     else => std.log.err("Unsupported input device type: {}", .{
    //         input_device.type,
    //     }),
    // }
}

// }
