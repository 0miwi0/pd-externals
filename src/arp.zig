const pd = @import("pd");
const libc = @cImport({ @cInclude("stdlib.h"); });

fn fParse(s: [*:0]const u8, ep: ?*[*:0]u8) ?pd.Float {
	var end: [*c]u8 = undefined;
	const f = libc.strtof(s, &end);
	if (ep) |e| {
		e.* = end;
	}
	return if (end != s) f else null;
}

fn iParse(s: [*:0]const u8, ep: ?*[*:0]u8) ?i32 {
	var end: [*c]u8 = undefined;
	const i: i32 = @intCast(libc.strtol(s, &end, 10));
	if (ep) |e| {
		e.* = end;
	}
	return if (end != s) i else null;
}

fn onset(i: i32, len: usize) usize {
	const j: u32 = @min(@max(0, @abs(i)), len);
	return if (i < 0) len - j else j;
}

const Op = ?*const fn(pd.Float, pd.Float) pd.Float;
fn opPlus(f1: pd.Float, f2: pd.Float)  pd.Float { return f1 + f2; }
fn opMinus(f1: pd.Float, f2: pd.Float) pd.Float { return f1 - f2; }
fn opTimes(f1: pd.Float, f2: pd.Float) pd.Float { return f1 * f2; }
fn opOver(f1: pd.Float, f2: pd.Float)  pd.Float { return if (f2 == 0) 0 else f1 / f2; }
var ops = [_]Op{null} ** 128;

fn opSetup() void {
	ops['+'] = opPlus;
	ops['^'] = opPlus;
	ops['-'] = opMinus;
	ops['v'] = opMinus;
	ops['*'] = opTimes;
	ops['/'] = opOver;
}

const Arp = extern struct {
	obj: pd.Object,
	out: [2]*pd.Outlet,
	oct: pd.Float,   // # of semitones per octave

	fn octC(self: *Arp, f: pd.Float) callconv(.C) void {
		self.oct = f;
	}

	fn printVec(self: *const Arp, vec: []const pd.Word) void {
		pd.post.start("[%g", .{ vec[0].float });
		for (vec[1..]) |w| {
			pd.post.start(", %g", .{ w.float });
		}
		pd.post.log(self, .normal, "]", .{});
	}

	fn init(self: *Arp) !void {
		self.oct = 12;
		const obj = &self.obj;
		self.out[0] = try obj.outlet(&pd.s_float);
		self.out[1] = try obj.outlet(&pd.s_list);
	}

	fn interval(self: *const Arp, vec: []const pd.Word, f: pd.Float) pd.Float {
		const g = @floor(f);
		const num: i32 = @intFromFloat(g);
		const den: i32 = @intCast(vec.len);
		const quo = @divFloor(num, den);
		var i: u32 = @intCast(num - den * quo);

		const oct = self.oct * @as(pd.Float, @floatFromInt(quo));
		const note = oct + if (i == 0) 0 else vec[i].float;
		const frac = f - g;
		if (frac == 0) {
			return note;
		}
		i += 1;
		const next = oct + if (i < vec.len) vec[i].float else self.oct;
		return (next - note) * frac + note;
	}

	fn list(self: *const Arp, vec: []pd.Word, av: []const pd.Atom, on: i32) void {
		const temp = pd.mem.dupe(pd.Word, vec) catch return; // unchanged values
		defer pd.mem.free(temp);

		var i = onset(on, vec.len);
		for (av[0..@min(vec.len - i, av.len)]) |*atom| {
			const w = &vec[i];
			if (atom.type == .float) {
				w.float = atom.w.float;
			} else {
				var s = atom.w.symbol.name;
				const n = blk: { // inner arg count
					var rem = vec.len - i;
					var end: [*:0]u8 = undefined;
					if (iParse(s, &end)) |j| {
						s = end;
						rem = onset(j, rem);
					}
					break :blk rem;
				};
				const c = s[0];
				if (ops[c]) |op| {
					if (c == s[1]) { // ++, --, etc.
						// do the same shift for all intervals that follow
						const f = fParse(s+2, null) orelse 1;
						for (vec[i..i+n]) |*x| {
							x.float = op(x.float, f);
						}
						i += n;
						continue;
					} else {
						w.float = op(w.float, fParse(s+1, null) orelse 1);
					}
				} else if (c == '&') { // value at a given index
					if (fParse(s+1, null)) |f| {
						w.float = self.interval(temp, f);
					}
				} else if (c == '<' or c == '>') { // scale inversion
					const vp = vec[i..i+n];
					const tp = temp[i..i+n];
					const root = tp[0].float;
					defer tp[0].float = root;
					tp[0].float = 0;

					const mvrt = (c == s[1]); // << or >> moves the root
					var f = blk: {
						const dir: pd.Float = @floatFromInt(@as(i8, @intCast(c)) - '=');
						const j = @as(u8, @intFromBool(mvrt)) + 1;
						break :blk dir * (fParse(s + j, null) orelse 1);
					};
					const g = @floor(f);
					const num: i32 = @intFromFloat(g);
					const den: i32 = @intCast(n);
					const quo = @divFloor(num, den);
					var d: u32 = @intCast(num - den * quo); // rotation amount
					var p = n - d; // pivot index

					// rotate vec to the left by `d` positions while simultaneously:
					// - adding (octave - vec[d]) to values where index >= pivot
					// - subtracting vec[d] from values where index < pivot
					const a = tp[d].float;
					const oa = self.oct - a;
					f -= g;
					if (f == 0) {
						for (vp[p..n], tp[0..d]) |*v, *t| {
							v.float = t.float + oa;
						}
						for (vp[1..p], tp[d+1..n]) |*v, *t| {
							v.float = t.float - a;
						}
						if (mvrt) {
							const octs = self.oct * @as(pd.Float, @floatFromInt(quo));
							vp[0].float = root + octs + a;
						}
					} else {
						// interpolate between inversions `a` and `b`
						d += 1;
						const b = if (d >= n) self.oct else tp[d].float;
						const ob = self.oct - b;
						var min: pd.Float = undefined;
						for (vp[p..n], tp[0..d-1], tp[1..d]) |*v, *ta, *tb| {
							min = ta.float + oa;
							v.float = (tb.float + ob - min) * f + min;
						}
						p -= 1;
						if (p > 0) {
							for (vp[1..p], tp[d..n-1], tp[d+1..n]) |*v, *ta, *tb| {
								min = ta.float - a;
								v.float = (tb.float - b - min) * f + min;
							}
							// interpolate between a's last item and b's first item
							min = tp[n-1].float - a;
							vp[p].float = (ob - min) * f + min;
						}
						if (mvrt) {
							const octs = self.oct * @as(pd.Float, @floatFromInt(quo));
							vp[0].float = root + octs + (b - a) * f + a;
						}
					}
					i += n;
					continue;
				}
			}
			i += 1;
		}
	}

	fn anything(
		self: *const Arp, vec: []pd.Word, sym: *pd.Symbol, av: []const pd.Atom,
	) void {
		const s = sym.name;
		if (av.len == 0) {
			var end: [*:0]u8 = undefined;
			if (fParse(s, &end)) |f| {
				if (ops[end[0]]) |op| {
					if (end[0] != end[1]) {
						const g = fParse(end+1, null) orelse 1;
						return self.out[0].float(op(vec[0].float + self.interval(vec, f), g));
					}
				}
			}
			const atom = [1]pd.Atom{.{ .type = .symbol, .w = .{.symbol = sym} }};
			return self.list(vec, &atom, 0);
		}
		if (s[0] == '#') {
			return self.list(vec, av, iParse(s+1, null) orelse 0);
		}
		const argv = pd.mem.alloc(pd.Atom, av.len + 1) catch return;
		defer pd.mem.free(argv);
		argv[0] = .{ .type = .symbol, .w = .{.symbol = sym} };
		@memcpy(argv[1..], av);
		self.list(vec, argv, 0);
	}

	fn send(self: *const Arp, vec: []const pd.Word, av: []const pd.Atom) void {
		const temp = pd.mem.alloc(pd.Word, vec.len) catch return;
		defer pd.mem.free(temp);
		@memcpy(temp, vec);

		if (av.len >= 2 and av[0].type == .symbol and av[0].w.symbol.name[0] == '#') {
			self.list(temp, av[1..], iParse(av[0].w.symbol.name+1, null) orelse 0);
		} else if (av.len >= 1) {
			self.list(temp, av, 0);
		}

		const atoms = pd.mem.alloc(pd.Atom, vec.len) catch return;
		defer pd.mem.free(atoms);
		for (atoms, temp) |*a, t| {
			a.type = .float;
			a.w = t;
		}
		self.out[1].list(null, atoms);
	}

	fn extend(class: *pd.Class) void {
		class.addMethod(@ptrCast(&octC), pd.symbol("oct"), &.{ .float });
	}

	inline fn new(av: []const pd.Atom) !*anyopaque {
		if (av.len == 1 and av[0].type == .symbol) {
			return try GArray.new(av[0].w.symbol);
		} else {
			return try Array.new(av);
		}
	}

	fn newC(_: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom) callconv(.C) ?*anyopaque {
		return new(av[0..ac]) catch null;
	}

	inline fn setup() !void {
		pd.addCreator(@ptrCast(&newC), pd.symbol("arp"), &.{ .gimme });
		try Array.setup();
		try GArray.setup();
		opSetup();
	}
};

const Array = extern struct {
	const Self = @This();
	const WInlet = @import("winlet.zig").WInlet;
	var class: *pd.Class = undefined;

	base: Arp,
	win: WInlet,
	size: usize,

	fn printC(self: *const Self) callconv(.C) void {
		pd.post.start("(len=%u/%u) ", .{ self.size, self.win.len });
		self.base.printVec(self.win.ptr[0..self.size]);
	}

	fn resizeC(self: *Self, f: pd.Float) callconv(.C) void {
		const n: usize = @intFromFloat(@max(1, f));
		self.win.resize(n) catch return;
		self.size = n;
	}

	fn floatC(self: *Self, f: pd.Float) callconv(.C) void {
		const vec = self.win.ptr[0..self.size];
		self.base.out[0].float(vec[0].float + self.base.interval(vec, f));
	}

	fn sendC(
		self: *const Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		self.base.send(self.win.ptr[0..self.size], av[0..ac]);
	}

	fn listC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		self.base.list(self.win.ptr[0..self.size], av[0..ac], 0);
	}

	fn anythingC(
		self: *Self, s: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		self.base.anything(self.win.ptr[0..self.size], s, av[0..ac]);
	}

	inline fn new(av: []const pd.Atom) !*Self {
		const self: *Self = @ptrCast(try class.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		try self.base.init();

		const obj = &self.base.obj;
		const n = @max(2, av.len);
		try self.win.init(obj, n);
		self.size = n;
		const wp = self.win.ptr;
		wp[0].float = 69;
		wp[1].float = 7;
		for (0..n, wp) |i, *w| {
			_ = try obj.inletFloatArg(&w.float, av, i);
		}
		return self;
	}

	fn freeC(self: *Self) callconv(.C) void {
		self.win.free();
	}

	inline fn setup() !void {
		class = try pd.class(pd.symbol("_arp_array"), null, @ptrCast(&freeC),
			@sizeOf(Self), .{}, &.{});
		class.addFloat(@ptrCast(&floatC));
		class.addList(@ptrCast(&listC));
		class.addAnything(@ptrCast(&anythingC));
		class.addMethod(@ptrCast(&printC), pd.symbol("print"), &.{});
		class.addMethod(@ptrCast(&resizeC), pd.symbol("n"), &.{ .float });
		class.addMethod(@ptrCast(&sendC), pd.symbol("send"), &.{ .gimme });
		Arp.extend(class);
	}
};

const GArray = extern struct {
	const Self = @This();
	var class: *pd.Class = undefined;

	base: Arp,
	sym: *pd.Symbol,

	fn garray(self: *const Self) ?*pd.GArray {
		return @as(*pd.GArray, @ptrCast(pd.Class.garray.*.find(self.sym) orelse {
			pd.post.err(self, "%s: no such array", .{ self.sym.name });
			return null;
		}));
	}

	fn printC(self: *const Self) callconv(.C) void {
		pd.post.start("%s (0x%x) ", .{ self.sym.name, self.sym.thing });
		self.base.printVec((self.garray() orelse return).floatWords() catch return);
	}

	fn resizeC(self: *Self, f: pd.Float) callconv(.C) void {
		(self.garray() orelse return).resize(@as(c_ulong, @intFromFloat(f)));
	}

	fn floatC(self: *Self, f: pd.Float) callconv(.C) void {
		const vec = (self.garray() orelse return).floatWords() catch return;
		self.base.out[0].float(vec[0].float + self.base.interval(vec, f));
	}

	fn sendC(
		self: *const Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		const garr = self.garray() orelse return;
		defer garr.redraw();
		self.base.send(garr.floatWords() catch return, av[0..ac]);
	}

	fn listC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		const garr = self.garray() orelse return;
		defer garr.redraw();
		self.base.list(garr.floatWords() catch return, av[0..ac], 0);
	}

	fn anythingC(
		self: *Self, s: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		const garr = self.garray() orelse return;
		defer garr.redraw();
		self.base.anything(garr.floatWords() catch return, s, av[0..ac]);
	}

	inline fn new(s: *pd.Symbol) !*Self {
		const self: *Self = @ptrCast(try class.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		try self.base.init();
		self.sym = s;
		_ = try self.base.obj.inletSymbol(&self.sym);
		return self;
	}

	inline fn setup() !void {
		class = try pd.class(pd.symbol("_arp_garray"), null, null,
			@sizeOf(Self), .{}, &.{});
		class.addFloat(@ptrCast(&floatC));
		class.addList(@ptrCast(&listC));
		class.addAnything(@ptrCast(&anythingC));
		class.addMethod(@ptrCast(&printC), pd.symbol("print"), &.{});
		class.addMethod(@ptrCast(&resizeC), pd.symbol("n"), &.{ .float });
		class.addMethod(@ptrCast(&sendC), pd.symbol("send"), &.{ .gimme });
		Arp.extend(class);
	}
};

export fn arp_setup() void {
	Arp.setup() catch {};
}
