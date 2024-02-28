const pd = @import("pd");
const inl = @import("inlet.zig");

pub const WInlet = extern struct {
	const Self = @This();

	owner: *pd.Object,
	ptr: [*]pd.Word,
	len: usize,

	pub fn print(self: *const Self) void {
		pd.logpost(self, .normal, "ptr_len = %u", self.len);
	}

	pub fn resize(self: *Self, size: usize) !void {
		if (size > self.len) {
			// smallest power of 2 that can accommodate new size
			const n = @as(usize, 2) << pd.ulog2(size - 1);
			const vec = try pd.mem.realloc(self.ptr[0..self.len], n);
			self.ptr = vec.ptr;
			self.len = vec.len;

			// re-associate inlets with float slots
			var i: u32 = 0;
			var in: ?*inl.Inlet = @ptrCast(@alignCast(self.owner.inlets));
			while (in) |ip| : ({ in = ip.next; i += 1; }) {
				ip.un.floatslot = &self.ptr[i].float;
			}
		}
	}

	pub fn init(self: *Self, owner: *pd.Object, len: usize) !void {
		self.owner = owner;
		const vec = try pd.mem.alloc(pd.Word, len);
		self.ptr = vec.ptr;
		self.len = vec.len;
	}

	pub fn free(self: *Self) void {
		pd.mem.free(self.ptr[0..self.len]);
	}
};
