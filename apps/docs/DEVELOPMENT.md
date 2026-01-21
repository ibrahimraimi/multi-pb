# Development Guide

This guide explains the project structure and how to contribute to Multi-PB.

## Project Structure

Multi-PB uses a monorepo-style layout to separate core logic from applications:

```
├── apps/
│   ├── dashboard/   # SvelteKit Dashboard
│   ├── docs/        # Documentation (Markdown)
│   └── web/         # Landing Page (Future)
├── core/
│   ├── api/         # Node.js API Server
│   ├── cli/         # Shell Management Scripts
│   └── entrypoint.sh # Container Entrypoint
├── tests/
│   ├── api/         # Integration tests for the API
│   └── shell/       # Integration tests for CLI/Install
├── Dockerfile       # Main container build
└── install.sh       # Installer script
```

## Local Development

### API Server

The API server is written in Node.js and located in `core/api/server.js`.

To run locally for testing (without the full container environment), you may need to mock some of the expected paths (e.g., `/var/multipb/data`).

### Dashboard

The dashboard is a SvelteKit application located in `apps/dashboard/`.

```bash
cd apps/dashboard
npm install
npm run dev
```

## Testing

We use a combination of shell scripts and Node.js tests to verify functionality.

### Running API Tests

```bash
cd tests/api
npm install
npm test
```

### Running Shell Tests

```bash
# Requires Docker
./tests/shell/test-cli.sh
```

## Contribution Guidelines

1.  **Branching**: Use descriptive branch names (e.g., `feat/xxx` or `fix/xxx`).
2.  **Linting**: Ensure your code follows established patterns.
3.  **Testing**: Always add or update tests for new features.
