const pd = @import("pd");

const DelP = extern struct {
	const Self = @This();
	const Base = @import("timer.zig").Timer;
	var class: *pd.Class = undefined;

	base: Base,
	out: [2]*pd.Outlet,
	clock: *pd.Clock,
	deltime: f64,
	settime: f64,
	setmore: f64,

	fn timeoutC(self: *const Self) callconv(.C) void {
		self.out[0].bang();
	}

	fn delayC(self: *Self, f: pd.Float) callconv(.C) void {
		self.setmore -= f;
		if (!self.base.paused) {
			self.clock.unset();
			self.setmore += self.base.timeSince(self.settime);
			self.settime = pd.time();
			if (self.setmore < 0) {
				self.clock.delay(-self.setmore);
			}
		}
	}

	fn timeC(self: *const Self) callconv(.C) void {
		const result = self.setmore + if (self.base.paused) 0 else
			self.base.timeSince(self.settime);
		self.out[1].float(@floatCast(result));
	}

	fn pauseC(
		self: *Self, _: ?*pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		if (!self.base.tglPause(av[0..ac])) {
			return;
		}

		if (self.base.paused) {
			self.clock.unset();
			self.setmore += self.base.timeSince(self.settime);
		} else {
			self.settime = pd.time();
			if (self.setmore < 0) {
				self.clock.delay(-self.setmore);
			}
		}
	}

	fn stopC(self: *Self) callconv(.C) void {
		var a = pd.Atom{ .type = .float, .w = .{ .float = 1 } };
		self.pauseC(null, 1, @ptrCast(&a));
	}

	fn tempoC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		if (!self.base.paused) {
			self.setmore += self.base.timeSince(self.settime);
			self.settime = pd.time();
		}
		self.base.parseUnits(av[0..ac]);
		self.clock.setUnit(self.base.unit, self.base.in_samples);
	}

	fn ft1C(self: *Self, f: pd.Float) callconv(.C) void {
		self.deltime = @max(0, f);
	}

	fn reset(self: *Self, paused: bool) void {
		self.base.setPause(paused);
		if (paused) {
			self.clock.unset();
		} else {
			self.clock.delay(self.deltime);
		}
		self.settime = pd.time();
		self.setmore = -self.deltime;
	}

	fn bangC(self: *Self) callconv(.C) void {
		self.reset(false);
	}

	fn floatC(self: *Self, f: pd.Float) callconv(.C) void {
		self.deltime = @max(0, f);
		self.reset(false);
	}

	fn listC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		if (ac >= 1 and av[0].type == .float) {
			self.ft1C(av[0].w.float);
		}
		self.reset(ac >= 2 and av[1].type == .float and av[1].w.float == 1);
	}

	fn anythingC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		self.reset(ac >= 1 and av[0].type == .float and av[0].w.float == 1);
	}

	inline fn new(av: []const pd.Atom) !*Self {
		const self: *Self = @ptrCast(try class.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		const obj = &self.base.obj;
		_ = try obj.inlet(&obj.g.pd, &pd.s_float, pd.symbol("ft1"));
		self.out[0] = try obj.outlet(&pd.s_bang);
		self.out[1] = try obj.outlet(&pd.s_float);

		self.clock = try pd.clock(self, @ptrCast(&timeoutC));
		self.settime = pd.time();

		var vec = av;
		if (vec.len >= 1 and vec[0].type == .float) {
			self.ft1C(vec[0].w.float);
			vec = vec[1..];
		}
		try self.base.init(vec);
		self.clock.setUnit(self.base.unit, self.base.in_samples);
		return self;
	}

	fn newC(_: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom) callconv(.C) ?*Self {
		return new(av[0..ac]) catch null;
	}

	fn freeC(self: *const Self) callconv(.C) void {
		self.clock.free();
	}

	inline fn setup() !void {
		class = try pd.class(pd.symbol("delp"), @ptrCast(&newC), @ptrCast(&freeC),
			@sizeOf(Self), .{}, &.{ .gimme });

		class.addBang(@ptrCast(&bangC));
		class.addFloat(@ptrCast(&floatC));
		class.addList(@ptrCast(&listC));
		class.addAnything(@ptrCast(&anythingC));
		class.addMethod(@ptrCast(&stopC), pd.symbol("stop"), &.{});
		class.addMethod(@ptrCast(&timeC), pd.symbol("time"), &.{});
		class.addMethod(@ptrCast(&ft1C), pd.symbol("ft1"), &.{ .float });
		class.addMethod(@ptrCast(&delayC), pd.symbol("del"), &.{ .float });
		class.addMethod(@ptrCast(&delayC), pd.symbol("delay"), &.{ .float });
		class.addMethod(@ptrCast(&pauseC), pd.symbol("pause"), &.{ .gimme });
		class.addMethod(@ptrCast(&tempoC), pd.symbol("tempo"), &.{ .gimme });
	}
};

export fn delp_setup() void {
	DelP.setup() catch {};
}
