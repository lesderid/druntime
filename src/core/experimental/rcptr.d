// Written in the D programming language.
/**
This module provides a shared pointer implementation with memory management
through reference counting.

License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).

Authors: Les De Ridder

Source: $(DRUNTIMESRC core/experimental/rcptr.d)
*/
module core.experimental.rcptr;

import core.memory : pureCalloc, pureFree;
import core.atomic : atomicOp;

/**
A reference counted shared pointer that can be used to implement reference
counted data structures.

The reference count is automatically incremented/decremented on assignment,
copy (construction), and destruction. When there are no more references to the
pointer, the reference count is automatically deallocated and the referenced
pointer is `free`d.

Implementation: The internal implementation of `__rcptr` uses `malloc`/`free`.
*/
struct __rcptr(T)
{
    alias CounterType = uint;

    private T* ptr = null;
    private shared(CounterType)* count = null;

    /**
    Creates a new `__rcptr` instance, tracking the provided pointer.

    This implies that the ownership of the pointer is transferred to
    `__rcptr`.

    Params:
         ptr = pointer to memory to be managed by `__rcptr`
    */
    this(T* ptr)
    {
        this.ptr = ptr;

        if (ptr !is null)
        {
            // We use `calloc` so we don't have to manually initialise count/addRef
            count = cast(typeof(count)) pureCalloc(1, CounterType.sizeof);
        }
    }

    void deallocate()
    {
        pureFree(ptr);
        pureFree(cast(CounterType*) count);
    }

    ~this()
    {
        delRef();
    }

    void opAssign(ref __rcptr!T rhs)
    {
        if (rhs.count == count)
        {
            return;
        }

        delRef();

        ptr = rhs.ptr;
        count = rhs.count;

        addRef();
    }

    this(ref __rcptr!T rhs)
    {
        ptr = rhs.ptr;
        count = rhs.count;

        addRef();
    }

    private void addRef()
    {
        if (ptr is null)
        {
            return;
        }

        atomicOp!"+="(*count, 1);
    }

    private void delRef()
    {
        if (ptr is null)
        {
            return;
        }

        // The counter is left at -1 when this was the last reference
        // (i.e. the counter is 0-based, because we use calloc)
        if (atomicOp!"-="(*count, 1) == -1)
        {
            deallocate();
        }
    }

    T* get()
    {
        return ptr;
    }
}

unittest
{
    import core.stdc.stdlib : calloc;

    auto allocInts = (size_t count) => cast(int*) calloc(count, int.sizeof);

    __rcptr!int a; //default ctor

    auto b = __rcptr!int(allocInts(10)); //ptr ctor

    {
        auto c = a; //copy ctor
        assert(c.get == a.get);
        assert(c.get != b.get);

        c = b; //opAssign
        assert(c.get != a.get);
        assert(c.get == b.get);
    }

    assert(a.count is null);
    assert(*b.count == 0);
}
