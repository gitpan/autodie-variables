#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#ifndef CopHINTHASH_get
#define CopHINTHASH_get(c) ((c)->cop_hints_hash)
#endif

#ifndef cophh_fetch_pvs
#define cophh_fetch_pvs(cophh, key, flags) Perl_refcounted_he_fetch(aTHX_ cophh, NULL, STR_WITH_LEN(key), 0, flags)
#endif


int autodie_variables(pTHX) {
	SV* val = cophh_fetch_pvs(CopHINTHASH_get(PL_curcop), "autodie_variables", 0);
	if (val != &PL_sv_placeholder)
		return SvIV(val);
	return 0;
}

int new_magic_set(pTHX_ SV *sv, MAGIC *mg) {
	dVAR;
	register const char *s;
	I32 i;
	STRLEN len;
	MAGIC *tmg;
	int ret = 0;

	PERL_ARGS_ASSERT_MAGIC_SET;

	if (!autodie_variables(aTHX))
		return Perl_magic_set(aTHX_ sv, mg);

	switch (*mg->mg_ptr) {
	case '<':
		PL_uid = SvIV(sv);
		if (PL_delaymagic) {
			PL_delaymagic |= DM_RUID;
			break;								/* don't do magic till later */
		}
#ifdef HAS_SETRESUID
		ret = setresuid((Uid_t)PL_uid, (Uid_t)-1, (Uid_t)-1);
#else
#ifdef HAS_SETRUID
		ret = setruid((Uid_t)PL_uid);
#else
#ifdef HAS_SETREUID
		ret = setreuid((Uid_t)PL_uid, (Uid_t)-1);
#else
		if (PL_uid == PL_euid) {				/* special case $< = $> */
#ifdef PERL_DARWIN
			/* workaround for Darwin's setuid peculiarity, cf [perl #24122] */
			if (PL_uid != 0 && PerlProc_getuid() == 0)
				(void)PerlProc_setuid(0);
#endif
			ret = PerlProc_setuid(PL_uid);
		} else {
			PL_uid = PerlProc_getuid();
			Perl_croak(aTHX_ "setruid() not implemented");
		}
#endif
#endif
#endif
		PL_uid = PerlProc_getuid();
		if (ret < 0)
			Perl_croak(aTHX_ "setruid(%d) failed: %s", SvIV(sv), Strerror(errno));
		break;
	case '>':
		PL_euid = SvIV(sv);
		if (PL_delaymagic) {
			PL_delaymagic |= DM_EUID;
			break;								/* don't do magic till later */
		}
#ifdef HAS_SETRESUID
		ret = setresuid((Uid_t)-1, (Uid_t)PL_euid, (Uid_t)-1);
#else
#ifdef HAS_SETEUID
		ret = seteuid((Uid_t)PL_euid);
#else
#ifdef HAS_SETREUID
		(void)setreuid((Uid_t)-1, (Uid_t)PL_euid);
#else
		if (PL_euid == PL_uid)				/* special case $> = $< */
			ret = PerlProc_setuid(PL_euid);
		else {
			PL_euid = PerlProc_geteuid();
			Perl_croak(aTHX_ "seteuid() not implemented");
		}
#endif
#endif
#endif
		PL_euid = PerlProc_geteuid();
		if (ret < 0)
			Perl_croak(aTHX_ "seteuid(%d) failed: %s", SvIV(sv), Strerror(errno));
		break;
	case '(':
		PL_gid = SvIV(sv);
		if (PL_delaymagic) {
			PL_delaymagic |= DM_RGID;
			break;								/* don't do magic till later */
		}
#ifdef HAS_SETRESGID
		ret = setresgid((Gid_t)PL_gid, (Gid_t)-1, (Gid_t) -1);
#else
#ifdef HAS_SETRGID
		ret = setrgid((Gid_t)PL_gid);
#else
#ifdef HAS_SETREGID
		ret = setregid((Gid_t)PL_gid, (Gid_t)-1);
#else
		if (PL_gid == PL_egid)						/* special case $( = $) */
			ret = PerlProc_setgid(PL_gid);
		else {
			PL_gid = PerlProc_getgid();
			Perl_croak(aTHX_ "setrgid() not implemented");
		}
#endif
#endif
#endif
		PL_gid = PerlProc_getgid();
		if (ret < 0)
			Perl_croak(aTHX_ "setrgid(%d) failed: %s", SvIV(sv), Strerror(errno));
		break;
	case ')':
#ifdef HAS_SETGROUPS
		{
			const char *p = SvPV_const(sv, len);
			const char *additional = NULL;
			Groups_t *gary = NULL;
#ifdef _SC_NGROUPS_MAX
			int maxgrp = sysconf(_SC_NGROUPS_MAX);

			if (maxgrp < 0)
				maxgrp = NGROUPS;
#else
			int maxgrp = NGROUPS;
#endif

			while (isSPACE(*p))
				++p;
			PL_egid = Atol(p);
			for (i = 0; i < maxgrp; ++i) {
				while (*p && !isSPACE(*p))
					++p;
				while (isSPACE(*p))
					++p;
				if (!additional)
					additional = p;
				if (!*p)
					break;
				if(!gary)
					Newx(gary, i + 1, Groups_t);
				else
					Renew(gary, i + 1, Groups_t);
				gary[i] = Atol(p);
			}
			if (i) {
				if (setgroups(i, gary) < 0) {
					PL_egid = PerlProc_getegid();
					Perl_croak(aTHX_ "setgroups(%s) failed: %s", additional, Strerror(errno));
				}
			}
			
			Safefree(gary);
		}
#else  /* HAS_SETGROUPS */
		PL_egid = SvIV(sv);
#endif /* HAS_SETGROUPS */
		if (PL_delaymagic) {
			PL_delaymagic |= DM_EGID;
			break;								/* don't do magic till later */
		}
#ifdef HAS_SETRESGID
		ret = setresgid((Gid_t)-1, (Gid_t)PL_egid, (Gid_t)-1);
#else
#ifdef HAS_SETEGID
		ret = setegid((Gid_t)PL_egid);
#else
#ifdef HAS_SETREGID
		ret = setregid((Gid_t)-1, (Gid_t)PL_egid);
#else
		if (PL_egid == PL_gid)						/* special case $) = $( */
			ret = PerlProc_setgid(PL_egid);
		else {
			PL_egid = PerlProc_getegid();
			Perl_croak(aTHX_ "setegid() not implemented");
		}
#endif
#endif
#endif
		PL_egid = PerlProc_getegid();
		if (ret < 0)
			Perl_croak(aTHX_ "setegid(%d) failed: %s", SvIV(sv), Strerror(errno));
		break;
		default:
			return Perl_magic_set(aTHX_ sv, mg);
	}
}

const MGVTBL new_vtable = { Perl_magic_get, new_magic_set, Perl_magic_len };

MODULE = autodie::variables                PACKAGE = autodie::variables

void
_reset_global(var)
	SV* var;
    CODE:
		MAGIC* magic = mg_find(var, PERL_MAGIC_sv);
		magic->mg_virtual = (MGVTBL*)&new_vtable;
