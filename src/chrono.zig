const pd = @import("pd");

const Chrono = extern struct {
	const Self = @This();
	const Base = @import("timer.zig").Timer;
	var class: *pd.Class = undefined;

	base: Base,
	out: [2]*pd.Outlet,
	settime: f64,
	setmore: f64,
	laptime: f64,
	lapmore: f64,

	fn setTime(self: *Self) void {
		self.settime = pd.time();
		self.laptime = self.settime;
	}

	fn reset(self: *Self, paused: bool) void {
		self.base.setPause(paused);
		self.setTime();
		self.setmore = 0;
		self.lapmore = 0;
	}

	fn delayC(self: *Self, f: pd.Float) callconv(.C) void {
		self.setmore -= f;
	}

	fn bangC(self: *Self) callconv(.C) void {
		self.reset(false);
	}

	fn floatC(self: *Self, f: pd.Float) callconv(.C) void {
		self.reset(false);
		self.delayC(f);
	}

	fn listC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		self.reset(ac >= 2 and av[1].type == .float and av[1].w.float == 1);
		if (ac > 0 and av[0].type == .float) {
			self.delayC(av[0].w.float);
		}
	}

	fn bang2C(self: *const Self) callconv(.C) void {
		const result = self.setmore + if (self.base.paused) 0 else
			self.base.timeSince(self.settime);
		self.out[0].float(@floatCast(result));
	}

	fn lapC(self: *Self) callconv(.C) void {
		const result = self.lapmore + if (self.base.paused) 0 else
			self.base.timeSince(self.laptime);
		self.out[1].float(@floatCast(result));
		self.laptime = pd.time();
		self.lapmore = 0;
	}

	fn pauseC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		if (!self.base.tglPause(av[0..ac])) {
			return;
		}

		if (self.base.paused) {
			self.setmore += self.base.timeSince(self.settime);
			self.lapmore += self.base.timeSince(self.laptime);
		} else {
			self.setTime();
		}
	}

	fn tempoC(
		self: *Self, _: ?*pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		if (!self.base.paused) {
			self.setmore += self.base.timeSince(self.settime);
			self.lapmore += self.base.timeSince(self.laptime);
			self.setTime();
		}
		self.base.parseUnits(av[0..ac]);
	}

	inline fn new(av: []const pd.Atom) !*Self {
		const self: *Self = @ptrCast(try class.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		const obj = &self.base.obj;
		_ = try obj.inlet(&obj.g.pd, &pd.s_bang, pd.symbol("bang2"));
		self.out[0] = try obj.outlet(&pd.s_float);
		self.out[1] = try obj.outlet(&pd.s_float);

		try self.base.init(av);
		self.bangC();
		return self;
	}

	fn newC(_: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom) callconv(.C) ?*Self {
		return new(av[0..ac]) catch null;
	}

	inline fn setup() !void {
		class = try pd.class(pd.symbol("chrono"), @ptrCast(&newC), null,
			@sizeOf(Self), .{}, &.{ .gimme });

		class.addBang(@ptrCast(&bangC));
		class.addFloat(@ptrCast(&floatC));
		class.addList(@ptrCast(&listC));
		class.addMethod(@ptrCast(&lapC), pd.symbol("lap"), &.{});
		class.addMethod(@ptrCast(&bang2C), pd.symbol("bang2"), &.{});
		class.addMethod(@ptrCast(&delayC), pd.symbol("del"), &.{ .float });
		class.addMethod(@ptrCast(&delayC), pd.symbol("delay"), &.{ .float });
		class.addMethod(@ptrCast(&pauseC), pd.symbol("pause"), &.{ .gimme });
		class.addMethod(@ptrCast(&tempoC), pd.symbol("tempo"), &.{ .gimme });
	}
};

export fn chrono_setup() void {
	Chrono.setup() catch {};
}
