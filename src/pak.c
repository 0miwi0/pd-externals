#include "pak.h"

/* -------------------------- pak ------------------------------ */
static t_class *pak_class;
static t_class *pak_proxy;

static void *pak_new(t_symbol *s ,int argc ,t_atom *argv) {
	return new_pak(pak_class ,pak_proxy ,s ,argc ,argv ,0);
}

static void pak_pointer(t_pak *x ,t_gpointer *gp) {
	pak_p(x ,x->ptr ,gp ,0);
}

static void pak_pxy_pointer(t_pak_pxy *p ,t_gpointer *gp) {
	pak_p(p->x ,p->ptr ,gp ,p->idx);
}

static int pak_l(t_pak *x ,int ac ,t_atom *av ,int i) {
	int ins = x->n - i ,result = 1;
	t_atom *vp     = x->vec  + i;
	t_atomtype *tp = x->type + i;
	t_pak_pxy **pp = x->ins  + (i-1);
	for (; ac-- && ins--; i++ ,vp++ ,tp++ ,pp++ ,av++)
	{	if (av->a_type == A_SYMBOL && !strcmp(av->a_w.w_symbol->s_name ,"."))
			continue;
		t_gpointer *ptr = i ? (*pp)->ptr : x->ptr;
		if (!pak_set(vp ,ptr ,*av ,*tp) && ((x->mute >> i) & 1))
		{	if (i) pd_error(x ,"inlet: expected '%s' but got '%s'"
				,pak_check(*tp) ,pak_check(av->a_type));
			else
			{	pd_error(x ,"pak_%s: wrong type" ,pak_check(av->a_type));
				result = 0;  }  }  }
	return result;
}

void pak_setup(void) {
	pak_class = class_new(gensym("pak")
		,(t_newmethod)pak_new ,(t_method)pak_free
		,sizeof(t_pak) ,0
		,A_GIMME ,0);
	pak_proxy = class_new(gensym("_pak_pxy") ,0 ,0
		,sizeof(t_pak_pxy) ,CLASS_PD | CLASS_NOINLET ,0);
	class_addpak(pak_class ,pak_proxy);
	class_addpointer(pak_class ,pak_pointer);
	class_addpointer(pak_proxy ,pak_pxy_pointer);
}
