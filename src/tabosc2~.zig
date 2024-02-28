const pd = @import("pd");

const unitbit32 = 3.0 * 0x1p19; // bit 32 has place value 1
const hioffset: u1 = blk: {
	const builtin = @import("builtin");
	break :blk if (builtin.target.cpu.arch.endian() == .little) 1 else 0;
};

const TabFudge = union {
	d: f64,
	i: [2]i32,
};

const TabOsc2 = extern struct {
	const Self = @This();
	const Base = @import("tab2.zig").Tab2;
	var class: *pd.Class = undefined;

	base: Base,
	phase: f64,
	conv: pd.Float,
	len: pd.Float,
	invlen: pd.Float,

	fn performC(w: [*]usize) callconv(.C) *usize {
		const self: *Self = @ptrFromInt(w[1]);
		const out = @as([*]pd.Sample, @ptrFromInt(w[3]))[0..w[2]];
		const vec = self.base.vec orelse {
			@memset(out, 0);
			return &w[6];
		};
		const len = self.len;
		const mask = @as(i32, @intFromFloat(len)) - 1;
		const conv = len * self.conv;
		var dphase = len * self.phase + unitbit32;

		var tf = TabFudge{ .d = unitbit32 };
		var normhipart = tf.i[hioffset];

		const inlet2: [*]pd.Sample = @ptrFromInt(w[4]);
		const inlet1: [*]pd.Sample = @ptrFromInt(w[5]);
		for (out, inlet1, inlet2) |*o, in1, in2| {
			tf.d = dphase;
			dphase += in1 * conv;
			const i: usize = @intCast(tf.i[hioffset] & mask);
			tf.i[hioffset] = normhipart;
			o.* = Base.sample(vec + i, @floatCast(tf.d - unitbit32), in2);
		}

		tf.d = unitbit32 * len;
		normhipart = tf.i[hioffset];
		tf.d = dphase + unitbit32 * (len - 1);
		tf.i[hioffset] = normhipart;
		self.phase = (tf.d - unitbit32 * len) * self.invlen;
		return &w[6];
	}

	fn setC(self: *Self, s: *pd.Symbol) callconv(.C) void {
		const len = self.base.setArray(s)
			catch |e| return pd.post.err(self, "%s: %s", .{ s.name, @errorName(e).ptr });
		self.len = @floatFromInt(len);
		self.invlen = 1.0 / self.len;
	}

	fn dspC(self: *Self, sp: [*]*pd.Signal) callconv(.C) void {
		self.conv = 1.0 / sp[0].srate;
		self.setC(self.base.arrayname);
		pd.dsp.add(&performC, .{ self, sp[2].len, sp[2].vec, sp[1].vec, sp[0].vec });
	}

	fn ft1C(self: *Self, f: pd.Float) callconv(.C) void {
		self.phase = f;
	}

	inline fn new(arrayname: *pd.Symbol, hold: pd.Float) !*Self {
		const self: *Self = @ptrCast(try class.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		try self.base.init(arrayname, hold);

		const obj: *pd.Object = @ptrCast(self);
		_ = try obj.inlet(&obj.g.pd, &pd.s_float, pd.symbol("ft1"));

		self.len = 512.0;
		self.invlen = 1.0 / self.len;
		return self;
	}

	fn newC(arrayname: *pd.Symbol, hold: pd.Float) callconv(.C) ?*Self {
		return new(arrayname, hold) catch null;
	}

	inline fn setup() !void {
		class = try pd.class(pd.symbol("tabosc2~"), @ptrCast(&newC), null,
			@sizeOf(Self), .{}, &.{ .defsymbol, .deffloat });

		Base.extend(class);
		class.addMethod(@ptrCast(&dspC), pd.symbol("dsp"), &.{ .cant });
		class.addMethod(@ptrCast(&setC), pd.symbol("set"), &.{ .symbol });
		class.addMethod(@ptrCast(&ft1C), pd.symbol("ft1"), &.{ .float });
	}
};

export fn tabosc2_tilde_setup() void {
	TabOsc2.setup() catch {};
}
