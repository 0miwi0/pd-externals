const pd = @import("pd");

fn list(vec: []pd.Word, av: []const pd.Atom) void {
	const i = blk: {
		const i: i32 = @intFromFloat(av[0].float());
		const j: usize = @min(@max(0, @abs(i)), vec.len);
		break :blk if (i < 0) vec.len - j else j;
	};
	const n = @min(vec.len - i, av.len - 1);
	for (vec[i..i+n], av[1..1+n]) |*w, *a| {
		if (a.type == .float) {
			w.float = a.w.float;
		}
	}
}

fn floatPassive(fp: *pd.Float, av: []const pd.Atom, i: usize) void {
	if (i < av.len and av[i].type == .float) {
		fp.* = av[i].w.float;
	}
}

const Rand = extern struct {
	const Base = @import("rng.zig").Rng;
	var s_rep: *pd.Symbol = undefined;

	base: Base,
	out: *pd.Outlet,
	rep: u32, // repeat interrupt (0: disabled, >=1: allowed values in a row)
	reps: u32, // repeat count
	prev: u32, // previous index

	fn repC(self: *Rand, f: pd.Float) callconv(.C) void {
		self.rep = @intFromFloat(f);
	}

	fn printVec(self: *const Rand, vec: []pd.Word) void {
		if (vec.len == 0) {
			return pd.post.log(self, .normal, "[]", .{});
		}
		pd.post.start("[%g", .{ vec[0].float });
		for (vec[1..]) |w| {
			pd.post.start(", %g", .{ w.float });
		}
		pd.post.log(self, .normal, "]", .{});
	}

	fn extend(class: *pd.Class) !void {
		try Base.extend(class);
		class.addMethod(@ptrCast(&repC), s_rep, &.{ .float });
	}

	fn next(self: *Rand, range: pd.Float) pd.Float {
		const f: pd.Float = blk: {
			const rand = self.base.next();
			if (self.rep != 0 and self.reps >= self.rep) {
				const offset: pd.Float = @floatFromInt(self.prev + 1);
				const n = rand * (range - 1) + offset;
				break :blk if (n >= range) n - range else n;
			}
			break :blk rand * range;
		};
		const i: u32 = @intFromFloat(f);
		self.reps = if (self.prev == i) self.reps + 1 else 1;
		self.prev = i;
		return f;
	}

	fn init(self: *Rand) !void {
		self.base.init();
		self.out = try self.base.obj.outlet(&pd.s_float);
	}

	inline fn new(av: []pd.Atom) !*anyopaque {
		if (av.len == 1 and av[0].type == .symbol) {
			return try GArray.new(av[0].w.symbol);
		} else if (av.len > 2) {
			return try Array.new(av);
		} else {
			return try Range.new(av);
		}
	}

	fn newC(_: *pd.Symbol, ac: c_uint, av: [*]pd.Atom) callconv(.C) ?*anyopaque {
		return new(av[0..ac]) catch null;
	}

	inline fn setup() !void {
		s_rep = pd.symbol("rep");
		pd.addCreator(@ptrCast(&newC), pd.symbol("rand"), &.{ .gimme });
		try Range.setup();
		try Array.setup();
		try GArray.setup();
	}
};

const Range = extern struct {
	const Self = @This();
	var class: *pd.Class = undefined;

	base: Rand,
	max: pd.Float,
	min: pd.Float,

	fn printC(self: *const Self) callconv(.C) void {
		pd.post.log(self, .normal, "%g..%g", .{ self.min, self.max });
	}

	fn listC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		const vec = av[0..ac];
		floatPassive(&self.max, vec, 0);
		floatPassive(&self.min, vec, 1);
	}

	fn anythingC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		floatPassive(&self.min, av[0..ac], 0);
	}

	fn bangC(self: *Self) callconv(.C) void {
		const range = self.max - self.min;
		const f = self.base.next(@abs(range));
		self.base.out.float(@floor((if (range < 0) -f else f) + self.min));
	}

	inline fn new(av: []const pd.Atom) !*Self {
		const self: *Self = @ptrCast(try class.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		try self.base.init();

		const obj = &self.base.base.obj;
		if (av.len == 1) {
			_ = try obj.inletFloatArg(&self.max, av, 0);
		} else {
			_ = try obj.inletFloatArg(&self.min, av, 0);
			_ = try obj.inletFloatArg(&self.max, av, 1);
		}
		return self;
	}

	inline fn setup() !void {
		class = try pd.class(pd.symbol("_rand_range"), null, null,
			@sizeOf(Self), .{}, &.{});
		try Rand.extend(class);
		class.addBang(@ptrCast(&bangC));
		class.addList(@ptrCast(&listC));
		class.addAnything(@ptrCast(&anythingC));
		class.addMethod(@ptrCast(&printC), pd.symbol("print"), &.{});
	}
};

const Array = extern struct {
	const Self = @This();
	const WInlet = @import("winlet.zig").WInlet;
	var class: *pd.Class = undefined;

	base: Rand,
	win: WInlet,
	size: usize,

	fn printC(self: *const Self) callconv(.C) void {
		self.base.printVec(self.win.ptr[0..self.size]);
	}

	fn resizeC(self: *Self, f: pd.Float) callconv(.C) void {
		const n: usize = @intFromFloat(@max(1, f));
		self.win.resize(n) catch return;
		self.size = n;
	}

	fn listC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		if (ac < 2) {
			return;
		}
		list(self.win.ptr[0..self.size], av[0..ac]);
	}

	fn bangC(self: *Self) callconv(.C) void {
		const f = self.base.next(@floatFromInt(self.size));
		self.base.out.float(self.win.ptr[@intFromFloat(f)].float);
	}

	inline fn new(av: []pd.Atom) !*Self {
		const self: *Self = @ptrCast(try class.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();

		try self.base.init();

		// 3 args with a symbol in the middle creates a 2-item array (ex: 7 or 9)
		const n: usize = blk: {
			if (av.len == 3 and av[1].type != .float) {
				av[1] = av[2];
				break :blk 2;
			}
			break :blk av.len;
		};

		const obj = &self.base.base.obj;
		try self.win.init(obj, n);
		self.size = n;
		for (0..n, self.win.ptr) |i, *w| {
			_ = try obj.inletFloatArg(&w.float, av, @intCast(i));
		}
		return self;
	}

	fn freeC(self: *Self) callconv(.C) void {
		self.win.free();
	}

	inline fn setup() !void {
		class = try pd.class(pd.symbol("_rand_array"), null, @ptrCast(&freeC),
			@sizeOf(Self), .{}, &.{});
		try Rand.extend(class);
		class.addBang(@ptrCast(&bangC));
		class.addList(@ptrCast(&listC));
		class.addMethod(@ptrCast(&printC), pd.symbol("print"), &.{});
		class.addMethod(@ptrCast(&resizeC), pd.symbol("n"), &.{ .float });
	}
};

const GArray = extern struct {
	const Self = @This();
	var class: *pd.Class = undefined;

	base: Rand,
	sym: *pd.Symbol,

	fn garray(self: *const Self) ?*pd.GArray {
		return @as(*pd.GArray, @ptrCast(pd.Class.garray.*.find(self.sym) orelse {
			pd.post.err(self, "%s: no such array", .{ self.sym.name });
			return null;
		}));
	}

	fn printC(self: *const Self) callconv(.C) void {
		pd.post.start("%s (0x%x) ", .{self.sym.name, self.sym.thing});
		self.base.printVec((self.garray() orelse return).floatWords() catch return);
	}

	fn resizeC(self: *Self, f: pd.Float) callconv(.C) void {
		(self.garray() orelse return).resize(@as(c_ulong, @intFromFloat(f)));
	}

	fn listC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		if (ac < 2) {
			return;
		}
		const garr = self.garray() orelse return;
		defer garr.redraw();
		list(garr.floatWords() catch return, av[0..ac]);
	}

	fn bangC(self: *Self) callconv(.C) void {
		const vec = (self.garray() orelse return).floatWords() catch return;
		const f = self.base.next(@floatFromInt(vec.len));
		self.base.out.float(vec[@intFromFloat(f)].float);
	}

	inline fn new(s: *pd.Symbol) !*Self {
		const self: *Self = @ptrCast(try class.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		try self.base.init();
		self.sym = s;
		_ = try self.base.base.obj.inletSymbol(&self.sym);
		return self;
	}

	inline fn setup() !void {
		class = try pd.class(pd.symbol("_rand_garray"), null, null,
			@sizeOf(Self), .{}, &.{});
		try Rand.extend(class);
		class.addBang(@ptrCast(&bangC));
		class.addList(@ptrCast(&listC));
		class.addMethod(@ptrCast(&printC), pd.symbol("print"), &.{});
		class.addMethod(@ptrCast(&resizeC), pd.symbol("n"), &.{ .float });
	}
};

export fn rand_setup() void {
	Rand.setup() catch {};
}
