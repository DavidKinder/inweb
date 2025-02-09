[Configuration::] Configuration.

To parse the command line arguments with which inweb was called,
and to handle any errors it needs to issue.

@h Instructions.
The following structure exists just to hold what the user specified on the
command line: there will only ever be one of these.

=
typedef struct inweb_instructions {
	int inweb_mode; /* our main mode of operation: one of the |*_MODE| constants */
	struct pathname *chosen_web; /* project folder relative to cwd */
	struct filename *chosen_file; /* or, single file relative to cwd */
	struct text_stream *chosen_range; /* which subset of this web we apply to (often, all of it) */
	int chosen_range_actually_chosen; /* rather than being a default choice */

	int swarm_mode; /* relevant to weaving only: one of the |*_SWARM| constants */
	struct text_stream *tag_setting; /* |-weave-tag X|: weave, but only the material tagged X */
	struct text_stream *weave_pattern; /* |-weave-as X|: for example, |-weave-to HTML| */

	int show_languages_switch; /* |-show-languages|: print list of available PLs */
	int catalogue_switch; /* |-catalogue|: print catalogue of sections */
	int functions_switch; /* |-functions|: print catalogue of functions within sections */
	int structures_switch; /* |-structures|: print catalogue of structures within sections */
	int advance_switch; /* |-advance-build|: advance build file for web */
	int scan_switch; /* |-scan|: simply show the syntactic scan of the source */
	int ctags_switch; /* |-ctags|: generate a set of Universal Ctags on each tangle */
	struct filename *weave_to_setting; /* |-weave-to X|: the pathname X, if supplied */
	struct pathname *weave_into_setting; /* |-weave-into X|: the pathname X, if supplied */
	int sequential; /* give the sections sequential sigils */
	struct filename *tangle_setting; /* |-tangle-to X|: the pathname X, if supplied */
	struct filename *ctags_setting; /* |-ctags-to X|: the pathname X, if supplied */
	struct filename *makefile_setting; /* |-makefile X|: the filename X, if supplied */
	struct filename *gitignore_setting; /* |-gitignore X|: the filename X, if supplied */
	struct filename *advance_setting; /* |-advance-build-file X|: advance build file X */
	struct filename *writeme_setting; /* |-write-me X|: advance build file X */
	struct filename *prototype_setting; /* |-prototype X|: the pathname X, if supplied */
	struct filename *navigation_setting; /* |-navigation X|: the filename X, if supplied */
	struct filename *colony_setting; /* |-colony X|: the filename X, if supplied */
	struct text_stream *member_setting; /* |-member X|: sets web to member X of colony */
	struct linked_list *breadcrumb_setting; /* of |breadcrumb_request| */
	struct text_stream *platform_setting; /* |-platform X|: sets prevailing platform to X */
	int verbose_switch; /* |-verbose|: print names of files read to stdout */
	int targets; /* used only for parsing */

	struct programming_language *test_language_setting; /* |-test-language X| */
	struct filename *test_language_on_setting; /* |-test-language-on X| */

	struct pathname *import_setting; /* |-import X|: where to find imported webs */
} inweb_instructions;

@h Reading the command line.
The dull work of this is done by the Foundation module: all we need to do is
to enumerate constants for the Inweb-specific command line switches, and
then declare them.

=
inweb_instructions Configuration::read(int argc, char **argv) {
	inweb_instructions args;
	@<Initialise the args@>;
	@<Declare the command-line switches specific to Inweb@>;
	CommandLine::read(argc, argv, &args, &Configuration::switch, &Configuration::bareword);
	Configuration::member_and_colony(&args);
	if (Str::len(args.weave_pattern) == 0) WRITE_TO(args.weave_pattern, "HTML");
	if ((args.chosen_web == NULL) && (args.chosen_file == NULL)) {
		if ((args.makefile_setting) || (args.gitignore_setting))
			args.inweb_mode = TRANSLATE_MODE;
		if (args.inweb_mode != TRANSLATE_MODE)
			args.inweb_mode = NO_MODE;
	}
	if (Str::len(args.chosen_range) == 0) {
		Str::copy(args.chosen_range, I"0");
	}
	return args;
}

@<Initialise the args@> =
	args.inweb_mode = NO_MODE;
	args.swarm_mode = SWARM_OFF_SWM;
	args.show_languages_switch = FALSE;
	args.catalogue_switch = FALSE;
	args.functions_switch = FALSE;
	args.structures_switch = FALSE;
	args.advance_switch = FALSE;
	args.scan_switch = FALSE;
	args.verbose_switch = FALSE;
	args.ctags_switch = TRUE;
	args.chosen_web = NULL;
	args.chosen_file = NULL;
	args.chosen_range = Str::new();
	args.chosen_range_actually_chosen = FALSE;
	args.tangle_setting = NULL;
	args.ctags_setting = NULL;
	args.weave_to_setting = NULL;
	args.weave_into_setting = NULL;
	args.makefile_setting = NULL;
	args.gitignore_setting = NULL;
	args.advance_setting = NULL;
	args.writeme_setting = NULL;
	args.prototype_setting = NULL;
	args.navigation_setting = NULL;
	args.colony_setting = NULL;
	args.member_setting = NULL;
	args.breadcrumb_setting = NEW_LINKED_LIST(breadcrumb_request);
	args.platform_setting = NULL;
	args.tag_setting = Str::new();
	args.weave_pattern = Str::new();
	args.import_setting = NULL;
	args.targets = 0;
	args.test_language_setting = NULL;
	args.test_language_on_setting = NULL;

@ The CommandLine section of Foundation needs to be told what command-line
switches we want, other than the standard set (such as |-help|) which it
provides automatically.

@e VERBOSE_CLSW
@e IMPORT_FROM_CLSW

@e LANGUAGES_CLSG

@e LANGUAGE_CLSW
@e LANGUAGES_CLSW
@e SHOW_LANGUAGES_CLSW
@e TEST_LANGUAGE_CLSW
@e TEST_LANGUAGE_ON_CLSW

@e ANALYSIS_CLSG

@e CATALOGUE_CLSW
@e FUNCTIONS_CLSW
@e STRUCTURES_CLSW
@e ADVANCE_CLSW
@e GITIGNORE_CLSW
@e MAKEFILE_CLSW
@e WRITEME_CLSW
@e PLATFORM_CLSW
@e ADVANCE_FILE_CLSW
@e PROTOTYPE_CLSW
@e SCAN_CLSW

@e WEAVING_CLSG

@e WEAVE_CLSW
@e WEAVE_INTO_CLSW
@e WEAVE_TO_CLSW
@e OPEN_CLSW
@e WEAVE_AS_CLSW
@e WEAVE_TAG_CLSW
@e BREADCRUMB_CLSW
@e NAVIGATION_CLSW

@e TANGLING_CLSG

@e TANGLE_CLSW
@e TANGLE_TO_CLSW
@e CTAGS_TO_CLSW
@e CTAGS_CLSW

@e COLONIAL_CLSG

@e COLONY_CLSW
@e MEMBER_CLSW

@<Declare the command-line switches specific to Inweb@> =
	CommandLine::declare_heading(U"inweb: a tool for literate programming\n\n"
		U"Usage: inweb WEB OPTIONS RANGE\n\n"
		U"WEB must be a directory holding a literate program (a 'web')\n\n"
		U"The legal RANGEs are:\n"
		U"   all: complete web (the default if no TARGETS set)\n"
		U"   P: all preliminaries\n"
		U"   1: Chapter 1 (and so on)\n"
		U"   A: Appendix A (and so on, up to Appendix O)\n"
		U"   3/eg: section with abbreviated name \"3/eg\" (and so on)\n"
		U"You can also, or instead, specify:\n"
		U"   index: to weave an HTML page indexing the project\n"
		U"   chapters: to weave all chapters as individual documents\n"
		U"   sections: ditto with sections\n");

	CommandLine::begin_group(LANGUAGES_CLSG,
		I"for locating programming language definitions");
	CommandLine::declare_switch(LANGUAGE_CLSW, U"read-language", 2,
		U"read language definition from file X");
	CommandLine::declare_switch(LANGUAGES_CLSW, U"read-languages", 2,
		U"read all language definitions in path X");
	CommandLine::declare_switch(SHOW_LANGUAGES_CLSW, U"show-languages", 1,
		U"list programming languages supported by Inweb");
	CommandLine::declare_switch(TEST_LANGUAGE_CLSW, U"test-language", 2,
		U"test language X on...");
	CommandLine::declare_switch(TEST_LANGUAGE_ON_CLSW, U"test-language-on", 2,
		U"...the code in the file X");
	CommandLine::end_group();

	CommandLine::begin_group(ANALYSIS_CLSG,
		I"for analysing a web");
	CommandLine::declare_switch(CATALOGUE_CLSW, U"catalogue", 1,
		U"list the sections in the web");
	CommandLine::declare_switch(CATALOGUE_CLSW, U"catalog", 1,
		U"same as '-catalogue'");
	CommandLine::declare_switch(MAKEFILE_CLSW, U"makefile", 2,
		U"write a makefile for this web and store it in X");
	CommandLine::declare_switch(GITIGNORE_CLSW, U"gitignore", 2,
		U"write a .gitignore file for this web and store it in X");
	CommandLine::declare_switch(ADVANCE_FILE_CLSW, U"advance-build-file", 2,
		U"increment daily build code in file X");
	CommandLine::declare_switch(WRITEME_CLSW, U"write-me", 2,
		U"write a read-me file following instructions in file X");
	CommandLine::declare_switch(PLATFORM_CLSW, U"platform", 2,
		U"use platform X (e.g. 'windows') when making e.g. makefiles");
	CommandLine::declare_switch(PROTOTYPE_CLSW, U"prototype", 2,
		U"translate makefile from prototype X");
	CommandLine::declare_switch(FUNCTIONS_CLSW, U"functions", 1,
		U"catalogue the functions in the web");
	CommandLine::declare_switch(STRUCTURES_CLSW, U"structures", 1,
		U"catalogue the structures in the web");
	CommandLine::declare_switch(ADVANCE_CLSW, U"advance-build", 1,
		U"increment daily build code for the web");
	CommandLine::declare_switch(SCAN_CLSW, U"scan", 1,
		U"scan the web");
	CommandLine::end_group();

	CommandLine::begin_group(WEAVING_CLSG,
		I"for weaving a web");
	CommandLine::declare_switch(WEAVE_CLSW, U"weave", 1,
		U"weave the web into human-readable form");
	CommandLine::declare_switch(WEAVE_INTO_CLSW, U"weave-into", 2,
		U"weave, but into directory X");
	CommandLine::declare_switch(WEAVE_TO_CLSW, U"weave-to", 2,
		U"weave, but to filename X (for single files only)");
	CommandLine::declare_switch(OPEN_CLSW, U"open", 1,
		U"weave then open woven file");
	CommandLine::declare_switch(WEAVE_AS_CLSW, U"weave-as", 2,
		U"set weave pattern to X (default is 'HTML')");
	CommandLine::declare_switch(WEAVE_TAG_CLSW, U"weave-tag", 2,
		U"weave, but only using material tagged as X");
	CommandLine::declare_switch(BREADCRUMB_CLSW, U"breadcrumb", 2,
		U"use the text X as a breadcrumb in overhead navigation");
	CommandLine::declare_switch(NAVIGATION_CLSW, U"navigation", 2,
		U"use the file X as a column of navigation links");
	CommandLine::end_group();

	CommandLine::begin_group(TANGLING_CLSG,
		I"for tangling a web");
	CommandLine::declare_switch(TANGLE_CLSW, U"tangle", 1,
		U"tangle the web into machine-compilable form");
	CommandLine::declare_switch(TANGLE_TO_CLSW, U"tangle-to", 2,
		U"tangle, but to filename X");
	CommandLine::declare_switch(CTAGS_TO_CLSW, U"ctags-to", 2,
		U"tangle, but write Universal Ctags file to X not to 'tags'");
	CommandLine::declare_boolean_switch(CTAGS_CLSW, U"ctags", 1,
		U"write a Universal Ctags file when tangling", TRUE);
	CommandLine::end_group();

	CommandLine::begin_group(COLONIAL_CLSG,
		I"for dealing with colonies of webs together");
	CommandLine::declare_switch(COLONY_CLSW, U"colony", 2,
		U"use the file X as a list of webs in this colony");
	CommandLine::declare_switch(MEMBER_CLSW, U"member", 2,
		U"use member X from the colony as our web");
	CommandLine::end_group();

	CommandLine::declare_boolean_switch(VERBOSE_CLSW, U"verbose", 1,
		U"explain what inweb is doing", FALSE);
	CommandLine::declare_switch(IMPORT_FROM_CLSW, U"import-from", 2,
		U"specify that imported modules are at pathname X");

@ Foundation calls this on any |-switch| argument read:

=
void Configuration::switch(int id, int val, text_stream *arg, void *state) {
	inweb_instructions *args = (inweb_instructions *) state;
	switch (id) {
		/* Miscellaneous */
		case VERBOSE_CLSW: args->verbose_switch = TRUE; break;
		case IMPORT_FROM_CLSW: args->import_setting = Pathnames::from_text(arg); break;

		/* Analysis */
		case LANGUAGE_CLSW:
			Languages::read_definition(Filenames::from_text(arg)); break;
		case LANGUAGES_CLSW:
			Languages::read_definitions(Pathnames::from_text(arg)); break;
		case SHOW_LANGUAGES_CLSW:
			args->show_languages_switch = TRUE;
			Configuration::set_fundamental_mode(args, ANALYSE_MODE); break;
		case TEST_LANGUAGE_CLSW:
			args->test_language_setting =
				Languages::read_definition(Filenames::from_text(arg));
			Configuration::set_fundamental_mode(args, ANALYSE_MODE); break;
		case TEST_LANGUAGE_ON_CLSW:
			args->test_language_on_setting = Filenames::from_text(arg);
			Configuration::set_fundamental_mode(args, ANALYSE_MODE); break;
		case CATALOGUE_CLSW:
			args->catalogue_switch = TRUE;
			Configuration::set_fundamental_mode(args, ANALYSE_MODE); break;
		case FUNCTIONS_CLSW:
			args->functions_switch = TRUE;
			Configuration::set_fundamental_mode(args, ANALYSE_MODE); break;
		case STRUCTURES_CLSW:
			args->structures_switch = TRUE;
			Configuration::set_fundamental_mode(args, ANALYSE_MODE); break;
		case ADVANCE_CLSW:
			args->advance_switch = TRUE;
			Configuration::set_fundamental_mode(args, ANALYSE_MODE); break;
		case MAKEFILE_CLSW:
			args->makefile_setting = Filenames::from_text(arg);
			if (args->inweb_mode != TRANSLATE_MODE)
				Configuration::set_fundamental_mode(args, ANALYSE_MODE);
			break;
		case GITIGNORE_CLSW:
			args->gitignore_setting = Filenames::from_text(arg);
			if (args->inweb_mode != TRANSLATE_MODE)
				Configuration::set_fundamental_mode(args, ANALYSE_MODE);
			break;
		case PLATFORM_CLSW:
			args->platform_setting = Str::duplicate(arg);
			break;
		case ADVANCE_FILE_CLSW:
			args->advance_setting = Filenames::from_text(arg);
			Configuration::set_fundamental_mode(args, TRANSLATE_MODE);
			break;
		case WRITEME_CLSW:
			args->writeme_setting = Filenames::from_text(arg);
			Configuration::set_fundamental_mode(args, TRANSLATE_MODE);
			break;
		case PROTOTYPE_CLSW:
			args->prototype_setting = Filenames::from_text(arg);
			Configuration::set_fundamental_mode(args, TRANSLATE_MODE); break;
		case SCAN_CLSW:
			args->scan_switch = TRUE;
			Configuration::set_fundamental_mode(args, ANALYSE_MODE); break;

		/* Weave-related */
		case WEAVE_CLSW:
			Configuration::set_fundamental_mode(args, WEAVE_MODE); break;
		case WEAVE_INTO_CLSW:
			args->weave_into_setting = Pathnames::from_text(arg);
			Configuration::set_fundamental_mode(args, WEAVE_MODE); break;
		case WEAVE_TO_CLSW:
			args->weave_to_setting = Filenames::from_text(arg);
			Configuration::set_fundamental_mode(args, WEAVE_MODE); break;
		case WEAVE_AS_CLSW:
			args->weave_pattern = Str::duplicate(arg);
			Configuration::set_fundamental_mode(args, WEAVE_MODE); break;
		case WEAVE_TAG_CLSW:
			args->tag_setting = Str::duplicate(arg);
			Configuration::set_fundamental_mode(args, WEAVE_MODE); break;
		case BREADCRUMB_CLSW:
			ADD_TO_LINKED_LIST(Colonies::request_breadcrumb(arg),
				breadcrumb_request, args->breadcrumb_setting);
			Configuration::set_fundamental_mode(args, WEAVE_MODE); break;
		case NAVIGATION_CLSW:
			args->navigation_setting = Filenames::from_text(arg);
			Configuration::set_fundamental_mode(args, WEAVE_MODE); break;

		/* Colonial */
		case COLONY_CLSW:
			args->colony_setting = Filenames::from_text(arg); break;
		case MEMBER_CLSW:
			args->member_setting = Str::duplicate(arg); break;

		/* Tangle-related */
		case TANGLE_CLSW:
			Configuration::set_fundamental_mode(args, TANGLE_MODE); break;
		case TANGLE_TO_CLSW:
			args->tangle_setting = Filenames::from_text(arg);
			Configuration::set_fundamental_mode(args, TANGLE_MODE); break;
		case CTAGS_TO_CLSW:
			args->ctags_setting = Filenames::from_text(arg);
			break;
		case CTAGS_CLSW:
			args->ctags_switch = val;
			break;

		default: internal_error("unimplemented switch");
	}
}

@ The colony file is, in one sense, a collection of presets for the web
location and its navigational aids.

=
void Configuration::member_and_colony(inweb_instructions *args) {
	if (args->colony_setting) Colonies::load(args->colony_setting);
	if (Str::len(args->member_setting) > 0) {
		if ((args->chosen_web == NULL) && (args->chosen_file == NULL)) {
			colony_member *CM = Colonies::find(args->member_setting);
			if (CM == NULL) Errors::fatal("the colony has no member of that name");
			Configuration::bareword(0, CM->path, args);
			if (Str::len(args->weave_pattern) == 0)
				args->weave_pattern = CM->default_weave_pattern;
			if (LinkedLists::len(args->breadcrumb_setting) == 0)
				args->breadcrumb_setting = CM->breadcrumb_tail;
			if (args->navigation_setting == NULL)
				args->navigation_setting = CM->navigation;
			if (args->weave_into_setting == NULL)
				args->weave_into_setting = CM->weave_path;
		} else {
			Errors::fatal("cannot specify a web and also use -member");
		}
	}
}

@ Foundation calls this routine on any command-line argument which is
neither a switch (like |-weave|), nor an argument for a switch (like
the |X| in |-weave-as X|).

=
void Configuration::bareword(int id, text_stream *opt, void *state) {
	inweb_instructions *args = (inweb_instructions *) state;
	if ((args->chosen_web == NULL) && (args->chosen_file == NULL)) {
		if (Str::suffix_eq(opt, I".inweb", 6))
			args->chosen_file = Filenames::from_text(opt);
		else if (Str::suffix_eq(opt, I".md", 3))
			args->chosen_file = Filenames::from_text(opt);
		else
			args->chosen_web = Pathnames::from_text(opt);
	} else Configuration::set_range(args, opt);
}

@ Here we read a range. The special ranges |index|, |chapters| and |sections|
are converted into swarm settings instead. |all| is simply an alias for |0|.
Otherwise, a range is a chapter number/letter, or a section range.

=
void Configuration::set_range(inweb_instructions *args, text_stream *opt) {
	match_results mr = Regexp::create_mr();
	if (Str::eq_wide_string(opt, U"index")) {
		args->swarm_mode = SWARM_INDEX_SWM;
	} else if (Str::eq_wide_string(opt, U"chapters")) {
		args->swarm_mode = SWARM_CHAPTERS_SWM;
	} else if (Str::eq_wide_string(opt, U"sections")) {
		args->swarm_mode = SWARM_SECTIONS_SWM;
	} else {
		if (++args->targets > 1) Errors::fatal("at most one target may be given");
		if (Str::eq_wide_string(opt, U"all")) {
			Str::copy(args->chosen_range, I"0");
		} else if (((Characters::isalnum(Str::get_first_char(opt))) && (Str::len(opt) == 1))
			|| (Regexp::match(&mr, opt, U"%i+/%i+"))) {
			Str::copy(args->chosen_range, opt);
			string_position P = Str::start(args->chosen_range);
			Str::put(P, Characters::toupper(Str::get(P)));
		} else {
			TEMPORARY_TEXT(ERM)
			WRITE_TO(ERM, "target not recognised (see -help for more): %S", opt);
			Main::error_in_web(ERM, NULL);
			DISCARD_TEXT(ERM)
			exit(1);
		}
	}
	args->chosen_range_actually_chosen = TRUE;
	Regexp::dispose_of(&mr);
}

@ We can only be in a single mode at a time:

=
void Configuration::set_fundamental_mode(inweb_instructions *args, int new_material) {
	if ((args->inweb_mode != NO_MODE) && (args->inweb_mode != new_material))
		Errors::fatal("can only do one at a time - weaving, tangling or analysing");
	args->inweb_mode = new_material;
}
