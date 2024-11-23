pub const name = "gmes~";
pub const nch = 16;

export fn gmes_tilde_setup() void {
	@import("gme-rabbit.zig").Performer(@This()).setup() catch {};
}
