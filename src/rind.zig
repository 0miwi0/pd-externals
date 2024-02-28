const pd = @import("pd");

pub const Rind = extern struct {
	const Self = @This();
	const Base = @import("rng.zig").Rng;
	var class: *pd.Class = undefined;

	base: Base,
	out: *pd.Outlet,
	min: pd.Float,
	max: pd.Float,

	fn printC(self: *const Self) callconv(.C) void {
		pd.post.log(self, .normal, "%g..%g", .{ self.min, self.max });
	}

	fn bangC(self: *Self) callconv(.C) void {
		const min = self.min;
		const range = self.max - min;
		self.out.float(self.base.next() * range + min);
	}

	fn listC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		if (ac >= 2 and av[1].type == .float) {
			self.min = av[1].w.float;
		}
		if (ac >= 1 and av[0].type == .float) {
			self.max = av[0].w.float;
		}
	}

	fn anythingC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		if (ac >= 1 and av[0].type == .float) {
			self.min = av[0].w.float;
		}
	}

	inline fn new(av: []const pd.Atom) !*Self {
		const self: *Self = @ptrCast(try class.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		self.base.init();

		const obj = &self.base.obj;
		self.out = try obj.outlet(&pd.s_float);

		switch (av.len) {
			1 => _ = try obj.inletFloatArg(&self.max, av, 0),
			0 => {
				_ = try obj.inletFloat(&self.min);
				_ = try obj.inletFloat(&self.max);
				self.max = 1;
			},
			else => {
				_ = try obj.inletFloatArg(&self.min, av, 0);
				_ = try obj.inletFloatArg(&self.max, av, 1);
			}
		}
		return self;
	}

	fn newC(_: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom) callconv(.C) ?*Self {
		return new(av[0..ac]) catch null;
	}

	inline fn setup() !void {
		class = try pd.class(pd.symbol("rind"), @ptrCast(&newC), null,
			@sizeOf(Self), .{}, &.{ .gimme });

		try Base.extend(class);
		class.addBang(@ptrCast(&bangC));
		class.addList(@ptrCast(&listC));
		class.addAnything(@ptrCast(&anythingC));
		class.addMethod(@ptrCast(&printC), pd.symbol("print"), &.{});
	}
};

export fn rind_setup() void {
	Rind.setup() catch {};
}
