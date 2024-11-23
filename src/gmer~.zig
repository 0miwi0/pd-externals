pub const name = "gmer~";
pub const nch = 2;

export fn gmer_tilde_setup() void {
	@import("gme-rubber.zig").Performer(@This()).setup() catch {};
}
