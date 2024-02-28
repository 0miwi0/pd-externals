const pd = @import("pd");

const TabRead2 = extern struct {
	const Self = @This();
	const Base = @import("tab2.zig").Tab2;
	var class: *pd.Class = undefined;

	base: Base,
	onset: pd.Float,
	len: usize,

	fn performC(w: [*]usize) callconv(.C) *usize {
		const self: *Self = @ptrFromInt(w[1]);
		const out = @as([*]pd.Sample, @ptrFromInt(w[3]))[0..w[2]];
		const vec = self.base.vec orelse {
			@memset(out, 0);
			return &w[6];
		};
		const onset = self.onset;
		const len = self.len;

		const inlet2: [*]pd.Sample = @ptrFromInt(w[4]);
		const inlet1: [*]pd.Sample = @ptrFromInt(w[5]);
		for (out, inlet1, inlet2) |*o, in1, in2| {
			const findex: f64 = in1 + onset;
			var i: usize = @intFromFloat(findex);
			const frac: pd.Sample = blk: {
				if (i < 0) {
					i = 0;
					break :blk 0;
				} else if (i >= len) {
					i = len - 1;
					break :blk 1;
				}
				break :blk @floatCast(findex - @as(f64, @floatFromInt(i)));
			};
			o.* = Base.sample(vec + i, frac, in2);
		}
		return &w[6];
	}

	fn setC(self: *Self, s: *pd.Symbol) callconv(.C) void {
		self.len = self.base.setArray(s) catch return;
	}

	fn dspC(self: *Self, sp: [*]*pd.Signal) callconv(.C) void {
		self.setC(self.base.arrayname);
		pd.dsp.add(&performC, .{ self, sp[2].len, sp[2].vec, sp[1].vec, sp[0].vec });
	}

	inline fn new(arrayname: *pd.Symbol, hold: pd.Float) !*Self {
		const self: *Self = @ptrCast(try class.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		try self.base.init(arrayname, hold);

		const obj = &self.base.obj;
		_ = try obj.inletFloat(&self.onset);
		self.onset = 0;
		return self;
	}

	fn newC(arrayname: *pd.Symbol, hold: pd.Float) callconv(.C) ?*Self {
		return new(arrayname, hold) catch null;
	}

	inline fn setup() !void {
		class = try pd.class(pd.symbol("tabread2~"), @ptrCast(&newC), null,
			@sizeOf(Self), .{}, &.{ .defsymbol, .deffloat });

		Base.extend(class);
		class.addMethod(@ptrCast(&dspC), pd.symbol("dsp"), &.{ .cant });
		class.addMethod(@ptrCast(&setC), pd.symbol("set"), &.{ .symbol });
	}
};

export fn tabread2_tilde_setup() void {
	TabRead2.setup() catch {};
}
