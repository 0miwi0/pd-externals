#include "inlet.h"
#include <string.h>
#include <samplerate.h>

#define FRAMES 0x10

static const double frames = FRAMES - .00001; // SRC gets stuck if too accurate
static const double inv_frames = 1. / FRAMES;

static t_symbol *s_open;
static t_symbol *s_play;

static t_atom (*fn_meta)(void* ,t_symbol*);

typedef struct {
	t_object obj;
	float     *in;
	float     *out;
	SRC_DATA   data;
	SRC_STATE *state;
	t_float   *speed;  /* playback speed */
	double     ratio;  /* resampling ratio */
	unsigned   play:1; /* play/pause toggle */
	unsigned   open:1; /* true when a file has been successfully opened */
	unsigned   nch;    /* number of channels */
	t_outlet  *o_meta; /* outputs track metadata */
} t_player;

static inline void player_reset(t_player *x) {
	src_reset(x->state);
	x->data.output_frames_gen = 0;
	x->data.input_frames = 0;
}

static inline void player_speed(t_player *x ,t_float f) {
	*x->speed = f;
	f *= x->ratio;
	f = f > frames ? frames : (f < inv_frames ? inv_frames : f);
	x->data.src_ratio = 1. / f;
}

static void player_interp(t_player *x ,t_float f) {
	int d = f;
	if (d < SRC_SINC_BEST_QUALITY || d > SRC_LINEAR)
		return;

	int err;
	src_delete(x->state);
	if ((x->state = src_new(d ,x->nch ,&err)) == NULL)
	{	post("Error : src_new() failed : %s." ,src_strerror(err));
		x->open = x->play = 0;  }
}

static inline t_atom player_time(t_player *x ,t_float ms) {
	return (t_atom){ .a_type=A_FLOAT ,.a_w={.w_float = ms} };
}

static inline t_atom player_ftime(t_player *x ,int64_t ms) {
	char time[33] ,*t = time;
	int64_t min =  ms / 60000;
	int     sec = (ms - 60000 * min) / 1000;
	if (min >= 60)
	{	sprintf(t ,"%d:" ,(int)min/60);
		t += strlen(t);  }
	sprintf(t ,"%02d:%02d" ,(int)min%60 ,sec);
	return (t_atom){ .a_type=A_SYMBOL ,.a_w={.w_symbol = gensym(time)} };
}

static void player_info_custom(t_player *x ,int ac ,t_atom *av) {
	for (; ac--; av++)
	if (av->a_type == A_SYMBOL)
	{	const char *sym = av->a_w.w_symbol->s_name ,*pct ,*end;
		while ( (pct = strchr(sym ,'%')) && (end = strchr(pct+1 ,'%')) )
		{	int len = pct - sym;
			if (len)
			{	char before[len + 1];
				strncpy(before ,sym ,len);
				before[len] = 0;
				startpost("%s" ,before);
				sym += len;  }
			pct++;
			len = end - pct;
			char buf[len + 1];
			strncpy(buf ,pct ,len);
			buf[len] = 0;
			t_atom meta = fn_meta(x ,gensym(buf));
			switch (meta.a_type)
			{	case A_FLOAT  : startpost("%g" ,meta.a_w.w_float);          break;
				case A_SYMBOL : startpost("%s" ,meta.a_w.w_symbol->s_name); break;
				default       : startpost("");  }
			sym += len + 2;  }
		startpost("%s%s" ,sym ,ac ? " " : "");  }
	else if (av->a_type == A_FLOAT)
		startpost("%g%s" ,av->a_w.w_float ,ac ? " " : "");
	endpost();
}

static void player_send(t_player *x ,t_symbol *s) {
	if (!x->open) return post("No file opened.");
	t_atom meta = fn_meta(x ,s);
	if (meta.a_type)
		outlet_anything(x->o_meta ,s ,1 ,&meta);
	else post("no metadata for '%s'" ,s->s_name);
}

static void player_anything(t_player *x ,t_symbol *s ,int ac ,t_atom *av) {
	player_send(x ,s);
}

static void player_play(t_player *x ,t_symbol *s ,int ac ,t_atom *av) {
	if (!x->open) return post("No file opened.");
	if (ac && av->a_type == A_FLOAT)
	{	int play = !!av->a_w.w_float;
		if (x->play == play) return;
		else x->play = play;  }
	else x->play = !x->play;
	t_atom play = { .a_type=A_FLOAT ,.a_w={.w_float = x->play} };
	outlet_anything(x->o_meta ,s_play ,1 ,&play);
}

static void player_bang(t_player *x) {
	player_play(x ,0 ,0 ,0);
}

static t_player *player_new(t_class *cl ,unsigned nch) {
	t_player *x = (t_player*)pd_new(cl);
	x->in  = (t_sample*)getbytes(nch * FRAMES * sizeof(t_sample));
	x->out = (t_sample*)getbytes(nch * FRAMES * sizeof(t_sample));
	x->nch = nch;

	int err;
	if ( !(x->state = src_new(SRC_LINEAR ,nch ,&err)) )
		post("Error : src_new() failed : %s." ,src_strerror(err));
	x->data.src_ratio = x->ratio = 1.;
	x->data.output_frames = FRAMES;

	t_inlet *in2 = signalinlet_new(&x->obj ,1.);
	x->speed = &in2->i_un.iu_floatsignalvalue;

	while (nch--) outlet_new(&x->obj ,&s_signal);
	x->o_meta = outlet_new(&x->obj ,0);

	x->open = x->play = 0;
	return (x);
}

static void player_free(t_player *x) {
	src_delete(x->state);
	freebytes(x->in  ,x->nch * FRAMES * sizeof(t_sample));
	freebytes(x->out ,x->nch * FRAMES * sizeof(t_sample));
}

static t_class *class_player
(t_symbol *s ,t_newmethod newm ,t_method free ,size_t size) {
	s_open = gensym("open");
	s_play = gensym("play");

	t_class *cls = class_new(s ,newm ,free ,size ,0 ,A_GIMME ,0);
	class_addbang     (cls ,player_bang);
	class_addanything (cls ,player_anything);

	class_addmethod(cls ,(t_method)player_speed  ,gensym("speed")  ,A_FLOAT  ,0);
	class_addmethod(cls ,(t_method)player_interp ,gensym("interp") ,A_FLOAT  ,0);
	class_addmethod(cls ,(t_method)player_send   ,gensym("send")   ,A_SYMBOL ,0);
	class_addmethod(cls ,(t_method)player_play   ,gensym("play")   ,A_GIMME  ,0);

	return cls;
}