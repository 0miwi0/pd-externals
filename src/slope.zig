const pd = @import("pd");

pub fn floatArgDef(av: []const pd.Atom, i: usize, def: pd.Float) pd.Float {
	return if (i < av.len and av[i].type == .float) av[i].w.float else def;
}

pub fn Slope(T: type) type { return extern struct {
	const Self = @This();
	var class: *pd.Class = undefined;
	const setK: fn(*Self) void = T.setK;

	obj: pd.Object,
	out: *pd.Outlet,
	min: f64,
	max: f64,
	run: f64,
	k: f64,
	log: bool,

	pub fn minmax(self: *Self) void {
		var min = self.min;
		var max = self.max;
		if (min == 0 and max == 0) {
			max = 1;
		}
		if (max > 0) {
			if (min <= 0) {
				min = 0.01 * max;
			}
		} else {
			if (min > 0) {
				max = 0.01 * min;
			}
		}
		self.min = min;
		self.max = max;
	}

	fn minC(self: *Self, f: pd.Float) callconv(.C) void {
		self.min = f;
		self.setK();
	}

	fn maxC(self: *Self, f: pd.Float) callconv(.C) void {
		self.max = f;
		self.setK();
	}

	fn runC(self: *Self, f: pd.Float) callconv(.C) void {
		self.run = f;
		self.setK();
	}

	fn logC(self: *Self, f: pd.Float) callconv(.C) void {
		self.log = (f != 0);
		self.setK();
	}

	fn list(self: *Self, j: u32, av: []const pd.Atom) void {
		const props = [_]*f64{ &self.min, &self.max, &self.run };
		const n = @min(av.len, props.len - j);
		for (props[j..j+n], av[0..n]) |p, *a| {
			if (a.type == .float) {
				p.* = a.w.float;
			}
		}
		self.setK();
	}

	fn listC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		self.list(0, av[0..ac]);
	}

	fn anythingC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		self.list(1, av[0..ac]);
	}

	inline fn new(av: []const pd.Atom) !*Self {
		const self: *Self = @ptrCast(try class.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		const obj: *pd.Object = &self.obj;
		self.out = try obj.outlet(&pd.s_float);
		_ = try obj.inlet(&obj.g.pd, &pd.s_float, pd.symbol("min"));
		_ = try obj.inlet(&obj.g.pd, &pd.s_float, pd.symbol("max"));
		_ = try obj.inlet(&obj.g.pd, &pd.s_float, pd.symbol("run"));

		self.log = (av.len > 0 and av[0].type == .symbol
			and av[0].w.symbol == pd.symbol("log"));
		const i = @intFromBool(self.log);
		const vec = av[i..];

		self.min = if (vec.len == 1) 0 else floatArgDef(vec, 0, 0);
		self.max = floatArgDef(vec, if (vec.len == 1) 0 else 1, 1);
		self.run = floatArgDef(vec, 2, 1);
		self.setK();

		return self;
	}

	pub fn newC(_: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom) callconv(.C) ?*Self {
		return new(av[0..ac]) catch null;
	}

	pub inline fn setup(s: *pd.Symbol, fmet: pd.Method) !void {
		class = try pd.class(s, @ptrCast(&newC), null,
			@sizeOf(Self), .{}, &.{ .gimme });
		class.addFloat(fmet);
		class.addList(@ptrCast(&listC));
		class.addAnything(@ptrCast(&anythingC));
		class.addMethod(@ptrCast(&minC), pd.symbol("min"), &.{ .float });
		class.addMethod(@ptrCast(&maxC), pd.symbol("max"), &.{ .float });
		class.addMethod(@ptrCast(&runC), pd.symbol("run"), &.{ .float });
		class.addMethod(@ptrCast(&logC), pd.symbol("log"), &.{ .float });
		class.setHelpSymbol(pd.symbol("slope"));
	}
};}
