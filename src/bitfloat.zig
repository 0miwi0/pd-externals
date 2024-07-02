const pd = @import("pd");
const std = @import("std");

pub const mantissa_bits = std.math.floatMantissaBits(pd.Float);
pub const exponent_bits = std.math.floatExponentBits(pd.Float);
pub const uf = std.meta.Int(.unsigned, @bitSizeOf(pd.Float));
pub const um = std.meta.Int(.unsigned, mantissa_bits);
pub const ue = std.meta.Int(.unsigned, exponent_bits);

pub const UnFloat = extern union {
	b: packed struct(uf) {
		m: um,
		e: ue,
		s: u1,
	},
	u: uf,
	f: pd.Float,
};
