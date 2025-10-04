# AI development guide

This is a guide for how AIs should develop code for Andy.

## About me

I'm Andy. Call me that.
- I prefer SQLite and PostgreSQL for databases. I also like object stores (such as S3), queues, and load balancers, but generally don't use any other cloud primitives.
- I don't like microservice-oriented architectures, preferring a more monolithic approach.

## Development style

### Go application structure

Generally, I build web applications and libraries/modules.

These are the packages typically present in applications (some may be missing, which typically means I don't need them in the project).

- `main`: contains the main entry point of the application (in directory `cmd/app`)
- `model`: contains the domain model used throughout the other packages
- `sql`/`sqlite`/`postgres`: contains SQL database-related logic as well as database migrations (under subdirectory `migrations/`). The database used is either SQLite or PostgreSQL.
- `sqltest`/`sqlitetest`/`postgrestest`: package used in testing, for setting up and tearing down test databases
- `s3`: logic for interacting with Amazon S3 or compatible object stores
- `s3test`: package used in testing, for setting up and tearing down test S3 buckets

### Code style

#### Tests

I write tests for most functions and methods. I almost always use subtests with a good description of whats is going on and what the expected result is.

It makes sense to use mocks when the important part of a test isn't the dependency, but it plays a smaller role. But for example, when testing database methods, a real underlying database should be used.

Since tests are shuffled, don't rely on test order, even for subtests.

Every time the `postgrestest.NewDatabase(t)`/`sqlitetest.NewDatabase(t)` test helpers are called, the database is in a clean state (no leftovers from other tests etc.).

I always want a README.md and a justfile when you create a project.  Use a lowercase 'j' in justfile.  Don't add fmt or lint targets in justfiles.  

Always add a build target and a 'run' target that will build and run the app, passing as command line switches anything I pass in on the 'just' line.  The run target relies on the build target and then passes all the input to the build artifact.  

I prefer'double-dash' command flags, not single flags, but remember not all commands have them, so double check the flag exists.

I prefer everying compiled into a single binary, not shelling out and calling commands from the prompt.

#### Miscellaneous

- Variable naming:
  - `req` for requests, `res` for responses
- Prefer lowercase SQL queries

### Testing, linting, evals

You can access the database by using `sqlite3` in the shell.

### Version control

When writing commit messages, surround identifier names (variable names, type names, etc.) in backticks.

### Bugs

If you think you've found a bug during testing, ask me what to do, instead of trying to work around the bug in tests.

### Documentation

You can generally look up documentation for a Go module using `go doc` with the module name. For example, `go doc net/http` for something in the standard library, or `go doc maragu.dev/gai` for a third-party module. You can also look up more specific documentation for an identifier with something like `go doc maragu.dev/gai.ChatCompleter`, for the `ChatCompleter` interface.
