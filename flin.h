#include "m_pd.h"

struct _inlet {
	t_pd i_pd;
	struct _inlet *i_next;
	t_object *i_owner;
	t_pd *i_dest;
	t_symbol *i_symfrom;
	t_float *i_floatslot;
};

typedef struct _flin {
	t_object x_obj;
	t_float *fp; /* float array */
	int ninlets; /* number of inlets */
	int siz;     /* pointer size */
} t_flin;

#define NMAX 1024

static void flin_alloc(t_flin *x ,int n) {
	x->siz = n;
	x->fp = (t_float*)getbytes(x->siz * sizeof(t_float));
}

static int flin_resize(t_flin *x ,int n ,int isindex) {
	n += isindex;
	if (n < 1 || n > NMAX)
		return -1;
	int d = 2;
	while (d < n) d <<= 1;
	x->fp = (t_float *)resizebytes(x->fp
		,x->siz * sizeof(t_float) ,d * sizeof(t_float));
	x->siz = d;
	t_float *fp = x->fp;
	t_inlet *ip = ((t_object *)x)->ob_inlet;
	for (int i=x->ninlets; i--; fp++ ,ip=ip->i_next)
		ip->i_floatslot = fp;
	return (n - isindex);
}

static void flin_free(t_flin *x) {
	freebytes(x->fp ,x->siz * sizeof(t_float));
}
