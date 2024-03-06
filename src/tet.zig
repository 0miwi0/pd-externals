const pd = @import("pd");

pub fn Tet(T: type) type { return extern struct {
	const Self = @This();
	pub var class: *pd.Class = undefined;
	const setK = T.setK;
	const setMin = T.setMin;

	obj: pd.Object,
	out: *pd.Outlet,
	k: f64,         // slope
	min: f64,       // frequency at index 0
	ref: pd.Float,  // reference pitch
	tet: pd.Float,  // number of tones

	fn refC(self: *Self, f: pd.Float) callconv(.C) void {
		self.ref = if (f == 0) 1 else f;
		self.setMin();
	}

	fn tetC(self: *Self, f: pd.Float) callconv(.C) void {
		self.tet = if (f == 0) 1 else f;
		self.setK();
		self.setMin();
	}

	fn list(self: *Self, j: u32, av: []const pd.Atom) void {
		const props = [_]*pd.Float{ &self.ref, &self.tet };
		const n = @min(av.len, props.len - j);
		for (0..n) |i| {
			if (av[i].type == .float) {
				props[i + j].* = av[i].w.float;
			}
		}
		self.setK();
		self.setMin();
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
		const obj = &self.obj;
		self.out = try obj.outlet(&pd.s_float);
		_ = try obj.inlet(&obj.g.pd, &pd.s_float, pd.symbol("ref"));
		_ = try obj.inlet(&obj.g.pd, &pd.s_float, pd.symbol("tet"));

		self.ref = if (av.len > 0 and av[0].type == .float) av[0].w.float else 440;
		self.tet = if (av.len > 1 and av[1].type == .float) av[1].w.float else 12;
		self.setK();
		self.setMin();
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
		class.addMethod(@ptrCast(&refC), pd.symbol("ref"), &.{ .float });
		class.addMethod(@ptrCast(&tetC), pd.symbol("tet"), &.{ .float });
		class.setHelpSymbol(pd.symbol("tet"));
	}
};}
