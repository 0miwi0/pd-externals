const pd = @import("pd");
const bf = @import("bitfloat.zig");

const FlEnc = extern struct {
	const Self = @This();
	var class: *pd.Class = undefined;

	obj: pd.Object,
	out: *pd.Outlet,
	uf: bf.UnFloat,

	fn printC(self: *const Self) callconv(.C) void {
		const m: bf.uf = self.uf.b.m;
		const e: bf.uf = self.uf.b.e;
		const s: bf.uf = self.uf.b.s;
		pd.post.log(self, .normal, "m=0x%x e=%u s=%u u=%u", .{ m, e, s, self.uf.u });
	}

	fn mantissaC(self: *Self, f: pd.Float) callconv(.C) void {
		self.uf.b.m = @intFromFloat(f);
	}

	fn exponentC(self: *Self, f: pd.Float) callconv(.C) void {
		self.uf.b.e = @intFromFloat(f);
	}

	fn signC(self: *Self, f: pd.Float) callconv(.C) void {
		self.uf.b.s = @intFromFloat(f);
	}

	fn intC(self: *Self, f: pd.Float) callconv(.C) void {
		self.uf = .{ .u = @intFromFloat(f) };
	}

	fn f1C(self: *Self, f: pd.Float) callconv(.C) void {
		self.uf = .{ .f = f };
	}

	fn bangC(self: *const Self) callconv(.C) void {
		self.out.float(self.uf.f);
	}

	fn floatC(self: *Self, f: pd.Float) callconv(.C) void {
		self.mantissaC(f);
		self.bangC();
	}

	fn set(self: *Self, offset: u32, av: []const pd.Atom) void {
		if (offset == 0 and av.len > 0 and av[0].type == .float) {
			self.uf.b.m = @intFromFloat(av[0].w.float);
		}
		if (av.len > 1 and av[1 - offset].type == .float) {
			self.uf.b.e = @intFromFloat(av[1 - offset].w.float);
		}
		if (av.len > 2 and av[2 - offset].type == .float) {
			self.uf.b.s = @intFromFloat(av[2 - offset].w.float);
		}
	}

	fn setC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		self.set(0, av[0..ac]);
	}

	fn listC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		self.set(0, av[0..ac]);
		self.bangC();
	}

	fn anythingC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		self.set(1, av[0..ac]);
		self.bangC();
	}

	inline fn new(av: []const pd.Atom) !*Self {
		const self: *Self = @ptrCast(try class.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		const obj = &self.obj;
		self.out = try obj.outlet(&pd.s_float);
		_ = try obj.inlet(&obj.g.pd, &pd.s_float, pd.symbol("e"));
		_ = try obj.inlet(&obj.g.pd, &pd.s_float, pd.symbol("s"));
		self.set(0, av);
		return self;
	}

	fn newC(_: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom) callconv(.C) ?*Self {
		return new(av[0..ac]) catch null;
	}

	inline fn setup() !void {
		class = try pd.class(pd.symbol("flenc"), @ptrCast(&newC), null,
			@sizeOf(Self), .{}, &.{ .gimme });

		class.addBang(@ptrCast(&bangC));
		class.addFloat(@ptrCast(&floatC));
		class.addList(@ptrCast(&listC));
		class.addAnything(@ptrCast(&anythingC));
		class.addMethod(@ptrCast(&printC), pd.symbol("print"), &.{});
		class.addMethod(@ptrCast(&mantissaC), pd.symbol("m"), &.{ .float });
		class.addMethod(@ptrCast(&exponentC), pd.symbol("e"), &.{ .float });
		class.addMethod(@ptrCast(&signC), pd.symbol("s"), &.{ .float });
		class.addMethod(@ptrCast(&f1C), pd.symbol("f"), &.{ .float });
		class.addMethod(@ptrCast(&intC), pd.symbol("u"), &.{ .float });
		class.addMethod(@ptrCast(&setC), pd.symbol("set"), &.{ .gimme });
	}
};

export fn flenc_setup() void {
	FlEnc.setup() catch {};
}
