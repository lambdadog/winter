const std = @import("std");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const C = @import("C.zig");

const ally = std.heap.c_allocator;

const Server = @import("Server.zig");

var scm_view_type: C.SCM = undefined;

var scm_view_on_map_hook: C.SCM = undefined;
var scm_view_on_unmap_hook: C.SCM = undefined;
var scm_view_on_destroy_hook: C.SCM = undefined;

pub fn scmInit() void {
    scm_view_type = C.scm_make_foreign_object_type(
        C.scm_from_utf8_symbol("view"),
        C.scm_list_1(
            C.scm_from_utf8_symbol("ptr"),
        ),
        null,
    );

    scm_view_on_map_hook = C.scm_make_hook(C.scm_from_uint(1));
    _ = C.scm_c_define("view-on-map-hook", scm_view_on_map_hook);
    scm_view_on_unmap_hook = C.scm_make_hook(C.scm_from_uint(1));
    _ = C.scm_c_define("view-on-unmap-hook", scm_view_on_unmap_hook);
    scm_view_on_destroy_hook = C.scm_make_hook(C.scm_from_uint(1));
    _ = C.scm_c_define("view-on-destroy-hook", scm_view_on_destroy_hook);

    _ = C.scm_c_define_gsubr(
        "views",
        0,
        0,
        0,
        @intToPtr(?*anyopaque, @ptrToInt(scm_views)),
    );

    _ = C.scm_c_define_gsubr(
        "enable-view!",
        1,
        0,
        0,
        @intToPtr(?*anyopaque, @ptrToInt(scm_enable_view_x)),
    );

    _ = C.scm_c_define_gsubr(
        "disable-view!",
        1,
        0,
        0,
        @intToPtr(?*anyopaque, @ptrToInt(scm_disable_view_x)),
    );
}

pub fn makeScmView(view: *View) C.SCM {
    return C.scm_make_foreign_object_1(
        scm_view_type,
        view,
    );
}

pub fn getViewFromScm(scm_view: C.SCM) *View {
    return @ptrCast(
        *View,
        @alignCast(@alignOf(*View), C.scm_foreign_object_ref(scm_view, 0).?),
    );
}

fn scm_views() callconv(.C) C.SCM {
    const server = Server.getServer();

    var iter = server.views.iterator(.forward);
    var list: C.SCM = C.scm_make_list(
        C.scm_from_uint(@truncate(c_uint, server.views.length())),
        null,
    );
    var index: C.SCM = C.scm_from_int(0);
    while (iter.next()) |view| {
        _ = C.scm_list_set_x(
            list,
            index,
            makeScmView(view),
        );
        index = C.scm_oneplus(index);
    }
    return list;
}

fn scm_enable_view_x(scm_view: C.SCM) callconv(.C) C.SCM {
    const view = getViewFromScm(scm_view);
    view.setEnabled(true);
    return scm_view;
}

fn scm_disable_view_x(scm_view: C.SCM) callconv(.C) C.SCM {
    const view = getViewFromScm(scm_view);
    view.setEnabled(false);
    return scm_view;
}

const View = @This(); // {

link: wl.list.Link = undefined,
xdg_surface: *wlr.XdgSurface,
scene_node: *wlr.SceneNode,

mapped: bool = false,

x: i32 = 0,
y: i32 = 0,

map_listener: wl.Listener(*wlr.XdgSurface),
unmap_listener: wl.Listener(*wlr.XdgSurface),
destroy_listener: wl.Listener(*wlr.XdgSurface),

pub fn create(server: *Server, xdg_surface: *wlr.XdgSurface) !*View {
    const self = try ally.create(View);
    errdefer ally.destroy(self);

    self.* = .{
        .xdg_surface = xdg_surface,
        .scene_node = try server.scene.node.createSceneXdgSurface(xdg_surface),

        .map_listener = wl.Listener(*wlr.XdgSurface).init(onMap),
        .unmap_listener = wl.Listener(*wlr.XdgSurface).init(onUnmap),
        .destroy_listener = wl.Listener(*wlr.XdgSurface).init(onDestroy),
    };

    self.scene_node.data = @ptrToInt(self);
    self.xdg_surface.data = @ptrToInt(self.scene_node);

    self.xdg_surface.events.map.add(&self.map_listener);
    self.xdg_surface.events.unmap.add(&self.unmap_listener);
    self.xdg_surface.events.destroy.add(&self.destroy_listener);

    return self;
}

pub fn setEnabled(self: *View, enabled: bool) void {
    self.scene_node.setEnabled(enabled);
}

fn onMap(
    listener: *wl.Listener(*wlr.XdgSurface),
    _: *wlr.XdgSurface,
) void {
    const self = @fieldParentPtr(View, "map_listener", listener);

    self.mapped = true;
    self.setEnabled(false);

    _ = C.scm_run_hook(
        scm_view_on_map_hook,
        C.scm_list_1(
            makeScmView(self),
        ),
    );
}

fn onUnmap(
    listener: *wl.Listener(*wlr.XdgSurface),
    _: *wlr.XdgSurface,
) void {
    const self = @fieldParentPtr(View, "unmap_listener", listener);

    self.mapped = false;

    _ = C.scm_run_hook(
        scm_view_on_unmap_hook,
        C.scm_list_1(
            makeScmView(self),
        ),
    );
}

fn onDestroy(
    listener: *wl.Listener(*wlr.XdgSurface),
    _: *wlr.XdgSurface,
) void {
    const self = @fieldParentPtr(View, "destroy_listener", listener);

    _ = C.scm_run_hook(
        scm_view_on_destroy_hook,
        C.scm_list_1(
            makeScmView(self),
        ),
    );

    self.map_listener.link.remove();
    self.unmap_listener.link.remove();
    self.destroy_listener.link.remove();

    ally.destroy(self);
}

// }
