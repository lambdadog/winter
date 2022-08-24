const std = @import("std");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const C = @import("C.zig");

const ally = std.heap.c_allocator;

const Server = @import("Server.zig");

pub var scm_view_type: C.SCM = undefined;

pub fn scm_init() void {
    _ = C.scm_c_define_module(
        "wl view internal",
        scm_initModule,
        null,
    );
}

fn scm_initModule(_: ?*anyopaque) callconv(.C) void {
    scm_view_type = C.scm_make_foreign_object_type(
        C.scm_from_utf8_symbol("view"),
        C.scm_list_1(
            C.scm_from_utf8_symbol("ptr"),
        ),
        // All resources but the server are managed by wayland.
        null,
    );

    _ = C.scm_c_define_gsubr(
        "view-enable!",
        1,
        0,
        0,
        @intToPtr(?*anyopaque, @ptrToInt(scm_viewEnableX)),
    );

    _ = C.scm_c_define_gsubr(
        "view-disable!",
        1,
        0,
        0,
        @intToPtr(?*anyopaque, @ptrToInt(scm_viewDisableX)),
    );

    _ = C.scm_module_export(
        C.scm_current_module(),
        C.scm_list_2(
            C.scm_from_utf8_symbol("view-enable!"),
            C.scm_from_utf8_symbol("view-disable!"),
        ),
    );
}

fn scm_viewEnableX(scm_view: C.SCM) callconv(.C) C.SCM {
    const view = scmToView(scm_view);

    view.setEnabled(true);
    return scm_view;
}

fn scm_viewDisableX(scm_view: C.SCM) callconv(.C) C.SCM {
    const view = scmToView(scm_view);

    view.setEnabled(false);
    return scm_view;
}

pub fn viewToScm(view: *View) C.SCM {
    return C.scm_make_foreign_object_1(
        scm_view_type,
        view,
    );
}

pub fn scmToView(scm_view: C.SCM) *View {
    C.scm_assert_foreign_object_type(scm_view_type, scm_view);

    return @ptrCast(
        *View,
        @alignCast(
            @alignOf(*View),
            C.scm_foreign_object_ref(scm_view, 0).?,
        ),
    );
}

const View = @This(); // {

server: *Server,

link: wl.list.Link = undefined,
xdg_surface: *wlr.XdgSurface,
scene_node: *wlr.SceneNode,

mapped: bool = false,
x: i32 = 0,
y: i32 = 0,

map_listener: wl.Listener(*wlr.XdgSurface),
on_map_function: ?C.SCM = null,
unmap_listener: wl.Listener(*wlr.XdgSurface),
on_unmap_function: ?C.SCM = null,
destroy_listener: wl.Listener(*wlr.XdgSurface),
on_destroy_function: ?C.SCM = null,

pub fn create(server: *Server, xdg_surface: *wlr.XdgSurface) !*View {
    const self = try ally.create(View);
    errdefer ally.destroy(self);

    self.* = .{
        .server = server,

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

pub fn bindScmFunction(
    self: *View,
    scm_event_symbol: C.SCM,
    scm_procedure: C.SCM,
) C.SCM {
    inline for ([_][2][:0]const u8{
        // symbol name   field name
        .{ "map", "on_map_function" },
        .{ "unmap", "on_unmap_function" },
        .{ "destroy", "on_destroy_function" },
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

pub fn setEnabled(self: *View, enabled: bool) void {
    self.scene_node.setEnabled(enabled);
}

fn onMap(
    listener: *wl.Listener(*wlr.XdgSurface),
    xdg_surface: *wlr.XdgSurface,
) void {
    const self = @fieldParentPtr(View, "map_listener", listener);

    self.mapped = true;
    self.setEnabled(false);

    // FIXME: handle guile errors so a scheme error doesn't cause a
    // crash.
    if (self.on_map_function) |scm_fn| {
        _ = C.scm_call_1(
            scm_fn,
            viewToScm(self),
        );
    }

    // temporary
    //   focus
    if (self.server.seat.keyboard_state.focused_surface) |previous_surface| {
        if (previous_surface == xdg_surface.surface) return;
        if (previous_surface.isXdgSurface()) {
            const prev_xdg_surface = wlr.XdgSurface.fromWlrSurface(previous_surface);
            _ = prev_xdg_surface.role_data.toplevel.setActivated(false);
        }
    }
    self.scene_node.raiseToTop();
    _ = xdg_surface.role_data.toplevel.setActivated(true);
}

fn onUnmap(
    listener: *wl.Listener(*wlr.XdgSurface),
    _: *wlr.XdgSurface,
) void {
    const self = @fieldParentPtr(View, "unmap_listener", listener);

    self.mapped = false;

    // FIXME: handle guile errors so a scheme error doesn't cause a
    // crash.
    if (self.on_unmap_function) |scm_fn| {
        _ = C.scm_call_1(
            scm_fn,
            viewToScm(self),
        );
    }
}

fn onDestroy(
    listener: *wl.Listener(*wlr.XdgSurface),
    _: *wlr.XdgSurface,
) void {
    const self = @fieldParentPtr(View, "destroy_listener", listener);

    // FIXME: handle guile errors so a scheme error doesn't cause a
    // crash.
    if (self.on_destroy_function) |scm_fn| {
        _ = C.scm_call_1(
            scm_fn,
            viewToScm(self),
        );
    }

    self.map_listener.link.remove();
    self.unmap_listener.link.remove();
    self.destroy_listener.link.remove();

    self.link.remove();

    ally.destroy(self);
}

// }
