const std = @import("std");
const Builder = std.build.Builder;
const Pkg = std.build.Pkg;

const ScanProtocolsStep = @import("deps/zig-wayland/build.zig").ScanProtocolsStep;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const scanner = ScanProtocolsStep.create(b);
    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addSystemProtocol("unstable/xdg-output/xdg-output-unstable-v1.xml");
    //scanner.addProtocolPath("protocol/wlr-protocols/unstable/wlr-layer-shell-unstable-v1.xml");

    const wayland = Pkg{
        .name = "wayland",
        .path = .{ .generated = &scanner.result },
    };
    const xkbcommon = Pkg{
        .name = "xkbcommon",
        .path = .{ .path = "deps/zig-xkbcommon/src/xkbcommon.zig" },
    };
    const pixman = Pkg{
        .name = "pixman",
        .path = .{ .path = "deps/zig-pixman/pixman.zig" },
    };
    const wlroots = Pkg{
        .name = "wlroots",
        .path = .{ .path = "deps/zig-wlroots/src/wlroots.zig" },
        .dependencies = &[_]Pkg{ wayland, xkbcommon, pixman },
    };

    const exe = b.addExecutable("winter", "src/wrapper.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);

    exe.linkLibC();

    exe.addPackage(wayland);
    exe.linkSystemLibrary("wayland-server");

    exe.addPackage(xkbcommon);
    exe.linkSystemLibrary("xkbcommon");

    exe.addPackage(wlroots);
    exe.linkSystemLibrary("wlroots");

    exe.addPackage(pixman);
    exe.linkSystemLibrary("pixman-1");

    exe.linkSystemLibrary("guile-3.0");

    exe.step.dependOn(&scanner.step);
    // https://github.com/ziglang/zig/issues/131
    scanner.addCSource(exe);

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // // I'm not entirely sure how testing should work, since I need to
    // // enter guile mode before starting...
    // const exe_tests = b.addTest("src/wrapper.zig");
    // exe_tests.setTarget(target);
    // exe_tests.setBuildMode(mode);

    // const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&exe_tests.step);
}
