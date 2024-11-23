const std = @import("std");
const installLink = @import("InstallLink.zig").installLink;

const Options = struct {
	float_size: u8 = 32,
	shared: bool = false,
	symlink: bool = false,
};

const Link = enum {
	gme,
	rubber,
	rabbit,
};

const External = struct {
	name: []const u8,
	links: []const Link = &.{},
};

const externals = [_]External{
	.{ .name = "arp" },
	.{ .name = "blunt" },
	.{ .name = "chrono" },
	.{ .name = "delp" },
	.{ .name = "fldec" },
	.{ .name = "flenc" },
	.{ .name = "fton" },
	.{ .name = "gmer~", .links = &.{ .gme, .rubber, .rabbit } },
	.{ .name = "gmes~", .links = &.{ .gme, .rabbit } },
	.{ .name = "gme~", .links = &.{ .gme, .rabbit } },
	.{ .name = "has" },
	.{ .name = "hsv" },
	.{ .name = "is" },
	.{ .name = "linp" },
	.{ .name = "linp~" },
	.{ .name = "metro~" },
	.{ .name = "ntof" },
	.{ .name = "paq" },
	.{ .name = "rand" },
	.{ .name = "rind" },
	.{ .name = "same" },
	.{ .name = "slx" },
	.{ .name = "sly" },
	.{ .name = "tabosc2~" },
	.{ .name = "tabread2~" },
	.{ .name = "unpaq" },
};

pub fn build(b: *std.Build) !void {
	const target = b.standardTargetOptions(.{});
	const optimize = b.standardOptimizeOption(.{});

	const defaults = Options{};
	const opt = Options{
		.float_size = b.option(u8, "float_size", "Size of a floating-point number")
			orelse defaults.float_size,
		.shared = b.option(bool, "shared", "Build shared libraries")
			orelse defaults.shared,
		.symlink = if (target.result.os.tag == .windows) false else
			b.option(bool, "symlink", "Install symbolic links of Pd patches.")
			orelse defaults.symlink,
	};

	const pd = b.dependency("pd_module", .{
		.target=target, .optimize=optimize, .float_size=opt.float_size,
	}).module("pd");
	const gme = b.dependency("game_music_emu", .{
		.target=target, .optimize=optimize, .shared=opt.shared, .ym2612_emu=.mame,
	}).module("gme");
	const unrar = b.dependency("unrar", .{
		.target=target, .optimize=optimize, .shared=opt.shared,
	}).module("unrar");
	const rubber = b.dependency("rubberband", .{
		.target=target, .optimize=optimize, .shared=opt.shared,
	}).module("rubberband");
	const rabbit = b.dependency("libsamplerate", .{
		.target=target, .optimize=optimize, .shared=opt.shared,
	}).module("samplerate");

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

	for (externals) |x| {
		const lib = b.addSharedLibrary(.{
			.name = x.name,
			.root_source_file = b.path(b.fmt("src/{s}.zig", .{x.name})),
			.target = target,
			.optimize = optimize,
			.link_libc = true,
			.pic = true,
		});
		lib.root_module.addImport("pd", pd);

		for (x.links) |link| switch (link) {
			.gme => {
				lib.root_module.addImport("gme", gme);
				lib.root_module.addImport("unrar", unrar);
			},
			.rubber => lib.root_module.addImport("rubber", rubber),
			.rabbit => lib.root_module.addImport("rabbit", rabbit),
		};

		const install = b.addInstallFile(lib.getEmittedBin(),
			b.fmt("{s}{s}", .{ x.name, extension }));
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
