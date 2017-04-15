#include "m_pd.h"
#include <time.h>

/* -------------------------- divrt -------------------------- */

static t_class *divrt_class;

typedef struct _divrt {
	t_object x_obj;
	t_float x_n, x_max;	// range, max repeats
	int x_prev, x_i;	// previous value, counter
	unsigned x_state;
} t_divrt;

static int divrt_time(void) {
	int thym = time(0) % 31536000; // seconds in a year
	return (thym|1); // odd numbers only
}

static int divrt_makeseed(void) {
	static unsigned divrt_next = 1267631501;
	divrt_next = divrt_next * divrt_time() + 938284287;
	return (divrt_next & 0x7fffffff);
}

static void divrt_seed(t_divrt *x, t_symbol *s, int argc, t_atom *argv) {
	x->x_state = (argc ? atom_getfloat(argv) : divrt_time());
}

static void divrt_peek(t_divrt *x, t_symbol *s) {
	post("%s%s%u", s->s_name, *s->s_name?": ":"", x->x_state);
}

static int nextr(t_divrt *x, int n) {
	int range = n<1?1:n, nval;
	unsigned state = x->x_state;
	x->x_state = state = state * 472940017 + 832416023;
	nval = (1./4294967296) * range * state;
	return nval;
}

static void divrt_float(t_divrt *x, t_float f) {
	int n=x->x_n, max=x->x_max, i=x->x_i, d=f;
	max = max<1?1:max;
	if (d==x->x_prev)
	{	if (i>=max)
		{	i=1, n=n<1?1:n;
			d = (nextr(x, n-1) + d+1) % n;   }
		else i++;   }
	else i=1;
	x->x_prev=d, x->x_i=i;
	outlet_float(x->x_obj.ob_outlet, d);
}

static void *divrt_new(t_floatarg n, t_floatarg max) {
	t_divrt *x = (t_divrt *)pd_new(divrt_class);
	x->x_n = n<1?3:n;
	x->x_max = max<1?2:max;
	x->x_state = divrt_makeseed();
	outlet_new(&x->x_obj, &s_float);
	floatinlet_new(&x->x_obj, &x->x_n);
	floatinlet_new(&x->x_obj, &x->x_max);
	return (x);
}

void divrt_setup(void) {
	divrt_class = class_new(gensym("divrt"),
		(t_newmethod)divrt_new, 0,
		sizeof(t_divrt), 0,
		A_DEFFLOAT, A_DEFFLOAT, 0);
	
	class_addfloat(divrt_class, divrt_float);
	class_addmethod(divrt_class, (t_method)divrt_seed,
		gensym("seed"), A_GIMME, 0);
	class_addmethod(divrt_class, (t_method)divrt_peek,
		gensym("peek"), A_DEFSYM, 0);
}
