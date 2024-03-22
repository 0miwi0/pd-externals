const std = @import("std");
const pd = @import("pd");
const LB = pd.cnv.LoadBang;

const pi = std.math.pi;
const atan = std.math.atan;
const atan2 = std.math.atan2;

// valgrind takes issue with std.mem.len
const strlen = @cImport({ @cInclude("string.h"); }).strlen;

// ----------------------------------- Blunt -----------------------------------
// -----------------------------------------------------------------------------
const Blunt = extern struct {
	const Self = @This();
	var class: *pd.Class = undefined;

	// "loadbang" actions - 0 for original meaning
	const c_load: u8 = '!';
	// loaded but not yet connected to parent patch
	const c_init: u8 = '$';
	// about to close
	const c_close: u8 = '&';

	obj: pd.Object,
	out: *pd.Outlet,
	mask: u8,

	fn loadbangC(self: *Self, f: pd.Float) callconv(.C) void {
		const action = @as(u8, 1) << @intFromFloat(f);
		if (self.mask & action != 0) {
			self.obj.g.pd.bang();
		}
	}

	fn init(self: *Self, av: []const pd.Atom) usize {
		self.mask = 0;
		if (av.len >= 1 and av[av.len - 1].type == .symbol) {
			const str = av[av.len - 1].w.symbol.name;
			var i: usize = 0;
			while (str[i] != 0) : (i += 1) {
				switch (str[i]) {
					c_load => self.mask |= 1 << @intFromEnum(LB.load),
					c_init => self.mask |= 1 << @intFromEnum(LB.init),
					c_close => self.mask |= 1 << @intFromEnum(LB.close),
					else => break,
				}
			}
		}
		return av.len - @intFromBool(self.mask != 0);
	}

	fn extend(cls: *pd.Class) void {
		cls.addMethod(@ptrCast(&loadbangC), pd.symbol("loadbang"), &.{ .deffloat });
	}

	fn newC() callconv(.C) ?*pd.Object {
		return @ptrCast(class.pd() catch return null);
	}

	inline fn setup() !void {
		pd.post.do("Blunt! v0.9", .{});
		class = try pd.class(pd.symbol("blunt"), @ptrCast(&newC), null,
			@sizeOf(pd.Object), .{ .no_inlet=true }, &.{});
	}
};


// ------------------------------ Binary operator ------------------------------
// -----------------------------------------------------------------------------
const BinOp = extern struct {
	const Self = @This();
	const Op = *const fn(pd.Float, pd.Float) callconv(.C) pd.Float;

	base: Blunt,
	f1: pd.Float,
	f2: pd.Float,

	fn printC(self: *const Self) callconv(.C) void {
		pd.post.log(self, .normal, "%g %g", .{ self.f1, self.f2 });
	}

	fn f1C(self: *Self, f: pd.Float) callconv(.C) void {
		self.f1 = f;
	}

	fn f2C(self: *Self, f: pd.Float) callconv(.C) void {
		self.f2 = f;
	}

	fn setC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		if (ac >= 2 and av[1].type == .float) {
			self.f2 = av[1].w.float;
		}
		if (ac >= 1 and av[0].type == .float) {
			self.f1 = av[0].w.float;
		}
	}

	fn op(self: *const Self) Op {
		const class: *const *pd.Class = @ptrCast(self);
		return @as(Op, @ptrCast(class.*.methods[0].fun));
	}

	fn sendC(self: *Self, s: pd.Symbol) callconv(.C) void {
		const thing = s.thing
			orelse return pd.post.err(self, "%s: no such object", .{ s.name });
		thing.float(self.op()(self.f1, self.f2));
	}

	fn revSendC(self: *Self, s: pd.Symbol) callconv(.C) void {
		const thing = s.thing
			orelse return pd.post.err(self, "%s: no such object", .{ s.name });
		thing.float(self.op()(self.f2, self.f1));
	}

	fn bangC(self: *const Self) callconv(.C) void {
		self.base.out.float(self.op()(self.f1, self.f2));
	}

	fn revBangC(self: *const Self) callconv(.C) void {
		self.base.out.float(self.op()(self.f2, self.f1));
	}

	fn floatC(self: *Self, f: pd.Float) callconv(.C) void {
		self.f1 = f;
		@as(*pd.Pd, @ptrCast(self)).bang();
	}

	fn listC(
		self: *Self, s: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		self.setC(s, ac, av);
		@as(*pd.Pd, @ptrCast(self)).bang();
	}

	fn anythingC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		if (ac >= 1 and av[0].type == .float) {
			self.f2 = av[0].w.float;
		}
		@as(*pd.Pd, @ptrCast(self)).bang();
	}

	fn init(self: *Self, av: []const pd.Atom) !void {
		const n = self.base.init(av);
		self.base.out = try self.base.obj.outlet(&pd.s_float);

		// set the 1st float, but only if there are 2 args
		switch (n) {
			2 => {
				self.f1 = av[0].float();
				self.f2 = av[1].float();
			},
			1 => self.f2 = av[0].float(),
			else => {},
		}
	}

	inline fn new(cl: *pd.Class, av: []const pd.Atom) !*Self {
		const self: *Self = @ptrCast(try cl.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		_ = try self.base.obj.inletFloat(&self.f2);
		try self.init(av);
		return self;
	}

	fn hotNew(cl: *pd.Class, av: []const pd.Atom) !*Self {
		const self: *Self = @ptrCast(try cl.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		const obj = &self.base.obj;
		_ = try obj.inlet(&obj.g.pd, &pd.s_float, &pd.s_anything);
		try self.init(av);
		return self;
	}

	const Pkg = struct {
		class: [2]*pd.Class = undefined,
		name: []const u8,
		new: *const fn(*pd.Symbol, u32, [*]const pd.Atom) callconv(.C) ?*Self,
		op: Op,
		rev: bool = false,

		fn tryGen(pack: *Pkg, s: *pd.Symbol, av: []const pd.Atom) !*Self {
			return switch (s.name[0]) {
				'#' => try Self.hotNew(pack.class[0], av),
				'@' => try Self.new(pack.class[1], av),
				else => try Self.new(pack.class[0], av),
			};
		}

		fn gen(pack: *Pkg, s: *pd.Symbol, av: []const pd.Atom) ?*Self {
			return tryGen(pack, s, av) catch null;
		}

		fn setup(self: *Pkg, s: *pd.Symbol) !*pd.Class {
			const cl = try pd.class(s, @ptrCast(self.new), null,
				@sizeOf(Self), .{}, &.{ .gimme });
			cl.addFloat(@ptrCast(&floatC));
			cl.addList(@ptrCast(&listC));
			cl.addAnything(@ptrCast(&anythingC));

			cl.addMethod(@ptrCast(self.op), &pd.s_, &.{});
			cl.addMethod(@ptrCast(&printC), pd.symbol("print"), &.{});
			cl.addMethod(@ptrCast(&f1C), pd.symbol("f1"), &.{ .float });
			cl.addMethod(@ptrCast(&f2C), pd.symbol("f2"), &.{ .float });
			cl.addMethod(@ptrCast(&setC), pd.symbol("set"), &.{ .gimme });
			cl.setHelpSymbol(pd.symbol("blunt"));
			Blunt.extend(cl);
			return cl;
		}
	};
};


// ------------------------------ Unary operator -------------------------------
// -----------------------------------------------------------------------------
const UnOp = extern struct {
	const Self = @This();
	const Op = *const fn(pd.Float) callconv(.C) pd.Float;
	const parse = std.fmt.parseFloat;

	base: Blunt,
	f: pd.Float,

	fn printC(self: *const Self) callconv(.C) void {
		pd.post.log(self, .normal, "%g", .{ self.f });
	}

	fn setC(self: *Self, f: pd.Float) callconv(.C) void {
		self.f = f;
	}

	fn op(self: *const Self) Op {
		const class: *const *pd.Class = @ptrCast(self);
		return @as(Op, @ptrCast(class.*.methods[0].fun));
	}

	fn sendC(self: *const Self, s: pd.Symbol) callconv(.C) void {
		const thing = s.thing
			orelse return pd.post.err(self, "%s: no such object", .{ s.name });
		thing.float(self.op()(self.f));
	}

	fn bangC(self: *const Self) callconv(.C) void {
		self.base.out.float(self.op()(self.f));
	}

	fn floatC(self: *Self, f: pd.Float) callconv(.C) void {
		self.f = f;
		@as(*pd.Pd, @ptrCast(self)).bang();
	}

	fn symbolC(self: *Self, s: pd.Symbol) callconv(.C) void {
		const f = parse(pd.Float, s.name[0..strlen(s.name)]) catch {
			pd.post.err(self, "Couldn't convert %s to float.", .{ s.name });
			return;
		};
		self.floatC(f);
	}

	const Pkg = struct {
		class: *pd.Class = undefined,
		name: []const u8,
		new: *const fn(*pd.Symbol, u32, [*]const pd.Atom) callconv(.C) ?*Self,
		op: Op,
		inlet: bool = false,
		alias: bool = true,

		fn tryGen(pack: *Pkg, av: []const pd.Atom) !*Self {
			const self: *Self = @ptrCast(try pack.class.pd());
			errdefer @as(*pd.Pd, @ptrCast(self)).free();
			const obj: *pd.Object = @ptrCast(self);
			if (pack.inlet) {
				_ = try obj.inletFloat(&self.f);
			}
			self.base.out = try obj.outlet(&pd.s_float);
			self.f = pd.floatArg(av[0..self.base.init(av)], 0);
			return self;
		}

		fn gen(pack: *Pkg, av: []const pd.Atom) ?*Self {
			return tryGen(pack, av) catch null;
		}

		fn setup(self: *Pkg) !*pd.Class {
			const cl = try pd.class(pd.symbol(@ptrCast(self.name)), @ptrCast(self.new), null,
				@sizeOf(Self), .{}, &.{ .gimme });
			cl.addBang(@ptrCast(&bangC));
			cl.addFloat(@ptrCast(&floatC));
			cl.addSymbol(@ptrCast(&symbolC));

			cl.addMethod(@ptrCast(self.op), &pd.s_, &.{});
			cl.addMethod(@ptrCast(&printC), pd.symbol("print"), &.{});
			cl.addMethod(@ptrCast(&setC), pd.symbol("set"), &.{ .float });
			cl.addMethod(@ptrCast(&sendC), pd.symbol("send"), &.{ .symbol });
			cl.setHelpSymbol(pd.symbol("blunt"));
			Blunt.extend(cl);
			return cl;
		}
	};
};


// ----------------------------------- Bang ------------------------------------
// -----------------------------------------------------------------------------
const Bang = extern struct {
	const Self = Blunt;
	var class: *pd.Class = undefined;

	fn bangC(self: *const Self) callconv(.C) void {
		self.out.bang();
	}

	inline fn new(av: []const pd.Atom) !*Self {
		const self: *Self = @ptrCast(try class.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		_ = self.init(av);
		self.out = try self.obj.outlet(&pd.s_bang);
		return self;
	}

	fn newC(_: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom) callconv(.C) ?*Self {
		return new(av[0..ac]) catch null;
	}

	inline fn setup() !void {
		const bnew: pd.NewMethod = @ptrCast(&newC);
		class = try pd.class(pd.symbol("b"), bnew, null,
			@sizeOf(Self), .{}, &.{ .gimme });
		pd.addCreator(bnew, pd.symbol("`b"), &.{ .gimme });
		class.addBang(@ptrCast(&bangC));
		class.addFloat(@ptrCast(&bangC));
		class.addSymbol(@ptrCast(&bangC));
		class.addList(@ptrCast(&bangC));
		class.addAnything(@ptrCast(&bangC));

		Blunt.extend(class);
		class.setHelpSymbol(pd.symbol("blunt"));
	}
};


// ---------------------------------- Symbol -----------------------------------
// -----------------------------------------------------------------------------
const Symbol = extern struct {
	const Self = @This();
	var class: *pd.Class = undefined;

	base: Blunt,
	sym: *pd.Symbol,

	fn printC(self: *const Self) callconv(.C) void {
		pd.post.log(self, .normal, "%s", .{ self.sym.name });
	}

	fn bangC(self: *const Self) callconv(.C) void {
		self.base.out.symbol(self.sym);
	}

	fn symbolC(self: *Self, s: *pd.Symbol) callconv(.C) void {
		self.sym = s;
		self.bangC();
	}

	fn listC(
		self: *Self, s: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		if (ac == 0) {
			self.bangC();
		} else if (av[0].type == .symbol) {
			self.symbolC(av[0].w.symbol);
		} else {
			self.symbolC(s);
		}
	}

	inline fn new(av: []const pd.Atom) !*Self {
		const self: *Self = @ptrCast(try class.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		self.sym = pd.symbolArg(av[0..self.base.init(av)], 0);
		self.base.out = try self.base.obj.outlet(&pd.s_symbol);
		_ = try self.base.obj.inletSymbol(&self.sym);
		return self;
	}

	fn newC(_: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom) callconv(.C) ?*Self {
		return new(av[0..ac]) catch null;
	}

	inline fn setup() !void {
		class = try pd.class(pd.symbol("sym"), @ptrCast(&newC), null,
			@sizeOf(Self), .{}, &.{ .gimme });
		class.addBang(@ptrCast(&bangC));
		class.addSymbol(@ptrCast(&symbolC));
		class.addList(@ptrCast(&listC));
		class.addAnything(@ptrCast(&symbolC));
		class.addMethod(@ptrCast(&printC), pd.symbol("print"), &.{});

		Blunt.extend(class);
		class.setHelpSymbol(pd.symbol("blunt"));
	}
};


// ------------------------------- Reverse moses -------------------------------
// -----------------------------------------------------------------------------
const RevMoses = extern struct {
	const Self = @This();
	var class: *pd.Class = undefined;

	obj: pd.Object,
	out: [2]*pd.Outlet,
	f: pd.Float,

	fn floatC(self: *Self, f: pd.Float) callconv(.C) void {
		self.out[if (f > self.f) 0 else 1].float(f);
	}

	inline fn new(f: pd.Float) !*Self {
		const self: *Self = @ptrCast(try class.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		self.f = f;

		const obj = &self.obj;
		self.out[0] = try obj.outlet(&pd.s_float);
		self.out[1] = try obj.outlet(&pd.s_float);
		_ = try obj.inletFloat(&self.f);
		return self;
	}

	fn newC(f: pd.Float) callconv(.C) ?*Self {
		return new(f) catch null;
	}

	inline fn setup() !void {
		class = try pd.class(pd.symbol("@moses"), @ptrCast(&newC), null,
			@sizeOf(Self), .{}, &.{ .deffloat });
		class.addFloat(@ptrCast(&floatC));
		class.setHelpSymbol(pd.symbol("blunt"));
	}
};


// --------------------------------- Packages ----------------------------------
// -----------------------------------------------------------------------------
var pkg_plus  = BinOp.Pkg { .name="+",     .new=plusNew,  .op=plusOp };
var pkg_minus = BinOp.Pkg { .name="-",     .new=minusNew, .op=minusOp, .rev=true };
var pkg_times = BinOp.Pkg { .name="*",     .new=timesNew, .op=timesOp };
var pkg_over  = BinOp.Pkg { .name="/",     .new=overNew,  .op=overOp,  .rev=true };
var pkg_min   = BinOp.Pkg { .name="min",   .new=minNew,   .op=minOp };
var pkg_max   = BinOp.Pkg { .name="max",   .new=maxNew,   .op=maxOp };
var pkg_log   = BinOp.Pkg { .name="log",   .new=logNew,   .op=logOp,   .rev=true };
var pkg_pow   = BinOp.Pkg { .name="pow",   .new=powNew,   .op=powOp,   .rev=true };
var pkg_lt    = BinOp.Pkg { .name="<",     .new=ltNew,    .op=ltOp };
var pkg_gt    = BinOp.Pkg { .name=">",     .new=gtNew,    .op=gtOp };
var pkg_le    = BinOp.Pkg { .name="<=",    .new=leNew,    .op=leOp };
var pkg_ge    = BinOp.Pkg { .name=">=",    .new=geNew,    .op=geOp };
var pkg_ee    = BinOp.Pkg { .name="==",    .new=eeNew,    .op=eeOp };
var pkg_ne    = BinOp.Pkg { .name="!=",    .new=neNew,    .op=neOp };
var pkg_la    = BinOp.Pkg { .name="&&",    .new=laNew,    .op=laOp };
var pkg_lo    = BinOp.Pkg { .name="||",    .new=loNew,    .op=loOp };
var pkg_ba    = BinOp.Pkg { .name="&",     .new=baNew,    .op=baOp };
var pkg_bo    = BinOp.Pkg { .name="|",     .new=boNew,    .op=boOp };
var pkg_bx    = BinOp.Pkg { .name="^",     .new=bxNew,    .op=bxOp };
var pkg_ls    = BinOp.Pkg { .name="<<",    .new=lsNew,    .op=lsOp,    .rev=true };
var pkg_rs    = BinOp.Pkg { .name=">>",    .new=rsNew,    .op=rsOp,    .rev=true };
var pkg_rem   = BinOp.Pkg { .name="%",     .new=remNew,   .op=remOp,   .rev=true };
var pkg_mod   = BinOp.Pkg { .name="mod",   .new=modNew,   .op=modOp,   .rev=true };
var pkg_div   = BinOp.Pkg { .name="div",   .new=divNew,   .op=divOp,   .rev=true };
var pkg_frem  = BinOp.Pkg { .name="f%",    .new=fremNew,  .op=fremOp,  .rev=true };
var pkg_fmod  = BinOp.Pkg { .name="fmod",  .new=fmodNew,  .op=fmodOp,  .rev=true };
var pkg_atan2 = BinOp.Pkg { .name="atan2", .new=atan2New, .op=atan2Op, .rev=true };

var pkg_f     = UnOp.Pkg { .name="f",     .new=fNew,     .op=fOp,     .inlet=true };
var pkg_i     = UnOp.Pkg { .name="i",     .new=iNew,     .op=iOp,     .inlet=true };
var pkg_floor = UnOp.Pkg { .name="floor", .new=floorNew, .op=floorOp, .alias=false };
var pkg_ceil  = UnOp.Pkg { .name="ceil",  .new=ceilNew,  .op=ceilOp,  .alias=false };
var pkg_bnot  = UnOp.Pkg { .name="~",     .new=bnotNew,  .op=bnotOp,  .alias=false };
var pkg_lnot  = UnOp.Pkg { .name="!",     .new=lnotNew,  .op=lnotOp,  .alias=false };
var pkg_fact  = UnOp.Pkg { .name="n!",    .new=factNew,  .op=factOp,  .alias=false };
var pkg_sin   = UnOp.Pkg { .name="sin",   .new=sinNew,   .op=sinOp };
var pkg_cos   = UnOp.Pkg { .name="cos",   .new=cosNew,   .op=cosOp };
var pkg_tan   = UnOp.Pkg { .name="tan",   .new=tanNew,   .op=tanOp };
var pkg_atan  = UnOp.Pkg { .name="atan",  .new=atanNew,  .op=atanOp };
var pkg_sqrt  = UnOp.Pkg { .name="sqrt",  .new=sqrtNew,  .op=sqrtOp };
var pkg_exp   = UnOp.Pkg { .name="exp",   .new=expNew,   .op=expOp };
var pkg_abs   = UnOp.Pkg { .name="abs",   .new=absNew,   .op=absOp };


// -------------------------------- New methods --------------------------------
// -----------------------------------------------------------------------------
const S = *pd.Symbol;
const Ac = u32;
const Av = [*]const pd.Atom;
fn plusNew(s: S, ac: Ac, av: Av)  callconv(.C) ?*BinOp { return pkg_plus.gen(s, av[0..ac]); }
fn minusNew(s: S, ac: Ac, av: Av) callconv(.C) ?*BinOp { return pkg_minus.gen(s, av[0..ac]); }
fn timesNew(s: S, ac: Ac, av: Av) callconv(.C) ?*BinOp { return pkg_times.gen(s, av[0..ac]); }
fn overNew(s: S, ac: Ac, av: Av)  callconv(.C) ?*BinOp { return pkg_over.gen(s, av[0..ac]); }
fn minNew(s: S, ac: Ac, av: Av)   callconv(.C) ?*BinOp { return pkg_min.gen(s, av[0..ac]); }
fn maxNew(s: S, ac: Ac, av: Av)   callconv(.C) ?*BinOp { return pkg_max.gen(s, av[0..ac]); }
fn logNew(s: S, ac: Ac, av: Av)   callconv(.C) ?*BinOp { return pkg_log.gen(s, av[0..ac]); }
fn powNew(s: S, ac: Ac, av: Av)   callconv(.C) ?*BinOp { return pkg_pow.gen(s, av[0..ac]); }
fn ltNew(s: S, ac: Ac, av: Av)    callconv(.C) ?*BinOp { return pkg_lt.gen(s, av[0..ac]); }
fn gtNew(s: S, ac: Ac, av: Av)    callconv(.C) ?*BinOp { return pkg_gt.gen(s, av[0..ac]); }
fn leNew(s: S, ac: Ac, av: Av)    callconv(.C) ?*BinOp { return pkg_le.gen(s, av[0..ac]); }
fn geNew(s: S, ac: Ac, av: Av)    callconv(.C) ?*BinOp { return pkg_ge.gen(s, av[0..ac]); }
fn eeNew(s: S, ac: Ac, av: Av)    callconv(.C) ?*BinOp { return pkg_ee.gen(s, av[0..ac]); }
fn neNew(s: S, ac: Ac, av: Av)    callconv(.C) ?*BinOp { return pkg_ne.gen(s, av[0..ac]); }
fn laNew(s: S, ac: Ac, av: Av)    callconv(.C) ?*BinOp { return pkg_la.gen(s, av[0..ac]); }
fn loNew(s: S, ac: Ac, av: Av)    callconv(.C) ?*BinOp { return pkg_lo.gen(s, av[0..ac]); }
fn baNew(s: S, ac: Ac, av: Av)    callconv(.C) ?*BinOp { return pkg_ba.gen(s, av[0..ac]); }
fn boNew(s: S, ac: Ac, av: Av)    callconv(.C) ?*BinOp { return pkg_bo.gen(s, av[0..ac]); }
fn bxNew(s: S, ac: Ac, av: Av)    callconv(.C) ?*BinOp { return pkg_bx.gen(s, av[0..ac]); }
fn lsNew(s: S, ac: Ac, av: Av)    callconv(.C) ?*BinOp { return pkg_ls.gen(s, av[0..ac]); }
fn rsNew(s: S, ac: Ac, av: Av)    callconv(.C) ?*BinOp { return pkg_rs.gen(s, av[0..ac]); }
fn remNew(s: S, ac: Ac, av: Av)   callconv(.C) ?*BinOp { return pkg_rem.gen(s, av[0..ac]); }
fn modNew(s: S, ac: Ac, av: Av)   callconv(.C) ?*BinOp { return pkg_mod.gen(s, av[0..ac]); }
fn divNew(s: S, ac: Ac, av: Av)   callconv(.C) ?*BinOp { return pkg_div.gen(s, av[0..ac]); }
fn fremNew(s: S, ac: Ac, av: Av)  callconv(.C) ?*BinOp { return pkg_frem.gen(s, av[0..ac]); }
fn fmodNew(s: S, ac: Ac, av: Av)  callconv(.C) ?*BinOp { return pkg_fmod.gen(s, av[0..ac]); }
fn atan2New(s: S, ac: Ac, av: Av) callconv(.C) ?*BinOp { return pkg_atan2.gen(s, av[0..ac]); }

fn fNew(_: S, ac: Ac, av: Av)     callconv(.C) ?*UnOp { return pkg_f.gen(av[0..ac]); }
fn iNew(_: S, ac: Ac, av: Av)     callconv(.C) ?*UnOp { return pkg_i.gen(av[0..ac]); }
fn floorNew(_: S, ac: Ac, av: Av) callconv(.C) ?*UnOp { return pkg_floor.gen(av[0..ac]); }
fn ceilNew(_: S, ac: Ac, av: Av)  callconv(.C) ?*UnOp { return pkg_ceil.gen(av[0..ac]); }
fn bnotNew(_: S, ac: Ac, av: Av)  callconv(.C) ?*UnOp { return pkg_bnot.gen(av[0..ac]); }
fn lnotNew(_: S, ac: Ac, av: Av)  callconv(.C) ?*UnOp { return pkg_lnot.gen(av[0..ac]); }
fn factNew(_: S, ac: Ac, av: Av)  callconv(.C) ?*UnOp { return pkg_fact.gen(av[0..ac]); }
fn sinNew(_: S, ac: Ac, av: Av)   callconv(.C) ?*UnOp { return pkg_sin.gen(av[0..ac]); }
fn cosNew(_: S, ac: Ac, av: Av)   callconv(.C) ?*UnOp { return pkg_cos.gen(av[0..ac]); }
fn tanNew(_: S, ac: Ac, av: Av)   callconv(.C) ?*UnOp { return pkg_tan.gen(av[0..ac]); }
fn atanNew(_: S, ac: Ac, av: Av)  callconv(.C) ?*UnOp { return pkg_atan.gen(av[0..ac]); }
fn sqrtNew(_: S, ac: Ac, av: Av)  callconv(.C) ?*UnOp { return pkg_sqrt.gen(av[0..ac]); }
fn expNew(_: S, ac: Ac, av: Av)   callconv(.C) ?*UnOp { return pkg_exp.gen(av[0..ac]); }
fn absNew(_: S, ac: Ac, av: Av)   callconv(.C) ?*UnOp { return pkg_abs.gen(av[0..ac]); }


// -------------------------------- Operations ---------------------------------
// -----------------------------------------------------------------------------
const F = pd.Float;
// binop1:  +  -  *  /  min  max  log  pow
fn plusOp(f1: F, f2: F)  callconv(.C) F { return f1 + f2; }
fn minusOp(f1: F, f2: F) callconv(.C) F { return f1 - f2; }
fn timesOp(f1: F, f2: F) callconv(.C) F { return f1 * f2; }
fn overOp(f1: F, f2: F)  callconv(.C) F { return if (f2 == 0) 0 else f1 / f2; }
fn minOp(f1: F, f2: F)   callconv(.C) F { return @min(f1, f2); }
fn maxOp(f1: F, f2: F)   callconv(.C) F { return @max(f1, f2); }

fn logOp(f1: F, f2: F) callconv(.C) F {
	return if (f1 <= 0) -1000
		else if (f2 <= 0) @log(f1)
		else @log2(f1) / @log2(f2);
}

fn powOp(f1: F, f2: F) callconv(.C) F {
	const d2: F = @floatFromInt(@as(i32, @intFromFloat(f2)));
	return if (f1 == 0 or (f1 < 0 and f2 - d2 != 0))
		0 else @exp2(@log2(f1) * f2);
}

// binop2:  <  >  <=  >=  ==  !=
fn ltOp(f1: F, f2: F) callconv(.C) F { return @floatFromInt(@intFromBool(f1 < f2)); }
fn gtOp(f1: F, f2: F) callconv(.C) F { return @floatFromInt(@intFromBool(f1 > f2)); }
fn leOp(f1: F, f2: F) callconv(.C) F { return @floatFromInt(@intFromBool(f1 <= f2)); }
fn geOp(f1: F, f2: F) callconv(.C) F { return @floatFromInt(@intFromBool(f1 >= f2)); }
fn eeOp(f1: F, f2: F) callconv(.C) F { return @floatFromInt(@intFromBool(f1 == f2)); }
fn neOp(f1: F, f2: F) callconv(.C) F { return @floatFromInt(@intFromBool(f1 != f2)); }

// binop3:  &&  ||  &  |  ^  <<  >>  %  mod  div  f%  fmod
fn laOp(f1: F, f2: F) callconv(.C) F { return @floatFromInt(@intFromBool(f1 != 0 and f2 != 0)); }
fn loOp(f1: F, f2: F) callconv(.C) F { return @floatFromInt(@intFromBool(f1 != 0 or f2 != 0)); }
fn baOp(f1: F, f2: F) callconv(.C) F
{ return @floatFromInt(@as(i32, @intFromFloat(f1)) & @as(i32, @intFromFloat(f2))); }
fn boOp(f1: F, f2: F) callconv(.C) F
{ return @floatFromInt(@as(i32, @intFromFloat(f1)) | @as(i32, @intFromFloat(f2))); }
fn bxOp(f1: F, f2: F) callconv(.C) F
{ return @floatFromInt(@as(i32, @intFromFloat(f1)) ^ @as(i32, @intFromFloat(f2))); }
fn lsOp(f1: F, f2: F) callconv(.C) F
{ return @floatFromInt(@as(i32, @intFromFloat(f1)) << @intFromFloat(f2)); }
fn rsOp(f1: F, f2: F) callconv(.C) F
{ return @floatFromInt(@as(i32, @intFromFloat(f1)) >> @intFromFloat(f2)); }

fn remOp(f1: F, f2: F) callconv(.C) F {
	const n2: i32 = @intFromFloat(@max(1, @abs(f2)));
	return @floatFromInt(@rem(@as(i32, @intFromFloat(f1)), n2));
}
fn modOp(f1: F, f2: F) callconv(.C) F {
	const n2: i32 = @intFromFloat(@max(1, @abs(f2)));
	return @floatFromInt(@mod(@as(i32, @intFromFloat(f1)), n2));
}
fn divOp(f1: F, f2: F) callconv(.C) F {
	const n2: i32 = @intFromFloat(@max(1, @abs(f2)));
	return @floatFromInt(@divFloor(@as(i32, @intFromFloat(f1)), n2));
}
fn fremOp(f1: F, f: F) callconv(.C) F {
	const f2 = if (f == 0) 1 else @abs(f);
	return @rem(f1, f2);
}
fn fmodOp(f1: F, f: F) callconv(.C) F {
	const f2 = if (f == 0) 1 else @abs(f);
	return @mod(f1, f2);
}
fn atan2Op(f1: F, f2: F) callconv(.C) F {
	return if (f1 == 0 and f2 == 0) 0 else atan2(f1, f2);
}

// // unop:  f  i  !  ~  floor  ceil  factorial
fn fOp(f: F)     callconv(.C) F { return f; }
fn iOp(f: F)     callconv(.C) F { return @floatFromInt(@as(i32, @intFromFloat(f))); }
fn floorOp(f: F) callconv(.C) F { return @floor(f); }
fn ceilOp(f: F)  callconv(.C) F { return @ceil(f); }
fn bnotOp(f: F)  callconv(.C) F { return @floatFromInt(~@as(i32, @intFromFloat(f))); }
fn lnotOp(f: F)  callconv(.C) F { return @floatFromInt(@intFromBool(f == 0)); }

fn factOp(f: F) callconv(.C) F {
	var d = @floor(f);
	if (d > 9) {
		// stirling's approximation
		return @exp2(@log2(f) * f) * @exp(-f) * @sqrt(f) * @sqrt(2 * pi);
	}
	var g: pd.Float = 1;
	while (d > 0) : (d -= 1) {
		g *= d;
	}
	return g;
}

fn sinOp(f: F)  callconv(.C) F { return @sin(f); }
fn cosOp(f: F)  callconv(.C) F { return @cos(f); }
fn tanOp(f: F)  callconv(.C) F { return @tan(f); }
fn atanOp(f: F) callconv(.C) F { return atan(f); }
fn sqrtOp(f: F) callconv(.C) F { return if (f > 0) @sqrt(f) else 0; }
fn expOp(f: F)  callconv(.C) F { return @exp(f); }
fn absOp(f: F)  callconv(.C) F { return @abs(f); }

inline fn setup() !void {
	var buf: [6:0]u8 = undefined;
	const b = &buf;

	const binops = [_]*BinOp.Pkg {
		&pkg_plus, &pkg_minus, &pkg_times, &pkg_over,
		&pkg_min, &pkg_max, &pkg_log, &pkg_pow,
		&pkg_lt, &pkg_gt, &pkg_le, &pkg_ge, &pkg_ee, &pkg_ne,
		&pkg_la, &pkg_lo, &pkg_ba, &pkg_bo, &pkg_bx, &pkg_ls, &pkg_rs,
		&pkg_rem, &pkg_mod, &pkg_div, &pkg_frem, &pkg_fmod, &pkg_atan2,
	};
	for (binops) |p| {
		p.class[0] = try p.setup(pd.symbol(@ptrCast(p.name.ptr)));
		p.class[0].addBang(@ptrCast(&BinOp.bangC));
		p.class[0].addMethod(
			@ptrCast(&BinOp.sendC), pd.symbol("send"), &.{ .symbol });

		@memcpy(b[1..p.name.len+1], p.name);
		b[p.name.len+1] = 0;
		const new: pd.NewMethod = @ptrCast(p.new);
		b[0] = '`'; // alias for compatibility
		pd.addCreator(new, pd.symbol(b), &.{ .gimme });
		b[0] = '#'; // hot 2nd inlet variant
		pd.addCreator(new, pd.symbol(b), &.{ .gimme });

		if (p.rev) {
			b[0] = '@'; // reverse operand variant
			p.class[1] = try p.setup(pd.symbol(b));
			p.class[1].addBang(@ptrCast(&BinOp.revBangC));
			p.class[1].addMethod(
				@ptrCast(&BinOp.revSendC), pd.symbol("send"), &.{ .symbol });
		}
	}
	pd.addCreator(@ptrCast(&fmodNew), pd.symbol("wrap"), &.{ .gimme });

	const unops = [_]*UnOp.Pkg {
		&pkg_f, &pkg_i, &pkg_floor, &pkg_ceil, &pkg_bnot, &pkg_lnot, &pkg_fact,
		&pkg_sin, &pkg_cos, &pkg_tan, &pkg_atan, &pkg_sqrt, &pkg_exp, &pkg_abs,
	};
	for (unops) |p| {
		p.class = try p.setup();
		if (p.alias) {
			@memcpy(b[1..p.name.len+1], p.name);
			b[p.name.len+1] = 0;
			b[0] = '`';
			pd.addCreator(@ptrCast(p.new), pd.symbol(b), &.{ .gimme });
		}
	}

	try Bang.setup();
	try Symbol.setup();
	try Blunt.setup();
	try RevMoses.setup();
}

export fn blunt_setup() void {
	setup() catch {};
}
