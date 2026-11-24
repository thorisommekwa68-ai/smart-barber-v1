# Development Guide

## Prerequisites

- Node.js 20 or newer
- npm 10 or newer
- Git

## Install

```bash
npm install
```

## Working independently

Start only the application being changed:

```bash
npm run dev:admin
npm run dev:merchant
npm run dev:customer
```

The applications are npm workspaces. They share dependencies and packages installed at the root while remaining separately runnable.

## Application layout

Place route-level screens in `pages/`, reusable interface pieces in `components/`, page shells in `layouts/`, backend calls in `services/`, styles in `styles/`, media in `assets/`, and common local functions in `utils/`.

Do not import one app's source into another app. Use a package under `packages/` when behavior or UI is genuinely shared.

## Environment configuration

Copy `.env.example` only as needed for local configuration:

```bash
cp .env.example .env.local
```

Leave values blank until services have been created. Never commit `.env.local` or put privileged keys in Vite variables.

## Builds

```bash
npm run build:admin
npm run build:merchant
npm run build:customer
npm run build
```

Run the smallest relevant build before adding more work.
