const pd = @import("pd");

pub const Inlet = extern struct {
  	pd: pd.Pd,
	next: ?*Inlet,
	owner: *pd.Object,
	dest: ?*pd.Pd,
	symfrom: *pd.Symbol,
	un: extern union {
		symto: *pd.Symbol,
		pointerslot: *pd.GPointer,
		floatslot: *pd.Float,
		symslot: **pd.Symbol,
		floatsignalvalue: pd.Float,
	},
};
