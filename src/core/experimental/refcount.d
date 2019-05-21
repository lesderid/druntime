module core.experimental.refcount;

struct _RefCount
{
    import core.atomic : atomicOp;

    alias CounterType = uint;
    private CounterType* rc = null;

    @nogc nothrow pure @safe scope
    bool isShared() const
    {
        // Faster than ((cast(size_t) rc) % 8) == 0;
        return !((cast(size_t) rc) & 7);
    }

    @nogc nothrow pure @trusted scope
    private CounterType rcOp(string op)(CounterType val) const
    {
        if (isShared())
        {
            return cast(CounterType)(atomicOp!op(*(cast(shared CounterType*) rc), val));
        }
        else
        {
            mixin("return cast(CounterType)(*(cast(CounterType*) rc)" ~ op ~ "val);");
        }
    }

    @nogc nothrow pure @trusted scope
    this(this Q)(int)
    {
        CounterType* support = cast(CounterType*) pureAllocate(2 * CounterType.sizeof);
        static if (is(Q == immutable))
        {
            *support = 0;
            rc = cast(immutable CounterType*) support;
        }
        else
        {
            *(support + 1) = 0;
            rc = cast(CounterType*) (support + 1);
        }
        addRef();
    }

    private enum copyCtorIncRef = q{
        rc = rhs.rc;
        assert(rc == rhs.rc);
        if (rhs.isInitialized())
        {
            assert(isShared() == rhs.isShared());
            addRef();
        }
    };

    @nogc nothrow pure @safe scope
    this(return scope ref typeof(this) rhs)
    {
        mixin(copyCtorIncRef);
    }

    // { Get a const obj
    @nogc nothrow pure @safe scope
    this(return scope ref typeof(this) rhs) const
    {
        mixin(copyCtorIncRef);
    }

    @nogc nothrow pure @safe scope
    this(return scope const ref typeof(this) rhs) const
    {
        mixin(copyCtorIncRef);
    }

    @nogc nothrow pure @safe scope
    this(return scope immutable ref typeof(this) rhs) const
    {
        mixin(copyCtorIncRef);
    }
    // } Get a const obj

    // { Get an immutable obj
    @nogc nothrow pure @trusted scope
    this(return scope ref typeof(this) rhs) immutable
    {
        // Can't have an immutable ref to a mutable. Create a new RC
        CounterType* support = cast(CounterType*) pureAllocate(2 * CounterType.sizeof);
        *support = 0;
        rc = cast(immutable CounterType*) support;
        addRef();
    }

    @nogc nothrow pure @trusted scope
    this(return scope const ref typeof(this) rhs) immutable
    {
        if (rhs.isShared())
        {
            // By implementation, only immutable RC is shared, so it's ok to inc ref
            rc = cast(immutable) rhs.rc;
            if (isInitialized())
            {
                addRef();
            }
        }
        else
        {
            // Can't have an immutable ref to a mutable. Create a new RC
            CounterType* support = cast(CounterType*) pureAllocate(2 * CounterType.sizeof);
            *support = 0;
            rc = cast(immutable CounterType*) support;
            addRef();
        }
    }

    @nogc nothrow pure @safe scope
    this(return scope immutable ref typeof(this) rhs) immutable
    {
        mixin(copyCtorIncRef);
    }
    // } Get an immutable obj

    @nogc nothrow pure @safe scope
    ref _RefCount opAssign(return scope ref typeof(this) rhs) return
    {
        if (rhs.isInitialized() && rc == rhs.rc)
        {
            return this;
        }
        if (rhs.isInitialized())
        {
            rhs.addRef();
        }
        if (isInitialized())
        {
            delRef();
        }
        () @trusted { rc = rhs.rc; }();
        return this;
    }

    @nogc nothrow pure @safe scope
    private void* addRef() const
    {
        assert(isInitialized(), "[_RefCount.addRef] _RefCount is uninitialized");
        cast(void) rcOp!"+="(1);
        return null;
    }

    @nogc nothrow pure @trusted scope
    private void* delRef() const
    {
        assert(isInitialized(), "[_RefCount.delRef] _RefCount is uninitialized");
        if (rcOp!"=="(1) || (rcOp!"-="(1) == 0))
        {
            return deallocate();
        }
        return null;
    }

    @nogc nothrow pure @system scope
    private void* deallocate() const
    {
        if (isShared())
        {
            return pureDeallocate((cast(CounterType*) rc)[0 .. 2]);
        }
        else
        {
            return pureDeallocate((cast(CounterType*) (rc - 1))[0 .. 2]);
        }
    }

    @nogc nothrow pure @trusted scope
    ~this()
    {
        if (isInitialized())
        {
            delRef();
        }
    }

    pure nothrow @safe @nogc scope
    bool isUnique() const
    {
        return isInitialized() && (!!rcOp!"=="(1));
    }

    pure nothrow @safe @nogc scope
    bool isInitialized() const
    {
        return rc !is null;
    }

    version (CoreUnittest)
    {
        pure nothrow @nogc @trusted scope
        bool isValueEq(uint val) const
        {
            return *getUnsafeValue == val;
        }
    }

    pure nothrow @nogc @system
    CounterType* getUnsafeValue() const
    {
        return cast(CounterType*) rc;
    }
}

version (CoreUnittest)
@safe unittest
{
    () @safe @nogc pure nothrow
    {
        _RefCount a = _RefCount(1);
        assert(a.isUnique);
        const _RefCount ca = const _RefCount(1);
        assert(ca.isUnique);
        immutable _RefCount ia = immutable _RefCount(1);
        assert(ia.isUnique);

        // A const reference will increase the ref count
        const c_cp_a = a;
        assert(a.isValueEq(2));
        const c_cp_ca = ca;
        assert(ca.isValueEq(2));
        const c_cp_ia = ia;
        assert(ia.isValueEq(2));

        // An immutable from a mutable reference will create a copy
        immutable i_cp_a = a;
        assert(a.isValueEq(2));
        assert(i_cp_a.isValueEq(1));
        // An immutable from a const to a mutable reference will create a copy
        immutable i_cp_ca = ca;
        assert(ca.isValueEq(2));
        assert(i_cp_ca.isValueEq(1));
        // An immutable from an immutable reference will increase the ref count
        immutable i_cp_ia = ia;
        assert(ia.isValueEq(3));
        assert(i_cp_ia.isValueEq(3));
        // An immutable from a const to an immutable reference will increase the ref count
        immutable i_cp_c_cp_ia = c_cp_ia;
        assert(c_cp_ia.isValueEq(4));
        assert(i_cp_c_cp_ia.isValueEq(4));
        assert((() @trusted => i_cp_c_cp_ia.getUnsafeValue() == c_cp_ia.getUnsafeValue())());

        _RefCount t;
        assert(!t.isInitialized());
        _RefCount t2 = t;
        assert(!t.isInitialized());
        assert(!t2.isInitialized());
    }();

    assert(allocator.bytesUsed == 0, "_RefCount leakes memory");
}

version (CoreUnittest)
@safe unittest
{
    () @safe @nogc pure nothrow scope
    {
        _RefCount a = _RefCount(1);
        assert(a.isUnique);
        _RefCount a2 = a;
        assert(a.isValueEq(2));
        _RefCount a3 = _RefCount(1);
        a2 = a3;
        assert(a.isValueEq(1));
        assert(a.isUnique);
    }();

    assert(allocator.bytesUsed == 0, "_RefCount leakes memory");
}

version (CoreUnittest)
@safe unittest
{
    struct TestRC
    {
        private _RefCount rc;
        int[] payload;

        @nogc nothrow pure @trusted scope
        this(this Q)(int sz) const
        {
            static if (is(Q == immutable))
            {
                rc = immutable _RefCount(1);
                payload = (cast(immutable int*) pureAllocate(sz * int.sizeof))[0 .. sz];
            }
            else
            {
                rc = _RefCount(1);
                payload = (cast(int*) pureAllocate(sz * int.sizeof))[0 .. sz];
            }
        }

        private enum copyCtorIncRef = q{
            rc = rhs.rc;
            payload = rhs.payload;
        };

        @nogc nothrow pure @safe scope
        this(return scope ref typeof(this) rhs)
        {
            mixin(copyCtorIncRef);
        }

        // { Get a const obj
        @nogc nothrow pure @safe scope
        this(return scope ref typeof(this) rhs) const
        {
            mixin(copyCtorIncRef);
        }

        @nogc nothrow pure @safe scope
        this(return scope const ref typeof(this) rhs) const
        {
            mixin(copyCtorIncRef);
        }

        @nogc nothrow pure @safe scope
        this(return scope immutable ref typeof(this) rhs) const
        {
            mixin(copyCtorIncRef);
        }
        // } Get a const obj

        // { Get an immutable obj
        @nogc nothrow pure @trusted scope
        this(return scope ref typeof(this) rhs) immutable
        {
            // Can't have an immutable ref to a mutable. Create a new RC
            rc = rhs.rc;
            auto sz = rhs.payload.length;
            int[] tmp = (cast(int*) pureAllocate(sz * int.sizeof))[0 .. sz];
            tmp[] = rhs.payload[];
            payload = cast(immutable) tmp;
        }

        @nogc nothrow pure @safe scope
        this(return scope const ref typeof(this) rhs) immutable
        {
            rc = rhs.rc;
            if (rhs.rc.isShared)
            {
                // By implementation, only immutable RC is shared, so it's ok to inc ref
                payload = (() @trusted => cast(immutable) rhs.payload)();
            }
            else
            {
                // Can't have an immutable ref to a mutable. Create a new RC
                auto sz = rhs.payload.length;
                int[] tmp = (() @trusted => (cast(int*) pureAllocate(sz * int.sizeof))[0 .. sz])();
                tmp[] = rhs.payload[];
                payload = (() @trusted => cast(immutable) tmp)();
            }
        }

        @nogc nothrow pure @safe scope
        this(return scope immutable ref typeof(this) rhs) immutable
        {
            mixin(copyCtorIncRef);
        }
        // } Get an immutable obj

        @nogc nothrow pure @safe scope
        ref TestRC opAssign(return ref typeof(this) rhs) return
        {
            if (payload is rhs.payload)
            {
                return this;
            }
            if (rc.isUnique)
            {
                () @trusted { pureDeallocate(payload); }();
            }
            payload = rhs.payload;
            rc = rhs.rc;
            return this;
        }

        @nogc nothrow pure @trusted scope
        ~this()
        {
            if (rc.isUnique())
            {
                pureDeallocate(cast(int[]) payload);
            }
        }
    }

    () @safe @nogc pure nothrow scope
    {
        enum numElem = 10;
        auto t = TestRC(numElem);
        assert(t.rc.isUnique);
        const TestRC ct = const TestRC(numElem);
        assert(ct.rc.isUnique);
        immutable TestRC it = immutable TestRC(numElem);
        assert(it.rc.isUnique);

        // A const reference will increase the ref count
        const c_cp_t = t;
        assert(t.rc.isValueEq(2));
        assert(t.payload is c_cp_t.payload);
        const c_cp_ct = ct;
        assert(ct.rc.isValueEq(2));
        assert(ct.payload is c_cp_ct.payload);
        const c_cp_it = it;
        assert(it.rc.isValueEq(2));
        assert(it.payload is c_cp_it.payload);

        // An immutable from a mutable reference will create a copy
        immutable i_cp_t = immutable TestRC(t);
        assert(t.rc.isValueEq(2));
        assert(i_cp_t.rc.isValueEq(1));
        assert(t.payload !is i_cp_t.payload);
        // An immutable from a const to a mutable reference will create a copy
        immutable i_cp_ct = immutable TestRC(ct);
        assert(ct.rc.isValueEq(2));
        assert(i_cp_ct.rc.isValueEq(1));
        assert(ct.payload !is i_cp_ct.payload);
        // An immutable from an immutable reference will increase the ref count
        immutable i_cp_it = it;
        assert(it.rc.isValueEq(3));
        assert(i_cp_it.rc.isValueEq(3));
        assert(it.payload is i_cp_it.payload);
        // An immutable from a const to an immutable reference will increase the ref count
        immutable i_cp_c_cp_it = c_cp_it;
        assert(c_cp_it.rc.isValueEq(4));
        assert(i_cp_c_cp_it.rc.isValueEq(4));
        assert((() @trusted => i_cp_c_cp_it.rc.getUnsafeValue() == c_cp_it.rc.getUnsafeValue())());
        assert(c_cp_it.payload is i_cp_c_cp_it.payload);

        // Ensure uninitialized structs don't crash
        TestRC t1;
        assert(!t1.rc.isUnique);
        TestRC t2 = t1;
        assert(!t1.rc.isUnique);
        assert(!t2.rc.isUnique);
        TestRC t3 = TestRC(numElem);
        t2 = t3;
    }();

    assert(allocator.bytesUsed == 0, "_RefCount leakes memory");
}

version (CoreUnittest)
{
    private struct StatsAllocator
    {
        version (CoreUnittest) size_t bytesUsed;

        @trusted @nogc nothrow pure
        void* allocate(size_t bytes) shared
        {
            import core.memory : pureMalloc;
            if (!bytes) return null;

            auto p = pureMalloc(bytes);
            if (p is null) return null;
            enum alignment = size_t.sizeof;
            assert(cast(size_t) p % alignment == 0);

            version (CoreUnittest)
            {
                static if (is(typeof(this) == shared))
                {
                    import core.atomic : atomicOp;
                    atomicOp!"+="(bytesUsed, bytes);
                }
                else
                {
                    bytesUsed += bytes;
                }
            }
            return p;
        }

        @system @nogc nothrow pure
        bool deallocate(void[] b) shared
        {
            import core.memory : pureFree;
            assert(b !is null);

            version (CoreUnittest)
            {
                static if (is(typeof(this) == shared))
                {
                    import core.atomic : atomicOp;
                    assert(atomicOp!">="(bytesUsed, b.length));
                    atomicOp!"-="(bytesUsed, b.length);
                }
                else
                {
                    assert(bytesUsed >= b.length);
                    bytesUsed -= b.length;
                }
            }
            pureFree(b.ptr);
            return true;
        }
    }

    private shared StatsAllocator allocator;

    private @nogc nothrow pure @trusted
    void* pureAllocate(size_t n)
    {
        return (cast(void* function(size_t) @nogc nothrow pure)(&_allocate))(n);
    }

    private @nogc nothrow @safe
    void* _allocate(size_t n)
    {
        return allocator.allocate(n);
    }

    private @nogc nothrow pure
    void* pureDeallocate(T)(T[] b)
    {
        return (cast(void* function(T[]) @nogc nothrow pure)(&_deallocate!(T)))(b);
    }

    private @nogc nothrow
    void* _deallocate(T)(T[] b)
    {
        allocator.deallocate(b);
        return null;
    }
}
else
{
    import core.memory : pureMalloc, pureFree;

    private alias pureAllocate = pureMalloc;

    @nogc nothrow pure
    private static void* pureDeallocate(T)(T[] b)
    {
        pureFree(b.ptr);
        return null;
    }
}
