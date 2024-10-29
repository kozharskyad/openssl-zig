const std = @import("std");
const Build = std.Build;
const LazyPath = Build.LazyPath;
const fs = std.fs;

fn setupExternalRun(run: *Build.Step.Run, cwd: LazyPath) void {
    run.setCwd(cwd);
    run.setEnvironmentVariable("CC", "zig cc");
    run.setEnvironmentVariable("CXX", "zig c++");
}

fn buildOpenSSL(b: *Build, openssl: *Build.Dependency, dependant: *Build.Step) void {
    const cpus = std.Thread.getCpuCount() catch 1;
    const openssl_sources = openssl.path("");
    const openssl_configure_path = openssl.path("Configure").getPath(b);
    const openssl_prefix_path = b.path(".zig-cache/openssl").getPath(b);

    fs.deleteTreeAbsolute(openssl_prefix_path) catch {};

    const openssl_configure_command = b.addSystemCommand(&.{
        openssl_configure_path,
        b.fmt("--prefix={s}", .{openssl_prefix_path}),
        "-no-shared",
        "-no-acvp-tests",
        "-no-external-tests",
        "-no-tests",
        "-no-unit-test",
    });
    setupExternalRun(openssl_configure_command, openssl_sources);

    const openssl_make_clean_command = b.addSystemCommand(&.{
        "make",
        "clean",
    });
    setupExternalRun(openssl_make_clean_command, openssl_sources);
    openssl_make_clean_command.step.dependOn(&openssl_configure_command.step);

    const openssl_make_build_command = b.addSystemCommand(&.{
        "make",
        b.fmt("-j{d}", .{cpus}),
        "build_generated",
        "libssl.a",
        "libcrypto.a",
    });
    setupExternalRun(openssl_make_build_command, openssl_sources);
    openssl_make_build_command.step.dependOn(&openssl_make_clean_command.step);

    const openssl_make_install_command = b.addSystemCommand(&.{
        "make",
        "install_dev",
    });
    setupExternalRun(openssl_make_install_command, openssl_sources);
    openssl_make_install_command.step.dependOn(&openssl_make_build_command.step);

    dependant.dependOn(&openssl_make_install_command.step);
}

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const cwd = fs.cwd();

    const openssl = b.dependency("openssl", .{
        .target = target,
        .optimize = optimize,
    });

    const openssl_prefix = b.path(".zig-cache/openssl");
    const openssl_libs = openssl_prefix.path(b, "lib");
    const openssl_include = openssl_prefix.path(b, "include");
    const openssl_lib_ssl = openssl_libs.path(b, "libssl.a");
    const openssl_lib_crypto = openssl_libs.path(b, "libcrypto.a");
    const openssl_lib_ssl_exists = if (cwd.statFile(openssl_lib_ssl.getPath(b))) |_| true else |_| false;
    const openssl_lib_crypto_exists = if (cwd.statFile(openssl_lib_crypto.getPath(b))) |_| true else |_| false;

    if (!openssl_lib_ssl_exists or !openssl_lib_crypto_exists) {
        buildOpenSSL(b, openssl, b.default_step);
    }

    _ = b.addModule("lib_ssl", .{ .root_source_file = openssl_lib_ssl, });
    _ = b.addModule("lib_crypto", .{ .root_source_file = openssl_lib_crypto, });
    _ = b.addModule("libs", .{ .root_source_file = openssl_libs, });
    _ = b.addModule("includes", .{ .root_source_file = openssl_include, });
}
