const pd = @import("pd");
const UnFloat = @import("bitfloat.zig").UnFloat;

const FlDec = extern struct {
	const Self = @This();
	var class: *pd.Class = undefined;

	obj: pd.Object,
	out: [3]*pd.Outlet,
	f: pd.Float,

	fn printC(self: *const Self) callconv(.C) void {
		pd.post.log(self, .normal, "f=%g", .{ self.f });
	}

	fn setC(self: *Self, f: pd.Float) callconv(.C) void {
		self.f = f;
	}

	fn bangC(self: *const Self) callconv(.C) void {
		const uf: UnFloat = .{ .f = self.f };
		self.out[2].float(@floatFromInt(uf.b.s));
		self.out[1].float(@floatFromInt(uf.b.e));
		self.out[0].float(@floatFromInt(uf.b.m));
	}

	fn floatC(self: *Self, f: pd.Float) callconv(.C) void {
		self.f = f;
		self.bangC();
	}

	inline fn new(f: pd.Float) !*Self {
		const self: *Self = @ptrCast(try class.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		const obj = &self.obj;
		self.out[0] = try obj.outlet(&pd.s_float);
		self.out[1] = try obj.outlet(&pd.s_float);
		self.out[2] = try obj.outlet(&pd.s_float);
		_ = try obj.inlet(&obj.g.pd, &pd.s_float, pd.symbol("set"));
		self.setC(f);
		return self;
	}

	fn newC(f: pd.Float) callconv(.C) ?*Self {
		return new(f) catch null;
	}

	inline fn setup() !void {
		class = try pd.class(pd.symbol("fldec"), @ptrCast(&newC), null,
			@sizeOf(Self), .{}, &.{ .deffloat });

		class.addBang(@ptrCast(&bangC));
		class.addFloat(@ptrCast(&floatC));
		class.addMethod(@ptrCast(&printC), pd.symbol("print"), &.{});
		class.addMethod(@ptrCast(&setC), pd.symbol("set"), &.{ .float });
		class.setHelpSymbol(pd.symbol("flenc"));
	}
};

export fn fldec_setup() void {
	FlDec.setup() catch {};
}
