const std = @import("std");
const Build = std.Build;
const LazyPath = Build.LazyPath;
const fs = std.fs;

fn setupExternalRun(run: *Build.Step.Run, cwd: LazyPath) void {
    run.setCwd(cwd);
    run.setEnvironmentVariable("CC", "zig cc");
    run.setEnvironmentVariable("CXX", "zig c++");
}

fn buildOpenSSL(b: *Build) LazyPath {
    const cwd = fs.cwd();
    const prefix_cache_path = b.cache_root.join(b.allocator, &.{"openssl"}) catch @panic("join path error");
    const prefix_cache = LazyPath{
        .cwd_relative = prefix_cache_path,
    };

    const include_path = prefix_cache.path(b, "include").getPath(b);
    const libs = prefix_cache.path(b, "lib");
    const lib_ssl_path = libs.path(b, "libssl.a").getPath(b);
    const lib_crypto_path = libs.path(b, "libcrypto.a").getPath(b);

    const include_exists = if (cwd.access(include_path, .{})) |_| true else |_| false;
    const lib_ssl_exists = if (cwd.access(lib_ssl_path, .{})) |_| true else |_| false;
    const lib_crypto_exists = if (cwd.access(lib_crypto_path, .{})) |_| true else |_| false;

    const is_cached = include_exists and lib_ssl_exists and lib_crypto_exists;

    if (is_cached) {
        return prefix_cache;
    }

    const cpus = std.Thread.getCpuCount() catch 1;

    const openssl = b.dependency("openssl", .{});
    const sources = openssl.path("");
    const configure_path = openssl.path("Configure").getPath(b);

    const configure_command = b.addSystemCommand(&.{
        configure_path,
        b.fmt("--prefix={s}", .{prefix_cache_path}),
        "-no-shared",
        "-no-acvp-tests",
        "-no-external-tests",
        "-no-tests",
        "-no-unit-test",
    });
    setupExternalRun(configure_command, sources);

    const make_clean_command = b.addSystemCommand(&.{
        "make",
        "clean",
    });
    setupExternalRun(make_clean_command, sources);
    make_clean_command.step.dependOn(&configure_command.step);

    const make_build_command = b.addSystemCommand(&.{
        "make",
        b.fmt("-j{d}", .{cpus}),
        "build_generated",
        "libssl.a",
        "libcrypto.a",
    });
    setupExternalRun(make_build_command, sources);
    make_build_command.step.dependOn(&make_clean_command.step);

    const make_install_command = b.addSystemCommand(&.{
        "make",
        "install_dev",
    });
    setupExternalRun(make_install_command, sources);
    make_install_command.step.dependOn(&make_build_command.step);

    const prefix_generated = b.allocator.create(Build.GeneratedFile) catch @panic("OOM");

    prefix_generated.* = .{
        .step = &make_install_command.step,
        .path = prefix_cache.getPath(b),
    };

    return .{
        .generated = .{
            .file = prefix_generated,
        }
    };
}

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_ssl = b.addStaticLibrary(.{
        .name = "ssl",
        .target = target,
        .optimize = optimize,
    });

    const lib_crypto = b.addStaticLibrary(.{
        .name = "crypto",
        .target = target,
        .optimize = optimize,
    });

    const openssl_generated_prefix = buildOpenSSL(b);
    const openssl_libs = openssl_generated_prefix.path(b, "lib");
    const openssl_include = openssl_generated_prefix.path(b, "include");
    const openssl_lib_ssl = openssl_libs.path(b, "libssl.a");
    const openssl_lib_crypto = openssl_libs.path(b, "libcrypto.a");

    lib_ssl.addObjectFile(openssl_lib_ssl);
    lib_crypto.addObjectFile(openssl_lib_crypto);

    b.installArtifact(lib_ssl);
    b.installArtifact(lib_crypto);

    lib_ssl.installHeadersDirectory(openssl_include, ".", .{});
    lib_crypto.installHeadersDirectory(openssl_include, ".", .{});
}
