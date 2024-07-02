const pd = @import("pd");
const Self = @import("slope.zig").Slope(@This());

pub fn setK(self: *Self) void {
	if (self.log) {
		self.minmax();
		self.k = @log(self.max / self.min) / self.run;
	} else {
		self.k = (self.max - self.min) / self.run;
	}
}

fn floatC(self: *const Self, f: pd.Float) callconv(.C) void {
	const res: pd.Float = @floatCast(if (self.log)
		@exp(f * self.k) * self.min
		else (f * self.k) + self.min);
	self.out.float(res);
}

export fn sly_setup() void {
	Self.setup(pd.symbol("sly"), @ptrCast(&floatC)) catch {};
}
