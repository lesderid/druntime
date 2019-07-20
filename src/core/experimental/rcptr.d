module core.experimental.rcptr;

import core.memory : pureCalloc, pureFree;
import core.atomic : atomicOp;

struct __rcptr(T)
{
    alias CounterType = uint;

    private T* ptr = null;
    private shared(CounterType)* count = null;

    this(T* ptr)
    {
        //TODO: Don't allocate count if ptr is null? assert(ptr !is null)?
        this.ptr = ptr;

        count = cast(typeof(count)) pureCalloc(1, CounterType.sizeof);
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
