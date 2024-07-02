const pd = @import("pd");
const Self = @import("slope.zig").Slope(@This());

pub fn setK(self: *Self) void {
	if (self.log) {
		self.minmax();
		self.k = self.run / @log(self.max / self.min);
	} else {
		self.k = self.run / (self.max - self.min);
	}
}

fn floatC(self: *const Self, f: pd.Float) callconv(.C) void {
	const res: pd.Float = @floatCast(if (self.log)
		@log(f / self.min) * self.k
		else (f - self.min) * self.k);
	self.out.float(res);
}

export fn slx_setup() void {
	Self.setup(pd.symbol("slx"), @ptrCast(&floatC)) catch {};
}
