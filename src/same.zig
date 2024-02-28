const pd = @import("pd");

const Same = extern struct {
	const Self = @This();
	var class: *pd.Class = undefined;

	obj: pd.Object,
	out: [2]*pd.Outlet,
	f: pd.Float,

	fn bangC(self: *const Self) callconv(.C) void {
		self.out[0].float(self.f);
	}

	fn floatC(self: *Self, f: pd.Float) callconv(.C) void {
		if (self.f != f) {
			self.f = f;
			self.out[0].float(f);
		} else {
			self.out[1].float(f);
		}
	}

	fn setC(self: *Self, f: pd.Float) callconv(.C) void {
		self.f = f;
	}

	inline fn new(f: pd.Float) !*Self {
		const self: *Self = @ptrCast(try class.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		self.f = f;

		const obj = &self.obj;
		self.out[0] = try obj.outlet(&pd.s_float);
		self.out[1] = try obj.outlet(&pd.s_float);
		return self;
	}

	fn newC(f: pd.Float) callconv(.C) ?*Self {
		return new(f) catch null;
	}

	inline fn setup() !void {
		class = try pd.class(pd.symbol("same"), @ptrCast(&newC), null,
			@sizeOf(Self), .{}, &.{ .deffloat });

		class.addBang(@ptrCast(&bangC));
		class.addFloat(@ptrCast(&floatC));
		class.addMethod(@ptrCast(&setC), pd.symbol("set"), &.{ .deffloat });
	}
};

export fn same_setup() void {
	Same.setup() catch {};
}
