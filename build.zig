const std = @import("std");
const installLink = @import("InstallLink.zig").installLink;

const Options = struct {
	float_size: u8 = 32,
	symlink: bool = false,
};

const externals = [_][]const u8{
	"fldec",
	"flenc",
	"has",
	"is",
	"rand",
	"rind",
	"same",
	"slx",
	"sly",
	"tabosc2~",
	"tabread2~",
};

pub fn build(b: *std.Build) void {
	const target = b.standardTargetOptions(.{});
	const optimize = b.standardOptimizeOption(.{});

	const defaults = Options{};
	const opt = Options{
		.float_size = b.option(u8, "float_size", "Size of a floating-point number")
			orelse defaults.float_size,
		.symlink = if (target.result.os.tag == .windows) false else
			b.option(bool, "symlink", "Install symbolic links of Pd patches.")
			orelse defaults.symlink,
	};

	const pd = b.dependency("pd_module", .{
		.target=target, .optimize=optimize, .float_size=opt.float_size,
	}).module("pd");

	const extension = b.fmt(".{s}_{s}", .{
		switch (target.result.os.tag) {
			.ios, .macos, .watchos, .tvos => "d",
			.windows => "m",
			else => "l",
		},
		switch (target.result.cpu.arch) {
			.x86_64 => "amd64",
			.x86 => "i386",
			.arm, .armeb => "arm",
			.aarch64, .aarch64_be, .aarch64_32 => "arm64",
			.powerpc, .powerpcle => "ppc",
			else => @tagName(target.result.cpu.arch),
		},
	});

	for (externals) |name| {
		const lib = b.addSharedLibrary(.{
			.name = name,
			.root_source_file = b.path(b.fmt("src/{s}.zig", .{name})),
			.target = target,
			.optimize = optimize,
			.link_libc = true,
			.pic = true,
		});
		lib.root_module.addImport("pd", pd);

		const install = b.addInstallFile(lib.getEmittedBin(),
			b.fmt("{s}{s}", .{ name, extension }));
		install.step.dependOn(&lib.step);
		b.getInstallStep().dependOn(&install.step);
	}

	const installFile = if (opt.symlink) &installLink else &std.Build.installFile;
	for (&[_][]const u8{"help", "abstractions"}) |dir_name| {
		const dir = try std.fs.cwd().openDir(dir_name, .{ .iterate = true });
		var iter = dir.iterate();
		while (try iter.next()) |file| {
			if (file.kind != .file)
				continue;
			installFile(b, b.fmt("{s}/{s}", .{dir_name, file.name}), file.name);
		}
	}
}
