const pd = @import("pd");

const Hsv = extern struct {
	const Self = @This();
	var class: *pd.Class = undefined;

	obj: pd.Object,
	out: *pd.Outlet,
	h: pd.Float,
	s: pd.Float,
	v: pd.Float,

	fn bangC(self: *const Self) callconv(.C) void {
		var r: pd.Float = undefined;
		var g: pd.Float = undefined;
		var b: pd.Float = undefined;

		const s = self.s;
		const v = self.v;
		if (s <= 0) {
			// Achromatic case
			r = v;
			g = v;
			b = v;
		} else {
			const h = @mod(self.h, 360) / 60;
			const i: i32 = @intFromFloat(h);

			const f = h - @as(pd.Float, @floatFromInt(i));
			const p = v * (1 - s);
			const q = v * (1 - (s * f));
			const t = v * (1 - (s * (1 - f)));

			switch (i) {
				0 =>    { r = v;  g = t;  b = p; },
				1 =>    { r = q;  g = v;  b = p; },
				2 =>    { r = p;  g = v;  b = t; },
				3 =>    { r = p;  g = q;  b = v; },
				4 =>    { r = t;  g = p;  b = v; },
				5 =>    { r = v;  g = p;  b = q; },
				else => { r = v;  g = v;  b = v; },
			}
		}
		const R = @as(u24, @intFromFloat(r * 0xff)) << 16;
		const G = @as(u24, @intFromFloat(g * 0xff)) << 8;
		const B = @as(u24, @intFromFloat(b * 0xff));
		self.out.float(@floatFromInt(R + G + B));
	}

	fn floatC(self: *Self, f: pd.Float) callconv(.C) void {
		self.h = f;
		self.bangC();
	}

	inline fn new(h: pd.Float, s: pd.Float, v: pd.Float) !*Self {
		const self: *Self = @ptrCast(try class.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		self.h = h;
		self.s = s;
		self.v = v;

		const obj = &self.obj;
		self.out = try obj.outlet(&pd.s_float);
		_ = try obj.inletFloat(&self.s);
		_ = try obj.inletFloat(&self.v);
		return self;
	}

	fn newC(h: pd.Float, s: pd.Float, v: pd.Float) callconv(.C) ?*Self {
		return new(h, s, v) catch null;
	}

	inline fn setup() !void {
		class = try pd.class(pd.symbol("hsv"), @ptrCast(&newC), null,
			@sizeOf(Self), .{}, &.{ .deffloat, .deffloat, .deffloat });

		class.addBang(@ptrCast(&bangC));
		class.addFloat(@ptrCast(&floatC));
	}
};

export fn hsv_setup() void {
	Hsv.setup() catch {};
}
