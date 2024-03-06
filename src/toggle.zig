const pd = @import("pd");

pub fn set(tgl: *bool, state: bool) bool {
	if (tgl.* == state) {
		return false;
	}
	tgl.* = state;
	return true;
}

pub fn toggle(tgl: *bool, av: []const pd.Atom) bool {
	return set(tgl, if (av.len >= 1 and av[0].type == .float)
		(av[0].w.float != 0) else !tgl.*);
}
