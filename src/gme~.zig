pub const name = "gme~";
pub const nch = 2;

export fn gme_tilde_setup() void {
	@import("gme-rabbit.zig").Performer(@This()).setup() catch {};
}
