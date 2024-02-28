const pd = @import("pd");

pub const Rng = extern struct {
	const Self = @This();
	var seed: u32 = undefined;

	obj: pd.Object,
	state: u32,

	fn printC(self: *const Self) callconv(.C) void {
		pd.post.log(self, .normal, "%u", .{ self.state });
	}

	fn seedC(self: *Self, f: pd.Float) callconv(.C) void {
		self.state = @intFromFloat(f);
	}

	pub fn next(self: *Self) pd.Float {
		self.state = self.state *% 472940017 +% 832416023;
		return @as(pd.Float, @floatFromInt(self.state)) * 0x1p-32;
	}

	pub fn init(self: *Self) void {
		seed = seed *% 435898247 +% 938284287;
		self.state = seed;
	}

	pub fn extend(class: *pd.Class) !void {
		const std = @import("std");
		try std.posix.getrandom(std.mem.asBytes(&seed));
		seed |= 1; // odd numbers only

		class.addMethod(@ptrCast(&seedC), pd.symbol("seed"), &.{ .float });
		class.addMethod(@ptrCast(&printC), pd.symbol("state"), &.{});
	}
};
