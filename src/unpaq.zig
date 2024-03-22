const pd = @import("pd");

const Unpaq = extern struct {
	const Self = @This();
	var class: *pd.Class = undefined;
	var dot: *pd.Symbol = undefined; // skips args

	const Outlet = struct {
		out: *pd.Outlet,
		type: pd.Atom.Type,
	};

	obj: pd.Object,
	ptr: [*]Outlet,
	len: usize,

	fn anythingC(
		self: *const Self, s: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		const firstarg = (s != &pd.s_list);
		const j = @intFromBool(firstarg);
		var i = @min(ac, self.len - j);
		while (i > 0) {
			i -= 1;
			const v = &self.ptr[i+j];
			const a = &av[i];
			if (v.type != .gimme and v.type != a.type) {
				continue;
			}
			switch (a.type) {
				.symbol => if (a.w.symbol != dot) {
					v.out.symbol(a.w.symbol);
				},
				.pointer => v.out.pointer(a.w.gpointer),
				else => v.out.float(a.w.float),
			}
		}
		if (firstarg and s != dot) {
			self.ptr[0].out.symbol(s);
		}
	}

	inline fn new(argv: []const pd.Atom) !*Self {
		const self: *Self = @ptrCast(try class.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		const obj = &self.obj;

		const av = if (argv.len > 0) argv else &[2]pd.Atom{
			.{ .type=.float, .w=.{ .float=0 } },
			.{ .type=.float, .w=.{ .float=0 } },
		};
		const vec = try pd.mem.alloc(Outlet, av.len);
		errdefer pd.mem.free(vec);
		self.ptr = vec.ptr;
		self.len = vec.len;

		for (vec, av) |*v, *a| {
			v.* = if (a.type == .symbol) switch (a.w.symbol.name[0]) {
				'f' => .{ .out = try obj.outlet(&pd.s_float), .type = .float },
				's' => .{ .out = try obj.outlet(&pd.s_symbol), .type = .symbol },
				'p' => .{ .out = try obj.outlet(&pd.s_pointer), .type = .pointer },
				else => .{ .out = try obj.outlet(null), .type=.gimme },
			} else .{ .out = try obj.outlet(null), .type=.gimme };
		}
		return self;
	}

	fn newC(_: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom) callconv(.C) ?*Self {
		return new(av[0..ac]) catch null;
	}

	fn freeC(self: *const Self) callconv(.C) void {
		pd.mem.free(self.ptr[0..self.len]);
	}

	inline fn setup() !void {
		dot = pd.symbol(".");
		class = try pd.class(pd.symbol("unpaq"), @ptrCast(&newC), @ptrCast(&freeC),
			@sizeOf(Self), .{}, &.{ .gimme });
		class.addAnything(@ptrCast(&anythingC));
		class.setHelpSymbol(pd.symbol("paq"));
	}
};

export fn unpaq_setup() void {
	Unpaq.setup() catch {};
}
