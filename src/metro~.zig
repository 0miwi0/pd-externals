const pd = @import("pd");

const unitbit32 = 1572864.0; // 3*2^19; bit 32 has place value 1
const hioffset: u1 = blk: {
	const builtin = @import("builtin");
	break :blk if (builtin.target.cpu.arch.endian() == .little) 1 else 0;
};

const TabFudge = union {
	d: f64,
	i: [2]i32,
};

const MetroTilde = extern struct {
	const Self = @This();
	var class: *pd.Class = undefined;

	obj: pd.Object,
	out: *pd.Outlet,
	phase: f64,
	prev: pd.Sample,
	conv: pd.Float,
	f: pd.Float, // scalar frequency

	fn performC(w: [*]usize) callconv(.C) *usize {
		const self: *Self = @ptrFromInt(w[1]);
		const inlet = @as([*]pd.Sample, @ptrFromInt(w[3]))[0..w[2]];
		const conv = self.conv;
		var dphase = self.phase + unitbit32;
		var tf = TabFudge{ .d = unitbit32 };
		const normhipart = tf.i[hioffset];
		tf.d = dphase;

		for (inlet) |in| {
			tf.i[hioffset] = normhipart;
			dphase += in * conv;
			const f: pd.Sample = @floatCast(tf.d - unitbit32);
			if (in < 0) {
				if (f < self.prev) {
					self.out.bang();
				}
			} else {
				if (f > self.prev) {
					self.out.bang();
				}
			}
			self.prev = f;
			tf.d = dphase;
		}
		tf.i[hioffset] = normhipart;
		self.phase = tf.d - unitbit32;
		return &w[4];
	}

	fn dspC(self: *Self, sp: [*]*pd.Signal) callconv(.C) void {
		self.conv = -1.0 / sp[0].srate;
		pd.dsp.add(&performC, .{ self, sp[0].len, sp[0].vec });
	}

	fn ft1C(self: *Self, f: pd.Float) callconv(.C) void {
		self.phase = f;
	}

	inline fn new(f: pd.Float) !*Self {
		const self: *Self = @ptrCast(try class.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		const obj: *pd.Object = @ptrCast(self);
		self.out = try obj.outlet(&pd.s_bang);
		_ = try obj.inlet(&obj.g.pd, &pd.s_float, pd.symbol("ft1"));
		self.phase = 0;
		self.prev = 0;
		self.conv = 0;
		self.f = f;
		return self;
	}

	fn newC(f: pd.Float) callconv(.C) ?*Self {
		return new(f) catch null;
	}

	inline fn setup() !void {
		class = try pd.class(pd.symbol("metro~"), @ptrCast(&newC), null,
			@sizeOf(Self), .{}, &.{ .deffloat });

		class.doMainSignalIn(@offsetOf(Self, "f"));
		class.addMethod(@ptrCast(&dspC), pd.symbol("dsp"), &.{ .cant });
		class.addMethod(@ptrCast(&ft1C), pd.symbol("ft1"), &.{ .float });
	}
};

export fn metro_tilde_setup() void {
	MetroTilde.setup() catch {};
}
