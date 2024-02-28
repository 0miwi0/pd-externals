const pd = @import("pd");

const Has = extern struct {
	const Self = @This();
	var class: *pd.Class = undefined;

	obj: pd.Object,
	out: *pd.Outlet,
	atom: pd.Atom,

	fn bangC(self: *const Self) callconv(.C) void {
		const atom = self.atom;
		self.out.float(
			if (atom.type == .symbol and atom.w.symbol == &pd.s_bang) 1.0 else 0.0);
	}

	fn listC(
		self: *const Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		self.out.float(blk: {
			const atom = self.atom;
			for (av[0..ac]) |*a| {
				if (a.type == atom.type) {
					if ((atom.type == .float and a.w.float == atom.w.float)
					 or a.w.symbol == atom.w.symbol) {
						break :blk 1;
					}
				}
			}
			break :blk 0;
		});
	}

	fn setC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom
	) callconv(.C) void {
		if (ac >= 1) {
			self.atom = av[0];
		}
	}

	inline fn new(av: []const pd.Atom) !*Self {
		const self: *Self = @ptrCast(try class.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		const obj = &self.obj;
		self.out = try obj.outlet(&pd.s_float);
		_ = try obj.inlet(&obj.g.pd, &pd.s_list, pd.symbol("set"));
		self.atom = if (av.len > 0) av[0] else .{ .type = .float, .w = .{.float = 0} };
		return self;
	}

	fn newC(_: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom) callconv(.C) ?*Self {
		return new(av[0..ac]) catch null;
	}

	inline fn setup() !void {
		class = try pd.class(pd.symbol("has"), @ptrCast(&newC), null,
			@sizeOf(Self), .{}, &.{ .gimme });

		class.addBang(@ptrCast(&bangC));
		class.addList(@ptrCast(&listC));
		class.addMethod(@ptrCast(&setC), pd.symbol("set"), &.{ .gimme });
	}
};

export fn has_setup() void {
	Has.setup() catch {};
}
