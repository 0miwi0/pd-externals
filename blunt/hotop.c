#include "m_pd.h"
#include <string.h> // strlen
#include <stdlib.h> // strtof
#include <math.h>

/* --------------------------------------------------------------- */
/*                       hot arithmetics                           */
/* --------------------------------------------------------------- */

typedef struct _hot t_hot;
typedef void (*t_hotmethod)(t_hot *x);

struct _hot {
	t_object x_obj;
	t_float x_f1;
	t_float x_f2;
	t_pd *x_p;
	t_hotmethod x_bang;
	int x_lb;
};

typedef struct _pxy {
	t_object p_obj;
	t_hot *p_x;
} t_pxy;

static void hot_float(t_hot *x, t_float f) {
	x->x_f1 = f;
	x->x_bang(x);
}

static void hot_f2(t_hot *x, t_floatarg f) {
	x->x_f2 = f;
}

static void hot_skip(t_hot *x, t_symbol *s, int ac, t_atom *av) {
	if (ac && av->a_type == A_FLOAT)
		x->x_f2 = av->a_w.w_float;
	x->x_bang(x);
}

static void hot_loadbang(t_hot *x, t_floatarg action) {
	if (x->x_lb && !action) x->x_bang(x);
}

static void pxy_bang(t_pxy *p) {
	t_hot *x = p->p_x;
	x->x_bang(x);
}

static void pxy_float(t_pxy *p, t_float f) {
	t_hot *x = p->p_x;
	x->x_f2 = f;
	x->x_bang(x);
}

static void *hot_new
(t_class *fltclass, t_class *pxyclass,
 t_hotmethod fn, t_symbol *s, int ac, t_atom *av) {
	t_hot *x = (t_hot *)pd_new(fltclass);
	t_pd *proxy = pd_new(pxyclass);
	x->x_p = proxy;
	((t_pxy *)proxy)->p_x = x;
	outlet_new(&x->x_obj, &s_float);
	inlet_new(&x->x_obj, proxy, 0, 0);
	x->x_bang = fn;

	if (ac>1 && av->a_type == A_FLOAT)
	{	x->x_f1 = av->a_w.w_float;
		av++;   }
	else x->x_f1 = 0;

	if (ac)
	{	if (av->a_type == A_FLOAT)
			x->x_f2 = av->a_w.w_float;
		else if (av->a_type == A_SYMBOL)
		{	const char *c = av->a_w.w_symbol->s_name;
			if (c[strlen(c)-1] == '!')
			{	x->x_f2 = strtof(c, NULL);
				x->x_lb = 1;   }
			else x->x_f2 = 0;   }   }

	return (x);
}

static void hot_free(t_hot *x) {
	pd_free(x->x_p);
}


/* --------------------- binop1:  +, -, *, / --------------------- */

/* --------------------- addition -------------------------------- */
static t_class *hplus_class;
static t_class *hplus_proxy;

static void hplus_bang(t_hot *x) {
	outlet_float(x->x_obj.ob_outlet, x->x_f1 + x->x_f2);
}

static void *hplus_new(t_symbol *s, int ac, t_atom *av) {
	return (hot_new(hplus_class, hplus_proxy, hplus_bang, s, ac, av));
}

/* --------------------- subtraction ----------------------------- */
static t_class *hminus_class;
static t_class *hminus_proxy;

static void hminus_bang(t_hot *x) {
	outlet_float(x->x_obj.ob_outlet, x->x_f1 - x->x_f2);
}

static void *hminus_new(t_symbol *s, int ac, t_atom *av) {
	return (hot_new(hminus_class, hminus_proxy, hminus_bang, s, ac, av));
}

/* --------------------- multiplication -------------------------- */
static t_class *htimes_class;
static t_class *htimes_proxy;

static void htimes_bang(t_hot *x) {
	outlet_float(x->x_obj.ob_outlet, x->x_f1 * x->x_f2);
}

static void *htimes_new(t_symbol *s, int ac, t_atom *av) {
	return (hot_new(htimes_class, htimes_proxy, htimes_bang, s, ac, av));
}

/* --------------------- division -------------------------------- */
static t_class *hdiv_class;
static t_class *hdiv_proxy;

static void hdiv_bang(t_hot *x) {
	outlet_float(x->x_obj.ob_outlet,
		(x->x_f2 != 0 ? x->x_f1 / x->x_f2 : 0));
}

static void *hdiv_new(t_symbol *s, int ac, t_atom *av) {
	return (hot_new(hdiv_class, hdiv_proxy, hdiv_bang, s, ac, av));
}

/* --------------------- log ------------------------------------- */
static t_class *hlog_class;
static t_class *hlog_proxy;

static void hlog_bang(t_hot *x) {
	t_float r;
	if (x->x_f1 <= 0)
		r = -1000;
	else if (x->x_f2 <= 0)
		r = log(x->x_f1);
	else r = log(x->x_f1)/log(x->x_f2);
	outlet_float(x->x_obj.ob_outlet, r);
}

static void *hlog_new(t_symbol *s, int ac, t_atom *av) {
	return (hot_new(hlog_class, hlog_proxy, hlog_bang, s, ac, av));
}

/* --------------------- pow ------------------------------------- */
static t_class *hpow_class;
static t_class *hpow_proxy;

static void hpow_bang(t_hot *x) {
	t_float r = (x->x_f1 == 0 && x->x_f2 < 0) ||
		(x->x_f1 < 0 && (x->x_f2 - (int)x->x_f2) != 0) ?
			0 : pow(x->x_f1, x->x_f2);
	outlet_float(x->x_obj.ob_outlet, r);
}

static void *hpow_new(t_symbol *s, int ac, t_atom *av) {
	return (hot_new(hpow_class, hpow_proxy, hpow_bang, s, ac, av));
}

/* --------------------- max ------------------------------------- */
static t_class *hmax_class;
static t_class *hmax_proxy;

static void hmax_bang(t_hot *x) {
	outlet_float(x->x_obj.ob_outlet,
		(x->x_f1 > x->x_f2 ? x->x_f1 : x->x_f2));
}

static void *hmax_new(t_symbol *s, int ac, t_atom *av) {
	return (hot_new(hmax_class, hmax_proxy, hmax_bang, s, ac, av));
}

/* --------------------- min ------------------------------------- */
static t_class *hmin_class;
static t_class *hmin_proxy;

static void hmin_bang(t_hot *x) {
	outlet_float(x->x_obj.ob_outlet,
		(x->x_f1 < x->x_f2 ? x->x_f1 : x->x_f2));
}

static void *hmin_new(t_symbol *s, int ac, t_atom *av) {
	return (hot_new(hmin_class, hmin_proxy, hmin_bang, s, ac, av));
}

/* --------------- binop2: ==, !=, >, <, >=, <=. ----------------- */

/* --------------------- == -------------------------------------- */
static t_class *hee_class;
static t_class *hee_proxy;

static void hee_bang(t_hot *x) {
	outlet_float(x->x_obj.ob_outlet, x->x_f1 == x->x_f2);
}

static void *hee_new(t_symbol *s, int ac, t_atom *av) {
	return (hot_new(hee_class, hee_proxy, hee_bang, s, ac, av));
}

/* --------------------- != -------------------------------------- */
static t_class *hne_class;
static t_class *hne_proxy;

static void hne_bang(t_hot *x) {
	outlet_float(x->x_obj.ob_outlet, x->x_f1 != x->x_f2);
}

static void *hne_new(t_symbol *s, int ac, t_atom *av) {
	return (hot_new(hne_class, hne_proxy, hne_bang, s, ac, av));
}

/* --------------------- > --------------------------------------- */
static t_class *hgt_class;
static t_class *hgt_proxy;

static void hgt_bang(t_hot *x) {
	outlet_float(x->x_obj.ob_outlet, x->x_f1 > x->x_f2);
}

static void *hgt_new(t_symbol *s, int ac, t_atom *av) {
	return (hot_new(hgt_class, hgt_proxy, hgt_bang, s, ac, av));
}

/* --------------------- < --------------------------------------- */
static t_class *hlt_class;
static t_class *hlt_proxy;

static void hlt_bang(t_hot *x) {
	outlet_float(x->x_obj.ob_outlet, x->x_f1 < x->x_f2);
}

static void *hlt_new(t_symbol *s, int ac, t_atom *av) {
	return (hot_new(hlt_class, hlt_proxy, hlt_bang, s, ac, av));
}

/* --------------------- >= -------------------------------------- */
static t_class *hge_class;
static t_class *hge_proxy;

static void hge_bang(t_hot *x) {
	outlet_float(x->x_obj.ob_outlet, x->x_f1 >= x->x_f2);
}

static void *hge_new(t_symbol *s, int ac, t_atom *av) {
	return (hot_new(hge_class, hge_proxy, hge_bang, s, ac, av));
}

/* --------------------- <= -------------------------------------- */
static t_class *hle_class;
static t_class *hle_proxy;

static void hle_bang(t_hot *x) {
	outlet_float(x->x_obj.ob_outlet, x->x_f1 <= x->x_f2);
}

static void *hle_new(t_symbol *s, int ac, t_atom *av) {
	return (hot_new(hle_class, hle_proxy, hle_bang, s, ac, av));
}

/* ------- binop3: &, |, &&, ||, <<, >>, %, ^, mod, div ------------- */

/* --------------------- & --------------------------------------- */
static t_class *hba_class;
static t_class *hba_proxy;

static void hba_bang(t_hot *x) {
	outlet_float(x->x_obj.ob_outlet, ((int)(x->x_f1)) & (int)(x->x_f2));
}

static void *hba_new(t_symbol *s, int ac, t_atom *av) {
	return (hot_new(hba_class, hba_proxy, hba_bang, s, ac, av));
}

/* --------------------- && -------------------------------------- */
static t_class *hla_class;
static t_class *hla_proxy;

static void hla_bang(t_hot *x) {
	outlet_float(x->x_obj.ob_outlet, ((int)(x->x_f1)) && (int)(x->x_f2));
}

static void *hla_new(t_symbol *s, int ac, t_atom *av) {
	return (hot_new(hla_class, hla_proxy, hla_bang, s, ac, av));
}

/* --------------------- | --------------------------------------- */
static t_class *hbo_class;
static t_class *hbo_proxy;

static void hbo_bang(t_hot *x) {
	outlet_float(x->x_obj.ob_outlet, ((int)(x->x_f1)) | (int)(x->x_f2));
}

static void *hbo_new(t_symbol *s, int ac, t_atom *av) {
	return (hot_new(hbo_class, hbo_proxy, hbo_bang, s, ac, av));
}

/* --------------------- || -------------------------------------- */
static t_class *hlo_class;
static t_class *hlo_proxy;

static void hlo_bang(t_hot *x) {
	outlet_float(x->x_obj.ob_outlet, ((int)(x->x_f1)) || (int)(x->x_f2));
}

static void *hlo_new(t_symbol *s, int ac, t_atom *av) {
	return (hot_new(hlo_class, hlo_proxy, hlo_bang, s, ac, av));
}

/* --------------------- << -------------------------------------- */
static t_class *hls_class;
static t_class *hls_proxy;

static void hls_bang(t_hot *x) {
	outlet_float(x->x_obj.ob_outlet, ((int)(x->x_f1)) << (int)(x->x_f2));
}

static void *hls_new(t_symbol *s, int ac, t_atom *av) {
	return (hot_new(hls_class, hls_proxy, hls_bang, s, ac, av));
}

/* --------------------- >> -------------------------------------- */
static t_class *hrs_class;
static t_class *hrs_proxy;

static void hrs_bang(t_hot *x) {
	outlet_float(x->x_obj.ob_outlet, ((int)(x->x_f1)) >> (int)(x->x_f2));
}

static void *hrs_new(t_symbol *s, int ac, t_atom *av) {
	return (hot_new(hrs_class, hrs_proxy, hrs_bang, s, ac, av));
}

/* --------------------- % --------------------------------------- */
static t_class *hpc_class;
static t_class *hpc_proxy;

static void hpc_bang(t_hot *x) {
	int n2 = x->x_f2;
		/* apparently "%" raises an exception for INT_MIN and -1 */
	if (n2 == -1)
		outlet_float(x->x_obj.ob_outlet, 0);
	else outlet_float(x->x_obj.ob_outlet, ((int)(x->x_f1)) % (n2 ? n2 : 1));
}

static void *hpc_new(t_symbol *s, int ac, t_atom *av) {
	return (hot_new(hpc_class, hpc_proxy, hpc_bang, s, ac, av));
}

/* --------------------- ^ --------------------------------------- */
static t_class *hxor_class;
static t_class *hxor_proxy;

static void hxor_bang(t_hot *x) {
	outlet_float(x->x_obj.ob_outlet, ((int)(x->x_f1)) ^ (int)(x->x_f2));
}

static void *hxor_new(t_symbol *s, int ac, t_atom *av) {
	return (hot_new(hxor_class, hxor_proxy, hxor_bang, s, ac, av));
}

/* --------------------- mod ------------------------------------- */
static t_class *hmod_class;
static t_class *hmod_proxy;

static void hmod_bang(t_hot *x) {
	int n2 = x->x_f2, result;
	if (n2 < 0) n2 = -n2;
	else if (!n2) n2 = 1;
	result = (int)x->x_f1 % n2;
	if (result < 0) result += n2;
	outlet_float(x->x_obj.ob_outlet, result);
}

static void *hmod_new(t_symbol *s, int ac, t_atom *av) {
	return (hot_new(hmod_class, hmod_proxy, hmod_bang, s, ac, av));
}

/* --------------------- div ------------------------------------- */
static t_class *hdivm_class;
static t_class *hdivm_proxy;

static void hdivm_bang(t_hot *x) {
	int n1 = x->x_f1, n2 = x->x_f2, result;
	if (n2 < 0) n2 = -n2;
	else if (!n2) n2 = 1;
	if (n1 < 0) n1 -= (n2-1);
	result = n1 / n2;
	outlet_float(x->x_obj.ob_outlet, result);
}

static void *hdivm_new(t_symbol *s, int ac, t_atom *av) {
	return (hot_new(hdivm_class, hdivm_proxy, hdivm_bang, s, ac, av));
}

void hotop_setup(void) {
	/* ------------------ binop1 ----------------------- */

	hplus_class = class_new(gensym("#+"),
		(t_newmethod)hplus_new, (t_method)hot_free,
		sizeof(t_hot), 0, A_GIMME, 0);
	class_addbang(hplus_class, hplus_bang);
	hplus_proxy = class_new(gensym("_#+_pxy"), 0, 0,
		sizeof(t_pxy), CLASS_PD | CLASS_NOINLET, 0);

	hminus_class = class_new(gensym("#-"),
		(t_newmethod)hminus_new, (t_method)hot_free,
		sizeof(t_hot), 0, A_GIMME, 0);
	class_addbang(hminus_class, hminus_bang);
	hminus_proxy = class_new(gensym("_#-_pxy"), 0, 0,
		sizeof(t_pxy), CLASS_PD | CLASS_NOINLET, 0);

	htimes_class = class_new(gensym("#*"),
		(t_newmethod)htimes_new, (t_method)hot_free,
		sizeof(t_hot), 0, A_GIMME, 0);
	class_addbang(htimes_class, htimes_bang);
	htimes_proxy = class_new(gensym("_#*_pxy"), 0, 0,
		sizeof(t_pxy), CLASS_PD | CLASS_NOINLET, 0);

	hdiv_class = class_new(gensym("#/"),
		(t_newmethod)hdiv_new, (t_method)hot_free,
		sizeof(t_hot), 0, A_GIMME, 0);
	class_addbang(hdiv_class, hdiv_bang);
	hdiv_proxy = class_new(gensym("_#/_pxy"), 0, 0,
		sizeof(t_pxy), CLASS_PD | CLASS_NOINLET, 0);

	hlog_class = class_new(gensym("#log"),
		(t_newmethod)hlog_new, (t_method)hot_free,
		sizeof(t_hot), 0, A_GIMME, 0);
	class_addbang(hlog_class, hlog_bang);
	hlog_proxy = class_new(gensym("_#log_pxy"), 0, 0,
		sizeof(t_pxy), CLASS_PD | CLASS_NOINLET, 0);

	hpow_class = class_new(gensym("#pow"),
		(t_newmethod)hpow_new, (t_method)hot_free,
		sizeof(t_hot), 0, A_GIMME, 0);
	class_addbang(hpow_class, hpow_bang);
	hpow_proxy = class_new(gensym("_#pow_pxy"), 0, 0,
		sizeof(t_pxy), CLASS_PD | CLASS_NOINLET, 0);

	hmax_class = class_new(gensym("#max"),
		(t_newmethod)hmax_new, (t_method)hot_free,
		sizeof(t_hot), 0, A_GIMME, 0);
	class_addbang(hmax_class, hmax_bang);
	hmax_proxy = class_new(gensym("_#max_pxy"), 0, 0,
		sizeof(t_pxy), CLASS_PD | CLASS_NOINLET, 0);

	hmin_class = class_new(gensym("#min"),
		(t_newmethod)hmin_new, (t_method)hot_free,
		sizeof(t_hot), 0, A_GIMME, 0);
	class_addbang(hmin_class, hmin_bang);
	hmin_proxy = class_new(gensym("_#min_pxy"), 0, 0,
		sizeof(t_pxy), CLASS_PD | CLASS_NOINLET, 0);

	/* ------------------ binop2 ----------------------- */

	hee_class = class_new(gensym("#=="),
		(t_newmethod)hee_new, (t_method)hot_free,
		sizeof(t_hot), 0, A_GIMME, 0);
	class_addbang(hee_class, hee_bang);
	hee_proxy = class_new(gensym("_#==_pxy"), 0, 0,
		sizeof(t_pxy), CLASS_PD | CLASS_NOINLET, 0);

	hne_class = class_new(gensym("#!="),
		(t_newmethod)hne_new, (t_method)hot_free,
		sizeof(t_hot), 0, A_GIMME, 0);
	class_addbang(hne_class, hne_bang);
	hne_proxy = class_new(gensym("_#!=_pxy"), 0, 0,
		sizeof(t_pxy), CLASS_PD | CLASS_NOINLET, 0);

	hgt_class = class_new(gensym("#>"),
		(t_newmethod)hgt_new, (t_method)hot_free,
		sizeof(t_hot), 0, A_GIMME, 0);
	class_addbang(hgt_class, hgt_bang);
	hgt_proxy = class_new(gensym("_#>_pxy"), 0, 0,
		sizeof(t_pxy), CLASS_PD | CLASS_NOINLET, 0);

	hlt_class = class_new(gensym("#<"),
		(t_newmethod)hlt_new, (t_method)hot_free,
		sizeof(t_hot), 0, A_GIMME, 0);
	class_addbang(hlt_class, hlt_bang);
	hlt_proxy = class_new(gensym("_#<_pxy"), 0, 0,
		sizeof(t_pxy), CLASS_PD | CLASS_NOINLET, 0);

	hge_class = class_new(gensym("#>="),
		(t_newmethod)hge_new, (t_method)hot_free,
		sizeof(t_hot), 0, A_GIMME, 0);
	class_addbang(hge_class, hge_bang);
	hge_proxy = class_new(gensym("_#>=_pxy"), 0, 0,
		sizeof(t_pxy), CLASS_PD | CLASS_NOINLET, 0);

	hle_class = class_new(gensym("#<="),
		(t_newmethod)hle_new, (t_method)hot_free,
		sizeof(t_hot), 0, A_GIMME, 0);
	class_addbang(hle_class, hle_bang);
	hle_proxy = class_new(gensym("_#<=_pxy"), 0, 0,
		sizeof(t_pxy), CLASS_PD | CLASS_NOINLET, 0);

	/* ------------------ binop3 ----------------------- */

	hba_class = class_new(gensym("#&"),
		(t_newmethod)hba_new, (t_method)hot_free,
		sizeof(t_hot), 0, A_GIMME, 0);
	class_addbang(hba_class, hba_bang);
	hba_proxy = class_new(gensym("_#&_pxy"), 0, 0,
		sizeof(t_pxy), CLASS_PD | CLASS_NOINLET, 0);

	hla_class = class_new(gensym("#&&"),
		(t_newmethod)hla_new, (t_method)hot_free,
		sizeof(t_hot), 0, A_GIMME, 0);
	class_addbang(hla_class, hla_bang);
	hla_proxy = class_new(gensym("_#&&_pxy"), 0, 0,
		sizeof(t_pxy), CLASS_PD | CLASS_NOINLET, 0);

	hbo_class = class_new(gensym("#|"),
		(t_newmethod)hbo_new, (t_method)hot_free,
		sizeof(t_hot), 0, A_GIMME, 0);
	class_addbang(hbo_class, hbo_bang);
	hbo_proxy = class_new(gensym("_#|_pxy"), 0, 0,
		sizeof(t_pxy), CLASS_PD | CLASS_NOINLET, 0);

	hlo_class = class_new(gensym("#||"),
		(t_newmethod)hlo_new, (t_method)hot_free,
		sizeof(t_hot), 0, A_GIMME, 0);
	class_addbang(hlo_class, hlo_bang);
	hlo_proxy = class_new(gensym("_#||_pxy"), 0, 0,
		sizeof(t_pxy), CLASS_PD | CLASS_NOINLET, 0);

	hls_class = class_new(gensym("#<<"),
		(t_newmethod)hls_new, (t_method)hot_free,
		sizeof(t_hot), 0, A_GIMME, 0);
	class_addbang(hls_class, hls_bang);
	hls_proxy = class_new(gensym("_#<<_pxy"), 0, 0,
		sizeof(t_pxy), CLASS_PD | CLASS_NOINLET, 0);

	hrs_class = class_new(gensym("#>>"),
		(t_newmethod)hrs_new, (t_method)hot_free,
		sizeof(t_hot), 0, A_GIMME, 0);
	class_addbang(hrs_class, hrs_bang);
	hrs_proxy = class_new(gensym("_#>>_pxy"), 0, 0,
		sizeof(t_pxy), CLASS_PD | CLASS_NOINLET, 0);

	hpc_class = class_new(gensym("#%"),
		(t_newmethod)hpc_new, (t_method)hot_free,
		sizeof(t_hot), 0, A_GIMME, 0);
	class_addbang(hpc_class, hpc_bang);
	hpc_proxy = class_new(gensym("_#%_pxy"), 0, 0,
		sizeof(t_pxy), CLASS_PD | CLASS_NOINLET, 0);

	hxor_class = class_new(gensym("#^"),
		(t_newmethod)hxor_new, (t_method)hot_free,
		sizeof(t_hot), 0, A_GIMME, 0);
	class_addbang(hpc_class, hpc_bang);
	hxor_proxy = class_new(gensym("_#^_pxy"), 0, 0,
		sizeof(t_pxy), CLASS_PD | CLASS_NOINLET, 0);

	hmod_class = class_new(gensym("#mod"),
		(t_newmethod)hmod_new, (t_method)hot_free,
		sizeof(t_hot), 0, A_GIMME, 0);
	class_addbang(hmod_class, hmod_bang);
	hmod_proxy = class_new(gensym("_#mod_pxy"), 0, 0,
		sizeof(t_pxy), CLASS_PD | CLASS_NOINLET, 0);

	hdivm_class = class_new(gensym("#div"),
		(t_newmethod)hdivm_new, (t_method)hot_free,
		sizeof(t_hot), 0, A_GIMME, 0);
	class_addbang(hdivm_class, hdivm_bang);
	hdivm_proxy = class_new(gensym("_#div_pxy"), 0, 0,
		sizeof(t_pxy), CLASS_PD | CLASS_NOINLET, 0);

	t_class *hots[][9] =
	{	{	hplus_class, hminus_class, htimes_class, hdiv_class,
			hlog_class, hpow_class, hmax_class, hmin_class   },

		{	hee_class, hne_class,
			hgt_class, hlt_class, hge_class, hle_class   },

		{	hba_class, hla_class, hbo_class, hlo_class, hls_class, hrs_class,
			hpc_class, hmod_class, hdivm_class   },

		{	hxor_class   }   };

	t_class *pxys[][9] =
	{	{	hplus_proxy, hminus_proxy, htimes_proxy, hdiv_proxy,
			hlog_proxy, hpow_proxy, hmax_proxy, hmin_proxy   },

		{	hee_proxy, hne_proxy,
			hgt_proxy, hlt_proxy, hge_proxy, hle_proxy   },

		{	hba_proxy, hla_proxy, hbo_proxy, hlo_proxy, hls_proxy, hrs_proxy,
			hpc_proxy, hmod_proxy, hdivm_proxy   },

		{	hxor_proxy   }   };

	t_symbol *syms[] =
	{	gensym("hotbinops1"), gensym("hotbinops2"), gensym("hotbinops3"),
		gensym("0x5e")   };

	int i = sizeof(syms) / sizeof*(syms);
	while (i--)
	{	int j = 0, max = sizeof(hots[i]) / sizeof*(hots[i]);
		for (; j < max; j++)
		{	if (hots[i][j] == 0) continue;
			class_addfloat(hots[i][j], hot_float);
			class_addmethod(hots[i][j], (t_method)hot_f2,
				gensym("f2"), A_FLOAT, 0);
			class_addmethod(hots[i][j], (t_method)hot_skip,
				gensym("."), A_GIMME, 0);
			class_addmethod(hots[i][j], (t_method)hot_loadbang,
				gensym("loadbang"), A_DEFFLOAT, 0);

			class_addbang(pxys[i][j], pxy_bang);
			class_addfloat(pxys[i][j], pxy_float);

			class_sethelpsymbol(hots[i][j], syms[i]);   }   }
}
