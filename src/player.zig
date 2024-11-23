const pd = @import("pd");
const std = @import("std");
const tg = @import("toggle.zig");

pub var s_open: *pd.Symbol = undefined;
pub var s_play: *pd.Symbol = undefined;
pub const blank = pd.Atom{ .type = .symbol, .w = .{.symbol = &pd.s_bang} };

// valgrind takes issue with std.mem.len
pub const strlen = @cImport({ @cInclude("string.h"); }).strlen;

pub fn fmtTime(ms: i64, buf: []u8) ![:0]u8 {
	if (ms < 0) {
		@memcpy(buf[0..4], "?:?\x00");
		return buf[0..3 :0];
	}
	const t = @as(f64, @floatFromInt(ms));
	const hr = t / (60 * 60 * 1000);
	const mn = @mod(t / (60 * 1000), 60);
	const sc = @mod(t / 1000, 60);

	var i: usize = 0;
	if (hr >= 1) {
		const slice = try std.fmt.bufPrint(buf, "{}:", .{ @as(i32, @intFromFloat(hr)) });
		i += slice.len;
	}
	const slice = try std.fmt.bufPrint(buf[i..], "{d:0>2}:{d:0>2}", .{
		@as(u8, @intFromFloat(mn)), @as(u8, @intFromFloat(sc)) });
	i += slice.len;

	buf[i] = 0;
	return buf[0..i :0];
}

test "format time" {
	var buffer: [32]u8 = undefined;
	var buf = try fmtTime(2 * 60 * 1000, &buffer);
	try std.testing.expect(std.mem.eql(u8, buf, "02:00"));
	buf = try fmtTime(2 * 60 * 60 * 1000, &buffer);
	try std.testing.expect(std.mem.eql(u8, buf, "2:00:00"));
}

pub fn fmtTimeSym(ms: i64) *pd.Symbol {
	var buffer: [32]u8 = undefined;
	const buf = fmtTime(ms, &buffer) catch return &pd.s_;
	return pd.symbol(buf.ptr);
}

pub inline fn interleavedToPlanar(
	interleaved: [*]pd.Sample,
	planar: [][*]pd.Sample,
	frames: u32,
) [*]pd.Sample {
	var n = planar.len;
	var out: [*]pd.Sample = undefined;
	while (n > 0) {
		n -= 1;
		var ch = planar[n];
		out = interleaved + n;
		const end: usize = @intFromPtr(ch + frames);
		while (@intFromPtr(ch) < end) {
			ch[0] = out[0];
			out += planar.len;
			ch += 1;
		}
	}
	return out;
}

pub fn Player(Dict: type) type { return extern struct {
	const Self = @This();
	pub var dict = std.AutoHashMap(*pd.Symbol, *const fn(*Dict) pd.Atom).init(pd.mem);

	obj: pd.Object,
	o_meta: *pd.Outlet,
	open: bool,
	play: bool,

	fn err(self: ?*Self, e: anyerror) void {
		pd.post.err(self, "%s", .{ @errorName(e).ptr });
	}

	pub fn print(self: *Self, av: []const pd.Atom) !void {
		var ac = av.len;
		for (av) |*a| {
			ac -= 1;
			if (a.type == .symbol) {
				const n = strlen(a.w.symbol.name);
				var sym = a.w.symbol.name[0..n];
				while (true) {
					var pct = std.mem.indexOf(u8, sym, "%") orelse break;
					const end = (std.mem.indexOf(u8, sym[pct+1..], "%") orelse break)
						+ pct + 1;
					if (pct > 0) { // print what comes before placeholder
						const buf = try pd.mem.allocSentinel(u8, pct, 0);
						defer pd.mem.free(buf);
						@memcpy(buf[0..pct], sym[0..pct]);
						pd.post.start("%s", .{ buf.ptr });
						sym = sym[pct..];
					}
					pct += 1;
					const len = end - pct;
					const buf = try pd.mem.allocSentinel(u8, len, 0);
					defer pd.mem.free(buf);
					@memcpy(buf[0..len], sym[1..1+len]);
					const meta = if (dict.get(pd.symbol(@ptrCast(buf.ptr)))) |func|
						func(@ptrCast(self)) else blank;
					switch (meta.type) {
						.float => pd.post.start("%g", .{ meta.w.float }),
						else => {
							const s: *pd.Symbol = meta.w.symbol;
							pd.post.start("%s", .{ if (s == &pd.s_bang) "" else s.name });
						},
					}
					sym = sym[len+2..];
				}
				pd.post.start("%s%s", .{ sym.ptr, (if (ac > 0) " " else "").ptr });
			} else if (a.type == .float) {
				pd.post.start("%g%s", .{ a.w.float, (if (ac > 0) " " else "").ptr });
			}
		}
		pd.post.end();
	}

	fn send(self: *Self, s: *pd.Symbol) !void {
		if (!self.open) {
			return error.NoFileOpened;
		}
		var meta = [1]pd.Atom{if (dict.get(s)) |func| func(@ptrCast(self)) else blank};
		self.o_meta.anything(s, &meta);
	}

	fn sendC(self: *Self, s: *pd.Symbol) callconv(.C) void {
		self.send(s) catch |e| self.err(e);
	}

	fn anythingC(
		self: *Self, s: *pd.Symbol, _: c_uint, _: [*]const pd.Atom
	) callconv(.C) void {
		self.sendC(s);
	}

	fn setPlay(self: *Self, av: []const pd.Atom) !void {
		if (!self.open) {
			return error.NoFileOpened;
		}
		if (tg.toggle(&self.play, av)) {
			var state = [1]pd.Atom{.{ .type = .float,
				.w = .{.float = @floatFromInt(@intFromBool(self.play))} }};
			self.o_meta.anything(s_play, &state);
		}
	}

	fn setPlayC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom
	) callconv(.C) void {
		self.setPlay(av[0..ac]) catch |e| self.err(e);
	}

	fn bangC(self: *Self) callconv(.C) void {
		self.setPlayC(s_play, 0, &[0]pd.Atom{});
	}

	pub inline fn new(Top: type, nch: u8) !*Self {
		const self: *Self = @ptrCast(try Top.class.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		const obj = &self.obj;
		for (0..nch) |_| {
			_ = try obj.outlet(&pd.s_signal);
		}
		self.o_meta = try obj.outlet(null);
		self.open = false;
		self.play = false;
		return self;
	}

	fn classFreeC(_: *pd.Class) callconv(.C) void {
		dict.clearAndFree();
	}

	pub fn class(Root: type, Top: type) !*pd.Class {
		s_open = pd.symbol("open");
		s_play = pd.symbol("play");

		const cls = try pd.class(pd.symbol(Root.name),
			@ptrCast(&Top.newC), @ptrCast(&Top.freeC), @sizeOf(Top), .{}, &.{ .gimme });
		cls.addBang(@ptrCast(&bangC));
		cls.addAnything(@ptrCast(&anythingC));
		cls.addMethod(@ptrCast(&sendC), pd.symbol("send"), &.{ .symbol });
		cls.addMethod(@ptrCast(&setPlayC), s_play, &.{ .gimme });
		cls.setFreeFn(classFreeC);
		return cls;
	}
};}
