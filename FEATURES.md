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
