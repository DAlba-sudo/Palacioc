const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependency Import
    const pg = b.dependency("pg", .{ .target = target, .optimize = optimize });
    const httpz = b.dependency("httpz", .{ .target = target, .optimize = optimize });

    // Internal Library
    const internal = b.createModule(.{
        .root_source_file = b.path("src/internal/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "pg", .module = pg.module("pg") },
        },
    });

    // Server Executable
    const exe_server = b.addExecutable(.{
        .name = "server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cmd/server/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pg", .module = pg.module("pg") },
                .{ .name = "httpz", .module = httpz.module("httpz") },
                .{ .name = "internal", .module = internal },
            },
        }),
    });

    b.installArtifact(exe_server);

    // `zig build run -- <args>`
    const run_server = b.addRunArtifact(exe_server);
    run_server.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_server.addArgs(args);

    const run_step = b.step("run", "Run the server");
    run_step.dependOn(&run_server.step);

    // `zig build test`
    const test_step = b.step("test", "Run unit tests");
    const internal_tests = b.addTest(.{ .root_module = internal });
    const server_tests = b.addTest(.{ .root_module = exe_server.root_module });
    test_step.dependOn(&b.addRunArtifact(internal_tests).step);
    test_step.dependOn(&b.addRunArtifact(server_tests).step);
}
