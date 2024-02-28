const pd = @import("pd");
const in = @import("inlet.zig");

pub const Tab2 = extern struct {
	const Self = @This();

	obj: pd.Object,
	hold: *pd.Float,
	vec: ?[*]pd.Word,
	arrayname: *pd.Symbol,
	f: pd.Float,

	fn holdC(self: *Self, f: pd.Float) callconv(.C) void {
		self.hold.* = f;
	}

	pub inline fn sample(w: [*]pd.Word, x: pd.Sample, hold: pd.Sample) pd.Sample {
		const h = 0.5 * @min(hold, 1);
		if (x < h) {
			return w[0].float;
		}
		if (x > 1 - h) {
			return w[1].float;
		}

		const y1 = w[0].float;
		const y2 = w[1].float;
		return (y2 - y1) / (1 - hold) * (x - h) + y1;
	}

	pub fn setArray(self: *Self, s: *pd.Symbol) !usize {
		errdefer self.vec = null;
		self.arrayname = s;

		const array: *pd.GArray = @ptrCast(pd.Class.garray.*.find(s)
			orelse return error.GArrayNotFound);

		const vec = try array.floatWords();
		const len = vec.len - 3;
		if (vec.len <= 3 or len & (len - 1) != 0) {
			return error.BadArraySize;
		}

		self.vec = vec.ptr;
		array.useInDsp();
		return len;
	}

	pub fn init(self: *Self, arrayname: *pd.Symbol, hold: pd.Float) !void {
		self.arrayname = arrayname;
		self.vec = null;

		const obj = &self.obj;
		const in2 = try obj.inletSignal(hold);
		const inr: *in.Inlet = @ptrCast(@alignCast(in2));
		self.hold = &inr.un.floatsignalvalue;

		_ = try obj.outlet(&pd.s_signal);
		self.f = 0;
	}

	pub fn extend(class: *pd.Class) void {
		class.doMainSignalIn(@offsetOf(Self, "f"));
		class.addMethod(@ptrCast(&holdC), pd.symbol("hold"), &.{ .float });
	}
};
