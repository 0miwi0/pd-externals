#define NCH 2
#include "gme~.h"

/* -------------------------- gme~ ------------------------------ */
static t_class *gme_tilde_class;

static void gme_tilde_dsp(t_gme_tilde *x, t_signal **sp) {
	dsp_add(gme_tilde_perform, NCH+2, x,
		sp[0]->s_vec, sp[1]->s_vec, sp[0]->s_n);
}

static void *gme_tilde_new(t_symbol *s, int ac, t_atom *av) {
	return (gme_new(gme_tilde_class, s, ac, av));
}

extern "C" EXPORT void gme_tilde_setup(void) {
	gme_tilde_class = gme_setup(gensym("gme~"), (t_newmethod)gme_tilde_new);
	class_addmethod(gme_tilde_class, (t_method)gme_tilde_dsp,
		gensym("dsp"), A_CANT, 0);
}
