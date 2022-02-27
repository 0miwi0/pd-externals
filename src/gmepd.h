/*
Game_Music_Emu library copyright (C) 2003-2009 Shay Green.
Sega Genesis YM2612 emulator copyright (C) 2002 Stephane Dallongeville.
MAME YM2612 emulator copyright (C) 2003 Jarek Burczynski, Tatsuyuki Satoh
Nuked OPN2 emulator copyright (C) 2017 Alexey Khokholov (Nuke.YKT)

--
Shay Green <gblargg@gmail.com>
*/

#include "m_pd.h"
#include <gme.h>
#include <string.h>
#include <samplerate.h>

#ifndef NCH
#define NCH 2
#endif

#define FRAMES 0x10

enum { buf_size = NCH * FRAMES };

static const double frames = FRAMES;
static const double inv_frames = 1. / FRAMES;
static const float short_limit = 0x8000;

static t_symbol *s_open;
static t_symbol *s_play;
static t_symbol *s_mask;

/* ------------------------- Game Music Emu player ------------------------- */
typedef struct {
	t_object obj;
	float      in[buf_size];
	float      out[buf_size];
	SRC_DATA   data;
	SRC_STATE *state;
	Music_Emu *emu;
	gme_info_t *info; /* current track info */
	t_symbol *path;   /* path to the most recently read file */
	double   tempo;   /* current tempo */
	int      mask;    /* muting mask */
	int      voices;  /* number of voices */
	unsigned open:1;  /* true when a track has been successfully started */
	unsigned play:1;  /* play/pause toggle */
	t_outlet *o_meta; /* outputs track metadata */
} t_gme;

static inline void gmepd_reset_src(t_gme *x) {
	src_reset(x->state);
	x->data.output_frames_gen = 0;
	x->data.input_frames = 0;
}

static void gmepd_seek(t_gme *x ,t_float f) {
	if (!x->open) return; // quietly
	gme_seek(x->emu ,f);
	gme_set_fade(x->emu ,-1 ,0);
	gmepd_reset_src(x);
}

static t_int *gmepd_perform(t_int *w) {
	t_gme *x = (t_gme*)(w[1]);
	t_sample *outs[NCH];
	for (int i=NCH; i--;)
		outs[i] = (t_sample*)(w[i+2]);
	int n = (int)(w[NCH+2]);

	if (x->play)
	{	SRC_DATA *data = &x->data;
		while (n--)
		{	if (data->output_frames_gen > 0)
			{	perform:
				for (int i = NCH; i--;)
					*outs[i]++ = data->data_out[i];
				data->data_out += NCH;
				data->output_frames_gen--;
				continue;
			}
			else if (data->input_frames > 0)
			{	resample:
				data->data_out = x->out;
				src_process(x->state ,data);
				data->input_frames -= data->input_frames_used;
				data->data_in += data->input_frames_used * NCH;
				goto perform;
			}
			else
			{	// receive
				data->data_in = x->in;
				float *in = x->in;
				short arr[buf_size] ,*buf = arr;
				gme_play(x->emu ,buf_size ,buf);
				for (int i = buf_size; i--; in++ ,buf++)
					*in = *buf / short_limit;
				data->input_frames = FRAMES;
				goto resample;
			}
		}
	}
	else while (n--)
		for (int i = NCH; i--;)
			*outs[i]++ = 0;
	return (w+NCH+3);
}

static void gmepd_speed(t_gme *x ,t_float f) {
	f = f > frames ? frames : (f < inv_frames ? inv_frames : f);
	x->data.src_ratio = 1. / f;
}

static void gmepd_tempo(t_gme *x ,t_float f) {
	x->tempo = f;
	if (x->emu) gme_set_tempo(x->emu ,x->tempo);
}

static void gmepd_interp(t_gme *x ,t_float f) {
	int d = f;
	if (d < SRC_SINC_BEST_QUALITY || d > SRC_LINEAR)
		return;

	int err;
	src_delete(x->state);
	if ((x->state = src_new(d ,NCH ,&err)) == NULL)
	{	post("Error : src_new() failed : %s." ,src_strerror(err));
		x->open = x->play = 0;  }
}

static inline int domask(int mask ,int voices ,int ac ,t_atom *av) {
	for (; ac--; av++) if (av->a_type == A_FLOAT)
	{	int d = av->a_w.w_float;
		if (!d)
		{	mask = 0;
			continue;  }
		if (d > 0) d--;
		d %= voices;
		if (d < 0) d += voices;
		mask ^= 1 << d;  }
	return mask;
}

static void gmepd_mute(t_gme *x ,t_symbol *s ,int ac ,t_atom *av) {
	x->mask = domask(x->mask ,x->voices ,ac ,av);
	if (x->emu) gme_mute_voices(x->emu ,x->mask);
}

static void gmepd_solo(t_gme *x ,t_symbol *s ,int ac ,t_atom *av) {
	int mask = domask(~0 ,x->voices ,ac ,av);
	mask &= (1 << x->voices) - 1;
	x->mask = (x->mask == mask ? 0 : mask);
	if (x->emu) gme_mute_voices(x->emu ,x->mask);
}

static void gmepd_mask(t_gme *x ,t_symbol *s ,int ac ,t_atom *av) {
	if (ac && av->a_type == A_FLOAT)
	{	x->mask = av->a_w.w_float;
		if (x->emu) gme_mute_voices(x->emu ,x->mask);  }
	else
	{	t_atom flt = { .a_type=A_FLOAT ,.a_w={.w_float = x->mask} };
		outlet_anything(x->o_meta ,s_mask ,1 ,&flt);  }
}

static gme_err_t gmepd_load(t_gme *x ,int index) {
	if (!x->state)
		return "SRC has not been initialized";

	gme_err_t err_msg;
	if ( (err_msg = gme_start_track(x->emu ,index)) )
		return err_msg;

	gme_free_info(x->info);
	if ( (err_msg = gme_track_info(x->emu ,&x->info ,index)) )
		return err_msg;

	gme_set_fade(x->emu ,-1 ,0);
	gmepd_reset_src(x);
	return 0;
}

static void gmepd_open(t_gme *x ,t_symbol *s) {
	x->play = 0;
	gme_err_t err_msg;
	gme_delete(x->emu); x->emu = NULL;
	if ( !(err_msg = gme_open_file(s->s_name ,&x->emu ,sys_getsr() ,NCH > 2)) )
	{	// check for a .m3u file of the same name
		char m3u_path [256 + 5];
		strncpy(m3u_path ,s->s_name ,256);
		m3u_path [256] = 0;
		char *p = strrchr(m3u_path ,'.');
		if (!p) p = m3u_path + strlen(m3u_path);
		strcpy(p ,".m3u");
		gme_load_m3u(x->emu ,m3u_path);

		gme_ignore_silence ( x->emu ,1        );
		gme_mute_voices    ( x->emu ,x->mask  );
		gme_set_tempo      ( x->emu ,x->tempo );
		x->voices = gme_voice_count(x->emu);
		err_msg = gmepd_load(x ,0);
		x->path = s;  }
	if (err_msg)
		post("Error: %s" ,err_msg);
	x->open = !err_msg;
	t_atom open = { .a_type=A_FLOAT ,.a_w={.w_float = x->open} };
	outlet_anything(x->o_meta ,s_open ,1 ,&open);
}

static inline t_float gmepd_length(t_gme *x) {
	t_float f = x->info->length;
	if (f < 0) // try intro + 2 loops
	{	int intro = x->info->intro_length ,loop = x->info->loop_length;
		if (intro < 0 && loop < 0)
			return f;
		f = (intro >= 0 ? intro : 0) + (loop >= 0 ? loop * 2 : 0);  }
	return f;
}

static inline t_atom gmepd_time(t_gme *x) {
	return (t_atom){ .a_type=A_FLOAT ,.a_w={.w_float = gmepd_length(x)} };
}

static inline t_atom gmepd_ftime(t_gme *x) {
	char time[33] ,*t = time;
	int ms  = gmepd_length(x);
	if (ms < 0) ms = 0;
	if (x->info->fade_length > 0)
		ms += x->info->fade_length;

	int min =  ms / 60000;
	int sec = (ms - 60000 * min) / 1000;
	if (min >= 60)
	{	sprintf(t ,"%d:" ,min/60);
		t += strlen(t);  }
	sprintf(t ,"%02d:%02d" ,min%60 ,sec);
	return (t_atom){ .a_type=A_SYMBOL ,.a_w={.w_symbol = gensym(time)} };
}

static const t_symbol *dict[15];

static t_atom gmepd_meta(t_gme *x ,t_symbol *s) {
	t_atom meta;
	if      (s == dict[0])  SETSYMBOL(&meta ,x->path);
	else if (s == dict[1])  meta = gmepd_time(x);
	else if (s == dict[2])  meta = gmepd_ftime(x);
	else if (s == dict[3])  SETFLOAT (&meta ,x->info->fade_length);
	else if (s == dict[4])  SETFLOAT (&meta ,gme_track_count(x->emu));
	else if (s == dict[5])  SETFLOAT (&meta ,x->mask);
	else if (s == dict[6])  SETFLOAT (&meta ,x->voices);
	else if (s == dict[7])
	{	char buf[33] ,*b = buf;
		int m = x->mask;
		int v = x->voices;
		for (int i = 0; i < v; i++ ,b++)
			*b = ((m>>i)&1) + '0';
		*b = '\0';
		SETSYMBOL(&meta ,gensym(buf));  }

	else if (s == dict[8])  SETSYMBOL(&meta ,gensym(x->info->system));
	else if (s == dict[9])  SETSYMBOL(&meta ,gensym(x->info->game));
	else if (s == dict[10]) SETSYMBOL(&meta ,gensym(x->info->song));
	else if (s == dict[11]) SETSYMBOL(&meta ,gensym(x->info->author));
	else if (s == dict[12]) SETSYMBOL(&meta ,gensym(x->info->copyright));
	else if (s == dict[13]) SETSYMBOL(&meta ,gensym(x->info->comment));
	else if (s == dict[14]) SETSYMBOL(&meta ,gensym(x->info->dumper));
	else meta = (t_atom){ A_NULL };
	return meta;
}

static void gmepd_info_custom(t_gme *x ,int ac ,t_atom *av) {
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
			t_atom meta = gmepd_meta(x ,gensym(buf));
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

static void gmepd_info(t_gme *x ,t_symbol *s ,int ac ,t_atom *av) {
	if (!x->open) return post("No file opened.");
	if (ac) return gmepd_info_custom(x ,ac ,av);

	if (x->info->game || x->info->song)
		post("%s%s%s"
			,*x->info->game ? x->info->game : ""
			," - "
			,*x->info->song ? x->info->song : "");
}

static void gmepd_send(t_gme *x ,t_symbol *s) {
	if (!x->open) return post("No file opened.");
	t_atom meta = gmepd_meta(x ,s);
	if (meta.a_type)
		outlet_anything(x->o_meta ,s ,1 ,&meta);
	else post("no metadata for '%s'" ,s->s_name);
}

static void gmepd_anything(t_gme *x ,t_symbol *s ,int ac ,t_atom *av) {
	gmepd_send(x ,s);
}

static void gmepd_play(t_gme *x ,t_symbol *s ,int ac ,t_atom *av) {
	if (!x->open) return post("No file opened.");
	if (ac && av->a_type == A_FLOAT)
	{	int play = !!av->a_w.w_float;
		if (x->play == play) return;
		else x->play = play;  }
	else x->play = !x->play;
	t_atom play = { .a_type=A_FLOAT ,.a_w={.w_float = x->play} };
	outlet_anything(x->o_meta ,s_play ,1 ,&play);
}

static void gmepd_bang(t_gme *x) {
	gmepd_play(x ,0 ,0 ,0);
}

static void gmepd_float(t_gme *x ,t_float f) {
	if (!x->emu) return post("No file opened.");
	int track = f;
	gme_err_t err_msg = "";
	if (track > 0 && track <= gme_track_count(x->emu))
	{	if ( (err_msg = gmepd_load(x ,track-1)) )
			post("Error: %s" ,err_msg);
		x->open = !err_msg;  }
	else gmepd_seek(x ,0);
	x->play = !err_msg;
	t_atom play = { .a_type=A_FLOAT ,.a_w={.w_float = x->play} };
	outlet_anything(x->o_meta ,s_play ,1 ,&play);
}

static void gmepd_stop(t_gme *x) {
	gmepd_float(x ,0);
}

static void *gmepd_new(t_class *gmeclass ,t_symbol *s ,int ac ,t_atom *av) {
	t_gme *x = (t_gme*)pd_new(gmeclass);
	int i = NCH;
	while (i--) outlet_new(&x->obj ,&s_signal);
	x->o_meta = outlet_new(&x->obj ,0);
	x->path = gensym("no track loaded");

	int err;
	if ((x->state = src_new(SRC_LINEAR ,NCH ,&err)) == NULL)
		post("Error : src_new() failed : %s." ,src_strerror(err)) ;
	x->data.output_frames = FRAMES;

	x->mask = x->voices = 0;
	if (ac) gmepd_solo(x ,NULL ,ac ,av);

	x->tempo = 1.;
	x->open = x->play = 0;
	return (x);
}

static void gmepd_free(t_gme *x) {
	gme_free_info(x->info);
	gme_delete(x->emu);
	src_delete(x->state);
}

static t_class *gmepd_setup(t_symbol *s ,t_newmethod newm) {
	dict[0] = gensym("path");
	dict[1] = gensym("time");
	dict[2] = gensym("ftime");
	dict[3] = gensym("fade");
	dict[4] = gensym("tracks");
	dict[5] = gensym("mask");
	dict[6] = gensym("voices");
	dict[7] = gensym("bmask");
	dict[8] = gensym("system");
	dict[9] = gensym("game");
	dict[10] = gensym("song");
	dict[11] = gensym("author");
	dict[12] = gensym("copyright");
	dict[13] = gensym("comment");
	dict[14] = gensym("dumper");

	s_open = gensym("open");
	s_play = gensym("play");
	s_mask = gensym("mask");

	t_class *gmeclass = class_new(s ,newm ,(t_method)gmepd_free
		,sizeof(t_gme) ,0 ,A_GIMME ,0);
	class_addbang     (gmeclass ,gmepd_bang);
	class_addfloat    (gmeclass ,gmepd_float);
	class_addanything (gmeclass ,gmepd_anything);

	class_addmethod(gmeclass ,(t_method)gmepd_seek   ,gensym("seek")   ,A_FLOAT  ,0);
	class_addmethod(gmeclass ,(t_method)gmepd_speed  ,gensym("speed")  ,A_FLOAT  ,0);
	class_addmethod(gmeclass ,(t_method)gmepd_tempo  ,gensym("tempo")  ,A_FLOAT  ,0);
	class_addmethod(gmeclass ,(t_method)gmepd_interp ,gensym("interp") ,A_FLOAT  ,0);
	class_addmethod(gmeclass ,(t_method)gmepd_mute   ,gensym("mute")   ,A_GIMME  ,0);
	class_addmethod(gmeclass ,(t_method)gmepd_solo   ,gensym("solo")   ,A_GIMME  ,0);
	class_addmethod(gmeclass ,(t_method)gmepd_mask   ,gensym("mask")   ,A_GIMME  ,0);
	class_addmethod(gmeclass ,(t_method)gmepd_info   ,gensym("info")   ,A_GIMME  ,0);
	class_addmethod(gmeclass ,(t_method)gmepd_info   ,gensym("print")  ,A_GIMME  ,0);
	class_addmethod(gmeclass ,(t_method)gmepd_play   ,gensym("play")   ,A_GIMME  ,0);
	class_addmethod(gmeclass ,(t_method)gmepd_send   ,gensym("send")   ,A_SYMBOL ,0);
	class_addmethod(gmeclass ,(t_method)gmepd_open   ,gensym("open")   ,A_SYMBOL ,0);
	class_addmethod(gmeclass ,(t_method)gmepd_stop   ,gensym("stop")   ,A_NULL);

	return gmeclass;
}
