const pd = @import("pd");
const tg = @import("toggle.zig");
const A = pd.AtomType;

extern fn parsetimeunits(*anyopaque, pd.Float, *pd.Symbol, *pd.Float, *c_int) void;
const parseTimeUnits = parsetimeunits;

pub const Timer = extern struct {
	const Self = @This();

	obj: pd.Object,
	o_pause: *pd.Outlet,
	unitname: *pd.Symbol,
	unit: pd.Float,
	in_samples: bool,
	paused: bool,

	pub fn timeSince(self: *const Self, f: f64) f64 {
		return pd.timeSinceWithUnits(f, @floatCast(self.unit), self.in_samples);
	}

	pub fn parseUnits(self: *Self, av: []const pd.Atom) void {
		for (av[0..@min(av.len, 2)]) |*a| {
			switch (a.type) {
				.float => self.unit = a.w.float,
				.symbol => self.unitname = a.w.symbol,
				else => {},
			}
		}
		var samps: c_int = undefined;
		parseTimeUnits(self, self.unit, self.unitname, &self.unit, &samps);
		self.in_samples = (samps != 0);
	}

	pub fn setPause(self: *Self, state: bool) void {
		if (tg.set(&self.paused, state)) {
			self.o_pause.float(@floatFromInt(@intFromBool(self.paused)));
		}
	}

	pub fn tglPause(self: *Self, av: []const pd.Atom) bool {
		const changed = tg.toggle(&self.paused, av);
		if (changed) {
			self.o_pause.float(@floatFromInt(@intFromBool(self.paused)));
		}
		return changed;
	}

	pub fn init(self: *Self, av: []const pd.Atom) !void {
		self.unit = 1;
		self.in_samples = false;
		self.unitname = pd.symbol("msec");
		self.o_pause = try self.obj.outlet(&pd.s_float);
		if (av.len >= 1) {
			self.parseUnits(av);
		}
	}
};
