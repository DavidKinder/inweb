[Parser::] The Parser.

To work through the program read in, assigning each line its category,
and noting down other useful information as we go.

@h Sequence of parsing.
At this point, the web has been read into memory. It's a linked list of
chapters, each of which is a linked list of sections, each of which must
be parsed in turn.

When we're done, we offer the support code for the web's programming language
a chance to do some further work, if it wants to. (This is how, for example,
function definitions are recognised in C programs.) There is no requirement
for it to do anything.

=
void Parser::parse_web(web *W, int inweb_mode) {
	chapter *C;
	section *S;
	LOOP_OVER_LINKED_LIST(C, chapter, W->chapters)
		LOOP_OVER_LINKED_LIST(S, section, C->sections)
			@<Parse a section@>;
	LanguageMethods::parse_types(W, W->main_language);
	LanguageMethods::parse_functions(W, W->main_language);
	LanguageMethods::further_parsing(W, W->main_language);
}

@ The task now is to parse those source lines, categorise them, and group them
further into a linked list of paragraphs. The basic method would be simple
enough, but is made more elaborate by supporting both version 1 and version 2
markup syntax, and trying to detect incorrect uses of one within the other.

@<Parse a section@> =
	int comment_mode = TRUE, extract_mode = FALSE;
	int code_lcat_for_body = NO_LCAT,
		code_plainness_for_body = FALSE,
		hyperlink_body = FALSE;
	programming_language *code_pl_for_body = NULL;
	text_stream *code_destination = NULL;
	int before_bar = TRUE;
	int next_par_number = 1;
	paragraph *current_paragraph = NULL;
	TEMPORARY_TEXT(tag_list)
	for (source_line *L = S->first_line, *PL = NULL; L; PL = L, L = L->next_line) {
		@<Apply tag list, if any@>;
		@<Remove tag list, if any@>;
		@<Detect implied paragraph breaks@>;
		@<Determine category for this source line@>;
	}
	DISCARD_TEXT(tag_list)
	@<In version 2 syntax, construe the comment under the heading as the purpose@>;
	@<If the section as a whole is tagged, apply that tag to each paragraph in it@>;
	@<Work out footnote numbering for this section@>;

@ In version 2 syntax, the notation for tags was clarified. The tag list
for a paragraph is the run of |^"This"| and |^"That"| markers at the end of
the line introducing that paragraph. They can only occur, therefore, on a
line beginning with an |@|. We extract them into a string called |tag_list|.
(The reason we can't act on them straight away, which would make for simpler
code, is that they need to be applied to a paragraph structure which doesn't
yet exist -- it will only exist when the line has been fully parsed.)

@<Remove tag list, if any@> =
	if (Str::get_first_char(L->text) == '@') {
		match_results mr = Regexp::create_mr();
		while (Regexp::match(&mr, L->text, U"(%c*?)( *%^\"%c+?\")(%c*)")) {
			if (S->md->using_syntax == V1_SYNTAX)
				Parser::wrong_version(S->md->using_syntax, L, "tags written ^\"thus\"", V2_SYNTAX);
			Str::clear(L->text);
			WRITE_TO(tag_list, "%S", mr.exp[1]);
			Str::copy(L->text, mr.exp[0]); WRITE_TO(L->text, " %S", mr.exp[2]);
		}
		Regexp::dispose_of(&mr);
	}

@ And now it's later, and we can safely apply the tags. |current_paragraph|
now points to the para which was created by this line, not the one before.

@<Apply tag list, if any@> =
	match_results mr = Regexp::create_mr();
	while (Regexp::match(&mr, tag_list, U" *%^\"(%c+?)\" *(%c*)")) {
		Tags::add_by_name(current_paragraph, mr.exp[0]);
		Str::copy(tag_list, mr.exp[1]);
	}
	Regexp::dispose_of(&mr);
	Str::clear(tag_list);

@<If the section as a whole is tagged, apply that tag to each paragraph in it@> =
	paragraph *P;
	if (S->tag_with)
		LOOP_OVER_LINKED_LIST(P, paragraph, S->paragraphs)
			Tags::add_to_paragraph(P, S->tag_with, NULL);

@ In the woven form of each section, footnotes are counting upwards from 1.

@<Work out footnote numbering for this section@> =
	int next_footnote = 1;
	paragraph *P;
	LOOP_OVER_LINKED_LIST(P, paragraph, S->paragraphs)
		@<Work out footnote numbering for this paragraph@>;

@ The "purpose" of a section is a brief note about what it's for. In version 1
syntax, this had to be explicitly declared with a |@Purpose:| command; in
version 2 it's much tidier.

@<In version 2 syntax, construe the comment under the heading as the purpose@> =
	if (S->md->using_syntax == V2_SYNTAX) {
		source_line *L = S->first_line;
		if ((L) && (L->category == CHAPTER_HEADING_LCAT)) L = L->next_line;
		if (Str::len(S->sect_purpose) == 0) {
			S->sect_purpose = Parser::extract_purpose(I"", L?L->next_line: NULL, S, NULL);
			if (Str::len(S->sect_purpose) > 0) L->next_line->category = PURPOSE_LCAT;
		}
	}

@ A new paragraph is implied when a macro definition begins in the middle of
what otherwise would be code, or when a paragraph and its code divider are
immediately adjacent on the same line.

@<Detect implied paragraph breaks@> =
	match_results mr = Regexp::create_mr();
	if ((PL) && (PL->category == CODE_BODY_LCAT) &&
		(Str::get_first_char(L->text) == '@') && (Str::get_at(L->text, 1) == '<') &&
		(Regexp::match(&mr, L->text, U"%c<(%c+)@> *= *")) &&
		(S->md->using_syntax == V2_SYNTAX)) {
		@<Insert an implied paragraph break@>;
	}
	if ((PL) && (Regexp::match(&mr, L->text, U"@ *= *"))) {
		Str::clear(L->text);
		Str::copy(L->text, I"=");
		if (S->md->using_syntax == V1_SYNTAX)
			Parser::wrong_version(S->md->using_syntax, L, "implied paragraph breaks", V2_SYNTAX);
		@<Insert an implied paragraph break@>;
	}
	Regexp::dispose_of(&mr);

@ We handle implied paragraph dividers by inserting a paragraph marker and
reparsing from there.

@<Insert an implied paragraph break@> =
	source_line *NL = Lines::new_source_line_in(I"@", &(L->source), S);
	PL->next_line = NL;
	NL->next_line = L;
	L = PL;
	Regexp::dispose_of(&mr);
	continue;

@h Categorisation.
This is where the work is really done. We have a source line: is it comment,
code, definition, what?

@<Determine category for this source line@> =
	L->is_commentary = comment_mode;
	L->category = COMMENT_BODY_LCAT; /* until set otherwise down below */
	L->owning_paragraph = current_paragraph;

	if (L->source.line_count == 0) @<Parse the line as a probable chapter heading@>;
	if (L->source.line_count <= 1) @<Parse the line as a probable section heading@>;
	if (extract_mode == FALSE) {
		@<Parse the line as a possible Inweb command@>;
		@<Parse the line as a possible paragraph macro definition@>;
	}
	if (Str::get_first_char(L->text) == '=') {
		if (S->md->using_syntax == V1_SYNTAX)
			Parser::wrong_version(S->md->using_syntax, L, "column-1 '=' as code divider", V2_SYNTAX);
		if (extract_mode) @<Exit extract mode@>
		else @<Parse the line as an equals structural marker@>;
	}
	if ((Str::get_first_char(L->text) == '@') &&
		(Str::get_at(L->text, 1) != '<') &&
		(L->category != MACRO_DEFINITION_LCAT))
		@<Parse the line as a structural marker@>;
	if (comment_mode) @<This is a line destined for commentary@>;
	if (comment_mode == FALSE) @<This is a line destined for the verbatim code@>;

@ This must be one of the inserted lines marking chapter headings; it doesn't
come literally from the source web.

@<Parse the line as a probable chapter heading@> =
	if (Str::eq_wide_string(L->text, U"Chapter Heading")) {
		comment_mode = TRUE;
		extract_mode = FALSE;
		L->is_commentary = TRUE;
		L->category = CHAPTER_HEADING_LCAT;
		L->owning_paragraph = NULL;
	}

@ The top line of a section gives its title; in InC, it can also give the
namespace for its functions.

@<Parse the line as a probable section heading@> =
	match_results mr = Regexp::create_mr();
	if (Regexp::match(&mr, L->text, U"Implied Purpose: (%c+)")) {
		S->sect_purpose = Str::duplicate(mr.exp[0]);
		if (Str::len(S->sect_purpose) > 0) {
			L->category = PURPOSE_LCAT;
			L->is_commentary = TRUE;
		}
	} else if (Regexp::match(&mr, L->text, U"%[(%C+)%] (%C+/%C+): (%c+).")) {
		if (S->md->using_syntax == V2_SYNTAX)
			Parser::wrong_version(S->md->using_syntax, L,
			"section range in header line", V1_SYNTAX);
		S->sect_namespace = Str::duplicate(mr.exp[0]);
		S->md->sect_range = Str::duplicate(mr.exp[1]);
		S->md->sect_title = Str::duplicate(mr.exp[2]);
		L->text_operand = Str::duplicate(mr.exp[2]);
		L->category = SECTION_HEADING_LCAT;
		L->owning_paragraph = NULL;
	} else if (Regexp::match(&mr, L->text, U"(%C+/%C+): (%c+).")) {
		if (S->md->using_syntax == V2_SYNTAX)
			Parser::wrong_version(S->md->using_syntax, L,
			"section range in header line", V1_SYNTAX);
		S->md->sect_range = Str::duplicate(mr.exp[0]);
		S->md->sect_title = Str::duplicate(mr.exp[1]);
		L->text_operand = Str::duplicate(mr.exp[1]);
		L->category = SECTION_HEADING_LCAT;
		L->owning_paragraph = NULL;
	} else if (Regexp::match(&mr, L->text, U"%[(%C+::)%] (%c+).")) {
		S->sect_namespace = Str::duplicate(mr.exp[0]);
		S->md->sect_title = Str::duplicate(mr.exp[1]);
		L->text_operand = Str::duplicate(mr.exp[1]);
		L->category = SECTION_HEADING_LCAT;
		L->owning_paragraph = NULL;
	} else if (Regexp::match(&mr, L->text, U"(%c+).")) {
		S->md->sect_title = Str::duplicate(mr.exp[0]);
		L->text_operand = Str::duplicate(mr.exp[0]);
		L->category = SECTION_HEADING_LCAT;
		L->owning_paragraph = NULL;
	}
	Regexp::dispose_of(&mr);

@ Version 1 syntax was cluttered up with a number of hardly-used markup
syntaxes called "commands", written in double squared brackets |[[Thus]]|.
In version 2, this notation is never used.

@<Parse the line as a possible Inweb command@> =
	match_results mr = Regexp::create_mr();
	if (Regexp::match(&mr, L->text, U"%[%[(%c+)%]%]")) {
		TEMPORARY_TEXT(full_command)
		TEMPORARY_TEXT(command_text)
		Str::copy(full_command, mr.exp[0]);
		Str::copy(command_text, mr.exp[0]);
		L->category = COMMAND_LCAT;
		if (Regexp::match(&mr, command_text, U"(%c+?): *(%c+)")) {
			Str::copy(command_text, mr.exp[0]);
			L->text_operand = Str::duplicate(mr.exp[1]);
		}
		if (Str::eq_wide_string(command_text, U"Page Break")) {
			if (S->md->using_syntax != V1_SYNTAX)
				Parser::wrong_version(S->md->using_syntax, L, "[[Page Break]]", V1_SYNTAX);
			L->command_code = PAGEBREAK_CMD;
		} else if (Str::eq_wide_string(command_text, U"Grammar Index"))
			L->command_code = GRAMMAR_INDEX_CMD;
		else if (Str::eq_wide_string(command_text, U"Tag")) {
			if (S->md->using_syntax != V1_SYNTAX)
				Parser::wrong_version(S->md->using_syntax, L, "[[Tag...]]", V1_SYNTAX);
			Tags::add_by_name(L->owning_paragraph, L->text_operand);
			L->command_code = TAG_CMD;
		} else if (Str::eq_wide_string(command_text, U"Figure")) {
			if (S->md->using_syntax != V1_SYNTAX)
				Parser::wrong_version(S->md->using_syntax, L, "[[Figure...]]", V1_SYNTAX);
			Tags::add_by_name(L->owning_paragraph, I"Figures");
			L->command_code = FIGURE_CMD;
		} else {
			Main::error_in_web(I"unknown [[command]]", L);
		}
		L->is_commentary = TRUE;
		DISCARD_TEXT(command_text)
		DISCARD_TEXT(full_command)
	}
	Regexp::dispose_of(&mr);

@ Some paragraphs define angle-bracketed macros, and those need special
handling. We'll call these "paragraph macros".

@<Parse the line as a possible paragraph macro definition@> =
	match_results mr = Regexp::create_mr();
	if ((Str::get_first_char(L->text) == '@') && (Str::get_at(L->text, 1) == '<') &&
		(Regexp::match(&mr, L->text, U"%c<(%c+)@> *= *"))) {
		TEMPORARY_TEXT(para_macro_name)
		Str::copy(para_macro_name, mr.exp[0]);
		L->category = MACRO_DEFINITION_LCAT;
		if (current_paragraph == NULL)
			Main::error_in_web(I"<...> definition begins outside of a paragraph", L);
		else Macros::create(S, current_paragraph, L, para_macro_name);
		comment_mode = FALSE; extract_mode = FALSE;
		L->is_commentary = FALSE;
		code_lcat_for_body = CODE_BODY_LCAT; /* code follows on subsequent lines */
		code_pl_for_body = NULL;
		code_plainness_for_body = FALSE;
		hyperlink_body = FALSE;
		DISCARD_TEXT(para_macro_name)
		continue;
	}
	Regexp::dispose_of(&mr);

@ A structural marker is introduced by an |@| in column 1, and is a structural
division in the current section.

@<Parse the line as a structural marker@> =
	TEMPORARY_TEXT(command_text)
	Str::copy(command_text, L->text);
	Str::delete_first_character(command_text); /* i.e., strip the at-sign from the front */
	TEMPORARY_TEXT(remainder)
	match_results mr = Regexp::create_mr();
	if (Regexp::match(&mr, command_text, U"(%C*) *(%c*?)")) {
		Str::copy(command_text, mr.exp[0]);
		Str::copy(remainder, mr.exp[1]);
	}
	@<Deal with a structural marker@>;
	DISCARD_TEXT(remainder)
	DISCARD_TEXT(command_text)
	Regexp::dispose_of(&mr);
	continue;

@ An equals sign in column 1 can just mean the end of an extract, so:

@<Exit extract mode@> =
	L->category = END_EXTRACT_LCAT;
	comment_mode = TRUE;
	extract_mode = FALSE;

@ But more usually an equals sign in column 1 is a structural marker:

@<Parse the line as an equals structural marker@> =
	L->category = BEGIN_CODE_LCAT;
	L->plainer = FALSE;
	code_lcat_for_body = CODE_BODY_LCAT;
	code_destination = NULL;
	code_pl_for_body = NULL;
	comment_mode = FALSE;
	match_results mr = Regexp::create_mr();
	match_results mr2 = Regexp::create_mr();
	if (Regexp::match(&mr, L->text, U"= *(%c+) *")) {
		if ((current_paragraph) && (Str::eq(mr.exp[0], I"(very early code)"))) {
			current_paragraph->placed_very_early = TRUE;
		} else if ((current_paragraph) && (Str::eq(mr.exp[0], I"(early code)"))) {
			current_paragraph->placed_early = TRUE;
		} else if ((current_paragraph) &&
			(Regexp::match(&mr2, mr.exp[0], U"%((%c*?) *text%)"))) {
			@<Make plainer@>;
			code_lcat_for_body = TEXT_EXTRACT_LCAT;
			code_destination = NULL;
			code_pl_for_body = NULL;
			extract_mode = TRUE;
		} else if ((current_paragraph) &&
			(Regexp::match(&mr2, mr.exp[0], U"%((%c*?) *text to *(%c+)%)"))) {
			@<Make plainer@>;
			code_lcat_for_body = TEXT_EXTRACT_LCAT;
			code_destination = Str::duplicate(mr2.exp[1]);
			code_pl_for_body = Analyser::find_by_name(I"Extracts", W, TRUE);
			extract_mode = TRUE;
		} else if ((current_paragraph) &&
			(Regexp::match(&mr2, mr.exp[0], U"%((%c*?) *text as code%)"))) {
			@<Make plainer@>;
			code_lcat_for_body = TEXT_EXTRACT_LCAT;
			code_destination = NULL;
			code_pl_for_body = S->sect_language;
			extract_mode = TRUE;
		} else if ((current_paragraph) &&
			(Regexp::match(&mr2, mr.exp[0], U"%((%c*?) *text as (%c+)%)"))) {
			@<Make plainer@>;
			code_lcat_for_body = TEXT_EXTRACT_LCAT;
			code_destination = NULL;
			code_pl_for_body = Analyser::find_by_name(mr2.exp[1], W, TRUE);
			extract_mode = TRUE;
		} else if ((current_paragraph) &&
			(Regexp::match(&mr2, mr.exp[0], U"%((%c*?) *text from (%c+) as code%)"))) {
			@<Make plainer@>;
			code_pl_for_body = S->sect_language;
			@<Spool from file@>;
		} else if ((current_paragraph) &&
			(Regexp::match(&mr2, mr.exp[0], U"%((%c*?) *text from (%c+) as (%c+)%)"))) {
			@<Make plainer@>;
			code_pl_for_body = Analyser::find_by_name(mr2.exp[2], W, TRUE);
			@<Spool from file@>;
		} else if ((current_paragraph) &&
			(Regexp::match(&mr2, mr.exp[0], U"%((%c*?) *text from (%c+)%)"))) {
			@<Make plainer@>;
			code_pl_for_body = NULL;
			@<Spool from file@>;
		} else if ((current_paragraph) &&
			(Regexp::match(&mr2, mr.exp[0], U"%(figure (%c+)%)"))) {
			Tags::add_by_name(L->owning_paragraph, I"Figures");
			L->command_code = FIGURE_CMD;
			L->category = COMMAND_LCAT;
			code_lcat_for_body = COMMENT_BODY_LCAT;
			L->text_operand = Str::duplicate(mr2.exp[0]);
			comment_mode = TRUE;
		} else if ((current_paragraph) &&
			(Regexp::match(&mr2, mr.exp[0], U"%(html (%c+)%)"))) {
			Tags::add_by_name(L->owning_paragraph, I"HTML");
			L->command_code = HTML_CMD;
			L->category = COMMAND_LCAT;
			code_lcat_for_body = COMMENT_BODY_LCAT;
			L->text_operand = Str::duplicate(mr2.exp[0]);
			comment_mode = TRUE;
		} else if ((current_paragraph) &&
			(Regexp::match(&mr2, mr.exp[0], U"%(audio (%c+)%)"))) {
			Tags::add_by_name(L->owning_paragraph, I"Audio");
			L->command_code = AUDIO_CMD;
			L->category = COMMAND_LCAT;
			code_lcat_for_body = COMMENT_BODY_LCAT;
			L->text_operand = Str::duplicate(mr2.exp[0]);
			comment_mode = TRUE;
		} else if ((current_paragraph) &&
			(Regexp::match(&mr2, mr.exp[0], U"%(video (%c+)%)"))) {
			Tags::add_by_name(L->owning_paragraph, I"Video");
			L->command_code = VIDEO_CMD;
			L->category = COMMAND_LCAT;
			code_lcat_for_body = COMMENT_BODY_LCAT;
			L->text_operand = Str::duplicate(mr2.exp[0]);
			comment_mode = TRUE;
		} else if ((current_paragraph) &&
			(Regexp::match(&mr2, mr.exp[0], U"%(download (%c+) \"(%c*)\"%)"))) {
			Tags::add_by_name(L->owning_paragraph, I"Download");
			L->command_code = DOWNLOAD_CMD;
			L->category = COMMAND_LCAT;
			code_lcat_for_body = COMMENT_BODY_LCAT;
			L->text_operand = Str::duplicate(mr2.exp[0]);
			L->text_operand2 = Str::duplicate(mr2.exp[1]);
			comment_mode = TRUE;
		} else if ((current_paragraph) &&
			(Regexp::match(&mr2, mr.exp[0], U"%(download (%c+)%)"))) {
			Tags::add_by_name(L->owning_paragraph, I"Download");
			L->command_code = DOWNLOAD_CMD;
			L->category = COMMAND_LCAT;
			code_lcat_for_body = COMMENT_BODY_LCAT;
			L->text_operand = Str::duplicate(mr2.exp[0]);
			L->text_operand2 = Str::new();
			comment_mode = TRUE;
		} else if ((current_paragraph) &&
			(Regexp::match(&mr2, mr.exp[0], U"%(carousel%)"))) {
			Tags::add_by_name(L->owning_paragraph, I"Carousels");
			L->command_code = CAROUSEL_UNCAPTIONED_CMD;
			L->category = COMMAND_LCAT;
			code_lcat_for_body = COMMENT_BODY_LCAT;
			L->text_operand = Str::new();
			comment_mode = TRUE;
		} else if ((current_paragraph) &&
			(Regexp::match(&mr2, mr.exp[0], U"%(carousel \"(%c+)\" below%)"))) {
			Tags::add_by_name(L->owning_paragraph, I"Carousels");
			L->command_code = CAROUSEL_BELOW_CMD;
			L->category = COMMAND_LCAT;
			code_lcat_for_body = COMMENT_BODY_LCAT;
			L->text_operand = Str::duplicate(mr2.exp[0]);
			comment_mode = TRUE;
		} else if ((current_paragraph) &&
			(Regexp::match(&mr2, mr.exp[0], U"%(carousel \"(%c+)\" above%)"))) {
			Tags::add_by_name(L->owning_paragraph, I"Carousels");
			L->command_code = CAROUSEL_ABOVE_CMD;
			L->category = COMMAND_LCAT;
			code_lcat_for_body = COMMENT_BODY_LCAT;
			L->text_operand = Str::duplicate(mr2.exp[0]);
			comment_mode = TRUE;
		} else if ((current_paragraph) &&
			(Regexp::match(&mr2, mr.exp[0], U"%(carousel \"(%c+)\"%)"))) {
			Tags::add_by_name(L->owning_paragraph, I"Carousels");
			L->command_code = CAROUSEL_CMD;
			L->category = COMMAND_LCAT;
			code_lcat_for_body = COMMENT_BODY_LCAT;
			L->text_operand = Str::duplicate(mr2.exp[0]);
			comment_mode = TRUE;
		} else if ((current_paragraph) &&
			(Regexp::match(&mr2, mr.exp[0], U"%(carousel end%)"))) {
			Tags::add_by_name(L->owning_paragraph, I"Carousels");
			L->command_code = CAROUSEL_END_CMD;
			L->category = COMMAND_LCAT;
			code_lcat_for_body = COMMENT_BODY_LCAT;
			comment_mode = TRUE;
		} else if ((current_paragraph) &&
			((Regexp::match(&mr2, mr.exp[0], U"%(embedded (%C+) video (%c+)%)")) ||
				(Regexp::match(&mr2, mr.exp[0], U"%(embedded (%C+) audio (%c+)%)")))) {
			Tags::add_by_name(L->owning_paragraph, I"Videos");
			L->command_code = EMBED_CMD;
			L->category = COMMAND_LCAT;
			code_lcat_for_body = COMMENT_BODY_LCAT;
			L->text_operand = Str::duplicate(mr2.exp[0]);
			L->text_operand2 = Str::duplicate(mr2.exp[1]);
			comment_mode = TRUE;
		} else {
			Main::error_in_web(I"unknown bracketed annotation", L);
		}
	} else if (Regexp::match(&mr, L->text, U"= *%C%c*")) {
		Main::error_in_web(I"unknown material after '='", L);
	}
	code_plainness_for_body = L->plainer;
	hyperlink_body = L->enable_hyperlinks;
	Regexp::dispose_of(&mr);
	Regexp::dispose_of(&mr2);
	continue;

@<Make plainer@> =
	match_results mr3 = Regexp::create_mr();
	while (TRUE) {
		if (Regexp::match(&mr3, mr2.exp[0], U" *(%C+) *(%c*?)")) {
			if (Str::eq(mr3.exp[0], I"undisplayed")) L->plainer = TRUE;
			else if (Str::eq(mr3.exp[0], I"hyperlinked")) L->enable_hyperlinks = TRUE;
			else {
				Main::error_in_web(
					I"only 'undisplayed' and/or 'hyperlinked' can precede 'text' here", L);	
			}
		} else break;
		Str::clear(mr2.exp[0]);
		Str::copy(mr2.exp[0], mr3.exp[1]);
	}
	Regexp::dispose_of(&mr3);

@<Spool from file@> =
	L->category = BEGIN_CODE_LCAT;
	pathname *P = W->md->path_to_web;
	if ((S->md->owning_module) && (S->md->owning_module->module_location))
		P = S->md->owning_module->module_location; /* references are relative to module */
	filename *F = Filenames::from_text_relative(P, mr2.exp[1]);
	linked_list *lines = Painter::lines(F);
	text_stream *T;
	source_line *latest = L;
	LOOP_OVER_LINKED_LIST(T, text_stream, lines) {
		source_line *TL = Lines::new_source_line_in(T, &(L->source), S);
		TL->next_line = latest->next_line;
		TL->plainer = L->plainer;
		latest->next_line = TL;
		latest = TL;
	}
	source_line *EEL = Lines::new_source_line_in(I"=", &(L->source), S);
	EEL->next_line = latest->next_line;
	latest->next_line = EEL;
	code_lcat_for_body = TEXT_EXTRACT_LCAT;
	extract_mode = TRUE;

@ So here we have the possibilities which start with a column-1 |@| sign.
There appear to be hordes of these, but in fact most of them were removed
in Inweb syntax version 2: in modern syntax, only |@d|, |@e|, |@h|, their
long forms |@define|, |@enum| and |@heading|, and plain old |@| remain.
(But |@e| has a different meaning from in version 1.)

@<Deal with a structural marker@> =
	extract_mode = FALSE;
	if (Str::eq_wide_string(command_text, U"Purpose:")) @<Deal with Purpose@>
	else if (Str::eq_wide_string(command_text, U"Interface:")) @<Deal with Interface@>
	else if (Str::eq_wide_string(command_text, U"Definitions:")) @<Deal with Definitions@>
	else if (Regexp::match(&mr, command_text, U"----+")) @<Deal with the bar@>
	else if ((Str::eq_wide_string(command_text, U"c")) ||
			(Str::eq_wide_string(command_text, U"x")) ||
			((S->md->using_syntax == V1_SYNTAX) && (Str::eq_wide_string(command_text, U"e"))))
				@<Deal with the code and extract markers@>
	else if (Str::eq_wide_string(command_text, U"d")) @<Deal with the define marker@>
	else if (Str::eq_wide_string(command_text, U"define")) {
		if (S->md->using_syntax == V1_SYNTAX)
			Parser::wrong_version(S->md->using_syntax, L, "'@define' for definitions (use '@d' instead)", V2_SYNTAX);
		@<Deal with the define marker@>;
	} else if (Str::eq_wide_string(command_text, U"default")) {
		if (S->md->using_syntax == V1_SYNTAX)
			Parser::wrong_version(S->md->using_syntax, L, "'@default' for definitions", V2_SYNTAX);
		L->default_defn = TRUE;
		@<Deal with the define marker@>;
	} else if (Str::eq_wide_string(command_text, U"enum")) @<Deal with the enumeration marker@>
	else if ((Str::eq_wide_string(command_text, U"e")) && (S->md->using_syntax == V2_SYNTAX))
		@<Deal with the enumeration marker@>
	else {
		int weight = -1, new_page = FALSE;
		if (Str::eq_wide_string(command_text, U"")) weight = ORDINARY_WEIGHT;
		if ((Str::eq_wide_string(command_text, U"h")) || (Str::eq_wide_string(command_text, U"heading"))) {
			if (S->md->using_syntax == V1_SYNTAX)
				Parser::wrong_version(S->md->using_syntax, L, "'@h' or '@heading' for headings (use '@p' instead)", V2_SYNTAX);
			weight = SUBHEADING_WEIGHT;
		}
		if (Str::eq_wide_string(command_text, U"p")) {
			if (S->md->using_syntax != V1_SYNTAX)
				Parser::wrong_version(S->md->using_syntax, L, "'@p' for headings (use '@h' instead)", V1_SYNTAX);
			weight = SUBHEADING_WEIGHT;
		}
		if (Str::eq_wide_string(command_text, U"pp")) {
			if (S->md->using_syntax != V1_SYNTAX)
				Parser::wrong_version(S->md->using_syntax, L, "'@pp' for super-headings", V1_SYNTAX);
			weight = SUBHEADING_WEIGHT; new_page = TRUE;
		}
		if (weight >= 0) @<Begin a new paragraph of this weight@>
		else Main::error_in_web(I"don't understand @command", L);
	}

@ In version 1 syntax there were some peculiar special headings above a divider
in the file made of hyphens, called "the bar". All of that has gone in V2.

@<Deal with Purpose@> =
	if (before_bar == FALSE) Main::error_in_web(I"Purpose used after bar", L);
	if (S->md->using_syntax == V2_SYNTAX)
		Parser::wrong_version(S->md->using_syntax, L, "'@Purpose'", V1_SYNTAX);
	L->category = PURPOSE_LCAT;
	L->is_commentary = TRUE;
	L->text_operand = Str::duplicate(remainder);
	S->sect_purpose = Parser::extract_purpose(remainder, L->next_line, L->owning_section, &L);

@<Deal with Interface@> =
	if (S->md->using_syntax == V2_SYNTAX)
		Parser::wrong_version(S->md->using_syntax, L, "'@Interface'", V1_SYNTAX);
	if (before_bar == FALSE) Main::error_in_web(I"Interface used after bar", L);
	L->category = INTERFACE_LCAT;
	L->owning_paragraph = NULL;
	L->is_commentary = TRUE;
	source_line *XL = L->next_line;
	while ((XL) && (XL->next_line) && (XL->owning_section == L->owning_section)) {
		if (Str::get_first_char(XL->text) == '@') break;
		XL->category = INTERFACE_BODY_LCAT;
		L = XL;
		XL = XL->next_line;
	}

@<Deal with Definitions@> =
	if (S->md->using_syntax == V2_SYNTAX)
		Parser::wrong_version(S->md->using_syntax, L, "'@Definitions' headings", V1_SYNTAX);
	if (before_bar == FALSE) Main::error_in_web(I"Definitions used after bar", L);
	L->category = DEFINITIONS_LCAT;
	L->owning_paragraph = NULL;
	L->is_commentary = TRUE;
	before_bar = TRUE;
	next_par_number = 1;

@ An |@| sign in the first column, followed by a row of four or more dashes,
constitutes the optional division bar in a section.

@<Deal with the bar@> =
	if (S->md->using_syntax == V2_SYNTAX)
		Parser::wrong_version(S->md->using_syntax, L, "the bar '----...'", V1_SYNTAX);
	if (before_bar == FALSE) Main::error_in_web(I"second bar in the same section", L);
	L->category = BAR_LCAT;
	L->owning_paragraph = NULL;
	L->is_commentary = TRUE;
	comment_mode = TRUE;
	S->barred = TRUE;
	before_bar = FALSE;
	next_par_number = 1;

@ In version 1, the division point where a paragraoh begins to go into
verbatim code was not marked with an equals sign, but with one of the three
commands |@c| ("code"), |@e| ("early code") and |@x| ("code-like extract").
These had identical behaviour except for whether or not to tangle what
follows:

@<Deal with the code and extract markers@> =
	if (S->md->using_syntax != V1_SYNTAX)
		Parser::wrong_version(S->md->using_syntax, L, "'@c' and '@x'", V1_SYNTAX);
	L->category = BEGIN_CODE_LCAT;
	if ((Str::eq_wide_string(command_text, U"e")) && (current_paragraph))
		current_paragraph->placed_early = TRUE;
	if (Str::eq_wide_string(command_text, U"x")) code_lcat_for_body = TEXT_EXTRACT_LCAT;
	else code_lcat_for_body = CODE_BODY_LCAT;
	code_pl_for_body = NULL;
	comment_mode = FALSE;
	code_plainness_for_body = FALSE;
	hyperlink_body = FALSE;

@ This is for |@d| and |@define|. Definitions are intended to translate to
C preprocessor macros, Inform 6 |Constant|s, and so on.

@<Deal with the define marker@> =
	L->category = BEGIN_DEFINITION_LCAT;
	code_lcat_for_body = CONT_DEFINITION_LCAT;
	code_pl_for_body = NULL;
	match_results mr = Regexp::create_mr();
	if (Regexp::match(&mr, remainder, U"(%C+) (%c+)")) {
		L->text_operand = Str::duplicate(mr.exp[0]); /* name of term defined */
		L->text_operand2 = Str::duplicate(mr.exp[1]); /* Value */
	} else {
		L->text_operand = Str::duplicate(remainder); /* name of term defined */
		L->text_operand2 = Str::new(); /* no value given */
	}
	Analyser::mark_reserved_word_at_line(L, L->text_operand, CONSTANT_COLOUR);
	Ctags::note_defined_constant(L, L->text_operand);
	comment_mode = FALSE;
	L->is_commentary = FALSE;
	Regexp::dispose_of(&mr);

@ This is for |@e| (in version 2) and |@enum|, which makes an automatically
enumerated sort of |@d|.

@<Deal with the enumeration marker@> =
	L->category = BEGIN_DEFINITION_LCAT;
	text_stream *from = NULL;
	match_results mr = Regexp::create_mr();
	L->text_operand = Str::duplicate(remainder); /* name of term defined */
	TEMPORARY_TEXT(before)
	TEMPORARY_TEXT(after)
	if (LanguageMethods::parse_comment(S->sect_language, L->text_operand,
		before, after)) {
		Str::copy(L->text_operand, before);
	}
	DISCARD_TEXT(before)
	DISCARD_TEXT(after)
	Str::trim_white_space(L->text_operand);
	if (Regexp::match(&mr, L->text_operand, U"(%C+) from (%c+)")) {
		from = mr.exp[1];
		Str::copy(L->text_operand, mr.exp[0]);
	} else if (Regexp::match(&mr, L->text_operand, U"(%C+) (%c+)")) {
		Main::error_in_web(I"enumeration constants can't supply a value", L);
	}
	L->text_operand2 = Str::new();
	if (inweb_mode == TANGLE_MODE)
		Enumerations::define(L->text_operand2, L->text_operand, from, L);
	Analyser::mark_reserved_word_at_line(L, L->text_operand, CONSTANT_COLOUR);
	Ctags::note_defined_constant(L, L->text_operand);
	comment_mode = FALSE;
	L->is_commentary = FALSE;
	Regexp::dispose_of(&mr);

@ Here we handle paragraph breaks which may or may not be headings. In
version 1, |@p| was a heading, and |@pp| a grander heading, while plain |@|
is no heading at all. The use of "p" was a little confusing, and went back
to CWEB, which used the term "paragraph" differently from us: it was "p"
short for what CWEB called a "paragraph". We now use |@h| or equivalently
|@heading| for a heading.

The noteworthy thing here is the way we fool around with the text on the line
of the paragraph opening. This is one of the few cases where Inweb has
retained the stream-based style of CWEB, where escape characters can appear
anywhere in a line and line breaks are not significant. Thus
= (text)
	@h The chronology of French weaving. Auguste de Papillon (1734-56) soon
=
is split into two, so that the title of the paragraph is just "The chronology
of French weaving" and the remainder,
= (text)
	Auguste de Papillon (1734-56) soon
=
will be woven exactly as the succeeding lines will be.

@d ORDINARY_WEIGHT 0 /* an ordinary paragraph has this "weight" */
@d SUBHEADING_WEIGHT 1 /* a heading paragraph */

@<Begin a new paragraph of this weight@> =
	comment_mode = TRUE;
	L->is_commentary = TRUE;
	L->category = PARAGRAPH_START_LCAT;
	if (weight == SUBHEADING_WEIGHT) L->category = HEADING_START_LCAT;
	L->text_operand = Str::new(); /* title */
	match_results mr = Regexp::create_mr();
	if ((weight == SUBHEADING_WEIGHT) && (Regexp::match(&mr, remainder, U"(%c+). (%c+)"))) {
		L->text_operand = Str::duplicate(mr.exp[0]);
		L->text_operand2 = Str::duplicate(mr.exp[1]);
	} else if ((weight == SUBHEADING_WEIGHT) && (Regexp::match(&mr, remainder, U"(%c+). *"))) {
		L->text_operand = Str::duplicate(mr.exp[0]);
		L->text_operand2 = Str::new();
	} else {
		L->text_operand = Str::new();
		L->text_operand2 = Str::duplicate(remainder);
	}
	@<Create a new paragraph, starting here, as new current paragraph@>;

	L->owning_paragraph = current_paragraph;
	W->no_paragraphs++;
	Regexp::dispose_of(&mr);

@ So now it's time to create paragraph structures:

=
typedef struct paragraph {
	int above_bar; /* placed above the dividing bar in its section (in Version 1 syntax) */
	int placed_early; /* should appear early in the tangled code */
	int placed_very_early; /* should appear very early in the tangled code */
	int invisible; /* do not render paragraph number */
	struct text_stream *heading_text; /* if any - many paras have none */
	struct text_stream *ornament; /* a "P" for a pilcrow or "S" for section-marker */
	struct text_stream *paragraph_number; /* used in combination with the ornament */
	int next_child_number; /* used when working out paragraph numbers */
	struct paragraph *parent_paragraph; /* ditto */

	int weight; /* typographic prominence: one of the |*_WEIGHT| values */
	int starts_on_new_page; /* relevant for weaving to TeX only, of course */

	struct para_macro *defines_macro; /* there can only be one */
	struct linked_list *functions; /* of |function|: those defined in this para */
	struct linked_list *structures; /* of |language_type|: similarly */
	struct linked_list *taggings; /* of |paragraph_tagging| */
	struct linked_list *footnotes; /* of |footnote| */
	struct source_line *first_line_in_paragraph;
	struct section *under_section;
	CLASS_DEFINITION
} paragraph;

@<Create a new paragraph, starting here, as new current paragraph@> =
	paragraph *P = CREATE(paragraph);
	if (S->md->using_syntax != V1_SYNTAX) {
		P->above_bar = FALSE;
		P->placed_early = FALSE;
		P->placed_very_early = FALSE;
	} else {
		P->above_bar = before_bar;
		P->placed_early = before_bar;
		P->placed_very_early = FALSE;
	}
	P->invisible = FALSE;
	if (Str::eq(Bibliographic::get_datum(W->md, I"Paragraph Numbers Visibility"), I"Off"))
		P->invisible = TRUE;
	P->heading_text = Str::duplicate(L->text_operand);
	if ((S->md->using_syntax == V1_SYNTAX) && (before_bar))
		P->ornament = Str::duplicate(I"P");
	else
		P->ornament = Str::duplicate(I"S");
	WRITE_TO(P->paragraph_number, "%d", next_par_number++);
	P->parent_paragraph = NULL;
	P->next_child_number = 1;
	P->starts_on_new_page = FALSE;
	P->weight = weight;
	P->first_line_in_paragraph = L;
	P->defines_macro = NULL;
	P->functions = NEW_LINKED_LIST(function);
	P->structures = NEW_LINKED_LIST(language_type);
	P->taggings = NEW_LINKED_LIST(paragraph_tagging);
	P->footnotes = NEW_LINKED_LIST(footnote);

	P->under_section = S;
	S->sect_paragraphs++;
	ADD_TO_LINKED_LIST(P, paragraph, S->paragraphs);

	current_paragraph = P;

@ Finally, we're down to either commentary or code.

@<This is a line destined for commentary@> =
	match_results mr = Regexp::create_mr();
	if (Regexp::match(&mr, L->text, U">> (%c+)")) {
		L->category = SOURCE_DISPLAY_LCAT;
		L->text_operand = Str::duplicate(mr.exp[0]);
	}
	Regexp::dispose_of(&mr);

@ Note that in an |@d| definition, a blank line is treated as the end of the
definition. (This is unnecessary for C, and is a point of difference with
CWEB, but is needed for languages which don't allow multi-line definitions.)

@<This is a line destined for the verbatim code@> =
	if ((L->category != BEGIN_DEFINITION_LCAT) && (L->category != COMMAND_LCAT)) {
		L->category = code_lcat_for_body;
		L->plainer = code_plainness_for_body;
		L->enable_hyperlinks = hyperlink_body;
		if (L->category == TEXT_EXTRACT_LCAT) {
			L->colour_as = code_pl_for_body;
			if (code_destination) L->extract_to = Str::duplicate(code_destination);
		}
	}

	if ((L->category == CONT_DEFINITION_LCAT) && (Regexp::string_is_white_space(L->text))) {
		L->category = COMMENT_BODY_LCAT;
		L->is_commentary = TRUE;
		code_lcat_for_body = COMMENT_BODY_LCAT;
		comment_mode = TRUE;
	}

	LanguageMethods::subcategorise_line(S->sect_language, L);

@ The purpose text occurs just below the heading. In version 1 it's cued with
a |@Purpose:| command; in version 2 it is unmarked. The following routine
is not elegant but handles the back end of both possibilities.

=
text_stream *Parser::extract_purpose(text_stream *prologue, source_line *XL, section *S, source_line **adjust) {
	text_stream *P = Str::duplicate(prologue);
	while ((XL) && (XL->next_line) && (XL->owning_section == S) &&
		(((adjust) && (Characters::isalnum(Str::get_first_char(XL->text)))) ||
		 ((!adjust) && (XL->category == COMMENT_BODY_LCAT)))) {
		WRITE_TO(P, " %S", XL->text);
		XL->category = PURPOSE_BODY_LCAT;
		XL->is_commentary = TRUE;
		if (adjust) *adjust = XL;
		XL = XL->next_line;
	}
	Str::trim_white_space(P);
	return P;
}

@h Footnote notation.

=
typedef struct footnote {
	int footnote_cue_number; /* used only for |FOOTNOTE_TEXT_LCAT| lines */
	int footnote_text_number; /* used only for |FOOTNOTE_TEXT_LCAT| lines */
	struct text_stream *cue_text;
	int cued_already;
	CLASS_DEFINITION
} footnote;

@<Work out footnote numbering for this paragraph@> =
	int next_footnote_in_para = 1;
	footnote *current_text = NULL;
	TEMPORARY_TEXT(before)
	TEMPORARY_TEXT(cue)
	TEMPORARY_TEXT(after)
	for (source_line *L = P->first_line_in_paragraph;
		((L) && (L->owning_paragraph == P)); L = L->next_line)
		if (L->is_commentary) {
			Str::clear(before); Str::clear(cue); Str::clear(after);
			if (Parser::detect_footnote(W, L->text, before, cue, after)) {
				int this_is_a_cue = FALSE;
				LOOP_THROUGH_TEXT(pos, before)
					if (Characters::is_whitespace(Str::get(pos)) == FALSE)
						this_is_a_cue = TRUE;
				if (this_is_a_cue == FALSE)
					@<This line begins a footnote text@>;
			}
			L->footnote_text = current_text;
		}
	DISCARD_TEXT(before)
	DISCARD_TEXT(cue)
	DISCARD_TEXT(after)

@<This line begins a footnote text@> =
	L->category = FOOTNOTE_TEXT_LCAT;
	footnote *F = CREATE(footnote);	
	F->footnote_cue_number = Str::atoi(cue, 0);
	if (F->footnote_cue_number != next_footnote_in_para) {
		TEMPORARY_TEXT(err)
		WRITE_TO(err, "footnote should be numbered [%d], not [%d]",
			next_footnote_in_para, F->footnote_cue_number);
		Main::error_in_web(err, L);
		DISCARD_TEXT(err)
	}
	next_footnote_in_para++;
	F->footnote_text_number = next_footnote++;
	F->cue_text = Str::new();
	F->cued_already = FALSE;
	WRITE_TO(F->cue_text, "%d", F->footnote_text_number);
	ADD_TO_LINKED_LIST(F, footnote, P->footnotes);
	current_text = F;

@ Where:

=
int Parser::detect_footnote(web *W, text_stream *matter, text_stream *before,
	text_stream *cue, text_stream *after) {
	text_stream *fn_on_notation =
		Bibliographic::get_datum(W->md, I"Footnote Begins Notation");
	text_stream *fn_off_notation =
		Bibliographic::get_datum(W->md, I"Footnote Ends Notation");
	if (Str::ne(fn_on_notation, I"Off")) {
		int N1 = Str::len(fn_on_notation);
		int N2 = Str::len(fn_off_notation);
		if ((N1 > 0) && (N2 > 0))
			for (int i=0; i < Str::len(matter); i++) {
				if (Str::includes_at(matter, i, fn_on_notation)) {
					int j = i + N1 + 1;
					while (j < Str::len(matter)) {
						if (Str::includes_at(matter, j, fn_off_notation)) {
							TEMPORARY_TEXT(b)
							TEMPORARY_TEXT(c)
							TEMPORARY_TEXT(a)
							Str::substr(b, Str::start(matter), Str::at(matter, i));
							Str::substr(c, Str::at(matter, i + N1), Str::at(matter, j));
							Str::substr(a, Str::at(matter, j + N2), Str::end(matter));
							int allow = TRUE;
							LOOP_THROUGH_TEXT(pos, c)
								if (Characters::isdigit(Str::get(pos)) == FALSE)
									allow = FALSE;
							if (allow) {
								Str::clear(before); Str::copy(before, b);
								Str::clear(cue); Str::copy(cue, c);
								Str::clear(after); Str::copy(after, a);
							}
							DISCARD_TEXT(b)
							DISCARD_TEXT(c)
							DISCARD_TEXT(a)
							if (allow) return TRUE;
						}
						j++;
					}			
				}
			}
	}
	return FALSE;
}

footnote *Parser::find_footnote_in_para(paragraph *P, text_stream *cue) {
	int N = Str::atoi(cue, 0);		
	footnote *F;
	if (P)
		LOOP_OVER_LINKED_LIST(F, footnote, P->footnotes)
			if (N == F->footnote_cue_number)
				return F;
	return NULL;
}

@h Parsing of dimensions.
It's possible, optionally, to specify width and height for some visual matter.
This is the syntax used.

@d POINTS_PER_CM 72

=
text_stream *Parser::dimensions(text_stream *item, int *w, int *h, source_line *L) {
	int sv = L->owning_section->md->using_syntax;
	*w = -1; *h = -1;
	text_stream *use = item;
	match_results mr = Regexp::create_mr();
	if (Regexp::match(&mr, item, U"(%c+) at (%d+) by (%d+)")) {
		if (sv < V2_SYNTAX)
			Parser::wrong_version(sv, L, "at X by Y", V2_SYNTAX);
		*w = Str::atoi(mr.exp[1], 0);
		*h = Str::atoi(mr.exp[2], 0);
		use = Str::duplicate(mr.exp[0]);
	} else if (Regexp::match(&mr, item, U"(%c+) at height (%d+)")) {
		if (sv < V2_SYNTAX)
			Parser::wrong_version(sv, L, "at height Y", V2_SYNTAX);
		*h = Str::atoi(mr.exp[1], 0);
		use = Str::duplicate(mr.exp[0]);
	} else if (Regexp::match(&mr, item, U"(%c+) at width (%d+)")) {
		if (sv < V2_SYNTAX)
			Parser::wrong_version(sv, L, "at width Y", V2_SYNTAX);
		*w = Str::atoi(mr.exp[1], 0);
		use = Str::duplicate(mr.exp[0]);
	} else if (Regexp::match(&mr, item, U"(%c+) at (%d+)cm by (%d+)cm")) {
		if (sv < V2_SYNTAX)
			Parser::wrong_version(sv, L, "at Xcm by Ycm", V2_SYNTAX);
		*w = POINTS_PER_CM*Str::atoi(mr.exp[1], 0);
		*h = POINTS_PER_CM*Str::atoi(mr.exp[2], 0);
		use = Str::duplicate(mr.exp[0]);
	} else if (Regexp::match(&mr, item, U"(%c+) at height (%d+)cm")) {
		if (sv < V2_SYNTAX)
			Parser::wrong_version(sv, L, "at height Ycm", V2_SYNTAX);
		*h = POINTS_PER_CM*Str::atoi(mr.exp[1], 0);
		use = Str::duplicate(mr.exp[0]);
	} else if (Regexp::match(&mr, item, U"(%c+) at width (%d+)cm")) {
		if (sv < V2_SYNTAX)
			Parser::wrong_version(sv, L, "at width Ycm", V2_SYNTAX);
		*w = POINTS_PER_CM*Str::atoi(mr.exp[1], 0);
		use = Str::duplicate(mr.exp[0]);
	}
	Regexp::dispose_of(&mr);
	return use;
}

@h Version errors.
These are not fatal (why should they be?): Inweb carries on and allows the use
of the feature despite the version mismatch. They nevertheless count as errors
when it comes to Inweb's exit code, so they will halt a make.

=
void Parser::wrong_version(int using, source_line *L, char *feature, int need) {
	TEMPORARY_TEXT(warning)
	WRITE_TO(warning, "%s is a feature of version %d syntax (you're using v%d)",
		feature, need, using);
	Main::error_in_web(warning, L);
	DISCARD_TEXT(warning)
}
