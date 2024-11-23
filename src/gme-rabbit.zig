const pd = @import("pd");
const ra = @import("rabbit");
const gm = @import("gme.zig");
const inl = @import("inlet.zig");
const interleavedToPlanar = @import("player.zig").interleavedToPlanar;

pub fn Performer(Root: type) type { return extern struct {
	const Self = @This();
	const Gme = gm.Gme(Root, Self);
	pub var class: *pd.Class = undefined;

	pub const frames = 0x10;
	// fastest speed gets stuck if it's too close to the exact number of frames
	const fastest: pd.Float = @as(pd.Float, @floatFromInt(frames)) - 0x1p-7;
	const slowest: pd.Float = 1 / @as(pd.Float, @floatFromInt(frames));

	gme: Gme,
	/// input buffer
	in: [Root.nch * frames]pd.Sample,
	/// output buffer
	out: [Root.nch * frames]pd.Sample,
	data: ra.Data,
	rabbit: *ra.State,
	speed: *pd.Float,
	tempo: *pd.Float,

	fn speedC(self: *Self, f: pd.Float) callconv(.C) void {
		self.speed.* = f;
	}

	fn tempoC(self: *Self, f: pd.Float) callconv(.C) void {
		self.tempo.* = f;
	}

	pub fn rabbitErr(self: *Self, e: ra.Error) void {
		pd.post.err(self, "%s", .{ if (ra.strError(e)) |str| str.ptr else "" });
	}

	pub fn reset(self: *Self) void {
		self.rabbit.reset() catch |e| self.rabbitErr(e);
		self.data.output_frames_gen = 0;
		self.data.input_frames = 0;
	}

	pub fn restart(self: *Self) void {
		self.gme.emu.setTempo(self.tempo.*);
	}

	fn conv(self: *Self, i: u32) ra.Error!void {
		try ra.Converter.expectValid(i);
		const new_state = try ra.State.new(@enumFromInt(i), Root.nch);
		self.rabbit.delete();
		self.rabbit = new_state;
	}

	fn convC(self: *Self, f: pd.Float) callconv(.C) void {
		self.conv(@intFromFloat(f)) catch |e| self.rabbitErr(e);
	}

	fn perform(self: *Self, w: [*]usize, ip: *u32) !void {
		var i: u32 = 0;
		errdefer ip.* = i;
		const n = w[2];
		const inlet2: [*]pd.Sample = @ptrFromInt(w[3]);
		const inlet1: [*]pd.Sample = @ptrFromInt(w[4]);

		const data = &self.data;
		const emu = self.gme.emu;
		const raw: []i16 = &self.gme.raw;
		var outs: [Root.nch][*]pd.Sample = self.gme.outs;

		while (i < n) {
			while (data.output_frames_gen <= 0) {
				if (data.input_frames <= 0) {
					emu.setTempo(inlet2[i]);
					try emu.play(raw);
					for (raw, &self.in) |*from, *to| {
						to.* = @as(pd.Sample, @floatFromInt(from.*)) * 0x1p-15;
					}
					data.data_in = &self.in;
					data.input_frames = frames;
				}
				data.data_out = &self.out;
				data.src_ratio = 1 / @min(@max(slowest, inlet1[i] * self.gme.ratio), fastest);
				try self.rabbit.process(data);
				data.input_frames -= data.input_frames_used;
				data.data_in += @as(usize, @intCast(data.input_frames_used)) * Root.nch;
			}
			const used: u32 = @min(@as(u32, @intCast(data.output_frames_gen)), n - i);
			data.data_out = interleavedToPlanar(data.data_out, &outs, used);
			inline for (0..Root.nch) |ch| {
				outs[ch] += used;
			}
			data.output_frames_gen -= used;
			i += used;
		}
	}

	pub fn performC(w: [*]usize) callconv(.C) *usize {
		const self: *Self = @ptrFromInt(w[1]);
		if (!self.gme.base.play) {
			inline for (self.gme.outs[0..Root.nch]) |ch| {
				@memset(ch[0..w[2]], 0);
			}
		} else {
			var i: u32 = undefined;
			self.perform(w, &i) catch |e| {
				self.gme.base.play = false;
				self.gme.err(e);
				inline for (self.gme.outs[0..Root.nch]) |ch| {
					@memset(ch[i..w[2]], 0);
				}
			};
		}
		return &w[5];
	}

	fn dspC(self: *Self, sp: [*]*pd.Signal) callconv(.C) void {
		for (&self.gme.outs, sp[2 .. 2 + Root.nch]) |*o, s| {
			o.* = s.vec;
		}
		pd.dsp.add(&performC, .{ self, sp[1].len, sp[1].vec, sp[0].vec });
	}

	inline fn new(av: []const pd.Atom) !*Self {
		const self: *Self = @ptrCast(try Gme.new(av));
		errdefer @as(*pd.Pd, @ptrCast(self)).free();

		const obj = &self.gme.base.obj;
		const in2: *inl.Inlet = @ptrCast(@alignCast(try obj.inletSignal(1.0)));
		self.speed = &in2.un.floatsignalvalue;
		const in3: *inl.Inlet = @ptrCast(@alignCast(try obj.inletSignal(1.0)));
		self.tempo = &in3.un.floatsignalvalue;

		self.rabbit = try ra.State.new(.sinc_fast, Root.nch);
		self.data.output_frames = frames;
		self.data.src_ratio = 1.0;
		return self;
	}

	pub fn newC(_: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom) callconv(.C) ?*Self {
		return new(av[0..ac]) catch |e| blk: {
			Gme.err(null, e);
			break :blk null;
		};
	}

	pub fn freeC(self: *Self) callconv(.C) void {
		self.gme.free();
		self.rabbit.delete();
	}

	pub inline fn setup() !void {
		class = try Gme.class();
		class.addMethod(@ptrCast(&dspC), pd.symbol("dsp"), &.{ .cant });
		class.addMethod(@ptrCast(&convC), pd.symbol("conv"), &.{ .float });
		class.addMethod(@ptrCast(&speedC), pd.symbol("speed"), &.{ .float });
		class.addMethod(@ptrCast(&tempoC), pd.symbol("tempo"), &.{ .float });
	}
};}
