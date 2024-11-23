const pd = @import("pd");
const gme = @import("gme");
const std = @import("std");
const pr = @import("player.zig");
const arc = @import("arc.zig");

var s_mask: *pd.Symbol = undefined;

pub fn Gme(Root: type, Performer: type) type { return extern struct {
	const Self = @This();
	const Player = pr.Player(Self);

	base: Player,
	/// raw input buffer
	raw: [Root.nch * Performer.frames]i16,
	/// outlets
	outs: [Root.nch][*]pd.Sample,
	emu: *gme.Emu, // safe if open or play is true
	info: *gme.Info, // safe if open or play is true
	path: *pd.Symbol,
	/// ratio between file samplerate and pd samplerate
	ratio: f64,
	voices: u32,
	mask: u32,

	pub fn err(self: ?*Self, e: anyerror) void {
		pd.post.err(self, "%s", .{ @errorName(e).ptr });
	}

	fn reset(self: *Self) void {
		self.emu.setFade(-1, 0);
		@as(*Performer, @ptrCast(self)).reset();
	}

	fn seekC(self: *Self, f: pd.Float) callconv(.C) void {
		if (!self.base.open) {
			return;
		}
		self.emu.seek(@intFromFloat(f)) catch |e| self.err(e);
		self.reset();
	}

	fn mute(self: *Self, av: []const pd.Atom) void {
		const voices: i32 = @intCast(self.voices);
		for (av) |*a| {
			self.mask = switch (a.type) {
			.float => blk: {
				const d: i32 = @intFromFloat(a.w.float);
				break :blk if (d == 0) 0       // unmute all channels
				else ( self.mask ^ @as(u32, 1) // toggle the bit at d position
					<< @intCast(@mod(d - @intFromBool(d > 0), voices)) );
			},
			else => // symbol, mute all channels
				(@as(u32, 1) << @intCast(self.voices)) - 1,
			};
		}
	}

	fn muteC(
		self: *Self, _: ?*pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		self.mute(av[0..ac]);
		if (self.base.open) {
			self.emu.muteVoices(self.mask);
		}
	}

	fn soloC(
		self: *Self, _: ?*pd.Symbol, ac: c_uint, av: [*]const pd.Atom
	) callconv(.C) void {
		const prev = self.mask;
		self.mask = (@as(u32, 1) << @intCast(self.voices)) - 1;
		self.mute(av[0..ac]);
		if (prev == self.mask) {
			self.mask = 0;
		}
		if (self.base.open) {
			self.emu.muteVoices(self.mask);
		}
	}

	fn maskC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		if (ac > 0 and av[0].type == .float) { // set
			self.mask = @intFromFloat(av[0].w.float);
			if (self.base.open) {
				self.emu.muteVoices(self.mask);
			}
		} else { // get
			var flt = [1]pd.Atom{.{ .type = .float,
				.w = .{ .float = @floatFromInt(self.mask) } }};
			self.base.o_meta.anything(s_mask, &flt);
		}
	}

	fn bMaskC(self: *Self) callconv(.C) void {
		var buf: [32:0]u8 = undefined;
		for (0..self.voices) |i| {
			buf[i] = '0' + @as(u8, @intCast((self.mask >> @intCast(i)) & 1));
		}
		buf[self.voices] = 0;
		pd.post.log(self, .normal, &buf, .{});
	}

	fn sampleRate(self: *Self, t: *const gme.Type) u32 {
		const pd_srate = pd.sampleRate();
		const srate = if (t == gme.Type.spc.*) 32000.0 else pd_srate;
		self.ratio = srate / pd_srate;
		return @intFromFloat(srate);
	}

	fn load(self: *Self, index: u32) !void {
		try self.emu.startTrack(index);
		const info = try self.emu.trackInfo(index);
		self.info.free();
		self.info = info;
		self.reset();
		@as(*Performer, @ptrCast(self)).restart();
	}

	fn open(self: *Self, s: *pd.Symbol) !void {
		const prev_emu = self.emu;

		const path = s.name[0..pr.strlen(s.name) :0];
		const new_fn: *const fn(*const gme.Type, u32) anyerror!*gme.Emu
			= if (Root.nch > 2) gme.Type.emuMultiChannel else gme.Type.emu;

		var file = try std.fs.cwd().openFile(path, .{});
		const signature: u32 = @bitCast(try file.reader().readBytesNoEof(4));
		file.close();

		var arc_reader: ?arc.Reader = inline for (arc.types) |t| {
			if (signature == t.signature) {
				break try t.init(&pd.mem, path);
			}
		} else null;

		if (arc_reader) |*ar| {
			defer ar.close();
			const sizes = try pd.mem.alloc(usize, ar.count);
			defer pd.mem.free(sizes);
			const buf = try pd.mem.alloc(u8, ar.size);
			defer pd.mem.free(buf);

			var bp = buf;
			var n: u32 = 0;
			var emu_type: ?*const gme.Type = null;
			while (try ar.next(bp)) |entry| {
				const t = gme.Type.fromExtension(entry.name) orelse continue;
				if (emu_type == null) {
					emu_type = t;
				}
				if (emu_type == t) {
					sizes[n] = entry.size;
					bp = bp[sizes[n]..];
					n += 1;
				}
			}

			const t = emu_type orelse return error.ArchiveNoMatch;
			const old_ratio = self.ratio;
			errdefer self.ratio = old_ratio;
			self.emu = try new_fn(t, self.sampleRate(t));
			errdefer { self.emu.delete(); self.emu = prev_emu; }
			if (t.trackCount() == 1) {
				try self.emu.loadTracks(buf.ptr, sizes[0..n]);
			} else {
				try self.emu.loadData(buf[0..sizes[0]]);
			}
		} else {
			const t = try gme.Type.fromFile(path) orelse return error.FileNoMatch;
			const old_ratio = self.ratio;
			errdefer self.ratio = old_ratio;
			self.emu = try new_fn(t, self.sampleRate(t));
			errdefer { self.emu.delete(); self.emu = prev_emu; }
			try self.emu.loadFile(path);
		}

		self.emu.ignoreSilence(true);
		self.emu.muteVoices(self.mask);
		try self.load(0);

		// safe to delete the previous emulator
		prev_emu.delete();

		// check for a .m3u file of the same name
		var m3u_path = try pd.mem.allocSentinel(u8, path.len + 4, 0);
		defer pd.mem.free(m3u_path);
		const i = std.mem.lastIndexOf(u8, path, ".") orelse path.len;
		@memcpy(m3u_path[0..i], s.name[0..i]);
		@memcpy(m3u_path[i..i+4], ".m3u");
		m3u_path[i+4] = 0;
		self.emu.loadM3u(m3u_path) catch {};

		self.path = s;
		self.base.open = true;
		self.base.play = false;
		self.voices = self.emu.voiceCount();

		var atom = [1]pd.Atom{.{ .type = .float,
			.w = .{.float = @floatFromInt(@intFromBool(self.base.open))} }};
		self.base.o_meta.anything(pr.s_open, &atom);
	}

	fn openC(self: *Self, s: *pd.Symbol) callconv(.C) void {
		self.open(s) catch |e| self.err(e);
	}

	fn length(self: *Self) i64 {
		const ms = self.info.length;
		return if (ms >= 0) ms else blk: { // try intro + 2 loops
			const intro = self.info.intro_length;
			const loop = self.info.loop_length;
			break :blk if (intro < 0 and loop < 0) ms
				else @max(0, intro) + @max(0, 2 * loop);
		};
	}

	fn print(self: *Self, av: []const pd.Atom) !void {
		if (!self.base.open) {
			return error.NoFileOpened;
		}
		if (av.len > 0) {
			return try self.base.print(av);
		}
		// general track info: %game% - %song%
		const info = self.info;
		if (info.game[0] != 0) {
			pd.post.start("%s", .{ info.game });
			if (info.song[0] != 0) {
				pd.post.start(" - %s", .{ info.song });
			}
			pd.post.end();
		} else if (info.song[0] != 0) {
			pd.post.do("%s", .{ info.song });
		}
	}

	fn printC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		self.print(av[0..ac]) catch |e| self.err(e);
	}

	fn float(self: *Self, f: pd.Float) !bool {
		if (!self.base.open) {
			return error.NoFileOpened;
		}
		const track: i32 = @intFromFloat(f);
		if (0 < track and track <= self.emu.trackCount()) {
			try self.load(@intCast(track - 1));
			return true;
		}
		self.seekC(0);
		self.reset();
		@as(*Performer, @ptrCast(self)).restart();
		return false;
	}

	fn floatC(self: *Self, f: pd.Float) callconv(.C) void {
		self.base.play = self.float(f) catch |e| blk: {
			self.err(e);
			break :blk false;
		};
		var play = [1]pd.Atom{.{ .type = .float, .w = .{
			.float = @floatFromInt(@intFromBool(self.base.play)) } }};
		self.base.o_meta.anything(pr.s_play, &play);
	}

	fn stopC(self: *Self) callconv(.C) void {
		self.floatC(0);
	}

	pub inline fn new(av: []const pd.Atom) !*Self {
		const self: *Self = @ptrCast(try Player.new(Performer, Root.nch));
		self.ratio = 1.0;
		self.mask = 0;
		self.voices = 16;
		self.path = &pd.s_;
		if (av.len > 0) {
			self.soloC(null, @intCast(av.len), av.ptr);
		}
		return self;
	}

	pub fn free(self: *Self) void {
		self.info.free();
		self.emu.delete();
	}

	pub fn class() !*pd.Class {
		s_mask = pd.symbol("mask");
		const cls = try Player.class(Root, Performer);

		const dict = &Player.dict;
		inline for ([_][:0]const u8{
			"path", "time", "ftime", "fade", "tracks", "voices",
			"system", "game", "song", "author", "copyright", "comment", "dumper",
		}) |meta| {
			try dict.put(pd.symbol(meta.ptr), @field(Dict, meta));
		}

		cls.addFloat(@ptrCast(&floatC));
		cls.addMethod(@ptrCast(&seekC), pd.symbol("seek"), &.{ .float });
		cls.addMethod(@ptrCast(&printC), pd.symbol("print"), &.{ .gimme });
		cls.addMethod(@ptrCast(&muteC), pd.symbol("mute"), &.{ .gimme });
		cls.addMethod(@ptrCast(&soloC), pd.symbol("solo"), &.{ .gimme });
		cls.addMethod(@ptrCast(&maskC), s_mask, &.{ .gimme });
		cls.addMethod(@ptrCast(&openC), pr.s_open, &.{ .symbol });
		cls.addMethod(@ptrCast(&stopC), pd.symbol("stop"), &.{});
		cls.addMethod(@ptrCast(&bMaskC), pd.symbol("bmask"), &.{});
		return cls;
	}

	const Dict = struct {
		fn path(self: *Self) pd.Atom
		{ return .{ .type = .symbol, .w = .{.symbol = self.path} }; }
		fn time(self: *Self) pd.Atom
		{ return .{ .type = .float, .w = .{.float = @floatFromInt(self.length())} }; }
		fn ftime(self: *Self) pd.Atom
		{ return .{ .type = .symbol, .w = .{.symbol = pr.fmtTimeSym(self.length())} }; }
		fn fade(self: *Self) pd.Atom
		{ return .{ .type = .float, .w = .{.float = @floatFromInt(self.info.fade_length)} }; }
		fn tracks(self: *Self) pd.Atom
		{ return .{ .type = .float, .w = .{.float = @floatFromInt(self.emu.trackCount())} }; }
		fn voices(self: *Self) pd.Atom
		{ return .{ .type = .float, .w = .{.float = @floatFromInt(self.emu.voiceCount())} }; }
		fn system(self: *Self) pd.Atom
		{ return .{ .type = .symbol, .w = .{.symbol = pd.symbol(self.info.system)} }; }
		fn game(self: *Self) pd.Atom
		{ return .{ .type = .symbol, .w = .{.symbol = pd.symbol(self.info.game)} }; }
		fn song(self: *Self) pd.Atom
		{ return .{ .type = .symbol, .w = .{.symbol = pd.symbol(self.info.song)} }; }
		fn author(self: *Self) pd.Atom
		{ return .{ .type = .symbol, .w = .{.symbol = pd.symbol(self.info.author)} }; }
		fn copyright(self: *Self) pd.Atom
		{ return .{ .type = .symbol, .w = .{.symbol = pd.symbol(self.info.copyright)} }; }
		fn comment(self: *Self) pd.Atom
		{ return .{ .type = .symbol, .w = .{.symbol = pd.symbol(self.info.comment)} }; }
		fn dumper(self: *Self) pd.Atom
		{ return .{ .type = .symbol, .w = .{.symbol = pd.symbol(self.info.dumper)} }; }
	};
};}
