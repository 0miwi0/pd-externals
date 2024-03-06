const pd = @import("pd");
const Self = @import("tet.zig").Tet(@This());

const ln2 = @import("std").math.ln2;

pub fn setK(self: *Self) void {
	self.k = self.tet / ln2;
}

pub fn setMin(self: *Self) void {
	self.min = @exp(69 / self.k) / self.ref;
}

fn floatC(self: *const Self, f: pd.Float) callconv(.C) void {
	self.out.float(@floatCast(@log(f * self.min) * self.k));
}

export fn fton_setup() void {
	Self.setup(pd.symbol("fton"), @ptrCast(&floatC)) catch {};
}
