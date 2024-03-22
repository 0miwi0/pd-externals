const pd = @import("pd");

var dot: *pd.Symbol = undefined; // skips args

const Paq = extern struct {
	const Self = @This();
	var class: *pd.Class = undefined;

	obj: pd.Object,
	ptr: [*]pd.Atom,
	len: usize,

	fn floatC(self: *Self, f: pd.Float) callconv(.C) void {
		self.ptr[0] = .{ .type=.float, .w=.{ .float=f } };
	}
	fn symbolC(self: *Self, s: *pd.Symbol) callconv(.C) void {
		self.ptr[0] = .{ .type=.symbol, .w=.{ .symbol=s } };
	}
	fn pointerC(self: *Self, p: *pd.GPointer) callconv(.C) void {
		self.ptr[0] = .{ .type=.pointer, .w=.{ .gpointer=p } };
	}

	fn anythingC(
		self: *Self, s: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		const firstarg = (s != &pd.s_list);
		if (firstarg and s != dot) {
			self.ptr[0] = .{ .type=.symbol, .w=.{ .symbol=s } };
		}
		const i = @intFromBool(firstarg);
		const n = @min(ac, self.len - i);
		for (self.ptr[i..i+n], av[0..n]) |*v, *a| {
			if (!(a.type == .symbol and a.w.symbol == dot)) {
				v.* = a.*;
			}
		}
	}

	fn new(cls: *pd.Class, vec: []pd.Atom) !*Self {
		const self: *Self = @ptrCast(try cls.pd());
		self.ptr = vec.ptr;
		self.len = vec.len;
		return self;
	}

	inline fn setup() !void {
		dot = pd.symbol(".");
		class = try pd.class(pd.symbol("_paq_pxy"), null, null,
			@sizeOf(Self), .{ .bare=true, .no_inlet=true }, &.{});
		class.addFloat(@ptrCast(&Self.floatC));
		class.addSymbol(@ptrCast(&Self.symbolC));
		class.addPointer(@ptrCast(&Self.pointerC));
		class.addAnything(@ptrCast(&Self.anythingC));
		try Owner.setup();
	}
};

const Owner = extern struct {
	const Self = @This();
	var class: *pd.Class = undefined;

	base: Paq,
	out: *pd.Outlet,
	ins: [*]*Paq,

	fn bangC(self: *const Self) callconv(.C) void {
		const vec = pd.mem.dupe(pd.Atom, self.base.ptr[0..self.base.len])
			catch return pd.post.do("Out of memory", .{});
		defer pd.mem.free(vec);
		self.out.list(&pd.s_list, vec);
	}

	fn floatC(self: *Self, f: pd.Float) callconv(.C) void {
		self.base.floatC(f);
		self.bangC();
	}
	fn symbolC(self: *Self, s: *pd.Symbol) callconv(.C) void {
		self.base.symbolC(s);
		self.bangC();
	}
	fn pointerC(self: *Self, p: *pd.GPointer) callconv(.C) void {
		self.base.pointerC(p);
		self.bangC();
	}
	fn anythingC(
		self: *Self, s: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		self.base.anythingC(s, ac, av);
		self.bangC();
	}

	inline fn new(argv: []const pd.Atom) !*Self {
		const av = if (argv.len > 0) argv else &[2]pd.Atom{
			.{ .type=.float, .w=.{ .float=0 } },
			.{ .type=.float, .w=.{ .float=0 } },
		};
		const vec = try pd.mem.alloc(pd.Atom, av.len);
		errdefer pd.mem.free(vec);
		vec[0] = av[0];

		const self: *Self = @ptrCast(try Paq.new(class, vec));
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		const obj = &self.base.obj;
		self.out = try obj.outlet(&pd.s_list);

		const ins = try pd.mem.alloc(*Paq, av.len - 1);
		errdefer pd.mem.free(ins);
		self.ins = ins.ptr;

		var n: u32 = 0; // proxies allocated
		errdefer for (ins[0..n]) |pxy| {
			@as(*pd.Pd, @ptrCast(pxy)).free();
		};
		while (n < ins.len) {
			const i = n + 1;
			vec[i] = av[i];
			ins[n] = try Paq.new(Paq.class, vec[i..]);
			_ = try obj.inlet(@ptrCast(ins[n]), null, null);
			n = i;
		}
		return self;
	}

	fn newC(_: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom) callconv(.C) ?*Self {
		return new(av[0..ac]) catch null;
	}

	fn freeC(self: *const Self) callconv(.C) void {
		const paq = self.base;
		const n = paq.len - 1;
		for (self.ins[0..n]) |pxy| {
			@as(*pd.Pd, @ptrCast(pxy)).free();
		}
		pd.mem.free(self.ins[0..n]);
		pd.mem.free(paq.ptr[0..paq.len]);
	}

	inline fn setup() !void {
		class = try pd.class(pd.symbol("paq"), @ptrCast(&newC), @ptrCast(&freeC),
			@sizeOf(Self), .{}, &.{ .gimme });
		class.addBang(@ptrCast(&bangC));
		class.addFloat(@ptrCast(&floatC));
		class.addSymbol(@ptrCast(&symbolC));
		class.addPointer(@ptrCast(&pointerC));
		class.addAnything(@ptrCast(&anythingC));
	}
};

export fn paq_setup() void {
	Paq.setup() catch {};
}
