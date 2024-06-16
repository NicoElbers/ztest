# Testing capabilities

## Base features

- Simple tests (already a language feature)
- Diverse set of asserts
- Parameterized tests
  - Report failed cases
  - Minimize cases
- Auto fuzz support
  - Create a build setting that will continuously generate cases
  - Provide a custom rng module so we can extract the seed
    - Depends on ziglang/zig#17609
- Simple integration around skipping tests
  - Just a thin wrapper
- Utilities to create (and get the path to) unique temp directories

## Advanced features

- Advanced test reporting
  - Possibly require change in test runner server to communicate better
  - Find issues relating to this
- Auto generate edge cases (Analyze AST?)
- Mocks (But have to figure out how to do that, fuck with vtables?)
- Set a timeout on tests
  - depends on ziglang/zig#19821

**Do more research about testing thingies**

## Current problems

### Doing testing across many different types

I want to test my equality functions across many different types. Preferably, across all permutations of primitive types and some more complex types (think hashmap, arraylist etc.) as well. The more complex types I'll almost certainly want to do manually, I don't think there's a good way to iterate over them. But I should have something for primitives.

#### Thinking

The ultimate best result is to dynamically create more tests (as in literally more things the test runner has to run) so that it's trivial to see which case (which type) exactly failed. I'll have to ask to be certain, but I don't think that's possible at this time. Actually I think it is never mind, if I create a `fn someGenericTest(comptime T:type) type {}` and put tests in that it creates more tests!!

We have the following types:

```
    Type: void,
    Void: void,
    Bool: void,
    NoReturn: void,
    Int: Int,
    Float: Float,
    Pointer: Pointer,
    Array: Array,
    Struct: Struct,
    ComptimeFloat: void,
    ComptimeInt: void,
    Undefined: void,
    Null: void,
    Optional: Optional,
    ErrorUnion: ErrorUnion,
    ErrorSet: ErrorSet,
    Enum: Enum,
    Union: Union,
    Fn: Fn,
    Opaque: Opaque,
    Frame: Frame,
    AnyFrame: AnyFrame,
    Vector: Vector,
    EnumLiteral: void,
```

I need to first probably eliminate a bunch which will obviously not work:

```
    Type: void, // I don't know if this is a good idea
    Bool: void,
    Int: Int,
    Float: Float,
    Pointer: Pointer, // Make sure to check all sub types
    Array: Array,
    Struct: Struct,
    ComptimeFloat: void,
    ComptimeInt: void,
    Null: void, // This can only be one value, probably best to not do
    Optional: Optional,
    ErrorUnion: ErrorUnion,
    ErrorSet: ErrorSet,
    Enum: Enum,
    Union: Union,
    Opaque: Opaque, // Can i even create a valueable arbitrary opaque; Maybe better to have opaqueOf()
    Vector: Vector,
    EnumLiteral: void,
```

Actually, it might be a lot better to whitelist different types.

Concrete current problems:

1. I want to input many different types to see if they will compile with a function.

2. I want to input many concrete different types to see if they fulfil a specific condition.

##### For the first problem

- Create a simple function that takes in a list of types and a function with one `type` argument and one `type` return. Aka generics in Zig.
- It will call the function, and discard the value, just asserting that it compiles

##### For the second problem

- I need to create some sort of 'Generator' struct that can configure types to values of that type.
- Then I have another function that takes in one of these generators and tries every input

##### PARAMETERIZED TESTS!!!

I'm looking for parameterized tests!

#### Making parameterized tests

Ok, the syntax I want for generic tests is as follows:

```zig
// No try because we're creating different tests for this
// will have to see how that pans out
parameterizedTest(someFunc, .{
  .{u32, @as(u32, 123)},
  .{u8, @as(u8, 4534)}
});
```

Then the parameterized test impl will look something like this:

```zig
pub fn parameterizedTest(func: anytype, argList: anytype) void {
    // Maybe skip this verification for the initial version
    assertThat(func).isAFunction();
    assertThat(argList).isAListOfTuples();

    const funcParams = std.meta.funcParams(func);

    // Maybe skip this verification for the initial version
    for (arglist.field) |argTuple| {
      assertThat(argTuple).isTuple();
      assertThat(argTuple.len).isEqualTo(funcParams.len);
      for (argTuple, 0..) |arg, idx| {
        // This might be a problem for generics, if so maybe skip this
        assertThat(arg.type).isEqualTo(funcParams[idx]);
      }
    }

    for (argList.field) |argTuple| {
      runParamTest(func, argTuple);
    }
}

fn runParamTest(func: anytype, args: anytype) void {
    // Try to put this in a test block so that different tests get generated for
    // each input
    test {
        try @Call(.auto, func, argTuple);
    }
}
```
