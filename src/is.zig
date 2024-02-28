const pd = @import("pd");

const Proxy = extern struct {
	const Self = @This();
	var class: *pd.Class = undefined;

	obj: pd.Object,
	owner: *Is,

	fn anythingC(
		self: *const Self, s: *pd.Symbol, _: u32, _: [*]const pd.Atom,
	) callconv(.C) void {
		self.owner.type = s;
	}

	inline fn new(owner: *Is) !*Self {
		const self: *Self = @ptrCast(try class.pd());
		self.owner = owner;
		owner.proxy = self;
		return self;
	}

	inline fn setup() !void {
		class = try pd.class(pd.symbol("_is_pxy"), null, null,
			@sizeOf(Self), .{ .bare=true, .no_inlet=true }, &.{});
		class.addAnything(@ptrCast(&anythingC));
	}
};

const Is = extern struct {
	const Self = @This();
	var class: *pd.Class = undefined;

	obj: pd.Object,
	out: *pd.Outlet,
	type: *pd.Symbol,
	proxy: *Proxy,

	fn printC(self: *const Self) callconv(.C) void {
		pd.post.log(self, .normal, "%s", .{ self.type.name });
	}

	fn bangC(self: *const Self) callconv(.C) void {
		self.out.float(if (self.type == &pd.s_bang) 1.0 else 0.0);
	}

	fn anythingC(
		self: *const Self, s: *pd.Symbol, ac: c_uint, _: [*]const pd.Atom,
	) callconv(.C) void {
		self.out.float(if (self.type == (if (ac > 0) s else &pd.s_symbol)) 1.0 else 0.0);
	}

	fn setC(self: *Self, s: *pd.Symbol) callconv(.C) void {
		self.type = s;
	}

	inline fn new(s: *pd.Symbol) !*Self {
		const self: *Self = @ptrCast(try class.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		const proxy = try Proxy.new(self);
		errdefer @as(*pd.Pd, @ptrCast(proxy)).free();

		const obj = &self.obj;
		self.out = try obj.outlet(&pd.s_float);
		_ = try obj.inlet(@ptrCast(proxy), null, null);
		self.type = if (s != &pd.s_) s else &pd.s_float;
		return self;
	}

	fn newC(s: *pd.Symbol) callconv(.C) ?*Self {
		return new(s) catch null;
	}

	fn freeC(self: *const Self) callconv(.C) void {
		@as(*pd.Pd, @ptrCast(self.proxy)).free();
	}

	inline fn setup() !void {
		class = try pd.class(pd.symbol("is"), @ptrCast(&newC), @ptrCast(&freeC),
			@sizeOf(Self), .{}, &.{ .defsymbol });

		class.addBang(@ptrCast(&bangC));
		class.addAnything(@ptrCast(&anythingC));
		class.addMethod(@ptrCast(&printC), pd.symbol("print"), &.{});
		class.addMethod(@ptrCast(&setC), pd.symbol("set"), &.{ .symbol });
		try Proxy.setup();
	}
};

export fn is_setup() void {
	Is.setup() catch {};
}
