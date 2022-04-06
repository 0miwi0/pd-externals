#include "m_pd.h"
#include <math.h>
#include <string.h> // strlen
#include <stdlib.h> // strtof

#if PD_FLOATSIZE == 32
# define POW powf
# define SQRT sqrtf
# define LOG logf
# define EXP expf
# define FABS fabsf
# define FMOD fmodf
# define FLOOR floorf
# define CEIL ceilf
#else
# define POW pow
# define SQRT sqrt
# define LOG log
# define EXP exp
# define FABS fabs
# define FMOD fmod
# define FLOOR floor
# define CEIL ceil
#endif

	// binop1:  +, -, *, /
static inline t_float blunt_plus  (t_float f1 ,t_float f2) { return (f1 + f2); }
static inline t_float blunt_minus (t_float f1 ,t_float f2) { return (f1 - f2); }
static inline t_float blunt_times (t_float f1 ,t_float f2) { return (f1 * f2); }
static inline t_float blunt_div   (t_float f1 ,t_float f2) { return (f2!=0 ? f1/f2 : 0); }

static inline t_float blunt_log(t_float f1 ,t_float f2) {
	return
	(	f1 <= 0 ? -1000
		: ( f2 <= 0 ? LOG(f1)
		: LOG(f1) / LOG(f2) )  );
}

static inline t_float blunt_pow(t_float f1 ,t_float f2) {
	return
	(	   (f1 == 0 && f2 < 0)
		|| (f1 <  0 && (f2 - (int)f2) != 0)
			? 0 : POW(f1 ,f2)  );
}

static inline t_float blunt_max(t_float f1 ,t_float f2) { return (f1 > f2 ? f1 : f2); }
static inline t_float blunt_min(t_float f1 ,t_float f2) { return (f1 < f2 ? f1 : f2); }

	// binop2: ==, !=, >, <, >=, <=
static inline t_float blunt_ee(t_float f1 ,t_float f2) { return (f1 == f2); }
static inline t_float blunt_ne(t_float f1 ,t_float f2) { return (f1 != f2); }
static inline t_float blunt_gt(t_float f1 ,t_float f2) { return (f1 >  f2); }
static inline t_float blunt_lt(t_float f1 ,t_float f2) { return (f1 <  f2); }
static inline t_float blunt_ge(t_float f1 ,t_float f2) { return (f1 >= f2); }
static inline t_float blunt_le(t_float f1 ,t_float f2) { return (f1 <= f2); }

	// binop3: &, |, &&, ||, <<, >>, ^, %, mod, div
static inline t_float blunt_ba  (t_float f1 ,t_float f2) { return ((int)f1 &  (int)f2); }
static inline t_float blunt_la  (t_float f1 ,t_float f2) { return ((int)f1 && (int)f2); }
static inline t_float blunt_bo  (t_float f1 ,t_float f2) { return ((int)f1 |  (int)f2); }
static inline t_float blunt_lo  (t_float f1 ,t_float f2) { return ((int)f1 || (int)f2); }
static inline t_float blunt_ls  (t_float f1 ,t_float f2) { return ((int)f1 << (int)f2); }
static inline t_float blunt_rs  (t_float f1 ,t_float f2) { return ((int)f1 >> (int)f2); }
static inline t_float blunt_xor (t_float f1 ,t_float f2) { return ((int)f1 ^  (int)f2); }
static inline t_float blunt_fpc (t_float f1 ,t_float f2) { return FMOD(f1 ,f2); }

static inline t_float blunt_pc(t_float f1 ,t_float f2) {
	int n2 = f2;
	return (n2 == -1) ? 0 : (int)f1 % (n2 ? n2 : 1);
}

static inline t_float blunt_mod(t_float f1 ,t_float f2) {
	int n2 = abs((int)f2) ,result;
	if (!n2) n2 = 1;
	result = (int)f1 % n2;
	if (result < 0) result += n2;
	return (t_float)result;
}

static inline t_float blunt_fmod(t_float f1 ,t_float f2) {
	f2 = FABS(f2);
	if (!f2) f2 = 1;
	t_float result = FMOD(f1 ,f2);
	if (result < 0) result += f2;
	return result;
}

static inline t_float blunt_divm(t_float f1 ,t_float f2) {
	int n1 = f1 ,n2 = abs((int)f2) ,result;
	if (!n2) n2 = 1;
	if (n1 < 0) n1 -= (n2-1);
	result = n1 / n2;
	return (t_float)result;
}

static inline t_float blunt_factorial(int d) {
	if (d > 8) // use stirling's approximation
		return POW(d ,d) * EXP(-d) * SQRT(d) * SQRT(2 * M_PI);

	t_float f = 1;
	while (d > 0) f *= d--;
	return f;
}

/* -------------------------- blunt base -------------------------- */
static t_symbol *s_load;
static t_symbol *s_init;
static t_symbol *s_close;

typedef enum {
	 LB_NONE  = -1
	,LB_LOAD  = 0   // "loadbang" actions - 0 for original meaning
	,LB_INIT  = 1   // loaded but not yet connected to parent patch
	,LB_CLOSE = 2   // about to close
} t_lbtype;

typedef struct {
	t_object obj;
	t_lbtype action;
} t_blunt;

static void blunt_loadbang(t_blunt *x ,t_float action) {
	if (x->action == action) pd_bang((t_pd*)x);
}

static void blunt_init(t_blunt *x ,int *ac ,t_atom *av) {
	x->action = LB_NONE;
	if (*ac && av[*ac-1].a_type == A_SYMBOL)
	{	t_symbol *lb = av[*ac-1].a_w.w_symbol;
		if      (lb == s_load)  x->action = LB_LOAD;
		else if (lb == s_init)  x->action = LB_INIT;
		else if (lb == s_close) x->action = LB_CLOSE;
		*ac -= (x->action != LB_NONE);  }
}

static inline void blunt_addmethod(t_class *c) {
	class_addmethod(c ,(t_method)blunt_loadbang ,gensym("loadbang") ,A_DEFFLOAT ,0);
}

/* -------------------------- blunt binops -------------------------- */
typedef struct {
	t_blunt bl;
	t_float f1;
	t_float f2;
} t_bop;

static void bop_print(t_bop *x ,t_symbol *s) {
	if (*s->s_name) startpost("%s: " ,s->s_name);
	startpost("%g %g" ,x->f1 ,x->f2);
	endpost();
}

static inline void bop_f1(t_bop *x ,t_float f) {
	x->f1 = f;
}

static inline void bop_f2(t_bop *x ,t_float f) {
	x->f2 = f;
}

static inline void bop_set(t_bop *x ,t_symbol *s ,int ac ,t_atom *av) {
	(void)s;
	if (ac > 1 && av[1].a_type == A_FLOAT) x->f2 = av[1].a_w.w_float;
	if (ac     && av[0].a_type == A_FLOAT) x->f1 = av[0].a_w.w_float;
}

static void bop_float(t_bop *x ,t_float f) {
	bop_f1(x ,f);
	pd_bang((t_pd*)x);
}

static void bop_list(t_bop *x ,t_symbol *s ,int ac ,t_atom *av) {
	bop_set(x ,s ,ac ,av);
	pd_bang((t_pd*)x);
}

static void bop_anything(t_bop *x ,t_symbol *s ,int ac ,t_atom *av) {
	(void)s;
	if (ac && av->a_type == A_FLOAT)
		x->f2 = av->a_w.w_float;
	pd_bang((t_pd*)x);
}

static void bop_init(t_bop *x ,int ac ,t_atom *av) {
	blunt_init(&x->bl ,&ac ,av);

	// set the 1st float, but only if there are 2 args
	x->f1 = (ac > 1 ? atom_getfloatarg(0 ,ac ,av++) : 0);
	x->f2 = (ac     ? atom_getfloatarg(0 ,ac ,av)   : 0);

	outlet_new(&x->bl.obj ,&s_float);
}

static t_bop *bop_new(t_class *cl ,t_symbol *s ,int ac ,t_atom *av) {
	(void)s;
	t_bop *x = (t_bop*)pd_new(cl);
	bop_init(x ,ac ,av);
	floatinlet_new(&x->bl.obj ,&x->f2);
	return (x);
}

static inline void bop_addmethods(t_class *c ,t_method bop_bang) {
	class_addbang     (c ,bop_bang);
	class_addfloat    (c ,bop_float);
	class_addlist     (c ,bop_list);
	class_addanything (c ,bop_anything);

	blunt_addmethod(c);
	class_addmethod(c ,(t_method)bop_print ,gensym("print") ,A_DEFSYM ,0);
	class_addmethod(c ,(t_method)bop_set   ,gensym("set")   ,A_GIMME  ,0);
	class_addmethod(c ,(t_method)bop_f1    ,gensym("f1")    ,A_FLOAT  ,0);
	class_addmethod(c ,(t_method)bop_f2    ,gensym("f2")    ,A_FLOAT  ,0);
}

static t_class *class_bop(t_symbol *s ,t_newmethod newmethod ,t_method bang) {
	t_class *c = class_new(s ,newmethod ,0 ,sizeof(t_bop) ,0 ,A_GIMME ,0);
	bop_addmethods(c ,bang);
	return c;
}
