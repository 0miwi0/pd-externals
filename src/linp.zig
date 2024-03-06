const pd = @import("pd");
const tg = @import("toggle.zig");

const default_grain = 20;

const LinP = extern struct {
	const Self = @This();
	var class: *pd.Class = undefined;

	obj: pd.Object,
	out: [2]*pd.Outlet,
	clock: *pd.Clock,
	targettime: f64,
	prevtime: f64,
	invtime: f64,
	in1val: f64,
	grain: pd.Float,
	setval: pd.Float,
	targetval: pd.Float,
	paused: bool,
	gotinlet: bool,

	fn setPause(self: *Self, state: bool) void {
		if (tg.set(&self.paused, state)) {
			self.out[1].float(@floatFromInt(@intFromBool(self.paused)));
		}
	}

	fn tglPause(self: *Self, av: []const pd.Atom) bool {
		const changed = tg.toggle(&self.paused, av);
		if (changed) {
			self.out[1].float(@floatFromInt(@intFromBool(self.paused)));
		}
		return changed;
	}

	fn ft1C(self: *Self, f: pd.Float) callconv(.C) void {
		self.in1val = f;
		self.gotinlet = true;
	}

	fn setC(self: *Self, f: pd.Float) callconv(.C) void {
		self.clock.unset();
		self.targetval = f;
		self.setval = f;
	}

	fn freeze(self: *Self) void {
		if (pd.time() >= self.targettime) {
			self.setval = self.targetval;
		} else {
			self.setval += @floatCast(self.invtime * (pd.time() - self.prevtime)
				* (self.targetval - self.setval));
		}
		self.clock.unset();
	}

	fn stopC(self: *Self) callconv(.C) void {
		if (pd.pd_compatibilitylevel >= 48) {
			self.freeze();
		}
		self.targetval = self.setval;
		self.setPause(true);
	}

	fn pauseC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		if (!self.tglPause(av[0..ac]) or self.setval == self.targetval) {
			return;
		}

		if (self.paused) {
			self.freeze();
			self.targettime = -pd.timeSince(self.targettime);
		} else {
			const timenow = pd.time();
			const msectogo = self.targettime;
			self.targettime = pd.sysTimeAfter(msectogo);
			self.invtime = 1 / (self.targettime - timenow);
			self.prevtime = timenow;
			if (self.grain <= 0) {
				self.grain = default_grain;
			}
			self.clock.delay(if (self.grain > msectogo) msectogo else self.grain);
		}
	}

	fn tickC(self: *Self) callconv(.C) void {
		const timenow = pd.time();
		const msectogo = -pd.timeSince(self.targettime);
		if (msectogo < 1e-9) {
			self.out[0].float(self.targetval);
		} else {
			self.out[0].float(@floatCast(self.setval + self.invtime
				* (timenow - self.prevtime) * (self.targetval - self.setval)));
			if (self.grain <= 0) {
				self.grain = default_grain;
			}
			self.clock.delay(if (self.grain > msectogo) msectogo else self.grain);
		}
	}

	fn floatC(self: *Self, f: pd.Float) callconv(.C) void {
		const timenow = pd.time();
		if (self.gotinlet and self.in1val > 0) {
			if (timenow > self.targettime) {
				self.setval = self.targetval;
			} else {
				self.setval += @floatCast(self.invtime * (timenow - self.prevtime)
					* (self.targetval - self.setval));
			}
			self.prevtime = timenow;
			self.targettime = pd.sysTimeAfter(self.in1val);
			self.targetval = f;
			self.tickC();
			self.gotinlet = false;
			self.setPause(false);
			self.invtime = 1 / (self.targettime - timenow);
			if (self.grain <= 0) {
				self.grain = default_grain;
			}
			self.clock.delay(if (self.grain > self.in1val) self.in1val else self.grain);
		} else {
			self.clock.unset();
			self.targetval = f;
			self.setval = f;
			self.out[0].float(f);
		}
		self.gotinlet = false;
	}

	inline fn new(f: pd.Float, grain: pd.Float) !*Self {
		const self: *Self = @ptrCast(try class.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		self.targetval = f;
		self.setval = f;
		self.gotinlet = false;
		self.paused = false;
		self.invtime = 1;
		self.grain = grain;
		self.clock = try pd.clock(self, @ptrCast(&tickC));
		self.targettime = pd.time();
		self.prevtime = self.targettime;
		const obj = &self.obj;
		self.out[0] = try obj.outlet(&pd.s_float);
		self.out[1] = try obj.outlet(&pd.s_float);
		_ = try obj.inlet(&obj.g.pd, &pd.s_float, pd.symbol("ft1"));
		_ = try obj.inletFloat(&self.grain);
		return self;
	}

	fn newC(f: pd.Float, grain: pd.Float) callconv(.C) ?*Self {
		return new(f, grain) catch null;
	}

	fn freeC(self: *Self) callconv(.C) void {
		self.clock.free();
	}

	inline fn setup() !void {
		class = try pd.class(pd.symbol("linp"), @ptrCast(&newC), @ptrCast(&freeC),
			@sizeOf(Self), .{}, &.{ .deffloat, .deffloat });
		class.addFloat(@ptrCast(&floatC));
		class.addMethod(@ptrCast(&stopC), pd.symbol("stop"), &.{});
		class.addMethod(@ptrCast(&ft1C), pd.symbol("ft1"), &.{ .float });
		class.addMethod(@ptrCast(&setC), pd.symbol("set"), &.{ .float });
		class.addMethod(@ptrCast(&pauseC), pd.symbol("pause"), &.{ .gimme });
	}
};

export fn linp_setup() void {
	LinP.setup() catch {};
}
