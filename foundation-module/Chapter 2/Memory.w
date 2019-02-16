[Memory::] Memory.

To allocate memory suitable for the dynamic creation of objects
of different sizes, placing some larger objects automatically into doubly
linked lists and assigning each a unique allocation ID number.

@h Memory manager.
This allocates memory as needed to store the numerous "objects" of different
sizes, all C structures. There's no garbage collection because nothing is ever
destroyed. Each type has its own doubly-linked list, and in each type the
objects created are given unique IDs (within that type) counting upwards
from 0. These IDs will be unique across all threads.

@ Before going much further, we will need to anticipate what the memory
manager wants.  An "object" is a copy in memory of a C |struct|; thus,
a plain |int| is not an object. The memory manager can only deal with
a given type of |struct| if it contains three special elements, and we
define those using a macro. Thus, if the user wants to allocate larger
structures of type |thingummy|, then it needs to be defined like so:

	|typedef struct thingummy {|
	|    int whatsit;|
	|    struct text_stream *doobrey;|
	|    ...|
	|    MEMORY_MANAGEMENT|
	|}|

The caveat about "larger structures" is that smaller objects can instead be
stored in arrays, to reduce memory and speed overheads. Their structure
declarations do not include the following macro; they do not have unique
IDs; and they cannot be iterated over.

@d MEMORY_MANAGEMENT
	int allocation_id; /* Numbered from 0 upwards in creation order */
	void *next_structure; /* Next object in double-linked list */
	void *prev_structure; /* Previous object in double-linked list */

@ It is also necessary to define a constant in the following enumeration
family: for |thingummy|, it would be |thingummy_MT|. Had it been a smaller
object, it would have been |thingummy_array_MT| instead.

There is no significance to the order in which structures are registered
with the memory system. The ones here are those needed by Foundation.

@e filename_MT from 0
@e pathname_MT
@e string_storage_area_MT
@e scan_directory_MT
@e ebook_MT
@e ebook_datum_MT
@e ebook_volume_MT
@e ebook_chapter_MT
@e ebook_page_MT
@e ebook_image_MT
@e HTML_file_state_MT
@e HTML_tag_array_MT
@e text_stream_array_MT
@e command_line_switch_MT
@e dictionary_MT
@e dict_entry_array_MT
@e debugging_aspect_MT
@e linked_list_MT
@e linked_list_item_array_MT
@e match_avinue_array_MT
@e match_trie_array_MT
@e method_MT
@e method_set_MT
@e ebook_mark_MT

@ For each type of object to be allocated, a single structure of the
following design is maintained. Types which are allocated individually,
like world objects, have |no_allocated_together| set to 1, and the doubly
linked list is of the objects themselves. For types allocated in small
arrays (typically of 100 objects at a time), |no_allocated_together| is set
to the number of objects in each completed array (so, typically 100) and
the doubly linked list is of the arrays.

=
typedef struct allocation_status_structure {
	/* actually needed for allocation purposes: */
	int objects_allocated; /* total number of objects (or arrays) ever allocated */
	void *first_in_memory; /* head of doubly linked list */
	void *last_in_memory; /* tail of doubly linked list */

	/* used only to provide statistics for the debugging log: */
	char *name_of_type; /* e.g., |"lexicon_entry_MT"| */
	int bytes_allocated; /* total allocation for this type of object, not counting overhead */
	int objects_count; /* total number currently in existence (i.e., undeleted) */
	int no_allocated_together; /* number of objects in each array of this type of object */
} allocation_status_structure;

@ The memory allocator itself needs some memory, but only a fixed-size and
fairly small array of the structures defined above. The allocator can safely
begin as soon as this is initialised.

=
allocation_status_structure alloc_status[NO_DEFINED_MT_VALUES];

void Memory::start(void) {
	for (int i=0; i<NO_DEFINED_MT_VALUES; i++) {
		alloc_status[i].first_in_memory = NULL;
		alloc_status[i].last_in_memory = NULL;
		alloc_status[i].objects_allocated = 0;
		alloc_status[i].objects_count = 0;
		alloc_status[i].bytes_allocated = 0;
		alloc_status[i].no_allocated_together = 1;
		alloc_status[i].name_of_type = "unused";
	}
	Memory::name_fundamental_reasons();
}

@h Architecture.
The memory manager is built in three levels, with its interface to the user
being entirely at level 3 (except that when it shuts down it calls a level 1
routine to free everything). Each level uses the one below it.

(3) Managing linked lists of large objects, within which objects can be
created at any point, and from which objects can be deleted; and providing
a way to create new small objects of any given type.
(2) Allocating some thousands of memory frames, each holding one large object
or an array of small objects.
(1) Allocating and freeing a few dozen large blocks of contiguous memory.

@h Level 1: memory blocks.
Memory is allocated in blocks within which objects are allocated as
needed. The "safety margin" is the number of spare bytes left blank at the
end of each object: this is done because we want to be paranoid about
compilers on different architectures aligning structures to different
boundaries (multiples of 4, 8, 16, etc.). Each block also ends with a
firebreak of zeroes, which ought never to be touched: we want to minimise the
chance of a mistake causing a memory exception which crashes the compiler,
because if that happens it will be difficult to recover the circumstances from
the debugging log.

@d SAFETY_MARGIN 128
@d BLANK_END_SIZE 256

@ At present |MEMORY_GRANULARITY| is 800K. This is the quantity of memory
allocated by each individual |malloc| call.

After |MAX_BLOCKS_ALLOWED| blocks, we throw in the towel: we must have
fallen into an endless loop which creates endless new objects somewhere.
(If this ever happens, it would be a bug: the point of this mechanism is to
be able to recover. Without this safety measure, OS X in particular would
grind slowly to a halt, never refusing a |malloc|, until the user was
unable to get the GUI responsive enough to kill the process.)

@d MAX_BLOCKS_ALLOWED 15000
@d MEMORY_GRANULARITY 100*1024*8 /* which must be divisible by 1024 */

=
int no_blocks_allocated = 0;
int total_objects_allocated = 0; /* a potentially larger number, used only for the debugging log */

@ Memory blocks are stored in a linked list, and we keep track of the
size of the current block: that is, the block at the tail of the list.
Each memory block consists of a header structure, followed by |SAFETY_MARGIN|
null bytes, followed by actual data.

=
typedef struct memblock_header {
	int block_number;
	struct memblock_header *next;
	char *the_memory;
} memblock_header;

@ =
memblock_header *first_memblock_header = NULL; /* head of list of memory blocks */
memblock_header *current_memblock_header = NULL; /* tail of list of memory blocks */

int used_in_current_memblock = 0; /* number of bytes so far used in the tail memory block */

@ The actual allocation and deallocation is performed by the following
pair of routines.

=
void Memory::allocate_another_block(void) {
	unsigned char *cp;
	memblock_header *mh;

	@<Allocate and zero out a block of memory, making cp point to it@>;

	mh = (memblock_header *) cp;
	used_in_current_memblock = sizeof(memblock_header) + SAFETY_MARGIN;
	mh->the_memory = (void *) (cp + used_in_current_memblock);

	@<Add new block to the tail of the list of memory blocks@>;
}

@ Note that |cp| and |mh| are set to the same value: they merely have different
pointer types as far as the C compiler is concerned.

@<Allocate and zero out a block of memory, making cp point to it@> =
	int i;
	if (no_blocks_allocated++ >= MAX_BLOCKS_ALLOWED)
		Errors::fatal(
			"the memory manager has halted inweb, which seems to be generating "
			"endless structures. Presumably it is trapped in a loop");
	Memory::check_memory_integrity();
	cp = (unsigned char *) (Memory::paranoid_calloc(MEMORY_GRANULARITY, 1));
	if (cp == NULL) Errors::fatal("Run out of memory: malloc failed");
	for (i=0; i<MEMORY_GRANULARITY; i++) cp[i] = 0;

@ As can be seen, memory block numbers count upwards from 0 in order of
their allocation.

@<Add new block to the tail of the list of memory blocks@> =
	if (current_memblock_header == NULL) {
		mh->block_number = 0;
		first_memblock_header = mh;
	} else {
		mh->block_number = current_memblock_header->block_number + 1;
		current_memblock_header->next = mh;
	}
	current_memblock_header = mh;

@ Freeing all this memory again is just a matter of freeing each block
in turn, but of course being careful to avoid following links in a just-freed
block.

=
void Memory::free(void) {
	Memory::free_ssas();
	memblock_header *mh = first_memblock_header;
	while (mh != NULL) {
		memblock_header *next_mh = mh->next;
		void *p = (void *) mh;
		free(p);
		mh = next_mh;
	}
}

@h Level 2: memory frames and integrity checking.
Within these extensive blocks of contiguous memory, we place the actual
objects in between "memory frames", which are only used at present to police
the integrity of memory: again, finding obscure and irritating memory-corruption
bugs is more important to us than saving bytes. Each memory frame wraps either
a single large object, or a single array of small objects.

@d INTEGRITY_NUMBER 0x12345678 /* a value unlikely to be in memory just by chance */

=
typedef struct memory_frame {
	int integrity_check; /* this should always contain the |INTEGRITY_NUMBER| */
	struct memory_frame *next_frame; /* next frame in the list of memory frames */
	int mem_type; /* type of object stored in this frame */
	int allocation_id; /* allocation ID number of object stored in this frame */
} memory_frame;

@ There is a single linked list of all the memory frames, perhaps of about
10000 entries in length, beginning here. (These frames live in different memory
blocks, but we don't need to worry about that.)

=
memory_frame *first_memory_frame = NULL; /* earliest memory frame ever allocated */
memory_frame *last_memory_frame = NULL;  /* most recent memory frame allocated */

@ If the integrity numbers of every frame are still intact, then it is pretty
unlikely that any bug has caused memory to overwrite one frame into another.
|Memory::check_memory_integrity| might on very large runs be run often, if we didn't
prevent this: since the number of calls would be roughly proportional to
memory usage, we would implicitly have an $O(n^2)$ running time in the
amount of storage $n$ allocated.

=
int calls_to_cmi = 0;
void Memory::check_memory_integrity(void) {
	int c;
	memory_frame *mf;
	c = calls_to_cmi++;
	if (!((c<10) || (c == 100) || (c == 1000) || (c == 10000))) return;

	for (c = 0, mf = first_memory_frame; mf; c++, mf = mf->next_frame)
		if (mf->integrity_check != INTEGRITY_NUMBER)
			Errors::fatal("Memory manager failed integrity check");
}

void Memory::debug_memory_frames(int from, int to) {
	int c;
	memory_frame *mf;
	for (c = 0, mf = first_memory_frame; (mf) && (c <= to); c++, mf = mf->next_frame)
		if (c >= from) {
			char *desc = "corrupt";
			if (mf->integrity_check == INTEGRITY_NUMBER)
				desc = alloc_status[mf->mem_type].name_of_type;
		}
}

@ We have seen how memory is allocated in large blocks, and that a linked
list of memory frames will live inside those blocks; we have seen how the
list is checked for integrity; but we not seen how it is built. Every
memory frame is created by the following function:

=
void *Memory::allocate(int mem_type, int extent) {
	CREATE_MUTEX(mutex);
	LOCK_MUTEX(mutex);

	unsigned char *cp;
	memory_frame *mf;
	int bytes_free_in_current_memblock, extent_without_overheads = extent;

	extent += sizeof(memory_frame); /* each allocation is preceded by a memory frame */
	extent += SAFETY_MARGIN; /* each allocation is followed by |SAFETY_MARGIN| null bytes */

	@<Ensure that the current memory block has room for this many bytes@>;

	cp = ((unsigned char *) (current_memblock_header->the_memory)) + used_in_current_memblock;
	used_in_current_memblock += extent;

	mf = (memory_frame *) cp; /* the new memory frame, */
	cp = cp + sizeof(memory_frame); /* following which is the actual allocated data */

	mf->integrity_check = INTEGRITY_NUMBER;
	mf->allocation_id = alloc_status[mem_type].objects_allocated;
	mf->mem_type = mem_type;

	@<Add the new memory frame to the big linked list of all frames@>;
	@<Update the allocation status for this type of object@>;

	total_objects_allocated++;

	UNLOCK_MUTEX(mutex);
	return (void *) cp;
}

@ The granularity error below will be triggered the first time a particular
object type is allocated. So this is not a potential time-bomb just waiting
for a user with a particularly long and involved source text to discover.

@<Ensure that the current memory block has room for this many bytes@> =
	if (current_memblock_header == NULL) Memory::allocate_another_block();
	bytes_free_in_current_memblock = MEMORY_GRANULARITY - (used_in_current_memblock + extent);
	if (bytes_free_in_current_memblock < BLANK_END_SIZE) {
		Memory::allocate_another_block();
		if (extent+BLANK_END_SIZE >= MEMORY_GRANULARITY)
			Errors::fatal("Memory manager failed because granularity too low");
	}

@ New memory frames are added to the tail of the list:

@<Add the new memory frame to the big linked list of all frames@> =
	mf->next_frame = NULL;
	if (first_memory_frame == NULL) first_memory_frame = mf;
	else last_memory_frame->next_frame = mf;
	last_memory_frame = mf;

@ See the definition of |alloc_status| above.

@<Update the allocation status for this type of object@> =
	if (alloc_status[mem_type].first_in_memory == NULL)
		alloc_status[mem_type].first_in_memory = (void *) cp;
	alloc_status[mem_type].last_in_memory = (void *) cp;
	alloc_status[mem_type].objects_allocated++;
	alloc_status[mem_type].bytes_allocated += extent_without_overheads;

@h Level 3: managing linked lists of allocated objects.
We define macros which look as if they are functions, but for which one
argument is the name of a type: expanding these macros provides suitable C
functions to handle each possible type. These macros provide the interface
through which all other sections allocate and leaf through memory.

Note that Inweb allows multi-line macro definitions without backslashes
to continue them, unlike ordinary C. Otherwise these are "standard"
macros, though this was my first brush with the |##| concatenation
operator: basically |CREATE(thing)| expands into |(allocate_thing())|
because of the |##|. (See Kernighan and Ritchie, section 4.11.2.)

@d CREATE(type_name) (allocate_##type_name())
@d COPY(to, from, type_name) (copy_##type_name(to, from))
@d CREATE_BEFORE(existing, type_name) (allocate_##type_name##_before(existing))
@d DESTROY(this, type_name) (deallocate_##type_name(this))
@d FIRST_OBJECT(type_name) ((type_name *) alloc_status[type_name##_MT].first_in_memory)
@d LAST_OBJECT(type_name) ((type_name *) alloc_status[type_name##_MT].last_in_memory)
@d NEXT_OBJECT(this, type_name) ((type_name *) (this->next_structure))
@d PREV_OBJECT(this, type_name) ((type_name *) (this->prev_structure))
@d NUMBER_CREATED(type_name) (alloc_status[type_name##_MT].objects_count)

@ The following macros are widely used (well, the first one is, anyway)
for looking through the double linked list of existing objects of a
given type.

@d LOOP_OVER(var, type_name)
	for (var=FIRST_OBJECT(type_name); var != NULL; var = NEXT_OBJECT(var, type_name))
@d LOOP_BACKWARDS_OVER(var, type_name)
	for (var=LAST_OBJECT(type_name); var != NULL; var = PREV_OBJECT(var, type_name))

@h Allocator functions created by macros.
The following macros generate a family of systematically named functions.
For instance, we shall shortly expand |ALLOCATE_INDIVIDUALLY(parse_node)|,
which will expand to three functions: |allocate_parse_node|,
|deallocate_parse_node| and |allocate_parse_node_before|.

Quaintly, |#type_name| expands into the value of |type_name| put within
double-quotes.

@d NEW_OBJECT(type_name) ((type_name *) Memory::allocate(type_name##_MT, sizeof(type_name)))

@d ALLOCATE_INDIVIDUALLY(type_name)
MAKE_REFERENCE_ROUTINES(type_name, type_name##_MT)
type_name *allocate_##type_name(void) {
	CREATE_MUTEX(mutex);
	LOCK_MUTEX(mutex);
	alloc_status[type_name##_MT].name_of_type = #type_name;
	type_name *prev_obj = LAST_OBJECT(type_name);
	type_name *new_obj = NEW_OBJECT(type_name);
	new_obj->allocation_id = alloc_status[type_name##_MT].objects_allocated-1;
	new_obj->next_structure = NULL;
	if (prev_obj != NULL)
		prev_obj->next_structure = (void *) new_obj;
	new_obj->prev_structure = prev_obj;
	alloc_status[type_name##_MT].objects_count++;
	UNLOCK_MUTEX(mutex);
	return new_obj;
}
void deallocate_##type_name(type_name *kill_me) {
	CREATE_MUTEX(mutex);
	LOCK_MUTEX(mutex);
	type_name *prev_obj = PREV_OBJECT(kill_me, type_name);
	type_name *next_obj = NEXT_OBJECT(kill_me, type_name);
	if (prev_obj == NULL) {
		alloc_status[type_name##_MT].first_in_memory = next_obj;
	} else {
		prev_obj->next_structure = next_obj;
	}
	if (next_obj == NULL) {
		alloc_status[type_name##_MT].last_in_memory = prev_obj;
	} else {
		next_obj->prev_structure = prev_obj;
	}
	alloc_status[type_name##_MT].objects_count--;
	UNLOCK_MUTEX(mutex);
}
type_name *allocate_##type_name##_before(type_name *existing) {
	CREATE_MUTEX(mutex);
	LOCK_MUTEX(mutex);
	type_name *new_obj = allocate_##type_name();
	deallocate_##type_name(new_obj);
	new_obj->prev_structure = existing->prev_structure;
	if (existing->prev_structure != NULL)
		((type_name *) existing->prev_structure)->next_structure = new_obj;
	else alloc_status[type_name##_MT].first_in_memory = (void *) new_obj;
	new_obj->next_structure = existing;
	existing->prev_structure = new_obj;
	alloc_status[type_name##_MT].objects_count++;
	UNLOCK_MUTEX(mutex);
	return new_obj;
}
void copy_##type_name(type_name *to, type_name *from) {
	CREATE_MUTEX(mutex);
	LOCK_MUTEX(mutex);
	type_name *prev_obj = to->prev_structure;
	type_name *next_obj = to->next_structure;
	int aid = to->allocation_id;
	*to = *from;
	to->allocation_id = aid;
	to->next_structure = next_obj;
	to->prev_structure = prev_obj;
	UNLOCK_MUTEX(mutex);
}

@ |ALLOCATE_IN_ARRAYS| is still more obfuscated. When we
|ALLOCATE_IN_ARRAYS(X, 100)|, the result will be definitions of a new type
|X_block| and functions |allocate_X|, |allocate_X_block|,
|deallocate_X_block| and |allocate_X_block_before| (though the last is not
destined ever to be used). Note that we are not provided with the means to
deallocate individual objects this time: that's the trade-off for
allocating in blocks.

@d ALLOCATE_IN_ARRAYS(type_name, NO_TO_ALLOCATE_TOGETHER)
MAKE_REFERENCE_ROUTINES(type_name, type_name##_array_MT)
typedef struct type_name##_array {
	int used;
	struct type_name array[NO_TO_ALLOCATE_TOGETHER];
	MEMORY_MANAGEMENT
} type_name##_array;
ALLOCATE_INDIVIDUALLY(type_name##_array)
type_name##_array *next_##type_name##_array = NULL;
struct type_name *allocate_##type_name(void) {
	CREATE_MUTEX(mutex);
	LOCK_MUTEX(mutex);
	if ((next_##type_name##_array == NULL) ||
		(next_##type_name##_array->used >= NO_TO_ALLOCATE_TOGETHER)) {
		alloc_status[type_name##_array_MT].no_allocated_together = NO_TO_ALLOCATE_TOGETHER;
		next_##type_name##_array = allocate_##type_name##_array();
		next_##type_name##_array->used = 0;
	}
	UNLOCK_MUTEX(mutex);
	return &(next_##type_name##_array->array[
		next_##type_name##_array->used++]);
}

@h Expanding many macros.
Each given structure must have a typedef name, say |marvel|, and can be
used in one of two ways. Either way, we can obtain a new one with the macro
|CREATE(marvel)|.

Either (a) it will be individually allocated. In this case |marvel_MT|
should be defined with a new MT (memory type) number, and the macro
|ALLOCATE_INDIVIDUALLY(marvel)| should be expanded. The first and last
objects created will be |FIRST_OBJECT(marvel)| and |LAST_OBJECT(marvel)|,
and we can proceed either way through a double linked list of them with
|PREV_OBJECT(mv, marvel)| and |NEXT_OBJECT(mv, marvel)|. For convenience,
we can loop through marvels, in creation order, using |LOOP_OVER(var,
marvel)|, which expands to a |for| loop in which the variable |var| runs
through each created marvel in turn; or equally we can run backwards
through using |LOOP_BACKWARDS_OVER(var, marvel)|. In addition, there are
corruption checks to protect the memory from overrunning accidents, and the
structure can be used as a value in the symbols table. Good for large
structures with significant semantic content.

Or (b) it will be allocated in arrays. Once again we can obtain new marvels
with |CREATE(marvel)|. This is more efficient both in speed and memory
usage, but we lose the ability to loop through the objects. For this
arrangement, define |marvel_array_MT| with a new MT number and expand the
macro |ALLOCATE_IN_ARRAYS(marvel, 100)|, where 100 (or what may you) is the
number of objects allocated jointly as a block. Good for small structures
used in the lower levels.

Here goes, then.

=
ALLOCATE_INDIVIDUALLY(filename)
ALLOCATE_INDIVIDUALLY(pathname)
ALLOCATE_INDIVIDUALLY(string_storage_area)
ALLOCATE_INDIVIDUALLY(scan_directory)
ALLOCATE_INDIVIDUALLY(ebook)
ALLOCATE_INDIVIDUALLY(ebook_datum)
ALLOCATE_INDIVIDUALLY(ebook_volume)
ALLOCATE_INDIVIDUALLY(ebook_chapter)
ALLOCATE_INDIVIDUALLY(ebook_page)
ALLOCATE_INDIVIDUALLY(ebook_image)
ALLOCATE_INDIVIDUALLY(HTML_file_state)
ALLOCATE_INDIVIDUALLY(command_line_switch)
ALLOCATE_INDIVIDUALLY(dictionary)
ALLOCATE_INDIVIDUALLY(debugging_aspect)
ALLOCATE_INDIVIDUALLY(linked_list)
ALLOCATE_INDIVIDUALLY(method)
ALLOCATE_INDIVIDUALLY(method_set)
ALLOCATE_INDIVIDUALLY(ebook_mark)

ALLOCATE_IN_ARRAYS(dict_entry, 100)
ALLOCATE_IN_ARRAYS(HTML_tag, 1000)
ALLOCATE_IN_ARRAYS(linked_list_item, 1000)
ALLOCATE_IN_ARRAYS(match_avinue, 1000)
ALLOCATE_IN_ARRAYS(match_trie, 1000)
ALLOCATE_IN_ARRAYS(text_stream, 100)

@h Simple memory allocations.
Not all of our memory will be claimed in the form of structures: now and then
we need to use the equivalent of traditional |malloc| and |calloc| routines.

@e STREAM_MREASON from 0
@e FILENAME_STORAGE_MREASON
@e STRING_STORAGE_MREASON
@e DICTIONARY_MREASON
@e CLS_SORTING_MREASON

=
void Memory::name_fundamental_reasons(void) {
	Memory::reason_name(STREAM_MREASON, "text stream storage");
	Memory::reason_name(FILENAME_STORAGE_MREASON, "filename/pathname storage");
	Memory::reason_name(STRING_STORAGE_MREASON, "string storage");
	Memory::reason_name(DICTIONARY_MREASON, "dictionary storage");
	Memory::reason_name(CLS_SORTING_MREASON, "sorting");
}

@ And here is the (very simple) implementation.

=
char *memory_needs[NO_DEFINED_MREASON_VALUES];

void Memory::reason_name(int r, char *reason) {
	if ((r < 0) || (r >= NO_DEFINED_MREASON_VALUES)) internal_error("MR out of range");
	memory_needs[r] = reason;
}

char *Memory::description_of_reason(int r) {
	if ((r < 0) || (r >= NO_DEFINED_MREASON_VALUES)) internal_error("MR out of range");
	return memory_needs[r];
}

@ We keep some statistics on this. The value for "memory claimed" is the
net amount of memory currently owned, which is increased when we allocate
it and decreased when we free it. Whether the host OS is able to make
efficient use of the memory we free, we can't know, but it probably is, and
therefore the best estimate of how well we're doing is the "maximum memory
claimed" -- the highest recorded net usage count over the run.

=
int max_memory_at_once_for_each_need[NO_DEFINED_MREASON_VALUES],
	memory_claimed_for_each_need[NO_DEFINED_MREASON_VALUES],
	number_of_claims_for_each_need[NO_DEFINED_MREASON_VALUES];
int total_claimed_simply = 0;

@ Our allocation routines behave just like the standard C library's |malloc|
and |calloc|, but where a third argument supplies a reason why the memory is
needed, and where any failure to allocate memory is tidily dealt with. We will
exit on any such failure, so that the caller can be certain that the return
values of these functions are always non-|NULL| pointers.

=
void *Memory::I7_calloc(int how_many, int size_in_bytes, int reason) {
	return Memory::I7_alloc(how_many, size_in_bytes, reason);
}
void *Memory::I7_malloc(int size_in_bytes, int reason) {
	return Memory::I7_alloc(-1, size_in_bytes, reason);
}

@ And this, then, is the joint routine implementing both.

=
void *Memory::I7_alloc(int N, int S, int R) {
	CREATE_MUTEX(mutex);
	LOCK_MUTEX(mutex);
	void *pointer;
	int bytes_needed;
	if ((R < 0) || (R >= NO_DEFINED_MREASON_VALUES)) internal_error("no such memory reason");
	if (total_claimed_simply == 0) @<Zero out the statistics on simple memory allocations@>;
	@<Claim the memory using malloc or calloc as appropriate@>;
	@<Update the statistics on simple memory allocations@>;
	UNLOCK_MUTEX(mutex);
	return pointer;
}

@ I am nervous about assuming that |calloc(0, X)| returns a non-|NULL| pointer
in all implementations of the standard C library, so the case when |N| is zero
allocates a tiny but positive amount of memory, just to be safe.

@<Claim the memory using malloc or calloc as appropriate@> =
	if (N > 0) {
		pointer = Memory::paranoid_calloc((size_t) N, (size_t) S);
		bytes_needed = N*S;
	} else {
		pointer = Memory::paranoid_calloc(1, (size_t) S);
		bytes_needed = S;
	}
	if (pointer == NULL) {
		Errors::fatal_with_C_string("Out of memory for %s", Memory::description_of_reason(R));
	}

@ These statistics have no function except to improve the diagnostics in the
debugging log, but they are very cheap to keep, since |Memory::I7_alloc| is called only
rarely and to allocate large blocks of memory.

@<Zero out the statistics on simple memory allocations@> =
	int i;
	for (i=0; i<NO_DEFINED_MREASON_VALUES; i++) {
		max_memory_at_once_for_each_need[i] = 0;
		memory_claimed_for_each_need[i] = 0;
		number_of_claims_for_each_need[i] = 0;
	}

@<Update the statistics on simple memory allocations@> =
	memory_claimed_for_each_need[R] += bytes_needed;
	total_claimed_simply += bytes_needed;
	number_of_claims_for_each_need[R]++;
	if (memory_claimed_for_each_need[R] > max_memory_at_once_for_each_need[R])
		max_memory_at_once_for_each_need[R] = memory_claimed_for_each_need[R];

@ We also provide our own wrapper for |free|:

=
void Memory::I7_free(void *pointer, int R, int bytes_freed) {
	if ((R < 0) || (R >= NO_DEFINED_MREASON_VALUES)) internal_error("no such memory reason");
	if (pointer == NULL) internal_error("can't free NULL memory");
	CREATE_MUTEX(mutex);
	LOCK_MUTEX(mutex);
	memory_claimed_for_each_need[R] -= bytes_freed;
	free(pointer);
	UNLOCK_MUTEX(mutex);
}

void Memory::I7_array_free(void *pointer, int R, int num_cells, size_t cell_size) {
	Memory::I7_free(pointer, R, num_cells*((int) cell_size));
}

@h Text storage.
We will also use much simpler memory areas for text, in 64K chunks:

@d SSA_CAPACITY 64*1024

=
typedef struct string_storage_area {
	char *storage_at;
	int first_free_byte;
	MEMORY_MANAGEMENT
} string_storage_area;

string_storage_area *current_ssa = NULL;

@ The following is ideal for parking a read-only string of text somewhere
safe in memory. Since the length can't be extended, it's usually unsafe
to write to the result.

=
char *Memory::new_string(char *from) {
	CREATE_MUTEX(mutex);
	LOCK_MUTEX(mutex);
	int length_needed = (int) strlen(from) + 1;
	if (!((current_ssa) &&
		(current_ssa->first_free_byte + length_needed < SSA_CAPACITY))) {
		current_ssa = CREATE(string_storage_area);
		current_ssa->storage_at = Memory::I7_malloc(SSA_CAPACITY, STRING_STORAGE_MREASON);
		current_ssa->first_free_byte = 0;
	}
	char *rp = current_ssa->storage_at + current_ssa->first_free_byte;
	current_ssa->first_free_byte += length_needed;
	strcpy(rp, from);
	UNLOCK_MUTEX(mutex);
	return rp;
}

@ And here we free any SSAs needed in the course of the run.

=
void Memory::free_ssas(void) {
	string_storage_area *ssa;
	LOOP_OVER(ssa, string_storage_area)
		Memory::I7_free(ssa->storage_at, STRING_STORAGE_MREASON, SSA_CAPACITY);
}

@ And the following provides statistics, and a mini-report, for the memory
report in the debugging log (for which, see below).

=
int Memory::log_usage(int total) {
	if (total_claimed_simply == 0) return 0;
	int i, t = 0;
	for (i=0; i<NO_DEFINED_MREASON_VALUES; i++) {
		t += max_memory_at_once_for_each_need[i];
		if (total > 0)
			LOG("0.%03d: %s - %d bytes in %d claim(s)\n",
				Memory::proportion(max_memory_at_once_for_each_need[i], total),
				Memory::description_of_reason(i),
				max_memory_at_once_for_each_need[i],
				number_of_claims_for_each_need[i]);
	}
	return t;
}

@h Memory usage report.
A small utility routine to help keep track of our unquestioned profligacy.

=
void Memory::log_statistics(void) {
	int total_for_objects = MEMORY_GRANULARITY*no_blocks_allocated; /* usage in bytes */
	int total_for_SMAs = Memory::log_usage(0); /* usage in bytes */
	int sorted_usage[NO_DEFINED_MT_VALUES]; /* memory type numbers, in usage order */
	int total = (total_for_objects + total_for_SMAs)/1024; /* total memory usage in KB */

	@<Sort the table of memory type usages into decreasing size order@>;

	int total_for_objects_used = 0; /* out of the |total_for_objects|, the bytes used */
	int total_objects = 0;
	@<Calculate the memory usage for objects@>;
	int overhead_for_objects = total_for_objects - total_for_objects_used; /* bytes wasted */
	@<Print the report to the debugging log@>;
}

@<Calculate the memory usage for objects@> =
	int i, j;
	for (j=0; j<NO_DEFINED_MT_VALUES; j++) {
		i = sorted_usage[j];
		if (alloc_status[i].objects_allocated != 0) {
			if (alloc_status[i].no_allocated_together == 1)
				total_objects += alloc_status[i].objects_allocated;
			else
				total_objects += alloc_status[i].objects_allocated*
									alloc_status[i].no_allocated_together;
			total_for_objects_used += alloc_status[i].bytes_allocated;
		}
	}

@ This is the criterion for sorting memory types in the report: descending
order of total number of bytes allocated.

@<Sort the table of memory type usages into decreasing size order@> =
	int i;
	for (i=0; i<NO_DEFINED_MT_VALUES; i++) sorted_usage[i] = i;
	qsort(sorted_usage, (size_t) NO_DEFINED_MT_VALUES, sizeof(int), Memory::compare_usage);

@ And here is the actual report:

@<Print the report to the debugging log@> =
	LOG("\nReport by memory manager:\n\n");
	LOG("Total consumption was %dK = %dMB, divided up in the following proportions:\n",
		total, (total+512)/1024);

	LOG("0.%03d: %d objects in %d frames in %d memory blocks (of %dK each):\n",
		Memory::proportion(total_for_objects, total),
		total_objects, total_objects_allocated, no_blocks_allocated, MEMORY_GRANULARITY/1024);
	LOG("    0.%03d: memory manager overhead - %d bytes\n",
		Memory::proportion(overhead_for_objects, total), overhead_for_objects);
	int i, j;
	for (j=0; j<NO_DEFINED_MT_VALUES; j++) {
		i = sorted_usage[j];
		if (alloc_status[i].objects_allocated != 0) {
			LOG("    0.%03d: %s  -  ",
				Memory::proportion(alloc_status[i].bytes_allocated, total),
				alloc_status[i].name_of_type);
			if (alloc_status[i].no_allocated_together == 1) {
				LOG("%d ", alloc_status[i].objects_count);
				if (alloc_status[i].objects_count != alloc_status[i].objects_allocated)
					LOG("(+%d deleted) ",
						alloc_status[i].objects_allocated - alloc_status[i].objects_count);
			} else LOG("%d blocks of %d = %d ",
				alloc_status[i].objects_allocated, alloc_status[i].no_allocated_together,
				alloc_status[i].objects_allocated*alloc_status[i].no_allocated_together);
			LOG("objects, %d bytes\n", alloc_status[i].bytes_allocated);
		}
	}
	Memory::log_usage(total);

@ =
int Memory::compare_usage(const void *ent1, const void *ent2) {
	int ix1 = *((const int *) ent1);
	int ix2 = *((const int *) ent2);
	return alloc_status[ix2].bytes_allocated - alloc_status[ix1].bytes_allocated;
}

@ Finally, a little routine to compute the proportions of memory for each
usage. Recall that |bytes| is measured in bytes, but |total| in kilobytes.

=
int Memory::proportion(int bytes, int total) {
	float B = (float) bytes, T = (float) total;
	float P = (1000*B)/(1024*T);
	return (int) P;
}

@ =
void *Memory::paranoid_calloc(size_t N, size_t S) {
	CREATE_MUTEX(mutex);
	LOCK_MUTEX(mutex);
	void *P = calloc(N, S);
	UNLOCK_MUTEX(mutex);
	return P;
}

@h Run-time pointer type checking.
In several places Inform needs to store pointers of type |void *|, that is,
pointers which have no indication of what type of data they point to.
This is not type-safe and therefore offers plenty of opportunity for
blunders. The following provides run-time type checking to ensure that
each time we dereference a typeless pointer, it does indeed point to
a structure of the type we think it should.

The structure |general_pointer| holds a |void *| pointer to any one of the
following:

(a) |NULL|, to which we assign ID number $-1$;
(b) |char|, to which we assign ID number 1000;
(c) any individually allocated structure of the types listed above, to
which we assign the ID numbers used above: for instance, |blorb_figure_MT|
is the ID number for a |general_pointer| which points to a |blorb_figure|
structure.

@d NULL_GENERAL_POINTER (Memory::store_gp_null())
@d GENERAL_POINTER_IS_NULL(gp) (Memory::test_gp_null(gp))

=
typedef struct general_pointer {
	void *pointer_to_data;
	int run_time_type_code;
} general_pointer;

general_pointer Memory::store_gp_null(void) {
	general_pointer gp;
	gp.pointer_to_data = NULL;
	gp.run_time_type_code = -1; /* guaranteed to differ from all |_MT| values */
	return gp;
}
int Memory::test_gp_null(general_pointer gp) {
	if (gp.run_time_type_code == -1) return TRUE;
	return FALSE;
}

@ The symbols tables need to look at pointer values directly without knowing
their types, but only to test equality, so we abstract that thus. And the
debugging log also shows actual hexadecimal addresses to distinguish nameless
objects and to help with interpreting output from GDB, so we abstract that too.

@d COMPARE_GENERAL_POINTERS(gp1, gp2)
	(gp1.pointer_to_data == gp2.pointer_to_data)

@d GENERAL_POINTER_AS_INT(gp)
	((pointer_sized_int) gp.pointer_to_data)

@ If we have a pointer to |circus| (say) then |g=STORE_POINTER_circus(p)|
returns a |general_pointer| with |p| as the actual pointer, but will not
compile unless |p| is indeed of type |circus *|. When we later
|RETRIEVE_POINTER_circus(g)|, an internal error is thrown if |g| contains a pointer
which is other than |void *|, or which has never been referenced.

@d MAKE_REFERENCE_ROUTINES(type_name, id_code)
general_pointer STORE_POINTER_##type_name(type_name *data) {
	general_pointer gp;
	gp.pointer_to_data = (void *) data;
	gp.run_time_type_code = id_code;
	return gp;
}
type_name *RETRIEVE_POINTER_##type_name(general_pointer gp) {
	if (gp.run_time_type_code != id_code) {
		LOG("Wanted ID code %d, found %d\n", id_code, gp.run_time_type_code);
		internal_error("attempt to retrieve wrong pointer type as " #type_name);
	}
	return (type_name *) gp.pointer_to_data;
}
general_pointer PASS_POINTER_##type_name(general_pointer gp) {
	if (gp.run_time_type_code != id_code) {
		LOG("Wanted ID code %d, found %d\n", id_code, gp.run_time_type_code);
		internal_error("attempt to pass wrong pointer type as " #type_name);
	}
	return gp;
}
int VALID_POINTER_##type_name(general_pointer gp) {
	if (gp.run_time_type_code == id_code) return TRUE;
	return FALSE;
}

@ Suitable |MAKE_REFERENCE_ROUTINES| were expanded for all of the memory
allocated objects above; so that leaves only humble |char *| pointers:

=
MAKE_REFERENCE_ROUTINES(char, 1000)
