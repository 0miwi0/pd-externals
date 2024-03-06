const pd = @import("pd");
const tg = @import("toggle.zig");

const LinPTilde = extern struct {
	const Self = @This();
	var class: *pd.Class = undefined;

	obj: pd.Object,
	o_pause: *pd.Outlet,
	target: pd.Sample,
	value: pd.Sample,
	biginc: pd.Sample,
	inc: pd.Sample,
	invn: pd.Float,
	dspticktomsec: pd.Float,
	inletvalue: pd.Float,
	inletwas: pd.Float,
	ticksleft: u32,
	retarget: bool,
	paused: bool,

	fn tglPause(self: *Self, av: []const pd.Atom) bool {
		const changed = tg.toggle(&self.paused, av);
		if (changed) {
			self.o_pause.float(@floatFromInt(@intFromBool(self.paused)));
		}
		return changed;
	}

	fn performC(w: [*]usize) callconv(.C) *usize {
		const self: *Self = @ptrFromInt(w[1]);
		const out = @as([*]pd.Sample, @ptrFromInt(w[3]))[0..w[2]];

		if (pd.bigOrSmall(self.value)) {
			self.value = 0;
		}
		if (self.retarget) {
			const nticks = @max(1,
				@as(u32, @intFromFloat(self.inletwas * self.dspticktomsec)));
			self.ticksleft = nticks;
			self.biginc = (self.target - self.value)
				/ @as(pd.Sample, @floatFromInt(nticks));
			self.inc = self.invn * self.biginc;
			self.retarget = false;
		}

		if (!self.paused) {
			if (self.ticksleft > 0) {
				var f = self.value;
				for (out) |*o| {
					o.* = f;
					f += self.inc;
				}
				self.value += self.biginc;
				self.ticksleft -= 1;
				return &w[4];
			} else {
				self.value = self.target;
			}
		}
		@memset(out, self.value);
		return &w[4];
	}

	fn dspC(self: *Self, sp: [*]*pd.Signal) callconv(.C) void {
		pd.dsp.add(&performC, .{ self, sp[0].len, sp[0].vec });
		self.invn = 1 / @as(pd.Float, @floatFromInt(sp[0].len));
		self.dspticktomsec = sp[0].srate
			/ @as(pd.Float, @floatFromInt(1000 * sp[0].len));
	}

	fn stopC(self: *Self) callconv(.C) void {
		self.target = self.value;
		self.ticksleft = 0;
		self.retarget = false;
	}

	fn pauseC(
		self: *Self, _: *pd.Symbol, ac: c_uint, av: [*]const pd.Atom,
	) callconv(.C) void {
		if (!self.tglPause(av[0..ac]) or self.value == self.target) {
			return;
		}
	}

	fn floatC(self: *Self, f: pd.Float) callconv(.C) void {
		if (self.inletvalue <= 0) {
			self.target = f;
			self.value = f;
			self.ticksleft = 0;
			self.retarget = false;
		} else {
			self.target = f;
			self.inletwas = self.inletvalue;
			self.inletvalue = 0;
			self.retarget = true;
			if (tg.set(&self.paused, false)) {
				self.o_pause.float(@floatFromInt(@intFromBool(self.paused)));
			}
		}
	}

	inline fn new() !*Self {
		const self: *Self = @ptrCast(try class.pd());
		errdefer @as(*pd.Pd, @ptrCast(self)).free();
		const obj = &self.obj;
		_ = try obj.inletFloat(&self.inletvalue);
		_ = try obj.outlet(&pd.s_signal);
		self.o_pause = try obj.outlet(&pd.s_float);
		self.paused = false;
		self.retarget = false;
		self.ticksleft = 0;
		self.value = 0;
		self.target = 0;
		self.inletvalue = 0;
		self.inletwas = 0;
		return self;
	}

	fn newC() callconv(.C) ?*Self {
		return new() catch null;
	}

	inline fn setup() !void {
		class = try pd.class(pd.symbol("linp~"), @ptrCast(&newC), null,
			@sizeOf(Self), .{}, &.{});

		class.addFloat(@ptrCast(&floatC));
		class.addMethod(@ptrCast(&stopC), pd.symbol("stop"), &.{});
		class.addMethod(@ptrCast(&dspC), pd.symbol("dsp"), &.{ .cant });
		class.addMethod(@ptrCast(&pauseC), pd.symbol("pause"), &.{ .gimme });
	}
};

export fn linp_tilde_setup() void {
	LinPTilde.setup() catch {};
}
