[Markdown::] Markdown.

To store the results of parsing the Markdown markup notation.

@h Introduction.
The following is not a simple algorithm. Those who, like myself three days ago,
think there ought to be a simple way to parse Markdown are invited to read
through the invaluable //CommonMark specification -> https://spec.commonmark.org/0.30//.
I am following version 0.30, from 2019, the most recent at time of writing.

The functions in this section provide a public API for dealing with Markdown.
We provide two basic functions:

|Markdown::parse(text)| turns the text |T| into a "Markdown tree".

|Markdown::render(OUT, tree)| outputs HTML expressing the Markdown tree |tree|.

The combination |Markdown::render(OUT, Markdown::parse(T))| thus turns
Markdown-marked-up text into HTML.

@ Markdown was devised by John Gruber in 2004, building on the work of Aaron Swartz
in 2002; CommonMark is the work of John MacFarlane and others, and began around 2012,
reflecting that Markdown was becoming indispensable to users and needed to be
codified.

This was difficult partly because early implementations of Markdown were fairly
hit-and-miss, but that can be exaggerated. No human being would ever naturally
write any of the syntaxes which trip up bad Markdown parsers, which is why
the CommonMark test suite often looks like the effect of monkeys discovering
the top row on a typewriter. Gruber declines to specify Markdown precisely, and
perhaps he's right about that. Markdown is more of a social construct than
a technological one. The practical effect is that his early Perl script
is studied as if it were a sometimes baffling scripture. But in many ways
that doesn't matter.

The real problem with Markdown is its genius is also its greatest weakness: that
no input text is illegal. There is no such thing as erroneous Markdown. There is
only Markdown that does something you didn't expect. And because all inputs are
legal, we cannot exclude tremendously unwise or on-its-face ambiguous syntax. We
have to take a decision on what it means in every conceivable case.

CommonMark is not wholly unambiguous, which is next to impossible, but it's very
precise and is certainly now best practice. It also provides an immensely valuable
test suite, as noted above, of 652 test examples. In every case
|Markdown::render(OUT, Markdown::parse(T))| exactly agrees with CommonMark,
producing precisely the same (and not simply equivalent) HTML output. These are
all organised as test cases of |foundation-test|, so if Intest passes all
the |foundation-test| cases then this parser is in agreement with CommonMark.
Do not modify it without checking this.

@ We will certainly want to know what's going on for debugging purposes, so:

=
int tracing_Markdown_parser = FALSE;
void Markdown::set_tracing(int state) {
	tracing_Markdown_parser = state;
}

@ As CommonMark recommends, I take the obvious two-stage strategy:

(1) Dividing the text into lines and building a block structure out of that,
which results in a complete and final tree for all of the container and leaf
block types.

(2) Refining the copy inside these containers to break down the inline content
into what's emphasised, and so on.

Phase I has to preserve some state between lines in order to keep track of
context, but that is opaque to us here.

=
markdown_item *Markdown::parse(text_stream *text) {
	if (tracing_Markdown_parser) PRINT("Begin Markdown parse, phase I\n");
	markdown_item *tree = Markdown::new_item(DOCUMENT_MIT);
	md_links_dictionary *dict = Markdown::new_links_dictionary();
	md_doc_state *state = MDBlockParser::initialise(tree, dict);
	@<Phase I@>;
	if (tracing_Markdown_parser) {
		PRINT("Tree at end of phase I:\n");
		Markdown::debug_subtree(STDOUT, tree);
		PRINT("======\nPhase II\n");
	}
	@<Phase II@>;
	if (tracing_Markdown_parser) {
		PRINT("======\nTree at end of phase II:\n");
		Markdown::debug_subtree(STDOUT, tree);
		PRINT("======\n");
	}
	return tree;
}

@ The following divides |line| into lines at newline characters. We don't need
to worry about Windows line endings, etc., because the copy arriving here will
all have arrived via other Foundation functions which took care of all that:
so we can assume that our input is a string of Unicode code points, with |'\n'|
as the newline.

Note that any final newline is ignored: thus |This\nThat\n| is two lines, not
three lines of which the third is empty.

@<Phase I@> =
	TEMPORARY_TEXT(line)
	LOOP_THROUGH_TEXT(pos, text) {
		wchar_t c = Str::get(pos);
		if (c == '\n') {
			MDBlockParser::add_to_document(state, line);
			Str::clear(line);
		} else {
			PUT_TO(line, c);
		}
	}
	if (Str::len(line) > 0) MDBlockParser::add_to_document(state, line);
	MDBlockParser::close_block(state, tree);
	if (tracing_Markdown_parser) PRINT("======\nGathering lists\n");
	MDBlockParser::gather_lists(state, tree);
	MDBlockParser::propagate_white_space_follows(state, tree);

@ Note that the Phase I parser state is not used in Phase II, which is
context-free except for its use of the links dictionary:

@<Phase II@> =
	MDInlineParser::inline_recursion(dict, tree);

@ Rendering is similarly delegated:

=
void Markdown::render(OUTPUT_STREAM, markdown_item *tree) {
	MDRenderer::render(OUT, tree);
}

@h Storing marked-up copy.
We will represent the results of parsing Markdown in the obvious way: as a
tree structure, made of nodes called "items" which are |markdown_item| objects.

Each node has one of the following types. |DOCUMENT_MIT| is for the head node,
and no other.

@e DOCUMENT_MIT from 1

@ Next we have the (other) "container block" items, which can contain either
other containers (though not |DOCUMENT_MIT) or leaf blocks. An |ORDERED_LIST_MIT|
can only contain |ORDERED_LIST_ITEM_MIT| blocks, and similarly for unordered lists.

@e BLOCK_QUOTE_MIT
@e UNORDERED_LIST_MIT
@e ORDERED_LIST_MIT
@e UNORDERED_LIST_ITEM_MIT
@e ORDERED_LIST_ITEM_MIT

@ Now the "leaf block" items. |EMPTY_MIT| items are ignored: they are used
to represent that |PARAGRAPH_MIT| turned out to contain only link references
and was discarded. (Properly, we should simply remove such items from the tree,
but it's more convenient not to have to do the necessary surgery.)

@e PARAGRAPH_MIT
@e THEMATIC_MIT
@e HEADING_MIT
@e CODE_BLOCK_MIT
@e HTML_MIT
@e EMPTY_MIT

@ Each leaf block is either empty, or contains a |MATERIAL_MIT| item, which
holds what CommonMark calls "inline content". For example, the body text of a
paragraph is inline content.

@e MATERIAL_MIT

@ And a material item contains a list of the following.

@e PLAIN_MIT
@e LINE_BREAK_MIT
@e SOFT_BREAK_MIT

@e EMPHASIS_MIT
@e STRONG_MIT
@e CODE_MIT

@e URI_AUTOLINK_MIT
@e EMAIL_AUTOLINK_MIT
@e INLINE_HTML_MIT

@e LINK_MIT
@e IMAGE_MIT

@ And these are used only as child nodes of |LINK_MIT| or |IMAGE_MIT| items:

@e LINK_DEST_MIT
@e LINK_TITLE_MIT

@ Recapitulating all of that:

=
text_stream *Markdown::item_type_name(int t) {
	switch (t) {
		case DOCUMENT_MIT:            return I"DOCUMENT_MIT";

		case BLOCK_QUOTE_MIT:         return I"BLOCK_QUOTE";
		case UNORDERED_LIST_MIT:      return I"UNORDERED_LIST";
		case ORDERED_LIST_MIT:        return I"ORDERED_LIST";
		case UNORDERED_LIST_ITEM_MIT: return I"UNORDERED_LIST_ITEM";
		case ORDERED_LIST_ITEM_MIT:   return I"ORDERED_LIST_ITEM";

		case PARAGRAPH_MIT:           return I"PARAGRAPH";
		case THEMATIC_MIT:            return I"THEMATIC";
		case HEADING_MIT:             return I"HEADING";
		case CODE_BLOCK_MIT:          return I"CODE_BLOCK";
		case HTML_MIT:                return I"HTML";
		case EMPTY_MIT:               return I"LINK_REF";

		case MATERIAL_MIT:            return I"MATERIAL";

		case PLAIN_MIT:               return I"PLAIN";
		case LINE_BREAK_MIT:          return I"LINE_BREAK";
		case SOFT_BREAK_MIT:          return I"SOFT_BREAK";

		case EMPHASIS_MIT:            return I"EMPHASIS";
		case STRONG_MIT:              return I"STRONG";
		case CODE_MIT:                return I"CODE";

		case URI_AUTOLINK_MIT:        return I"URI_AUTOLINK";
		case EMAIL_AUTOLINK_MIT:      return I"EMAIL_AUTOLINK";
		case INLINE_HTML_MIT:         return I"INLINE_HTML";

		case LINK_MIT:                return I"LINK";
		case IMAGE_MIT:               return I"IMAGE";

		case LINK_DEST_MIT:           return I"LINK_DEST";
		case LINK_TITLE_MIT:          return I"LINK_TITLE";

		default:                      return I"<UNKNOWN>";
	}
}

int Markdown::item_type_container_block(int t) {
	switch (t) {
		case DOCUMENT_MIT:            return TRUE;
		case BLOCK_QUOTE_MIT:         return TRUE;
		case ORDERED_LIST_MIT:        return TRUE;
		case UNORDERED_LIST_MIT:      return TRUE;
		case ORDERED_LIST_ITEM_MIT:   return TRUE;
		case UNORDERED_LIST_ITEM_MIT: return TRUE;
	}
	return FALSE;
}

int Markdown::item_type_leaf_block(int t) {
	switch (t) {
		case PARAGRAPH_MIT:           return TRUE;
		case THEMATIC_MIT:            return TRUE;
		case HEADING_MIT:             return TRUE;
		case CODE_BLOCK_MIT:          return TRUE;
		case HTML_MIT:                return TRUE;
		case EMPTY_MIT:               return TRUE;
	}
	return FALSE;
}

@ All nodes other than blocks are "inline" items:

=
int Markdown::item_type_inline(int t) {
	switch (t) {
		case MATERIAL_MIT:            return TRUE;

		case PLAIN_MIT:               return TRUE;
		case LINE_BREAK_MIT:          return TRUE;
		case SOFT_BREAK_MIT:          return TRUE;

		case EMPHASIS_MIT:            return TRUE;
		case STRONG_MIT:              return TRUE;
		case CODE_MIT:                return TRUE;

		case URI_AUTOLINK_MIT:        return TRUE;
		case EMAIL_AUTOLINK_MIT:      return TRUE;
		case INLINE_HTML_MIT:         return TRUE;

		case LINK_MIT:                return TRUE;
		case IMAGE_MIT:               return TRUE;

		case LINK_DEST_MIT:           return TRUE;
		case LINK_TITLE_MIT:          return TRUE;
	}
	return FALSE;
}

@ A "plainish" item contains plain text and/or line breaks:

=
int Markdown::plainish(markdown_item *md) {
	if (md) return Markdown::item_type_plainish(md->type);
	return FALSE;
}

int Markdown::item_type_plainish(int t) {
	switch (t) {
		case PLAIN_MIT:               return TRUE;
		case LINE_BREAK_MIT:          return TRUE;
		case SOFT_BREAK_MIT:          return TRUE;
	}
	return FALSE;
}

@ A "quasi-plainish" item can also include autolinks:

=
int Markdown::quasi_plainish(markdown_item *md) {
	if (md) return Markdown::item_type_quasi_plainish(md->type);
	return FALSE;
}

int Markdown::item_type_quasi_plainish(int t) {
	switch (t) {
		case PLAIN_MIT:               return TRUE;
		case LINE_BREAK_MIT:          return TRUE;
		case SOFT_BREAK_MIT:          return TRUE;
		case INLINE_HTML_MIT:         return TRUE;
	}
	return FALSE;
}

@h Items.
Clearly with only a little effort we could make this structure smaller, but
clarity seems more important. In typical MD text, there are only about two
or three items per line, so the memory overhead is harmless enough.

=
typedef struct markdown_item {
	int type; /* one of the |*_MIT| types above */

	/* text storage for inline items */
	struct text_stream *sliced_from; 
	int from; /*inline nodes only */
	int to; /*inline nodes only */

	/* text storage for block items */
	struct text_stream *stashed;

	/* relevant for block nodes only */
	int whitespace_follows;
	struct text_stream *info_string;
	int details;
	int open;

	/* tree position of this item */
	struct markdown_item *next;
	struct markdown_item *down;
	struct markdown_item *copied_from;

	int cycle_count; /* used only for tracing the tree when debugging */
	int id;          /* used only for tracing the tree when debugging */
	CLASS_DEFINITION
} markdown_item;

int md_ids = 1;
markdown_item *Markdown::new_item(int type) {
	markdown_item *md = CREATE(markdown_item);
	md->type = type;

	md->open = NOT_APPLICABLE;
	md->copied_from = NULL;

	md->info_string = NULL;
	md->details = 0;

	md->sliced_from = NULL; md->from = 0; md->to = -1;
	md->stashed = NULL;

	md->next = NULL; md->down = NULL;
	md->whitespace_follows = FALSE;

	md->cycle_count = 0;
	md->id = md_ids++;
	return md;
}

@ A deep copy of the tree hanging from node |md|. Because this is only ever
done for subtrees at the inline level, we can ignore many of the fields.

=
markdown_item *Markdown::deep_copy(markdown_item *md) {
	if (md == NULL) internal_error("cannot copy null node");
	if (Markdown::item_type_inline(md->type) == FALSE)
		internal_error("can only copy inline nodes");
	markdown_item *copied = Markdown::new_item(md->type);
	if (Str::len(md->sliced_from) > 0) {
		copied->sliced_from = Str::duplicate(md->sliced_from);
	}
	copied->from = md->from;
	copied->to = md->to;
	copied->copied_from = md;
	for (markdown_item *c = md->down; c; c = c->next)
		Markdown::add_to(Markdown::deep_copy(c), copied);
	return copied;
}

@ Enough of creation. The following makes |md| the latest child of |owner|:

=
void Markdown::add_to(markdown_item *md, markdown_item *owner) {
	md->next = NULL;
	if (owner->down == NULL) { owner->down = md; return; }
	for (markdown_item *ch = owner->down; ch; ch = ch->next)
		if (ch->next == NULL) { ch->next = md; return; }
}

@ The |HEADING_MIT| item, and no other, has a "level" from 1 to 6.

=
int Markdown::get_heading_level(markdown_item *md) {
	if ((md == NULL) || (md->type != HEADING_MIT)) return 0;
	return md->details;
}

void Markdown::set_heading_level(markdown_item *md, int L) {
	if ((md == NULL) || (md->type != HEADING_MIT)) internal_error("not a heading");
	if ((L < 1) || (L > 6)) internal_error("bad heading level");
	md->details = L;
}

@ List items have a "flavour".

=
int Markdown::get_item_number(markdown_item *md) {
	if ((md == NULL) || (md->type != ORDERED_LIST_ITEM_MIT)) return 0;
	if (md->details < 0) return -(md->details+1);
	return md->details;
}

wchar_t Markdown::get_item_flavour(markdown_item *md) {
	if ((md == NULL) ||
		((md->type != ORDERED_LIST_ITEM_MIT) && (md->type != UNORDERED_LIST_ITEM_MIT)))
		return 0;
	if (md->type == ORDERED_LIST_ITEM_MIT) {
		if (md->details >= 0) return ')';
		return '.';
	}
	return (wchar_t) md->details;
}

void Markdown::set_item_number_and_flavour(markdown_item *md, int L, wchar_t f) {
	if (md->type == ORDERED_LIST_ITEM_MIT) {
		if (L < 0) internal_error("bad list item number");
		if (f == ')') md->details = L;
		else md->details = -1 - L;
	}
	if (md->type == UNORDERED_LIST_ITEM_MIT) {
		if (L != 0) internal_error("inappropriate list item number");
		md->details = f;
	}
}

@ Markdown uses backslash as an escape character, with double-backslash meaning
a literal backslash. It follows that if a character is preceded by an odd number
of backslashes, it must be escaped; if an even (including zero) it is unescaped.

This function returns a harmless letter for an escaped active character, so
that it can be used to test for unescaped active characters.

=
wchar_t Markdown::get_unescaped(md_charpos pos, int offset) {
	wchar_t c = Markdown::get_offset(pos, offset);
	int preceding_backslashes = 0;
	while (Markdown::get_offset(pos, offset - 1 - preceding_backslashes) == '\\')
		preceding_backslashes++;
	if (preceding_backslashes % 2 == 1) return 'a';
	return c;
}

@ An "unescaped run" is a sequence of one or more instances of |of|, which
must be non-zero, which are not escaped with a backslash.

=
int Markdown::unescaped_run(md_charpos pos, wchar_t of) {
	int count = 0;
	while (Markdown::get_unescaped(pos, count) == of) count++;
	if (Markdown::get_unescaped(pos, -1) == of) count = 0;
	return count;
}

@h Working with slices.
A "slice" contains a snipped of text, where by convention the portion is
from character positions |from| to |to| inclusive. If |to| is less than |from|,
it represents the empty snippet. Slices are used only by inline items, and
are a way of saving memory rather than endless duplicating fragments of text.

=
markdown_item *Markdown::new_slice(int type, text_stream *text, int from, int to) {
	markdown_item *md = Markdown::new_item(type);
	md->sliced_from = text;
	md->from = from;
	md->to = to;
	return md;
}

@ This is a convenient adaptation of |Str::get_at| which reads from the slice
inside a markdown node. Note that it is able to see characters outside the
range being sliced: this is intentional and is needed for some of the
delimiter-scanning.

=
wchar_t Markdown::get_at(markdown_item *md, int at) {
	if (md == NULL) return 0;
	if (Str::len(md->sliced_from) == 0) return 0;
	return Str::get_at(md->sliced_from, at);
}

@ This function recursively calculates the number of characters of actual text
represented by a subtree. (Well, strictly speaking, code points. It would
read |&HilbertSpace;| as width 14, not 1.)

=
int Markdown::width(markdown_item *md) {
	if (md) {
		int width = 0;
		if (md->type == PLAIN_MIT) {
			for (int i=md->from; i<=md->to; i++) {
				wchar_t c = Markdown::get_at(md, i);
				if (c == '\\') i++;
				width++;
			}
		}
		if ((md->type == CODE_MIT) || (md->type == URI_AUTOLINK_MIT) ||
			(md->type == EMAIL_AUTOLINK_MIT) || (md->type == INLINE_HTML_MIT)) {
			for (int i=md->from; i<=md->to; i++) {
				width++;
			}
		}
		if (md->type == LINE_BREAK_MIT) width++;
		if (md->type == SOFT_BREAK_MIT) width++;
		for (markdown_item *c = md->down; c; c = c->next)
			width += Markdown::width(c);
		return width;
	}
	return 0;
}

@ It turns out to be convenient to represent a run of material being worked
on as a linked list of items, and then we want to represent sub-intervals of
that list, which means we need a way to indicate "character position X in item Y".
This is provided by:

=
typedef struct md_charpos {
	struct markdown_item *md;
	int at;
} md_charpos;

@ The equivalent of a null pointer, or an unset marker:

=
md_charpos Markdown::nowhere(void) {
	md_charpos pos;
	pos.md = NULL;
	pos.at = -1;
	return pos;
}

md_charpos Markdown::pos(markdown_item *md, int at) {
	if (md == NULL) return Markdown::nowhere();
	md_charpos pos;
	pos.md = md;
	pos.at = at;
	return pos;
}

int Markdown::somewhere(md_charpos pos) {
	if (pos.md) return TRUE;
	return FALSE;
}

@ This is a rather strict form of equality:

=
int Markdown::pos_eq(md_charpos A, md_charpos B) {
	if ((A.md) && (A.md == B.md) && (A.at == B.at)) return TRUE;
	if ((A.md == NULL) && (B.md == NULL)) return TRUE;
	return FALSE;
}

@ Whereas this is more lax, and reflects the fact that, when surgery
is going on to split items into new items, there can be multiple items which
represent the same piece of text:

=
int Markdown::is_in(md_charpos pos, markdown_item *md) {
	if ((Markdown::somewhere(pos)) && (md)) {
		if ((md->sliced_from) && (md->sliced_from == pos.md->sliced_from) &&
			(pos.at >= md->from) && (pos.at <= md->to)) return TRUE;
	}
	return FALSE;
}

@ "The Left Edge of Nowhere" would make a good pulp 70s sci-fi paperback, but
failing that:

=
md_charpos Markdown::left_edge_of(markdown_item *md) {
	if (md == NULL) return Markdown::nowhere();
	return Markdown::pos(md, md->from);
}

@ To "advance" is to move one character position forward in the linked list
of items. Note that the position must remain in a plainish item at all times,
and this may mean that whole non-plainish items are skipped.

=
md_charpos Markdown::advance(md_charpos pos) {
	if (Markdown::somewhere(pos)) {
		if (pos.at < pos.md->to) { pos.at++; return pos; }
		pos.md = pos.md->next;
		while ((pos.md) && (Markdown::plainish(pos.md) == FALSE)) pos.md = pos.md->next;
		if (pos.md) { pos.at = pos.md->from; return pos; }
	}
	return Markdown::nowhere();
}

@ A more restrictive version halts at the first non-plainish item:

=
md_charpos Markdown::advance_plainish_only(md_charpos pos) {
	if (Markdown::somewhere(pos)) {
		if (pos.at < pos.md->to) { pos.at++; return pos; }
		pos.md = pos.md->next;
		if ((pos.md) && (Markdown::plainish(pos.md))) { pos.at = pos.md->from; return pos; }
	}
	return Markdown::nowhere();
}

@ A fractionally different version again:

=
md_charpos Markdown::advance_quasi_plainish_only(md_charpos pos) {
	if (Markdown::somewhere(pos)) {
		if (pos.at < pos.md->to) { pos.at++; return pos; }
		pos.md = pos.md->next;
		if ((pos.md) && (Markdown::quasi_plainish(pos.md))) { pos.at = pos.md->from; return pos; }
	}
	return Markdown::nowhere();
}

@ And these halt at a specific point:

=
md_charpos Markdown::advance_up_to(md_charpos pos, md_charpos end) {
	if ((Markdown::somewhere(end)) &&
		(pos.md->sliced_from == end.md->sliced_from) && (pos.at >= end.at))
		return Markdown::nowhere();
	return Markdown::advance(pos);
}

md_charpos Markdown::advance_up_to_plainish_only(md_charpos pos, md_charpos end) {
	if ((Markdown::somewhere(end)) &&
		(pos.md->sliced_from == end.md->sliced_from) && (pos.at >= end.at))
		return Markdown::nowhere();
	return Markdown::advance_plainish_only(pos);
}

md_charpos Markdown::advance_up_to_quasi_plainish_only(md_charpos pos, md_charpos end) {
	if ((Markdown::somewhere(end)) &&
		(pos.md->sliced_from == end.md->sliced_from) && (pos.at >= end.at))
		return Markdown::nowhere();
	return Markdown::advance_quasi_plainish_only(pos);
}

@ The character at a given position:

=
wchar_t Markdown::get(md_charpos pos) {
	return Markdown::get_offset(pos, 0);
}

wchar_t Markdown::get_offset(md_charpos pos, int by) {
	if (Markdown::somewhere(pos)) return Markdown::get_at(pos.md, pos.at + by);
	return 0;
}

void Markdown::put(md_charpos pos, wchar_t c) {
	Markdown::put_offset(pos, 0, c);
}

void Markdown::put_offset(md_charpos pos, int by, wchar_t c) {
	if (Markdown::somewhere(pos)) Str::put_at(pos.md->sliced_from, pos.at + by, c);
}

@ Now for some surgery. We want to take a linked list (the "chain") and cut
it into a left and right hand side, which partition its character positions
exactly. If the cut point does not represent a position in the list, then
the righthand piece will be empty.

We will need two versions of this: in the first, the "cut point" character
becomes the leftmost character of the righthand piece.

=
void Markdown::cut_to_just_before(markdown_item *chain_from, md_charpos cut_point,
	markdown_item **left_segment, markdown_item **right_segment) {
	markdown_item *L = chain_from, *R = NULL;
	if ((chain_from) && (Markdown::somewhere(cut_point))) {
		markdown_item *md, *md_prev = NULL;
		for (md = chain_from; (md) && (Markdown::is_in(cut_point, md) == FALSE);
			md_prev = md, md = md->next) ;
		if (md) {
			if (cut_point.at <= md->from) {
				if (md_prev) md_prev->next = NULL; else L = NULL;
				R = md;
			} else {
				int old_to = md->to;
				md->to = cut_point.at - 1;
				markdown_item *splinter =
					Markdown::new_slice(md->type, md->sliced_from, cut_point.at, old_to);
				splinter->next = md->next;
				md->next = NULL;
				R = splinter;
			}
		}
	}
	if (left_segment) *left_segment = L;
	if (right_segment) *right_segment = R;
}

@ In this version, the "cut point" becomes the rightmost character of the
lefthand piece.

=
void Markdown::cut_to_just_at(markdown_item *chain_from, md_charpos cut_point,
	markdown_item **left_segment, markdown_item **right_segment) {
	markdown_item *L = chain_from, *R = NULL;
	if ((chain_from) && (Markdown::somewhere(cut_point))) {
		markdown_item *md, *md_prev = NULL;
		for (md = chain_from; (md) && (Markdown::is_in(cut_point, md) == FALSE);
			md_prev = md, md = md->next) ;
		if (md) {
			if (cut_point.at >= md->to) {
				R = md->next;
				md->next = NULL;
			} else {
				int old_to = md->to;
				md->to = cut_point.at;
				markdown_item *splinter =
					Markdown::new_slice(md->type, md->sliced_from, cut_point.at + 1, old_to);
				splinter->next = md->next;
				md->next = NULL;
				R = splinter;
			}
		}
	}
	if (left_segment) *left_segment = L;
	if (right_segment) *right_segment = R;
}

@ Combining these, we can cut a chain into three, with the middle part being
the range |A| to |B| inclusive.

=
void Markdown::cut_interval(markdown_item *chain_from, md_charpos A, md_charpos B,
	markdown_item **left_segment, markdown_item **middle_segment, markdown_item **right_segment) {
	markdown_item *interstitial = NULL;
	Markdown::cut_to_just_before(chain_from, A, left_segment, &interstitial);
	Markdown::cut_to_just_at(interstitial, B, &interstitial, right_segment);
	if (middle_segment) *middle_segment = interstitial;
}

@h Links dictionary.
Every Markdown document has its own dictionary of link labels, built during
Phase I and used during Phase II. For example, the label |home| might have
destination |https://supervillain.com/secret-lair| and title |"Evil Plans"|.

=
typedef struct md_links_dictionary {
	struct dictionary *dict;
	CLASS_DEFINITION
} md_links_dictionary;

typedef struct md_link_dictionary_entry {
	struct text_stream *destination;
	struct text_stream *title;
	CLASS_DEFINITION
} md_link_dictionary_entry;

md_links_dictionary *Markdown::new_links_dictionary(void) {
	md_links_dictionary *dict = CREATE(md_links_dictionary);
	dict->dict = Dictionaries::new(32, FALSE); /* of |md_link_dictionary_entry| */
	return dict;
}

@ Here we create entries. A second definition of the same label is not an
error, because nothing is ever an error. The first definition remains, and
subsequent ones are ignored. (See CommonMark at 6.3: "If there are multiple
matching reference link definitions, the one that comes first in the document
is used." Phase I parsing calls the following in sequential order.)

=
void Markdown::create(md_links_dictionary *dict, text_stream *label,
	text_stream *destination, text_stream *title) {
	Markdown::normalise_link_label(label);
	if (tracing_Markdown_parser) {
		PRINT("[%S] := %S", label, destination);
		if (Str::len(title) > 0) PRINT(" with title %S", title);
		PRINT("\n");
	}
	md_link_dictionary_entry *link_ref = CREATE(md_link_dictionary_entry);
	link_ref->destination = Str::duplicate(destination);
	link_ref->title = Str::duplicate(title);			
	if (Dictionaries::find(dict->dict, label) == NULL) {
		dict_entry *de = Dictionaries::create(dict->dict, label);
		if (de) de->value = link_ref;
	}
}

@ And here we query the dictionary, returning either the entry or |NULL|
if it isn't there.

=
md_link_dictionary_entry *Markdown::look_up(md_links_dictionary *dict, text_stream *label) {
	if (Str::is_whitespace(label)) return NULL;
	if (Str::len(label) > 999) return NULL;
	if (tracing_Markdown_parser) PRINT("Looking up reference '%S' -> ", label);
	Markdown::normalise_link_label(label);
	if (tracing_Markdown_parser) PRINT("'%S'\n", label);
	dict_entry *de = Dictionaries::find(dict->dict, label);
	if (de) return (md_link_dictionary_entry *) Dictionaries::value_for_entry(de);
	return NULL;
}

@ Labels are not matched literally: that would be too easy. CommonMark:

"One label matches another just in case their normalized forms are equal. To
normalize a label, strip off the opening and closing brackets, perform the
Unicode case fold, strip leading and trailing spaces, tabs, and line endings,
and collapse consecutive internal spaces, tabs, and line endings to a single
space."

=
void Markdown::normalise_link_label(text_stream *label) {
	TEMPORARY_TEXT(normal)
	for (int i=0, ws = FALSE; i<Str::len(label); i++) {
		wchar_t c = Str::get_at(label, i);
		if ((c == ' ') || (c == '\t') || (c == '\n')) {
			ws = TRUE; continue;
		} else if (ws) {
			PUT_TO(normal, ' ');
		}
		ws = FALSE;
		wchar_t F[4];
		Characters::full_Unicode_fold(c, F);
		for (int j=0; j<4; j++) if (F[j]) PUT_TO(normal, F[j]);
	}
	Str::clear(label); WRITE_TO(label, "%S", normal);
	DISCARD_TEXT(normal)
}

@h Debugging.
This prints the internal tree representation of Markdown: none of this code
is needed either for parsing or rendering.

=
void Markdown::debug_char(OUTPUT_STREAM, wchar_t c) {
	switch (c) {
		case 0:    WRITE("NULL"); break;
		case '\n': WRITE("NEWLINE"); break;
		case '\t': WRITE("TAB"); break;
		case ' ':  WRITE("SPACE"); break;
		case 0xA0: WRITE("NONBREAKING-SPACE"); break;
		default:   WRITE("'%c'", c); break;
	}
}

void Markdown::debug_char_briefly(OUTPUT_STREAM, wchar_t c) {
	switch (c) {
		case 0:    WRITE("\\x0000"); break;
		case '\n': WRITE("\\n"); break;
		case '\t': WRITE("\\t"); break;
		case '\\': WRITE("\\\\"); break;
		default:   WRITE("%c", c); break;
	}
}

void Markdown::debug_pos(OUTPUT_STREAM, md_charpos A) {
	if (Markdown::somewhere(A) == FALSE) { WRITE("{nowhere}"); return; }
	WRITE("{");
	Markdown::debug_item(OUT, A.md);
	WRITE(" at %d = ", A.at);
	Markdown::debug_char(OUT, Markdown::get(A));
	WRITE("}");
}

void Markdown::debug_interval(OUTPUT_STREAM, md_charpos A, md_charpos B) {
	if (Markdown::somewhere(A) == FALSE) { WRITE("NONE\n"); return; }
	WRITE("[");
	Markdown::debug_pos(OUT, A);
	WRITE("...");
	Markdown::debug_pos(OUT, B);
	WRITE(" - ");
	for (md_charpos pos = A; Markdown::somewhere(pos); pos = Markdown::advance(pos)) {
		Markdown::debug_char(OUT, Markdown::get(pos));
		if (Markdown::pos_eq(pos, B)) break;
		WRITE(",");
	}
	WRITE("]\n");
}

void Markdown::debug_item(OUTPUT_STREAM, markdown_item *md) {
	if (md == NULL) { WRITE("<no-item>"); return; }
	if (md->open == TRUE) WRITE("*");
	if (md->open == FALSE) WRITE(".");
	WRITE("%S-", Markdown::item_type_name(md->type));
	WRITE("M%d", md->id);
	if (md->copied_from) WRITE("<-M%d", md->copied_from->id);
	if (md->sliced_from) {
		WRITE("(%d = '", md->from);
		for (int i = md->from; i <= md->to; i++) {
			Markdown::debug_char_briefly(OUT, Str::get_at(md->sliced_from, i));
		}
		WRITE("' = %d", md->to);
		WRITE(")");
	} else if (Str::len(md->stashed) > 0) {
		WRITE(" = (", md->from);
		for (int i=0; i<Str::len(md->stashed); i++)
			Markdown::debug_char_briefly(OUT, Str::get_at(md->stashed, i));
		WRITE(")");
	}
	if (md->whitespace_follows) WRITE("+ws");
}

@h Trees and chains.
This rather defensively-written code is to print a tree or chain which may be
ill-founded or otherwise damaged. That should never happen, but if things which
should never happen never happened, we wouldn't need to debug.

=
int md_db_cycle_count = 1;

void Markdown::debug_subtree(OUTPUT_STREAM, markdown_item *md) {
	md_db_cycle_count++;
	Markdown::debug_item_r(OUT, md);
}

void Markdown::debug_chain(OUTPUT_STREAM, markdown_item *md) {
	Markdown::debug_chain_label(OUT, md, I"CHAIN");
}

void Markdown::debug_chain_label(OUTPUT_STREAM, markdown_item *md, text_stream *label) {
	md_db_cycle_count++;
	WRITE("%S:\n", label);
	INDENT;
	if (md)
		for (; md; md = md->next) {
			WRITE(" -> ");
			Markdown::debug_item_r(OUT, md);
		}
	else
		WRITE("<none>\n");
	OUTDENT;
}

@ Both of which recursively use:

=
void Markdown::debug_item_r(OUTPUT_STREAM, markdown_item *md) {
	if (md) {
		Markdown::debug_item(OUT, md);
		if (md->cycle_count == md_db_cycle_count) {
			WRITE("AGAIN!\n");
		} else {
			md->cycle_count = md_db_cycle_count;
			WRITE("\n");
			INDENT;
			for (markdown_item *c = md->down; c; c = c->next)
				Markdown::debug_item_r(OUT, c);
			OUTDENT;
		}
	}
}