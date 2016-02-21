#include "../m_pd.h"
#include <math.h>

/* -------------------------- fton -------------------------- */

t_float fton(t_float f, t_float rt, t_float st)
{ return (f > 0 ? st * log(rt*f) : -1500); }

static t_class *fton_class;

typedef struct _fton {
    t_object x_obj;
    t_float x_rt, x_st;		/* root tone, semi-tone */
	t_float x_ref, x_tet;	/* ref-pitch, # of tones */
} t_fton;

static void fton_ref(t_fton *x, t_floatarg f)
{ x->x_rt = 1./ ((x->x_ref=f) * pow(2,-69/x->x_tet)); }

static void fton_tet(t_fton *x, t_floatarg f) {
	x->x_rt = 1./ (x->x_ref * pow(2,-69/f));
	x->x_st = 1./ (log(2) / (x->x_tet=f));
}

static void fton_float(t_fton *x, t_float f)
{ outlet_float(x->x_obj.ob_outlet, fton(f, x->x_rt, x->x_st)); }

static void *fton_new(t_symbol *s, int argc, t_atom *argv) {
	t_fton *x = (t_fton *)pd_new(fton_class);
	outlet_new(&x->x_obj, &s_float);
	t_float ref=440, tet=12;
	
	switch (argc) {
		case 2: tet = atom_getfloat(argv+1);
		case 1: ref = atom_getfloat(argv); }
	x->x_ref=ref, x->x_tet=tet;
	x->x_rt = 1./ (ref * pow(2,-69/tet));
	x->x_st = 1./ (log(2) / tet);
	return (x);
}

void fton_setup(void) {	
	fton_class = class_new(gensym("fton"),
		(t_newmethod)fton_new, 0,
		sizeof(t_fton), 0,
		A_GIMME, 0);
		
	class_addfloat(fton_class, fton_float);
	class_sethelpsymbol(fton_class, gensym("ntof.pd"));
	class_addmethod(fton_class, (t_method)fton_ref,
		gensym("ref"), A_FLOAT, 0);
	class_addmethod(fton_class, (t_method)fton_tet,
		gensym("tet"), A_FLOAT, 0);
}