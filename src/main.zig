const std = @import("std");

const wl = @import("wayland").server.wl;

const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const C = @cImport({
    @cInclude("libguile.h");
});

const ally = std.heap.c_allocator;

// Are global for scheme binding purposes
var server: Server = undefined;
var scheme: Scheme = undefined;

// Thanks to wrapper.zig, we start in guile mode.
pub fn main() anyerror!void {
    wlr.log.init(.debug);

    scheme.init();

    try server.init();
    defer server.deinit();

    var buf: [11]u8 = undefined;
    const socket = try server.wl_server.addSocketAuto(&buf);

    try server.backend.start();

    Scheme.load();

    std.log.info("Running compositor on WAYLAND_DISPLAY={s}", .{socket});
    server.wl_server.run();
}

const Scheme = struct {
    view_type: C.SCM,
    output_type: C.SCM,

    view_map_hooks: C.SCM,

    fn init(self: *Scheme) void {
        self.* = .{
            .view_type = C.scm_make_foreign_object_type(
                C.scm_from_utf8_symbol("view"),
                C.scm_list_1(
                    C.scm_from_utf8_symbol("ptr"),
                ),
                null,
            ),
            .output_type = C.scm_make_foreign_object_type(
                C.scm_from_utf8_symbol("output"),
                C.scm_list_1(
                    C.scm_from_utf8_symbol("ptr"),
                ),
                null,
            ),

            .view_map_hooks = C.scm_make_hook(C.scm_from_uint(1)),
        };

        _ = C.scm_c_define("view-map-hooks", self.view_map_hooks);

        _ = C.scm_c_define_gsubr(
            "views",
            0,
            0,
            0,
            @intToPtr(?*anyopaque, @ptrToInt(views)),
        );

        _ = C.scm_c_define_gsubr(
            "view-enable!",
            1,
            0,
            0,
            @intToPtr(?*anyopaque, @ptrToInt(viewEnable)),
        );

        _ = C.scm_c_define_gsubr(
            "view-disable!",
            1,
            0,
            0,
            @intToPtr(?*anyopaque, @ptrToInt(viewDisable)),
        );

        _ = C.scm_c_define_gsubr(
            "view-focus!",
            1,
            0,
            0,
            @intToPtr(?*anyopaque, @ptrToInt(viewFocus)),
        );

        _ = C.scm_c_define_gsubr(
            "view-name",
            1,
            0,
            0,
            @intToPtr(?*anyopaque, @ptrToInt(viewName)),
        );
    }

    fn load() void {
        _ = C.scm_c_primitive_load("./scheme/init.scm");
    }

    fn viewEnable(view_scm: C.SCM) callconv(.C) C.SCM {
        var view = @ptrCast(
            *View,
            @alignCast(@alignOf(*View), C.scm_foreign_object_ref(view_scm, 0).?),
        );
        view.setEnabled(true);
        return view_scm;
    }

    fn viewDisable(view_scm: C.SCM) callconv(.C) C.SCM {
        var view = @ptrCast(
            *View,
            @alignCast(@alignOf(*View), C.scm_foreign_object_ref(view_scm, 0).?),
        );
        view.setEnabled(false);
        return view_scm;
    }

    fn viewFocus(view_scm: C.SCM) callconv(.C) C.SCM {
        var view = @ptrCast(
            *View,
            @alignCast(@alignOf(*View), C.scm_foreign_object_ref(view_scm, 0).?),
        );
        server.focusView(view);
        return view_scm;
    }

    fn viewName(view_scm: C.SCM) callconv(.C) C.SCM {
        var view = @ptrCast(
            *View,
            @alignCast(@alignOf(*View), C.scm_foreign_object_ref(view_scm, 0).?),
        );
        return C.scm_from_utf8_string(
            @ptrCast([*c]const u8, view.xdg_surface.role_data.toplevel.title.?),
        );
    }

    // scm_cons uses scm_cell which translates brokenly, so we use the
    // scm_make_list and scm_list_set_x instead.
    fn views() callconv(.C) C.SCM {
        var iter = server.views.iterator(.forward);
        var index: c_uint = 0;
        var list: C.SCM = C.scm_make_list(
            C.scm_from_uint(@truncate(c_uint, server.views.length())),
            null,
        );
        while (iter.next()) |view| {
            _ = C.scm_list_set_x(
                list,
                C.scm_from_uint(index),
                Scheme.makeView(view),
            );
            index += 1;
        }
        return list;
    }

    fn makeView(view: *View) C.SCM {
        return C.scm_make_foreign_object_1(
            scheme.view_type,
            view,
        );
    }
};

// TODO: no input yet
const Server = struct {
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

    new_output_listener: wl.Listener(*wlr.Output),
    new_xdg_surface_listener: wl.Listener(*wlr.XdgSurface),

    fn init(self: *Server) !void {
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

            .new_output_listener = wl.Listener(*wlr.Output).init(onNewOutput),
            .new_xdg_surface_listener = wl.Listener(*wlr.XdgSurface).init(onNewXdgSurface),
        };

        try self.renderer.initServer(self.wl_server);
        try self.scene.attachOutputLayout(self.output_layout);

        _ = try wlr.Compositor.create(self.wl_server, self.renderer);
        _ = try wlr.DataDeviceManager.create(self.wl_server);

        self.backend.events.new_output.add(&self.new_output_listener);
        self.outputs.init();

        self.xdg_shell.events.new_surface.add(&self.new_xdg_surface_listener);
        self.views.init();
    }

    fn deinit(self: *Server) void {
        self.wl_server.destroyClients();
        self.wl_server.destroy();
    }

    fn focusView(self: *Server, view: *View) void {
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

        const wlr_keyboard = self.seat.getKeyboard() orelse return;
        self.seat.keyboardNotifyEnter(
            view.xdg_surface.surface,
            &wlr_keyboard.keycodes,
            wlr_keyboard.num_keycodes,
            &wlr_keyboard.modifiers,
        );
    }

    // callbacks
    fn onNewOutput(
        listener: *wl.Listener(*wlr.Output),
        wlr_output: *wlr.Output,
    ) void {
        const self = @fieldParentPtr(Server, "new_output_listener", listener);

        if (!wlr_output.initRender(self.allocator, self.renderer)) return;

        if (wlr_output.preferredMode()) |mode| {
            wlr_output.setMode(mode);
            wlr_output.enable(true);
            wlr_output.commit() catch return;
        }

        const output = Output.init(wlr_output) catch {
            std.log.err("Failed to create a new output!", .{});
            return;
        };

        self.outputs.prepend(output);

        self.output_layout.addAuto(wlr_output);
    }

    fn onNewXdgSurface(
        _: *wl.Listener(*wlr.XdgSurface),
        xdg_surface: *wlr.XdgSurface,
    ) void {
        //const self = @fieldParentPtr(Server, "new_xdg_surface_listener", listener);

        switch (xdg_surface.role) {
            .toplevel => {
                _ = View.init(xdg_surface) catch {
                    std.log.err("Failed to create a new view!", .{});
                    return;
                };
            },
            .popup => {
                unreachable;
            },
            .none => {
                // ??
                unreachable;
            },
        }
    }
};

const Output = struct {
    link: wl.list.Link = undefined,
    wlr_output: *wlr.Output,

    frame_listener: wl.Listener(*wlr.Output),
    destroy_listener: wl.Listener(*wlr.Output),

    fn init(wlr_output: *wlr.Output) !*Output {
        var self = try ally.create(Output);

        self.* = .{
            .wlr_output = wlr_output,

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

        const scene_output = server.scene.getSceneOutput(self.wlr_output).?;
        _ = scene_output.commit();

        var now: std.os.timespec = undefined;
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
};

const View = struct {
    link: wl.list.Link = undefined,
    xdg_surface: *wlr.XdgSurface,
    scene_node: *wlr.SceneNode,

    x: i32 = 0,
    y: i32 = 0,

    map_listener: wl.Listener(*wlr.XdgSurface),
    unmap_listener: wl.Listener(*wlr.XdgSurface),
    destroy_listener: wl.Listener(*wlr.XdgSurface),

    request_move_listener: wl.Listener(*wlr.XdgToplevel.event.Move),
    request_resize_listener: wl.Listener(*wlr.XdgToplevel.event.Resize),

    fn init(xdg_surface: *wlr.XdgSurface) !*View {
        var self = try ally.create(View);
        errdefer ally.destroy(self);

        self.* = .{
            .xdg_surface = xdg_surface,
            .scene_node = try server.scene.node.createSceneXdgSurface(xdg_surface),

            .map_listener = wl.Listener(*wlr.XdgSurface).init(onMap),
            .unmap_listener = wl.Listener(*wlr.XdgSurface).init(onUnmap),
            .destroy_listener = wl.Listener(*wlr.XdgSurface).init(onDestroy),

            .request_move_listener = wl.Listener(*wlr.XdgToplevel.event.Move).init(onRequestMove),
            .request_resize_listener = wl.Listener(*wlr.XdgToplevel.event.Resize).init(onRequestResize),
        };

        self.scene_node.data = @ptrToInt(self);
        self.xdg_surface.data = @ptrToInt(self.scene_node);

        self.xdg_surface.events.map.add(&self.map_listener);
        self.xdg_surface.events.unmap.add(&self.unmap_listener);
        self.xdg_surface.events.destroy.add(&self.destroy_listener);

        self.xdg_surface.role_data.toplevel.events.request_move.add(&self.request_move_listener);
        self.xdg_surface.role_data.toplevel.events.request_resize.add(&self.request_resize_listener);

        return self;
    }

    fn setEnabled(self: *View, enabled: bool) void {
        //std.debug.print("{*}.setEnabled: {}\n", .{ self, enabled });
        self.scene_node.setEnabled(enabled);
    }

    // callbacks
    fn onMap(
        listener: *wl.Listener(*wlr.XdgSurface),
        _: *wlr.XdgSurface,
    ) void {
        const self = @fieldParentPtr(View, "map_listener", listener);

        // setEnabled doesn't work until the view is mapped, so we
        // disable now. Views are disabled by default and must be
        // enabled in scheme.
        self.setEnabled(false);
        server.views.prepend(self);

        _ = C.scm_run_hook(scheme.view_map_hooks, C.scm_list_1(Scheme.makeView(self)));
    }

    fn onUnmap(
        listener: *wl.Listener(*wlr.XdgSurface),
        _: *wlr.XdgSurface,
    ) void {
        const self = @fieldParentPtr(View, "unmap_listener", listener);

        self.link.remove();
    }

    fn onDestroy(
        listener: *wl.Listener(*wlr.XdgSurface),
        _: *wlr.XdgSurface,
    ) void {
        const self = @fieldParentPtr(View, "destroy_listener", listener);

        self.map_listener.link.remove();
        self.unmap_listener.link.remove();
        self.destroy_listener.link.remove();
        self.request_move_listener.link.remove();
        self.request_resize_listener.link.remove();

        ally.destroy(self);
    }

    fn onRequestMove(
        listener: *wl.Listener(*wlr.XdgToplevel.event.Move),
        _: *wlr.XdgToplevel.event.Move,
    ) void {
        const self = @fieldParentPtr(View, "request_move_listener", listener);

        _ = self;
    }

    fn onRequestResize(
        listener: *wl.Listener(*wlr.XdgToplevel.event.Resize),
        _: *wlr.XdgToplevel.event.Resize,
    ) void {
        const self = @fieldParentPtr(View, "request_resize_listener", listener);

        _ = self;
    }
};
