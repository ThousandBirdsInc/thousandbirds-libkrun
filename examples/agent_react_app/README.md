# libkrun Agent React Demo

This is a small Vite/React workspace intended to be mounted into a Debian
OS-mode guest for AI-agent experiments.

Inside the guest:

```sh
cd /workspace/react-app
npm install
npm run build
chromium --headless --no-sandbox --disable-gpu --dump-dom file://$PWD/index.html
```

The app is source-only by default. Dependencies are installed inside the guest
so the host checkout stays clean.
